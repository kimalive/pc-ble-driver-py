#!/bin/bash
# Build wheels for all Python versions (ARM64 and x86_64 if possible)
# This script builds wheels for each Python version separately

# Don't exit on error - continue building other versions
set +e

export VCPKG_ROOT=/Users/kbalive/Devel/OpenSource/vcpkg
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake

echo "=================================================================================="
echo "Building wheels for all Python versions"
echo "=================================================================================="
echo ""

# Create dist directory and clean it
mkdir -p dist
echo "Cleaning dist/ directory..."
find dist -maxdepth 1 -name "*.whl" -delete 2>/dev/null || true
find dist -maxdepth 1 -name "*.backup" -delete 2>/dev/null || true
find dist -maxdepth 1 -name "*.tmp.*" -delete 2>/dev/null || true
rm -f /tmp/wheel_rename_map.txt 2>/dev/null || true
echo "✓ Cleaned dist/ directory"
echo ""

# Function to find Python executable
find_python() {
    local version=$1
    # Try tox environment first (most reliable)
    local tox_python=".tox/py${version//./}/bin/python"
    if [ -f "$tox_python" ]; then
        echo "$tox_python"
        return 0
    fi
    # Try common locations
    for base in "/usr/local/bin" "/opt/homebrew/bin" "$HOME/.pyenv/versions/${version}/bin"; do
        if [ -f "${base}/python${version}" ]; then
            echo "${base}/python${version}"
            return 0
        fi
    done
    return 1
}

# Function to build ARM64 wheel
build_arm64_wheel() {
    local python_version=$1
    local python_exe=$2
    
    echo ""
    echo "Building ARM64 wheel for Python ${python_version}..."
    export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/arm64-osx
    
    # CRITICAL: Clean _skbuild directory for this Python version to prevent cross-contamination
    # Old build artifacts from Python 3.13 might be reused if we don't clean
    local skbuild_pattern="_skbuild/macosx-*-arm64-${python_version}"
    if [ -d "_skbuild" ]; then
        echo "  Cleaning old build artifacts for Python ${python_version}..."
        find _skbuild -maxdepth 1 -type d -name "macosx-*-arm64-${python_version}" -exec rm -rf {} + 2>/dev/null || true
        # Also clean any build directories that don't match current Python version
        find _skbuild -maxdepth 1 -type d -name "macosx-*-arm64-*" ! -name "macosx-*-arm64-${python_version}" -exec rm -rf {} + 2>/dev/null || true
    fi
    
    # CRITICAL: Convert python_exe to absolute path for CMake
    # CMake requires absolute paths for PYTHON_EXECUTABLE
    local python_exe_abs
    if [[ "$python_exe" = /* ]]; then
        python_exe_abs="$python_exe"
    else
        python_exe_abs="$(cd "$(dirname "$python_exe")" && pwd)/$(basename "$python_exe")"
    fi
    
    # CRITICAL: Verify we're using the correct Python version
    local actual_version=$($python_exe -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null)
    if [ "$actual_version" != "$python_version" ]; then
        echo "  ✗ ERROR: Python executable version mismatch!"
        echo "     Expected: ${python_version}, Got: ${actual_version}"
        echo "     Executable: ${python_exe}"
        return 1
    fi
    echo "  ✓ Verified Python version: ${actual_version}"
    
    # CRITICAL: Pass PYTHON_EXECUTABLE to CMake to ensure it uses the correct Python version
    # Without this, CMake might find a different Python (e.g., Python 3.13 when building for 3.12)
    # Also tell CMake to prefer our explicitly provided Python over vcpkg's finder
    # CRITICAL: Capture wheel list BEFORE building to identify the NEW wheel
    local wheels_before=$(ls -1 dist/pc_ble_driver_py-*-cp38-abi3-*.whl 2>/dev/null | grep -v ".tmp\." | sort)
    
    # CRITICAL: Check if build actually succeeded - if it fails, don't try to find/rename wheels
    build_log="/tmp/build_py${python_version//./}.log"
    # CRITICAL: Unset PYTHONPATH and ensure PATH doesn't interfere with Python detection
    # Also explicitly set Python3_ROOT_DIR to the Python executable's directory
    local python_root_dir=$(dirname "$(dirname "$python_exe_abs")")
    if ! env -u PYTHONPATH PATH="$(dirname "$python_exe_abs"):$PATH" $python_exe setup.py bdist_wheel --build-type Release -- \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DPYTHON_EXECUTABLE="$python_exe_abs" \
        -DPython3_EXECUTABLE="$python_exe_abs" \
        -DPython3_ROOT_DIR="$python_root_dir" \
        -DPython3_FIND_STRATEGY=LOCATION \
        -DPython3_FIND_REGISTRY=NEVER \
        -DPython3_FIND_VIRTUALENV=ONLY \
        -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON \
        2>&1 | tee "$build_log"; then
        echo "  ✗ Build failed for Python ${python_version}"
        echo "  Check $build_log for details"
        return 1
    fi
    
    # CRITICAL: Find the NEW wheel by comparing before/after lists
    # This ensures we get the wheel we just built, not an older one
    local wheels_after=$(ls -1 dist/pc_ble_driver_py-*-cp38-abi3-*.whl 2>/dev/null | grep -v ".tmp\." | sort)
    local wheel=""
    
    # Find the new wheel (in after but not in before)
    if [ -n "$wheels_after" ]; then
        if [ -z "$wheels_before" ]; then
            # No wheels before, so the first one is the new one
            wheel=$(echo "$wheels_after" | head -1)
        else
            # Use comm to find wheels in after but not in before
            wheel=$(comm -13 <(echo "$wheels_before") <(echo "$wheels_after") | head -1)
        fi
    fi
    
    # Verify we found a new wheel
    if [ -z "$wheel" ] || [ ! -f "$wheel" ]; then
        echo "  ✗ Build completed but could not identify new wheel for Python ${python_version}"
        echo "  Before: $(echo "$wheels_before" | wc -l | tr -d ' ') wheels"
        echo "  After: $(echo "$wheels_after" | wc -l | tr -d ' ') wheels"
        echo "  Check $build_log for details"
        return 1
    fi
    
    # CRITICAL: Immediately rename to a unique temporary name to prevent overwriting
    # Keep it as a temp name until ALL builds are done, then rename at the end
    # This prevents any Python version from overwriting another's wheel
    if [ -n "$wheel" ] && [ -f "$wheel" ]; then
        local python_tag="cp${python_version//./}"
        local base_name=$(basename "$wheel" .whl)
        local final_name="dist/${base_name%-cp38-abi3*}-${python_tag}-abi3-macosx_26_0_arm64.whl"
        
        # Create unique temp name that includes Python version to prevent overwriting
        local unique_temp_name="dist/pc_ble_driver_py-0.17.10-${python_tag}-abi3-macosx_26_0_arm64.tmp.$(date +%s).$$.whl"
        mv "$wheel" "$unique_temp_name" 2>/dev/null || true
        wheel="$unique_temp_name"
        
        echo "✓ Built: $(basename "$wheel") (built with Python ${python_version}, will rename to $(basename "$final_name") at end)"
        
        # Bundle dependencies (using temp name)
        if [ -f "$(dirname "$0")/bundle_into_wheel.py" ]; then
            echo "  Bundling dependencies..."
            python3 "$(dirname "$0")/bundle_into_wheel.py" "$wheel" 2>&1 | grep -E "(Bundled|Updated|wheel:)" || true
        fi
        
        # Store mapping for final rename (using a simple approach: rename temp to final)
        # We'll do the final rename after all builds are complete
        if [ "$wheel" != "$final_name" ]; then
            # Store the final name by creating a symlink or just remember to rename at end
            # For now, we'll rename at the end of the script
            echo "$wheel|$final_name" >> /tmp/wheel_rename_map.txt 2>/dev/null || true
        fi
    fi
}

# Function to build x86_64 wheel (if possible)
build_x86_64_wheel() {
    local python_version=$1
    local python_exe=$2
    
    echo ""
    echo "Building x86_64 wheel for Python ${python_version}..."
    export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/x64-osx
    
    # CRITICAL: Convert python_exe to absolute path for CMake
    # CMake requires absolute paths for PYTHON_EXECUTABLE
    local python_exe_abs
    if [[ "$python_exe" = /* ]]; then
        python_exe_abs="$python_exe"
    else
        python_exe_abs="$(cd "$(dirname "$python_exe")" && pwd)/$(basename "$python_exe")"
    fi
    
    # CRITICAL: Capture wheel list BEFORE building to identify the NEW wheel
    local wheels_before=$(ls -1 dist/pc_ble_driver_py-*-cp38-abi3-*x86_64*.whl 2>/dev/null | grep -v ".tmp\." | sort)
    
    # Try to build x86_64 wheel
    # This requires Intel Python or Rosetta
    # CRITICAL: Pass PYTHON_EXECUTABLE to CMake to ensure it uses the correct Python version
    local build_succeeded=0
    if command -v arch &> /dev/null; then
        if arch -x86_64 $python_exe setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=x86_64 -DPYTHON_EXECUTABLE="$python_exe_abs" 2>&1 | tail -5; then
            build_succeeded=1
        else
            echo "⚠️  Failed to build x86_64 wheel (may need Intel Python)"
            return 1
        fi
    else
        if $python_exe setup.py bdist_wheel --build-type Release -- -DCMAKE_OSX_ARCHITECTURES=x86_64 -DPYTHON_EXECUTABLE="$python_exe_abs" 2>&1 | tail -5; then
            build_succeeded=1
        else
            echo "⚠️  Failed to build x86_64 wheel"
            return 1
        fi
    fi
    
    # Only proceed if build actually succeeded
    if [ "$build_succeeded" = "1" ]; then
        # CRITICAL: Find the NEW wheel by comparing before/after lists
        local wheels_after=$(ls -1 dist/pc_ble_driver_py-*-cp38-abi3-*x86_64*.whl 2>/dev/null | grep -v ".tmp\." | sort)
        local wheel=""
        
        # Find the new wheel (in after but not in before)
        if [ -n "$wheels_after" ]; then
            if [ -z "$wheels_before" ]; then
                # No wheels before, so the first one is the new one
                wheel=$(echo "$wheels_after" | head -1)
            else
                # Use comm to find wheels in after but not in before
                wheel=$(comm -13 <(echo "$wheels_before") <(echo "$wheels_after") | head -1)
            fi
        fi
        
        # Verify we found a new wheel
        if [ -z "$wheel" ] || [ ! -f "$wheel" ]; then
            echo "  ⚠️  Build completed but could not identify new x86_64 wheel for Python ${python_version}"
            return 1
        fi
        
        if [ -n "$wheel" ] && [ -f "$wheel" ]; then
            local python_tag="cp${python_version//./}"
            local final_name="dist/pc_ble_driver_py-0.17.10-${python_tag}-abi3-macosx_26_0_x86_64.whl"
            
            # Create unique temp name
            local unique_temp_name="dist/pc_ble_driver_py-0.17.10-${python_tag}-abi3-macosx_26_0_x86_64.tmp.$(date +%s).$$.whl"
            mv "$wheel" "$unique_temp_name" 2>/dev/null || true
            wheel="$unique_temp_name"
            
            echo "✓ Built: $(basename "$wheel") (built with Python ${python_version}, will rename to $(basename "$final_name") at end)"
            
            # Bundle dependencies (using temp name)
            if [ -f "$(dirname "$0")/bundle_into_wheel.py" ]; then
                echo "  Bundling dependencies..."
                python3 "$(dirname "$0")/bundle_into_wheel.py" "$wheel" 2>&1 | grep -E "(Bundled|Updated|wheel:)" || true
            fi
            
            # Store mapping for final rename
            if [ "$wheel" != "$final_name" ]; then
                echo "$wheel|$final_name" >> /tmp/wheel_rename_map.txt 2>/dev/null || true
            fi
        fi
    fi
}

# Build wheels for each Python version
PYTHON_VERSIONS=("3.8" "3.9" "3.10" "3.11" "3.12" "3.13")

BUILT_ARM64=0
BUILT_X86_64=0
FAILED=0

for version in "${PYTHON_VERSIONS[@]}"; do
    python_exe=$(find_python $version)
    
    if [ -z "$python_exe" ] || [ ! -f "$python_exe" ]; then
        echo "⚠️  Python ${version} not found, skipping..."
        ((FAILED++))
        continue
    fi
    
    echo ""
    echo "=================================================================================="
    echo "Python ${version} ($python_exe)"
    echo "=================================================================================="
    
    # Build ARM64 wheel
    if build_arm64_wheel $version "$python_exe"; then
        ((BUILT_ARM64++))
    else
        echo "  ⚠️  Failed to build ARM64 wheel for Python ${version}"
        ((FAILED++))
    fi
    
    # Try to build x86_64 wheel (only on Intel Macs or if explicitly enabled)
    # Detect architecture: on ARM64 Macs, x86_64 builds require Intel Python or Rosetta
    arch=$(uname -m)
    if [ "$arch" = "arm64" ] || [ "$arch" = "aarch64" ]; then
        # On Apple Silicon, x86_64 builds are disabled by default
        if [ "${BUILD_X86_64:-0}" = "1" ]; then
            echo "  (x86_64 wheel - attempting on Apple Silicon with BUILD_X86_64=1)"
            if build_x86_64_wheel $version "$python_exe"; then
                ((BUILT_X86_64++))
            else
                echo "  ⚠️  x86_64 wheel failed (may need Intel Python or Rosetta)"
            fi
        else
            echo "  (x86_64 wheel skipped on Apple Silicon - set BUILD_X86_64=1 to enable)"
        fi
    else
        # On Intel Macs, build x86_64 by default
        if build_x86_64_wheel $version "$python_exe"; then
            ((BUILT_X86_64++))
        else
            echo "  ⚠️  x86_64 wheel failed"
        fi
    fi
done

echo ""
echo "=================================================================================="
echo "Build Summary"
echo "=================================================================================="
echo "ARM64 wheels built: $BUILT_ARM64"
echo "x86_64 wheels built: $BUILT_X86_64"
echo "Failed: $FAILED"
echo ""
echo "Renaming wheels to final names..."
# Rename all temp wheels to final names
if [ -f /tmp/wheel_rename_map.txt ]; then
    while IFS='|' read -r temp_name final_name; do
        if [ -f "$temp_name" ] && [ -n "$final_name" ]; then
            mv "$temp_name" "$final_name" 2>/dev/null && echo "  ✓ Renamed: $(basename "$temp_name") -> $(basename "$final_name")" || true
        fi
    done < /tmp/wheel_rename_map.txt
    rm -f /tmp/wheel_rename_map.txt
fi
# Also rename any remaining .tmp.*.whl files (fallback)
for temp_wheel in dist/*.tmp.*.whl; do
    if [ -f "$temp_wheel" ]; then
        # Extract Python version from temp name and create final name
        if [[ "$temp_wheel" =~ cp([0-9]+)-abi3 ]]; then
            python_tag="${BASH_REMATCH[0]}"
            final_name="${temp_wheel%.tmp.*.whl}.whl"
            final_name="dist/pc_ble_driver_py-0.17.10-${python_tag}-abi3-macosx_26_0_arm64.whl"
            mv "$temp_wheel" "$final_name" 2>/dev/null && echo "  ✓ Renamed: $(basename "$temp_wheel") -> $(basename "$final_name")" || true
        fi
    fi
done
echo "✓ All wheels renamed to final names"
echo ""
echo "Cleaning up backup files..."
find dist -maxdepth 1 -name "*.backup" -delete 2>/dev/null || true
find dist -maxdepth 1 -name "*.tmp.*" -delete 2>/dev/null || true
echo "✓ Removed backup files"
echo ""
echo "Wheels in dist/:"
ls -lh dist/*.whl 2>/dev/null | awk '{print $9, "(" $5 ")"}' || echo "No wheels found"

