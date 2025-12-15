const std = @import("std");

pub fn build(b: *std.Build) void {
    // Force RISC-V 64-bit freestanding target for Zisk zkVM
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    });

    // Optimize for size or speed as needed
    const optimize = b.standardOptimizeOption(.{});

    // Get zevm dependency
    const zevm_dep = b.dependency("zevm", .{
        .target = target,
        .optimize = optimize,
        .blst = false,  // Disable crypto libraries for freestanding
        .mcl = false,
    });

    // Get zevm modules
    const primitives = zevm_dep.module("primitives");
    const bytecode = zevm_dep.module("bytecode");
    const state = zevm_dep.module("state");
    const database = zevm_dep.module("database");
    const context = zevm_dep.module("context");
    const interpreter = zevm_dep.module("interpreter");
    const precompile = zevm_dep.module("precompile");
    const handler = zevm_dep.module("handler");
    const inspector = zevm_dep.module("inspector");

    // Create baremetal module
    const baremetal = b.addModule("baremetal", .{
        .root_source_file = b.path("src/baremetal/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    baremetal.addImport("primitives", primitives);

    // Zisk zkVM state transition executable
    const exe = b.addExecutable(.{
        .name = "zevm-zisk",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Use custom linker script for Zisk zkVM
    exe.setLinkerScript(b.path("zisk.ld"));

    // Use medium code model for full 64-bit address space access
    exe.root_module.code_model = .medium;

    // Add all module imports
    exe.root_module.addImport("baremetal", baremetal);
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
