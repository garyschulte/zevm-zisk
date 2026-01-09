const std = @import("std");
const zisk = @import("zisk");
const demo = @import("demo.zig");
const state_transition = @import("state_transition.zig");
const zkvm_io = @import("zkvm_io.zig");

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

// Entry point for linker (_start symbol)
// Pure assembly entry - NO function prologue allowed
// Must use comptime asm to avoid Zig generating function prologue
comptime {
    asm (
        \\.section .text._start,"ax",%progbits
        \\.global _start
        \\.type _start, @function
        \\_start:
        \\  li sp, 0xa0120000    // Initialize stack pointer
        \\  li gp, 0xa0020000    // Initialize global pointer
        \\  call _start_main     // Jump to Zig code
        \\  .align 4
        \\1: wfi                  // Should never reach here
        \\  j 1b
        \\.size _start, . - _start
    );
}

/// Main initialization after sp/gp are set
export fn _start_main() noreturn {
    // Now we can use regular Zig code with stack
    uartWrite("INIT\n");

    // Call main
    main() catch |err| {
        uartWrite("ERROR: ");
        uartWrite(@errorName(err));
        uartWrite("\n");
        zkExit(1);
    };

    // Success
    uartWrite("DONE\n");
    zkExit(0);
}

/// Zisk zkVM entry point
pub fn main() !void {
    // Use Zisk's sys_alloc_aligned for dynamic allocations
    var zisk_alloc = zisk.ZiskAllocator.init();
    const allocator = zisk_alloc.allocator();

    // Use zkVM standard I/O interface to check for input
    const input_data = zkvm_io.read_input_slice();

    if (input_data.len > 0) {
        // We have stateless input data - execute state transition
        uartWrite("Reading stateless input via zkVM I/O interface...\n");
        try state_transition.executeStateTransitionFromBytes(allocator, input_data);
    } else {
        // No input data - run demo mode
        uartWrite("No input data found, running demo mode...\n");
        try demo.runDemo(allocator);
    }
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
