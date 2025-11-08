#!/bin/bash
# Test script to verify GitHub release wheels work correctly

set -e

PYTHON_VERSION=${1:-3.12}
ARCH=${2:-arm64}

echo "=================================================================================="
echo "Testing GitHub Release Wheel v0.17.11"
echo "Python: ${PYTHON_VERSION}, Architecture: ${ARCH}"
echo "=================================================================================="
echo ""

# Create a clean virtual environment
VENV_DIR="test_release_venv_${PYTHON_VERSION}"
echo "Creating clean virtual environment..."
python${PYTHON_VERSION} -m venv "${VENV_DIR}"
source "${VENV_DIR}/bin/activate"

# Determine the cp tag
case ${PYTHON_VERSION} in
    3.8) CP_TAG="cp38" ;;
    3.9) CP_TAG="cp39" ;;
    3.10) CP_TAG="cp310" ;;
    3.11) CP_TAG="cp311" ;;
    3.12) CP_TAG="cp312" ;;
    3.13) CP_TAG="cp313" ;;
    *) echo "Unsupported Python version: ${PYTHON_VERSION}"; exit 1 ;;
esac

# Install the wheel from GitHub release
WHEEL_URL="https://github.com/kimalive/pc-ble-driver-py/releases/download/v0.17.11/pc_ble_driver_py-0.17.11-${CP_TAG}-abi3-macosx_26_0_${ARCH}.whl"
echo "Installing wheel from: ${WHEEL_URL}"
pip install --upgrade pip --quiet
pip install "${WHEEL_URL}" --quiet

echo ""
echo "Testing imports..."
python -c "
import sys
print(f'Python: {sys.version}')
print(f'Platform: {sys.platform}')

# Test basic import
try:
    import pc_ble_driver_py
    print('✓ Imported pc_ble_driver_py')
    print(f'  Location: {pc_ble_driver_py.__file__}')
except Exception as e:
    print(f'✗ Failed to import pc_ble_driver_py: {e}')
    sys.exit(1)

# Test lib imports
try:
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v5
    print('✓ Imported nrf_ble_driver_sd_api_v5')
except Exception as e:
    print(f'✗ Failed to import nrf_ble_driver_sd_api_v5: {e}')
    sys.exit(1)

try:
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v2
    print('✓ Imported nrf_ble_driver_sd_api_v2')
except Exception as e:
    print(f'✗ Failed to import nrf_ble_driver_sd_api_v2: {e}')
    sys.exit(1)

# Test ble_driver import
try:
    from pc_ble_driver_py.ble_driver import BLEDriver
    print('✓ Imported BLEDriver')
except Exception as e:
    print(f'✗ Failed to import BLEDriver: {e}')
    sys.exit(1)

print('')
print('✓ All imports successful!')
"

echo ""
echo "Testing library paths..."
python -c "
import pc_ble_driver_py
import os

lib_dir = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
if os.path.exists(lib_dir):
    so_files = [f for f in os.listdir(lib_dir) if f.endswith('.so')]
    py_files = [f for f in os.listdir(lib_dir) if f.endswith('.py') and 'nrf_ble_driver' in f]
    print(f'✓ Found {len(so_files)} .so file(s): {so_files}')
    print(f'✓ Found {len(py_files)} Python wrapper file(s): {py_files}')
else:
    print('✗ lib/ directory not found')
"

echo ""
echo "Testing .so file linking..."
python -c "
import pc_ble_driver_py
import os
import subprocess

lib_dir = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
so_files = [f for f in os.listdir(lib_dir) if f.endswith('.so')]

for so_file in so_files:
    so_path = os.path.join(lib_dir, so_file)
    print(f'Checking {so_file}...')
    result = subprocess.run(['otool', '-L', so_path], capture_output=True, text=True)
    if 'libpython' in result.stdout or '@rpath' in result.stdout:
        print(f'  ✓ Uses @rpath for Python library')
    else:
        print(f'  ⚠️  May have hardcoded Python paths')
        print(f'  Output: {result.stdout[:200]}')
"

echo ""
echo "=================================================================================="
echo "✓ Release wheel test completed successfully!"
echo "=================================================================================="

# Cleanup
deactivate
rm -rf "${VENV_DIR}"
echo ""
echo "Cleaned up test environment"
