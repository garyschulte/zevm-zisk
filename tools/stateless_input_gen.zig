const std = @import("std");
const rlp = @import("rlp.zig");
const rpc_parser = @import("rpc_parser.zig");
const stateless = @import("stateless_input");
const serialize = @import("serialize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("Usage: {s} <block_json> <witness_json> <output_bin>\n", .{args[0]});
        std.debug.print("\nGenerates a binary StatelessInput file from JSON-RPC responses\n", .{});
        std.debug.print("\nArguments:\n", .{});
        std.debug.print("  block_json    - Path to debug_getRawBlock JSON response\n", .{});
        std.debug.print("  witness_json  - Path to debug_executionWitness JSON response\n", .{});
        std.debug.print("  output_bin    - Path to output binary file\n", .{});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  {s} test/vectors/test_block.json test/vectors/test_block_witness.json output.bin\n", .{args[0]});
        return;
    }

    const block_json_path = args[1];
    const witness_json_path = args[2];
    const output_path = args[3];

    std.debug.print("Reading block from: {s}\n", .{block_json_path});
    std.debug.print("Reading witness from: {s}\n", .{witness_json_path});
    std.debug.print("Output will be written to: {s}\n\n", .{output_path});

    // Read block JSON
    const block_json = blk: {
        const file = try std.fs.cwd().openFile(block_json_path, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    };
    defer allocator.free(block_json);

    // Read witness JSON
    const witness_json = blk: {
        const file = try std.fs.cwd().openFile(witness_json_path, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    };
    defer allocator.free(witness_json);

    std.debug.print("Parsing block...\n", .{});
    var block = try rpc_parser.parseBlockFromJson(allocator, block_json);
    defer block.deinit();

    std.debug.print("Block parsed successfully:\n", .{});
    std.debug.print("  Number: {d}\n", .{block.header.number});
    std.debug.print("  Timestamp: {d}\n", .{block.header.timestamp});
    std.debug.print("  Gas limit: {d}\n", .{block.header.gas_limit});
    std.debug.print("  Gas used: {d}\n", .{block.header.gas_used});
    std.debug.print("  Transactions: {d}\n", .{block.transactions.len});
    std.debug.print("  Beneficiary: 0x", .{});
    for (block.header.beneficiary) |byte| {
        std.debug.print("{x:0>2}", .{byte});
    }
    std.debug.print("\n\n", .{});

    std.debug.print("Parsing witness...\n", .{});
    var witness = try rpc_parser.parseExecutionWitnessFromJson(allocator, witness_json);
    defer witness.deinit();

    std.debug.print("Witness parsed successfully:\n", .{});
    std.debug.print("  State preimages: {d}\n", .{witness.state.len});
    std.debug.print("  Code preimages: {d}\n", .{witness.codes.len});
    std.debug.print("  Keys: {d}\n", .{witness.keys.len});
    std.debug.print("  Headers: {d}\n", .{witness.headers.len});
    std.debug.print("\n", .{});

    // Create StatelessInput
    var input = try stateless.StatelessInput.init(allocator);
    defer input.deinit();

    input.block = block;
    input.witness = witness;

    // Serialize to binary format (no header - ziskemu adds it automatically)
    std.debug.print("Serializing to binary format...\n", .{});
    const binary_data = try serialize.serializeStatelessInput(allocator, &input);
    defer allocator.free(binary_data);

    std.debug.print("Binary size: {d} bytes (ziskemu will add 16-byte header)\n", .{binary_data.len});
    std.debug.print("\n", .{});

    // Write to output file
    std.debug.print("Writing to {s}...\n", .{output_path});
    const output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    try output_file.writeAll(binary_data);

    std.debug.print("✓ Successfully generated {s}\n", .{output_path});
    std.debug.print("\nYou can now use this file as input to the Zisk zkVM:\n", .{});
    std.debug.print("  ./zisk/target/release/ziskemu -e zig-out/bin/zevm-zisk --inputs {s}\n", .{output_path});
}
