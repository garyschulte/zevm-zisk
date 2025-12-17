const std = @import("std");
const zisk = @import("zisk");
const primitives = @import("primitives");
const state = @import("state");
const database = @import("database");

/// Zisk zkVM UART address for console output
const ZISK_UART: *volatile u8 = @ptrFromInt(0xa0000200);

/// Write to Zisk zkVM UART
fn uartWrite(bytes: []const u8) void {
    for (bytes) |byte| {
        ZISK_UART.* = byte;
    }
}

/// Write a string to UART with newline
fn uartPrint(comptime fmt: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, fmt, args) catch "ERROR: Format failed\n";
    uartWrite(message);
}

/// Print a hash as hex string
fn uartPrintHash(prefix: []const u8, hash: primitives.Hash) void {
    uartWrite(prefix);
    for (hash) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch {
            uartWrite("??");
            continue;
        };
        uartWrite(&buf);
    }
    uartWrite("\n");
}

/// Mock Block structure for demonstration
const MockBlock = struct {
    number: u64,
    timestamp: u64,
    beneficiary: primitives.Address,

    pub fn init(number: u64, timestamp: u64, beneficiary: primitives.Address) MockBlock {
        return MockBlock{
            .number = number,
            .timestamp = timestamp,
            .beneficiary = beneficiary,
        };
    }
};

/// Simple state root computation (simplified - not a full Merkle Patricia Trie)
fn computeSimpleStateRoot(db: *database.InMemoryDB) !primitives.Hash {
    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});

    var account_iter = db.accounts.iterator();
    var count: u32 = 0;

    while (account_iter.next()) |entry| {
        const address = entry.key_ptr.*;
        const account = entry.value_ptr.*;

        hasher.update(&address);

        var balance_bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &balance_bytes, account.balance, .big);
        hasher.update(&balance_bytes);

        var nonce_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &nonce_bytes, account.nonce, .big);
        hasher.update(&nonce_bytes);

        hasher.update(&account.code_hash);

        count += 1;
    }

    var count_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &count_bytes, count, .big);
    hasher.update(&count_bytes);

    var result: primitives.Hash = undefined;
    hasher.final(&result);
    return result;
}

/// Execute a simple value transfer transaction
fn executeValueTransfer(
    db: *database.InMemoryDB,
    from: primitives.Address,
    to: primitives.Address,
    value: primitives.U256,
    nonce: u64,
) !void {
    // Get sender account
    var sender_account = (try db.basic(from)) orelse {
        return error.AccountNotFound;
    };

    // Check balance
    if (sender_account.balance < value) {
        return error.InsufficientBalance;
    }

    // Check nonce
    if (sender_account.nonce != nonce) {
        return error.InvalidNonce;
    }

    // Get or create receiver account
    var receiver_account = (try db.basic(to)) orelse state.AccountInfo.fromBalance(0);

    // Update balances
    sender_account.balance -= value;
    sender_account.nonce += 1;
    receiver_account.balance += value;

    // Write back to database
    try db.insertAccount(from, sender_account);
    try db.insertAccount(to, receiver_account);
}

/// Test EIP-196 BN254 operations (ecAdd and ecMul)
fn testBn254CurveAddCircuit() void {
    uartWrite("=== EIP-196 BN254 Operations ===\n");

    // BN254 generator point G = (1, 2) in big-endian format (EIP-196 standard)
    var g_point: [64]u8 = [_]u8{0} ** 64;
    g_point[31] = 1; // x = 1 (big-endian)
    g_point[63] = 2; // y = 2 (big-endian)

    // Test 1: ecAdd with G + G (should use doubling internally)
    uartWrite("\nTest 1: ecAdd(G, G) = 2G\n");
    var result: [64]u8 = undefined;
    zisk.eip196.ecAdd(&g_point, &g_point, &result);

    uartWrite("  Result (2G):\n");
    uartWrite("    x = 0x");
    for (result[0..32]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n    y = 0x");
    for (result[32..64]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n");

    // Test 2: ecAdd with 2G + G = 3G
    uartWrite("\nTest 2: ecAdd(2G, G) = 3G\n");
    var two_g = result; // Save 2G from previous test
    zisk.eip196.ecAdd(&two_g, &g_point, &result);

    uartWrite("  Result (3G):\n");
    uartWrite("    x = 0x");
    for (result[0..32]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n    y = 0x");
    for (result[32..64]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n");

    // Test 3: ecMul with k = 3 (should match 3G from above)
    uartWrite("\nTest 3: ecMul(G, 3) = 3G\n");
    var scalar: [32]u8 = [_]u8{0} ** 32;
    scalar[31] = 3; // k = 3 (big-endian)

    var mul_result: [64]u8 = undefined;
    zisk.eip196.ecMul(&g_point, &scalar, &mul_result);

    uartWrite("  Result (3G via ecMul):\n");
    uartWrite("    x = 0x");
    for (mul_result[0..32]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n    y = 0x");
    for (mul_result[32..64]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n");

    // Verify ecMul(G, 3) == ecAdd(2G, G)
    if (std.mem.eql(u8, &result, &mul_result)) {
        uartWrite("  ✓ ecMul matches ecAdd result!\n");
    } else {
        uartWrite("  ✗ ecMul does NOT match ecAdd result!\n");
    }

    // Test 4: ecMul with larger scalar
    uartWrite("\nTest 4: ecMul(G, 100)\n");
    scalar = [_]u8{0} ** 32;
    scalar[31] = 100; // k = 100 (big-endian)

    zisk.eip196.ecMul(&g_point, &scalar, &mul_result);

    uartWrite("  Result (100G):\n");
    uartWrite("    x = 0x");
    for (mul_result[0..32]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n    y = 0x");
    for (mul_result[32..64]) |byte| {
        var buf: [2]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable;
        uartWrite(&buf);
    }
    uartWrite("\n");
}

/// Run all demo transactions and tests
pub fn runDemo(allocator: std.mem.Allocator) !void {
    uartWrite("=== Zisk zkVM Block State Transition Demo ===\n");

    uartWrite("Creating in-memory database...\n");
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Create some accounts
    const alice = primitives.Address{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x11 };
    const bob = primitives.Address{ 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22 };
    const beneficiary = primitives.Address{ 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF, 0xBE, 0xEF };

    uartWrite("Setting up initial account state...\n");

    // Alice starts with 1000 ETH
    var alice_account = state.AccountInfo.fromBalance(1000);
    alice_account.nonce = 0;
    try db.insertAccount(alice, alice_account);

    // Bob starts with 100 ETH
    var bob_account = state.AccountInfo.fromBalance(100);
    bob_account.nonce = 0;
    try db.insertAccount(bob, bob_account);

    // Compute initial state root
    uartWrite("Computing initial state root...\n");
    const initial_state_root = try computeSimpleStateRoot(&db);
    uartPrintHash("Initial state root: ", initial_state_root);

    // Create a mock block
    const block = MockBlock.init(12345, 1700000000, beneficiary);
    uartPrint("Block number: {d}\n", .{block.number});
    uartPrint("Block timestamp: {d}\n", .{block.timestamp});

    // Execute transaction: Alice sends 50 ETH to Bob
    uartWrite("\nExecuting transaction: Alice -> Bob (50 ETH)...\n");
    try executeValueTransfer(&db, alice, bob, 50, 0);

    // Verify final balances
    const alice_final = (try db.basic(alice)).?;
    const bob_final = (try db.basic(bob)).?;

    uartPrint("Alice final balance: {d} ETH (nonce: {d})\n", .{ alice_final.balance, alice_final.nonce });
    uartPrint("Bob final balance: {d} ETH (nonce: {d})\n", .{ bob_final.balance, bob_final.nonce });

    // Compute final state root
    uartWrite("\nComputing final state root...\n");
    const final_state_root = try computeSimpleStateRoot(&db);
    uartPrintHash("Final state root: ", final_state_root);

    // Check if state changed
    if (std.mem.eql(u8, &initial_state_root, &final_state_root)) {
        uartWrite("\nERROR: State root unchanged!\n");
        return error.StateUnchanged;
    }

    // Test EIP-196 BN254 operations
    uartWrite("\n");
    testBn254CurveAddCircuit();

    uartWrite("\n=== Block transition completed successfully ===\n");
}
