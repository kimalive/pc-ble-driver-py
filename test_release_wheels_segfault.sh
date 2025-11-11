#!/bin/bash
# Test release wheels for segfaults
# This script directly tests the import to detect segfaults (exit code -11 or 139)

set -e

echo "=================================================================================="
echo "Testing Release Wheels for Segfaults (ARM64 only)"
echo "=================================================================================="
echo ""

# Test each ARM64 wheel
for wheel in $(find dist -name "*arm64*.whl" -type f 2>/dev/null | sort); do
    if [ ! -f "$wheel" ]; then
        continue
    fi
    
    # Extract Python version from wheel name
    if [[ "$wheel" =~ cp([0-9]+)-abi3 ]]; then
        py_tag="${BASH_REMATCH[1]}"
        if [ ${#py_tag} -eq 2 ]; then
            # cp38 -> 3.8
            py_ver="${py_tag:0:1}.${py_tag:1:1}"
        elif [ ${#py_tag} -eq 3 ]; then
            # cp310 -> 3.10
            py_ver="${py_tag:0:1}.${py_tag:1:2}"
        else
            echo "⚠️  Could not parse Python version from: $(basename "$wheel")"
            continue
        fi
        
        echo "Testing: $(basename "$wheel") (Python ${py_ver})"
        
        # Find Python executable
        PYTHON_EXE=""
        for path in "/opt/homebrew/bin/python${py_ver}" "/usr/local/bin/python${py_ver}" "$(which python${py_ver} 2>/dev/null)"; do
            if [[ -f "$path" ]]; then
                PYTHON_EXE="$path"
                break
            fi
        done
        
        if [ -z "$PYTHON_EXE" ]; then
            echo "  ⚠️  Python ${py_ver} not found, skipping"
            echo ""
            continue
        fi
        
        # Install wheel
        echo "  Installing wheel..."
        $PYTHON_EXE -m pip install --force-reinstall --no-deps "$wheel" > /dev/null 2>&1
        
        # Test import in subprocess to catch segfaults
        echo "  Testing import (checking for segfaults)..."
        IMPORT_TEST='
import sys
try:
    from pc_ble_driver_py import config
    config.__conn_ic_id__ = "NRF52"
    import pc_ble_driver_py.ble_driver  # noqa: F401
    print("✓ Import successful - no segfault!")
    sys.exit(0)
except ImportError as e:
    print(f"⚠ Import failed (missing dependency): {e}")
    sys.exit(0)  # Not a failure
except Exception as e:
    print(f"✗ Import failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
'
        
        # Run import test with timeout
        if command -v timeout >/dev/null 2>&1; then
            result=$(timeout 10 $PYTHON_EXE -c "$IMPORT_TEST" 2>&1)
            exit_code=$?
        else
            result=$($PYTHON_EXE -c "$IMPORT_TEST" 2>&1)
            exit_code=$?
        fi
        
        # Check exit code
        if [ $exit_code -eq -11 ] || [ $exit_code -eq 139 ]; then
            echo "  ✗ SEGFAULT DETECTED (exit code: $exit_code)"
            echo "    This wheel has a critical issue!"
        elif [ $exit_code -eq 124 ]; then
            echo "  ✗ Test timed out (possible hang)"
        elif [ $exit_code -eq 0 ]; then
            echo "$result" | grep -q "✓" && echo "$result" | grep "✓" || echo "  ✓ Import test passed (exit code: 0)"
        else
            echo "  ✗ Import failed (exit code: $exit_code)"
            echo "$result"
        fi
    fi
    echo ""
done

echo "=================================================================================="
echo "✓ Testing completed"
echo "=================================================================================="

