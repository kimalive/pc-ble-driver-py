#!/bin/bash
# Test script to run GitHub Actions build commands locally
# This mimics what GitHub Actions does for ARM64 builds

set -e

echo "=================================================================================="
echo "Testing GitHub Actions Build Commands Locally (ARM64)"
echo "=================================================================================="
echo ""

# Check if we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script is for macOS only"
    exit 1
fi

# Check architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
    echo "⚠️  Warning: This script is designed for ARM64, but you're on $ARCH"
    echo "   It will still run, but results may differ"
fi

# Get Python version from argument or use default
PYTHON_VERSION=${1:-"3.12"}
echo "Testing with Python ${PYTHON_VERSION}..."
echo ""

# Find Python executable
if command -v "python${PYTHON_VERSION}" &> /dev/null; then
    PYTHON_EXE=$(which "python${PYTHON_VERSION}")
elif command -v "python3" &> /dev/null; then
    PYTHON_EXE=$(which python3)
    ACTUAL_VERSION=$($PYTHON_EXE -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    if [[ "$ACTUAL_VERSION" != "$PYTHON_VERSION" ]]; then
        echo "⚠️  Warning: Requested Python ${PYTHON_VERSION}, but found Python ${ACTUAL_VERSION}"
    fi
else
    echo "❌ Python not found"
    exit 1
fi

echo "Using Python: $PYTHON_EXE"
$PYTHON_EXE --version
echo ""

# Check for vcpkg
if [[ -z "$VCPKG_ROOT" ]]; then
    echo "❌ VCPKG_ROOT not set"
    echo "   Set it to your vcpkg installation directory"
    exit 1
fi

if [[ ! -d "$VCPKG_ROOT" ]]; then
    echo "❌ VCPKG_ROOT directory doesn't exist: $VCPKG_ROOT"
    exit 1
fi

echo "Using vcpkg: $VCPKG_ROOT"
echo ""

# Check for nrf-ble-driver
if [[ ! -d "$VCPKG_ROOT/installed/arm64-osx" ]]; then
    echo "❌ nrf-ble-driver not installed for arm64-osx"
    echo "   Run: $VCPKG_ROOT/vcpkg install nrf-ble-driver --triplet arm64-osx"
    exit 1
fi

echo "✓ nrf-ble-driver found"
echo ""

# Check for SWIG
if ! command -v swig &> /dev/null; then
    echo "❌ SWIG not found"
    echo "   Install with: brew install swig"
    exit 1
fi

echo "Using SWIG: $(which swig)"
swig -version | head -1
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."
$PYTHON_EXE -m pip install --upgrade pip --quiet
$PYTHON_EXE -m pip install scikit-build ninja cmake wrapt cryptography --quiet
echo "✓ Dependencies installed"
echo ""

# Set environment variables (matching GitHub Actions)
export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/arm64-osx
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

# Clean _skbuild (matching GitHub Actions)
echo "Cleaning _skbuild directory..."
rm -rf _skbuild || true
echo "✓ Cleaned"
echo ""

# Build wheel (matching GitHub Actions command exactly)
echo "Building ARM64 wheel (matching GitHub Actions)..."
echo "Command:"
echo "  $PYTHON_EXE setup.py bdist_wheel --build-type Release -- \\"
echo "    -DCMAKE_OSX_ARCHITECTURES=arm64 \\"
echo "    -DPYTHON_EXECUTABLE=\"$PYTHON_EXE\" \\"
echo "    -DPython3_EXECUTABLE=\"$PYTHON_EXE\" \\"
echo "    -DPython3_ROOT_DIR=\"$(dirname $(dirname $PYTHON_EXE))\" \\"
echo "    -DPython3_FIND_STRATEGY=LOCATION \\"
echo "    -DPython3_FIND_REGISTRY=NEVER \\"
echo "    -DPython3_FIND_VIRTUALENV=ONLY \\"
echo "    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON"
echo ""

$PYTHON_EXE setup.py bdist_wheel --build-type Release -- \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DPYTHON_EXECUTABLE="$PYTHON_EXE" \
    -DPython3_EXECUTABLE="$PYTHON_EXE" \
    -DPython3_ROOT_DIR="$(dirname $(dirname $PYTHON_EXE))" \
    -DPython3_FIND_STRATEGY=LOCATION \
    -DPython3_FIND_REGISTRY=NEVER \
    -DPython3_FIND_VIRTUALENV=ONLY \
    -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON

if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ Build successful!"
    
    # Find the built wheel
    WHEEL=$(ls -t dist/pc_ble_driver_py-*-cp*-abi3-*arm64*.whl 2>/dev/null | head -1)
    if [[ -n "$WHEEL" ]]; then
        echo "✓ Wheel created: $(basename $WHEEL)"
        
        # Verify Python version in wheel
        echo ""
        echo "Verifying wheel Python version..."
        PYTHON_TAG=$($PYTHON_EXE -c "import sys; print(f'cp{sys.version_info.major}{sys.version_info.minor}')")
        if [[ "$WHEEL" == *"$PYTHON_TAG"* ]]; then
            echo "✓ Wheel Python tag matches: $PYTHON_TAG"
        else
            echo "⚠️  Warning: Wheel Python tag might not match expected $PYTHON_TAG"
        fi
    else
        echo "⚠️  Warning: Could not find built wheel"
    fi
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "=================================================================================="
echo "✓ Local test completed successfully!"
echo "=================================================================================="

