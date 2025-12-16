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
}
