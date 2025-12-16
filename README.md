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

