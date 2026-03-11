"""QemuToolchainInfo provider and qemu_toolchain rule."""

QemuToolchainInfo = provider(
    doc = "Information about a QEMU toolchain",
    fields = {
        "qemu_system": "File: qemu-system-{arch} binary (None if host fallback)",
        "qemu_img": "File: qemu-img binary (None if host fallback)",
        "ovmf_code": "File: OVMF/AAVMF CODE firmware (read-only pflash)",
        "ovmf_vars": "File: OVMF/AAVMF VARS template (writable pflash source)",
        "arch": "string: guest architecture — x86_64 or aarch64",
        "accel": "string: acceleration backend — kvm (Linux native), hvf (macOS native), tcg (cross-arch emulation, slow)",
        "machine_type": "string: QEMU machine type — q35 (x86_64 guest) or virt (aarch64 guest)",
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
            accel = ctx.attr.accel,
            machine_type = ctx.attr.machine_type,
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
            doc = "OVMF/AAVMF CODE firmware file",
        ),
        "ovmf_vars": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "OVMF/AAVMF VARS template file",
        ),
        "arch": attr.string(
            default = "x86_64",
            values = ["x86_64", "aarch64"],
            doc = "Guest target architecture",
        ),
        "accel": attr.string(
            default = "kvm",
            values = ["kvm", "hvf", "tcg"],
            doc = "Acceleration backend: kvm (Linux native), hvf (macOS native), tcg (cross-arch, slow)",
        ),
        "machine_type": attr.string(
            default = "q35",
            values = ["q35", "virt"],
            doc = "QEMU machine type: q35 for x86_64 guests, virt for aarch64 guests",
        ),
    },
    doc = "Defines a QEMU toolchain with firmware, optional binaries, and acceleration metadata.",
)
