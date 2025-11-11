#!/bin/bash
# Fix all downloaded release wheels for local testing
# This script fixes the RPATH issues in all ARM64 wheels from the release

set -e

echo "=================================================================================="
echo "Fixing All Release Wheels for Local Testing"
echo "=================================================================================="
echo ""

# Python versions to fix
PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")

FIXED=0
FAILED=0
SKIPPED=0

for py_ver in "${PYTHON_VERSIONS[@]}"; do
    # Find Python executable
    PYTHON_EXE=""
    for path in "/opt/homebrew/bin/python${py_ver}" "/usr/local/bin/python${py_ver}" "$(which python${py_ver} 2>/dev/null)"; do
        if [[ -f "$path" ]] || command -v "$path" >/dev/null 2>&1; then
            # If it's a pyenv shim, resolve to actual Python executable
            if [[ "$path" == *"/.pyenv/shims/"* ]]; then
                PYTHON_EXE=$(python${py_ver} -c "import sys; print(sys.executable)" 2>/dev/null || echo "$path")
            else
                PYTHON_EXE="$path"
            fi
            break
        fi
    done
    
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        echo "⚠️  Python ${py_ver} not found, skipping wheel fix"
        ((SKIPPED++))
        continue
    fi
    
    # Find wheel for this Python version
    # Remove the dot from version: 3.8 -> 38, 3.10 -> 310, 3.13 -> 313
    py_tag="cp${py_ver//./}"
    
    WHEEL=$(ls dist/pc_ble_driver_py-0.17.11-${py_tag}-abi3-*arm64*.whl 2>/dev/null | head -1)
    
    if [ -z "$WHEEL" ] || [ ! -f "$WHEEL" ]; then
        echo "⚠️  Wheel not found for Python ${py_ver} (${py_tag})"
        ((SKIPPED++))
        continue
    fi
    
    echo "Fixing wheel for Python ${py_ver}: $(basename "$WHEEL")"
    
    if bash fix_wheel_python_linking.sh "$WHEEL" "$PYTHON_EXE" > /tmp/fix_wheel_${py_tag}.log 2>&1; then
        echo "  ✓ Fixed successfully"
        ((FIXED++))
    else
        echo "  ✗ Fix failed - check /tmp/fix_wheel_${py_tag}.log"
        ((FAILED++))
    fi
    echo ""
done

echo "=================================================================================="
echo "Summary"
echo "=================================================================================="
echo "Fixed: ${FIXED} wheels"
echo "Failed: ${FAILED} wheels"
echo "Skipped: ${SKIPPED} wheels (Python not found or wheel missing)"
echo ""

if [ $FIXED -gt 0 ]; then
    echo "✓ Fixed wheels are ready for testing"
    echo "  You can now run tox to test them:"
    echo "    ./run_tox.sh"
fi

if [ $FAILED -gt 0 ]; then
    echo "⚠️  Some wheels failed to fix - check logs in /tmp/fix_wheel_*.log"
fi

