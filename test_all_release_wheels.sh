#!/bin/bash
# Comprehensive test script for all release wheels
# Tests each wheel with its corresponding Python version, similar to tox

set -e

RELEASE_TAG="v0.17.11"
RELEASE_VERSION="0.17.11"

# Detect system architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    PRIMARY_ARCH="arm64"
    SECONDARY_ARCH="x86_64"
else
    PRIMARY_ARCH="x86_64"
    SECONDARY_ARCH="arm64"
fi

echo "=================================================================================="
echo "Testing All Release Wheels: ${RELEASE_TAG}"
echo "System Architecture: ${ARCH}"
echo "Primary Architecture: ${PRIMARY_ARCH}"
echo "=================================================================================="
echo ""

# Python versions and their cp tags (matching tox.ini)
declare -a PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")

# Function to get cp tag from Python version
get_cp_tag() {
    local py_ver=$1
    case "$py_ver" in
        3.8) echo "cp38" ;;
        3.9) echo "cp39" ;;
        3.10) echo "cp310" ;;
        3.11) echo "cp311" ;;
        3.12) echo "cp312" ;;
        3.13) echo "cp313" ;;
        *) echo "" ;;
    esac
}

# Function to find Python executable (similar to tox)
find_python() {
    local py_ver=$1
    local py_ver_no_dot="${py_ver//./}"
    
    # 1. Try tox environment first (most reliable, matches tox.ini)
    if [ -f ".tox/py${py_ver_no_dot}/bin/python" ]; then
        echo ".tox/py${py_ver_no_dot}/bin/python"
        return 0
    fi
    
    # 2. Try direct command (python3.8, python3.9, etc.)
    if command -v "python${py_ver}" &> /dev/null; then
        if "python${py_ver}" --version &> /dev/null 2>&1; then
            echo "python${py_ver}"
            return 0
        fi
    fi
    
    # 3. Try pyenv (get latest patch version)
    if command -v pyenv &> /dev/null; then
        local pyenv_version=$(pyenv versions --bare 2>/dev/null | grep "^${py_ver}\." | sort -V | tail -1)
        if [ -n "$pyenv_version" ] && [ -f "${HOME}/.pyenv/versions/${pyenv_version}/bin/python" ]; then
            echo "${HOME}/.pyenv/versions/${pyenv_version}/bin/python"
            return 0
        fi
    fi
    
    return 1
}

# Test results
PASSED=0
FAILED=0
SKIPPED=0
FAILED_TESTS=()

# Function to test a single wheel
test_wheel() {
    local python_version=$1
    local cp_tag=$2
    local arch=$3
    
    echo ""
    echo "=================================================================================="
    echo "Testing: Python ${python_version} (${cp_tag}) - ${arch}"
    echo "=================================================================================="
    
    # Find Python executable (like tox does)
    local python_exe=$(find_python "$python_version")
    if [ -z "$python_exe" ] || [ ! -f "$python_exe" ]; then
        echo "⚠️  Python ${python_version} not found, skipping..."
        echo "   Tried: .tox/py${python_version//./}/bin/python, python${python_version}, pyenv"
        ((SKIPPED++))
        return 1
    fi
    
    echo "Using Python: ${python_exe}"
    echo "Python version: $(${python_exe} --version 2>&1)"
    
    # For x86_64 on ARM64, check if we can run it
    if [ "$arch" = "x86_64" ] && [ "$PRIMARY_ARCH" = "arm64" ]; then
        if ! command -v arch &> /dev/null || ! arch -x86_64 "${python_exe}" --version &> /dev/null 2>&1; then
            echo "⚠️  Cannot test x86_64 wheel on ARM64 (requires Rosetta or Intel Python), skipping..."
            ((SKIPPED++))
            return 1
        fi
    fi
    
    # Create temporary venv (similar to tox)
    local venv_dir=$(mktemp -d -t test_wheel_${python_version//./}_${arch}_XXXXXX)
    local test_dir=$(mktemp -d -t test_wheel_import_XXXXXX)
    local wheel_url="https://github.com/kimalive/pc-ble-driver-py/releases/download/${RELEASE_TAG}/pc_ble_driver_py-${RELEASE_VERSION}-${cp_tag}-abi3-macosx_26_0_${arch}.whl"
    
    echo "Wheel URL: ${wheel_url}"
    echo "Creating virtual environment..."
    
    # Create venv with appropriate Python (like tox does)
    if [ "$arch" = "x86_64" ] && [ "$PRIMARY_ARCH" = "arm64" ]; then
        if ! arch -x86_64 "${python_exe}" -m venv "${venv_dir}" 2>/dev/null; then
            echo "✗ Failed to create venv for x86_64"
            rm -rf "${venv_dir}"
            ((FAILED++))
            FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${arch} - venv creation failed")
            return 1
        fi
        local venv_python="${venv_dir}/bin/python"
        local venv_pip="${venv_dir}/bin/pip"
    else
        if ! "${python_exe}" -m venv "${venv_dir}" 2>/dev/null; then
            echo "✗ Failed to create venv"
            rm -rf "${venv_dir}"
            ((FAILED++))
            FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${arch} - venv creation failed")
            return 1
        fi
        local venv_python="${venv_dir}/bin/python"
        local venv_pip="${venv_dir}/bin/pip"
    fi
    
    echo "Installing wheel..."
    "${venv_pip}" install --upgrade pip --quiet
    if ! "${venv_pip}" install "${wheel_url}" --quiet; then
        echo "✗ Failed to install wheel"
        rm -rf "${venv_dir}" "${test_dir}"
        ((FAILED++))
        FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${arch} - installation failed")
        return 1
    fi
    
    echo "Testing imports (similar to tox tests)..."
    # Set environment variables like tox does (for nrf-ble-driver dependencies)
    export DYLD_LIBRARY_PATH="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}/installed/arm64-osx/lib:${DYLD_LIBRARY_PATH:-}"
    # Change to a temp directory to avoid importing from source
    cd "${test_dir}"
    if ! "${venv_python}" -c "
import sys
import os

# CRITICAL: Remove source directory from sys.path to ensure we import from installed wheel
# This matches how tox tests work
if '__file__' in globals():
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
else:
    # If running from command line, try to find project root from current working directory
    cwd = os.getcwd()
    # Remove current directory and parent if they contain source code
    for path in [cwd, os.path.dirname(cwd)]:
        if path in sys.path and os.path.exists(os.path.join(path, 'pc_ble_driver_py', '__init__.py')):
            sys.path.remove(path)
            print(f'Removed source directory from sys.path: {path}')

print(f'Python: {sys.version}')
print(f'Platform: {sys.platform}')
print(f'Working directory: {os.getcwd()}')
print(f'sys.path (first 3): {sys.path[:3]}')

# Test basic import
try:
    import pc_ble_driver_py
    print('✓ Imported pc_ble_driver_py')
    print(f'  Version: {pc_ble_driver_py.__version__}')
    print(f'  Location: {pc_ble_driver_py.__file__}')
except Exception as e:
    print(f'✗ Failed to import pc_ble_driver_py: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test lib imports
try:
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v5
    print('✓ Imported nrf_ble_driver_sd_api_v5')
except Exception as e:
    print(f'✗ Failed to import nrf_ble_driver_sd_api_v5: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)

try:
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v2
    print('✓ Imported nrf_ble_driver_sd_api_v2')
except Exception as e:
    print(f'✗ Failed to import nrf_ble_driver_sd_api_v2: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test ble_driver import (may fail on initialization if hardware not available, that's OK)
try:
    from pc_ble_driver_py.ble_driver import BLEDriver
    print('✓ Imported BLEDriver')
except RuntimeError as e:
    # RuntimeError about __conn_ic_id__ is expected when hardware is not available
    if '__conn_ic_id__' in str(e):
        print('✓ Imported BLEDriver (initialization skipped - hardware not available, expected)')
    else:
        print(f'✗ Failed to import BLEDriver: {e}')
        import traceback
        traceback.print_exc()
        sys.exit(1)
except Exception as e:
    print(f'✗ Failed to import BLEDriver: {e}')
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test library paths (like tox does)
import os
lib_dir = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
if os.path.exists(lib_dir):
    so_files = [f for f in os.listdir(lib_dir) if f.endswith('.so')]
    py_files = [f for f in os.listdir(lib_dir) if f.endswith('.py') and 'nrf_ble_driver' in f]
    print(f'✓ Found {len(so_files)} .so file(s) in lib/: {so_files}')
    print(f'✓ Found {len(py_files)} Python wrapper file(s) in lib/: {py_files}')
else:
    print('⚠️  lib/ directory not found')

# Test .so file linking (check rpath) - skip if otool fails
if so_files:
    import subprocess
    for so_file in so_files:
        so_path = os.path.join(lib_dir, so_file)
        try:
            result = subprocess.run(['otool', '-L', so_path], capture_output=True, text=True, timeout=5, check=False)
            if result.returncode == 0 and ('@rpath' in result.stdout or 'libpython' in result.stdout):
                print(f'✓ {so_file} uses @rpath for Python library')
            elif result.returncode == 0:
                print(f'⚠️  {so_file} may have hardcoded Python paths')
            else:
                print(f'⚠️  Could not check {so_file} linking (otool returned {result.returncode})')
        except Exception as e:
            print(f'⚠️  Could not check {so_file} linking: {e}')

print('')
print('✓ All tests passed!')
"; then
        echo "✗ Import tests failed"
        cd - > /dev/null
        rm -rf "${venv_dir}" "${test_dir}"
        ((FAILED++))
        FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${arch} - import tests failed")
        return 1
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "${venv_dir}" "${test_dir}"
    echo "✓ Test passed for Python ${python_version} (${cp_tag}) - ${arch}"
    ((PASSED++))
    return 0
}

# Test all wheels
echo "Testing ${PRIMARY_ARCH} wheels (primary architecture)..."
for py_ver in "${PYTHON_VERSIONS[@]}"; do
    cp_tag=$(get_cp_tag "$py_ver")
    test_wheel "$py_ver" "$cp_tag" "$PRIMARY_ARCH"
done

echo ""
echo "Testing ${SECONDARY_ARCH} wheels (secondary architecture)..."
for py_ver in "${PYTHON_VERSIONS[@]}"; do
    cp_tag=$(get_cp_tag "$py_ver")
    test_wheel "$py_ver" "$cp_tag" "$SECONDARY_ARCH"
done

# Print summary
echo ""
echo "=================================================================================="
echo "Test Summary"
echo "=================================================================================="
echo "Passed:  ${PASSED}"
echo "Failed:  ${FAILED}"
echo "Skipped: ${SKIPPED}"
echo "Total:   $((PASSED + FAILED + SKIPPED))"
echo ""

if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo "Failed tests:"
    for test in "${FAILED_TESTS[@]}"; do
        echo "  - ${test}"
    done
    echo ""
fi

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
