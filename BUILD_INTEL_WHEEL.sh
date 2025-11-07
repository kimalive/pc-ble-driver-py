#!/bin/bash
# Script to build macOS Intel (x86_64) wheel for pc-ble-driver-py
# 
# Usage:
#   ./BUILD_INTEL_WHEEL.sh
#
# Prerequisites:
#   - vcpkg with nrf-ble-driver installed for x64-osx
#   - Python 3.8+ (Intel version)
#   - All build dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building macOS Intel (x86_64) wheel for pc-ble-driver-py${NC}"

# Check if we're on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}Error: This script must be run on macOS${NC}"
    exit 1
fi

# Check architecture
ARCH=$(arch)
echo "Current architecture: $ARCH"

# Check for vcpkg
if [ -z "$VCPKG_ROOT" ]; then
    echo -e "${YELLOW}Warning: VCPKG_ROOT not set. Please set it:${NC}"
    echo "  export VCPKG_ROOT=/path/to/vcpkg"
    exit 1
fi

if [ ! -d "$VCPKG_ROOT" ]; then
    echo -e "${RED}Error: VCPKG_ROOT directory does not exist: $VCPKG_ROOT${NC}"
    exit 1
fi

# Set up environment
export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"

# Check if nrf-ble-driver is installed
if [ ! -d "$VCPKG_ROOT/installed/x64-osx/share/nrf-ble-driver" ]; then
    echo -e "${YELLOW}Warning: nrf-ble-driver not found for x64-osx${NC}"
    echo "Installing nrf-ble-driver for x64-osx..."
    cd "$VCPKG_ROOT"
    ./vcpkg install nrf-ble-driver --triplet x64-osx
    cd -
fi

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
echo "Python version: $PYTHON_VERSION"

# Check if Python is Intel or ARM
PYTHON_ARCH=$(python3 -c "import platform; print(platform.machine())")
echo "Python architecture: $PYTHON_ARCH"

if [ "$PYTHON_ARCH" != "x86_64" ] && [ "$ARCH" == "arm64" ]; then
    echo -e "${YELLOW}Warning: Python appears to be ARM, but we need Intel for x86_64 wheel${NC}"
    echo "You may need to:"
    echo "  1. Install Intel Python via Homebrew: brew install python@3.12"
    echo "  2. Or use Rosetta: arch -x86_64 python3 ..."
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get the project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo -e "${GREEN}Building wheel...${NC}"

# Build the wheel
if [ "$ARCH" == "arm64" ] && [ "$PYTHON_ARCH" != "x86_64" ]; then
    # Cross-compile using Rosetta
    echo "Cross-compiling for x86_64 using Rosetta..."
    arch -x86_64 python3 setup.py bdist_wheel --build-type Release \
        -- -DCMAKE_OSX_ARCHITECTURES=x86_64
else
    # Native build
    python3 setup.py bdist_wheel --build-type Release \
        -- -DCMAKE_OSX_ARCHITECTURES=x86_64
fi

# Find the built wheel
WHEEL=$(ls -t dist/pc_ble_driver_py-*-macosx_*_x86_64.whl 2>/dev/null | head -1)

if [ -z "$WHEEL" ]; then
    echo -e "${RED}Error: Wheel not found in dist/ directory${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Wheel built successfully:${NC}"
echo "  $WHEEL"

# Verify the wheel
echo ""
echo "Verifying wheel..."
python3 -m wheel show "$WHEEL" | grep -E "(Filename|Tag|Compatible)" || true

echo ""
echo -e "${GREEN}Done!${NC}"
echo "Copy the wheel to your project's wheels/ directory:"
echo "  cp $WHEEL /path/to/your/project/wheels/"

