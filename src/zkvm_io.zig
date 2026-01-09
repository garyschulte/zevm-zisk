/// zkVM I/O Interface Implementation
/// Based on: https://github.com/eth-act/zkvm-standards/tree/main/standards/io-interface
///
/// Provides standardized input/output operations for zero-knowledge virtual machines.
/// Implements Option 2 (Direct Buffer Interface) which is optimal for Zisk's memory-mapped I/O.

const std = @import("std");

/// Zisk zkVM memory regions
const ZISK_INPUT_BASE: usize = 0x90000000;
const ZISK_INPUT_SIZE: usize = 0x08000000; // 128MB
const ZISK_OUTPUT_BASE: usize = 0xa0010000;
const ZISK_OUTPUT_SIZE: usize = 0x00010000; // 64KB

/// Track output position for sequential writes
var output_pos: usize = 0;

/// Read the private input data.
///
/// This function populates the pointer and size parameters with the input buffer.
/// The input is the private input, the existential part of the relation being proven.
///
/// Per the spec: "This function cannot fail, so no error code is returned."
/// "The function is idempotent."
///
/// A zero size indicates no valid input data is available.
///
/// # Safety
/// The returned pointer is valid for the lifetime of the program execution.
pub fn read_input(buf_ptr: *[*]const u8, buf_size: *usize) void {
    // Ziskemu INPUT region layout:
    // INPUT_ADDR + 0:  free_input (8 bytes, value=0)
    // INPUT_ADDR + 8:  input_len  (8 bytes, little-endian)
    // INPUT_ADDR + 16: input data (input_len bytes)

    // Read the input size from offset 8 (little-endian)
    const size_ptr: *const u64 = @ptrFromInt(ZISK_INPUT_BASE + 8);
    const input_size = std.mem.littleToNative(u64, size_ptr.*);

    // Validate size
    if (input_size == 0 or input_size > ZISK_INPUT_SIZE - 16) {
        // No valid input or size exceeds region
        buf_ptr.* = @ptrFromInt(ZISK_INPUT_BASE);
        buf_size.* = 0;
        return;
    }

    // Return pointer to data (starting at offset 16) and actual size
    const data_ptr: [*]const u8 = @ptrFromInt(ZISK_INPUT_BASE + 16);
    buf_ptr.* = data_ptr;
    buf_size.* = input_size;
}

/// Write public output data.
///
/// The output is the public part of the relation being proven.
/// Multiple calls to this function will concatenate the buffers sequentially.
///
/// Per the spec: "This function cannot fail, so no error code is returned."
///
/// # Arguments
/// * `output` - Pointer to output data buffer
/// * `size` - Size of output data in bytes
///
/// # Panics
/// Panics if the output exceeds the OUTPUT region size (64KB).
pub fn write_output(output: [*]const u8, size: usize) void {
    if (output_pos + size > ZISK_OUTPUT_SIZE) {
        @panic("Output exceeds OUTPUT region size (64KB)");
    }

    const output_region: [*]u8 = @ptrFromInt(ZISK_OUTPUT_BASE);
    const dest = output_region + output_pos;

    // Copy output data to OUTPUT region
    @memcpy(dest[0..size], output[0..size]);
    output_pos += size;
}

/// Reset output position (for testing)
pub fn reset_output() void {
    output_pos = 0;
}

/// Get current output position
pub fn get_output_position() usize {
    return output_pos;
}

/// POSIX-style interface (Option 1 from spec)
/// Provides compatibility with standard C library conventions.
pub const posix = struct {
    const STDIN_FD: i32 = 0;
    const STDOUT_FD: i32 = 1;
    const EBADF: i32 = 9; // Bad file descriptor

    /// POSIX read() implementation
    ///
    /// # Arguments
    /// * `fd` - File descriptor (must be 0 for input)
    /// * `buf` - Buffer to read into
    /// * `count` - Maximum bytes to read
    ///
    /// # Returns
    /// Number of bytes read, or -1 on error
    pub fn read(fd: i32, buf: [*]u8, count: usize) isize {
        if (fd != STDIN_FD) {
            // errno = EBADF
            return -1;
        }

        // Get input buffer
        var input_ptr: [*]const u8 = undefined;
        var input_size: usize = 0;
        read_input(&input_ptr, &input_size);

        if (input_size == 0) {
            return 0; // No input available
        }

        // Read up to count bytes
        const bytes_to_read = @min(count, input_size);
        @memcpy(buf[0..bytes_to_read], input_ptr[0..bytes_to_read]);

        return @intCast(bytes_to_read);
    }

    /// POSIX write() implementation
    ///
    /// # Arguments
    /// * `fd` - File descriptor (must be 1 for output)
    /// * `buf` - Buffer to write from
    /// * `count` - Number of bytes to write
    ///
    /// # Returns
    /// Number of bytes written, or -1 on error
    pub fn write(fd: i32, buf: [*]const u8, count: usize) isize {
        if (fd != STDOUT_FD) {
            // errno = EBADF
            return -1;
        }

        write_output(buf, count);
        return @intCast(count);
    }
};

/// Helper: Read input as a slice
pub fn read_input_slice() []const u8 {
    var buf_ptr: [*]const u8 = undefined;
    var buf_size: usize = 0;
    read_input(&buf_ptr, &buf_size);
    return buf_ptr[0..buf_size];
}

/// Helper: Write output from a slice
pub fn write_output_slice(output: []const u8) void {
    write_output(output.ptr, output.len);
}

test "zkvm_io basic functionality" {
    const testing = std.testing;

    // Test read_input with no data
    var buf_ptr: [*]const u8 = undefined;
    var buf_size: usize = 0;
    read_input(&buf_ptr, &buf_size);
    try testing.expectEqual(@as(usize, 0), buf_size);

    // Test POSIX interface
    try testing.expectEqual(@as(isize, -1), posix.read(2, undefined, 0)); // Invalid FD
    try testing.expectEqual(@as(isize, -1), posix.write(2, undefined, 0)); // Invalid FD
}
