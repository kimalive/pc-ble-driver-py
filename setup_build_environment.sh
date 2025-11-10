#!/bin/bash
# Standardized build environment setup script
# This script ensures identical environments for local and CI builds
# Run this before building wheels in both local and GitHub Actions

set -e

echo "=================================================================================="
echo "Setting up standardized build environment"
echo "=================================================================================="

# Detect OS
OS="$(uname -s)"
ARCH="$(uname -m)"

echo "OS: $OS"
echo "Architecture: $ARCH"

# Set consistent MACOSX_DEPLOYMENT_TARGET
export MACOSX_DEPLOYMENT_TARGET=11.0
echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"

# Install/verify system dependencies with specific versions
if [[ "$OS" == "Darwin" ]]; then
    echo ""
    echo "=== Installing/Verifying macOS Build Tools ==="
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "✗ Homebrew not found - required for macOS builds"
        exit 1
    fi
    
    # Install/upgrade specific versions of build tools
    # Pin versions to ensure consistency
    echo "Installing build tools..."
    
    # SWIG - check version and install if needed
    if ! command -v swig &> /dev/null; then
        echo "Installing SWIG..."
        brew install swig
    else
        SWIG_VERSION=$(swig -version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "SWIG version: $SWIG_VERSION"
        # Verify minimum version (4.2.0+)
        SWIG_MAJOR=$(echo "$SWIG_VERSION" | cut -d. -f1)
        SWIG_MINOR=$(echo "$SWIG_VERSION" | cut -d. -f2)
        if [ "$SWIG_MAJOR" -lt 4 ] || ([ "$SWIG_MAJOR" -eq 4 ] && [ "$SWIG_MINOR" -lt 2 ]); then
            echo "⚠️  SWIG version $SWIG_VERSION is too old, upgrading..."
            brew upgrade swig
        fi
    fi
    
    # CMake - check version and install if needed
    if ! command -v cmake &> /dev/null; then
        echo "Installing CMake..."
        brew install cmake
    else
        CMAKE_VERSION=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "CMake version: $CMAKE_VERSION"
        # Verify minimum version (3.20+)
        CMAKE_MAJOR=$(echo "$CMAKE_VERSION" | cut -d. -f1)
        CMAKE_MINOR=$(echo "$CMAKE_VERSION" | cut -d. -f2)
        if [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 20 ]); then
            echo "⚠️  CMake version $CMAKE_VERSION is too old, upgrading..."
            brew upgrade cmake
        fi
    fi
fi

# Install Python dependencies with pinned versions
echo ""
echo "=== Installing Python Build Dependencies ==="
python -m pip install --upgrade pip
python -m pip install --upgrade \
    "scikit-build==0.17.6" \
    "ninja>=1.10.0" \
    "cmake>=3.20.0" \
    "wrapt>=1.14.0" \
    "cryptography>=3.4.0"
echo "scikit-build version check:"
python -c 'import skbuild; print("scikit-build:", skbuild.__version__)'

# Verify vcpkg setup
echo ""
echo "=== Verifying vcpkg Setup ==="
if [ -z "$VCPKG_ROOT" ]; then
    echo "✗ VCPKG_ROOT not set"
    if [ -n "$GITHUB_WORKSPACE" ]; then
        # In GitHub Actions, use workspace
        export VCPKG_ROOT="$GITHUB_WORKSPACE/vcpkg"
    else
        # Local - try common location
        if [ -d "$HOME/vcpkg" ]; then
            export VCPKG_ROOT="$HOME/vcpkg"
        elif [ -d "/Users/kbalive/Devel/OpenSource/vcpkg" ]; then
            export VCPKG_ROOT="/Users/kbalive/Devel/OpenSource/vcpkg"
        else
            echo "  Please set VCPKG_ROOT environment variable"
            exit 1
        fi
    fi
fi

if [ ! -d "$VCPKG_ROOT" ]; then
    echo "✗ VCPKG_ROOT directory does not exist: $VCPKG_ROOT"
    exit 1
fi

export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "CMAKE_TOOLCHAIN_FILE: $CMAKE_TOOLCHAIN_FILE"

# Set CMAKE_PREFIX_PATH based on architecture
if [[ "$ARCH" == "arm64" ]]; then
    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/arm64-osx"
elif [[ "$ARCH" == "x86_64" ]]; then
    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"
else
    echo "⚠️  Unknown architecture: $ARCH"
fi
echo "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"

# Verify nrf-ble-driver is installed
if [ ! -d "$CMAKE_PREFIX_PATH" ]; then
    echo "⚠️  vcpkg installed directory not found: $CMAKE_PREFIX_PATH"
    echo "  Run: $VCPKG_ROOT/vcpkg install nrf-ble-driver --triplet $(basename $CMAKE_PREFIX_PATH)"
fi

# Fix scikit-build macOS version parsing issue
if [[ "$OS" == "Darwin" ]]; then
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
    MACOS_MINOR=$(echo "$MACOS_VERSION" | cut -d. -f2)
    if [ -z "$MACOS_MINOR" ]; then
        MACOS_MINOR="0"
    fi
    if [[ "$ARCH" == "arm64" ]]; then
        export _SKBUILD_PLAT_NAME="macosx-${MACOS_MAJOR}.${MACOS_MINOR}-arm64"
    else
        export _SKBUILD_PLAT_NAME="macosx-${MACOS_MAJOR}.${MACOS_MINOR}-x86_64"
    fi
    echo "_SKBUILD_PLAT_NAME: $_SKBUILD_PLAT_NAME"
fi

echo ""
echo "=================================================================================="
echo "✓ Build environment setup complete"
echo "=================================================================================="
echo ""
echo "Environment variables set:"
echo "  MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
echo "  VCPKG_ROOT=$VCPKG_ROOT"
echo "  CMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE"
echo "  CMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH"
if [ -n "$_SKBUILD_PLAT_NAME" ]; then
    echo "  _SKBUILD_PLAT_NAME=$_SKBUILD_PLAT_NAME"
fi
echo ""

