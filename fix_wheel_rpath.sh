#!/bin/bash
# Fix rpath in wheels to include vcpkg library path
# This allows wheels to find nrf-ble-driver dependencies at runtime

set -e

VCPKG_ROOT="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}"
VCPKG_LIB_DIR="${VCPKG_ROOT}/installed/arm64-osx/lib"

if [ ! -d "$VCPKG_LIB_DIR" ]; then
    echo "Error: VCPKG_LIB_DIR not found: $VCPKG_LIB_DIR"
    echo "Set VCPKG_ROOT environment variable"
    exit 1
fi

echo "Fixing rpath in wheels to include: $VCPKG_LIB_DIR"
echo ""

for wheel in dist/*.whl; do
    if [ ! -f "$wheel" ]; then
        continue
    fi
    
    echo "Processing: $(basename $wheel)"
    
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
            
            # Add vcpkg lib dir to rpath if not already present
            if ! otool -l "$so_file" 2>/dev/null | grep -q "$VCPKG_LIB_DIR"; then
                install_name_tool -add_rpath "$VCPKG_LIB_DIR" "$so_file" 2>/dev/null
                echo "    ✓ Added vcpkg lib dir to rpath"
                FIXED=1
            else
                echo "    ✓ vcpkg lib dir already in rpath"
            fi
            
            # Note: Python library directory should already be in rpath from build
            # but we verify it's there
            python_lib_dirs=$(otool -l "$so_file" 2>/dev/null | grep -A 1 "LC_RPATH" | grep "path" | awk '{print $2}' | grep -i python || true)
            if [ -z "$python_lib_dirs" ]; then
                echo "    ⚠️  Warning: No Python library directory found in rpath"
            fi
        fi
    done
    
    if [ $FIXED -eq 1 ]; then
        # Recreate wheel
        BACKUP="${wheel}.backup"
        cp "$wheel" "$BACKUP"
        echo "  Backed up to: $(basename $BACKUP)"
        
        cd "$TEMP_DIR"
        zip -q -r "$OLDPWD/$wheel" .
        cd - > /dev/null
        
        echo "  ✓ Fixed wheel: $(basename $wheel)"
    else
        echo "  No changes needed"
    fi
    
    echo ""
done

echo "Done! Wheels updated with vcpkg library path in rpath."

