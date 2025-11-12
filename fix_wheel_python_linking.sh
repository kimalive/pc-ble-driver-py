#!/bin/bash
# Post-build script to verify and fix Python library linking in .so files
# This ensures wheels work correctly by fixing any incorrect Python library links

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <wheel_path> <python_executable>"
    exit 1
fi

WHEEL_PATH="$1"
PYTHON_EXE="$2"

if [ ! -f "$WHEEL_PATH" ]; then
    echo "Error: Wheel not found: $WHEEL_PATH"
    exit 1
fi

if [ ! -f "$PYTHON_EXE" ]; then
    echo "Error: Python executable not found: $PYTHON_EXE"
    exit 1
fi

echo "=== Fixing Python library linking in wheel ==="
echo "Wheel: $(basename "$WHEEL_PATH")"
echo "Python: $PYTHON_EXE"
echo ""

# Get Python version and library info
PYTHON_VER=$("$PYTHON_EXE" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
PYTHON_LIB_INFO=$("$PYTHON_EXE" -c "import sysconfig; libdir = sysconfig.get_config_var('LIBDIR'); libfile = sysconfig.get_config_var('LIBRARY'); libpath = f'{libdir}/{libfile}' if libfile else libdir; print(libpath)" 2>/dev/null)

if [ -z "$PYTHON_LIB_INFO" ]; then
    echo "Error: Could not determine Python library path"
    exit 1
fi

    # Determine expected library name - use @loader_path with relative path
    # This is portable and works in any Python environment:
    #   @loader_path = site-packages/pc_ble_driver_py/lib/ (where .so is)
    #   ../../../../ = goes up to <python_root>/lib/
    #   libpython3.X.dylib = Python library
    # This avoids hardcoded build-time paths and doesn't require RPATH entries.
    if [ -f "$PYTHON_LIB_INFO" ]; then
        PYTHON_LIB_NAME=$(basename "$PYTHON_LIB_INFO")
        if [[ "$PYTHON_LIB_NAME" =~ libpython([0-9]+\.[0-9]+)\.dylib ]]; then
            EXPECTED_LINK="@loader_path/../../../../libpython${BASH_REMATCH[1]}.dylib"
        elif [ "$PYTHON_LIB_NAME" = "Python" ] || [[ "$PYTHON_LIB_INFO" =~ Python.framework ]]; then
            # For framework builds, use @loader_path with relative path
            EXPECTED_LINK="@loader_path/../../../../Python"
        else
            EXPECTED_LINK="@loader_path/../../../../$PYTHON_LIB_NAME"
        fi
    else
        # If library file doesn't exist, try to determine from version
        EXPECTED_LINK="@loader_path/../../../../libpython${PYTHON_VER}.dylib"
    fi

echo "Python version: $PYTHON_VER"
echo "Python library: $PYTHON_LIB_INFO"
echo "Expected library link: $EXPECTED_LINK"
echo "Note: Using @loader_path with relative path - portable, no build-time paths"
echo "      Path: site-packages/pc_ble_driver_py/lib/ -> ../../../../ -> <python_root>/lib/"
echo ""

# Extract wheel to temporary directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Extracting wheel..."
unzip -q "$WHEEL_PATH" -d "$TEMP_DIR"

# Find all .so files
SO_FILES=$(find "$TEMP_DIR" -name "*.so" -type f)

if [ -z "$SO_FILES" ]; then
    echo "Error: No .so files found in wheel"
    exit 1
fi

FIXED_ANY=0
for SO_FILE in $SO_FILES; do
    echo "Checking $(basename "$SO_FILE")..."
    
    # Get current Python library links
    CURRENT_LINKS=$(otool -L "$SO_FILE" 2>/dev/null | grep -E "(python|Python)" | awk '{print $1}' || true)
    
    if [ -z "$CURRENT_LINKS" ]; then
        echo "  ⚠️  Warning: No Python library found in linking"
        continue
    fi
    
    NEEDS_FIX=0
    for LINK in $CURRENT_LINKS; do
        # Check if link is hardcoded path (not @loader_path or @rpath)
        if [[ "$LINK" != @loader_path* ]] && [[ "$LINK" != @rpath* ]]; then
            echo "  Found hardcoded path: $LINK"
            NEEDS_FIX=1
        # Check if link is @rpath (we want to change this to @loader_path)
        elif [[ "$LINK" =~ @rpath/libpython([0-9]+\.[0-9]+)\.dylib ]]; then
            echo "  Found @rpath link (will change to @loader_path): $LINK"
            NEEDS_FIX=1
        # Check if link is wrong @loader_path version or structure
        elif [[ "$LINK" =~ @loader_path.*libpython([0-9]+\.[0-9]+)\.dylib ]] && [ "${BASH_REMATCH[1]}" != "$PYTHON_VER" ]; then
            echo "  Found wrong Python version: $LINK (expected $PYTHON_VER)"
            NEEDS_FIX=1
        elif [[ "$LINK" =~ @loader_path ]] && [[ "$LINK" != "$EXPECTED_LINK" ]]; then
            echo "  Found @loader_path with wrong structure: $LINK"
            NEEDS_FIX=1
        # Check if link is @executable_path (we want to change this to @loader_path)
        elif [[ "$LINK" =~ @executable_path ]]; then
            echo "  Found @executable_path link (will change to @loader_path): $LINK"
            NEEDS_FIX=1
        fi
    done
    
    if [ $NEEDS_FIX -eq 1 ]; then
        echo "  Fixing Python library links..."
        
        # Fix all Python library links
        for LINK in $CURRENT_LINKS; do
            if [[ "$LINK" != "$EXPECTED_LINK" ]]; then
                echo "    Changing: $LINK -> $EXPECTED_LINK"
                install_name_tool -change "$LINK" "$EXPECTED_LINK" "$SO_FILE" 2>/dev/null || {
                    echo "    ⚠️  Warning: Failed to change $LINK"
                }
            fi
        done
        FIXED_ANY=1
    fi
    
    # With @loader_path, we don't need RPATH entries - the relative path
    # from the .so file location works directly. However, we should remove
    # any incorrect hardcoded RPATH entries that might have been added.
    
    # Get current RPATH entries and remove all of them (we don't need RPATH with @loader_path)
    CURRENT_RPATHS=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{found=1; next} found && /path /{print $2; found=0}' || true)
    
    # Remove all RPATH entries - we don't need them with @loader_path
    if [ -n "$CURRENT_RPATHS" ]; then
        while IFS= read -r RPATH_ENTRY; do
            echo "  Removing rpath (not needed with @loader_path): $RPATH_ENTRY"
            install_name_tool -delete_rpath "$RPATH_ENTRY" "$SO_FILE" 2>/dev/null || true
            FIXED_ANY=1
        done <<< "$CURRENT_RPATHS"
    fi
    
           # Verify fix
           if [ $NEEDS_FIX -eq 1 ] || [ $FIXED_ANY -eq 1 ]; then
               VERIFIED_LINKS=$(otool -L "$SO_FILE" 2>/dev/null | grep -E "(python|Python)" | awk '{print $1}' || true)
               if echo "$VERIFIED_LINKS" | grep -q "$EXPECTED_LINK"; then
                   echo "  ✓ Fixed successfully"
               else
                   echo "  ✗ Fix verification failed"
                   echo "    Expected: $EXPECTED_LINK"
                   echo "    Current links: $VERIFIED_LINKS"
               fi
           else
               echo "  ✓ Already correctly linked"
           fi
    echo ""
done

if [ $FIXED_ANY -eq 1 ]; then
    echo "Recreating wheel with fixed .so files..."
    BACKUP="${WHEEL_PATH}.backup"
    cp "$WHEEL_PATH" "$BACKUP"
    
    cd "$TEMP_DIR"
    zip -q -r "$OLDPWD/$WHEEL_PATH" .
    cd - > /dev/null
    
    echo "✓ Wheel fixed and recreated"
    echo "  Backup saved to: $(basename "$BACKUP")"
else
    echo "✓ No fixes needed - wheel is correctly linked"
fi

rm -rf "$TEMP_DIR"
trap - EXIT

echo ""
echo "=== Verification ==="
# Quick verification by checking one .so file
TEMP_DIR2=$(mktemp -d)
unzip -q "$WHEEL_PATH" -d "$TEMP_DIR2"
SO_FILE=$(find "$TEMP_DIR2" -name "*.so" -type f | head -1)
       if [ -n "$SO_FILE" ]; then
           echo "Final Python library links:"
           otool -L "$SO_FILE" 2>/dev/null | grep -E "(python|Python)" || echo "  None found"
           echo ""
           echo "RPATH entries (should be empty with @loader_path):"
           RPATH_ENTRIES=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{found=1; next} found && /path /{print $2; found=0}' || true)
           if [ -n "$RPATH_ENTRIES" ]; then
               echo "$RPATH_ENTRIES" | while IFS= read -r rpath; do
                   echo "  ⚠️  $rpath (should be removed - not needed with @loader_path)"
               done
           else
               echo "  ✓ No RPATH entries (correct - @loader_path doesn't need RPATH)"
           fi
       fi
       rm -rf "$TEMP_DIR2"
       
       # With @loader_path, we use a relative path from the .so file location:
       #   @loader_path = site-packages/pc_ble_driver_py/lib/ (where .so is)
       #   ../../../../ = goes up to <python_root>/lib/
       #   libpython3.X.dylib = Python library
       # This is portable and works in any Python environment without build-time paths.

