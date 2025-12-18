/// EIP-196 and EIP-197 implementation for BN254 (alt_bn128) curve operations
/// Provides high-level functions that handle EIP format conversions and circuit selection

const std = @import("std");
const circuits = @import("zisk_circuits.zig");

/// Convert 32-byte big-endian scalar to [4]u64 little-endian limbs
fn scalarToLimbs(scalar_be: *const [32]u8) [4]u64 {
    var limbs: [4]u64 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        // Read 8 bytes from big-endian input in reverse order
        const offset = (3 - i) * 8;
        limbs[i] = std.mem.readInt(u64, scalar_be[offset..][0..8], .big);
    }
    return limbs;
}

/// Convert 32-byte big-endian coordinate to [4]u64 little-endian limbs
fn coordinateToLimbs(coord_be: *const [32]u8) [4]u64 {
    return scalarToLimbs(coord_be);
}

/// Convert [4]u64 little-endian limbs to 32-byte big-endian
fn limbsToCoordinate(limbs: [4]u64, coord_be: *[32]u8) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        const offset = (3 - i) * 8;
        std.mem.writeInt(u64, coord_be[offset..][0..8], limbs[i], .big);
    }
}

/// Check if two points are equal
fn pointsEqual(p1: *const [64]u8, p2: *const [64]u8) bool {
    return std.mem.eql(u8, p1, p2);
}

/// Check if point is at infinity (all zeros)
fn isInfinity(point: *const [64]u8) bool {
    for (point) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

/// EIP-196 ecAdd: Add two points on the BN254 curve
/// Input: p1 (64 bytes) and p2 (64 bytes) in big-endian format
/// Output: p1 + p2 (64 bytes) in big-endian format
/// Handles special cases:
/// - Point at infinity
/// - Adding a point to itself (uses doubling circuit)
/// - Adding inverse points (returns infinity)
///
/// TODO: this needs hardening since all points are assumed to be on the curve and in the correct subgroup
pub fn ecAdd(p1_be: *const [64]u8, p2_be: *const [64]u8, result_be: *[64]u8) void {
    // Convert inputs from big-endian to circuit format (little-endian limbs)
    var p1: [64]u8 align(8) = undefined;
    var p2: [64]u8 align(8) = undefined;

    // Convert x and y coordinates
    const p1_x_limbs = coordinateToLimbs(p1_be[0..32]);
    const p1_y_limbs = coordinateToLimbs(p1_be[32..64]);
    const p2_x_limbs = coordinateToLimbs(p2_be[0..32]);
    const p2_y_limbs = coordinateToLimbs(p2_be[32..64]);

    // Write limbs to circuit format (each u64 in little-endian)
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        std.mem.writeInt(u64, p1[i * 8 ..][0..8], p1_x_limbs[i], .little);
        std.mem.writeInt(u64, p1[32 + i * 8 ..][0..8], p1_y_limbs[i], .little);
        std.mem.writeInt(u64, p2[i * 8 ..][0..8], p2_x_limbs[i], .little);
        std.mem.writeInt(u64, p2[32 + i * 8 ..][0..8], p2_y_limbs[i], .little);
    }

    // Handle special cases
    if (isInfinity(&p1)) {
        // 0 + p2 = p2
        @memcpy(&p1, &p2);
    } else if (isInfinity(&p2)) {
        // p1 + 0 = p1 (p1 already has the result)
    } else if (pointsEqual(&p1, &p2)) {
        // p1 + p1 = 2*p1 (use doubling circuit)
        circuits.bn254CurveDouble(&p1);
    } else {
        // General case: use addition circuit
        // Check if x coordinates are equal but y coordinates differ (inverse points)
        const x_equal = std.mem.eql(u8, p1[0..32], p2[0..32]);
        const y_equal = std.mem.eql(u8, p1[32..64], p2[32..64]);

        if (x_equal and !y_equal) {
            // p1 + (-p1) = 0 (point at infinity)
            @memset(&p1, 0);
        } else {
            var points: [128]u8 align(8) = undefined;
            @memcpy(points[0..64], &p1);
            @memcpy(points[64..128], &p2);
            circuits.bn254CurveAdd(&points);
            @memcpy(&p1, points[0..64]);
        }
    }

    // Convert result back to big-endian
    var result_x_limbs: [4]u64 = undefined;
    var result_y_limbs: [4]u64 = undefined;
    i = 0;
    while (i < 4) : (i += 1) {
        result_x_limbs[i] = std.mem.readInt(u64, p1[i * 8 ..][0..8], .little);
        result_y_limbs[i] = std.mem.readInt(u64, p1[32 + i * 8 ..][0..8], .little);
    }

    limbsToCoordinate(result_x_limbs, result_be[0..32]);
    limbsToCoordinate(result_y_limbs, result_be[32..64]);
}

/// EIP-196 ecMul: Scalar multiplication k * P on the BN254 curve
/// Input: point (64 bytes) and scalar (32 bytes) in big-endian format
/// Output: k * P (64 bytes) in big-endian format
/// Uses double-and-add algorithm with hardware circuits
pub fn ecMul(point_be: *const [64]u8, scalar_be: *const [32]u8, result_be: *[64]u8) void {
    // Convert scalar to limbs
    const k = scalarToLimbs(scalar_be);

    // Convert point from big-endian to circuit format
    var point: [64]u8 align(8) = undefined;
    const x_limbs = coordinateToLimbs(point_be[0..32]);
    const y_limbs = coordinateToLimbs(point_be[32..64]);

    var i: usize = 0;
    while (i < 4) : (i += 1) {
        std.mem.writeInt(u64, point[i * 8 ..][0..8], x_limbs[i], .little);
        std.mem.writeInt(u64, point[32 + i * 8 ..][0..8], y_limbs[i], .little);
    }

    // Handle special cases
    const is_zero = k[0] == 0 and k[1] == 0 and k[2] == 0 and k[3] == 0;
    const is_one = k[0] == 1 and k[1] == 0 and k[2] == 0 and k[3] == 0;
    const is_two = k[0] == 2 and k[1] == 0 and k[2] == 0 and k[3] == 0;

    if (is_zero or isInfinity(&point)) {
        // 0 * P = 0 or k * 0 = 0 (point at infinity)
        @memset(result_be, 0);
        return;
    }

    if (is_one) {
        // 1 * P = P
        @memcpy(result_be, point_be);
        return;
    }

    if (is_two) {
        // 2 * P (just double)
        circuits.bn254CurveDouble(&point);
    } else {
        // General case: double-and-add algorithm
        // Find the most significant bit
        var max_limb: usize = 3;
        while (max_limb > 0 and k[max_limb] == 0) : (max_limb -= 1) {}

        var max_bit: u6 = 63;
        const test_val = k[max_limb];
        while (max_bit > 0 and (test_val >> max_bit) == 0) : (max_bit -= 1) {}

        // Copy original point for additions
        var p_orig: [64]u8 = undefined;
        @memcpy(&p_orig, &point);

        // Result starts at P (first bit is always 1)
        // Point already contains P

        // Process remaining bits using double-and-add
        var limb_idx: usize = max_limb;
        var first_iteration = true;

        while (true) {
            const start_bit: usize = if (limb_idx == max_limb) max_bit else 63;
            var bit_idx: usize = start_bit;

            while (true) {
                // Skip the first bit (MSB, already processed)
                if (first_iteration and bit_idx == start_bit) {
                    first_iteration = false;
                    if (bit_idx == 0) break;
                    bit_idx -= 1;
                    continue;
                }

                // Always double
                circuits.bn254CurveDouble(&point);

                // If bit is set, add original point
                if (((k[limb_idx] >> @intCast(bit_idx)) & 1) == 1) {
                    var points: [128]u8 align(8) = undefined;
                    @memcpy(points[0..64], &point);
                    @memcpy(points[64..128], &p_orig);
                    circuits.bn254CurveAdd(&points);
                    @memcpy(&point, points[0..64]);
                }

                if (bit_idx == 0) break;
                bit_idx -= 1;
            }

            if (limb_idx == 0) break;
            limb_idx -= 1;
        }
    }

    // Convert result back to big-endian
    var result_x_limbs: [4]u64 = undefined;
    var result_y_limbs: [4]u64 = undefined;
    i = 0;
    while (i < 4) : (i += 1) {
        result_x_limbs[i] = std.mem.readInt(u64, point[i * 8 ..][0..8], .little);
        result_y_limbs[i] = std.mem.readInt(u64, point[32 + i * 8 ..][0..8], .little);
    }

    limbsToCoordinate(result_x_limbs, result_be[0..32]);
    limbsToCoordinate(result_y_limbs, result_be[32..64]);
}

/// EIP-197 ecPairing: Pairing check for BN254 curve
/// Note: Zisk does not currently provide hardware-accelerated pairing circuits.
/// This would need to be implemented using the Fp2 complex field operations
/// and Fp12 tower field arithmetic, which is computationally expensive.
/// For now, this is left unimplemented.
pub fn ecPairing(input: []const u8, result: *[32]u8) !void {
    _ = input;
    _ = result;
    return error.NotImplemented;
}
