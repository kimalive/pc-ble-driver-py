#!/bin/bash
# Test all ARM64 release wheels from GitHub release v0.17.11
# Each wheel is tested in its own venv with the matching Python version

# Don't exit on error - continue testing other versions
set +e

# Use v-prefixed tag format (e.g., v0.17.11)
RELEASE_TAG="v0.17.11"
RELEASE_VERSION="0.17.11"
ARCH="arm64"

echo "=================================================================================="
echo "Testing All ARM64 Release Wheels: ${RELEASE_TAG}"
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
    
    echo ""
    echo "=================================================================================="
    echo "Testing: Python ${python_version} (${cp_tag}) - ${ARCH}"
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
    
    # Create temporary venv (similar to tox)
    local venv_dir=$(mktemp -d -t test_wheel_${python_version//./}_${ARCH}_XXXXXX)
    local test_dir=$(mktemp -d -t test_wheel_import_XXXXXX)
    local wheel_url="https://github.com/kimalive/pc-ble-driver-py/releases/download/${RELEASE_TAG}/pc_ble_driver_py-${RELEASE_VERSION}-${cp_tag}-abi3-macosx_26_0_${ARCH}.whl"
    
    echo "Wheel URL: ${wheel_url}"
    echo "Creating virtual environment..."
    
    # Create venv
    if ! "${python_exe}" -m venv "${venv_dir}" 2>/dev/null; then
        echo "✗ Failed to create venv"
        rm -rf "${venv_dir}" "${test_dir}"
        ((FAILED++))
        FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${ARCH} - venv creation failed")
        return 1
    fi
    
    local venv_python="${venv_dir}/bin/python"
    local venv_pip="${venv_dir}/bin/pip"
    
    echo "Installing wheel..."
    "${venv_pip}" install --upgrade pip --quiet
    if ! "${venv_pip}" install "${wheel_url}" --quiet; then
        echo "✗ Failed to install wheel"
        rm -rf "${venv_dir}" "${test_dir}"
        ((FAILED++))
        FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${ARCH} - installation failed")
        return 1
    fi
    
    echo "Testing imports..."
    # Set environment variables like tox does (for nrf-ble-driver dependencies)
    export DYLD_LIBRARY_PATH="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}/installed/arm64-osx/lib:${DYLD_LIBRARY_PATH:-}"
    export PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
    # Change to a temp directory to avoid importing from source
    cd "${test_dir}"
    
    # Run test in a subshell to catch segfaults
    # Use timeout to prevent hanging, and capture both stdout and stderr
    # Note: timeout might not be available on all systems, so we'll try without it first
    local test_output
    if command -v timeout &> /dev/null; then
        test_output=$(cd "${test_dir}" && timeout 30 "${venv_python}" -c "
import sys
import os

# CRITICAL: Remove source directory from sys.path to ensure we import from installed wheel
# This matches how tox tests work
# Only remove paths that are NOT in site-packages (where the wheel is installed)
cwd = os.getcwd()
project_root = os.environ.get('PROJECT_ROOT', '')
if not project_root:
    # Try to find project root from common locations
    for possible_root in [os.path.expanduser('~/Devel/OpenSource/pc-ble-driver-py'),
                          os.path.dirname(os.path.dirname(cwd))]:
        if os.path.exists(os.path.join(possible_root, 'pc_ble_driver_py', '__init__.py')):
            project_root = possible_root
            break

for path in list(sys.path):
    # Only remove if it's the project root and NOT a site-packages directory
    if (path == project_root or 
        (os.path.exists(os.path.join(path, 'pc_ble_driver_py', '__init__.py')) and 
         'site-packages' not in path and 
         path != cwd)):
        sys.path.remove(path)
        print(f'Removed source directory from sys.path: {path}')

print(f'Python: {sys.version.split()[0]}')
print(f'Platform: {sys.platform}')

# Test basic import
try:
    import pc_ble_driver_py
    print('✓ Imported pc_ble_driver_py')
    print(f'  Version: {pc_ble_driver_py.__version__}')
    print(f'  Location: {pc_ble_driver_py.__file__}')
    # Verify it's from the installed wheel, not source
    if 'site-packages' not in pc_ble_driver_py.__file__:
        print('⚠️  WARNING: Package may be imported from source, not wheel!')
        print(f'   Expected site-packages in path, got: {pc_ble_driver_py.__file__}')
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

# Test library paths
lib_dir = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
if os.path.exists(lib_dir):
    so_files = [f for f in os.listdir(lib_dir) if f.endswith('.so')]
    py_files = [f for f in os.listdir(lib_dir) if f.endswith('.py') and 'nrf_ble_driver' in f]
    print(f'✓ Found {len(so_files)} .so file(s) in lib/: {so_files}')
    print(f'✓ Found {len(py_files)} Python wrapper file(s) in lib/: {py_files}')
    
    if len(so_files) == 0:
        print('✗ ERROR: No .so files found in lib/ directory!')
        sys.exit(1)
else:
    print('✗ ERROR: lib/ directory not found!')
    sys.exit(1)

print('')
print('✓ All tests passed!')
" 2>&1)
    else
        # Fallback: run without timeout (should be fast enough)
        test_output=$(cd "${test_dir}" && "${venv_python}" -c "
import sys
import os

# CRITICAL: Remove source directory from sys.path to ensure we import from installed wheel
# This matches how tox tests work
# Only remove paths that are NOT in site-packages (where the wheel is installed)
cwd = os.getcwd()
project_root = os.environ.get('PROJECT_ROOT', '')
if not project_root:
    # Try to find project root from common locations
    for possible_root in [os.path.expanduser('~/Devel/OpenSource/pc-ble-driver-py'),
                          os.path.dirname(os.path.dirname(cwd))]:
        if os.path.exists(os.path.join(possible_root, 'pc_ble_driver_py', '__init__.py')):
            project_root = possible_root
            break

for path in list(sys.path):
    # Only remove if it's the project root and NOT a site-packages directory
    if (path == project_root or 
        (os.path.exists(os.path.join(path, 'pc_ble_driver_py', '__init__.py')) and 
         'site-packages' not in path and 
         path != cwd)):
        sys.path.remove(path)
        print(f'Removed source directory from sys.path: {path}')

print(f'Python: {sys.version.split()[0]}')
print(f'Platform: {sys.platform}')

# Test basic import
try:
    import pc_ble_driver_py
    print('✓ Imported pc_ble_driver_py')
    print(f'  Version: {pc_ble_driver_py.__version__}')
    print(f'  Location: {pc_ble_driver_py.__file__}')
    # Verify it's from the installed wheel, not source
    if 'site-packages' not in pc_ble_driver_py.__file__:
        print('⚠️  WARNING: Package may be imported from source, not wheel!')
        print(f'   Expected site-packages in path, got: {pc_ble_driver_py.__file__}')
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

# Test library paths
lib_dir = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
if os.path.exists(lib_dir):
    so_files = [f for f in os.listdir(lib_dir) if f.endswith('.so')]
    py_files = [f for f in os.listdir(lib_dir) if f.endswith('.py') and 'nrf_ble_driver' in f]
    print(f'✓ Found {len(so_files)} .so file(s) in lib/: {so_files}')
    print(f'✓ Found {len(py_files)} Python wrapper file(s) in lib/: {py_files}')
    
    if len(so_files) == 0:
        print('✗ ERROR: No .so files found in lib/ directory!')
        sys.exit(1)
else:
    print('✗ ERROR: lib/ directory not found!')
    sys.exit(1)

print('')
print('✓ All tests passed!')
" 2>&1)
    fi
    local test_exit_code=$?
    
    # Print test output
    echo "$test_output"
    
    # Check for segfault or other failures
    if [ $test_exit_code -ne 0 ] || echo "$test_output" | grep -q "Segmentation fault\|✗"; then
        if echo "$test_output" | grep -q "Segmentation fault"; then
            echo "✗ Import tests failed: Segmentation fault detected"
            ((FAILED++))
            FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${ARCH} - SEGFAULT during import")
        elif echo "$test_output" | grep -q "✓ All tests passed!"; then
            # Actually passed despite exit code
            echo "✓ Test passed for Python ${python_version} (${cp_tag}) - ${ARCH}"
            cd - > /dev/null
            rm -rf "${venv_dir}" "${test_dir}"
            ((PASSED++))
            return 0
        else
            echo "✗ Import tests failed (exit code: ${test_exit_code})"
            ((FAILED++))
            FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${ARCH} - import tests failed (exit code: ${test_exit_code})")
        fi
        cd - > /dev/null
        rm -rf "${venv_dir}" "${test_dir}"
        return 1
    fi
    
    # Check if test actually passed
    if echo "$test_output" | grep -q "✓ All tests passed!"; then
        echo "✓ Test passed for Python ${python_version} (${cp_tag}) - ${ARCH}"
        cd - > /dev/null
        rm -rf "${venv_dir}" "${test_dir}"
        ((PASSED++))
        return 0
    else
        echo "✗ Import tests failed: Test output did not show success"
        cd - > /dev/null
        rm -rf "${venv_dir}" "${test_dir}"
        ((FAILED++))
        FAILED_TESTS+=("Python ${python_version} (${cp_tag}) - ${ARCH} - test output did not show success")
        return 1
    fi
    
    # Cleanup
    cd - > /dev/null
    rm -rf "${venv_dir}" "${test_dir}"
    echo "✓ Test passed for Python ${python_version} (${cp_tag}) - ${ARCH}"
    ((PASSED++))
    return 0
}

# Test all ARM64 wheels
for py_ver in "${PYTHON_VERSIONS[@]}"; do
    cp_tag=$(get_cp_tag "$py_ver")
    test_wheel "$py_ver" "$cp_tag"
done

# Print summary
echo ""
echo "=================================================================================="
echo "Test Summary"
echo "=================================================================================="
echo "Release: ${RELEASE_TAG}"
echo "Architecture: ${ARCH}"
echo ""
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

if [ $FAILED -eq 0 ] && [ $PASSED -gt 0 ]; then
    echo "✓ All tests passed!"
    exit 0
elif [ $PASSED -gt 0 ]; then
    echo "⚠️  Some tests passed, but some failed"
    exit 1
else
    echo "✗ All tests failed or were skipped"
    exit 1
fi

