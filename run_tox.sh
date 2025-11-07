#!/bin/bash
# Helper script to run tox with proper environment setup

set -e

# Set up build environment
export VCPKG_ROOT=/Users/kbalive/Devel/OpenSource/vcpkg
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/arm64-osx

# Optional: Set hardware ports for hardware tests
# export PORT_A=/dev/tty.usbmodemE5FD57A3EBB32
# export PORT_B=/dev/tty.usbmodemE5FD57A3EBB32
# export NRF_FAMILY=NRF52
# export ITERATIONS=1

# Find tox - try multiple methods
# Note: We check if the command actually works, not just if it exists
# (pyenv shims may exist but not work if tox isn't installed for that Python version)
TOX_CMD=""
if command -v python3.12 &> /dev/null && python3.12 -m tox --version &> /dev/null 2>&1; then
    TOX_CMD="python3.12 -m tox"
elif [ -f /usr/local/bin/python3.12 ] && /usr/local/bin/python3.12 -m tox --version &> /dev/null 2>&1; then
    TOX_CMD="/usr/local/bin/python3.12 -m tox"
elif command -v python3 &> /dev/null && python3 -m tox --version &> /dev/null 2>&1; then
    TOX_CMD="python3 -m tox"
elif command -v tox &> /dev/null && tox --version &> /dev/null 2>&1; then
    TOX_CMD="tox"
else
    echo "Error: tox not found. Please install it with:"
    echo "  python3.12 -m pip install --user tox"
    echo "  or"
    echo "  pip install --user tox"
    exit 1
fi

# Run tox with arguments passed to this script
$TOX_CMD "$@"
