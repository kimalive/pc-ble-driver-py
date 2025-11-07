#!/bin/bash
# Script to check if all requirements for building wheels are met

echo "============================================================"
echo "Checking build requirements for pc-ble-driver-py"
echo "============================================================"

ALL_OK=true

# Check Python
echo -n "Python: "
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    echo "✓ $PYTHON_VERSION"
else
    echo "✗ Not found"
    ALL_OK=false
fi

# Check CMake
echo -n "CMake: "
if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -n1)
    echo "✓ $CMAKE_VERSION"
else
    echo "✗ Not found"
    ALL_OK=false
fi

# Check SWIG
echo -n "SWIG: "
if command -v swig &> /dev/null; then
    SWIG_VERSION=$(swig -version | head -n1)
    echo "✓ $SWIG_VERSION"
else
    echo "✗ Not found"
    ALL_OK=false
fi

# Check ninja
echo -n "Ninja: "
if command -v ninja &> /dev/null; then
    NINJA_VERSION=$(ninja --version 2>&1)
    echo "✓ $NINJA_VERSION"
else
    echo "✗ Not found (will be installed via pip)"
fi

# Check for pc-ble-driver
echo -n "pc-ble-driver: "
if pkg-config --exists nrf-ble-driver 2>/dev/null; then
    echo "✓ Found (installed)"
else
    echo "✗ Not found - REQUIRED for building"
    echo "  You need to build and install pc-ble-driver first:"
    echo "  1. Clone: git clone https://github.com/NordicSemiconductor/pc-ble-driver"
    echo "  2. Build: cd pc-ble-driver && mkdir build && cd build"
    echo "  3. Configure: cmake -DCMAKE_BUILD_TYPE=Release -DDISABLE_TESTS=1 .."
    echo "  4. Build: make nrf_ble_driver_sd_api_v5_static"
    echo "  5. Install: sudo make install"
    ALL_OK=false
fi

# Check for Homebrew dependencies (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -n "asio (Homebrew): "
    if brew list asio &>/dev/null; then
        echo "✓ Installed"
    else
        echo "✗ Not found - install with: brew install asio"
        ALL_OK=false
    fi
    
    echo -n "spdlog (Homebrew): "
    if brew list spdlog &>/dev/null; then
        echo "✓ Installed"
    else
        echo "✗ Not found - install with: brew install spdlog"
        ALL_OK=false
    fi
fi

echo ""
echo "============================================================"
if [ "$ALL_OK" = true ]; then
    echo "✓ All requirements met! You can build wheels."
    echo ""
    echo "To build a wheel:"
    echo "  python3 -m venv venv"
    echo "  source venv/bin/activate"
    echo "  pip install -r requirements-dev.txt"
    echo "  python setup.py bdist_wheel --build-type Release"
else
    echo "✗ Some requirements are missing. Please install them first."
    exit 1
fi

