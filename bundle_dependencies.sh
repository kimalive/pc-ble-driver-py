#!/bin/bash
# Bundle nrf-ble-driver dependencies into wheels
# This makes wheels self-contained but increases size and complexity

set -e

VCPKG_ROOT="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}"
VCPKG_LIB_DIR="${VCPKG_ROOT}/installed/arm64-osx/lib"

if [ ! -d "$VCPKG_LIB_DIR" ]; then
    echo "Error: VCPKG_LIB_DIR not found: $VCPKG_LIB_DIR"
    exit 1
fi

echo "=================================================================================="
echo "Bundling nrf-ble-driver dependencies into wheels"
echo "=================================================================================="
echo ""
echo "This will:"
echo "  1. Copy nrf-ble-driver libraries into each wheel"
echo "  2. Update .so files to use @loader_path for bundled libraries"
echo "  3. Increase wheel size significantly"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 1
fi

# Libraries to bundle (check which ones are actually needed)
LIBS_TO_BUNDLE=(
    "libnrf-ble-driver-sd_api_v2.4.1.4.dylib"
    "libnrf-ble-driver-sd_api_v5.4.dylib"
)

# Also check for dependencies
DEP_LIBS=(
    "libasio.dylib"
    "libspdlog.dylib"
)

echo ""
echo "Libraries to bundle:"
for lib in "${LIBS_TO_BUNDLE[@]}" "${DEP_LIBS[@]}"; do
    lib_path="${VCPKG_LIB_DIR}/${lib}"
    if [ -f "$lib_path" ]; then
        size=$(ls -lh "$lib_path" | awk '{print $5}')
        echo "  ✓ $lib ($size)"
    else
        echo "  ⚠️  $lib (not found, may not be needed)"
    fi
done

echo ""

for wheel in dist/*.whl; do
    if [ ! -f "$wheel" ]; then
        continue
    fi
    
    # Skip if already bundled
    if [[ "$wheel" == *"_bundled"* ]]; then
        echo "Skipping already bundled wheel: $(basename $wheel)"
        continue
    fi
    
    echo "Processing: $(basename $wheel)"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Extract wheel
    unzip -q "$wheel" -d "$TEMP_DIR"
    
    # Create lib directory for bundled dependencies
    BUNDLE_LIB_DIR="${TEMP_DIR}/pc_ble_driver_py/lib/deps"
    mkdir -p "$BUNDLE_LIB_DIR"
    
    # Copy libraries
    BUNDLED=0
    for lib in "${LIBS_TO_BUNDLE[@]}" "${DEP_LIBS[@]}"; do
        lib_path="${VCPKG_LIB_DIR}/${lib}"
        if [ -f "$lib_path" ]; then
            cp "$lib_path" "$BUNDLE_LIB_DIR/"
            echo "  ✓ Bundled: $lib"
            BUNDLED=1
            
            # Fix rpath in bundled library to use @loader_path
            bundled_lib="${BUNDLE_LIB_DIR}/${lib}"
            # Update any absolute paths to @loader_path
            install_name_tool -id "@loader_path/$lib" "$bundled_lib" 2>/dev/null || true
        fi
    done
    
    if [ $BUNDLED -eq 0 ]; then
        echo "  ⚠️  No libraries to bundle (may be statically linked)"
        rm -rf "$TEMP_DIR"
        continue
    fi
    
    # Update .so files to use bundled libraries
    for so_file in "$TEMP_DIR"/pc_ble_driver_py/lib/*.so; do
        if [ -f "$so_file" ] && [[ "$so_file" != *"deps"* ]]; then
            echo "  Updating $(basename $so_file)..."
            
            # Change library paths to use @loader_path
            for lib in "${LIBS_TO_BUNDLE[@]}"; do
                lib_name=$(basename "$lib")
                # Change any reference to the library to use @loader_path
                install_name_tool -change \
                    "${VCPKG_LIB_DIR}/${lib_name}" \
                    "@loader_path/deps/${lib_name}" \
                    "$so_file" 2>/dev/null || true
            done
            
            # Add @loader_path/deps to rpath
            install_name_tool -add_rpath "@loader_path/deps" "$so_file" 2>/dev/null || true
        fi
    done
    
    # Recreate wheel with new name
    OUTPUT_WHEEL=$(echo "$wheel" | sed 's/\.whl$/_bundled.whl/')
    
    cd "$TEMP_DIR"
    zip -q -r "$OLDPWD/$OUTPUT_WHEEL" .
    cd - > /dev/null
    
    # Calculate size difference
    old_size=$(ls -lh "$wheel" | awk '{print $5}')
    new_size=$(ls -lh "$OUTPUT_WHEEL" | awk '{print $5}')
    
    echo "  ✓ Created bundled wheel: $(basename $OUTPUT_WHEEL)"
    echo "    Size: $old_size → $new_size"
    echo ""
done

echo "Done! Bundled wheels created with '_bundled' suffix."
echo ""
echo "⚠️  NOTE: Original wheels preserved. Test bundled wheels before using."

