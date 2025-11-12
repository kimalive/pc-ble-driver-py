#!/bin/bash
# Easy installation script for pc-ble-driver-py from source
# This script handles all prerequisites and setup automatically
#
# Usage:
#   ./install.sh              # Interactive mode (prompts for vcpkg download)
#   ./install.sh --non-interactive  # Non-interactive (fails if vcpkg not found)

set -e

NON_INTERACTIVE=false
if [[ "$1" == "--non-interactive" ]] || [[ "$1" == "-y" ]]; then
    NON_INTERACTIVE=true
fi

echo "=================================================================================="
echo "pc-ble-driver-py Easy Installation Script"
echo "=================================================================================="
echo ""

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    VCPKG_TRIPLET="arm64-osx"
elif [[ "$ARCH" == "x86_64" ]]; then
    VCPKG_TRIPLET="x64-osx"
else
    echo "✗ Unsupported architecture: $ARCH"
    exit 1
fi

echo "Detected architecture: $ARCH"
echo ""

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "✗ Python 3 not found. Please install Python 3.8 or later."
    exit 1
fi

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "✓ Python $PYTHON_VERSION found"

# Check for CMake
if ! command -v cmake &> /dev/null; then
    echo ""
    echo "CMake not found. Installing via Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "✗ Homebrew not found. Please install CMake manually:"
        echo "  brew install cmake"
        exit 1
    fi
    brew install cmake
fi

CMAKE_VERSION=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "✓ CMake $CMAKE_VERSION found"

# Check for C++ compiler
if ! command -v c++ &> /dev/null && ! command -v clang++ &> /dev/null; then
    echo "✗ C++ compiler not found. Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi
echo "✓ C++ compiler found"

# Auto-detect or setup vcpkg
echo ""
echo "=== Setting up vcpkg ==="

VCPKG_ROOT=""
# Check common locations
for location in "$HOME/vcpkg" "$HOME/.vcpkg" "/usr/local/vcpkg" "/opt/vcpkg"; do
    if [ -d "$location" ] && [ -f "$location/scripts/buildsystems/vcpkg.cmake" ]; then
        VCPKG_ROOT="$location"
        echo "✓ Found vcpkg at: $VCPKG_ROOT"
        break
    fi
done

# If not found, offer to download it
if [ -z "$VCPKG_ROOT" ]; then
    if [ "$NON_INTERACTIVE" = true ]; then
        echo "✗ vcpkg not found and non-interactive mode enabled"
        echo "  Please set VCPKG_ROOT environment variable or install vcpkg manually"
        exit 1
    fi
    
    echo "vcpkg not found in common locations."
    echo ""
    read -p "Would you like to download and set up vcpkg automatically? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        VCPKG_ROOT="$HOME/vcpkg"
        echo "Downloading vcpkg to $VCPKG_ROOT..."
        if [ -d "$VCPKG_ROOT" ]; then
            echo "  Directory exists, updating..."
            cd "$VCPKG_ROOT"
            git pull || true
        else
            git clone https://github.com/Microsoft/vcpkg.git "$VCPKG_ROOT"
            cd "$VCPKG_ROOT"
            ./bootstrap-vcpkg.sh
        fi
        echo "✓ vcpkg downloaded and bootstrapped"
    else
        echo "Please install vcpkg manually:"
        echo "  git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg"
        echo "  cd ~/vcpkg && ./bootstrap-vcpkg.sh"
        echo "Then run this script again."
        exit 1
    fi
fi

export VCPKG_ROOT
export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"

# Check if nrf-ble-driver is installed
echo ""
echo "=== Checking nrf-ble-driver ==="
INSTALLED_DIR="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"
if [ ! -d "$INSTALLED_DIR" ] || [ ! -f "$INSTALLED_DIR/share/nrf-ble-driver/nrf-ble-driver-config.cmake" ]; then
    echo "nrf-ble-driver not found. Installing..."
    echo "This may take 10-20 minutes (first time only)..."
    echo ""
    "$VCPKG_ROOT/vcpkg" install nrf-ble-driver --triplet "$VCPKG_TRIPLET"
    if [ $? -eq 0 ]; then
        echo "✓ nrf-ble-driver installed successfully"
    else
        echo "✗ Failed to install nrf-ble-driver"
        echo "  You may need to install it manually:"
        echo "  $VCPKG_ROOT/vcpkg install nrf-ble-driver --triplet $VCPKG_TRIPLET"
        exit 1
    fi
else
    echo "✓ nrf-ble-driver already installed"
fi

export CMAKE_PREFIX_PATH="$INSTALLED_DIR"

# Install Python build dependencies
echo ""
echo "=== Installing Python build dependencies ==="
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install scikit-build cmake ninja

# Install the package
echo ""
echo "=== Installing pc-ble-driver-py ==="
echo "This will build from source. This may take several minutes..."
echo ""

python3 -m pip install . --no-binary :all:

echo ""
echo "=================================================================================="
echo "✓ Installation complete!"
echo "=================================================================================="
echo ""
echo "You can now use pc-ble-driver-py:"
echo "  python3 -c 'import pc_ble_driver_py; print(\"Success!\")'"
echo ""

