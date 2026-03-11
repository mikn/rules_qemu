"""Public API for rules_qemu."""

load("//qemu:toolchain.bzl", _QemuToolchainInfo = "QemuToolchainInfo", _qemu_toolchain = "qemu_toolchain")

QemuToolchainInfo = _QemuToolchainInfo
qemu_toolchain = _qemu_toolchain

QEMU_TOOLCHAIN_TYPE = "@rules_qemu//qemu:toolchain_type"
SWTPM_TOOLCHAIN_TYPE = "@rules_qemu//qemu:swtpm_type"
SWTPM_SETUP_TOOLCHAIN_TYPE = "@rules_qemu//qemu:swtpm_setup_type"

# Supported guest architectures
QEMU_ARCH_X86_64 = "x86_64"
QEMU_ARCH_AARCH64 = "aarch64"

# Acceleration backends
QEMU_ACCEL_KVM = "kvm"    # Linux native KVM (fast)
QEMU_ACCEL_HVF = "hvf"    # macOS Hypervisor.framework (fast)
QEMU_ACCEL_TCG = "tcg"    # Software emulation, cross-arch (slow, ~10-50x penalty)

# Machine types
QEMU_MACHINE_Q35 = "q35"   # x86_64 guests
QEMU_MACHINE_VIRT = "virt"  # aarch64 guests
