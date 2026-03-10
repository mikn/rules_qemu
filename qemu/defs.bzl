"""Public API for rules_qemu."""

load("//qemu:toolchain.bzl", _QemuToolchainInfo = "QemuToolchainInfo", _qemu_toolchain = "qemu_toolchain")

QemuToolchainInfo = _QemuToolchainInfo
qemu_toolchain = _qemu_toolchain

QEMU_TOOLCHAIN_TYPE = "@rules_qemu//qemu:toolchain_type"
SWTPM_TOOLCHAIN_TYPE = "@rules_qemu//qemu:swtpm_type"
SWTPM_SETUP_TOOLCHAIN_TYPE = "@rules_qemu//qemu:swtpm_setup_type"
