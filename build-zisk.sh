#!/bin/bash
set -e  # Exit on error

# Configuration
ZISK_REPO="https://github.com/0xPolygonHermez/zisk"
ZISK_BRANCH="main"  # or specify a specific tag/branch
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZISK_DIR="${SCRIPT_DIR}/zisk"

echo "========================================="
echo "Building Zisk VM"
echo "Repository: ${ZISK_REPO}"
echo "Install directory: ${ZISK_DIR}"
echo "========================================="

# Check for required tools
if ! command -v cargo &> /dev/null; then
    echo "Error: cargo (Rust) not found in PATH"
    echo "Please install Rust from: https://rustup.rs/"
    echo "Or run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "Error: git not found in PATH"
    echo "Please install git first"
    exit 1
fi

# Clone or update zisk repository
if [ -d "${ZISK_DIR}" ]; then
    echo "Zisk directory already exists. Updating..."
    cd "${ZISK_DIR}"
    git fetch origin
    git checkout "${ZISK_BRANCH}"
    git pull origin "${ZISK_BRANCH}"
else
    echo "Cloning zisk repository..."
    git clone --depth=1 "${ZISK_REPO}" "${ZISK_DIR}"
    cd "${ZISK_DIR}"
    git checkout "${ZISK_BRANCH}"
fi

# Build zisk emulator only (without proving dependencies)
echo "Building zisk emulator (this may take several minutes)..."
echo "Note: Building without proving support to avoid CUDA, libgmp, and other heavy dependencies"
cargo build --release --bin ziskemu --features no_lib_link

# Check if build was successful
if [ -f "target/release/ziskemu" ]; then
    echo ""
    echo "========================================="
    echo "Zisk VM build complete!"
    echo ""
    echo "Emulator binary: ${ZISK_DIR}/target/release/ziskemu"
    echo ""
    echo "You can now run your program with:"
    echo "  ${ZISK_DIR}/target/release/ziskemu -e hello_world.elf"
    echo ""
    echo "Or add an alias to your shell profile:"
    echo "  alias ziskemu='${ZISK_DIR}/target/release/ziskemu'"
    echo "========================================="
else
    echo "Error: Build failed - ziskemu binary not found"
    exit 1
fi
