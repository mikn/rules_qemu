"""Module extension for QEMU toolchain registration."""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("//qemu:repositories.bzl", "ovmf_repo", "qemu_toolchains_repo", "swtpm_host_repo")
load("//qemu/private:versions.bzl", "OVMF_VERSIONS", "SWTPM_VERSIONS")

_toolchain_tag = tag_class(
    attrs = {
        "qemu_version": attr.string(default = "9.2.0", doc = "QEMU version (for future hermetic downloads)"),
        "ovmf_version": attr.string(default = "2025.02-8", doc = "OVMF firmware version"),
        "ovmf_url": attr.string(doc = "Custom OVMF deb URL (overrides version lookup)"),
        "ovmf_sha256": attr.string(doc = "Custom OVMF deb sha256 (required with ovmf_url)"),
        "swtpm_version": attr.string(default = "0.10.1", doc = "swtpm version to build from source"),
        "swtpm_from_source": attr.bool(default = True, doc = "Build swtpm from source (False = host fallback)"),
    },
    doc = "Configure the QEMU toolchain.",
)

def _qemu_impl(module_ctx):
    registrations = []
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            registrations.append(toolchain)

    if not registrations:
        return

    # Use the first (root module) registration
    reg = registrations[0]

    # Set up OVMF repository
    if reg.ovmf_url:
        ovmf_url = reg.ovmf_url
        ovmf_sha256 = reg.ovmf_sha256
        ovmf_code_path = "usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
        ovmf_vars_path = "usr/share/OVMF/OVMF_VARS_4M.fd"
    else:
        version_info = OVMF_VERSIONS.get(reg.ovmf_version)
        if not version_info:
            fail("Unknown OVMF version: {}. Available: {}".format(
                reg.ovmf_version,
                ", ".join(OVMF_VERSIONS.keys()),
            ))
        ovmf_url = version_info["url"]
        ovmf_sha256 = version_info["sha256"]
        ovmf_code_path = version_info["code_path"]
        ovmf_vars_path = version_info["vars_path"]

    ovmf_repo(
        name = "qemu_ovmf",
        url = ovmf_url,
        sha256 = ovmf_sha256,
        code_path = ovmf_code_path,
        vars_path = ovmf_vars_path,
    )

    # Set up swtpm
    if reg.swtpm_from_source:
        _setup_swtpm_from_source(reg.swtpm_version)
        swtpm_label = "@qemu_swtpm_src//:swtpm"
        swtpm_setup_label = "@qemu_swtpm_src//:swtpm_setup"
    else:
        swtpm_host_repo(name = "qemu_swtpm")
        swtpm_label = "@qemu_swtpm//:swtpm"
        swtpm_setup_label = "@qemu_swtpm//:swtpm_setup"

    # Create the toolchains repository with wiring.
    # Uses toolchain_info from toolchain_utils (ARM pattern) for individual
    # executables, and the composite qemu_toolchain for OVMF + QEMU binaries.
    build_content = """\
load("@rules_qemu//qemu:toolchain.bzl", "qemu_toolchain")
load("@toolchain_utils//toolchain/info:defs.bzl", "toolchain_info")

# --- QEMU composite toolchain (OVMF + qemu-system + qemu-img) ---

qemu_toolchain(
    name = "qemu_toolchain_x86_64",
    arch = "x86_64",
    ovmf_code = "@qemu_ovmf//:ovmf_code",
    ovmf_vars = "@qemu_ovmf//:ovmf_vars",
    visibility = ["//visibility:public"],
)

toolchain(
    name = "qemu_x86_64_toolchain",
    toolchain = ":qemu_toolchain_x86_64",
    toolchain_type = "@rules_qemu//qemu:toolchain_type",
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    visibility = ["//visibility:public"],
)

# --- swtpm toolchains (ARM toolchain_info pattern) ---

toolchain_info(
    name = "swtpm_info",
    target = "{swtpm}",
    variable = "SWTPM",
)

toolchain(
    name = "swtpm_toolchain",
    toolchain = ":swtpm_info",
    toolchain_type = "@rules_qemu//qemu:swtpm_type",
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    visibility = ["//visibility:public"],
)

toolchain_info(
    name = "swtpm_setup_info",
    target = "{swtpm_setup}",
    variable = "SWTPM_SETUP",
)

toolchain(
    name = "swtpm_setup_toolchain",
    toolchain = ":swtpm_setup_info",
    toolchain_type = "@rules_qemu//qemu:swtpm_setup_type",
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    visibility = ["//visibility:public"],
)
""".format(
        swtpm = swtpm_label,
        swtpm_setup = swtpm_setup_label,
    )
    qemu_toolchains_repo(
        name = "qemu_toolchains",
        build_file_content = build_content,
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
    tag_classes = {
        "toolchain": _toolchain_tag,
    },
)
