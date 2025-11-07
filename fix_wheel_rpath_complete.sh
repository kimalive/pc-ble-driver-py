#!/bin/bash
# Complete rpath fix for wheels - matches development build configuration
# This script fixes rpath in wheels to include both Python library directory
# and vcpkg library directory, matching what works in development builds

set -e

VCPKG_ROOT="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}"
VCPKG_LIB_DIR="${VCPKG_ROOT}/installed/arm64-osx/lib"

if [ ! -d "$VCPKG_LIB_DIR" ]; then
    echo "Error: VCPKG_LIB_DIR not found: $VCPKG_LIB_DIR"
    echo "Set VCPKG_ROOT environment variable"
    exit 1
fi

echo "Fixing rpath in wheels to match development build"
echo "VCPKG lib dir: $VCPKG_LIB_DIR"
echo ""

# Function to get Python library directory for a wheel
get_python_lib_dir() {
    local wheel="$1"
    # Extract Python version from wheel name
    if [[ "$wheel" =~ cp([0-9]+)([0-9]+) ]]; then
        local major="${BASH_REMATCH[1]}"
        local minor="${BASH_REMATCH[2]}"
        local version="${major}.${minor}"
        
        # Try to find Python library directory
        # Check common locations
        for base in "/opt/homebrew/opt/python@${version}" "/usr/local/lib/python${version}" "$HOME/.pyenv/versions/${version}"; do
            if [ -d "${base}/lib" ]; then
                echo "${base}/lib"
                return 0
            fi
        done
        
        # Try using Python to find it
        if command -v "python${version}" &> /dev/null; then
            python${version} -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null && return 0
        fi
    fi
    return 1
}

for wheel in dist/*.whl; do
    if [ ! -f "$wheel" ]; then
        continue
    fi
    
    echo "Processing: $(basename $wheel)"
    
    # Get Python library directory for this wheel
    PYTHON_LIB_DIR=$(get_python_lib_dir "$wheel")
    if [ -z "$PYTHON_LIB_DIR" ] || [ ! -d "$PYTHON_LIB_DIR" ]; then
        echo "  ⚠️  Could not determine Python library directory, skipping Python lib rpath fix"
        PYTHON_LIB_DIR=""
    else
        echo "  Python library directory: $PYTHON_LIB_DIR"
    fi
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Extract wheel
    unzip -q "$wheel" -d "$TEMP_DIR"
    
    # Find and fix .so files
    FIXED=0
    for so_file in "$TEMP_DIR"/pc_ble_driver_py/lib/*.so; do
        if [ -f "$so_file" ]; then
            echo "  Fixing $(basename $so_file)..."
            
            # Check current rpath entries
            CURRENT_RPATHS=$(otool -l "$so_file" 2>/dev/null | awk '/LC_RPATH/{getline; getline; if(/path/) print $2}')
            
            # Add vcpkg lib dir to rpath if not already present
            if echo "$CURRENT_RPATHS" | grep -q "$VCPKG_LIB_DIR"; then
                echo "    ✓ vcpkg lib dir already in rpath"
            else
                install_name_tool -add_rpath "$VCPKG_LIB_DIR" "$so_file" 2>/dev/null
                if [ $? -eq 0 ]; then
                    echo "    ✓ Added vcpkg lib dir to rpath: $VCPKG_LIB_DIR"
                    FIXED=1
                else
                    echo "    ✗ Failed to add vcpkg lib dir to rpath"
                fi
            fi
            
            # Add Python library directory to rpath if not already present
            if [ -n "$PYTHON_LIB_DIR" ]; then
                if echo "$CURRENT_RPATHS" | grep -q "$PYTHON_LIB_DIR"; then
                    echo "    ✓ Python lib dir already in rpath"
                else
                    install_name_tool -add_rpath "$PYTHON_LIB_DIR" "$so_file" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "    ✓ Added Python lib dir to rpath: $PYTHON_LIB_DIR"
                        FIXED=1
                    else
                        echo "    ✗ Failed to add Python lib dir to rpath"
                    fi
                fi
            fi
            
            # Show all rpath entries after fix
            echo "    Current rpath entries:"
            otool -l "$so_file" 2>/dev/null | awk '/LC_RPATH/{getline; getline; if(/path/) print "      " $2}' || echo "      (none)"
        fi
    done
    
    if [ $FIXED -eq 1 ]; then
        # Recreate wheel
        BACKUP="${wheel}.backup"
        if [ ! -f "$BACKUP" ]; then
            cp "$wheel" "$BACKUP"
            echo "  Backed up to: $(basename $BACKUP)"
        fi
        
        cd "$TEMP_DIR"
        zip -q -r "$OLDPWD/$wheel" .
        cd - > /dev/null
        
        echo "  ✓ Fixed wheel: $(basename $wheel)"
    else
        echo "  No changes needed"
    fi
    
    echo ""
done

echo "Done! Wheels updated with complete rpath configuration."

