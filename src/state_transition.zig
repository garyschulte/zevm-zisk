const std = @import("std");
const primitives = @import("primitives");
const database = @import("database");
const stateless = @import("stateless_input.zig");
const deserialize = @import("deserialize.zig");
const witness_loader = @import("witness_loader.zig");

/// Zisk zkVM INPUT memory region where serialized StatelessInput data is loaded
/// INPUT (r): 0x90000000 - 0x98000000 [128MB max]
const ZISK_INPUT_BASE: usize = 0x90000000;
const ZISK_INPUT_SIZE: usize = 0x08000000; // 128MB

/// Read the input size from the first 8 bytes of INPUT region
/// Format: [size: u64 big-endian][data: size bytes]
fn readInputSize() u64 {
    const ptr: *const u64 = @ptrFromInt(ZISK_INPUT_BASE);
    return std.mem.bigToNative(u64, ptr.*);
}

/// Get a slice to the input data (after the 8-byte size prefix)
fn getInputData(size: u64) []const u8 {
    if (size == 0 or size > ZISK_INPUT_SIZE - 8) {
        return &.{}; // Empty or invalid size
    }
    const data_ptr: [*]const u8 = @ptrFromInt(ZISK_INPUT_BASE + 8);
    return data_ptr[0..size];
}

/// Execute a state transition from serialized StatelessInput
/// Reads input from Zisk zkVM INPUT memory region (0x90000000)
pub fn executeStateTransition(allocator: std.mem.Allocator) !void {
    // Read input size
    const input_size = readInputSize();
    if (input_size == 0) {
        return error.NoInputData;
    }

    // Get input data slice
    const input_data = getInputData(input_size);
    if (input_data.len == 0) {
        return error.InvalidInputSize;
    }

    // Deserialize StatelessInput
    var stateless_input = try deserialize.deserializeStatelessInput(allocator, input_data);
    defer stateless_input.deinit();

    // Create in-memory database
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Load witness data into database
    try witness_loader.loadWitnessIntoDatabase(&db, &stateless_input.witness);

    // Convert block header to execution context
    const block_env = stateless_input.block.header.toBlockEnv();
    _ = block_env;

    // TODO: Execute each transaction in the block
    // For each transaction:
    //   1. Recover sender from signature
    //   2. Convert to TxEnv
    //   3. Execute transaction against database
    //   4. Collect gas used and logs

    // TODO: Compute final state root
    // TODO: Verify state root matches block header

    // For now, just verify we can parse the input
}

/// Execute state transition with mock data for testing
pub fn executeWithMockData(allocator: std.mem.Allocator) !void {
    // Create empty StatelessInput for testing structure
    var input = try stateless.StatelessInput.init(allocator);
    defer input.deinit();

    // Set up a simple mock block
    input.block.header.number = 12345;
    input.block.header.timestamp = 1700000000;
    input.block.header.gas_limit = 30_000_000;
    input.block.header.beneficiary = .{0xBE} ** 20;

    // Create database
    var db = database.InMemoryDB.init(allocator);
    defer db.deinit();

    // Load empty witness
    try witness_loader.loadWitnessIntoDatabase(&db, &input.witness);

    // Verify we can create BlockEnv
    const block_env = input.block.header.toBlockEnv();
    _ = block_env;
}
