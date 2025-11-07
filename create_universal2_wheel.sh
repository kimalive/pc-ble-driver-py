#!/bin/bash
# Script to create Universal2 wheel from separate architecture wheels
# 
# This script combines ARM64 and x86_64 wheels into a single Universal2 wheel
# that works on both Apple Silicon and Intel Macs.
#
# Usage:
#   ./create_universal2_wheel.sh arm64_wheel.whl x86_64_wheel.whl [output.whl]

set -e

ARM64_WHEEL="$1"
X86_64_WHEEL="$2"
OUTPUT_WHEEL="${3:-pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_universal2.whl}"

if [ -z "$ARM64_WHEEL" ] || [ -z "$X86_64_WHEEL" ]; then
    echo "Usage: $0 <arm64_wheel.whl> <x86_64_wheel.whl> [output.whl]"
    exit 1
fi

if [ ! -f "$ARM64_WHEEL" ]; then
    echo "Error: ARM64 wheel not found: $ARM64_WHEEL"
    exit 1
fi

if [ ! -f "$X86_64_WHEEL" ]; then
    echo "Error: x86_64 wheel not found: $X86_64_WHEEL"
    exit 1
fi

echo "Creating Universal2 wheel..."
echo "  ARM64: $ARM64_WHEEL"
echo "  x86_64: $X86_64_WHEEL"
echo "  Output: $OUTPUT_WHEEL"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract both wheels
echo "Extracting wheels..."
unzip -q "$ARM64_WHEEL" -d "$TEMP_DIR/arm64"
unzip -q "$X86_64_WHEEL" -d "$TEMP_DIR/x86_64"

# Create output directory
mkdir -p "$TEMP_DIR/universal"
cp -r "$TEMP_DIR/arm64"/* "$TEMP_DIR/universal/"

# Combine .so files using lipo
echo "Combining .so files with lipo..."
for so_file in "$TEMP_DIR/arm64"/pc_ble_driver_py/lib/*.so; do
    if [ -f "$so_file" ]; then
        filename=$(basename "$so_file")
        x86_file="$TEMP_DIR/x86_64/pc_ble_driver_py/lib/$filename"
        if [ -f "$x86_file" ]; then
            echo "  Combining $filename..."
            lipo -create "$so_file" "$x86_file" -output "$TEMP_DIR/universal/pc_ble_driver_py/lib/$filename"
            
            # Verify it's universal
            file_info=$(file "$TEMP_DIR/universal/pc_ble_driver_py/lib/$filename")
            if [[ "$file_info" == *"universal"* ]] || [[ "$file_info" == *"x86_64"* && "$file_info" == *"arm64"* ]]; then
                echo "    ✓ Created universal binary"
            else
                echo "    ⚠ Warning: May not be universal: $file_info"
            fi
        else
            echo "  ⚠ Warning: x86_64 version not found for $filename, copying ARM64 version"
        fi
    fi
done

# Update wheel metadata to reflect universal2
echo "Updating wheel metadata..."
if [ -f "$TEMP_DIR/universal/pc_ble_driver_py-0.17.10.dist-info/WHEEL" ]; then
    sed -i '' 's/macosx_26_0_arm64/macosx_26_0_universal2/g' "$TEMP_DIR/universal/pc_ble_driver_py-0.17.10.dist-info/WHEEL"
fi

# Rename dist-info directory if needed
if [ -d "$TEMP_DIR/universal/pc_ble_driver_py-0.17.10.dist-info" ]; then
    # Update RECORD file
    if [ -f "$TEMP_DIR/universal/pc_ble_driver_py-0.17.10.dist-info/RECORD" ]; then
        sed -i '' 's/macosx_26_0_arm64/macosx_26_0_universal2/g' "$TEMP_DIR/universal/pc_ble_driver_py-0.17.10.dist-info/RECORD"
    fi
fi

# Create new wheel
echo "Creating wheel file..."
cd "$TEMP_DIR/universal"
OUTPUT_PATH="$OLDPWD/$OUTPUT_WHEEL"
zip -q -r "$OUTPUT_PATH" .
cd - > /dev/null

echo ""
echo "✓ Universal2 wheel created: dist/$OUTPUT_WHEEL"
echo ""
echo "Verifying wheel..."
python3 -m wheel show "dist/$OUTPUT_WHEEL" 2>/dev/null | grep -E "(Filename|Tag)" | head -3 || echo "  (wheel tool not available, but wheel should be valid)"
