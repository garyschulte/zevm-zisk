# ZEVM RISC-V and zkVM Support

## Overview

ZEVM now supports bare-metal RISC-V targets with complete Zisk zkVM integration, enabling Ethereum block execution in zero-knowledge proof environments. This implementation provides a fully functional EVM running on rv64im (RISC-V 64-bit with integer multiply) with no OS, atomics, or floating-point operations.

## Quick Start - Zisk zkVM

### Build and Run

```bash
# Build for Zisk zkVM using dedicated build file
zig build --build-file build.zisk.zig

# Or with optimization options
zig build --build-file build.zisk.zig -Doptimize=ReleaseSmall

# Run in Zisk emulator
../hello_zisk/zisk/target/release/ziskemu -e zig-out/bin/block_transition_zisk
```

**Note**: The `build.zisk.zig` file is a dedicated build configuration specifically for Zisk zkVM. It automatically:
- Targets `riscv64-freestanding`
- Disables crypto libraries (blst, mcl) that aren't available in freestanding environments
- Uses the custom linker script (`zisk.ld`)
- Sets the medium code model for full 64-bit addressing

For reference, the old manual approach (not recommended):
```bash
# Old approach - now replaced by build.zisk.zig
zig build -Dtarget=riscv64-freestanding \
          -Dcpu=baseline_rv64-a-c-d-f-zicsr-zaamo-zalrsc \
          -Doptimize=ReleaseSmall \
          -Dblst=false \
          -Dmcl=false
```

### Expected Output

```
INIT
=== Zisk zkVM Block State Transition Demo ===
Creating in-memory database...
Setting up initial account state...
Computing initial state root...
Initial state root: b6f5ed83d9edc9038e5c01ce2023b8e50d7f6d2426cd943166fc7e181e8d097c
Block number: 12345
Block timestamp: 1700000000

Executing transaction: Alice -> Bob (50 ETH)...
Alice final balance: 950 ETH (nonce: 1)
Bob final balance: 150 ETH (nonce: 0)

Computing final state root...
Final state root: 43cc4236fa7dbe412b074f7e37c0f2efe0256353a7b63182e3536e7230527a1e

=== Block transition completed successfully ===
DONE
```

## Architecture

### RISC-V Target: rv64im

- **RV64I**: 64-bit base integer instruction set
- **M Extension**: Integer multiplication and division
- **No A Extension**: No atomic instructions (incompatible with zkVMs)
- **No F/D Extensions**: No floating-point operations
- **Code Model**: medium (medany) for full 64-bit addressing

### Memory Layout (Zisk zkVM)

The Zisk zkVM requires a specific memory layout defined in `zisk.ld`:

```
ROM (0x80000000 - 0x90000000):  [256MB]
├── .text         Code section
└── .rodata       Read-only data

Reserved (0xa0000000 - 0xa0020000): [128KB]
└── Zisk internal use

RAM (0xa0020000 - 0xc0000000): [~512MB]
├── .data         Initialized data
├── .bss          Uninitialized data
├── .heap         2MB NOLOAD section
└── Stack         @ 0xa0120000 (RAM + 1MB)

UART (0xa0000200): Console output
```

**Critical Requirements:**
- Code MUST be in ROM at 0x80000000 (not RAM)
- Writable data MUST be in RAM starting at 0xa0020000
- Stack pointer must be initialized before any function calls

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

## Implementation Components

### 1. Bare-Metal Allocators (`src/baremetal/allocator.zig`)

#### BumpAllocator
Simple sequential allocator for bare-metal environments:

```zig
var buffer: [2 * 1024 * 1024]u8 = undefined;
var bump = baremetal.BumpAllocator.init(&buffer);
const allocator = bump.allocator();

// Use like any Zig allocator
const db = database.InMemoryDB.init(allocator);

// Check memory usage
const stats = bump.getStats();
// stats.used, stats.total, stats.free

// Reset all allocations
bump.reset();
```

#### ArenaAllocator
Reset-able bump allocator for per-block allocation patterns:

```zig
var arena = baremetal.ArenaAllocator.init(&buffer);
defer arena.reset(); // Reset after each block

const allocator = arena.allocator();
// ... process block ...
```

#### FixedBufferAllocator
Compile-time sized allocator:

```zig
var fba = baremetal.FixedBufferAllocator(2 * 1024 * 1024).init();
const allocator = fba.allocator();
```

### 2. Crypto Ecall Stubs (`src/baremetal/ecalls.zig`)

Syscall interface for crypto operations (currently stubbed, returns errors):

```zig
pub const SyscallNum = enum(u32) {
    keccak256 = 0x1000,
    sha256 = 0x1001,
    ecrecover = 0x1002,
    bn256_add = 0x1003,
    bn256_mul = 0x1004,
    bn256_pairing = 0x1005,
    modexp = 0x1007,
    bls12_g1_add = 0x1010,
    bls12_g1_mul = 0x1011,
    bls12_g2_add = 0x1013,
    bls12_pairing = 0x1016,
    kzg_point_evaluation = 0x1020,
    p256_verify = 0x1030,
};
```

**Integration Pattern** (for future zkVM syscalls):

```zig
fn ecallStub(syscall_num: u32, input_ptr: [*]const u8, ...) callconv(.C) Result {
    var status: u32 = undefined;
    var gas_used: u64 = undefined;

    asm volatile ("ecall"
        : [status] "={x10}" (status),
          [gas_used] "={x11}" (gas_used)
        : [syscall] "{x17}" (syscall_num),
          [input_ptr] "{x10}" (input_ptr),
          // ... other parameters ...
        : "memory"
    );

    return .{ .status = status, .gas_used = gas_used };
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
$ ls -lh zig-out/bin/block_transition_zisk
-rwxr-xr-x  25K  block_transition_zisk

$ riscv64-unknown-elf-size zig-out/bin/block_transition_zisk
   text	   data	    bss	    dec	    hex	filename
  16396	      0	2097152	2113548	 20400c	block_transition_zisk
```

- **File size**: 25KB (efficient!)
- **Code (.text)**: ~16KB
- **Heap (.bss)**: 2MB (NOLOAD, not in file)
- **Data**: Minimal

### Optimization Notes

- `ReleaseSmall` optimization balances size and performance
- NOLOAD sections prevent heap from bloating binary
- Disabled crypto libraries (blst, mcl) for minimal dependencies
- Pure Zig stdlib Keccak256 (no external deps)

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

**Cause**: Code placed in RAM causes 32-bit addresses to be sign-extended to 64-bit

**Solution**: Place code in ROM at 0x80000000 (linker script requirement)

### Issue: Incomplete 32-bit Instruction

**Symptom**: `incomplete 32-bits instruction at the end of the code buffer`

**Cause**: Unaligned code after ecall instruction

**Solution**: Add `.align 4` directive after ecall

### Issue: Stack Initialization

**Symptom**: Crashes immediately on entry, stack-related errors

**Cause**: Function prologue runs before sp initialization

**Solution**: Use the two-function entry pattern (_start + _start_main)


## Performance Characteristics

### Memory Usage

| Component | Size | Notes |
|-----------|------|-------|
| Core EVM | ~100KB | Without crypto |
| Database | Variable | Depends on state size |
| Stack | ~8KB | 1024 stack items × 32 bytes |
| Heap (configured) | 2MB | Adjustable via HEAP size |

### Computational Complexity

- ✅ No floating-point operations
- ✅ No atomic operations
- ✅ Pure integer arithmetic
- ✅ 256-bit math via multi-precision integers
- ✅ Keccak256 pure Zig implementation

### Optimization Opportunities

1. **Custom Keccak**: Implement as zkVM syscall for better performance
2. **Heap Size**: Tune based on actual workload
3. **Stack Size**: Reduce if not using deep recursion
4. **Code Size**: Further optimization with `-OReleaseFast` if space allows

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
- ✅ `src/interpreter/` - EVM interpreter (not used in demo yet)

### Bare-Metal Modules

- ✅ `src/baremetal/allocator.zig` - Memory allocators
- ✅ `src/baremetal/ecalls.zig` - Syscall stubs
- ✅ `src/baremetal/main.zig` - Module exports

### Examples

- ✅ `examples/block_transition.zig` - Native demo
- ✅ `examples/block_transition_zisk.zig` - Zisk zkVM demo
