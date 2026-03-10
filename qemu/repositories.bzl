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
        fail("swtpm not found on host. Install with: apt install swtpm swtpm-tools")
    if swtpm_setup == None:
        fail("swtpm_setup not found on host. Install with: apt install swtpm-tools")

    # Create symlinks to host binaries
    rctx.symlink(swtpm, "swtpm")
    rctx.symlink(swtpm_setup, "swtpm_setup")

    rctx.file("BUILD.bazel", content = """
exports_files(["swtpm", "swtpm_setup"], visibility = ["//visibility:public"])
""")

swtpm_host_repo = repository_rule(
    implementation = _swtpm_host_repo_impl,
    local = True,
    doc = "Wraps host swtpm binaries for use in Bazel.",
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
