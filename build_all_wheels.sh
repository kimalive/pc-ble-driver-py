#!/bin/bash
# Build wheels for all Python versions and architectures
# Supports: Python 3.8-3.13, ARM64 and x86_64

set -e

export VCPKG_ROOT=/Users/kbalive/Devel/OpenSource/vcpkg
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

# Python versions to build
PYTHON_VERSIONS=(3.8 3.9 3.10 3.11 3.12 3.13)

# Architectures to build
ARCHITECTURES=("arm64" "x86_64")

echo "=================================================================================="
echo "Building wheels for all Python versions and architectures"
echo "=================================================================================="
echo "Python versions: ${PYTHON_VERSIONS[@]}"
echo "Architectures: ${ARCHITECTURES[@]}"
echo ""

# Create dist directory if it doesn't exist
mkdir -p dist

# Function to find Python executable
find_python() {
    local version=$1
    # Try common locations
    for base in "/usr/local/bin" "/opt/homebrew/bin" "$HOME/.pyenv/versions/${version}/bin"; do
        if [ -f "${base}/python${version}" ]; then
            echo "${base}/python${version}"
            return 0
        fi
    done
    # Try tox environment
    if [ -f ".tox/py${version//./}/bin/python" ]; then
        echo ".tox/py${version//./}/bin/python"
        return 0
    fi
    return 1
}

# Function to build wheel for a specific Python version and architecture
build_wheel() {
    local python_version=$1
    local arch=$2
    
    echo ""
    echo "=================================================================================="
    echo "Building wheel: Python ${python_version}, Architecture: ${arch}"
    echo "=================================================================================="
    
    # Find Python executable
    PYTHON_EXE=$(find_python ${python_version})
    if [ -z "$PYTHON_EXE" ] || [ ! -f "$PYTHON_EXE" ]; then
        echo "⚠️  Python ${python_version} not found, skipping..."
        return 1
    fi
    
    echo "Using Python: $PYTHON_EXE"
    $PYTHON_EXE --version
    
    # Set architecture-specific CMAKE_PREFIX_PATH
    if [ "$arch" == "arm64" ]; then
        export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/arm64-osx
    elif [ "$arch" == "x86_64" ]; then
        export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/x64-osx
    fi
    
    # Build wheel
    echo "Building wheel..."
    if [ "$arch" == "x86_64" ]; then
        # For x86_64, we might need to use arch command or Intel Python
        # Try with arch command first
        if command -v arch &> /dev/null; then
            arch -x86_64 $PYTHON_EXE setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=x86_64 || {
                echo "⚠️  Failed to build x86_64 wheel with arch command, trying direct..."
                $PYTHON_EXE setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=x86_64
            }
        else
            $PYTHON_EXE setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=x86_64
        fi
    else
        $PYTHON_EXE setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=arm64
    fi
    
    echo "✓ Built wheel for Python ${python_version}, ${arch}"
}

# Build wheels for all combinations
BUILT=0
FAILED=0

for version in "${PYTHON_VERSIONS[@]}"; do
    for arch in "${ARCHITECTURES[@]}"; do
        if build_wheel $version $arch; then
            ((BUILT++))
        else
            ((FAILED++))
        fi
    done
done

echo ""
echo "=================================================================================="
echo "Build Summary"
echo "=================================================================================="
echo "Successfully built: $BUILT wheels"
echo "Failed: $FAILED wheels"
echo ""
echo "Wheels are in: dist/"
ls -lh dist/*.whl 2>/dev/null | tail -20 || echo "No wheels found"

