# rules_qemu

Bazel toolchains for QEMU and swtpm. Provides hermetic OVMF firmware, builds swtpm from source via `rules_foreign_cc`, and exposes toolchain types for VM testing.

## Commands

```bash
bazel test //...                    # Run all tests
bazel build //...                   # Build all targets
bazel run //:gazelle                # Regenerate BUILD files after Go changes
```

## Structure

- `qemu/defs.bzl` — Public API: `QemuToolchainInfo`, `qemu_toolchain`, toolchain type constants
- `qemu/extensions.bzl` — Module extension: `qemu` (configures OVMF + swtpm)
- `qemu/repositories.bzl` — Repository rules: `ovmf_repo`, `swtpm_host_repo`, `qemu_toolchains_repo`
- `qemu/toolchain.bzl` — `QemuToolchainInfo` provider and `qemu_toolchain` rule
- `qemu/private/` — Build files for native deps (swtpm, libtpms, json-glib, libtasn1, gmp)
- `qemu/private/versions.bzl` — Version pinning for all artifacts
- `qemu/private/cc_static_only.bzl` — Strips `.so` from `CcInfo` to force static linking
- `vm/` — Go VM lifecycle library (functional options: `vm.Start(ctx, vm.WithKernelBoot(...), ...)`)
- `vm/` — Provides: QMP client, serial console, 9P sharing, TPM, networking, AgentConn, Bridge
- `agent/` — Guest agent binary (~4MB static Go), virtio-serial RPC via `net/rpc` + `jsonrpc`
- `agentpb/` — Shared RPC types (ExecRequest/Response, UnitRequest/Response, etc.)
- `tests/` — Analysis, build, and imperative tests

## Toolchain Types

- `@rules_qemu//qemu:toolchain_type` — QEMU (`QemuToolchainInfo`: qemu_system, qemu_img, ovmf_code, ovmf_vars, arch)
- `@rules_qemu//qemu:swtpm_type` — swtpm binary (via `toolchain_utils` `ToolchainInfo`)
- `@rules_qemu//qemu:swtpm_setup_type` — swtpm_setup binary

## Code Quality

- **Starlark**: All toolchain fields validated. `fail()` on missing required attrs. Repository rules must be reproducible.
- **Native builds**: Pin exact versions in `versions.bzl`. All deps via `cc_static_only` wrapper — never link `.so`. Test that built binaries execute.
- **Go tools**: Static binaries (`pure = "on"`, `static = "on"`). Zero CGO for agent.
- **swtpm patches**: `configure.ac` appends `-Werror` — must be stripped via `patch_cmds`. PKG_CONFIG stubs required for BCR deps.
- **rules_foreign_cc escaping**: Use `$$$$VAR$$$$` in Starlark env dicts for shell variable passthrough (`$$$$VAR$$$$` → `$$VAR$$` after make-var → `$VAR` after template expansion).
- **Test toolchain changes**: Add analysis tests in `tests/` verifying provider fields.

## Pitfalls & Learnings

### swtpm / TPM

- **`--flags startup-clear` is required**: Tells swtpm to run `TPM2_Startup(TPM_SU_CLEAR)` internally so TPM is ready when OVMF connects. Without it, OVMF gets `EFI_DEVICE_ERROR` on first TPM access, causing 60-100s+ firmware boot times.
- **`not-need-init` is NOT sufficient**: It only allows guest to send TPM2_Startup if it wants, but doesn't actually start the TPM.
- **Default to 1 PCR bank (`sha256`)**: 4 banks (`sha1,sha256,sha384,sha512`) causes ~4x UEFI measurement time per boot component. OVMF may call `TPM2_PCR_Allocate` if banks don't match expectations, triggering a firmware reboot cycle. `tpmPCRBanks` is `[]string` with variadic `WithTPMBanks(...string)` option.
- **swtpm logging is CPU-bound**: Hex dump formatting at level=4 is extremely slow even on tmpfs — it's CPU-bound, not I/O-bound. Keep log level low.
- **Socket readiness**: Use `net.DialTimeout("unix", ...)` not file existence — swtpm creates the socket file before finishing TPM state load.

### OVMF / Secure Boot

- **Fresh OVMF_VARS causes double boot**: First boot enrolls PK/KEK/db certificates, second boot has SecureBoot enabled. This is expected for fresh VARS files.
- **PCI device ordering matters**: Place firmware/storage devices before TPM/network to avoid unnecessary PXE ROM loading and TPM measurement overhead.

### cc_static_only

- **Purpose**: Strips `.so` files from `CcInfo` providers, forcing `rules_foreign_cc` to link statically against BCR deps (glib, openssl).
- **Usage**: Wrap BCR `cc_library` targets with `cc_static_only` before passing to `rules_foreign_cc` builds.

### VM lifecycle (vm/ package)

- **Functional options pattern**: `vm.Start(ctx, vm.WithKernelBoot(...), vm.WithTPM(...))`.
- **Unix domain socket 108-byte path limit**: Always use `/tmp` for sockets, not deep Bazel sandbox paths. Sandbox paths can exceed the 108-byte `sun_path` limit.
- **Go os/exec pipe gotcha**: `cmd.Run()` with `bytes.Buffer` stdout/stderr blocks until ALL inherited file descriptors close (including backgrounded processes). Use the agent's `Background` RPC for detached processes, not shell `&`.
- **Agent DNS**: Guest VMs may have no DNS resolver. `resolveAddr()` maps `"localhost"` → `"127.0.0.1"` to avoid DNS lookups that would hang.

### Serial console

- **Non-blocking sends**: Both `lines` and `logChan` use non-blocking sends. Lines may be dropped if the consumer is slow.
- **Use `OnLine()` for logging, `WaitFor()` for pattern matching**: Don't use both `Lines()` channel and `WaitFor()` concurrently.
- **Cleanup order**: `Kill()` → `serial.Close()` → `serial.Wait()` → OnLine goroutine drains. This order prevents `t.Logf` data races.

### virtio-serial

- **Port discovery without udev**: `/dev/virtio-ports/` named symlinks are created by udev. Without udev, scan `/sys/class/virtio-ports/vport*/name` and create symlinks manually.
- **9P symlinks**: Symlinks to host absolute paths are dangling inside the guest. Always copy files into the shared directory instead.

### Agent (agent/ package)

- **Must be pure static Go**: `pure = "on"`, `static = "on"`, stripped. Zero CGO. Only stdlib deps.
- **Agent tar**: Produces `agent_tar` containing the binary and systemd service file. The service file must have `mode = "0644"`.

### Build system

- **Bazel sandbox persistent writes**: Need BOTH `--sandbox_add_mount_pair=X:X` AND `--sandbox_writable_path=X`.
- **ccache symlink mode**: Create `clang -> ccache` symlink first on PATH, real clang found further in PATH.
- **`toolchains_llvm` compiler_executable**: The actual binary is `cc_wrapper.sh`, real clang at `llvm_toolchain_llvm/bin/clang`.
- **rules_foreign_cc make toolchain**: Access via `.data` (not `.make_info`), has `.target` and `.path`.
- **`perl_info.runtime`**: Already a depset — don't wrap in `depset()`.
- **ARM `toolchain_utils` pattern**: `toolchain_info` rule wraps executable → provides `ToolchainInfo` with fields `.executable`, `.run`, `.variable`, `.default`. Access in Starlark: `ctx.toolchains[TYPE].executable`.

### Circular dependency

- **rules_qemu CANNOT depend on rules_linux**: rules_linux depends on rules_qemu (for macOS kernel build), so rules_qemu cannot use rules_linux macros. This is a hard constraint.

## Self-Correction Protocol

When you receive a correction from the user about rules_qemu patterns, VM lifecycle, swtpm behavior, or toolchain configuration, update the "Pitfalls & Learnings" section of this file to capture the correction. This prevents repeating the same mistakes across conversations.

## Releasing

See [RELEASING.md](RELEASING.md). Tag push → GitHub release → `publish-to-bcr` reusable workflow auto-opens BCR PR. No deps on other `rules_*` modules.
