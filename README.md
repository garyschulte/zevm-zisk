# ZEVM RISC-V and zkVM Support

## Overview

zevm-zisk is a state-transition-function guest program for Zisk zkVM using upstream [zevm](https://github.com/10d9e/zevm.git).

## Quick Start - Zisk zkVM

### Build and Run

```bash
# download and build zevm:
`bash ./build-zisk.sh`

# Build for Zisk zkVM using dedicated build file
`zig build` 

# Or with optimization options
zig build -Doptimize=ReleaseSmall

# Run in Zisk emulator
./zisk/target/release/ziskemu -e zig-out/bin/zevm-zisk
```

**WIP**: zevm-zisk is a proof-of-concept state transition function specifically for zisk zkevm, it: 
- Targets `riscv64-freestanding`
- Disables crypto libraries (blst, mcl) that aren't available in freestanding environments
- Uses the custom linker script (`zisk.ld`)
- Sets the medium code model for full 64-bit addressing
- Uses mock storage, mock blocks

TODO:
- precompile ecall implementations
- block and witness input state implementation
- block processing


## Architecture

### RISC-V Target: rv64im

- **RV64I**: 64-bit base integer instruction set
- **M Extension**: Integer multiplication and division
- **No A Extension**: No atomic instructions (incompatible with zkVMs)
- **No F/D Extensions**: No floating-point operations
- **Code Model**: medium (medany) for full 64-bit addressing

### Memory Layout (Zisk zkVM)

The Zisk zkVM uses a specific memory layout defined in `zisk.ld`. Understanding this layout is critical for implementing guest programs:

```
ROM (Code/Read-Only): 0x80000000 - 0x87FFFFFF [128MB]
├── 0x80000000    Program ROM start (your code here)
├── .text         Code section
├── .rodata       Read-only data
└── 0x87F00000    Float library ROM (last 1MB, reserved)

INPUT (Read-Only): 0x90000000 - 0x98000000 [128MB max]
└── Program input data (written during initialization)

SYSTEM (R/W): 0xa0000000 - 0xa0010000 [64KB]
├── 0xa0000000    Register file (32 registers × 8 bytes = 256 bytes)
├── 0xa0000200    UART_ADDR (stdout, write single bytes)
├── 0xa0001000    Float registers (FREG_FIRST)
└── 0xa0008000    CSR registers (CSR_ADDR)

OUTPUT (R/W): 0xa0010000 - 0xa0020000 [64KB]
└── Public output data (ziskos::set_output)

RAM (R/W): 0xa0020000 - 0xc0000000 [~512MB]
├── .data         Initialized writable data (VMA=LMA in RAM)
├── .bss          Zero-initialized data
├── Stack         1MB (grows down from _init_stack_top)
└── Heap          Dynamic allocation via sys_alloc_aligned
                  From: _kernel_heap_bottom (after stack)
                  To:   0xc0000000 (~511MB available)

FLOAT LIB RAM: 0xafff0000 - 0xc0000000 [64KB]
└── Float library runtime memory (reserved)
```

**Critical Requirements:**
- Code MUST be in ROM (0x80000000-0x87EFFFFF)
- Float library region (0x87F00000+) is reserved - don't use
- Writable data uses `>RAM AT>RAM` (VMA=LMA, no copying needed)
- Heap grows upward via `sys_alloc_aligned` (bump allocator)
- All addresses are 64-bit, but ROM is in positive 32-bit range

### Entry Point Pattern

The entry point uses a two-function pattern to avoid stack initialization issues:

```zig
/// Entry point - pure assembly, no prologue
export fn _start() linksection(".text._start") noreturn {
    asm volatile (
        \\ li sp, 0xa0120000    // Initialize stack pointer
        \\ li gp, 0xa0020000    // Initialize global pointer
        \\ call _start_main     // Call main initialization
        \\ // ... wfi loop ...
    );
    unreachable;
}

/// Main initialization - regular Zig code with stack
export fn _start_main() noreturn {
    // Now safe to use regular Zig features
    uartWrite("INIT\n");
    main() catch |err| {
        uartWrite("ERROR\n");
        zkExit(1);
    };
    zkExit(0);
}
```

**Why This Pattern?**
- Zig generates a function prologue that uses the stack
- The prologue runs BEFORE inline assembly in the function body
- Therefore, sp/gp must be initialized in pure assembly first

### Linker Script Details (`zisk.ld`)

**Key Insight: zkVM vs Bare-Metal**

Traditional embedded systems use `>RAM AT>ROM` for `.data` sections:
```ld
.data : {
    *(.data .data.*)
} >RAM AT>ROM  /* VMA in RAM, LMA in ROM - requires copying */
```

This requires startup code to copy data from ROM to RAM. **Zisk doesn't work this way!**

Zisk zkVM uses `>RAM AT>RAM` for writable data:
```ld
.data : {
    *(.data .data.*)
} >RAM AT>RAM  /* VMA = LMA, both in RAM */
```

**Why?**
- The zkVM emulator/prover loads your ELF and **initializes memory directly**
- No copying needed - memory is already set up when your program starts
- This is standard for virtual machines (like running on an OS)

**Memory Regions in zisk.ld:**
```ld
MEMORY {
    ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 0x08000000  /* 128MB */
    RAM (rw)  : ORIGIN = 0xa0020000, LENGTH = 0x1FFE0000  /* ~512MB */
}

SECTIONS {
    .text : { ... } >ROM :text
    .rodata : { ... } >ROM :text

    /* IMPORTANT: Both VMA and LMA in RAM */
    .data : { ... } >RAM AT>RAM :data
    .bss : { ... } >RAM AT>RAM :bss

    /* Heap grows from here */
    PROVIDE(_kernel_heap_bottom = _init_stack_top);
    PROVIDE(_kernel_heap_top = ORIGIN(RAM) + LENGTH(RAM));
}
```

## Implementation Components

### 1. Zisk zkVM Allocators (`src/zisk/allocator.zig`)

#### ZiskAllocator (Recommended)
Dynamic allocator using Zisk's `sys_alloc_aligned` runtime function:

```zig
const zisk = @import("zisk");

// Initialize - uses Zisk's kernel heap (~511MB available)
var zisk_alloc = zisk.ZiskAllocator.init();
const allocator = zisk_alloc.allocator();

// Use like any Zig allocator
const db = database.InMemoryDB.init(allocator);
```

**How it works:**
- Calls `sys_alloc_aligned(bytes, alignment)` for each allocation
- Bump allocator: allocates from `_kernel_heap_bottom` upward
- No free/realloc support (zkVM constraint)
- Backed by ~511MB of RAM (after 1MB stack)

**Implementation:**
```zig
export fn sys_alloc_aligned(bytes: usize, alignment: usize) [*]u8 {
    // Static heap position tracker
    if (heap_pos == 0) {
        heap_pos = @intFromPtr(&_kernel_heap_bottom);
    }

    // Align and allocate
    heap_pos = alignForward(heap_pos, alignment);
    const ptr = heap_pos;
    heap_pos += bytes;
    return @ptrFromInt(ptr);
}
```

#### BumpAllocator (For Fixed Buffers)
Sequential allocator when you want to manage your own buffer:

```zig
var buffer: [1024 * 1024]u8 = undefined;  // 1MB buffer
var bump = zisk.BumpAllocator.init(&buffer);
const allocator = bump.allocator();

// Check usage
const stats = bump.getStats();
// stats.used, stats.total, stats.free

// Reset for reuse
bump.reset();
```

#### ArenaAllocator
Reset-able bump allocator for per-block patterns:

```zig
var buffer: [1024 * 1024]u8 = undefined;
var arena = zisk.ArenaAllocator.init(&buffer);
defer arena.reset();  // Clear after each iteration

const allocator = arena.allocator();
// ... process block ...
```

### 2. Zisk Syscalls/Precompiles

Zisk implements precompiles as **CSR instructions** (not traditional ecalls). The syscall range is `0x800-0x84F` (80 syscalls):

```
Available Precompiles (via csrs instruction):
├── 0x800  SYSCALL_KECCAKF_ID        Keccak-f[1600] permutation
├── 0x801  SYSCALL_ARITH256_ID       256-bit multiply-add
├── 0x802  SYSCALL_ARITH256_MOD_ID   256-bit modular multiply-add
├── 0x803  SYSCALL_SECP256K1_ADD_ID  Secp256k1 point addition
├── 0x804  SYSCALL_SECP256K1_DBL_ID  Secp256k1 point doubling
├── 0x805  SYSCALL_SHA256F_ID        SHA-256 compress function
├── 0x806  SYSCALL_BN254_CURVE_ADD_ID    BN254 point addition
├── 0x807  SYSCALL_BN254_CURVE_DBL_ID    BN254 point doubling
├── 0x808  SYSCALL_BN254_COMPLEX_ADD_ID  BN254 Fp2 addition
├── 0x80B  SYSCALL_ARITH384_MOD_ID   384-bit modular multiply-add
├── 0x80C  SYSCALL_BLS12_381_CURVE_ADD_ID    BLS12-381 G1 add
├── 0x80D  SYSCALL_BLS12_381_CURVE_DBL_ID    BLS12-381 G1 double
└── 0x811  SYSCALL_ADD256_ID         256-bit addition with carry
```

**Zig Implementation Pattern:**

```zig
// Hypothetical Zisk precompile wrapper
fn ziskKeccakF(state: *[25]u64) void {
    asm volatile (
        \\ csrs 0x800, %[state]
        :
        : [state] "r" (state)
        : "memory"
    );
}
```

**Key Differences from Traditional Ecalls:**
- Uses `csrs` (CSR set) instead of `ecall` instruction
- CSR address encodes the precompile ID (0x800-0x84F)
- Parameters passed via registers or memory pointers
- When transpiled to Zisk, these become optimized precompile operations

**Exit Syscall (Traditional Ecall):**

```zig
fn zkExit(exit_code: u32) noreturn {
    asm volatile (
        \\ ecall
        :
        : [exit_code] "{a0}" (exit_code),
          [syscall] "{a7}" (93)  // Linux exit syscall number
        : "memory"
    );
    while (true) {
        asm volatile ("wfi");
    }
}
```

### 3. UART Console Output

Direct memory-mapped I/O for debugging:

```zig
const ZISK_UART: *volatile u8 = @ptrFromInt(0xa0000200);

fn uartWrite(bytes: []const u8) void {
    for (bytes) |byte| {
        ZISK_UART.* = byte;
    }
}

fn uartPrint(comptime fmt: []const u8, args: anytype) void {
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(&buffer, fmt, args) catch "FORMAT ERROR\n";
    uartWrite(message);
}
```

### 4. Exit Syscall

Clean program termination via Zisk zkVM syscall:

```zig
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
```

## Block State Transition Example

### Implementation (`examples/block_transition_zisk.zig`)

Demonstrates a complete Ethereum block execution:

1. **Initialize Memory**: 2MB heap with BumpAllocator
2. **Create Database**: In-memory account storage
3. **Setup Initial State**: Alice (1000 ETH), Bob (100 ETH)
4. **Compute State Root**: Keccak256 hash of all account data
5. **Execute Transaction**: Alice sends 50 ETH to Bob
6. **Update State**: Balances and nonces
7. **Verify State Change**: New state root differs from initial

### State Root Computation

Simplified implementation (not full Merkle Patricia Trie):

```zig
fn computeSimpleStateRoot(db: *database.InMemoryDB) !primitives.Hash {
    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});

    var account_iter = db.accounts.iterator();
    var count: u32 = 0;

    while (account_iter.next()) |entry| {
        const address = entry.key_ptr.*;
        const account = entry.value_ptr.*;

        hasher.update(&address);

        var balance_bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &balance_bytes, account.balance, .big);
        hasher.update(&balance_bytes);

        var nonce_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &nonce_bytes, account.nonce, .big);
        hasher.update(&nonce_bytes);

        hasher.update(&account.code_hash);
        count += 1;
    }

    var count_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &count_bytes, count, .big);
    hasher.update(&count_bytes);

    var result: primitives.Hash = undefined;
    hasher.final(&result);
    return result;
}
```

**Production Note**: A full implementation would use a proper Merkle Patricia Trie for:
- Deterministic ordering
- Efficient state proofs
- Ethereum compatibility

### Transaction Execution

Simple value transfer with validation:

```zig
fn executeValueTransfer(
    db: *database.InMemoryDB,
    from: primitives.Address,
    to: primitives.Address,
    value: primitives.U256,
    nonce: u64,
) !void {
    // Get sender account
    var sender_account = (try db.basic(from)) orelse {
        return error.AccountNotFound;
    };

    // Validate
    if (sender_account.balance < value) return error.InsufficientBalance;
    if (sender_account.nonce != nonce) return error.InvalidNonce;

    // Get or create receiver account
    var receiver_account = (try db.basic(to)) orelse
        state.AccountInfo.fromBalance(0);

    // Update balances
    sender_account.balance -= value;
    sender_account.nonce += 1;
    receiver_account.balance += value;

    // Write back to database
    try db.insertAccount(from, sender_account);
    try db.insertAccount(to, receiver_account);
}
```

## Binary Characteristics

### Size and Sections

```bash
$ ls -lh zig-out/bin/zevm-zisk
-rwxr-xr-x  3.0M  zevm-zisk

$ riscv64-unknown-elf-size zig-out/bin/zevm-zisk
   text    data     bss     dec     hex filename
 123456      128    4096  127680   1f2a0 zevm-zisk  (example values)
```

**Size breakdown:**
- **File size**: ~3MB (includes full EVM interpreter + state management)
- **Code (.text)**: Majority of size (EVM opcodes, crypto, etc.)
- **Data (.data)**: Minimal initialized data
- **BSS (.bss)**: Zero-initialized data
- **No static heap**: Uses dynamic allocation from kernel heap

### Optimization Notes

- `ReleaseSmall` optimization balances size and performance
- No NOLOAD sections needed - heap is dynamically allocated
- Disabled crypto libraries (blst, mcl) for freestanding compatibility
- Pure Zig stdlib Keccak256 implementation
- ~511MB heap available via `sys_alloc_aligned`

## Build System Integration

### Build Options

| Option | Description | Required |
|--------|-------------|----------|
| `-Dtarget=riscv64-freestanding` | Bare-metal RISC-V 64-bit | Yes |
| `-Dcpu=baseline_rv64-a-c-d-f-zicsr-zaamo-zalrsc` | rv64im only | Yes |
| `-Doptimize=ReleaseSmall` | Size optimization | Recommended |
| `-Dblst=false` | Disable BLS12-381 library | Yes (zkVM) |
| `-Dmcl=false` | Disable BN254 library | Yes (zkVM) |

### Targets in build.zig

```zig
// Native example (for testing)
const block_transition = b.addExecutable(.{
    .name = "block_transition",
    .root_source_file = .{ .path = "examples/block_transition.zig" },
    .target = target,
    .optimize = optimize,
});

// Zisk zkVM target
const block_transition_zisk_exe = b.addExecutable(.{
    .name = "block_transition_zisk",
    // ... module configuration ...
});

// Use custom linker script and code model for Zisk
if (target.result.os.tag == .freestanding) {
    block_transition_zisk_exe.setLinkerScript(.{
        .src_path = .{ .owner = b, .sub_path = "zisk.ld" }
    });
    block_transition_zisk_exe.root_module.code_model = .medium;
}
```

## Testing and Validation

### Native Testing

For development and debugging on native platforms:

```bash
# Build native version (macOS/Linux)
zig build -Dblst=false -Dmcl=false

# Run locally
./zig-out/bin/block_transition
```

### Zisk zkVM Testing

```bash
# Build for Zisk
zig build -Dtarget=riscv64-freestanding \
          -Dcpu=baseline_rv64-a-c-d-f-zicsr-zaamo-zalrsc \
          -Doptimize=ReleaseSmall \
          -Dblst=false -Dmcl=false

# Run in emulator
../hello_zisk/zisk/target/release/ziskemu -e zig-out/bin/block_transition_zisk

# Verify exit code
echo $?  # Should be 0 for success
```

### Debugging

#### Verbose Emulator Output

```bash
../hello_zisk/zisk/target/release/ziskemu -v -e zig-out/bin/block_transition_zisk
```

#### Disassembly

```bash
riscv64-unknown-elf-objdump -d zig-out/bin/block_transition_zisk | less
```

#### ELF Analysis

```bash
riscv64-unknown-elf-readelf -l zig-out/bin/block_transition_zisk  # Program headers
riscv64-unknown-elf-readelf -S zig-out/bin/block_transition_zisk  # Sections
riscv64-unknown-elf-readelf -A zig-out/bin/block_transition_zisk  # RISC-V attributes
riscv64-unknown-elf-size zig-out/bin/block_transition_zisk         # Size breakdown
```

## Known Issues and Solutions

### Issue: Sign-Extension Errors

**Symptom**: `Address out of range: 18446744071025197048` (0xFFFFFFFF...)

**Cause**: Code placed in RAM (0xa0000000+) causes 32-bit addresses to be sign-extended to 64-bit negative values

**Solution**: Place code in ROM at 0x80000000 (positive 32-bit range)

### Issue: Incomplete 32-bit Instruction

**Symptom**: `incomplete 32-bits instruction at the end of the code buffer`

**Cause**: Unaligned code after ecall instruction

**Solution**: Add `.align 4` directive after ecall in assembly

### Issue: Stack Initialization

**Symptom**: Crashes immediately on entry, stack-related errors

**Cause**: Function prologue runs before sp initialization

**Solution**: Use two-function entry pattern (_start pure assembly + _start_main with stack)

### Issue: Incorrect Alignment Panic

**Symptom**: `PANIC: incorrect alignment` immediately on start

**Cause**: Code references a `.heap` section that's not defined in linker script

**Solution**: Either:
1. Use `ZiskAllocator` (dynamic heap via `sys_alloc_aligned`) - **Recommended**
2. Or add `.heap (NOLOAD)` section to linker script for static buffers

### Issue: Undefined Symbol `sys_alloc_aligned`

**Symptom**: `ld.lld: undefined symbol: sys_alloc_aligned`

**Cause**: Rust's ziskos runtime provides this, but we're writing in Zig

**Solution**: Implement it yourself (see `src/zisk/allocator.zig:8-30`)


## Performance Characteristics

### Memory Usage

| Component | Size | Notes |
|-----------|------|-------|
| Core EVM | ~1-2MB | With full interpreter |
| Database | Variable | Depends on state size |
| Stack | 1MB | Linker-configured via _init_stack_top |
| Heap | ~511MB | Dynamic, from _kernel_heap_bottom |

### Computational Complexity

- ✅ No floating-point operations
- ✅ No atomic operations
- ✅ Pure integer arithmetic
- ✅ 256-bit math via multi-precision integers
- ✅ Keccak256 pure Zig implementation

### Optimization Opportunities

1. **Use Zisk Precompiles**: Replace Zig crypto with CSR-based precompiles
   - Keccak-f (0x800) instead of software implementation
   - SHA256 (0x805) for faster hashing
   - BN254/BLS12-381 operations for signature verification

2. **Tune Stack Size**: 1MB may be excessive for most programs
3. **Memory Pooling**: Reuse allocations with ArenaAllocator reset patterns
4. **Code Size**: Further optimize with `-OReleaseFast` vs `-OReleaseSmall`

## Future Enhancements

### Short Term

1. **Crypto Precompiles**: Implement via Zisk ecalls
   - ECRECOVER (secp256k1)
   - SHA256
   - RIPEMD160
   - ModExp

2. **EVM Bytecode Execution**: Add interpreter support
   - Opcode dispatch
   - Gas metering
   - Contract calls

3. **Full MPT**: Replace simplified state root with Merkle Patricia Trie

### Medium Term

4. **Transaction Pool**: Support multiple transactions per block
5. **Block Rewards**: Proper coinbase handling
6. **Gas Accounting**: Full EIP-1559 support
7. **Receipt Generation**: Transaction receipts with logs


## Module Structure

### Core Modules (Cross-Platform)

- ✅ `src/primitives/` - Address, U256, Hash types
- ✅ `src/bytecode/` - Opcode definitions
- ✅ `src/state/` - Account info
- ✅ `src/database/` - In-memory DB
- ✅ `src/context/` - Block context
- ✅ `src/interpreter/` - EVM interpreter
- ✅ `src/precompile/` - Precompile implementations
- ✅ `src/handler/` - Execution handler

### Zisk zkVM Support Module

- ✅ `src/zisk/allocator.zig` - ZiskAllocator, BumpAllocator, ArenaAllocator
- ✅ `src/zisk/ecalls.zig` - Placeholder ecall stubs (for compatibility)
- ✅ `src/zisk/main.zig` - Module exports

### Main Program

- ✅ `src/main.zig` - Zisk zkVM state transition demo

### Build Configuration

- ✅ `build.zig` - Zig build system configuration
- ✅ `zisk.ld` - Custom linker script for Zisk zkVM memory layout
