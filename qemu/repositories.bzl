"""Repository rules for downloading QEMU-related binaries."""

def _extract_deb(rctx, deb_path, extract_dir):
    """Extracts a .deb file into extract_dir."""
    rctx.execute(["mkdir", "-p", extract_dir])
    result = rctx.execute(
        ["ar", "x", str(deb_path)],
        working_directory = extract_dir,
        quiet = False,
    )
    if result.return_code != 0:
        fail("ar x failed for {}: {}".format(deb_path, result.stderr))

    # Find and extract data.tar.*
    result = rctx.execute(
        ["sh", "-c", "ls data.tar.*"],
        working_directory = extract_dir,
    )
    data_tar = result.stdout.strip()
    result = rctx.execute(
        ["tar", "xf", data_tar],
        working_directory = extract_dir,
        quiet = False,
    )
    if result.return_code != 0:
        fail("tar xf failed for {}: {}".format(data_tar, result.stderr))

def _ovmf_repo_impl(rctx):
    """Downloads and extracts OVMF firmware from a Debian package."""
    rctx.download(
        url = rctx.attr.url,
        output = "ovmf.deb",
        sha256 = rctx.attr.sha256,
    )

    _extract_deb(rctx, "ovmf.deb", ".")

    # Create BUILD file exposing the firmware files
    rctx.file("BUILD.bazel", content = """
exports_files([
    "{code_path}",
    "{vars_path}",
])

filegroup(
    name = "ovmf_code",
    srcs = ["{code_path}"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ovmf_vars",
    srcs = ["{vars_path}"],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "ovmf_files",
    srcs = [
        "{code_path}",
        "{vars_path}",
    ],
    visibility = ["//visibility:public"],
)
""".format(
        code_path = rctx.attr.code_path,
        vars_path = rctx.attr.vars_path,
    ))

    # Clean up deb artifacts
    rctx.delete("ovmf.deb")
    rctx.execute(["sh", "-c", "rm -f control.tar.* data.tar.* debian-binary"])

ovmf_repo = repository_rule(
    implementation = _ovmf_repo_impl,
    attrs = {
        "url": attr.string(mandatory = True, doc = "URL of the OVMF deb package"),
        "sha256": attr.string(mandatory = True, doc = "SHA256 hash of the deb package"),
        "code_path": attr.string(
            default = "usr/share/OVMF/OVMF_CODE_4M.secboot.fd",
            doc = "Path to OVMF_CODE within the deb",
        ),
        "vars_path": attr.string(
            default = "usr/share/OVMF/OVMF_VARS_4M.fd",
            doc = "Path to OVMF_VARS within the deb",
        ),
    },
    doc = "Downloads OVMF firmware from a Debian package.",
)

def _swtpm_deb_repo_impl(rctx):
    """Downloads and extracts swtpm + dependencies from Debian packages."""
    debs = json.decode(rctx.attr.debs_json)

    # Download and extract all debs
    for deb in debs:
        deb_file = "_debs/{}.deb".format(deb["name"])
        rctx.download(
            url = deb["url"],
            output = deb_file,
            sha256 = deb["sha256"],
        )
        _extract_deb(rctx, deb_file, "_debs/{}".format(deb["name"]))

    # Collect binaries and shared libraries into a flat layout
    rctx.execute(["mkdir", "-p", "bin", "lib"])

    # Collect binaries from usr/bin/ and usr/sbin/
    rctx.execute([
        "sh", "-c",
        "find _debs/*/usr/bin _debs/*/usr/sbin -type f 2>/dev/null | " +
        "while read f; do cp \"$f\" bin/; done",
    ])

    # Collect shared libraries from usr/lib/
    rctx.execute([
        "sh", "-c",
        "find _debs/*/usr/lib -name '*.so*' -type f -o -name '*.so*' -type l 2>/dev/null | " +
        "while read f; do cp -P \"$f\" lib/; done",
    ])

    # Make binaries executable
    rctx.execute(["chmod", "+x", "bin/swtpm", "bin/swtpm_setup"])

    # Create wrapper scripts that set LD_LIBRARY_PATH
    rctx.file("swtpm.sh", content = """\
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "${DIR}/bin/swtpm" "$@"
""", executable = True)

    rctx.file("swtpm_setup.sh", content = """\
#!/bin/bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="${DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "${DIR}/bin/swtpm_setup" "$@"
""", executable = True)

    # Create BUILD file with sh_binary targets
    rctx.file("BUILD.bazel", content = """\
filegroup(
    name = "libs",
    srcs = glob(["lib/*.so*"]),
)

sh_binary(
    name = "swtpm",
    srcs = ["swtpm.sh"],
    data = [
        "bin/swtpm",
        ":libs",
    ],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "swtpm_setup",
    srcs = ["swtpm_setup.sh"],
    data = [
        "bin/swtpm_setup",
        ":libs",
    ],
    visibility = ["//visibility:public"],
)
""")

    # Clean up temp deb extraction directory
    rctx.delete("_debs")

swtpm_deb_repo = repository_rule(
    implementation = _swtpm_deb_repo_impl,
    attrs = {
        "debs_json": attr.string(
            mandatory = True,
            doc = "JSON-encoded list of {name, url, sha256} dicts for swtpm deb packages",
        ),
    },
    doc = "Downloads swtpm and dependencies from Debian packages.",
)

def _swtpm_host_repo_impl(rctx):
    """Creates a repository that wraps host swtpm binaries."""
    swtpm = rctx.which("swtpm")
    swtpm_setup = rctx.which("swtpm_setup")

    if swtpm == None:
        fail(
            "swtpm not found on host. Install with:\n" +
            "  macOS:        brew install swtpm\n" +
            "  Debian/Ubuntu: apt install swtpm swtpm-tools",
        )
    if swtpm_setup == None:
        fail(
            "swtpm_setup not found on host. Install with:\n" +
            "  macOS:        brew install swtpm\n" +
            "  Debian/Ubuntu: apt install swtpm-tools",
        )

    # Simple wrapper scripts — the host binary already has its library paths
    # resolved via its own rpath or the system dynamic linker configuration.
    rctx.file("swtpm.sh", content = """\
#!/bin/bash
exec "{swtpm}" "$@"
""".format(swtpm = swtpm), executable = True)

    rctx.file("swtpm_setup.sh", content = """\
#!/bin/bash
exec "{swtpm_setup}" "$@"
""".format(swtpm_setup = swtpm_setup), executable = True)

    rctx.file("BUILD.bazel", content = """\
sh_binary(
    name = "swtpm",
    srcs = ["swtpm.sh"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "swtpm_setup",
    srcs = ["swtpm_setup.sh"],
    visibility = ["//visibility:public"],
)
""")

swtpm_host_repo = repository_rule(
    implementation = _swtpm_host_repo_impl,
    local = True,
    doc = "Wraps host swtpm binaries for use in Bazel. Supports Linux and macOS.",
)

def _qemu_host_repo_impl(rctx):
    """Creates a repository that wraps host QEMU binaries.

    Searches for qemu-system-x86_64, qemu-system-aarch64, and qemu-img on the
    host PATH. For each binary that is found, creates a wrapper sh_binary target.
    For each binary that is NOT found, creates a stub sh_binary that prints an
    error and exits 1 at execution time. This ensures all targets always exist
    at analysis time, and toolchain declarations for missing binaries only fail
    when actually invoked rather than during Bazel analysis.

    Fails with an actionable error if no QEMU system emulator is found at all.
    """
    qemu_x86_64 = rctx.which("qemu-system-x86_64")
    qemu_aarch64 = rctx.which("qemu-system-aarch64")
    qemu_img = rctx.which("qemu-img")

    if qemu_x86_64 == None and qemu_aarch64 == None:
        fail(
            "No QEMU system emulators found on host PATH. Install with:\n" +
            "  macOS:        brew install qemu\n" +
            "  Debian/Ubuntu: apt install qemu-system-x86 qemu-system-arm",
        )

    build_targets = []

    for binary, path in [
        ("qemu-system-x86_64", qemu_x86_64),
        ("qemu-system-aarch64", qemu_aarch64),
    ]:
        script_name = binary + ".sh"
        if path != None:
            rctx.file(script_name, content = """\
#!/bin/bash
exec "{path}" "$@"
""".format(path = path), executable = True)
        else:
            rctx.file(script_name, content = """\
#!/bin/bash
echo "error: {binary} not found on host PATH. Install with:" >&2
echo "  macOS:        brew install qemu" >&2
echo "  Debian/Ubuntu: apt install qemu-system-x86 qemu-system-arm" >&2
exit 1
""".format(binary = binary), executable = True)
        build_targets.append("""\
sh_binary(
    name = "{binary}",
    srcs = ["{script}"],
    visibility = ["//visibility:public"],
)
""".format(binary = binary, script = script_name))

    # qemu-img: always create the target, stub if missing
    qemu_img_script = "qemu-img.sh"
    if qemu_img != None:
        rctx.file(qemu_img_script, content = """\
#!/bin/bash
exec "{path}" "$@"
""".format(path = qemu_img), executable = True)
    else:
        rctx.file(qemu_img_script, content = """\
#!/bin/bash
echo "error: qemu-img not found on host PATH. Install with:" >&2
echo "  macOS:        brew install qemu" >&2
echo "  Debian/Ubuntu: apt install qemu-utils" >&2
exit 1
""", executable = True)
    build_targets.append("""\
sh_binary(
    name = "qemu-img",
    srcs = ["qemu-img.sh"],
    visibility = ["//visibility:public"],
)
""")

    rctx.file("BUILD.bazel", content = "\n".join(build_targets))

qemu_host_repo = repository_rule(
    implementation = _qemu_host_repo_impl,
    local = True,
    doc = "Wraps host QEMU binaries for use in Bazel. Supports Linux and macOS.",
)

def _qemu_toolchains_repo_impl(rctx):
    """Creates a repository with toolchain declarations."""
    rctx.file("BUILD.bazel", content = rctx.attr.build_file_content)

qemu_toolchains_repo = repository_rule(
    implementation = _qemu_toolchains_repo_impl,
    attrs = {
        "build_file_content": attr.string(mandatory = True),
    },
)
