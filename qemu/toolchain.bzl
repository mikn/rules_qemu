"""QemuToolchainInfo provider and qemu_toolchain rule."""

QemuToolchainInfo = provider(
    doc = "Information about a QEMU toolchain",
    fields = {
        "qemu_system": "File: qemu-system-{arch} binary (None if host fallback)",
        "qemu_img": "File: qemu-img binary (None if host fallback)",
        "ovmf_code": "File: OVMF_CODE firmware (read-only pflash)",
        "ovmf_vars": "File: OVMF_VARS template (writable pflash source)",
        "arch": "string: x86_64 or aarch64",
    },
)

def _qemu_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        qemu_info = QemuToolchainInfo(
            qemu_system = ctx.file.qemu_system,
            qemu_img = ctx.file.qemu_img,
            ovmf_code = ctx.file.ovmf_code,
            ovmf_vars = ctx.file.ovmf_vars,
            arch = ctx.attr.arch,
        ),
    )
    return [toolchain_info]

qemu_toolchain = rule(
    implementation = _qemu_toolchain_impl,
    attrs = {
        "qemu_system": attr.label(allow_single_file = True, doc = "qemu-system binary"),
        "qemu_img": attr.label(allow_single_file = True, doc = "qemu-img binary"),
        "ovmf_code": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "OVMF CODE firmware file",
        ),
        "ovmf_vars": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "OVMF VARS template file",
        ),
        "arch": attr.string(
            default = "x86_64",
            values = ["x86_64", "aarch64"],
            doc = "Target architecture",
        ),
    },
    doc = "Defines a QEMU toolchain with firmware and optional binaries.",
)
