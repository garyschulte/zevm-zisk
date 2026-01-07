/// Zisk zkVM Hardware-Accelerated Circuits via CSR Instructions
///
/// Zisk implements cryptographic and arithmetic operations as hardware-accelerated
/// circuits accessible via CSR (Control and Status Register) instructions.
/// Each circuit has a dedicated CSR address in the 0x800-0x8FF range.
///
/// Usage pattern:
/// ```zig
/// var data: [128]u8 = ...;  // Input data
/// zisk.bn254CurveAdd(&data);  // Result overwrites input
/// ```
const std = @import("std");

/// Zisk circuit CSR addresses
pub const CircuitCSR = enum(u16) {
    // Basic cryptographic operations
    keccakf = 0x800, // Keccak-f[1600] permutation
    arith256 = 0x801, // 256-bit mul+add
    arith256_mod = 0x802, // 256-bit modular mul+add

    // Secp256k1 elliptic curve operations
    secp256k1_add = 0x803, // Secp256k1 point addition
    secp256k1_dbl = 0x804, // Secp256k1 point doubling

    // SHA-256
    sha256f = 0x805, // SHA-256 compress function

    // BN254 (alt_bn128) elliptic curve operations
    bn254_curve_add = 0x806, // BN254 G1 point addition
    bn254_curve_dbl = 0x807, // BN254 G1 point doubling
    bn254_complex_add = 0x808, // BN254 Fp2 complex field addition
    bn254_complex_sub = 0x809, // BN254 Fp2 complex field subtraction
    bn254_complex_mul = 0x80A, // BN254 Fp2 complex field multiplication

    // Higher precision arithmetic
    arith384_mod = 0x80B, // 384-bit modular operations

    // BLS12-381 elliptic curve operations
    bls12_381_curve_add = 0x80C, // BLS12-381 G1 point addition
    bls12_381_curve_dbl = 0x80D, // BLS12-381 G1 point doubling
    bls12_381_complex_add = 0x80E, // BLS12-381 Fp2 complex field addition
    bls12_381_complex_sub = 0x80F, // BLS12-381 Fp2 complex field subtraction
    bls12_381_complex_mul = 0x810, // BLS12-381 Fp2 complex field multiplication

    // Additional operations
    add256 = 0x811, // 256-bit addition
};

// ============================================================================
// Basic Cryptographic Operations
// ============================================================================

/// Keccak-f[1600] permutation circuit
/// Input/output: 200 bytes (25 x 64-bit words)
/// Result overwrites input in-place
pub fn keccakf(state: *[200]u8) void {
    const state_ptr = @intFromPtr(state);
    asm volatile ("csrs 0x800, %[ptr]"
        :
        : [ptr] "r" (state_ptr),
        : .{ .memory = true }
    );
}

/// SHA-256 compression function circuit
/// Input: 96 bytes (64-byte message block + 32-byte state)
/// Output: 32 bytes new state (overwrites first 32 bytes of input)
pub fn sha256Compress(block_and_state: *[96]u8) void {
    const ptr = @intFromPtr(block_and_state);
    asm volatile ("csrs 0x805, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

// ============================================================================
// Secp256k1 Elliptic Curve Operations
// ============================================================================

/// Secp256k1 point addition circuit: P1 + P2 = P3
/// Input: 128 bytes (P1: 64 bytes, P2: 64 bytes)
/// Output: 64 bytes (P3, overwrites first 64 bytes of input)
pub fn secp256k1Add(points: *[128]u8) void {
    const ptr = @intFromPtr(points);
    asm volatile ("csrs 0x803, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// Secp256k1 point doubling circuit: 2 * P = P'
/// Input/Output: 64 bytes (point to double, result overwrites input)
pub fn secp256k1Double(point: *[64]u8) void {
    const ptr = @intFromPtr(point);
    asm volatile ("csrs 0x804, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

// ============================================================================
// BN254 (alt_bn128) Elliptic Curve Operations
// ============================================================================

/// Point256 structure matching Rust/Go SyscallPoint256
pub const Point256 = extern struct {
    x: [4]u64,
    y: [4]u64,
};

/// BN254 curve add params structure
pub const Bn254CurveAddParams = extern struct {
    p1: *Point256,
    p2: *Point256,
};

/// Fp2 element (64 bytes = 2 field elements of 32 bytes each)
pub const Fp2Element = extern struct {
    data: [64]u8,
};

/// BN254 Fp2 binary operation params structure
pub const Bn254Fp2BinaryOpParams = extern struct {
    e1: *Fp2Element,
    e2: *Fp2Element,
};

/// BN254 G1 curve point addition circuit: P1 + P2 = P3
/// Input: 128 bytes (P1: 64 bytes, P2: 64 bytes)
/// Output: 64 bytes (P3, overwrites first 64 bytes of input)
pub fn bn254CurveAdd(points: *[128]u8) void {
    // Cast byte array to Point256 pointers
    const p1: *Point256 = @ptrCast(@alignCast(points[0..64]));
    const p2: *Point256 = @ptrCast(@alignCast(points[64..128]));

    // Create params structure
    var params = Bn254CurveAddParams{
        .p1 = p1,
        .p2 = p2,
    };

    const params_ptr = @intFromPtr(&params);
    asm volatile ("csrs 0x806, %[ptr]"
        :
        : [ptr] "r" (params_ptr),
        : .{ .memory = true }
    );
}

/// BN254 G1 curve point doubling circuit: 2 * P = P'
/// Input/Output: 64 bytes (point to double, result overwrites input)
pub fn bn254CurveDouble(point: *[64]u8) void {
    const p: *Point256 = @ptrCast(@alignCast(point));
    const ptr = @intFromPtr(p);
    asm volatile ("csrs 0x807, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// BN254 Fp2 complex field addition circuit: (a + bi) + (c + di)
/// Input: 128 bytes (first complex: 64 bytes, second complex: 64 bytes)
/// Output: 64 bytes (result, overwrites first 64 bytes of input)
pub fn bn254ComplexAdd(elements: *[128]u8) void {
    const e1: *Fp2Element = @ptrCast(@alignCast(elements[0..64]));
    const e2: *Fp2Element = @ptrCast(@alignCast(elements[64..128]));

    var params = Bn254Fp2BinaryOpParams{
        .e1 = e1,
        .e2 = e2,
    };

    const params_ptr = @intFromPtr(&params);
    asm volatile ("csrs 0x808, %[ptr]"
        :
        : [ptr] "r" (params_ptr),
        : .{ .memory = true }
    );
}

/// BN254 Fp2 complex field subtraction circuit: (a + bi) - (c + di)
/// Input: 128 bytes (first complex: 64 bytes, second complex: 64 bytes)
/// Output: 64 bytes (result, overwrites first 64 bytes of input)
pub fn bn254ComplexSub(elements: *[128]u8) void {
    const e1: *Fp2Element = @ptrCast(@alignCast(elements[0..64]));
    const e2: *Fp2Element = @ptrCast(@alignCast(elements[64..128]));

    var params = Bn254Fp2BinaryOpParams{
        .e1 = e1,
        .e2 = e2,
    };

    const params_ptr = @intFromPtr(&params);
    asm volatile ("csrs 0x809, %[ptr]"
        :
        : [ptr] "r" (params_ptr),
        : .{ .memory = true }
    );
}

/// BN254 Fp2 complex field multiplication circuit: (a + bi) * (c + di)
/// Input: 128 bytes (first complex: 64 bytes, second complex: 64 bytes)
/// Output: 64 bytes (result, overwrites first 64 bytes of input)
pub fn bn254ComplexMul(elements: *[128]u8) void {
    const e1: *Fp2Element = @ptrCast(@alignCast(elements[0..64]));
    const e2: *Fp2Element = @ptrCast(@alignCast(elements[64..128]));

    var params = Bn254Fp2BinaryOpParams{
        .e1 = e1,
        .e2 = e2,
    };

    const params_ptr = @intFromPtr(&params);
    asm volatile ("csrs 0x80A, %[ptr]"
        :
        : [ptr] "r" (params_ptr),
        : .{ .memory = true }
    );
}

/// BN254 pairing check: verifies e(P1, Q1) * e(P2, Q2) * ... = 1
/// Uses software pairing with Fp2 hardware circuits (CSR 0x808, 0x809, 0x80A)
///
/// Input format (EIP-197):
/// - Each pair: G1 point (64 bytes) + G2 point (128 bytes) = 192 bytes total
/// - Multiple pairs concatenated
/// - All coordinates in little-endian u64 limbs
///
/// Returns: true if pairing product equals 1, false otherwise
///
/// Implementation: Software Miller loop and final exponentiation that maximally
/// utilizes Fp2 hardware circuits for the performance-critical operations.
pub fn bn254PairingCheck(pairs_data: []const u8, allocator: std.mem.Allocator) !bool {
    const pairing_impl = @import("bn254_pairing.zig");

    // Validate input length
    if (pairs_data.len % 192 != 0) {
        return error.InvalidPairingInput;
    }

    const num_pairs = pairs_data.len / 192;
    if (num_pairs == 0) {
        // Empty pairing returns true (identity)
        return true;
    }

    // Parse pairs into the format expected by pairingCheck
    const pairs = try allocator.alloc(pairing_impl.Pair, num_pairs);
    defer allocator.free(pairs);

    var i: usize = 0;
    while (i < num_pairs) : (i += 1) {
        const pair_offset = i * 192;

        // Parse G1 point (64 bytes, little-endian limbs)
        @memcpy(&pairs[i].p.data, pairs_data[pair_offset .. pair_offset + 64]);

        // Parse G2 point (128 bytes, little-endian limbs)
        // G2 point has x and y, each is Fp2 (64 bytes)
        @memcpy(&pairs[i].q.x.data, pairs_data[pair_offset + 64 .. pair_offset + 128]);
        @memcpy(&pairs[i].q.y.data, pairs_data[pair_offset + 128 .. pair_offset + 192]);
    }

    // Perform pairing check using software implementation with Fp2 circuits
    return pairing_impl.pairingCheck(pairs);
}

// ============================================================================
// BLS12-381 Elliptic Curve Operations
// ============================================================================

/// BLS12-381 G1 curve point addition circuit: P1 + P2 = P3
/// Input: 192 bytes (P1: 96 bytes, P2: 96 bytes)
/// Output: 96 bytes (P3, overwrites first 96 bytes of input)
pub fn bls12_381CurveAdd(points: *[192]u8) void {
    const ptr = @intFromPtr(points);
    asm volatile ("csrs 0x80C, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// BLS12-381 G1 curve point doubling circuit: 2 * P = P'
/// Input/Output: 96 bytes (point to double, result overwrites input)
pub fn bls12_381CurveDouble(point: *[96]u8) void {
    const ptr = @intFromPtr(point);
    asm volatile ("csrs 0x80D, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// BLS12-381 Fp2 complex field addition circuit: (a + bi) + (c + di)
/// Input: 192 bytes (first complex: 96 bytes, second complex: 96 bytes)
/// Output: 96 bytes (result, overwrites first 96 bytes of input)
pub fn bls12_381ComplexAdd(elements: *[192]u8) void {
    const ptr = @intFromPtr(elements);
    asm volatile ("csrs 0x80E, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// BLS12-381 Fp2 complex field subtraction circuit: (a + bi) - (c + di)
/// Input: 192 bytes (first complex: 96 bytes, second complex: 96 bytes)
/// Output: 96 bytes (result, overwrites first 96 bytes of input)
pub fn bls12_381ComplexSub(elements: *[192]u8) void {
    const ptr = @intFromPtr(elements);
    asm volatile ("csrs 0x80F, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// BLS12-381 Fp2 complex field multiplication circuit: (a + bi) * (c + di)
/// Input: 192 bytes (first complex: 96 bytes, second complex: 96 bytes)
/// Output: 96 bytes (result, overwrites first 96 bytes of input)
pub fn bls12_381ComplexMul(elements: *[192]u8) void {
    const ptr = @intFromPtr(elements);
    asm volatile ("csrs 0x810, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

// ============================================================================
// Arithmetic Operations
// ============================================================================

/// 256-bit arithmetic circuit: result = (a * b + c) mod 2^256
/// Input: 96 bytes (a: 32 bytes, b: 32 bytes, c: 32 bytes)
/// Output: 32 bytes (result, overwrites first 32 bytes of input)
pub fn arith256(input: *[96]u8) void {
    const ptr = @intFromPtr(input);
    asm volatile ("csrs 0x801, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// 256-bit modular arithmetic circuit: result = (a * b + c) mod m
/// Input: 128 bytes (a: 32, b: 32, c: 32, m: 32)
/// Output: 32 bytes (result, overwrites first 32 bytes of input)
pub fn arith256Mod(input: *[128]u8) void {
    const ptr = @intFromPtr(input);
    asm volatile ("csrs 0x802, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// 384-bit modular arithmetic circuit
/// Input: 192 bytes (a: 48, b: 48, c: 48, m: 48)
/// Output: 48 bytes (result, overwrites first 48 bytes of input)
pub fn arith384Mod(input: *[192]u8) void {
    const ptr = @intFromPtr(input);
    asm volatile ("csrs 0x80B, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}

/// 256-bit addition circuit: result = a + b
/// Input: 64 bytes (a: 32 bytes, b: 32 bytes)
/// Output: 32 bytes (result, overwrites first 32 bytes of input)
pub fn add256(input: *[64]u8) void {
    const ptr = @intFromPtr(input);
    asm volatile ("csrs 0x811, %[ptr]"
        :
        : [ptr] "r" (ptr),
        : .{ .memory = true }
    );
}
