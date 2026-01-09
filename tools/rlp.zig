const std = @import("std");

/// RLP decoder for Ethereum blocks
/// Based on https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/
pub const RlpDecoder = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) RlpDecoder {
        return .{ .data = data, .pos = 0 };
    }

    pub const RlpItem = union(enum) {
        bytes: []const u8,
        list: RlpList,
    };

    pub const RlpList = struct {
        data: []const u8,
        start: usize,
        end: usize,
    };

    /// Decode the next RLP item
    pub fn decode(self: *RlpDecoder) !RlpItem {
        if (self.pos >= self.data.len) return error.UnexpectedEndOfInput;

        const prefix = self.data[self.pos];

        // Single byte (0x00 - 0x7f)
        if (prefix < 0x80) {
            const byte = self.data[self.pos .. self.pos + 1];
            self.pos += 1;
            return RlpItem{ .bytes = byte };
        }

        // Short string (0x80 - 0xb7)
        if (prefix <= 0xb7) {
            const len = prefix - 0x80;
            self.pos += 1;
            if (self.pos + len > self.data.len) return error.UnexpectedEndOfInput;
            const bytes = self.data[self.pos .. self.pos + len];
            self.pos += len;
            return RlpItem{ .bytes = bytes };
        }

        // Long string (0xb8 - 0xbf)
        if (prefix <= 0xbf) {
            const len_size = prefix - 0xb7;
            self.pos += 1;
            if (self.pos + len_size > self.data.len) return error.UnexpectedEndOfInput;

            var len: usize = 0;
            for (0..len_size) |i| {
                len = (len << 8) | self.data[self.pos + i];
            }
            self.pos += len_size;

            if (self.pos + len > self.data.len) return error.UnexpectedEndOfInput;
            const bytes = self.data[self.pos .. self.pos + len];
            self.pos += len;
            return RlpItem{ .bytes = bytes };
        }

        // Short list (0xc0 - 0xf7)
        if (prefix <= 0xf7) {
            const len = prefix - 0xc0;
            self.pos += 1;
            if (self.pos + len > self.data.len) return error.UnexpectedEndOfInput;
            const start = self.pos;
            const end = self.pos + len;
            self.pos = end;
            return RlpItem{ .list = .{ .data = self.data, .start = start, .end = end } };
        }

        // Long list (0xf8 - 0xff)
        const len_size = prefix - 0xf7;
        self.pos += 1;
        if (self.pos + len_size > self.data.len) return error.UnexpectedEndOfInput;

        var len: usize = 0;
        for (0..len_size) |i| {
            len = (len << 8) | self.data[self.pos + i];
        }
        self.pos += len_size;

        if (self.pos + len > self.data.len) return error.UnexpectedEndOfInput;
        const start = self.pos;
        const end = self.pos + len;
        self.pos = end;
        return RlpItem{ .list = .{ .data = self.data, .start = start, .end = end } };
    }

    /// Decode bytes, expecting a byte string
    pub fn decodeBytes(self: *RlpDecoder) ![]const u8 {
        const item = try self.decode();
        return switch (item) {
            .bytes => item.bytes,
            .list => error.ExpectedBytes,
        };
    }

    /// Decode list, expecting a list
    pub fn decodeList(self: *RlpDecoder) !RlpDecoder {
        const item = try self.decode();
        return switch (item) {
            .bytes => error.ExpectedList,
            .list => |list| RlpDecoder.init(list.data[list.start..list.end]),
        };
    }

    /// Check if there is more data to decode
    pub fn hasMore(self: *const RlpDecoder) bool {
        return self.pos < self.data.len;
    }

    /// Get remaining bytes count
    pub fn remaining(self: *const RlpDecoder) usize {
        if (self.pos >= self.data.len) return 0;
        return self.data.len - self.pos;
    }
};

/// Helper to convert hex string to bytes
pub fn hexToBytes(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    // Remove 0x prefix if present
    const start: usize = if (hex_str.len >= 2 and hex_str[0] == '0' and hex_str[1] == 'x') 2 else 0;
    const hex = hex_str[start..];

    if (hex.len % 2 != 0) return error.InvalidHexLength;

    const bytes = try allocator.alloc(u8, hex.len / 2);
    errdefer allocator.free(bytes);

    for (0..bytes.len) |i| {
        const high = try std.fmt.charToDigit(hex[i * 2], 16);
        const low = try std.fmt.charToDigit(hex[i * 2 + 1], 16);
        bytes[i] = (high << 4) | low;
    }

    return bytes;
}

/// Helper to decode u64 from RLP bytes (big-endian)
pub fn bytesToU64(bytes: []const u8) !u64 {
    if (bytes.len == 0) return 0;
    if (bytes.len > 8) return error.ValueTooLarge;

    var result: u64 = 0;
    for (bytes) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Helper to decode u256 from RLP bytes (big-endian)
pub fn bytesToU256(bytes: []const u8) !u256 {
    if (bytes.len == 0) return 0;
    if (bytes.len > 32) return error.ValueTooLarge;

    var result: u256 = 0;
    for (bytes) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}

/// Helper to decode u128 from RLP bytes (big-endian)
pub fn bytesToU128(bytes: []const u8) !u128 {
    if (bytes.len == 0) return 0;
    if (bytes.len > 16) return error.ValueTooLarge;

    var result: u128 = 0;
    for (bytes) |byte| {
        result = (result << 8) | byte;
    }
    return result;
}
