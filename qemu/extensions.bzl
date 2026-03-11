"""Module extension for QEMU toolchain registration."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//qemu:repositories.bzl", "ovmf_repo", "qemu_host_repo", "qemu_toolchains_repo", "swtpm_host_repo")
load("//qemu/private:versions.bzl", "OVMF_VERSIONS", "SWTPM_VERSIONS")

_toolchain_tag = tag_class(
    attrs = {
        "qemu_version": attr.string(default = "9.2.0", doc = "QEMU version (for future hermetic downloads)"),
        "ovmf_version": attr.string(default = "2025.02-8", doc = "OVMF/AAVMF firmware version"),
        "swtpm_version": attr.string(default = "0.10.1", doc = "swtpm version to build from source"),
        "swtpm_from_source": attr.bool(
            default = True,
            doc = "Build swtpm from source (Linux only). False = use host swtpm on all platforms.",
        ),
    },
    doc = "Configure the QEMU toolchain.",
)

# Each entry describes one toolchain registration.
# Fields: exec_os, exec_cpu, guest_arch, accel, machine_type
# native=True means exec and guest arch align (fast KVM/HVF).
# native=False means cross-arch TCG emulation (slow, ~10-50x penalty).
#
# Native toolchains are listed first so Bazel prefers them over TCG ones
# when the exec platform matches both.
_TOOLCHAIN_MATRIX = [
    # --- Native (KVM/HVF — fast) ---
    struct(exec_os = "linux",  exec_cpu = "x86_64",  guest_arch = "x86_64",  accel = "kvm", machine_type = "q35",  native = True),
    struct(exec_os = "linux",  exec_cpu = "aarch64", guest_arch = "aarch64", accel = "kvm", machine_type = "virt", native = True),
    struct(exec_os = "macos",  exec_cpu = "aarch64", guest_arch = "aarch64", accel = "hvf", machine_type = "virt", native = True),
    # --- Cross-architecture (TCG — slow) ---
    struct(exec_os = "macos",  exec_cpu = "aarch64", guest_arch = "x86_64",  accel = "tcg", machine_type = "q35",  native = False),
    struct(exec_os = "linux",  exec_cpu = "x86_64",  guest_arch = "aarch64", accel = "tcg", machine_type = "virt", native = False),
    struct(exec_os = "linux",  exec_cpu = "aarch64", guest_arch = "x86_64",  accel = "tcg", machine_type = "q35",  native = False),
]

# Maps our simplified os/cpu strings to @platforms// constraint labels.
_OS_CONSTRAINTS = {
    "linux": "@platforms//os:linux",
    "macos": "@platforms//os:macos",
}

# Note: @platforms//cpu:aarch64 and @platforms//cpu:arm64 are the SAME constraint
# value in the platforms repo (arm64 is an alias for aarch64). We use aarch64
# consistently throughout.
_CPU_CONSTRAINTS = {
    "x86_64":  "@platforms//cpu:x86_64",
    "aarch64": "@platforms//cpu:aarch64",
}

def _toolchain_name(entry):
    """Generates a unique toolchain identifier from a matrix entry."""
    return "qemu_{exec_os}_{exec_cpu}_guest_{guest_arch}_{accel}".format(
        exec_os = entry.exec_os,
        exec_cpu = entry.exec_cpu,
        guest_arch = entry.guest_arch,
        accel = entry.accel,
    )

def _ovmf_repo_name(guest_arch):
    return "qemu_ovmf_{}".format(guest_arch)

def _qemu_impl(module_ctx):
    registrations = []
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            registrations.append(toolchain)

    # Use the first (root module) registration, or fall back to tag-class defaults
    # when no qemu.toolchain() tag is provided. This avoids breaking use_repo
    # declarations even when no explicit configuration is present.
    if registrations:
        reg = registrations[0]
    else:
        # Mirror the defaults from _toolchain_tag so the extension behaves as
        # if qemu.toolchain() was called with no arguments.
        reg = struct(
            qemu_version = "9.2.0",
            ovmf_version = "2025.02-8",
            swtpm_version = "0.10.1",
            swtpm_from_source = True,
        )

    # --- Resolve OVMF version info ---
    version_info = OVMF_VERSIONS.get(reg.ovmf_version)
    if not version_info:
        fail("Unknown OVMF version: {}. Available: {}".format(
            reg.ovmf_version,
            ", ".join(OVMF_VERSIONS.keys()),
        ))

    # Create per-arch firmware repos (x86_64 → OVMF, aarch64 → AAVMF)
    for arch in ["x86_64", "aarch64"]:
        arch_info = version_info.get(arch)
        if not arch_info:
            fail("No firmware info for arch '{}' in OVMF version '{}'".format(arch, reg.ovmf_version))
        ovmf_repo(
            name = _ovmf_repo_name(arch),
            url = arch_info["url"],
            sha256 = arch_info["sha256"],
            code_path = arch_info["code_path"],
            vars_path = arch_info["vars_path"],
        )

    # --- Resolve swtpm ---
    # swtpm from source: only supported on Linux (uses configure_make with Linux toolchains).
    # On macOS, skip source downloads entirely and always use the host swtpm regardless
    # of the swtpm_from_source setting — building from source is not supported there.
    host_os = module_ctx.os.name.lower()
    is_macos = "mac" in host_os or "darwin" in host_os
    if reg.swtpm_from_source and not is_macos:
        _setup_swtpm_from_source(reg.swtpm_version)
        swtpm_src_label = "@qemu_swtpm_src//:swtpm"
        swtpm_setup_src_label = "@qemu_swtpm_src//:swtpm_setup"
    else:
        swtpm_src_label = None
        swtpm_setup_src_label = None

    # Host swtpm repo (used on macOS and when swtpm_from_source=False)
    swtpm_host_repo(name = "qemu_swtpm_host")
    swtpm_host_label = "@qemu_swtpm_host//:swtpm"
    swtpm_setup_host_label = "@qemu_swtpm_host//:swtpm_setup"

    # --- QEMU binaries ---
    # Currently host-only on all platforms. A future version may add hermetic downloads.
    qemu_host_repo(name = "qemu_system_host")

    # --- Generate toolchains repository BUILD content ---
    # Accumulate all toolchain declarations as strings, then write them in one repo.
    build_lines = [
        'load("@rules_qemu//qemu:toolchain.bzl", "qemu_toolchain")',
        'load("@toolchain_utils//toolchain/info:defs.bzl", "toolchain_info")',
        "",
        "# This file is generated by qemu/extensions.bzl — do not edit manually.",
        "",
    ]

    # Track which swtpm toolchains have already been declared (one per exec platform)
    swtpm_declared = {}

    for entry in _TOOLCHAIN_MATRIX:
        tc_name = _toolchain_name(entry)
        ovmf_repo_name = _ovmf_repo_name(entry.guest_arch)
        exec_os_constraint = _OS_CONSTRAINTS[entry.exec_os]
        exec_cpu_constraint = _CPU_CONSTRAINTS[entry.exec_cpu]
        guest_cpu_constraint = _CPU_CONSTRAINTS[entry.guest_arch]

        # Choose QEMU binary label based on guest arch (host provides the binary)
        qemu_system_label = "@qemu_system_host//:qemu-system-{}".format(entry.guest_arch)
        qemu_img_label = "@qemu_system_host//:qemu-img"

        # qemu_toolchain rule (inner, provides QemuToolchainInfo)
        build_lines += [
            "# --- {} ---".format(tc_name),
            'qemu_toolchain(',
            '    name = "{}",'.format(tc_name),
            '    arch = "{}",'.format(entry.guest_arch),
            '    accel = "{}",'.format(entry.accel),
            '    machine_type = "{}",'.format(entry.machine_type),
            '    ovmf_code = "@{}//:ovmf_code",'.format(ovmf_repo_name),
            '    ovmf_vars = "@{}//:ovmf_vars",'.format(ovmf_repo_name),
            '    qemu_system = "{}",'.format(qemu_system_label),
            '    qemu_img = "{}",'.format(qemu_img_label),
            '    visibility = ["//visibility:public"],',
            ")",
            "",
            "toolchain(",
            '    name = "{}_toolchain",'.format(tc_name),
            '    toolchain = ":{}", '.format(tc_name),
            '    toolchain_type = "@rules_qemu//qemu:toolchain_type",',
            "    exec_compatible_with = [",
            '        "{}",'.format(exec_os_constraint),
            '        "{}",'.format(exec_cpu_constraint),
            "    ],",
            # Only constrain by CPU architecture, not OS — QEMU can emulate any guest OS.
            "    target_compatible_with = [",
            '        "{}",'.format(guest_cpu_constraint),
            "    ],",
            '    visibility = ["//visibility:public"],',
            ")",
            "",
        ]

        # swtpm toolchains: one per exec platform (TPM is arch-agnostic).
        # Key by (exec_os, exec_cpu) so we only declare each exec platform once.
        swtpm_key = (entry.exec_os, entry.exec_cpu)
        if swtpm_key not in swtpm_declared:
            swtpm_declared[swtpm_key] = True
            swtpm_tc_base = "swtpm_{}_{}".format(entry.exec_os, entry.exec_cpu)

            # Choose swtpm source: from-source for Linux, host fallback for macOS
            if entry.exec_os == "linux" and swtpm_src_label != None:
                swtpm_label = swtpm_src_label
                swtpm_setup_label = swtpm_setup_src_label
            else:
                swtpm_label = swtpm_host_label
                swtpm_setup_label = swtpm_setup_host_label

            build_lines += [
                "# --- swtpm for exec {}/{} ---".format(entry.exec_os, entry.exec_cpu),
                "toolchain_info(",
                '    name = "{}_swtpm_info",'.format(swtpm_tc_base),
                '    target = "{}",'.format(swtpm_label),
                '    variable = "SWTPM",',
                ")",
                "",
                "toolchain(",
                '    name = "{}_swtpm_toolchain",'.format(swtpm_tc_base),
                '    toolchain = ":{}_swtpm_info",'.format(swtpm_tc_base),
                '    toolchain_type = "@rules_qemu//qemu:swtpm_type",',
                "    exec_compatible_with = [",
                '        "{}",'.format(exec_os_constraint),
                '        "{}",'.format(exec_cpu_constraint),
                "    ],",
                '    visibility = ["//visibility:public"],',
                ")",
                "",
                "toolchain_info(",
                '    name = "{}_swtpm_setup_info",'.format(swtpm_tc_base),
                '    target = "{}",'.format(swtpm_setup_label),
                '    variable = "SWTPM_SETUP",',
                ")",
                "",
                "toolchain(",
                '    name = "{}_swtpm_setup_toolchain",'.format(swtpm_tc_base),
                '    toolchain = ":{}_swtpm_setup_info",'.format(swtpm_tc_base),
                '    toolchain_type = "@rules_qemu//qemu:swtpm_setup_type",',
                "    exec_compatible_with = [",
                '        "{}",'.format(exec_os_constraint),
                '        "{}",'.format(exec_cpu_constraint),
                "    ],",
                '    visibility = ["//visibility:public"],',
                ")",
                "",
            ]

    qemu_toolchains_repo(
        name = "qemu_toolchains",
        build_file_content = "\n".join(build_lines),
    )

def _setup_swtpm_from_source(swtpm_version):
    """Download swtpm and all dependencies for building from source."""
    version_info = SWTPM_VERSIONS.get(swtpm_version)
    if not version_info:
        fail("Unknown swtpm version: {}. Available: {}".format(
            swtpm_version,
            ", ".join(SWTPM_VERSIONS.keys()),
        ))

    # libtpms — TPM emulation library
    libtpms = version_info["libtpms"]
    http_archive(
        name = "qemu_libtpms",
        url = libtpms["url"],
        sha256 = libtpms["sha256"],
        strip_prefix = libtpms["strip_prefix"],
        build_file = "@rules_qemu//qemu/private:libtpms.BUILD.bazel",
    )

    # libtasn1 — ASN.1 parsing for TPM certificates
    libtasn1 = version_info["libtasn1"]
    http_archive(
        name = "qemu_libtasn1",
        url = libtasn1["url"],
        sha256 = libtasn1["sha256"],
        strip_prefix = libtasn1["strip_prefix"],
        build_file = "@rules_qemu//qemu/private:libtasn1.BUILD.bazel",
    )

    # gmp — GNU Multiple Precision Arithmetic
    gmp = version_info["gmp"]
    http_archive(
        name = "qemu_gmp",
        url = gmp["url"],
        sha256 = gmp["sha256"],
        strip_prefix = gmp["strip_prefix"],
        build_file = "@rules_qemu//qemu/private:gmp.BUILD.bazel",
    )

    # json-glib — JSON library for GLib
    json_glib = version_info["json_glib"]
    http_archive(
        name = "qemu_json_glib",
        url = json_glib["url"],
        sha256 = json_glib["sha256"],
        strip_prefix = json_glib["strip_prefix"],
        build_file = "@rules_qemu//qemu/private:json_glib.BUILD.bazel",
        # Patch meson.build to bypass pkg-config for BCR-provided glib/gio.
        # rules_foreign_cc already sets CFLAGS/LDFLAGS with the correct -I/-L
        # paths for BCR deps. We just need explicit -l flags for linking.
        patch_cmds = [
            # Bypass pkg-config for BCR-provided gio/glib. Use -l:name.a to force
            # static linking. Include all transitive deps of the static archives.
            "sed -i \"s|gio_dep = dependency('gio-2.0', version: glib_req_version)|gio_dep = declare_dependency(link_args: ['-l:libgio.a', '-l:libgobject.a', '-l:libglib.a', '-l:libgmodule.a', '-l:libxdgmime.a', '-l:liblibffi.a', '-l:libpcre2.a', '-l:libz.a'])|\" meson.build",
        ],
    )

    # swtpm — the TPM emulator itself
    swtpm = version_info["swtpm"]
    http_archive(
        name = "qemu_swtpm_src",
        url = swtpm["url"],
        sha256 = swtpm["sha256"],
        strip_prefix = swtpm["strip_prefix"],
        build_file = "@rules_qemu//qemu/private:swtpm.BUILD.bazel",
        # Create stub .pc files for BCR-provided deps (glib, openssl).
        # swtpm's configure.ac calls pkg-config directly, but BCR deps don't
        # provide .pc files. These stubs map pkg-config module names to the
        # actual BCR library names. The cc_static_only rule in the BUILD
        # overlay ensures only .a files are staged, so no -l: prefix needed.
        # Foreign_cc-built deps (libtpms, json-glib, libtasn1, gmp) have
        # their .pc files auto-generated by rules_foreign_cc.
        patch_cmds = [
            # Remove -Werror from configure.ac — swtpm appends it to CFLAGS after
            # rules_foreign_cc sets them, overriding our -Wno-error copts.
            "sed -i 's/-Werror//g' configure.ac",
            "mkdir -p bcr_pkgconfig",
            """cat > bcr_pkgconfig/glib-2.0.pc << 'PCEOF'
Name: glib-2.0
Description: BCR-provided stub
Version: 2.82.2
Cflags:
Libs: -l:libglib.a -l:libpcre2.a
PCEOF""",
            """cat > bcr_pkgconfig/gio-2.0.pc << 'PCEOF'
Name: gio-2.0
Description: BCR-provided stub
Version: 2.82.2
Requires: gobject-2.0 glib-2.0
Cflags:
Libs: -l:libgio.a -l:libgmodule.a -l:libxdgmime.a -l:libz.a
PCEOF""",
            """cat > bcr_pkgconfig/gobject-2.0.pc << 'PCEOF'
Name: gobject-2.0
Description: BCR-provided stub
Version: 2.82.2
Requires: glib-2.0
Cflags:
Libs: -l:libgobject.a -l:liblibffi.a
PCEOF""",
            """cat > bcr_pkgconfig/libcrypto.pc << 'PCEOF'
Name: libcrypto
Description: BCR-provided stub
Version: 3.5.0
Cflags:
Libs: -l:libcrypto.a
PCEOF""",
        ],
    )

qemu = module_extension(
    implementation = _qemu_impl,
    os_dependent = True,
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
