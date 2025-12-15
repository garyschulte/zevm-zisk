const std = @import("std");
const baremetal = @import("baremetal");

// Import individual modules instead of zevm library to avoid crypto dependencies
const primitives = @import("primitives");
const state = @import("state");
const database = @import("database");

/// Zisk zkVM memory buffer (2MB) - placed at fixed address to avoid sign-extension issues
var HEAP: [2 * 1024 * 1024]u8 linksection(".heap") = undefined;

/// Zisk zkVM UART address for console output
const ZISK_UART: *volatile u8 = @ptrFromInt(0xa0000200);

// Linker-provided symbols
extern const __bss_start: u8;
extern const __bss_end: u8;

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

/// Exit via zisk zkVM syscall
fn zkExit(exit_code: u32) noreturn {
    asm volatile (
        \\ ecall
        \\ .align 4
        :
        : [exit_code] "{a0}" (exit_code),
          [syscall] "{a7}" (93)
        : .{ .memory = true }
    );
    // Loop forever if ecall doesn't exit
    while (true) {
        asm volatile ("wfi");
    }
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

/// Entry point for linker (_start symbol)
/// This MUST be pure assembly - no function prologue allowed
export fn _start() linksection(".text._start") noreturn {
    asm volatile (
        \\ // Initialize sp and gp
        \\ li sp, 0xa0120000
        \\ li gp, 0xa0020000
        \\
        \\ // Call _start_main
        \\ call _start_main
        \\
        \\ // Should never return
        \\ .align 4
        \\ 1: wfi
        \\ j 1b
        :
        :
        : .{ .x2 = true, .x3 = true, .memory = true }
    );
    unreachable;
}

/// Main initialization after sp/gp are set
export fn _start_main() noreturn {
    // Now we can use regular Zig code with stack
    uartWrite("INIT\n");

    // Call main
    main() catch {
        uartWrite("ERROR\n");
        zkExit(1);
    };

    // Success
    uartWrite("DONE\n");
    zkExit(0);
}

/// Zisk zkVM entry point
pub fn main() !void {
    uartWrite("=== Zisk zkVM Block State Transition Demo ===\n");

    // Use the 2MB heap for allocations
    var bump_alloc = baremetal.BumpAllocator.init(&HEAP);
    const allocator = bump_alloc.allocator();

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
    uartPrint("Initial state root: {x:0>64}\n", .{initial_state_root});

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
    uartPrint("Final state root: {x:0>64}\n", .{final_state_root});

    // Check if state changed
    if (std.mem.eql(u8, &initial_state_root, &final_state_root)) {
        uartWrite("\nERROR: State root unchanged!\n");
        return error.StateUnchanged;
    }

    uartWrite("\n=== Block transition completed successfully ===\n");
}

/// Panic handler for zisk zkVM
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = error_return_trace;
    _ = ret_addr;

    // Output panic message to UART
    uartWrite("PANIC: ");
    uartWrite(msg);
    uartWrite("\n");

    // Exit with error code 1 via zisk zkVM syscall
    zkExit(1);
}
