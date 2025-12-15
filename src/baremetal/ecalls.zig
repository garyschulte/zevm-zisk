const std = @import("std");
const primitives = @import("primitives");

/// Syscall numbers for RISC-V ecalls
/// These can be customized based on your zkVM syscall interface
pub const SyscallNum = enum(u32) {
    // Cryptographic operations
    keccak256 = 0x1000,
    sha256 = 0x1001,
    ecrecover = 0x1002,
    bn256_add = 0x1003,
    bn256_mul = 0x1004,
    bn256_pairing = 0x1005,
    blake2f = 0x1006,
    modexp = 0x1007,
    // BLS12-381 operations
    bls12_g1_add = 0x1010,
    bls12_g1_mul = 0x1011,
    bls12_g1_msm = 0x1012,
    bls12_g2_add = 0x1013,
    bls12_g2_mul = 0x1014,
    bls12_g2_msm = 0x1015,
    bls12_pairing = 0x1016,
    bls12_map_fp_to_g1 = 0x1017,
    bls12_map_fp2_to_g2 = 0x1018,
    // KZG point evaluation
    kzg_point_evaluation = 0x1020,
    // P256 verification
    p256_verify = 0x1030,

    _,
};

/// Result type for ecall operations
pub const EcallResult = union(enum) {
    success: []const u8,
    error_out_of_gas: void,
    error_invalid_input: void,
    error_precompile_error: void,
};

/// Perform a RISC-V ecall for cryptographic operations
/// This is a stub implementation that will be replaced with actual ecall assembly
fn ecallStub(
    syscall_num: u32,
    input_ptr: [*]const u8,
    input_len: usize,
    output_ptr: [*]u8,
    output_len: usize,
    gas_limit: u64,
) callconv(.C) struct { status: u32, gas_used: u64 } {
    _ = syscall_num;
    _ = input_ptr;
    _ = input_len;
    _ = output_ptr;
    _ = output_len;
    _ = gas_limit;

    // Stub implementation - returns error
    // In real bare-metal environment, this would use inline assembly:
    // asm volatile ("ecall"
    //     : [status] "={x10}" (-> u32),
    //       [gas_used] "={x11}" (-> u64)
    //     : [syscall] "{x17}" (syscall_num),
    //       [input_ptr] "{x10}" (input_ptr),
    //       [input_len] "{x11}" (input_len),
    //       [output_ptr] "{x12}" (output_ptr),
    //       [output_len] "{x13}" (output_len),
    //       [gas] "{x14}" (gas_limit)
    //     : "memory"
    // );

    return .{ .status = 2, .gas_used = 0 }; // Error: not implemented
}

/// Keccak256 hash via ecall
pub fn keccak256Ecall(input: []const u8, output: *[32]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.keccak256),
        input.ptr,
        input.len,
        output,
        32,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// SHA256 hash via ecall
pub fn sha256Ecall(input: []const u8, output: *[32]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.sha256),
        input.ptr,
        input.len,
        output,
        32,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// ECRECOVER signature recovery via ecall
pub fn ecrecoverEcall(
    msg: [32]u8,
    sig: [64]u8,
    recid: u8,
    output: *[20]u8,
    gas_limit: u64,
) !u64 {
    var input: [97]u8 = undefined;
    @memcpy(input[0..32], &msg);
    @memcpy(input[32..96], &sig);
    input[96] = recid;

    const result = ecallStub(
        @intFromEnum(SyscallNum.ecrecover),
        &input,
        input.len,
        output,
        20,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BN256 Add via ecall
pub fn bn256AddEcall(input: []const u8, output: *[64]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bn256_add),
        input.ptr,
        input.len,
        output,
        64,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BN256 Mul via ecall
pub fn bn256MulEcall(input: []const u8, output: *[64]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bn256_mul),
        input.ptr,
        input.len,
        output,
        64,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BN256 Pairing via ecall
pub fn bn256PairingEcall(input: []const u8, output: *[32]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bn256_pairing),
        input.ptr,
        input.len,
        output,
        32,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// Blake2F compression via ecall
pub fn blake2fEcall(input: []const u8, output: *[64]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.blake2f),
        input.ptr,
        input.len,
        output,
        64,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// Modular exponentiation via ecall
pub fn modexpEcall(input: []const u8, output: []u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.modexp),
        input.ptr,
        input.len,
        output.ptr,
        output.len,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G1 Add via ecall
pub fn bls12G1AddEcall(input: []const u8, output: *[128]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g1_add),
        input.ptr,
        input.len,
        output,
        128,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G1 Mul via ecall
pub fn bls12G1MulEcall(input: []const u8, output: *[128]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g1_mul),
        input.ptr,
        input.len,
        output,
        128,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G1 MSM (Multi-Scalar Multiplication) via ecall
pub fn bls12G1MsmEcall(input: []const u8, output: *[128]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g1_msm),
        input.ptr,
        input.len,
        output,
        128,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G2 Add via ecall
pub fn bls12G2AddEcall(input: []const u8, output: *[256]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g2_add),
        input.ptr,
        input.len,
        output,
        256,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G2 Mul via ecall
pub fn bls12G2MulEcall(input: []const u8, output: *[256]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g2_mul),
        input.ptr,
        input.len,
        output,
        256,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 G2 MSM via ecall
pub fn bls12G2MsmEcall(input: []const u8, output: *[256]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_g2_msm),
        input.ptr,
        input.len,
        output,
        256,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 Pairing via ecall
pub fn bls12PairingEcall(input: []const u8, output: *[32]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_pairing),
        input.ptr,
        input.len,
        output,
        32,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 Map Fp to G1 via ecall
pub fn bls12MapFpToG1Ecall(input: []const u8, output: *[128]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_map_fp_to_g1),
        input.ptr,
        input.len,
        output,
        128,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// BLS12-381 Map Fp2 to G2 via ecall
pub fn bls12MapFp2ToG2Ecall(input: []const u8, output: *[256]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.bls12_map_fp2_to_g2),
        input.ptr,
        input.len,
        output,
        256,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// KZG Point Evaluation via ecall
pub fn kzgPointEvaluationEcall(input: []const u8, output: *[64]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.kzg_point_evaluation),
        input.ptr,
        input.len,
        output,
        64,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}

/// P256 Verify via ecall
pub fn p256VerifyEcall(input: []const u8, output: *[32]u8, gas_limit: u64) !u64 {
    const result = ecallStub(
        @intFromEnum(SyscallNum.p256_verify),
        input.ptr,
        input.len,
        output,
        32,
        gas_limit,
    );

    if (result.status != 0) {
        return error.PrecompileError;
    }

    return result.gas_used;
}
