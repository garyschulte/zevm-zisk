const std = @import("std");
const primitives = @import("primitives");
const stateless = @import("stateless_input");

/// Simple binary serializer for StatelessInput
/// Uses a straightforward binary format suitable for zkVM INPUT region
pub const Serializer = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Serializer {
        return .{
            .buffer = std.ArrayList(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Serializer) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Serializer) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    /// Write a single byte
    pub fn writeU8(self: *Serializer, value: u8) !void {
        try self.buffer.append(self.allocator, value);
    }

    /// Write u64 in big-endian
    pub fn writeU64(self: *Serializer, value: u64) !void {
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, value, .big);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    /// Write u128 in big-endian
    pub fn writeU128(self: *Serializer, value: u128) !void {
        var bytes: [16]u8 = undefined;
        std.mem.writeInt(u128, &bytes, value, .big);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    /// Write U256 (32 bytes, big-endian)
    pub fn writeU256(self: *Serializer, value: primitives.U256) !void {
        var bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &bytes, value, .big);
        try self.buffer.appendSlice(self.allocator, &bytes);
    }

    /// Write fixed-size byte array
    pub fn writeBytes(self: *Serializer, bytes: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, bytes);
    }

    /// Write length-prefixed byte slice
    pub fn writeByteSlice(self: *Serializer, slice: []const u8) !void {
        try self.writeU64(slice.len);
        try self.buffer.appendSlice(self.allocator, slice);
    }

    /// Write optional value
    pub fn writeOptional(self: *Serializer, comptime T: type, value: ?T) !void {
        if (value) |v| {
            try self.writeU8(1); // present
            switch (T) {
                u64 => try self.writeU64(v),
                primitives.Hash => try self.writeBytes(&v),
                else => @compileError("Unsupported optional type"),
            }
        } else {
            try self.writeU8(0); // not present
        }
    }

    /// Serialize Header
    pub fn writeHeader(self: *Serializer, header: *const stateless.Header) !void {
        try self.writeBytes(&header.parent_hash);
        try self.writeBytes(&header.ommers_hash);
        try self.writeBytes(&header.beneficiary);
        try self.writeBytes(&header.state_root);
        try self.writeBytes(&header.transactions_root);
        try self.writeBytes(&header.receipts_root);
        try self.writeBytes(&header.logs_bloom);
        try self.writeU256(header.difficulty);
        try self.writeU64(header.number);
        try self.writeU64(header.gas_limit);
        try self.writeU64(header.gas_used);
        try self.writeU64(header.timestamp);
        try self.writeByteSlice(header.extra_data);
        try self.writeBytes(&header.mix_hash);
        try self.writeU64(header.nonce);
        try self.writeOptional(u64, header.base_fee_per_gas);
        try self.writeOptional(primitives.Hash, header.withdrawals_root);
        try self.writeOptional(u64, header.blob_gas_used);
        try self.writeOptional(u64, header.excess_blob_gas);
        try self.writeOptional(primitives.Hash, header.parent_beacon_block_root);
        try self.writeOptional(primitives.Hash, header.requests_hash);
    }

    /// Serialize AccessListItem
    pub fn writeAccessListItem(self: *Serializer, item: *const stateless.AccessListItem) !void {
        try self.writeBytes(&item.address);
        try self.writeU64(item.storage_keys.len);
        for (item.storage_keys) |key| {
            try self.writeU256(key);
        }
    }

    /// Serialize Transaction
    pub fn writeTransaction(self: *Serializer, tx: *const stateless.Transaction) !void {
        try self.writeU8(tx.tx_type);

        // Chain ID
        if (tx.chain_id) |chain_id| {
            try self.writeU8(1);
            try self.writeU64(chain_id);
        } else {
            try self.writeU8(0);
        }

        try self.writeU64(tx.nonce);
        try self.writeU128(tx.gas_price);

        // Priority fee
        if (tx.gas_priority_fee) |fee| {
            try self.writeU8(1);
            try self.writeU128(fee);
        } else {
            try self.writeU8(0);
        }

        try self.writeU64(tx.gas_limit);

        // To address
        if (tx.to) |to| {
            try self.writeU8(1);
            try self.writeBytes(&to);
        } else {
            try self.writeU8(0);
        }

        try self.writeU256(tx.value);
        try self.writeByteSlice(tx.data);

        // Access list
        try self.writeU64(tx.access_list.len);
        for (tx.access_list) |*item| {
            try self.writeAccessListItem(item);
        }

        // Blob hashes
        try self.writeU64(tx.blob_hashes.len);
        for (tx.blob_hashes) |*hash| {
            try self.writeBytes(hash);
        }

        try self.writeU128(tx.max_fee_per_blob_gas);

        // Signature
        try self.writeU64(tx.v);
        try self.writeU256(tx.r);
        try self.writeU256(tx.s);
    }

    /// Serialize Withdrawal
    pub fn writeWithdrawal(self: *Serializer, withdrawal: *const stateless.Withdrawal) !void {
        try self.writeU64(withdrawal.index);
        try self.writeU64(withdrawal.validator_index);
        try self.writeBytes(&withdrawal.address);
        try self.writeU64(withdrawal.amount);
    }

    /// Serialize Block
    pub fn writeBlock(self: *Serializer, block: *const stateless.Block) !void {
        // Header
        try self.writeHeader(&block.header);

        // Transactions
        try self.writeU64(block.transactions.len);
        for (block.transactions) |*tx| {
            try self.writeTransaction(tx);
        }

        // Ommers
        try self.writeU64(block.ommers.len);
        for (block.ommers) |*ommer| {
            try self.writeHeader(ommer);
        }

        // Withdrawals
        if (block.withdrawals) |withdrawals| {
            try self.writeU8(1);
            try self.writeU64(withdrawals.len);
            for (withdrawals) |*w| {
                try self.writeWithdrawal(w);
            }
        } else {
            try self.writeU8(0);
        }
    }

    /// Serialize ExecutionWitness
    pub fn writeExecutionWitness(self: *Serializer, witness: *const stateless.ExecutionWitness) !void {
        // State preimages
        try self.writeU64(witness.state.len);
        for (witness.state) |item| {
            try self.writeByteSlice(item);
        }

        // Code preimages
        try self.writeU64(witness.codes.len);
        for (witness.codes) |item| {
            try self.writeByteSlice(item);
        }

        // Keys
        try self.writeU64(witness.keys.len);
        for (witness.keys) |item| {
            try self.writeByteSlice(item);
        }

        // Headers
        try self.writeU64(witness.headers.len);
        for (witness.headers) |item| {
            try self.writeByteSlice(item);
        }
    }

    /// Serialize full StatelessInput
    pub fn writeStatelessInput(self: *Serializer, input: *const stateless.StatelessInput) !void {
        try self.writeBlock(&input.block);
        try self.writeExecutionWitness(&input.witness);
    }
};

/// Serialize StatelessInput to bytes
pub fn serializeStatelessInput(allocator: std.mem.Allocator, input: *const stateless.StatelessInput) ![]u8 {
    var serializer = Serializer.init(allocator);
    defer serializer.deinit();
    try serializer.writeStatelessInput(input);
    return try serializer.toOwnedSlice();
}

/// Serialize StatelessInput with 8-byte size prefix (for Zisk INPUT region)
pub fn serializeStatelessInputWithSize(allocator: std.mem.Allocator, input: *const stateless.StatelessInput) ![]u8 {
    var serializer = Serializer.init(allocator);
    defer serializer.deinit();
    try serializer.writeStatelessInput(input);

    const data = try serializer.toOwnedSlice();
    defer allocator.free(data);

    // Prepend size
    var result = try allocator.alloc(u8, 8 + data.len);
    std.mem.writeInt(u64, result[0..8], data.len, .big);
    @memcpy(result[8..], data);

    return result;
}
