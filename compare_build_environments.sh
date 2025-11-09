#!/bin/bash
# Compare local build environment with GitHub Actions build environment
# This script captures the same information that GitHub Actions will log

set -e

echo "=================================================================================="
echo "Local Build Environment Analysis"
echo "=================================================================================="
echo ""

# System Info
echo "=== System Info ==="
echo "macOS version: $(sw_vers -productVersion)"
echo "macOS build: $(sw_vers -buildVersion)"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo ""

# Compiler Info
echo "=== Compiler Info ==="
echo "CC: $(which cc)"
echo "CXX: $(which c++)"
echo "CC version: $(cc --version 2>/dev/null | head -1 || echo 'Unknown')"
echo "CXX version: $(c++ --version 2>/dev/null | head -1 || echo 'Unknown')"
echo ""

# CMake Info
echo "=== CMake Info ==="
cmake --version || echo "⚠️  cmake not found"
echo ""

# Python versions to check
PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")

for py_ver in "${PYTHON_VERSIONS[@]}"; do
    # Try to find Python executable
    PYTHON_EXE=""
    if command -v "python${py_ver}" >/dev/null 2>&1; then
        PYTHON_EXE="python${py_ver}"
    elif [ -d "$HOME/.pyenv/versions/${py_ver}" ]; then
        PYTHON_EXE="$HOME/.pyenv/versions/${py_ver}/bin/python"
    elif [ -d ".tox/py${py_ver//./}/bin/python" ]; then
        PYTHON_EXE=".tox/py${py_ver//./}/bin/python"
    fi
    
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        echo "⚠️  Python ${py_ver} not found, skipping..."
        continue
    fi
    
    echo "=================================================================================="
    echo "Python ${py_ver} Build Configuration"
    echo "=================================================================================="
    echo ""
    
    PYTHON_EXE_ABS=$(cd "$(dirname "$PYTHON_EXE")" && pwd)/$(basename "$PYTHON_EXE")
    PYTHON_ROOT_DIR=$(dirname "$(dirname "$PYTHON_EXE_ABS")")
    
    echo "=== Python Installation Info ==="
    echo "Python executable: $PYTHON_EXE_ABS"
    echo "Python root: $PYTHON_ROOT_DIR"
    echo "Python version: $($PYTHON_EXE_ABS --version 2>&1)"
    echo ""
    
    echo "=== Python Build Configuration ==="
    $PYTHON_EXE_ABS -c "
import sysconfig
import sys
import os

print(f'MACOSX_DEPLOYMENT_TARGET: {sysconfig.get_config_var(\"MACOSX_DEPLOYMENT_TARGET\")}')
print(f'CFLAGS: {sysconfig.get_config_var(\"CFLAGS\")}')
print(f'LDFLAGS: {sysconfig.get_config_var(\"LDFLAGS\")}')
print(f'LDSHARED: {sysconfig.get_config_var(\"LDSHARED\")}')
print(f'CC: {sysconfig.get_config_var(\"CC\")}')
print(f'CXX: {sysconfig.get_config_var(\"CXX\")}')
print(f'Python executable: {sys.executable}')
print(f'Python prefix: {sys.prefix}')
print(f'Python base prefix: {sys.base_prefix}')
print(f'Python framework: {sysconfig.get_config_var(\"PYTHONFRAMEWORK\") or \"not set\"}')

# Get Python library path
libdir = sysconfig.get_config_var('LIBDIR')
libfile = sysconfig.get_config_var('LIBRARY')
if libfile:
    libpath = f'{libdir}/{libfile}'
else:
    libpath = libdir
print(f'Python library path: {libpath}')
if os.path.exists(libpath):
    print(f'  ✓ Library exists')
    if os.path.islink(libpath):
        print(f'  → Symlink to: {os.readlink(libpath)}')
else:
    print(f'  ✗ Library not found')
" 2>&1 || echo "⚠️  Could not get Python build config"
    echo ""
    
    echo "=== Environment Variables ==="
    echo "VCPKG_ROOT: ${VCPKG_ROOT:-not set}"
    echo "CMAKE_TOOLCHAIN_FILE: ${CMAKE_TOOLCHAIN_FILE:-not set}"
    echo "CMAKE_PREFIX_PATH: ${CMAKE_PREFIX_PATH:-not set}"
    echo "DYLD_LIBRARY_PATH: ${DYLD_LIBRARY_PATH:-not set}"
    echo "MACOSX_DEPLOYMENT_TARGET: ${MACOSX_DEPLOYMENT_TARGET:-not set}"
    echo "CFLAGS: ${CFLAGS:-not set}"
    echo "CXXFLAGS: ${CXXFLAGS:-not set}"
    echo "LDFLAGS: ${LDFLAGS:-not set}"
    echo ""
    
    # Check if we have a built wheel for this version
    WHEEL=$(ls -t dist/pc_ble_driver_py-*-cp${py_ver//./}-abi3-*.whl 2>/dev/null | head -1)
    if [ -n "$WHEEL" ] && [ -f "$WHEEL" ]; then
        echo "=== Built Wheel Analysis ==="
        echo "Wheel: $(basename "$WHEEL")"
        echo "Size: $(ls -lh "$WHEEL" | awk '{print $5}')"
        echo ""
        
        # Extract and check .so file
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        unzip -q "$WHEEL" 2>/dev/null || true
        
        SO_FILE=$(find . -name "_nrf_ble_driver_sd_api_v5.so" -type f | head -1)
        if [ -n "$SO_FILE" ] && [ -f "$SO_FILE" ]; then
            echo "=== .so File Analysis ==="
            echo "File: $SO_FILE"
            echo "Size: $(ls -lh "$SO_FILE" | awk '{print $5}')"
            echo ""
            echo "Linking info:"
            otool -L "$SO_FILE" | head -10
            echo ""
            echo "Python library link:"
            otool -L "$SO_FILE" | grep -E "(python|Python)" || echo "  ⚠️  No Python library found"
            echo ""
            echo "RPath:"
            otool -l "$SO_FILE" | grep -A 2 "LC_RPATH" || echo "  No RPATH found"
            echo ""
            echo "File type:"
            file "$SO_FILE"
        fi
        
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
    else
        echo "⚠️  No built wheel found for Python ${py_ver}"
    fi
    
    echo ""
done

echo "=================================================================================="
echo "Summary"
echo "=================================================================================="
echo ""
echo "This script captures the same information that GitHub Actions will log."
echo "Compare the output with GitHub Actions build logs to identify differences."
echo ""

