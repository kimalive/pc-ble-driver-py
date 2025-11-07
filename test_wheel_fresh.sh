#!/bin/bash
# Test wheel with fresh installation (no cache, force reinstall)

set -e

WHEEL="$1"
PYTHON="${2:-python3.12}"

if [ -z "$WHEEL" ] || [ ! -f "$WHEEL" ]; then
    echo "Usage: $0 <wheel_file> [python_executable]"
    echo "Example: $0 dist/pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl python3.12"
    exit 1
fi

echo "=================================================================================="
echo "Testing wheel with fresh installation"
echo "=================================================================================="
echo "Wheel: $(basename $WHEEL)"
echo "Python: $($PYTHON --version)"
echo "Wheel timestamp: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$WHEEL")"
echo ""

# Step 1: Uninstall existing installation
echo "Step 1: Uninstalling existing installation..."
$PYTHON -m pip uninstall -y pc-ble-driver-py 2>&1 | grep -E "(Uninstalling|Successfully|WARNING|not installed)" || true
echo ""

# Step 2: Clear pip cache for this package
echo "Step 2: Clearing pip cache..."
$PYTHON -m pip cache purge 2>&1 | tail -2 || echo "  (pip cache purge not available, using --no-cache-dir)"
echo ""

# Step 3: Install wheel with --force-reinstall --no-deps --no-cache-dir
echo "Step 3: Installing wheel (fresh, no cache)..."
$PYTHON -m pip install --force-reinstall --no-deps --no-cache-dir "$WHEEL" 2>&1 | tail -5
echo ""

# Step 4: Verify installation location
echo "Step 4: Verifying installation..."
INSTALLED_LOCATION=$($PYTHON -c "import pc_ble_driver_py; import os; print(os.path.dirname(pc_ble_driver_py.__file__))" 2>&1)
if [ $? -eq 0 ]; then
    echo "  ✓ Installed at: $INSTALLED_LOCATION"
    
    # Check if it's in site-packages (correct) or source directory (wrong)
    if echo "$INSTALLED_LOCATION" | grep -q "site-packages"; then
        echo "  ✓ Correct location: site-packages"
    elif echo "$INSTALLED_LOCATION" | grep -q "pc-ble-driver-py/pc_ble_driver_py"; then
        echo "  ⚠️  WARNING: Installed in source directory (not site-packages)"
        echo "     This may cause issues - Python is finding source before wheel"
        echo "     Try testing in a clean virtual environment"
    else
        echo "  ? Unknown location type"
    fi
    
    SO_FILE="$INSTALLED_LOCATION/lib/_nrf_ble_driver_sd_api_v5.so"
    if [ -f "$SO_FILE" ]; then
        echo "  ✓ .so file exists: $SO_FILE"
        echo "  .so timestamp: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$SO_FILE" 2>/dev/null || echo "N/A")"
    else
        echo "  ✗ .so file not found!"
    fi
else
    echo "  ✗ Installation verification failed"
    echo "$INSTALLED_LOCATION"
fi
echo ""

# Step 5: Test import
echo "Step 5: Testing import..."
$PYTHON << 'PYTHON_SCRIPT'
import sys
try:
    from pc_ble_driver_py import config
    config.__conn_ic_id__ = 'NRF52'
    from pc_ble_driver_py.ble_driver import BLEDriver
    print("  ✓ SUCCESS: Import works!")
    sys.exit(0)
except ImportError as e:
    print(f"  ✗ ImportError: {e}")
    sys.exit(1)
except Exception as e:
    print(f"  ✗ FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYTHON_SCRIPT

EXIT_CODE=$?
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "=================================================================================="
    echo "✓ TEST PASSED: Wheel works correctly"
    echo "=================================================================================="
else
    echo "=================================================================================="
    echo "✗ TEST FAILED: Wheel has issues (exit code: $EXIT_CODE)"
    echo "=================================================================================="
fi

exit $EXIT_CODE
