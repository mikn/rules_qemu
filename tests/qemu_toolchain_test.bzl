"""Analysis tests for qemu_toolchain rule."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//qemu:toolchain.bzl", "QemuToolchainInfo")

# --- Test: qemu_toolchain provides correct provider fields ---

def _provides_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    tc_info = target[platform_common.ToolchainInfo]
    qemu_info = tc_info.qemu_info

    asserts.equals(env, "x86_64", qemu_info.arch)
    asserts.equals(env, "kvm", qemu_info.accel)
    asserts.equals(env, "q35", qemu_info.machine_type)
    asserts.true(env, qemu_info.ovmf_code != None, "ovmf_code should be present")
    asserts.true(env, qemu_info.ovmf_vars != None, "ovmf_vars should be present")
    # qemu_system and qemu_img are None when not provided (host fallback)
    asserts.true(env, qemu_info.qemu_system == None, "qemu_system should be None for host fallback")
    asserts.true(env, qemu_info.qemu_img == None, "qemu_img should be None for host fallback")

    return analysistest.end(env)

provides_info_test = analysistest.make(_provides_info_test_impl)

# --- Test: qemu_toolchain with explicit binaries ---

def _with_binaries_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    tc_info = target[platform_common.ToolchainInfo]
    qemu_info = tc_info.qemu_info

    asserts.equals(env, "x86_64", qemu_info.arch)
    asserts.equals(env, "kvm", qemu_info.accel)
    asserts.equals(env, "q35", qemu_info.machine_type)
    asserts.true(env, qemu_info.qemu_system != None, "qemu_system should be present")
    asserts.true(env, qemu_info.qemu_img != None, "qemu_img should be present")
    asserts.true(env, qemu_info.ovmf_code != None, "ovmf_code should be present")
    asserts.true(env, qemu_info.ovmf_vars != None, "ovmf_vars should be present")

    return analysistest.end(env)

with_binaries_test = analysistest.make(_with_binaries_test_impl)

# --- Test: qemu_toolchain with aarch64 arch (native KVM/HVF) ---

def _aarch64_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    tc_info = target[platform_common.ToolchainInfo]
    qemu_info = tc_info.qemu_info

    asserts.equals(env, "aarch64", qemu_info.arch)
    asserts.equals(env, "kvm", qemu_info.accel)
    asserts.equals(env, "virt", qemu_info.machine_type)

    return analysistest.end(env)

aarch64_test = analysistest.make(_aarch64_test_impl)

# --- Test: qemu_toolchain with TCG cross-arch acceleration ---

def _tcg_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    tc_info = target[platform_common.ToolchainInfo]
    qemu_info = tc_info.qemu_info

    asserts.equals(env, "x86_64", qemu_info.arch)
    asserts.equals(env, "tcg", qemu_info.accel)
    asserts.equals(env, "q35", qemu_info.machine_type)

    return analysistest.end(env)

tcg_test = analysistest.make(_tcg_test_impl)

# --- Test: qemu_toolchain with HVF acceleration (macOS) ---

def _hvf_aarch64_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    tc_info = target[platform_common.ToolchainInfo]
    qemu_info = tc_info.qemu_info

    asserts.equals(env, "aarch64", qemu_info.arch)
    asserts.equals(env, "hvf", qemu_info.accel)
    asserts.equals(env, "virt", qemu_info.machine_type)

    return analysistest.end(env)

hvf_aarch64_test = analysistest.make(_hvf_aarch64_test_impl)
