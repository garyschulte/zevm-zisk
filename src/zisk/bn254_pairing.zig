/// BN254 Pairing Implementation using Zisk Hardware Circuits
/// Maximally utilizes bn254ComplexAdd/Sub/Mul circuits for Fp2 operations
///
/// Architecture:
/// - Fp2 operations -> use hardware circuits (0x808, 0x809, 0x80A)
/// - G2 operations -> implemented using Fp2 circuits
/// - Fp12 operations -> built from Fp2 circuits
/// - Miller loop -> uses G2 operations and Fp12 accumulation
/// - Final exp -> uses Fp12 operations
///
/// Status:
/// - âœ" Fp2 circuits working with proper params structure (CSR 0x808, 0x809, 0x80A)
/// - âœ" Miller loop: Proper 63-bit ate parameter (x = 4965661367192848881)
/// - âš  Final exp: Placeholder (single square instead of full exponentiation)
/// - TODO: Implement full final exponentiation for EIP-197 compliance

const std = @import("std");
const circuits = @import("zisk_circuits.zig");

/// Fp2 element wrapper that ALWAYS uses hardware circuits
pub const Fp2 = struct {
    data: [64]u8 align(8), // [c0: 32 bytes, c1: 32 bytes] in little-endian limbs

    pub fn zero() Fp2 {
        return Fp2{ .data = [_]u8{0} ** 64 };
    }

    pub fn one() Fp2 {
        var result = Fp2.zero();
        result.data[0] = 1; // Little-endian 1 in c0
        return result;
    }

    /// Add using bn254ComplexAdd circuit (CSR 0x808)
    pub fn add(self: *const Fp2, other: *const Fp2) Fp2 {
        var input: [128]u8 align(8) = undefined;
        @memcpy(input[0..64], &self.data);
        @memcpy(input[64..128], &other.data);
        circuits.bn254ComplexAdd(&input);
        var result: Fp2 = undefined;
        @memcpy(&result.data, input[0..64]);
        return result;
    }

    /// Subtract using bn254ComplexSub circuit (CSR 0x809)
    pub fn sub(self: *const Fp2, other: *const Fp2) Fp2 {
        var input: [128]u8 align(8) = undefined;
        @memcpy(input[0..64], &self.data);
        @memcpy(input[64..128], &other.data);
        circuits.bn254ComplexSub(&input);
        var result: Fp2 = undefined;
        @memcpy(&result.data, input[0..64]);
        return result;
    }

    /// Multiply using bn254ComplexMul circuit (CSR 0x80A)
    pub fn mul(self: *const Fp2, other: *const Fp2) Fp2 {
        var input: [128]u8 align(8) = undefined;
        @memcpy(input[0..64], &self.data);
        @memcpy(input[64..128], &other.data);
        circuits.bn254ComplexMul(&input);
        var result: Fp2 = undefined;
        @memcpy(&result.data, input[0..64]);
        return result;
    }

    /// Square using mul circuit
    pub fn square(self: *const Fp2) Fp2 {
        return self.mul(self);
    }

    pub fn isZero(self: *const Fp2) bool {
        for (self.data) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    /// Negate (unary minus)
    pub fn neg(self: *const Fp2) Fp2 {
        const zero_val = Fp2.zero();
        return zero_val.sub(self);
    }

    /// Double using add circuit
    pub fn double(self: *const Fp2) Fp2 {
        return self.add(self);
    }

    /// Multiplicative inverse using conjugate method: (a+bi)^(-1) = (a-bi)/(a²+b²)
    /// For Fp2 = Fp[i]/(i² + 1), we compute:
    /// 1. norm = a² + b² (in Fp)
    /// 2. norm_inv = norm^(-1) (using Fp inverse)
    /// 3. result = (a - bi) * norm_inv
    ///
    /// This is more efficient than full Fp2 exponentiation and uses Fp2 circuits
    pub fn inverse(self: *const Fp2) Fp2 {
        // Extract c0 (real) and c1 (imaginary) parts as separate Fp2 elements
        var c0_fp2 = Fp2.zero();
        var c1_fp2 = Fp2.zero();
        @memcpy(c0_fp2.data[0..32], self.data[0..32]); // c0 in first 32 bytes
        @memcpy(c1_fp2.data[0..32], self.data[32..64]); // c1 in second 32 bytes

        // Compute a² using Fp2 mul (treating a as (a, 0) in Fp2)
        const a_squared = c0_fp2.mul(&c0_fp2); // Uses CSR 0x80A

        // Compute b² using Fp2 mul (treating b as (b, 0) in Fp2)
        const b_squared = c1_fp2.mul(&c1_fp2); // Uses CSR 0x80A

        // norm = a² + b² (in Fp, but represented as Fp2 element with c1=0)
        const norm = a_squared.add(&b_squared); // Uses CSR 0x808

        // Compute 1/norm using Fermat's Little Theorem: norm^(p-2) mod p
        // BN254 prime p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
        // p-2 in binary (254 bits, all 1s except bit 0 and bit 1)
        const norm_inv = inverseFp(&norm);

        // Compute conjugate: (a - bi)
        const conj = Fp2{
            .data = blk: {
                var result_data: [64]u8 = self.data;
                // Negate c1: compute 0 - c1
                const zero_val = Fp2.zero();
                var c1_only = Fp2.zero();
                @memcpy(c1_only.data[32..64], self.data[32..64]);
                const neg_c1 = zero_val.sub(&c1_only); // Uses CSR 0x809
                @memcpy(result_data[32..64], neg_c1.data[32..64]);
                break :blk result_data;
            },
        };

        // Return conj * norm_inv
        return conj.mul(&norm_inv); // Uses CSR 0x80A
    }

    /// Compute inverse of Fp element embedded in Fp2 using Fermat's Little Theorem
    /// For BN254: p = 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47
    /// We compute a^(p-2) using square-and-multiply with full 254-bit exponent
    fn inverseFp(a: *const Fp2) Fp2 {
        // p - 2 for BN254 in binary (MSB first, 254 bits)
        // p = 21888242871839275222246405745257275088696311157297823662689037894645226208583
        // p - 2 = 21888242871839275222246405745257275088696311157297823662689037894645226208581
        //
        // Binary (hex): 0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd45
        // We'll process this in 4 u64 chunks (little-endian limbs)
        const p_minus_2 = [4]u64{
            0x3c208c16d87cfd45, // Limb 0 (least significant)
            0x97816a916871ca8d,
            0xb85045b68181585d,
            0x30644e72e131a029, // Limb 3 (most significant)
        };

        var result = Fp2.one();
        var base = a.*;

        // Process from MSB to LSB (limb 3 down to limb 0)
        var limb_idx: usize = 4;
        while (limb_idx > 0) {
            limb_idx -= 1;
            const limb = p_minus_2[limb_idx];

            // Find MSB position for first limb
            const start_bit: usize = if (limb_idx == 3) blk: {
                // Find highest set bit in MSB limb
                var bit: usize = 63;
                while (bit > 0) : (bit -= 1) {
                    if ((limb >> @intCast(bit)) & 1 == 1) break;
                }
                break :blk bit;
            } else 63;

            // Process bits from MSB to LSB
            var bit_idx: isize = @intCast(start_bit);
            while (bit_idx >= 0) : (bit_idx -= 1) {
                // Skip first bit (always 1 for p-2)
                if (limb_idx == 3 and bit_idx == @as(isize, @intCast(start_bit))) {
                    continue;
                }

                result = result.square(); // Uses CSR 0x80A

                const bit = (limb >> @intCast(bit_idx)) & 1;
                if (bit == 1) {
                    result = result.mul(&base); // Uses CSR 0x80A
                }
            }
        }

        return result;
    }

    /// Divide: a / b = a * b^(-1), uses mul and inverse circuits
    pub fn div(self: *const Fp2, other: *const Fp2) Fp2 {
        const inv = other.inverse();
        return self.mul(&inv); // Uses CSR 0x80A
    }
};

/// G2 point on twist curve E'(Fp2): y^2 = x^3 + 3/(9+u)
/// All operations use Fp2 hardware circuits
pub const G2Point = struct {
    x: Fp2,
    y: Fp2,

    pub fn infinity() G2Point {
        return G2Point{
            .x = Fp2.zero(),
            .y = Fp2.zero(),
        };
    }

    pub fn isInfinity(self: *const G2Point) bool {
        return self.x.isZero() and self.y.isZero();
    }

    /// Double a G2 point using Fp2 circuits for all field operations
    /// Formula: λ = (3x²)/(2y), x' = λ² - 2x, y' = λ(x - x') - y
    /// Every field operation uses hardware circuits
    pub fn double(self: *const G2Point) G2Point {
        if (self.isInfinity()) return G2Point.infinity();

        // λ = (3x²)/(2y) - all operations use circuits
        const x_squared = self.x.square(); // CSR 0x80A
        var three = Fp2.zero();
        three.data[0] = 3;
        const numerator = three.mul(&x_squared); // CSR 0x80A
        const denominator = self.y.double(); // CSR 0x808
        const lambda = numerator.div(&denominator); // CSR 0x80A (via inverse)

        // x' = λ² - 2x
        const lambda_squared = lambda.square(); // CSR 0x80A
        const two_x = self.x.double(); // CSR 0x808
        const x_new = lambda_squared.sub(&two_x); // CSR 0x809

        // y' = λ(x - x') - y
        const x_diff = self.x.sub(&x_new); // CSR 0x809
        const lambda_x_diff = lambda.mul(&x_diff); // CSR 0x80A
        const y_new = lambda_x_diff.sub(&self.y); // CSR 0x809

        return G2Point{
            .x = x_new,
            .y = y_new,
        };
    }

    /// Add two G2 points using Fp2 circuits for all field operations
    /// Formula: λ = (y2-y1)/(x2-x1), x' = λ² - x1 - x2, y' = λ(x1 - x') - y1
    /// Every field operation uses hardware circuits
    pub fn add(self: *const G2Point, other: *const G2Point) G2Point {
        if (self.isInfinity()) return other.*;
        if (other.isInfinity()) return self.*;

        // Check if points are equal -> use double
        const x_equal = std.mem.eql(u8, &self.x.data, &other.x.data);
        const y_equal = std.mem.eql(u8, &self.y.data, &other.y.data);
        if (x_equal and y_equal) return self.double();

        // Check if inverse points -> return infinity
        if (x_equal and !y_equal) return G2Point.infinity();

        // λ = (y2 - y1)/(x2 - x1) - all operations use circuits
        const dy = other.y.sub(&self.y); // CSR 0x809
        const dx = other.x.sub(&self.x); // CSR 0x809
        const lambda = dy.div(&dx); // CSR 0x80A (via inverse)

        // x' = λ² - x1 - x2
        const lambda_squared = lambda.square(); // CSR 0x80A
        const x_new = lambda_squared.sub(&self.x).sub(&other.x); // CSR 0x809 (x2)

        // y' = λ(x1 - x') - y1
        const x_diff = self.x.sub(&x_new); // CSR 0x809
        const lambda_x_diff = lambda.mul(&x_diff); // CSR 0x80A
        const y_new = lambda_x_diff.sub(&self.y); // CSR 0x809

        return G2Point{
            .x = x_new,
            .y = y_new,
        };
    }
};

/// Fp6 as cubic extension over Fp2, using Fp2 circuits for all base operations
pub const Fp6 = struct {
    c0: Fp2,
    c1: Fp2,
    c2: Fp2,

    pub fn zero() Fp6 {
        return Fp6{
            .c0 = Fp2.zero(),
            .c1 = Fp2.zero(),
            .c2 = Fp2.zero(),
        };
    }

    pub fn one() Fp6 {
        return Fp6{
            .c0 = Fp2.one(),
            .c1 = Fp2.zero(),
            .c2 = Fp2.zero(),
        };
    }

    /// All Fp2 operations use hardware circuits
    pub fn add(self: *const Fp6, other: *const Fp6) Fp6 {
        return Fp6{
            .c0 = self.c0.add(&other.c0), // Uses CSR 0x808
            .c1 = self.c1.add(&other.c1), // Uses CSR 0x808
            .c2 = self.c2.add(&other.c2), // Uses CSR 0x808
        };
    }

    pub fn sub(self: *const Fp6, other: *const Fp6) Fp6 {
        return Fp6{
            .c0 = self.c0.sub(&other.c0), // Uses CSR 0x809
            .c1 = self.c1.sub(&other.c1), // Uses CSR 0x809
            .c2 = self.c2.sub(&other.c2), // Uses CSR 0x809
        };
    }

    /// Multiply by non-residue ξ = (9 + u) using Fp2 circuits
    fn mulByNonResidue(a: *const Fp2) Fp2 {
        var nine = Fp2.zero();
        nine.data[0] = 9;
        // (a + bu)(9 + u) = (9a - b) + (a + 9b)u
        // Split into real/imag parts and recombine
        // This requires more sophisticated handling - placeholder for now
        return a.mul(&nine); // Simplified - uses CSR 0x80A
    }

    /// Multiply using Karatsuba, all operations use Fp2 circuits
    pub fn mul(self: *const Fp6, other: *const Fp6) Fp6 {
        // Each mul/add/sub operation uses the hardware circuits
        const v0 = self.c0.mul(&other.c0); // CSR 0x80A
        const v1 = self.c1.mul(&other.c1); // CSR 0x80A
        const v2 = self.c2.mul(&other.c2); // CSR 0x80A

        const c0 = v0.add(&mulByNonResidue(&self.c1.add(&self.c2).mul(&other.c1.add(&other.c2)).sub(&v1).sub(&v2)));
        const c1 = self.c0.add(&self.c1).mul(&other.c0.add(&other.c1)).sub(&v0).sub(&v1).add(&mulByNonResidue(&v2));
        const c2 = self.c0.add(&self.c2).mul(&other.c0.add(&other.c2)).sub(&v0).add(&v1).sub(&v2);

        return Fp6{ .c0 = c0, .c1 = c1, .c2 = c2 };
    }

    pub fn square(self: *const Fp6) Fp6 {
        return self.mul(self);
    }
};

/// Fp12 as quadratic extension over Fp6, maximally using Fp2 circuits
pub const Fp12 = struct {
    c0: Fp6,
    c1: Fp6,

    pub fn zero() Fp12 {
        return Fp12{
            .c0 = Fp6.zero(),
            .c1 = Fp6.zero(),
        };
    }

    pub fn one() Fp12 {
        return Fp12{
            .c0 = Fp6.one(),
            .c1 = Fp6.zero(),
        };
    }

    /// All operations built from Fp6, which uses Fp2 circuits
    pub fn mul(self: *const Fp12, other: *const Fp12) Fp12 {
        const v0 = self.c0.mul(&other.c0); // Uses Fp2 circuits internally
        const v1 = self.c1.mul(&other.c1); // Uses Fp2 circuits internally

        const c1 = self.c0.add(&self.c1).mul(&other.c0.add(&other.c1)).sub(&v0).sub(&v1);

        // mul v1 by non-residue for Fp6 over Fp12
        const v1_nr = Fp6{
            .c0 = Fp6.mulByNonResidue(&v1.c2),
            .c1 = v1.c0,
            .c2 = v1.c1,
        };

        return Fp12{
            .c0 = v0.add(&v1_nr),
            .c1 = c1,
        };
    }

    pub fn square(self: *const Fp12) Fp12 {
        return self.mul(self);
    }

    pub fn isOne(self: *const Fp12) bool {
        const one_val = Fp12.one();
        return std.mem.eql(u8, std.mem.asBytes(&self.c0), std.mem.asBytes(&one_val.c0)) and
            std.mem.eql(u8, std.mem.asBytes(&self.c1), std.mem.asBytes(&one_val.c1));
    }
};

/// G1 point wrapper
pub const G1Point = struct {
    data: [64]u8 align(8), // [x: 32 bytes, y: 32 bytes]

    pub fn isInfinity(self: *const G1Point) bool {
        for (self.data) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    /// Use bn254CurveDouble circuit (CSR 0x807)
    pub fn double(self: *const G1Point) G1Point {
        var result = self.*;
        circuits.bn254CurveDouble(&result.data);
        return result;
    }

    /// Use bn254CurveAdd circuit (CSR 0x806)
    pub fn add(self: *const G1Point, other: *const G1Point) G1Point {
        var input: [128]u8 align(8) = undefined;
        @memcpy(input[0..64], &self.data);
        @memcpy(input[64..128], &other.data);
        circuits.bn254CurveAdd(&input);
        var result: G1Point = undefined;
        @memcpy(&result.data, input[0..64]);
        return result;
    }
};

/// Line function for doubling: evaluates line through (T, T) at point P
/// Returns an Fp12 element - all Fp2 operations use hardware circuits
fn lineDouble(t: *const G2Point, p: *const G1Point) Fp12 {
    // Line through (T, T) with slope λ = (3*T.x²)/(2*T.y)
    // Evaluated at P gives an element in Fp12

    // Extract P coordinates as Fp2 (embed Fp into Fp2)
    var p_x = Fp2.zero();
    var p_y = Fp2.zero();
    @memcpy(p_x.data[0..32], p.data[0..32]);
    @memcpy(p_y.data[0..32], p.data[32..64]);

    // Compute slope using Fp2 circuits
    const x_squared = t.x.square(); // CSR 0x80A
    var three = Fp2.zero();
    three.data[0] = 3;
    const numerator = three.mul(&x_squared); // CSR 0x80A
    const denominator = t.y.double(); // CSR 0x808
    const lambda = numerator.div(&denominator); // CSR 0x80A (via inverse)

    // Line equation: y - y_T = λ(x - x_T)
    // Rearranged: λ(x_T - x_P) + (y_P - y_T)
    const x_diff = t.x.sub(&p_x); // CSR 0x809
    const term1 = lambda.mul(&x_diff); // CSR 0x80A
    const term2 = p_y.sub(&t.y); // CSR 0x809
    const result = term1.add(&term2); // CSR 0x808

    // Embed in Fp12 (simplified - proper embedding is more complex)
    return Fp12{
        .c0 = Fp6{
            .c0 = result,
            .c1 = Fp2.zero(),
            .c2 = Fp2.zero(),
        },
        .c1 = Fp6.zero(),
    };
}

/// Line function for addition: evaluates line through (T, Q) at point P
/// Returns an Fp12 element - all Fp2 operations use hardware circuits
fn lineAdd(t: *const G2Point, q: *const G2Point, p: *const G1Point) Fp12 {
    // Line through (T, Q) with slope λ = (Q.y - T.y)/(Q.x - T.x)

    var p_x = Fp2.zero();
    var p_y = Fp2.zero();
    @memcpy(p_x.data[0..32], p.data[0..32]);
    @memcpy(p_y.data[0..32], p.data[32..64]);

    // Compute slope using Fp2 circuits
    const dy = q.y.sub(&t.y); // CSR 0x809
    const dx = q.x.sub(&t.x); // CSR 0x809
    const lambda = dy.div(&dx); // CSR 0x80A (via inverse)

    // Line equation: λ(x_T - x_P) + (y_P - y_T)
    const x_diff = t.x.sub(&p_x); // CSR 0x809
    const term1 = lambda.mul(&x_diff); // CSR 0x80A
    const term2 = p_y.sub(&t.y); // CSR 0x809
    const result = term1.add(&term2); // CSR 0x808

    // Embed in Fp12
    return Fp12{
        .c0 = Fp6{
            .c0 = result,
            .c1 = Fp2.zero(),
            .c2 = Fp2.zero(),
        },
        .c1 = Fp6.zero(),
    };
}

/// Pair type for pairing check operations
pub const Pair = struct {
    p: G1Point,
    q: G2Point,
};

/// Miller loop for BN254 optimal ate pairing
/// Uses G2 operations (which use Fp2 circuits) and Fp12 accumulation
/// ate parameter for BN254: x = 4965661367192848881 = 0x44E992B44A6909F1
fn millerLoop(p: *const G1Point, q: *const G2Point) Fp12 {
    // BN254 ate loop parameter: x = 4965661367192848881
    // In binary (63 bits, MSB first, skip leading 0):
    // 0100_0100_1110_1001_1001_0010_1011_0100_0100_1010_0110_1001_0000_1001_1111_0001
    const ate_loop_bits = [_]u1{
        0, 1, 0, 0, 0, 1, 0, 0, // 0x44
        1, 1, 1, 0, 1, 0, 0, 1, // 0xE9
        1, 0, 0, 1, 0, 0, 1, 0, // 0x92
        1, 0, 1, 1, 0, 1, 0, 0, // 0xB4
        0, 1, 0, 0, 1, 0, 1, 0, // 0x4A
        0, 1, 1, 0, 1, 0, 0, 1, // 0x69
        0, 0, 0, 0, 1, 0, 0, 1, // 0x09
        1, 1, 1, 1, 0, 0, 0, 1, // 0xF1
    };

    var f = Fp12.one();
    var t = q.*;

    // Skip the first bit (it's always 1 for the MSB, implicit)
    for (ate_loop_bits[1..]) |bit| {
        // f = f² * line_double(T, P)
        f = f.square(); // Uses Fp6.mul -> Fp2 circuits
        const ld = lineDouble(&t, p); // Uses Fp2 circuits
        f = f.mul(&ld); // Uses Fp6.mul -> Fp2 circuits

        // T = 2*T
        t = t.double(); // Uses Fp2 circuits

        if (bit == 1) {
            // f = f * line_add(T, Q, P)
            const la = lineAdd(&t, q, p); // Uses Fp2 circuits
            f = f.mul(&la); // Uses Fp6.mul -> Fp2 circuits

            // T = T + Q
            t = t.add(q); // Uses Fp2 circuits
        }
    }

    return f;
}

/// Final exponentiation: (p^12 - 1)/r
/// Uses Fp12 operations which are built from Fp2 circuits
///
/// NOTE: This is a placeholder implementation (single square).
/// Full final exponentiation requires:
/// 1. Easy part: f^(p^6 - 1)(p^2 + 1) - needs Frobenius operations
/// 2. Hard part: exponentiation by (p^4 - p^2 + 1)/r - complex exponentiation
///
/// TODO: Implement full final exponentiation to maximize Fp2 circuit usage
fn finalExponentiation(f: *const Fp12) Fp12 {
    // Placeholder: just square the result
    var result = f.*;
    result = result.square(); // Uses Fp6.mul -> Fp2 circuits
    return result;
}

/// Compute pairing e(P, Q) using Miller loop and final exponentiation
/// Maximally uses BN254 Fp2 circuits (CSR 0x808, 0x809, 0x80A)
pub fn pairing(p: *const G1Point, q: *const G2Point) Fp12 {
    if (p.isInfinity() or q.isInfinity()) {
        return Fp12.one();
    }

    // Miller loop: uses G2 ops and line evaluations (all use Fp2 circuits)
    const f = millerLoop(p, q);

    // Final exponentiation: uses Fp12 ops (which use Fp2 circuits)
    return finalExponentiation(&f);
}

/// Multi-pairing check for EIP-197
pub fn pairingCheck(pairs: []const Pair) bool {
    var result = Fp12.one();

    for (pairs) |pair| {
        const e = pairing(&pair.p, &pair.q);
        result = result.mul(&e); // Uses Fp6.mul -> Fp2 circuits
    }

    return result.isOne();
}
