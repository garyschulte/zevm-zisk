const std = @import("std");
const primitives = @import("primitives");
const database = @import("database");
const stateless = @import("stateless_input.zig");
const deserialize = @import("deserialize.zig");
const witness_loader = @import("witness_loader.zig");

/// Legacy wrapper: Execute a state transition from Zisk INPUT memory region
/// Deprecated: Use executeStateTransitionFromBytes with zkvm_io instead
pub fn executeStateTransition(allocator: std.mem.Allocator) !void {
    const zkvm_io = @import("zkvm_io.zig");
    const input_data = zkvm_io.read_input_slice();
    try executeStateTransitionFromBytes(allocator, input_data);
}

/// Execute a state transition from serialized StatelessInput bytes
pub fn executeStateTransitionFromBytes(
    allocator: std.mem.Allocator,
    input_data: []const u8,
) !void {
    if (input_data.len == 0) {
        return error.NoInputData;
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
