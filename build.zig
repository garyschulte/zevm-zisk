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

    // Create zevm modules directly from source
    const zevm_path = "../zevm/src";

    const primitives = b.addModule("primitives", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/primitives/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    const bytecode = b.addModule("bytecode", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/bytecode/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    bytecode.addImport("primitives", primitives);

    const state = b.addModule("state", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/state/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    state.addImport("primitives", primitives);
    state.addImport("bytecode", bytecode);

    const database = b.addModule("database", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/database/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    database.addImport("primitives", primitives);
    database.addImport("state", state);
    database.addImport("bytecode", bytecode);

    const context = b.addModule("context", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/context/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    context.addImport("primitives", primitives);
    context.addImport("state", state);
    context.addImport("database", database);

    const interpreter = b.addModule("interpreter", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/interpreter/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    interpreter.addImport("primitives", primitives);
    interpreter.addImport("bytecode", bytecode);
    interpreter.addImport("context", context);

    const precompile = b.addModule("precompile", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/precompile/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    precompile.addImport("build_options", lib_options_module);
    precompile.addImport("primitives", primitives);

    const handler = b.addModule("handler", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/handler/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    handler.addImport("primitives", primitives);
    handler.addImport("bytecode", bytecode);
    handler.addImport("state", state);
    handler.addImport("database", database);
    handler.addImport("interpreter", interpreter);
    handler.addImport("context", context);
    handler.addImport("precompile", precompile);

    const inspector = b.addModule("inspector", .{
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = zevm_path ++ "/inspector/main.zig" } },
        .target = target,
        .optimize = optimize,
    });
    inspector.addImport("primitives", primitives);
    inspector.addImport("interpreter", interpreter);

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
}
