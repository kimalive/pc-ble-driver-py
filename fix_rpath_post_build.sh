#!/bin/bash
# Post-build script to fix rpath in .so files
# This ensures Python library directory is in rpath

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_so_file>"
    exit 1
fi

SO_FILE="$1"

# Get Python library directory from Python itself
PYTHON_EXE="${PYTHON_EXECUTABLE:-python3}"
PYTHON_LIB_DIR=$($PYTHON_EXE -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null)

if [ -z "$PYTHON_LIB_DIR" ] || [ ! -d "$PYTHON_LIB_DIR" ]; then
    echo "Warning: Could not determine Python library directory"
    exit 0
fi

# Check if rpath already includes Python lib dir
CURRENT_RPATHS=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{getline; getline; if(/path/) print $2}')

if echo "$CURRENT_RPATHS" | grep -q "$PYTHON_LIB_DIR"; then
    echo "Python lib dir already in rpath: $PYTHON_LIB_DIR"
else
    echo "Adding Python lib dir to rpath: $PYTHON_LIB_DIR"
    install_name_tool -add_rpath "$PYTHON_LIB_DIR" "$SO_FILE" 2>/dev/null || true
fi

# Also add vcpkg lib dir if available
if [ -n "$VCPKG_ROOT" ]; then
    VCPKG_LIB_DIR="$VCPKG_ROOT/installed/arm64-osx/lib"
    if [ -d "$VCPKG_LIB_DIR" ]; then
        if echo "$CURRENT_RPATHS" | grep -q "$VCPKG_LIB_DIR"; then
            echo "VCPKG lib dir already in rpath: $VCPKG_LIB_DIR"
        else
            echo "Adding VCPKG lib dir to rpath: $VCPKG_LIB_DIR"
            install_name_tool -add_rpath "$VCPKG_LIB_DIR" "$SO_FILE" 2>/dev/null || true
        fi
    fi
fi

