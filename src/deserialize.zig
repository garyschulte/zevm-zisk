const std = @import("std");
const primitives = @import("primitives");
const stateless = @import("stateless_input.zig");

/// Simple binary deserializer for StatelessInput
/// Uses a straightforward binary format suitable for zkVM
pub const Deserializer = struct {
    buffer: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, buffer: []const u8) Deserializer {
        return .{
            .buffer = buffer,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// Read a single byte
    pub fn readU8(self: *Deserializer) !u8 {
        if (self.pos >= self.buffer.len) return error.UnexpectedEndOfInput;
        const value = self.buffer[self.pos];
        self.pos += 1;
        return value;
    }

    /// Read u64 in big-endian
    pub fn readU64(self: *Deserializer) !u64 {
        if (self.pos + 8 > self.buffer.len) return error.UnexpectedEndOfInput;
        const value = std.mem.readInt(u64, self.buffer[self.pos..][0..8], .big);
        self.pos += 8;
        return value;
    }

    /// Read u128 in big-endian
    pub fn readU128(self: *Deserializer) !u128 {
        if (self.pos + 16 > self.buffer.len) return error.UnexpectedEndOfInput;
        const value = std.mem.readInt(u128, self.buffer[self.pos..][0..16], .big);
        self.pos += 16;
        return value;
    }

    /// Read U256 (32 bytes, big-endian)
    pub fn readU256(self: *Deserializer) !primitives.U256 {
        if (self.pos + 32 > self.buffer.len) return error.UnexpectedEndOfInput;
        const bytes = self.buffer[self.pos..][0..32];
        self.pos += 32;
        return std.mem.readInt(u256, bytes, .big);
    }

    /// Read fixed-size byte array
    pub fn readBytes(self: *Deserializer, comptime size: usize) ![size]u8 {
        if (self.pos + size > self.buffer.len) return error.UnexpectedEndOfInput;
        var result: [size]u8 = undefined;
        @memcpy(&result, self.buffer[self.pos..][0..size]);
        self.pos += size;
        return result;
    }

    /// Read length-prefixed byte slice (allocates)
    pub fn readByteSlice(self: *Deserializer) ![]const u8 {
        const len = try self.readU64();
        if (self.pos + len > self.buffer.len) return error.UnexpectedEndOfInput;
        const slice = try self.allocator.alloc(u8, len);
        @memcpy(@constCast(slice), self.buffer[self.pos..][0..len]);
        self.pos += len;
        return slice;
    }

    /// Read optional value
    pub fn readOptional(self: *Deserializer, comptime T: type) !?T {
        const present = try self.readU8();
        if (present == 0) return null;

        return switch (T) {
            u64 => try self.readU64(),
            primitives.Hash => try self.readBytes(32),
            else => @compileError("Unsupported optional type"),
        };
    }

    /// Deserialize Header
    pub fn readHeader(self: *Deserializer) !stateless.Header {
        var header = try stateless.Header.init(self.allocator);

        header.parent_hash = try self.readBytes(32);
        header.ommers_hash = try self.readBytes(32);
        header.beneficiary = try self.readBytes(20);
        header.state_root = try self.readBytes(32);
        header.transactions_root = try self.readBytes(32);
        header.receipts_root = try self.readBytes(32);
        header.logs_bloom = try self.readBytes(256);
        header.difficulty = try self.readU256();
        header.number = try self.readU64();
        header.gas_limit = try self.readU64();
        header.gas_used = try self.readU64();
        header.timestamp = try self.readU64();

        // Extra data
        header.extra_data = try self.readByteSlice();

        header.mix_hash = try self.readBytes(32);
        header.nonce = try self.readU64();
        header.base_fee_per_gas = try self.readOptional(u64);
        header.withdrawals_root = try self.readOptional(primitives.Hash);
        header.blob_gas_used = try self.readOptional(u64);
        header.excess_blob_gas = try self.readOptional(u64);
        header.parent_beacon_block_root = try self.readOptional(primitives.Hash);
        header.requests_hash = try self.readOptional(primitives.Hash);

        return header;
    }

    /// Deserialize AccessListItem
    pub fn readAccessListItem(self: *Deserializer) !stateless.AccessListItem {
        const address = try self.readBytes(20);
        const num_keys = try self.readU64();

        const keys = try self.allocator.alloc(primitives.U256, num_keys);
        for (0..num_keys) |i| {
            keys[i] = try self.readU256();
        }

        return .{
            .address = address,
            .storage_keys = keys,
        };
    }

    /// Deserialize Transaction
    pub fn readTransaction(self: *Deserializer) !stateless.Transaction {
        var tx = try stateless.Transaction.init(self.allocator);

        tx.tx_type = try self.readU8();

        // Chain ID (optional)
        const has_chain_id = try self.readU8();
        tx.chain_id = if (has_chain_id != 0) try self.readU64() else null;

        tx.nonce = try self.readU64();
        tx.gas_price = try self.readU128();

        // Priority fee (optional for EIP-1559)
        const has_priority_fee = try self.readU8();
        tx.gas_priority_fee = if (has_priority_fee != 0) try self.readU128() else null;

        tx.gas_limit = try self.readU64();

        // To address (optional for Create)
        const has_to = try self.readU8();
        tx.to = if (has_to != 0) try self.readBytes(20) else null;

        tx.value = try self.readU256();
        tx.data = try self.readByteSlice();

        // Access list
        const access_list_len = try self.readU64();
        if (access_list_len > 0) {
            const access_list = try self.allocator.alloc(stateless.AccessListItem, access_list_len);
            for (0..access_list_len) |i| {
                access_list[i] = try self.readAccessListItem();
            }
            tx.access_list = access_list;
        }

        // Blob hashes (EIP-4844)
        const blob_hashes_len = try self.readU64();
        if (blob_hashes_len > 0) {
            const blob_hashes = try self.allocator.alloc(primitives.Hash, blob_hashes_len);
            for (0..blob_hashes_len) |i| {
                blob_hashes[i] = try self.readBytes(32);
            }
            tx.blob_hashes = blob_hashes;
        }

        tx.max_fee_per_blob_gas = try self.readU128();

        // Signature
        tx.v = try self.readU64();
        tx.r = try self.readU256();
        tx.s = try self.readU256();

        return tx;
    }

    /// Deserialize Withdrawal
    pub fn readWithdrawal(self: *Deserializer) !stateless.Withdrawal {
        return .{
            .index = try self.readU64(),
            .validator_index = try self.readU64(),
            .address = try self.readBytes(20),
            .amount = try self.readU64(),
        };
    }

    /// Deserialize Block
    pub fn readBlock(self: *Deserializer) !stateless.Block {
        var block = try stateless.Block.init(self.allocator);

        // Header
        block.header = try self.readHeader();

        // Transactions
        const tx_count = try self.readU64();
        if (tx_count > 0) {
            const transactions = try self.allocator.alloc(stateless.Transaction, tx_count);
            for (0..tx_count) |i| {
                transactions[i] = try self.readTransaction();
            }
            block.transactions = transactions;
        }

        // Ommers
        const ommer_count = try self.readU64();
        if (ommer_count > 0) {
            const ommers = try self.allocator.alloc(stateless.Header, ommer_count);
            for (0..ommer_count) |i| {
                ommers[i] = try self.readHeader();
            }
            block.ommers = ommers;
        }

        // Withdrawals
        const has_withdrawals = try self.readU8();
        if (has_withdrawals != 0) {
            const withdrawal_count = try self.readU64();
            const withdrawals = try self.allocator.alloc(stateless.Withdrawal, withdrawal_count);
            for (0..withdrawal_count) |i| {
                withdrawals[i] = try self.readWithdrawal();
            }
            block.withdrawals = withdrawals;
        }

        return block;
    }

    /// Deserialize ExecutionWitness
    pub fn readExecutionWitness(self: *Deserializer) !stateless.ExecutionWitness {
        var witness = stateless.ExecutionWitness.init(self.allocator);

        // State preimages
        const state_count = try self.readU64();
        if (state_count > 0) {
            const state = try self.allocator.alloc([]const u8, state_count);
            for (0..state_count) |i| {
                state[i] = try self.readByteSlice();
            }
            witness.state = state;
        }

        // Code preimages
        const code_count = try self.readU64();
        if (code_count > 0) {
            const codes = try self.allocator.alloc([]const u8, code_count);
            for (0..code_count) |i| {
                codes[i] = try self.readByteSlice();
            }
            witness.codes = codes;
        }

        // Keys (unhashed)
        const key_count = try self.readU64();
        if (key_count > 0) {
            const keys = try self.allocator.alloc([]const u8, key_count);
            for (0..key_count) |i| {
                keys[i] = try self.readByteSlice();
            }
            witness.keys = keys;
        }

        // Headers (RLP-encoded)
        const header_count = try self.readU64();
        if (header_count > 0) {
            const headers = try self.allocator.alloc([]const u8, header_count);
            for (0..header_count) |i| {
                headers[i] = try self.readByteSlice();
            }
            witness.headers = headers;
        }

        return witness;
    }

    /// Deserialize full StatelessInput
    pub fn readStatelessInput(self: *Deserializer) !stateless.StatelessInput {
        var input = try stateless.StatelessInput.init(self.allocator);

        input.block = try self.readBlock();
        input.witness = try self.readExecutionWitness();

        return input;
    }
};

/// Deserialize StatelessInput from bytes
pub fn deserializeStatelessInput(allocator: std.mem.Allocator, data: []const u8) !stateless.StatelessInput {
    var deserializer = Deserializer.init(allocator, data);
    return try deserializer.readStatelessInput();
}
