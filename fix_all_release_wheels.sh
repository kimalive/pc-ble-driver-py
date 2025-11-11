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
    # Prefer pyenv/python from PATH first, then Homebrew, then system
    PYTHON_EXE=""
    # Try which first (will find pyenv shims if in PATH)
    if command -v python${py_ver} >/dev/null 2>&1; then
        PYTHON_EXE=$(which python${py_ver})
        # If it's a pyenv shim, resolve to actual Python executable
        if [[ "$PYTHON_EXE" == *"/.pyenv/shims/"* ]]; then
            PYTHON_EXE=$(python${py_ver} -c "import sys; print(sys.executable)" 2>/dev/null || echo "$PYTHON_EXE")
        fi
    fi
    # Fallback to common locations
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        for path in "/opt/homebrew/bin/python${py_ver}" "/usr/local/bin/python${py_ver}"; do
            if [[ -f "$path" ]]; then
                PYTHON_EXE="$path"
                break
            fi
        done
    fi
    
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        echo "⚠️  Python ${py_ver} not found, skipping wheel fix"
        ((SKIPPED++))
        continue
    fi
    
    # Find wheel for this Python version
    # Remove the dot from version: 3.8 -> 38, 3.10 -> 310, 3.13 -> 313
    py_tag="cp${py_ver//./}"
    
    # Try both patterns: with underscore (_arm64) and with hyphen (-arm64)
    WHEEL=$(ls dist/pc_ble_driver_py-0.17.11-${py_tag}-abi3-*_arm64.whl 2>/dev/null | head -1)
    if [ -z "$WHEEL" ] || [ ! -f "$WHEEL" ]; then
        WHEEL=$(ls dist/pc_ble_driver_py-0.17.11-${py_tag}-abi3-*-arm64*.whl 2>/dev/null | head -1)
    fi
    
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

