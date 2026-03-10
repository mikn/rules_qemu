# rules_qemu

Bazel toolchains for QEMU and TPM emulation. Provides hermetic OVMF firmware and statically-linked swtpm binaries.

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

## Toolchain Types

Three toolchain types are provided:

| Type | Purpose | Access |
|------|---------|--------|
| `@rules_qemu//qemu:toolchain_type` | QEMU + OVMF firmware | `QemuToolchainInfo` with `ovmf_code`, `ovmf_vars`, `qemu_system`, `qemu_img`, `arch` |
| `@rules_qemu//qemu:swtpm_type` | swtpm binary | `toolchain_utils` `ToolchainInfo` with `.executable` |
| `@rules_qemu//qemu:swtpm_setup_type` | swtpm_setup binary | `toolchain_utils` `ToolchainInfo` with `.executable` |

## Usage in Rules

```starlark
load("@rules_qemu//qemu:defs.bzl", "QemuToolchainInfo", "QEMU_TOOLCHAIN_TYPE", "SWTPM_TOOLCHAIN_TYPE")

def _my_rule_impl(ctx):
    qemu_info = ctx.toolchains[QEMU_TOOLCHAIN_TYPE].qemu_info
    ovmf_code = qemu_info.ovmf_code   # OVMF_CODE firmware file
    ovmf_vars = qemu_info.ovmf_vars   # OVMF_VARS template file
    arch = qemu_info.arch              # "x86_64"

    swtpm = ctx.toolchains[SWTPM_TOOLCHAIN_TYPE].executable

my_rule = rule(
    implementation = _my_rule_impl,
    toolchains = [QEMU_TOOLCHAIN_TYPE, SWTPM_TOOLCHAIN_TYPE],
)
```

## What Gets Built

**OVMF** is extracted from Debian packages (snapshot.debian.org):
- `OVMF_CODE_4M.secboot.fd` — UEFI firmware with Secure Boot support (read-only)
- `OVMF_VARS_4M.fd` — UEFI variable store template (copied per-VM)

**swtpm** is built from source with all dependencies statically linked:
- `libtpms` v0.10.2 (TPM emulation)
- `json-glib` v1.10.8, `libtasn1` v4.19.0, `gmp` v6.3.0
- `openssl` and `glib` from BCR (forced static via `cc_static_only`)

The resulting `swtpm` and `swtpm_setup` binaries have zero runtime dependencies beyond libc.

## Architecture

Currently supports `x86_64`. The toolchain declarations include `target_compatible_with` constraints for `@platforms//cpu:x86_64` and `@platforms//os:linux`.
