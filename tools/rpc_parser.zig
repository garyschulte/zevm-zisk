const std = @import("std");
const rlp = @import("rlp.zig");
const stateless = @import("stateless_input");
const primitives = @import("primitives");

/// Parse ExecutionWitness from JSON-RPC response
pub fn parseExecutionWitnessFromJson(
    allocator: std.mem.Allocator,
    json_text: []const u8,
) !stateless.ExecutionWitness {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Extract the witness data - handle both JSON-RPC wrapped and direct witness format
    const witness_obj = if (root.object.get("result")) |result|
        result
    else
        root;

    var witness = stateless.ExecutionWitness.init(allocator);
    errdefer witness.deinit();

    // Parse state array
    if (witness_obj.object.get("state")) |state_val| {
        const state_arr = state_val.array;
        var state_list = try allocator.alloc([]const u8, state_arr.items.len);
        for (state_arr.items, 0..) |item, i| {
            const hex_str = item.string;
            state_list[i] = try rlp.hexToBytes(allocator, hex_str);
        }
        witness.state = state_list;
    }

    // Parse codes array
    if (witness_obj.object.get("codes")) |codes_val| {
        const codes_arr = codes_val.array;
        var codes_list = try allocator.alloc([]const u8, codes_arr.items.len);
        for (codes_arr.items, 0..) |item, i| {
            const hex_str = item.string;
            codes_list[i] = try rlp.hexToBytes(allocator, hex_str);
        }
        witness.codes = codes_list;
    }

    // Parse keys array
    if (witness_obj.object.get("keys")) |keys_val| {
        const keys_arr = keys_val.array;
        var keys_list = try allocator.alloc([]const u8, keys_arr.items.len);
        for (keys_arr.items, 0..) |item, i| {
            const hex_str = item.string;
            keys_list[i] = try rlp.hexToBytes(allocator, hex_str);
        }
        witness.keys = keys_list;
    }

    // Parse headers array
    if (witness_obj.object.get("headers")) |headers_val| {
        const headers_arr = headers_val.array;
        var headers_list = try allocator.alloc([]const u8, headers_arr.items.len);
        for (headers_arr.items, 0..) |item, i| {
            const hex_str = item.string;
            headers_list[i] = try rlp.hexToBytes(allocator, hex_str);
        }
        witness.headers = headers_list;
    }

    return witness;
}

/// Parse block header from RLP
fn parseHeaderFromRlp(allocator: std.mem.Allocator, decoder: *rlp.RlpDecoder) !stateless.Header {
    var header = try stateless.Header.init(allocator);

    // Decode header fields in order
    // See: https://ethereum.org/en/developers/docs/blocks/#block-anatomy

    // parent_hash (32 bytes)
    const parent_hash_bytes = try decoder.decodeBytes();
    if (parent_hash_bytes.len != 32) return error.InvalidParentHash;
    @memcpy(&header.parent_hash, parent_hash_bytes);

    // ommers_hash (32 bytes)
    const ommers_hash_bytes = try decoder.decodeBytes();
    if (ommers_hash_bytes.len != 32) return error.InvalidOmmersHash;
    @memcpy(&header.ommers_hash, ommers_hash_bytes);

    // beneficiary (20 bytes)
    const beneficiary_bytes = try decoder.decodeBytes();
    if (beneficiary_bytes.len != 20) return error.InvalidBeneficiary;
    @memcpy(&header.beneficiary, beneficiary_bytes);

    // state_root (32 bytes)
    const state_root_bytes = try decoder.decodeBytes();
    if (state_root_bytes.len != 32) return error.InvalidStateRoot;
    @memcpy(&header.state_root, state_root_bytes);

    // transactions_root (32 bytes)
    const tx_root_bytes = try decoder.decodeBytes();
    if (tx_root_bytes.len != 32) return error.InvalidTxRoot;
    @memcpy(&header.transactions_root, tx_root_bytes);

    // receipts_root (32 bytes)
    const receipts_root_bytes = try decoder.decodeBytes();
    if (receipts_root_bytes.len != 32) return error.InvalidReceiptsRoot;
    @memcpy(&header.receipts_root, receipts_root_bytes);

    // logs_bloom (256 bytes)
    const logs_bloom_bytes = try decoder.decodeBytes();
    if (logs_bloom_bytes.len != 256) return error.InvalidLogsBloom;
    @memcpy(&header.logs_bloom, logs_bloom_bytes);

    // difficulty
    header.difficulty = try rlp.bytesToU256(try decoder.decodeBytes());

    // number
    header.number = try rlp.bytesToU64(try decoder.decodeBytes());

    // gas_limit
    header.gas_limit = try rlp.bytesToU64(try decoder.decodeBytes());

    // gas_used
    header.gas_used = try rlp.bytesToU64(try decoder.decodeBytes());

    // timestamp
    header.timestamp = try rlp.bytesToU64(try decoder.decodeBytes());

    // extra_data (variable length)
    const extra_data_bytes = try decoder.decodeBytes();
    const extra_data = try allocator.alloc(u8, extra_data_bytes.len);
    @memcpy(extra_data, extra_data_bytes);
    header.extra_data = extra_data;

    // mix_hash (32 bytes)
    const mix_hash_bytes = try decoder.decodeBytes();
    if (mix_hash_bytes.len != 32) return error.InvalidMixHash;
    @memcpy(&header.mix_hash, mix_hash_bytes);

    // nonce (8 bytes)
    header.nonce = try rlp.bytesToU64(try decoder.decodeBytes());

    // EIP-1559: base_fee_per_gas (optional)
    if (decoder.hasMore()) {
        header.base_fee_per_gas = try rlp.bytesToU64(try decoder.decodeBytes());
    }

    // EIP-4895: withdrawals_root (optional)
    if (decoder.hasMore()) {
        const wr_bytes = try decoder.decodeBytes();
        if (wr_bytes.len == 32) {
            var wr: primitives.Hash = undefined;
            @memcpy(&wr, wr_bytes);
            header.withdrawals_root = wr;
        }
    }

    // EIP-4844: blob_gas_used (optional)
    if (decoder.hasMore()) {
        header.blob_gas_used = try rlp.bytesToU64(try decoder.decodeBytes());
    }

    // EIP-4844: excess_blob_gas (optional)
    if (decoder.hasMore()) {
        header.excess_blob_gas = try rlp.bytesToU64(try decoder.decodeBytes());
    }

    // EIP-4788: parent_beacon_block_root (optional)
    if (decoder.hasMore()) {
        const pbbr_bytes = try decoder.decodeBytes();
        if (pbbr_bytes.len == 32) {
            var pbbr: primitives.Hash = undefined;
            @memcpy(&pbbr, pbbr_bytes);
            header.parent_beacon_block_root = pbbr;
        }
    }

    // EIP-7685: requests_hash (optional)
    if (decoder.hasMore()) {
        const rh_bytes = try decoder.decodeBytes();
        if (rh_bytes.len == 32) {
            var rh: primitives.Hash = undefined;
            @memcpy(&rh, rh_bytes);
            header.requests_hash = rh;
        }
    }

    return header;
}

/// Parse Block from RLP-encoded hex string (from debug_getRawBlock)
pub fn parseBlockFromRlp(
    allocator: std.mem.Allocator,
    rlp_hex: []const u8,
) !stateless.Block {
    // Decode hex to bytes
    const rlp_bytes = try rlp.hexToBytes(allocator, rlp_hex);
    defer allocator.free(rlp_bytes);

    var decoder = rlp.RlpDecoder.init(rlp_bytes);

    // Block is a list: [header, transactions, ommers, withdrawals?]
    var block_decoder = try decoder.decodeList();

    var block = try stateless.Block.init(allocator);
    errdefer block.deinit();

    // Parse header (first element)
    var header_decoder = try block_decoder.decodeList();
    block.header = try parseHeaderFromRlp(allocator, &header_decoder);

    // Parse transactions (second element) - for now, we'll skip full transaction parsing
    // TODO: Implement full transaction RLP decoding
    const tx_decoder = try block_decoder.decodeList();
    _ = tx_decoder; // Placeholder - transactions will be empty for now

    // Parse ommers (third element)
    const ommers_decoder = try block_decoder.decodeList();
    _ = ommers_decoder; // Placeholder - ommers will be empty for now

    // Parse withdrawals if present (post-Shanghai)
    // TODO: Implement withdrawal parsing

    return block;
}

/// Parse block from JSON-RPC response (containing RLP-encoded block)
pub fn parseBlockFromJson(
    allocator: std.mem.Allocator,
    json_text: []const u8,
) !stateless.Block {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_text, .{});
    defer parsed.deinit();

    const root = parsed.value;

    // Extract the RLP hex from JSON-RPC response
    const rlp_hex = if (root.object.get("result")) |result|
        result.string
    else
        return error.MissingResult;

    return try parseBlockFromRlp(allocator, rlp_hex);
}
