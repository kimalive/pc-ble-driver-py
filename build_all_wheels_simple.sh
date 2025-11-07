#!/bin/bash
# Simple script to build all wheels for pc-ble-driver-py
# Usage: ./build_all_wheels_simple.sh

set -e

# Set vcpkg environment variables
export VCPKG_ROOT=${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

echo "=================================================================================="
echo "Building all wheels for pc-ble-driver-py"
echo "=================================================================================="
echo ""
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "CMAKE_TOOLCHAIN_FILE: $CMAKE_TOOLCHAIN_FILE"
echo ""

# Check if vcpkg is set up
if [ ! -f "$CMAKE_TOOLCHAIN_FILE" ]; then
    echo "⚠️  Error: CMAKE_TOOLCHAIN_FILE not found: $CMAKE_TOOLCHAIN_FILE"
    echo "   Please set VCPKG_ROOT environment variable"
    exit 1
fi

# Run the build script
bash build_wheels.sh

echo ""
echo "=================================================================================="
echo "Build complete! Wheels are in dist/"
echo "=================================================================================="
ls -lh dist/*.whl 2>/dev/null | awk '{print $9, "(" $5 ")"}' || echo "No wheels found"
