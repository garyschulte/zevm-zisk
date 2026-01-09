# zkVM I/O Interface

This project implements the [zkVM I/O Interface Standard](https://github.com/eth-act/zkvm-standards/tree/main/standards/io-interface) for portable input/output operations across zero-knowledge virtual machines.

## Overview

The zkVM I/O interface provides a standardized way to:
- **Read private input** - The existential part of the relation being proven
- **Write public output** - The public part of the relation being proven

This enables portable application code across different zkVM implementations.

## Memory Layout

Zisk zkVM provides dedicated memory regions for I/O:

```
INPUT (r):  0x90000000 - 0x98000000  [128MB max, read-only]
OUTPUT (rw): 0xa0010000 - 0xa0020000 [64KB, read-write]
```

## Interface Implementation

We implement **Option 2: Direct Buffer Interface** from the standard, which is optimal for Zisk's memory-mapped I/O.

### Reading Input

```zig
const zkvm_io = @import("zkvm_io.zig");

// Direct buffer interface
var buf_ptr: [*]const u8 = undefined;
var buf_size: usize = 0;
zkvm_io.read_input(&buf_ptr, &buf_size);

if (buf_size > 0) {
    const input_data = buf_ptr[0..buf_size];
    // Use input_data...
}

// Or use the helper function
const input_data = zkvm_io.read_input_slice();
```

### Writing Output

```zig
const output_data = "Hello from zkVM!";

// Direct buffer interface
zkvm_io.write_output(output_data.ptr, output_data.len);

// Or use the helper function
zkvm_io.write_output_slice(output_data);
```

### POSIX-Style Interface (Optional)

For compatibility with C libraries:

```zig
const zkvm_io = @import("zkvm_io.zig");

// Read from stdin (FD 0)
var buffer: [1024]u8 = undefined;
const bytes_read = zkvm_io.posix.read(0, &buffer, buffer.len);

// Write to stdout (FD 1)
const output = "Hello!";
const bytes_written = zkvm_io.posix.write(1, output.ptr, output.len);
```

## Loading Input Data

Use ziskemu's `--inputs` flag to load data into the INPUT region:

```bash
# Generate binary input
zig build gen-input

# Run with input
./zisk/target/release/ziskemu -e zig-out/bin/zevm-zisk --inputs test_stateless_input.bin
```

## Input Format

When loading a file via ziskemu's `--inputs` flag, the emulator automatically populates the INPUT region with:
```
INPUT_ADDR + 0:  free_input (8 bytes, value=0)
INPUT_ADDR + 8:  input_len  (8 bytes, little-endian) = file size
INPUT_ADDR + 16: input data (input_len bytes) = file contents
```

Our `stateless-input-gen` tool generates raw binary files (without headers). The ziskemu emulator adds the 16-byte header automatically when loading the file.

## Example Usage

```zig
const std = @import("std");
const zkvm_io = @import("zkvm_io.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Read private input
    const input_data = zkvm_io.read_input_slice();

    if (input_data.len > 0) {
        // Process input...
        const result = processInput(input_data);

        // Write public output
        zkvm_io.write_output_slice(result);
    }
}
```

## Benefits

1. **Portable** - Code works across different zkVM implementations
2. **Efficient** - Zero-copy access to memory-mapped regions
3. **Simple** - Clean API following established standards
4. **Compatible** - Optional POSIX interface for C library integration

## Specification Compliance

Our implementation follows the zkVM I/O standard:
- ✅ Direct buffer interface (Option 2)
- ✅ POSIX-style interface (Option 1) for compatibility
- ✅ Idempotent read operations
- ✅ Sequential write concatenation
- ✅ No error returns (follows spec: "cannot fail")
- ✅ Zero-copy implementation

## References

- [zkVM I/O Interface Specification](https://github.com/eth-act/zkvm-standards/tree/main/standards/io-interface)
- [Zisk zkVM Documentation](https://github.com/0xPolygonHermez/zisk)
