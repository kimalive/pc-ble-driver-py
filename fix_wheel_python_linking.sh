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

# Determine expected @rpath name
if [ -f "$PYTHON_LIB_INFO" ]; then
    PYTHON_LIB_NAME=$(basename "$PYTHON_LIB_INFO")
    if [[ "$PYTHON_LIB_NAME" =~ libpython([0-9]+\.[0-9]+)\.dylib ]]; then
        EXPECTED_RPATH="@rpath/libpython${BASH_REMATCH[1]}.dylib"
    elif [ "$PYTHON_LIB_NAME" = "Python" ] || [[ "$PYTHON_LIB_INFO" =~ Python.framework ]]; then
        EXPECTED_RPATH="@rpath/Python"
    else
        EXPECTED_RPATH="@rpath/$PYTHON_LIB_NAME"
    fi
else
    # If library file doesn't exist, try to determine from version
    EXPECTED_RPATH="@rpath/libpython${PYTHON_VER}.dylib"
fi

echo "Python version: $PYTHON_VER"
echo "Python library: $PYTHON_LIB_INFO"
echo "Expected @rpath: $EXPECTED_RPATH"
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
        # Check if link is hardcoded path (not @rpath)
        if [[ "$LINK" != @rpath* ]] && [[ "$LINK" != @loader_path* ]]; then
            echo "  Found hardcoded path: $LINK"
            NEEDS_FIX=1
        # Check if link is wrong @rpath version
        elif [[ "$LINK" =~ @rpath/libpython([0-9]+\.[0-9]+)\.dylib ]] && [ "${BASH_REMATCH[1]}" != "$PYTHON_VER" ]; then
            echo "  Found wrong Python version: $LINK (expected $PYTHON_VER)"
            NEEDS_FIX=1
        fi
    done
    
    if [ $NEEDS_FIX -eq 1 ]; then
        echo "  Fixing Python library links..."
        
        # Fix all Python library links
        for LINK in $CURRENT_LINKS; do
            if [[ "$LINK" != "$EXPECTED_RPATH" ]]; then
                echo "    Changing: $LINK -> $EXPECTED_RPATH"
                install_name_tool -change "$LINK" "$EXPECTED_RPATH" "$SO_FILE" 2>/dev/null || {
                    echo "    ⚠️  Warning: Failed to change $LINK"
                }
            fi
        done
        
        # Ensure Python library directory is in rpath
        if [ -f "$PYTHON_LIB_INFO" ]; then
            PYTHON_LIB_DIR=$(dirname "$PYTHON_LIB_INFO")
            CURRENT_RPATHS=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{getline; getline; if(/path/) print $2}' || true)
            
            if ! echo "$CURRENT_RPATHS" | grep -q "$PYTHON_LIB_DIR"; then
                echo "    Adding rpath: $PYTHON_LIB_DIR"
                install_name_tool -add_rpath "$PYTHON_LIB_DIR" "$SO_FILE" 2>/dev/null || {
                    echo "    ⚠️  Warning: Failed to add rpath"
                }
            fi
        fi
        
        # Verify fix
        VERIFIED_LINKS=$(otool -L "$SO_FILE" 2>/dev/null | grep -E "(python|Python)" | awk '{print $1}' || true)
        if echo "$VERIFIED_LINKS" | grep -q "$EXPECTED_RPATH"; then
            echo "  ✓ Fixed successfully"
            FIXED_ANY=1
        else
            echo "  ✗ Fix verification failed"
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
fi
rm -rf "$TEMP_DIR2"

