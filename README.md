# ZEVM RISC-V and zkVM Support

## Overview

zevm-zisk is a state-transition-function guest program for Zisk zkVM using upstream [zevm](https://github.com/10d9e/zevm.git).

Status is currently proof-of-concept.    

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

## Stateless Input Generation Tool

The `stateless-input-gen` tool converts JSON-RPC responses from Ethereum nodes into binary StatelessInput files for the zkVM.

### Build the Tool

```bash
# Build the input generation tool (for host OS, not cross-compiled)
zig build input-tool
```

### Usage

```bash
# Generate binary input from test vectors
zig build gen-input

# Or run directly with custom inputs
./zig-out/bin/stateless-input-gen \
  <block_json> \
  <witness_json> \
  <output_bin>
```

### Example

```bash
# Using test vectors
./zig-out/bin/stateless-input-gen \
  test/vectors/test_block.json \
  test/vectors/test_block_witness.json \
  stateless_input.bin

# The generated binary can be loaded into Zisk INPUT region
./zisk/target/release/ziskemu -e zig-out/bin/zevm-zisk --inputs stateless_input.bin
```

### Input Format

The tool expects:
- **block_json**: Output from `debug_getRawBlock` RPC call (RLP-encoded block)
- **witness_json**: Output from `debug_executionWitness` RPC call (state preimages)
- **output_bin**: Raw binary serialized StatelessInput (ziskemu adds the 16-byte header automatically)

The binary file contains just the serialized StatelessInput data. When loaded via ziskemu's `--inputs` flag, the emulator automatically adds a 16-byte header (8 bytes free_input + 8 bytes size) before placing it in the INPUT memory region at 0x90000000.

**WIP**: zevm-zisk is a proof-of-concept state transition function specifically for zisk zkevm, it: 
- Targets `riscv64-freestanding`
- Disables crypto libraries (blst, mcl) that aren't available in freestanding environments
- Uses the custom linker script (`zisk.ld`)
- Sets the medium code model for full 64-bit addressing
- Uses mock storage, mock blocks

## zkVM I/O Interface

This project implements the [proposed zkVM I/O Interface Standard](https://github.com/eth-act/zkvm-standards/pull/8/) for portable I/O operations:

```zig
const zkvm_io = @import("zkvm_io.zig");

// Read private input (zero-copy from INPUT region)
const input_data = zkvm_io.read_input_slice();

// Write public output (to OUTPUT region)
zkvm_io.write_output_slice(result);
```

See [docs/zkvm-io-interface.md](docs/zkvm-io-interface.md) for complete documentation.

### Recent Progress
- ✅ zkVM I/O Interface Standard implementation
- ✅ StatelessInput structure (Block + ExecutionWitness)
- ✅ Binary serialization/deserialization
- ✅ RLP decoder for blocks
- ✅ JSON-RPC response parser
- ✅ Input generation tool

### Precompile Status
- ✅ Keccak-256 (via Zisk CSR 0x800)
- ✅ SHA-256 (via Zisk CSR 0x805)
- ✅ secp256k1 operations (via Zisk CSRs 0x803-0x804)
- ✅ BN254 G1 operations: ecAdd, ecMul (via Zisk CSRs 0x806-0x807)
- 🚧 BN254 pairing (partial software implementation, waiting for Zisk CSR)
- [ ] ecRecover (ECDSA public key recovery)
- [ ] RIPEMD-160 hash
- [ ] blake2f compression
- [ ] modexp (big integer modular exponentiation)
- [ ] p256verify (secp256r1 signature verification)
- [ ] BLS12-381 operations (G1/G2 add, mul, pairing)
- [ ] KZG point evaluation (EIP-4844)

### TODO
- [ ] Complete transaction RLP decoding
- [ ] Parse withdrawals from blocks
- [ ] Witness → database population (full implementation)
- [ ] Transaction execution loop
- [ ] State root computation and verification
- [ ] Add RPC client for live queries

