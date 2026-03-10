# rules_qemu

Bazel toolchains for QEMU and swtpm. Provides hermetic OVMF firmware, builds swtpm from source via `rules_foreign_cc`, and exposes toolchain types for VM testing.

## Commands

```bash
bazel test //...                    # Run all tests
bazel build //...                   # Build all targets
```

## Structure

- `qemu/defs.bzl` — Public API: `QemuToolchainInfo`, `qemu_toolchain`, toolchain type constants
- `qemu/extensions.bzl` — Module extension: `qemu` (configures OVMF + swtpm)
- `qemu/repositories.bzl` — Repository rules: `ovmf_repo`, `swtpm_host_repo`, `qemu_toolchains_repo`
- `qemu/toolchain.bzl` — `QemuToolchainInfo` provider and `qemu_toolchain` rule
- `qemu/private/` — Build files for native deps (swtpm, libtpms, json-glib, libtasn1, gmp)
- `qemu/private/versions.bzl` — Version pinning for all artifacts
- `qemu/private/cc_static_only.bzl` — Strips `.so` from `CcInfo` to force static linking
- `tests/` — Analysis and build tests

## Toolchain Types

- `@rules_qemu//qemu:toolchain_type` — QEMU (`QemuToolchainInfo`: qemu_system, qemu_img, ovmf_code, ovmf_vars, arch)
- `@rules_qemu//qemu:swtpm_type` — swtpm binary (via `toolchain_utils` `ToolchainInfo`)
- `@rules_qemu//qemu:swtpm_setup_type` — swtpm_setup binary

## Code Quality

- **Starlark**: All toolchain fields validated. `fail()` on missing required attrs. Repository rules must be reproducible.
- **Native builds**: Pin exact versions in `versions.bzl`. All deps via `cc_static_only` wrapper — never link `.so`. Test that built binaries execute.
- **swtpm patches**: `configure.ac` appends `-Werror` — must be stripped via `patch_cmds`. PKG_CONFIG stubs required for BCR deps.
- **rules_foreign_cc escaping**: Use `$$$$VAR$$$$` in Starlark env dicts for shell variable passthrough.
- **Test toolchain changes**: Add analysis tests in `tests/` verifying provider fields.

## Releasing

See [RELEASING.md](RELEASING.md). Tag push → GitHub release → `publish-to-bcr` reusable workflow auto-opens BCR PR. No deps on other `rules_*` modules.
