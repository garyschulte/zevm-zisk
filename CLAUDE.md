# Zisk zkVM Guest Program - Context for AI Assistants

## Project Overview

This is a Zig-based state transition function (guest program) for **Zisk zkVM**, a RISC-V based zero-knowledge virtual machine. It implements an EVM-compatible execution environment.

**Target**: `riscv64-freestanding-none` with `rv64im` ISA (no atomics, no floating-point)

## Critical Zisk zkVM Architecture

### Memory Layout (from zisk/core/src/mem.rs)

``` 
ROM (rx):   0x80000000 - 0x87FFFFFF  [128MB]
            └─ 0x87F00000+: Float library (RESERVED - don't use)

INPUT (r):  0x90000000 - 0x98000000  [128MB max]

SYSTEM (rw):
            0xa0000000: Register file (256 bytes)
            0xa0000200: UART_ADDR (stdout)
            0xa0001000: FREG_FIRST
            0xa0008000: CSR_ADDR

OUTPUT (rw): 0xa0010000 - 0xa0020000 [64KB]

RAM (rw):   0xa0020000 - 0xc0000000  [~512MB]
            ├─ .data, .bss
            ├─ Stack (1MB)
            └─ Heap (dynamic, ~511MB via sys_alloc_aligned)

FLOAT RAM:  0xafff0000 - 0xc0000000  [64KB, RESERVED]
```

### Key Architectural Differences from Bare-Metal

1. **Linker Script Pattern**: Use `>RAM AT>RAM` (NOT `>RAM AT>ROM`)
   - zkVM initializes memory directly from ELF
   - No startup copying needed (VMA = LMA for writable sections)

2. **Precompiles via CSR Instructions** (NOT traditional ecalls)
   - Range: 0x800 - 0x84F
   - Instruction: `csrs <csr_addr>, <register>`
   - Examples: 0x800 (Keccak-f), 0x805 (SHA256), 0x803 (secp256k1)

3. **Exit via Ecall**:
   ```zig
   asm volatile ("ecall" : : [exit_code] "{a0}" (code), [syscall] "{a7}" (93));
   ```

4. **Memory Allocation**:
   - Implement `sys_alloc_aligned(bytes, alignment)` yourself
   - Bump allocator using `_kernel_heap_bottom` linker symbol
   - No free/realloc (zkVM constraint)

## Project Structure

```
src/
├── main.zig              Main entry point and demo
├── zisk/                 Zisk zkVM support module
│   ├── allocator.zig     ZiskAllocator + sys_alloc_aligned impl
│   ├── ecalls.zig        Placeholder stubs
│   └── main.zig          Module exports
└── (zevm modules)        EVM primitives, interpreter, etc.

zisk.ld                   Custom linker script
build.zig                 Build configuration
```

## Linker Script (zisk.ld)

**Critical sections:**

```ld
MEMORY {
    ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 0x08000000  /* 128MB NOT 256MB */
    RAM (rw)  : ORIGIN = 0xa0020000, LENGTH = 0x1FFE0000
}

SECTIONS {
    .text : { ... } >ROM :text
    .rodata : { ... } >ROM :text

    /* IMPORTANT: Both VMA and LMA in RAM */
    .data : { ... } >RAM AT>RAM :data    /* NOT AT>ROM */
    .bss : { ... } >RAM AT>RAM :bss      /* NOT AT>ROM */

    /* Heap symbols for sys_alloc_aligned */
    PROVIDE(_init_stack_top = . + 0x100000);  /* 1MB stack */
    PROVIDE(_kernel_heap_bottom = _init_stack_top);
    PROVIDE(_kernel_heap_top = ORIGIN(RAM) + LENGTH(RAM));
}
```

## Entry Point Pattern

```zig
// Entry point for linker (_start symbol)
// Pure assembly entry - NO function prologue allowed
// MUST use comptime asm to avoid Zig generating function prologue
// Using export fn with linksection() causes sign-extension errors!
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

// Main initialization after sp/gp are set
// Regular Zig code with stack available
export fn _start_main() noreturn {
    uartWrite("INIT\n");
    main() catch |err| zkExit(1);
    zkExit(0);
}
```

## Memory Allocation Pattern

```zig
const zisk = @import("zisk");

// Use ZiskAllocator for dynamic allocation from kernel heap
var zisk_alloc = zisk.ZiskAllocator.init();
const allocator = zisk_alloc.allocator();

// ~511MB available from _kernel_heap_bottom to 0xc0000000
```

## Implementation of sys_alloc_aligned

Located in `src/zisk/allocator.zig:8-30`:

```zig
extern const _kernel_heap_bottom: u8;

export fn sys_alloc_aligned(bytes: usize, alignment: usize) [*]u8 {
    const State = struct {
        var heap_pos: usize = 0;
    };

    if (State.heap_pos == 0) {
        State.heap_pos = @intFromPtr(&_kernel_heap_bottom);
    }

    // Align and bump
    const offset = State.heap_pos & (alignment - 1);
    if (offset != 0) {
        State.heap_pos += alignment - offset;
    }

    const ptr: [*]u8 = @ptrFromInt(State.heap_pos);
    State.heap_pos += bytes;
    return ptr;
}
```

## Common Issues and Solutions

### 1. Sign-Extension Errors
**Problem**: Addresses like `0xFFFFFFFF...`
**Cause**: Code in RAM (0xa0000000+) gets sign-extended
**Fix**: Code MUST be in ROM at 0x80000000

### 2. "Incorrect Alignment" Panic
**Problem**: Panic at startup
**Cause**: Code references `.heap` section not in linker script
**Fix**: Use `ZiskAllocator` (dynamic) instead of static heap buffer

### 3. "Undefined Symbol: sys_alloc_aligned"
**Problem**: Linker error
**Cause**: Rust ziskos provides this, but we're using Zig
**Fix**: Implement it yourself (see above)

### 4. Incomplete 32-bit Instruction
**Problem**: Error from emulator
**Cause**: Unaligned code after ecall
**Fix**: Add `.align 4` after ecall

### 5. AT>ROM vs AT>RAM Confusion
**Problem**: Uninitialized data, crashes
**Cause**: Used `>RAM AT>ROM` pattern from bare-metal
**Fix**: Use `>RAM AT>RAM` for zkVM (no copying)

## Build Commands

```bash
# Build for Zisk zkVM
zig build

# Run in emulator
./zisk/target/release/ziskemu -e zig-out/bin/zevm-zisk

# With verbose output
./zisk/target/release/ziskemu -v -e zig-out/bin/zevm-zisk
```

## Zisk Precompiles (CSR-based)

When implementing crypto operations, use Zisk precompiles via CSR instructions:

```
0x800  KECCAKF       Keccak-f[1600]
0x801  ARITH256      256-bit mul+add
0x802  ARITH256_MOD  256-bit modular mul+add
0x803  SECP256K1_ADD Secp256k1 point add
0x804  SECP256K1_DBL Secp256k1 point double
0x805  SHA256F       SHA-256 compress
0x806  BN254_ADD     BN254 curve add
0x80B  ARITH384_MOD  384-bit modular ops
0x80C+ BLS12_381_*   BLS12-381 operations
```

**Invocation pattern (Zig)**:
```zig
asm volatile (
    "csrs 0x800, %[ptr]"
    :
    : [ptr] "r" (data_pointer)
    : "memory"
);
```

## Important Files to Reference

- `zisk/core/src/mem.rs`: Memory layout constants
- `zisk/ziskos/entrypoint/src/lib.rs`: Rust runtime reference
- `zisk/ziskos/entrypoint/src/syscalls/`: Precompile examples
- `zisk.ld`: Linker script with correct memory regions

## Debug Tips

1. **Check section placement**: `riscv64-unknown-elf-readelf -S zig-out/bin/zevm-zisk`
2. **Check program headers**: `riscv64-unknown-elf-readelf -l zig-out/bin/zevm-zisk`
3. **Disassemble**: `riscv64-unknown-elf-objdump -d zig-out/bin/zevm-zisk | less`
4. **Size breakdown**: `riscv64-unknown-elf-size zig-out/bin/zevm-zisk`

## Key Constraints

- ❌ No atomics (no A extension)
- ❌ No floating-point (no F/D extensions)
- ❌ No free/realloc (bump allocator only)
- ❌ No dynamic linking
- ✅ Pure integer arithmetic
- ✅ 256-bit operations via multi-precision
- ✅ ~511MB heap available
- ✅ Can use Zisk precompiles for crypto

## Module Naming

- `zisk` module (NOT `baremetal`) - contains zkVM-specific support
- Rust uses `ziskos` crate - we implement equivalent in Zig
- Import pattern: `const zisk = @import("zisk");`

## Testing

```bash
# Build
zig build

# Expected output from emulator
INIT
=== Zisk zkVM Block State Transition Demo ===
Creating in-memory database...
Setting up initial account state...
...
=== Block transition completed successfully ===
DONE
```

Exit code 0 = success, non-zero = failure
