#!/bin/bash
# Download and test release wheels from GitHub
# Usage: ./download_and_test_release_wheels.sh [release_tag]
# Example: ./download_and_test_release_wheels.sh v0.17.11

set -e

RELEASE_TAG=${1:-"v0.17.11"}
REPO="kimalive/pc-ble-driver-py"
BASE_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}"

echo "=================================================================================="
echo "Downloading and Testing Release Wheels"
echo "Release: ${RELEASE_TAG}"
echo "Repository: ${REPO}"
echo "=================================================================================="
echo ""

# Create dist directory if it doesn't exist
mkdir -p dist

# Python versions to download
PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")
ARCHITECTURES=("arm64")  # Only test ARM64 wheels

DOWNLOADED=0
FAILED=0

# Function to download a wheel
download_wheel() {
    local py_ver=$1
    local arch=$2
    local py_tag="cp${py_ver//./}"
    local wheel_name="pc_ble_driver_py-0.17.11-${py_tag}-abi3-macosx_26_0_${arch}.whl"
    local url="${BASE_URL}/${wheel_name}"
    local dest="dist/${wheel_name}"
    
    echo "Downloading: ${wheel_name}..."
    if curl -L -f -o "$dest" "$url" 2>/dev/null; then
        if [ -f "$dest" ] && [ -s "$dest" ]; then
            echo "  ✓ Downloaded: $(basename "$dest") ($(ls -lh "$dest" | awk '{print $5}'))"
            ((DOWNLOADED++))
            return 0
        else
            echo "  ✗ Download failed: file is empty or doesn't exist"
            ((FAILED++))
            return 1
        fi
    else
        echo "  ✗ Download failed: HTTP error"
        ((FAILED++))
        return 1
    fi
}

# Download all wheels
echo "=== Downloading Wheels ==="
for arch in "${ARCHITECTURES[@]}"; do
    echo ""
    echo "Architecture: ${arch}"
    for py_ver in "${PYTHON_VERSIONS[@]}"; do
        download_wheel "$py_ver" "$arch" || true
    done
done

echo ""
echo "=================================================================================="
echo "Download Summary"
echo "=================================================================================="
echo "Downloaded: ${DOWNLOADED} wheels"
echo "Failed: ${FAILED} downloads"
echo ""

# List downloaded wheels
echo "=== Downloaded Wheels ==="
ls -lh dist/*.whl 2>/dev/null | awk '{print $9, "(" $5 ")"}' || echo "No wheels found"
echo ""

# Test the wheels
echo "=================================================================================="
echo "Testing Wheels"
echo "=================================================================================="
echo ""

# Use the test script if available
if [ -f "./tests/test_wheel_compatibility.py" ]; then
    echo "Testing wheels with test_wheel_compatibility.py..."
    echo ""
    
    for wheel in dist/pc_ble_driver_py-0.17.11-*.whl; do
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
            
            echo "Testing wheel: $(basename "$wheel") (Python ${py_ver})"
            
            # Find Python executable
            PYTHON_EXE=""
            for path in "/opt/homebrew/bin/python${py_ver}" "/usr/local/bin/python${py_ver}" "$(which python${py_ver} 2>/dev/null)"; do
                if [[ -f "$path" ]]; then
                    PYTHON_EXE="$path"
                    break
                fi
            done
            
            if [ -z "$PYTHON_EXE" ]; then
                echo "  ⚠️  Python ${py_ver} not found, skipping test"
                continue
            fi
            
            # Install and test wheel
            $PYTHON_EXE -m pip install --force-reinstall --no-deps "$wheel" > /dev/null 2>&1
            if $PYTHON_EXE tests/test_wheel_compatibility.py 2>&1; then
                echo "  ✓ Test passed"
            else
                TEST_EXIT=$?
                if [ $TEST_EXIT -eq 139 ] || [ $TEST_EXIT -eq -11 ]; then
                    echo "  ✗ Test FAILED - SEGFAULT (exit code: $TEST_EXIT)"
                else
                    echo "  ✗ Test FAILED (exit code: $TEST_EXIT)"
                fi
            fi
            echo ""
        fi
    done
else
    echo "⚠️  test_wheel_compatibility.py not found, skipping tests"
fi

echo "=================================================================================="
echo "✓ Download and test completed"
echo "=================================================================================="

