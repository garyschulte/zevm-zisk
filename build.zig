const std = @import("std");

pub fn build(b: *std.Build) void {
    // Force RISC-V 64-bit freestanding target for Zisk zkVM
    // Use rv64im (no atomics, no floating point, no compressed instructions)
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv64 },
        .cpu_features_add = std.Target.riscv.featureSet(&.{.m}),
        .cpu_features_sub = std.Target.riscv.featureSet(&.{ .a, .c, .d, .f, .zicsr, .zaamo, .zalrsc }),
        .os_tag = .freestanding,
        .abi = .none,
    });

    // Optimize for size or speed as needed
    const optimize = b.standardOptimizeOption(.{});

    // Build options - crypto libraries are disabled for freestanding
    const lib_options = b.addOptions();
    lib_options.addOption(bool, "enable_blst", false);
    lib_options.addOption(bool, "enable_mcl", false);
    const lib_options_module = lib_options.createModule();

    // Get zevm dependency and import its modules
    const zevm_dep = b.dependency("zevm", .{
        .target = target,
        .optimize = optimize,
    });

    // Import zevm modules from the dependency
    const primitives = zevm_dep.module("primitives");
    const bytecode = zevm_dep.module("bytecode");
    const state = zevm_dep.module("state");
    const database = zevm_dep.module("database");
    const context = zevm_dep.module("context");
    const interpreter = zevm_dep.module("interpreter");
    const precompile = zevm_dep.module("precompile");
    const handler = zevm_dep.module("handler");
    const inspector = zevm_dep.module("inspector");

    // Add build options to precompile module
    precompile.addImport("build_options", lib_options_module);

    // Create Zisk zkVM support module
    const zisk_mod = b.addModule("zisk", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/zisk/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    zisk_mod.addImport("primitives", primitives);

    // Zisk zkVM state transition executable
    const exe = b.addExecutable(.{
        .name = "zevm-zisk",
        .root_module = b.addModule("zevm-zisk", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/main.zig" } },
            .target = target,
            .optimize = optimize,
        }),
    });

    // Use custom linker script for Zisk zkVM
    exe.setLinkerScript(.{ .src_path = .{ .owner = b, .sub_path = "zisk.ld" } });

    // Use medium code model for full 64-bit address space access
    exe.root_module.code_model = .medium;

    // Add all module imports
    exe.root_module.addImport("zisk", zisk_mod);
    exe.root_module.addImport("primitives", primitives);
    exe.root_module.addImport("bytecode", bytecode);
    exe.root_module.addImport("state", state);
    exe.root_module.addImport("database", database);
    exe.root_module.addImport("context", context);
    exe.root_module.addImport("interpreter", interpreter);
    exe.root_module.addImport("precompile", precompile);
    exe.root_module.addImport("handler", handler);
    exe.root_module.addImport("inspector", inspector);

    // Install the executable
    b.installArtifact(exe);

    // Default build step
    const run_step = b.step("run", "Run the Zisk zkVM emulator");
    const run_cmd = b.addSystemCommand(&.{
        "../hello_zisk/zisk/target/release/ziskemu",
        "-e",
    });
    run_cmd.addArtifactArg(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_step.dependOn(&run_cmd.step);

    // ============================================================
    // StatelessInput Generator Tool (for host OS, not cross-compiled)
    // ============================================================

    const host_target = b.standardTargetOptions(.{});

    // Get zevm dependency for host target (reuse optimize from above)
    const zevm_host_dep = b.dependency("zevm", .{
        .target = host_target,
        .optimize = optimize,
    });

    const primitives_host = zevm_host_dep.module("primitives");
    const context_host = zevm_host_dep.module("context");

    // Create stateless_input module for tools
    const stateless_input_mod = b.addModule("stateless_input", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/stateless_input.zig" } },
        .target = host_target,
        .optimize = optimize,
    });
    stateless_input_mod.addImport("primitives", primitives_host);
    stateless_input_mod.addImport("context", context_host);

    // Create serialize module for tools
    const serialize_mod = b.addModule("serialize", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/serialize.zig" } },
        .target = host_target,
        .optimize = optimize,
    });
    serialize_mod.addImport("primitives", primitives_host);
    serialize_mod.addImport("stateless_input", stateless_input_mod);

    // StatelessInput generator tool
    const tool_exe = b.addExecutable(.{
        .name = "stateless-input-gen",
        .root_module = b.addModule("stateless-input-gen", .{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "tools/stateless_input_gen.zig" } },
            .target = host_target,
            .optimize = optimize,
        }),
    });

    tool_exe.root_module.addImport("primitives", primitives_host);
    tool_exe.root_module.addImport("context", context_host);
    tool_exe.root_module.addImport("stateless_input", stateless_input_mod);
    tool_exe.root_module.addImport("serialize", serialize_mod);

    b.installArtifact(tool_exe);

    // Build step for tool
    const tool_step = b.step("input-tool", "Build the stateless-input-gen tool");
    tool_step.dependOn(&tool_exe.step);

    // Run step for tool with test vectors
    const run_tool_step = b.step("gen-input", "Generate StatelessInput from test vectors");
    const run_tool_cmd = b.addRunArtifact(tool_exe);
    run_tool_cmd.addArgs(&.{
        "test/vectors/test_block.json",
        "test/vectors/test_block_witness.json",
        "test_stateless_input.bin",
    });
    run_tool_step.dependOn(&run_tool_cmd.step);
}
