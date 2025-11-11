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
        FIXED_ANY=1
    fi
    
    # ALWAYS check and fix RPATH (even if library link is already correct)
    # Get Python library directory from the Python executable
    # In GitHub Actions (hostedtoolcache), we need to be more robust in finding the lib directory
    PYTHON_LIB_DIR=$($PYTHON_EXE -c "import sysconfig; libdir = sysconfig.get_config_var('LIBDIR'); print(libdir)" 2>/dev/null || echo "")
    
    # If LIBDIR is empty or doesn't exist, try multiple fallback methods
    # Note: We still add the path to RPATH even if directory doesn't exist (it will exist at runtime)
    if [ -z "$PYTHON_LIB_DIR" ]; then
        # Method 1: Try to determine from Python executable path (for pyenv, Homebrew, etc.)
        PYTHON_ROOT=$(dirname "$(dirname "$PYTHON_EXE")")
        if [ -d "$PYTHON_ROOT/lib" ]; then
            PYTHON_LIB_DIR="$PYTHON_ROOT/lib"
        # Method 2: For GitHub Actions hostedtoolcache, try standard structure
        elif [[ "$PYTHON_EXE" == *"/hostedtoolcache/Python/"* ]]; then
            # Extract Python version and path from hostedtoolcache structure
            # e.g., /Users/runner/hostedtoolcache/Python/3.10.18/arm64/bin/python -> /Users/runner/hostedtoolcache/Python/3.10.18/arm64/lib
            PYTHON_TOOLCACHE_DIR=$(echo "$PYTHON_EXE" | sed 's|/bin/python.*|/lib|')
            PYTHON_LIB_DIR="$PYTHON_TOOLCACHE_DIR"
        # Method 3: Try Python framework structure (Homebrew)
        elif [[ "$PYTHON_EXE" == *"/Frameworks/Python.framework/"* ]]; then
            # Extract framework lib path
            # e.g., /opt/homebrew/.../Frameworks/Python.framework/Versions/3.10/bin/python -> .../Versions/3.10/lib
            PYTHON_FRAMEWORK_LIB=$(echo "$PYTHON_EXE" | sed 's|/Frameworks/Python.framework/Versions/[^/]*/bin/python.*|/Frameworks/Python.framework/Versions/|')
            PYTHON_FRAMEWORK_LIB=$(echo "$PYTHON_FRAMEWORK_LIB" | sed 's|/bin/python.*|/lib|')
            # Try to extract version from path and construct proper path
            if [[ "$PYTHON_EXE" =~ /Versions/([0-9]+\.[0-9]+)/ ]]; then
                PYTHON_VER="${BASH_REMATCH[1]}"
                PYTHON_FRAMEWORK_BASE=$(echo "$PYTHON_EXE" | sed 's|/Frameworks/Python.framework/Versions/[^/]*/.*||')
                PYTHON_LIB_DIR="${PYTHON_FRAMEWORK_BASE}/Frameworks/Python.framework/Versions/${PYTHON_VER}/lib"
            else
                PYTHON_LIB_DIR="$PYTHON_FRAMEWORK_LIB"
            fi
        fi
    fi
    
    # Final fallback: use sysconfig LIBDIR even if directory doesn't exist
    # (it will exist at runtime when Python is installed on user's machine)
    if [ -z "$PYTHON_LIB_DIR" ]; then
        PYTHON_LIB_DIR=$($PYTHON_EXE -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR'))" 2>/dev/null || echo "")
    fi
    
    if [ -n "$PYTHON_LIB_DIR" ]; then
        # Get current RPATH entries - extract path from LC_RPATH commands
        # Format: LC_RPATH section has "path <path>" on the line after "cmdsize"
        CURRENT_RPATHS=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{found=1; next} found && /path /{print $2; found=0}' || true)
        
        # Check if correct Python library directory is in RPATH
        RPATH_EXISTS=0
        if [ -n "$CURRENT_RPATHS" ]; then
            while IFS= read -r RPATH_ENTRY; do
                if [ "$RPATH_ENTRY" = "$PYTHON_LIB_DIR" ]; then
                    RPATH_EXISTS=1
                    break
                fi
            done <<< "$CURRENT_RPATHS"
        fi
        
        if [ $RPATH_EXISTS -eq 0 ]; then
            echo "  Adding rpath: $PYTHON_LIB_DIR"
            # Always try to add the RPATH, even if the directory doesn't exist yet
            # (it will exist at runtime when Python is installed)
            if install_name_tool -add_rpath "$PYTHON_LIB_DIR" "$SO_FILE" 2>&1; then
                echo "  ✓ Successfully added rpath"
                FIXED_ANY=1
            else
                echo "  ✗ ERROR: Failed to add rpath: $PYTHON_LIB_DIR"
                echo "    This is a critical error - the wheel will not work correctly"
                echo "    Attempting to continue, but the wheel may be broken"
                # Don't exit here - we want to see all errors for all .so files
                FIXED_ANY=1  # Still mark as fixed so wheel gets recreated
            fi
        fi
        
        # Remove incorrect hardcoded RPATH entries from GitHub Actions (if they exist and are wrong)
        if [ -n "$CURRENT_RPATHS" ]; then
            while IFS= read -r RPATH_ENTRY; do
                # ALWAYS remove /Library/Frameworks/Python.framework* paths - these are always wrong
                # They come from the build environment and should never be in the final wheel
                if [[ "$RPATH_ENTRY" == /Library/Frameworks/Python.framework* ]]; then
                    echo "  Removing incorrect rpath (hardcoded framework path): $RPATH_ENTRY"
                    install_name_tool -delete_rpath "$RPATH_ENTRY" "$SO_FILE" 2>/dev/null || {
                        echo "  ⚠️  Warning: Failed to remove rpath (may not exist)"
                    }
                    FIXED_ANY=1
                # Remove /Users/runner/hostedtoolcache* paths only if they don't match current Python
                # (In GitHub Actions, the correct path IS in hostedtoolcache, so we keep it if it matches)
                elif [[ "$RPATH_ENTRY" == /Users/runner/hostedtoolcache* ]]; then
                    if [ "$RPATH_ENTRY" != "$PYTHON_LIB_DIR" ]; then
                        echo "  Removing incorrect rpath (wrong hostedtoolcache path): $RPATH_ENTRY"
                        install_name_tool -delete_rpath "$RPATH_ENTRY" "$SO_FILE" 2>/dev/null || {
                            echo "  ⚠️  Warning: Failed to remove rpath (may not exist)"
                        }
                        FIXED_ANY=1
                    fi
                fi
            done <<< "$CURRENT_RPATHS"
        fi
    else
        echo "  ✗ ERROR: Could not determine Python library directory"
        echo "    Python executable: $PYTHON_EXE"
        echo "    This is a critical error - the wheel will not work correctly"
        echo "    Attempting to continue, but the wheel may be broken"
        # Don't exit here - we want to see all errors for all .so files
    fi
    
    # Verify fix
    if [ $NEEDS_FIX -eq 1 ] || [ $FIXED_ANY -eq 1 ]; then
        VERIFIED_LINKS=$(otool -L "$SO_FILE" 2>/dev/null | grep -E "(python|Python)" | awk '{print $1}' || true)
        if echo "$VERIFIED_LINKS" | grep -q "$EXPECTED_RPATH"; then
            echo "  ✓ Fixed successfully"
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
    echo ""
    echo "Final RPATH entries:"
    RPATH_ENTRIES=$(otool -l "$SO_FILE" 2>/dev/null | awk '/LC_RPATH/{found=1; next} found && /path /{print $2; found=0}' | grep -v "@loader_path" || true)
    if [ -n "$RPATH_ENTRIES" ]; then
        echo "$RPATH_ENTRIES" | while IFS= read -r rpath; do
            echo "  $rpath"
        done
    else
        echo "  ⚠️  WARNING: No RPATH entries found (only @loader_path)"
        echo "     The wheel may not work correctly if Python executable doesn't have RPATH"
    fi
fi
rm -rf "$TEMP_DIR2"

# Final check: If we couldn't determine Python library directory for any .so file, fail
if [ -z "$PYTHON_LIB_DIR" ] && [ $FIXED_ANY -eq 0 ]; then
    echo ""
    echo "✗ ERROR: Could not determine Python library directory and no fixes were applied"
    echo "  This wheel will not work correctly"
    exit 1
fi

