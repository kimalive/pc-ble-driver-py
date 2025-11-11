#!/bin/bash
# Test GitHub Actions workflow locally
# This script mimics the exact steps from .github/workflows/build-wheels.yml
# Run with: ./test_github_actions_workflow_local.sh [python_version]
# Example: ./test_github_actions_workflow_local.sh 3.12

set -e

PYTHON_VERSION=${1:-"3.12"}
ARCH="arm64"

echo "=================================================================================="
echo "Testing GitHub Actions Workflow Locally (ARM64)"
echo "Python version: ${PYTHON_VERSION}"
echo "=================================================================================="
echo ""

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script is for macOS only"
    exit 1
fi

# Check architecture
CURRENT_ARCH=$(uname -m)
if [[ "$CURRENT_ARCH" != "arm64" ]]; then
    echo "⚠️  Warning: This script is designed for ARM64, but you're on $CURRENT_ARCH"
fi

# Find Python executable
PYTHON_EXE=""
for path in "/opt/homebrew/bin/python${PYTHON_VERSION}" "/usr/local/bin/python${PYTHON_VERSION}" "$(which python${PYTHON_VERSION} 2>/dev/null)"; do
    if [[ -f "$path" ]]; then
        PYTHON_EXE="$path"
        break
    fi
done

if [[ -z "$PYTHON_EXE" ]]; then
    echo "❌ Python ${PYTHON_VERSION} not found"
    echo "   Try: brew install python@${PYTHON_VERSION}"
    exit 1
fi

# Verify Python version
ACTUAL_VER=$($PYTHON_EXE -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
if [[ "$ACTUAL_VER" != "$PYTHON_VERSION" ]]; then
    echo "⚠️  Warning: Requested Python ${PYTHON_VERSION}, but found Python ${ACTUAL_VER}"
fi

echo "✓ Using Python: $PYTHON_EXE (version ${ACTUAL_VER})"
echo ""

# Set up environment variables (matching GitHub Actions)
export VCPKG_ROOT="${VCPKG_ROOT:-$(pwd)/vcpkg}"
export CMAKE_TOOLCHAIN_FILE="${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
export CMAKE_PREFIX_PATH="${VCPKG_ROOT}/installed/arm64-osx"
export MACOSX_DEPLOYMENT_TARGET="11.0"
export SKBUILD_FORCE_ABI3="0"
export _SKBUILD_PLAT_NAME="macosx-11.0-arm64"
export SKBUILD_PLAT_NAME="macosx-11.0-arm64"

echo "=== Environment Variables ==="
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "CMAKE_TOOLCHAIN_FILE: $CMAKE_TOOLCHAIN_FILE"
echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"
echo ""

# Check for vcpkg
if [[ ! -d "$VCPKG_ROOT" ]]; then
    echo "⚠️  vcpkg not found at $VCPKG_ROOT"
    echo "   Cloning vcpkg..."
    git clone https://github.com/Microsoft/vcpkg.git "$VCPKG_ROOT" || {
        echo "❌ Failed to clone vcpkg"
        exit 1
    }
    cd "$VCPKG_ROOT"
    ./bootstrap-vcpkg.sh
    cd - > /dev/null
fi

# Check for nrf-ble-driver
if [[ ! -d "$VCPKG_ROOT/installed/arm64-osx" ]]; then
    echo "⚠️  nrf-ble-driver not installed for arm64-osx"
    echo "   Installing..."
    "$VCPKG_ROOT/vcpkg" install nrf-ble-driver --triplet arm64-osx || {
        echo "❌ Failed to install nrf-ble-driver"
        exit 1
    }
fi

echo "✓ vcpkg and nrf-ble-driver ready"
echo ""

# Setup build environment (if script exists)
if [[ -f "./setup_build_environment.sh" ]]; then
    echo "=== Setting up build environment ==="
    bash ./setup_build_environment.sh
    echo ""
fi

# Get absolute paths
PYTHON_EXE_ABS=$(cd "$(dirname "$PYTHON_EXE")" && pwd)/$(basename "$PYTHON_EXE")
PYTHON_ROOT_DIR=$(dirname "$(dirname "$PYTHON_EXE_ABS")")

echo "=== Build Environment Info ==="
echo "Python executable: $PYTHON_EXE_ABS"
echo "Python version: $ACTUAL_VER"
echo "Python root: $PYTHON_ROOT_DIR"
echo ""

# Clean _skbuild
echo "=== Cleaning _skbuild ==="
rm -rf _skbuild || true
echo "✓ Cleaned"
echo ""

# Build wheel (matching GitHub Actions exactly)
echo "=== Building ARM64 wheel ==="
BUILD_LOG="/tmp/build_wheel_${ACTUAL_VER//./}.log"
WHEELS_BEFORE=$(ls -1 dist/*.whl 2>/dev/null | wc -l || echo "0")
echo "Wheels in dist/ before build: $WHEELS_BEFORE"
echo ""

# Export _SKBUILD_PLAT_NAME for scikit-build
export _SKBUILD_PLAT_NAME

# Build with exact same command as GitHub Actions
if ! env -u PYTHONPATH PATH="$(dirname "$PYTHON_EXE_ABS"):$PATH" \
    MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET \
    _SKBUILD_PLAT_NAME="$_SKBUILD_PLAT_NAME" \
    VCPKG_ROOT="$VCPKG_ROOT" \
    CMAKE_TOOLCHAIN_FILE="$CMAKE_TOOLCHAIN_FILE" \
    CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH" \
    $PYTHON_EXE_ABS setup.py bdist_wheel --build-type Release -- \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET \
    -DPYTHON_EXECUTABLE="$PYTHON_EXE_ABS" \
    -DPython3_EXECUTABLE="$PYTHON_EXE_ABS" \
    -DPython3_ROOT_DIR="$PYTHON_ROOT_DIR" \
    -DPython3_FIND_STRATEGY=LOCATION \
    -DPython3_FIND_REGISTRY=NEVER \
    -DPython3_FIND_VIRTUALENV=ONLY \
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    2>&1 | tee "$BUILD_LOG"; then
    echo "✗ Build failed - check $BUILD_LOG for details"
    exit 1
fi

# Verify wheel was created
echo ""
echo "=== Verifying wheel was created ==="
WHEELS_AFTER=$(ls -1 dist/*.whl 2>/dev/null | wc -l || echo "0")
echo "Wheels in dist/ after build: $WHEELS_AFTER"
if [ "$WHEELS_AFTER" -le "$WHEELS_BEFORE" ]; then
    echo "✗ ERROR: No new wheel was created!"
    exit 1
fi
echo "✓ New wheel created successfully"
echo ""

# Find the wheel
PYTHON_TAG="cp${ACTUAL_VER//./}"
WHEEL=$(ls -t dist/pc_ble_driver_py-*-cp38-abi3-*arm64*.whl 2>/dev/null | head -1)
if [ -z "$WHEEL" ]; then
    WHEEL=$(ls -t dist/pc_ble_driver_py-*-*arm64*.whl 2>/dev/null | head -1)
fi

if [ -z "$WHEEL" ] || [ ! -f "$WHEEL" ]; then
    echo "✗ ERROR: Could not find built wheel"
    exit 1
fi

echo "Found wheel: $(basename "$WHEEL")"
echo ""

# Rename wheel to preserve Python version (matching GitHub Actions)
echo "=== Renaming wheel to preserve Python version ==="
VERSION=$($PYTHON_EXE_ABS -c "import sys; sys.path.insert(0, '.'); from pc_ble_driver_py import __version__; print(__version__)" 2>/dev/null || echo "0.17.11")
MACOS_VERSION="26_0"
NEW_WHEEL="dist/pc_ble_driver_py-${VERSION}-${PYTHON_TAG}-abi3-macosx_${MACOS_VERSION}_arm64.whl"

if [ "$WHEEL" != "$NEW_WHEEL" ]; then
    echo "Renaming: $(basename $WHEEL) -> $(basename $NEW_WHEEL)"
    mv "$WHEEL" "$NEW_WHEEL"
    WHEEL="$NEW_WHEEL"
fi
echo "✓ Wheel renamed"
echo ""

# Bundle dependencies (matching GitHub Actions)
echo "=== Bundling dependencies ==="
if [ -f "./bundle_into_wheel.py" ] && [ -f "$WHEEL" ]; then
    $PYTHON_EXE_ABS ./bundle_into_wheel.py "$WHEEL" || echo "⚠️  Bundling skipped (optional)"
    echo ""
fi

# Fix Python library linking (matching GitHub Actions)
echo "=== Fixing Python library linking ==="
if [ -f "./fix_wheel_python_linking.sh" ] && [ -f "$WHEEL" ]; then
    bash ./fix_wheel_python_linking.sh "$WHEEL" "$PYTHON_EXE_ABS"
    echo ""
else
    echo "⚠️  Fix script not found, skipping"
    echo ""
fi

# Test wheel (matching GitHub Actions)
echo "=== Testing wheel ==="
if [ -f "$WHEEL" ]; then
    WHEEL_ABS=$(cd "$(dirname "$WHEEL")" && pwd)/$(basename "$WHEEL")
    TEMP_INSTALL_DIR=$(mktemp -d)
    
    cd "$TEMP_INSTALL_DIR"
    unzip -q "$WHEEL_ABS" 2>/dev/null || {
        echo "✗ Failed to extract wheel"
        rm -rf "$TEMP_INSTALL_DIR"
        exit 1
    }
    
    export PYTHONPATH="$TEMP_INSTALL_DIR:$PYTHONPATH"
    cd - > /dev/null
    
    # Test imports
    if $PYTHON_EXE_ABS -c 'import sys; import os; TEMP_DIR = os.environ.get("PYTHONPATH", "").split(":")[0] if os.environ.get("PYTHONPATH") else ""; [sys.path.insert(0, TEMP_DIR) for _ in [None] if TEMP_DIR]; sys.path = [p for p in sys.path if p and (TEMP_DIR in p or "site-packages" in p or "lib/python" in p or "Frameworks/Python.framework" in p)]; import pc_ble_driver_py; print("✓ Imported pc_ble_driver_py"); import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v5; print("✓ Imported nrf_ble_driver_sd_api_v5"); print("✓ Wheel test passed (imports only)")' 2>&1; then
        echo "✓ Wheel test passed"
        TEST_EXIT=0
    else
        TEST_EXIT=$?
        if [ $TEST_EXIT -eq 139 ]; then
            echo "✗ Wheel test FAILED - SEGFAULT (exit code: 139)"
        else
            echo "✗ Wheel test FAILED (exit code: $TEST_EXIT)"
        fi
    fi
    
    rm -rf "$TEMP_INSTALL_DIR" 2>/dev/null || true
    
    if [ $TEST_EXIT -ne 0 ]; then
        exit 1
    fi
else
    echo "⚠️  No wheel found to test"
fi

echo ""
echo "=================================================================================="
echo "✓ GitHub Actions workflow test completed successfully!"
echo "Wheel: $(basename "$WHEEL")"
echo "=================================================================================="

