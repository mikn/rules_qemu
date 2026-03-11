# rules_qemu

Bazel toolchains for QEMU and TPM emulation. Provides hermetic OVMF/AAVMF firmware and statically-linked swtpm binaries across Linux and macOS.

## Supported Platforms

### Native (fast — KVM on Linux, HVF on macOS)

| Host (exec) | Guest (target) | Accelerator | Machine |
|-------------|----------------|-------------|---------|
| Linux x86_64 | x86_64 | `kvm` | `q35` |
| Linux aarch64 | aarch64 | `kvm` | `virt` |
| macOS ARM64 | aarch64 | `hvf` | `virt` |

### Cross-architecture emulation (slow — TCG software emulation, 10-50x performance penalty)

| Host (exec) | Guest (target) | Accelerator | Machine |
|-------------|----------------|-------------|---------|
| macOS ARM64 | x86_64 | `tcg` | `q35` |
| Linux x86_64 | aarch64 | `tcg` | `virt` |
| Linux aarch64 | x86_64 | `tcg` | `q35` |

Bazel selects the best-matching toolchain automatically. Native toolchains are registered first and take priority over TCG ones when the host supports them.

## Setup

```starlark
# MODULE.bazel
bazel_dep(name = "rules_qemu", version = "0.1.0")

qemu = use_extension("@rules_qemu//qemu:extensions.bzl", "qemu")
qemu.toolchain(
    ovmf_version = "2025.02-8",
    swtpm_version = "0.10.1",
    swtpm_from_source = True,
)
```

### macOS Prerequisites

QEMU must be installed via Homebrew on macOS (hermetic builds are not yet supported):

```sh
brew install qemu
```

When building swtpm from source (the default), autotools and pkg-config are also required:

```sh
brew install autoconf automake libtool pkg-config
```

To use a host-installed swtpm instead, set `swtpm_from_source = False` and install via `brew install swtpm`.

### Linux Prerequisites

QEMU must be on the host PATH. swtpm is built from source by default (set `swtpm_from_source = True`). For host swtpm:

```sh
# Debian/Ubuntu
apt install qemu-system-x86 qemu-system-arm swtpm swtpm-tools
```

## Toolchain Types

Three toolchain types are provided:

| Type | Purpose | Access |
|------|---------|--------|
| `@rules_qemu//qemu:toolchain_type` | QEMU + firmware | `QemuToolchainInfo` with `ovmf_code`, `ovmf_vars`, `qemu_system`, `qemu_img`, `arch`, `accel`, `machine_type` |
| `@rules_qemu//qemu:swtpm_type` | swtpm binary | `toolchain_utils` `ToolchainInfo` with `.executable` |
| `@rules_qemu//qemu:swtpm_setup_type` | swtpm_setup binary | `toolchain_utils` `ToolchainInfo` with `.executable` |

## Usage in Rules

```starlark
load("@rules_qemu//qemu:defs.bzl", "QemuToolchainInfo", "QEMU_TOOLCHAIN_TYPE", "SWTPM_TOOLCHAIN_TYPE")

def _my_rule_impl(ctx):
    qemu_info = ctx.toolchains[QEMU_TOOLCHAIN_TYPE].qemu_info

    ovmf_code    = qemu_info.ovmf_code    # OVMF_CODE / AAVMF_CODE firmware file
    ovmf_vars    = qemu_info.ovmf_vars    # OVMF_VARS / AAVMF_VARS template file
    arch         = qemu_info.arch          # "x86_64" or "aarch64"
    accel        = qemu_info.accel         # "kvm", "hvf", or "tcg"
    machine_type = qemu_info.machine_type  # "q35" or "virt"

    # qemu_system and qemu_img are stub scripts that invoke the host-installed
    # QEMU binaries (resolved via PATH at runtime).
    qemu_bin = qemu_info.qemu_system

    swtpm = ctx.toolchains[SWTPM_TOOLCHAIN_TYPE].executable

my_rule = rule(
    implementation = _my_rule_impl,
    toolchains = [QEMU_TOOLCHAIN_TYPE, SWTPM_TOOLCHAIN_TYPE],
)
```

### Exported Constants

```starlark
load("@rules_qemu//qemu:defs.bzl",
    "QEMU_ACCEL_KVM", "QEMU_ACCEL_HVF", "QEMU_ACCEL_TCG",
    "QEMU_MACHINE_Q35", "QEMU_MACHINE_VIRT",
    "QEMU_ARCH_X86_64", "QEMU_ARCH_AARCH64",
)
```

## What Gets Built / Downloaded

**OVMF** (x86_64 guests) is extracted from the Debian `ovmf` package (snapshot.debian.org):
- `OVMF_CODE_4M.secboot.fd` — UEFI firmware with Secure Boot support (read-only)
- `OVMF_VARS_4M.fd` — UEFI variable store template (copied per-VM)

**AAVMF** (aarch64 guests) is extracted from the Debian `qemu-efi-aarch64` package:
- `AAVMF_CODE.secboot.fd` — AArch64 UEFI firmware with Secure Boot support (read-only)
- `AAVMF_VARS.fd` — AArch64 UEFI variable store template (copied per-VM)

Both packages come from the same Debian snapshot timestamp for reproducibility.

**swtpm** is built from source with all dependencies statically linked:
- `libtpms` v0.10.2 (TPM emulation)
- `json-glib` v1.10.8, `libtasn1` v4.19.0, `gmp` v6.3.0
- `openssl` and `glib` from BCR (forced static via `cc_static_only`)

The resulting `swtpm` and `swtpm_setup` binaries have zero runtime dependencies beyond libc and work on both Linux and macOS.

**QEMU** binaries are currently sourced from the host PATH on all platforms. A future version may add hermetic downloads.

## Go Packages

### `vm` — VM lifecycle management

Low-level QEMU process management with functional options:

```go
import "github.com/mikn/rules_qemu/vm"

v, err := vm.Start(ctx,
    vm.WithKernelBoot(kernel, initrd, "console=ttyS0"),
    vm.WithMemory("2G"),
    vm.WithCPUs(2),
    vm.WithUEFI(ovmfCode, ovmfVars),
    vm.WithTPM(swtpm, swtpmSetup),
    vm.WithAgent(),
    vm.WithSerialCapture(),
    vm.WithQMP(),
)
defer v.Kill()
```

Provides QMP client, serial console capture, 9P sharing, TPM management, and agent connection.

### `agent` — Guest agent binary

Static Go binary (~4MB) that runs inside VMs, serving RPC over virtio-serial (`/dev/virtio-ports/org.vmtest.agent`). Implements command execution, systemd unit queries, port checks, and file operations.

Include in guest images via `@rules_qemu//agent:agent_tar`.

### `agentpb` — Shared RPC types

Request/response types for host-guest communication: `ExecRequest`, `ExecResponse`, `UnitRequest`, `UnitResponse`, `FileRequest`, `FileResponse`, `PortRequest`, `PortResponse`.

## Architecture Notes

- `exec_compatible_with` constrains the HOST machine where QEMU runs
- `target_compatible_with` constrains the GUEST architecture being emulated
- For swtpm, only `exec_compatible_with` is set (TPM is architecture-agnostic)
- Native toolchains (KVM/HVF) are registered before TCG ones so Bazel prefers them
- TCG emulation works but carries a significant performance penalty — use it only when cross-arch testing is required
