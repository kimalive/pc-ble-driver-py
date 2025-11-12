#!/bin/bash
# Easy installation script for pc-ble-driver-py
# Works in any Python environment (venv, conda, system, etc.)
#
# Usage:
#   ./install_pc_ble_driver_py.sh                    # Install latest from PyPI
#   ./install_pc_ble_driver_py.sh --source          # Force install from source
#   ./install_pc_ble_driver_py.sh --version 0.17.11  # Install specific version
#   ./install_pc_ble_driver_py.sh --local           # Install from local source

set -e

INSTALL_FROM_SOURCE=false
INSTALL_FROM_PYPI=false
INSTALL_VERSION=""
INSTALL_LOCAL=false
NON_INTERACTIVE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source)
            INSTALL_FROM_SOURCE=true
            shift
            ;;
        --version)
            INSTALL_VERSION="$2"
            shift 2
            ;;
        --local)
            INSTALL_LOCAL=true
            shift
            ;;
        --pypi)
            # Install from PyPI instead of GitHub
            INSTALL_FROM_PYPI=true
            shift
            ;;
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --source              Force installation from source (build from source)"
            echo "  --version VERSION     Install specific version from GitHub release (e.g., 0.17.11)"
            echo "  --local               Install from local source directory"
            echo "  --pypi                Install from PyPI instead of GitHub (not recommended)"
            echo "  --non-interactive     Non-interactive mode (no prompts)"
            echo "  --help                Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                           # Install latest from GitHub fork (source build)"
            echo "  $0 --version 0.17.11         # Install specific version from GitHub (source build)"
            echo "  $0 --local                   # Install from current directory (source build)"
            echo "  $0 --pypi                    # Install from PyPI (not recommended - wheels have issues)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "=================================================================================="
echo "pc-ble-driver-py Installation Script"
echo "=================================================================================="
echo ""

# Detect Python
if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo "✗ Python not found. Please install Python 3.8 or later."
    exit 1
fi

# Use python3 if available, otherwise python
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
else
    PYTHON_CMD="python"
fi

PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
PYTHON_EXECUTABLE=$($PYTHON_CMD -c "import sys; print(sys.executable)" 2>/dev/null)

echo "Python: $PYTHON_EXECUTABLE"
echo "Version: $PYTHON_VERSION"
echo ""

# Detect environment type
if [[ "$PYTHON_EXECUTABLE" == *"/venv/"* ]] || [[ "$PYTHON_EXECUTABLE" == *"/.venv/"* ]]; then
    ENV_TYPE="venv"
elif [[ "$PYTHON_EXECUTABLE" == *"conda"* ]]; then
    ENV_TYPE="conda"
elif [[ "$PYTHON_EXECUTABLE" == *".tox/"* ]]; then
    ENV_TYPE="tox"
else
    ENV_TYPE="system"
fi

echo "Environment: $ENV_TYPE"
echo ""

# Check if we're in a virtual environment
if [ -n "$VIRTUAL_ENV" ]; then
    echo "✓ Virtual environment detected: $VIRTUAL_ENV"
elif [[ "$ENV_TYPE" != "system" ]]; then
    echo "✓ Using isolated environment"
else
    echo "⚠️  Installing to system Python"
    if [ "$NON_INTERACTIVE" = false ]; then
        read -p "Continue? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled. Consider using a virtual environment:"
            echo "  python3 -m venv venv"
            echo "  source venv/bin/activate"
            exit 0
        fi
    fi
fi

# Upgrade pip
echo ""
echo "=== Upgrading pip ==="
$PYTHON_CMD -m pip install --upgrade pip setuptools wheel

# Determine installation method
if [ "$INSTALL_LOCAL" = true ]; then
    echo ""
    echo "=== Installing from Local Source ==="
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ ! -f "$SCRIPT_DIR/setup.py" ]; then
        echo "✗ setup.py not found in current directory"
        echo "  Please run this script from the pc-ble-driver-py source directory"
        exit 1
    fi
    
    # Check if vcpkg is needed
    if [ -z "$VCPKG_ROOT" ]; then
        # Try to auto-detect
        for location in "$HOME/vcpkg" "$HOME/.vcpkg" "/usr/local/vcpkg" "/opt/vcpkg"; do
            if [ -d "$location" ] && [ -f "$location/scripts/buildsystems/vcpkg.cmake" ]; then
                export VCPKG_ROOT="$location"
                export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
                ARCH=$(uname -m)
                if [[ "$ARCH" == "arm64" ]]; then
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/arm64-osx"
                else
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"
                fi
                echo "✓ Auto-detected vcpkg at: $VCPKG_ROOT"
                break
            fi
        done
        
        if [ -z "$VCPKG_ROOT" ]; then
            echo "⚠️  vcpkg not found. Source installation requires vcpkg."
            echo "  Run ./install.sh first, or set VCPKG_ROOT environment variable"
            exit 1
        fi
    fi
    
    $PYTHON_CMD -m pip install .
    
elif [ "$INSTALL_FROM_PYPI" = true ]; then
    echo ""
    echo "=== Installing from PyPI ==="
    echo "⚠️  WARNING: PyPI version may not have the latest fixes!"
    echo "   Consider using GitHub fork instead (default)"
    echo ""
    
    if [ -n "$INSTALL_VERSION" ]; then
        PACKAGE="pc-ble-driver-py==$INSTALL_VERSION"
    else
        PACKAGE="pc-ble-driver-py"
    fi
    
    $PYTHON_CMD -m pip install "$PACKAGE"
    
elif [ "$INSTALL_FROM_SOURCE" = true ]; then
    echo ""
    echo "=== Installing from GitHub Source (forced) ==="
    
    GITHUB_REPO="kimalive/pc-ble-driver-py"
    
    if [ -n "$INSTALL_VERSION" ]; then
        GITHUB_URL="git+https://github.com/${GITHUB_REPO}.git@v${INSTALL_VERSION}#egg=pc-ble-driver-py"
    else
        GITHUB_URL="git+https://github.com/${GITHUB_REPO}.git@master#egg=pc-ble-driver-py"
    fi
    
    echo "Installing from: https://github.com/${GITHUB_REPO}"
    echo "This requires vcpkg and build tools."
    echo ""
    
    # Check for vcpkg (same logic as in else block)
    if [ -z "$VCPKG_ROOT" ]; then
        for location in "$HOME/vcpkg" "$HOME/.vcpkg" "/usr/local/vcpkg" "/opt/vcpkg"; do
            if [ -d "$location" ] && [ -f "$location/scripts/buildsystems/vcpkg.cmake" ]; then
                export VCPKG_ROOT="$location"
                export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
                ARCH=$(uname -m)
                if [[ "$ARCH" == "arm64" ]]; then
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/arm64-osx"
                else
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"
                fi
                echo "✓ Auto-detected vcpkg at: $VCPKG_ROOT"
                break
            fi
        done
        
        if [ -z "$VCPKG_ROOT" ]; then
            echo "⚠️  vcpkg not found. Source installation requires vcpkg."
            echo "  Please set VCPKG_ROOT or use ./install.sh for automated setup"
            exit 1
        fi
    fi
    
    $PYTHON_CMD -m pip install "$GITHUB_URL"
    
else
    echo ""
    echo "=== Installing from GitHub Fork (Source - with fixes) ==="
    echo ""
    echo "⚠️  NOTE: Installing from source (sdist) to ensure correct Python library linking."
    echo "   Wheels have path issues, so source installation is required."
    echo ""
    
    GITHUB_REPO="kimalive/pc-ble-driver-py"
    
    if [ -n "$INSTALL_VERSION" ]; then
        # Install specific version from GitHub release tag
        GITHUB_URL="git+https://github.com/${GITHUB_REPO}.git@v${INSTALL_VERSION}#egg=pc-ble-driver-py"
        echo "Installing version $INSTALL_VERSION from GitHub..."
    else
        # Install latest from GitHub (master branch with fixes)
        GITHUB_URL="git+https://github.com/${GITHUB_REPO}.git@master#egg=pc-ble-driver-py"
        echo "Installing latest from GitHub fork (master branch with fixes)..."
    fi
    
    echo "Repository: https://github.com/${GITHUB_REPO}"
    echo ""
    echo "This will build from source, which requires:"
    echo "  - vcpkg (for nrf-ble-driver dependency)"
    echo "  - CMake"
    echo "  - C++ compiler"
    echo ""
    
    # Check for vcpkg
    if [ -z "$VCPKG_ROOT" ]; then
        # Try to auto-detect
        for location in "$HOME/vcpkg" "$HOME/.vcpkg" "/usr/local/vcpkg" "/opt/vcpkg"; do
            if [ -d "$location" ] && [ -f "$location/scripts/buildsystems/vcpkg.cmake" ]; then
                export VCPKG_ROOT="$location"
                export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
                ARCH=$(uname -m)
                if [[ "$ARCH" == "arm64" ]]; then
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/arm64-osx"
                else
                    export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"
                fi
                echo "✓ Auto-detected vcpkg at: $VCPKG_ROOT"
                break
            fi
        done
        
        if [ -z "$VCPKG_ROOT" ]; then
            echo "⚠️  vcpkg not found. Source installation requires vcpkg."
            echo ""
            if [ "$NON_INTERACTIVE" = false ]; then
                read -p "Would you like to download and set up vcpkg automatically? (y/n) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    VCPKG_ROOT="$HOME/vcpkg"
                    echo "Downloading vcpkg to $VCPKG_ROOT..."
                    if [ -d "$VCPKG_ROOT" ]; then
                        cd "$VCPKG_ROOT"
                        git pull || true
                    else
                        git clone https://github.com/Microsoft/vcpkg.git "$VCPKG_ROOT"
                        cd "$VCPKG_ROOT"
                        ./bootstrap-vcpkg.sh
                    fi
                    export VCPKG_ROOT
                    export CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake"
                    ARCH=$(uname -m)
                    if [[ "$ARCH" == "arm64" ]]; then
                        export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/arm64-osx"
                    else
                        export CMAKE_PREFIX_PATH="$VCPKG_ROOT/installed/x64-osx"
                    fi
                    
                    # Install nrf-ble-driver
                    echo ""
                    echo "Installing nrf-ble-driver (this may take 10-20 minutes)..."
                    "$VCPKG_ROOT/vcpkg" install nrf-ble-driver --triplet "$(basename $CMAKE_PREFIX_PATH)"
                else
                    echo "Please set VCPKG_ROOT or use ./install.sh for automated setup"
                    exit 1
                fi
            else
                echo "Please set VCPKG_ROOT or use ./install.sh for automated setup"
                exit 1
            fi
        fi
    fi
    
    # Verify nrf-ble-driver is installed
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        VCPKG_TRIPLET="arm64-osx"
    else
        VCPKG_TRIPLET="x64-osx"
    fi
    INSTALLED_DIR="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"
    if [ ! -d "$INSTALLED_DIR" ] || [ ! -f "$INSTALLED_DIR/share/nrf-ble-driver/nrf-ble-driver-config.cmake" ]; then
        echo ""
        echo "nrf-ble-driver not found. Installing..."
        echo "This may take 10-20 minutes (first time only)..."
        "$VCPKG_ROOT/vcpkg" install nrf-ble-driver --triplet "$VCPKG_TRIPLET"
        if [ $? -eq 0 ]; then
            echo "✓ nrf-ble-driver installed successfully"
        else
            echo "✗ Failed to install nrf-ble-driver"
            exit 1
        fi
    else
        echo "✓ nrf-ble-driver already installed"
    fi
    
    echo ""
    echo "Building from source (this may take several minutes)..."
    echo ""
    
    # Install from GitHub source
    $PYTHON_CMD -m pip install --no-binary :all: "$GITHUB_URL"
fi

# Verify installation
echo ""
echo "=== Verifying Installation ==="
if $PYTHON_CMD -c "import pc_ble_driver_py; print('✓ pc-ble-driver-py imported successfully')" 2>/dev/null; then
    INSTALLED_VERSION=$($PYTHON_CMD -c "import pc_ble_driver_py; print(pc_ble_driver_py.__version__)" 2>/dev/null || echo "unknown")
    echo "✓ Installed version: $INSTALLED_VERSION"
    echo ""
    echo "=================================================================================="
    echo "✓ Installation complete!"
    echo "=================================================================================="
    echo ""
    echo "You can now use pc-ble-driver-py in your Python code:"
    echo "  import pc_ble_driver_py"
    echo ""
else
    echo "✗ Installation verification failed"
    echo "  The package was installed but cannot be imported"
    echo "  This may indicate a compatibility issue"
    exit 1
fi

