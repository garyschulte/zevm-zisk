/// Zisk zkVM support module
///
/// This module provides runtime support for programs running on the Zisk zkVM:
/// - ZiskAllocator: Memory allocation using Zisk's sys_alloc_aligned
/// - BumpAllocator: Simple bump allocator for fixed buffers
/// - ArenaAllocator: Resettable bump allocator
/// - Hardware-accelerated circuits via CSR instructions

pub const allocator = @import("allocator.zig");
pub const circuits = @import("zisk_circuits.zig");
pub const eip196 = @import("eip196.zig");
pub const bn254_pairing = @import("bn254_pairing.zig");

// Re-export commonly used allocator types
pub const ZiskAllocator = allocator.ZiskAllocator;
pub const BumpAllocator = allocator.BumpAllocator;
pub const ArenaAllocator = allocator.ArenaAllocator;
pub const FixedBufferAllocator = allocator.FixedBufferAllocator;

// Re-export circuit CSR addresses
pub const CircuitCSR = circuits.CircuitCSR;

// Re-export cryptographic circuit functions
pub const keccakf = circuits.keccakf;
pub const sha256Compress = circuits.sha256Compress;

// Re-export elliptic curve circuit functions
pub const secp256k1Add = circuits.secp256k1Add;
pub const secp256k1Double = circuits.secp256k1Double;

pub const bn254CurveAdd = circuits.bn254CurveAdd;
pub const bn254CurveDouble = circuits.bn254CurveDouble;
pub const bn254ComplexAdd = circuits.bn254ComplexAdd;
pub const bn254ComplexSub = circuits.bn254ComplexSub;
pub const bn254ComplexMul = circuits.bn254ComplexMul;

pub const bls12_381CurveAdd = circuits.bls12_381CurveAdd;
pub const bls12_381CurveDouble = circuits.bls12_381CurveDouble;
pub const bls12_381ComplexAdd = circuits.bls12_381ComplexAdd;
pub const bls12_381ComplexSub = circuits.bls12_381ComplexSub;
pub const bls12_381ComplexMul = circuits.bls12_381ComplexMul;

// Re-export arithmetic circuit functions
pub const arith256 = circuits.arith256;
pub const arith256Mod = circuits.arith256Mod;
pub const arith384Mod = circuits.arith384Mod;
pub const add256 = circuits.add256;
