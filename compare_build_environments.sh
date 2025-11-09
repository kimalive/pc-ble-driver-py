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

# Check build_wheels.sh for MACOSX_DEPLOYMENT_TARGET setting
echo "=== Build Configuration (from build_wheels.sh) ==="
if [ -f "build_wheels.sh" ]; then
    BUILD_DEPLOYMENT_TARGET=$(grep -E "^export MACOSX_DEPLOYMENT_TARGET=" build_wheels.sh | sed 's/.*=//' | tr -d '"' | tr -d "'")
    if [ -n "$BUILD_DEPLOYMENT_TARGET" ]; then
        echo "MACOSX_DEPLOYMENT_TARGET set in build_wheels.sh: $BUILD_DEPLOYMENT_TARGET"
    else
        echo "MACOSX_DEPLOYMENT_TARGET: not set in build_wheels.sh (should be 11.0)"
    fi
else
    echo "build_wheels.sh not found"
fi
echo ""

# Function to find Python executable (same as build_wheels.sh)
find_python() {
    local version=$1
    # Try tox environment first (most reliable)
    local tox_python=".tox/py${version//./}/bin/python"
    if [ -f "$tox_python" ]; then
        echo "$tox_python"
        return 0
    fi
    # Try common locations
    for base in "/usr/local/bin" "/opt/homebrew/bin" "$HOME/.pyenv/versions/${version}/bin"; do
        if [ -f "${base}/python${version}" ]; then
            echo "${base}/python${version}"
            return 0
        fi
    done
    # Try pyenv with patch version matching
    if command -v pyenv &> /dev/null; then
        local pyenv_version=$(pyenv versions --bare 2>/dev/null | grep "^${version}\." | sort -V | tail -1)
        if [ -n "$pyenv_version" ] && [ -f "${HOME}/.pyenv/versions/${pyenv_version}/bin/python" ]; then
            echo "${HOME}/.pyenv/versions/${pyenv_version}/bin/python"
            return 0
        fi
    fi
    # Try direct command
    if command -v "python${version}" &> /dev/null; then
        if "python${version}" --version &> /dev/null 2>&1; then
            echo "python${version}"
            return 0
        fi
    fi
    return 1
}

# Python versions to check
PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")

for py_ver in "${PYTHON_VERSIONS[@]}"; do
    # Try to find Python executable
    PYTHON_EXE=$(find_python "$py_ver")
    
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        echo "⚠️  Python ${py_ver} not found, checking for wheels only..."
        # Still check for wheels even if Python isn't found
        WHEEL=$(ls -t dist/pc_ble_driver_py-*-cp${py_ver//./}-abi3-*.whl 2>/dev/null | head -1)
        if [ -n "$WHEEL" ] && [ -f "$WHEEL" ]; then
            echo "  Found wheel: $(basename "$WHEEL")"
            echo "  (Python executable not available for full analysis)"
        fi
        echo ""
        continue
    fi
    
    echo "=================================================================================="
    echo "Python ${py_ver} Build Configuration"
    echo "=================================================================================="
    echo ""
    echo "NOTE: This matches how build_wheels.sh finds and uses Python (tox venv first)"
    echo ""
    
    PYTHON_EXE_ABS=$(cd "$(dirname "$PYTHON_EXE")" && pwd)/$(basename "$PYTHON_EXE")
    PYTHON_ROOT_DIR=$(dirname "$(dirname "$PYTHON_EXE_ABS")")
    
    # Check if this is a tox venv (like build_wheels.sh uses)
    if [[ "$PYTHON_EXE_ABS" == *"/.tox/"* ]]; then
        echo "✓ Using tox venv Python (same as build_wheels.sh)"
    else
        echo "⚠️  Using system Python (build_wheels.sh prefers tox venv)"
    fi
    echo ""
    
    echo "=== Python Installation Info ==="
    echo "Python executable: $PYTHON_EXE_ABS"
    echo "Python root: $PYTHON_ROOT_DIR"
    echo "Python version: $($PYTHON_EXE_ABS --version 2>&1)"
    echo ""
    
    echo "=== Python Build Configuration ==="
    echo "NOTE: The MACOSX_DEPLOYMENT_TARGET shown below is what Python was built with."
    echo "      This is DIFFERENT from what we set during wheel builds (MACOSX_DEPLOYMENT_TARGET=11.0)."
    echo "      Our build_wheels.sh overrides this to ensure all wheels use 11.0."
    echo ""
    $PYTHON_EXE_ABS -c "
import sysconfig
import sys
import os

python_deployment_target = sysconfig.get_config_var('MACOSX_DEPLOYMENT_TARGET')
print(f'Python built with MACOSX_DEPLOYMENT_TARGET: {python_deployment_target}')
print(f'  (This is what Python was compiled with, not what we use during builds)')
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
    
    echo "=== Environment Variables (Build-Time Settings) ==="
    echo "VCPKG_ROOT: ${VCPKG_ROOT:-not set}"
    echo "CMAKE_TOOLCHAIN_FILE: ${CMAKE_TOOLCHAIN_FILE:-not set}"
    echo "CMAKE_PREFIX_PATH: ${CMAKE_PREFIX_PATH:-not set}"
    echo "DYLD_LIBRARY_PATH: ${DYLD_LIBRARY_PATH:-not set}"
    echo ""
    echo "MACOSX_DEPLOYMENT_TARGET (build-time): ${MACOSX_DEPLOYMENT_TARGET:-not set}"
    if [ -z "${MACOSX_DEPLOYMENT_TARGET}" ]; then
        echo "  ⚠️  WARNING: MACOSX_DEPLOYMENT_TARGET not set in environment"
        echo "     build_wheels.sh should set this to 11.0"
    elif [ "${MACOSX_DEPLOYMENT_TARGET}" != "11.0" ]; then
        echo "  ⚠️  WARNING: MACOSX_DEPLOYMENT_TARGET is ${MACOSX_DEPLOYMENT_TARGET}, expected 11.0"
    else
        echo "  ✓ MACOSX_DEPLOYMENT_TARGET correctly set to 11.0"
    fi
    echo ""
    echo "CFLAGS: ${CFLAGS:-not set}"
    echo "CXXFLAGS: ${CXXFLAGS:-not set}"
    echo "LDFLAGS: ${LDFLAGS:-not set}"
    echo ""
    echo "IMPORTANT: The MACOSX_DEPLOYMENT_TARGET shown above in 'Python Build Configuration'"
    echo "           is what Python was built with (varies by Python installation)."
    echo "           The MACOSX_DEPLOYMENT_TARGET shown here is what we set during wheel builds."
    echo "           build_wheels.sh sets MACOSX_DEPLOYMENT_TARGET=11.0 to override Python's value."
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

