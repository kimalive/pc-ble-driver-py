#!/bin/bash
# Complete bundling solution for wheels
# Bundles all runtime dependencies to make wheels self-contained

set -e

VCPKG_ROOT="${VCPKG_ROOT:-/Users/kbalive/Devel/OpenSource/vcpkg}"
VCPKG_LIB_DIR="${VCPKG_ROOT}/installed/arm64-osx/lib"

if [ ! -d "$VCPKG_LIB_DIR" ]; then
    echo "Error: VCPKG_LIB_DIR not found: $VCPKG_LIB_DIR"
    exit 1
fi

echo "=================================================================================="
echo "Bundling dependencies into wheels"
echo "=================================================================================="
echo "VCPKG lib dir: $VCPKG_LIB_DIR"
echo ""

# Determine which libraries to bundle based on what's actually needed
# Since we're using static linking, we might not need nrf-ble-driver libraries
# But let's bundle them anyway to be safe, and also check for other dependencies

LIBS_TO_CHECK=(
    "libnrf-ble-driver-sd_api_v2.4.1.4.dylib"
    "libnrf-ble-driver-sd_api_v5.4.1.4.dylib"
    "libasio.dylib"
    "libspdlog.dylib"
)

echo "Checking available libraries:"
AVAILABLE_LIBS=()
for lib in "${LIBS_TO_CHECK[@]}"; do
    lib_path="${VCPKG_LIB_DIR}/${lib}"
    if [ -f "$lib_path" ]; then
        size=$(ls -lh "$lib_path" | awk '{print $5}')
        echo "  ✓ $lib ($size)"
        AVAILABLE_LIBS+=("$lib")
    fi
done

if [ ${#AVAILABLE_LIBS[@]} -eq 0 ]; then
    echo "  ⚠️  No libraries found to bundle (using static linking)"
    echo "  Bundling may not be necessary, but proceeding anyway..."
fi

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
    for lib in "${AVAILABLE_LIBS[@]}"; do
        lib_path="${VCPKG_LIB_DIR}/${lib}"
        if [ -f "$lib_path" ]; then
            cp "$lib_path" "$BUNDLE_LIB_DIR/"
            echo "  ✓ Bundled: $lib"
            BUNDLED=1
            
            # Fix rpath in bundled library to use @loader_path
            bundled_lib="${BUNDLE_LIB_DIR}/${lib}"
            install_name_tool -id "@loader_path/$lib" "$bundled_lib" 2>/dev/null || true
            
            # Update dependencies in bundled library to use @loader_path
            otool -L "$bundled_lib" 2>/dev/null | grep -E "(asio|spdlog|nrf)" | while read line; do
                dep_path=$(echo "$line" | awk '{print $1}')
                if [[ "$dep_path" == *"$VCPKG_LIB_DIR"* ]]; then
                    dep_name=$(basename "$dep_path")
                    install_name_tool -change "$dep_path" "@loader_path/$dep_name" "$bundled_lib" 2>/dev/null || true
                fi
            done
        fi
    done
    
    if [ $BUNDLED -eq 0 ]; then
        echo "  ⚠️  No libraries to bundle"
        rm -rf "$TEMP_DIR"
        continue
    fi
    
    # Update .so files to use bundled libraries
    for so_file in "$TEMP_DIR"/pc_ble_driver_py/lib/*.so; do
        if [ -f "$so_file" ] && [[ "$so_file" != *"deps"* ]]; then
            echo "  Updating $(basename $so_file)..."
            
            # Add @loader_path/deps to rpath
            install_name_tool -add_rpath "@loader_path/deps" "$so_file" 2>/dev/null || true
            
            # Change any references to vcpkg libraries to use @loader_path
            for lib in "${AVAILABLE_LIBS[@]}"; do
                lib_name=$(basename "$lib")
                lib_path="${VCPKG_LIB_DIR}/${lib_name}"
                install_name_tool -change \
                    "$lib_path" \
                    "@loader_path/deps/${lib_name}" \
                    "$so_file" 2>/dev/null || true
            done
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
