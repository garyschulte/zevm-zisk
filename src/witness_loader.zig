const std = @import("std");
const primitives = @import("primitives");
const state = @import("state");
const database = @import("database");
const stateless = @import("stateless_input.zig");

/// Populate an InMemoryDB from ExecutionWitness data
/// The witness contains all pre-state account data needed for stateless execution
pub fn loadWitnessIntoDatabase(
    db: *database.InMemoryDB,
    witness: *const stateless.ExecutionWitness,
) !void {
    // TODO: Parse witness data to extract account information
    // The witness contains:
    // - witness.state: Hashed trie node preimages (for MPT verification)
    // - witness.codes: Contract bytecode
    // - witness.keys: Unhashed addresses and storage keys
    // - witness.headers: Block headers for BLOCKHASH opcode

    // For now, this is a placeholder
    // In production implementation, you would:
    // 1. Parse the keys to extract account addresses and storage keys
    // 2. Reconstruct account state from trie nodes (or use state preimages)
    // 3. Load contract codes and compute code hashes
    // 4. Populate storage slots

    _ = db;
    _ = witness;
}

/// Parse witness keys to extract account addresses and storage keys
/// Keys format (from alloy ExecutionWitness):
/// - 20 bytes = account address (for account keys)
/// - 52 bytes = address (20) + storage key (32) (for storage keys)
pub fn parseWitnessKeys(
    allocator: std.mem.Allocator,
    keys: []const []const u8,
) !ParsedKeys {
    var accounts = std.ArrayList(primitives.Address).init(allocator);
    var storage = std.AutoHashMap(primitives.Address, std.ArrayList(primitives.U256)).init(allocator);

    for (keys) |key| {
        if (key.len == 20) {
            // Account key - just the address
            var addr: primitives.Address = undefined;
            @memcpy(&addr, key[0..20]);
            try accounts.append(addr);
        } else if (key.len == 52) {
            // Storage key - address (20) + slot (32)
            var addr: primitives.Address = undefined;
            @memcpy(&addr, key[0..20]);

            const slot = std.mem.readInt(u256, key[20..52], .big);

            // Get or create storage list for this address
            const result = try storage.getOrPut(addr);
            if (!result.found_existing) {
                result.value_ptr.* = std.ArrayList(primitives.U256).init(allocator);
            }
            try result.value_ptr.append(slot);
        }
        // Ignore keys with other lengths (may be added in future witness formats)
    }

    return ParsedKeys{
        .accounts = accounts,
        .storage = storage,
    };
}

pub const ParsedKeys = struct {
    accounts: std.ArrayList(primitives.Address),
    storage: std.AutoHashMap(primitives.Address, std.ArrayList(primitives.U256)),

    pub fn deinit(self: *ParsedKeys) void {
        self.accounts.deinit();

        var iter = self.storage.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.storage.deinit();
    }
};

/// Helper: Load a simplified witness with explicit account data
/// This is useful for testing before full witness parsing is implemented
pub fn loadSimplifiedWitness(
    db: *database.InMemoryDB,
    accounts: []const AccountData,
) !void {
    for (accounts) |account_data| {
        // Create AccountInfo
        const account_info = state.AccountInfo{
            .balance = account_data.balance,
            .nonce = account_data.nonce,
            .code_hash = account_data.code_hash,
            .bytecode = account_data.bytecode,
        };

        // Insert account
        try db.insertAccount(account_data.address, account_info);

        // Populate storage slots
        for (account_data.storage) |slot| {
            try db.insertStorage(account_data.address, slot.key, slot.value);
        }
    }
}

/// Simplified account data structure for testing
pub const AccountData = struct {
    address: primitives.Address,
    nonce: u64,
    balance: primitives.U256,
    code_hash: primitives.Hash,
    bytecode: ?[]const u8,
    storage: []const StorageSlot,
};

pub const StorageSlot = struct {
    key: primitives.U256,
    value: primitives.U256,
};
