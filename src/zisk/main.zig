/// Zisk zkVM support module
///
/// This module provides runtime support for programs running on the Zisk zkVM:
/// - ZiskAllocator: Memory allocation using Zisk's sys_alloc_aligned
/// - BumpAllocator: Simple bump allocator for fixed buffers
/// - ArenaAllocator: Resettable bump allocator
/// - Ecall stubs: Placeholder ecalls for compatibility (not used by Zisk)

pub const allocator = @import("allocator.zig");
pub const ecalls = @import("ecalls.zig");

// Re-export commonly used types
pub const ZiskAllocator = allocator.ZiskAllocator;
pub const BumpAllocator = allocator.BumpAllocator;
pub const ArenaAllocator = allocator.ArenaAllocator;
pub const FixedBufferAllocator = allocator.FixedBufferAllocator;

pub const SyscallNum = ecalls.SyscallNum;
pub const EcallResult = ecalls.EcallResult;

// Re-export ecall functions
pub const keccak256Ecall = ecalls.keccak256Ecall;
pub const sha256Ecall = ecalls.sha256Ecall;
pub const ecrecoverEcall = ecalls.ecrecoverEcall;
pub const bn256AddEcall = ecalls.bn256AddEcall;
pub const bn256MulEcall = ecalls.bn256MulEcall;
pub const bn256PairingEcall = ecalls.bn256PairingEcall;
pub const blake2fEcall = ecalls.blake2fEcall;
pub const modexpEcall = ecalls.modexpEcall;
pub const bls12G1AddEcall = ecalls.bls12G1AddEcall;
pub const bls12G1MulEcall = ecalls.bls12G1MulEcall;
pub const bls12G1MsmEcall = ecalls.bls12G1MsmEcall;
pub const bls12G2AddEcall = ecalls.bls12G2AddEcall;
pub const bls12G2MulEcall = ecalls.bls12G2MulEcall;
pub const bls12G2MsmEcall = ecalls.bls12G2MsmEcall;
pub const bls12PairingEcall = ecalls.bls12PairingEcall;
pub const bls12MapFpToG1Ecall = ecalls.bls12MapFpToG1Ecall;
pub const bls12MapFp2ToG2Ecall = ecalls.bls12MapFp2ToG2Ecall;
pub const kzgPointEvaluationEcall = ecalls.kzgPointEvaluationEcall;
pub const p256VerifyEcall = ecalls.p256VerifyEcall;
