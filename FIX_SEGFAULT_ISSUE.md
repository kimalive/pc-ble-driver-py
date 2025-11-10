# Fix for GitHub Actions Wheel Segfault Issue

## Problem
Wheels built with GitHub Actions segfault (exit code -11) for Python 3.9-3.12, while local builds work fine. Python 3.8 works, Python 3.13 has a different error.

## Root Cause
The issue was that `.so` files in GitHub Actions-built wheels were linked to incorrect Python library paths or wrong Python versions. This happened because:
1. Python library detection in CMake might fail silently in GitHub Actions (hostedtoolcache Python installations)
2. The post-build fix step in CMakeLists.txt might not always run correctly
3. No verification step existed to catch and fix incorrect linking

## Solution

### 1. Test Fix (`tests/test_wheel_compatibility.py`)
- **Changed**: Import test now runs in a subprocess to detect segfaults
- **Why**: Segfaults kill the process before Python can catch exceptions
- **Result**: Tests now properly detect and report segfaults (exit code -11 or 139)

### 2. Post-Build Fix Script (`fix_wheel_python_linking.sh`)
- **New script**: Verifies and fixes Python library linking in `.so` files after wheel is built
- **What it does**:
  - Extracts the wheel
  - Checks all `.so` files for incorrect Python library links
  - Fixes hardcoded paths to use `@rpath`
  - Ensures correct Python version is linked
  - Adds Python library directory to RPATH if missing
  - Recreates the wheel with fixed `.so` files
- **When it runs**: After bundling dependencies, before testing

### 3. Improved CMakeLists.txt
- **Enhanced**: Python library detection with better error messages
- **Added**: Warnings when library detection fails
- **Result**: Better visibility into what's happening during build

### 4. GitHub Actions Workflow Updates
- **Added**: "Fix Python library linking in wheel" step for both ARM64 and x86_64 builds
- **Placement**: After bundling, before testing
- **Result**: All wheels are automatically fixed before testing/release

## Files Changed

1. `tests/test_wheel_compatibility.py` - Subprocess-based import test
2. `fix_wheel_python_linking.sh` - New post-build fix script
3. `.github/workflows/build-wheels.yml` - Added fix step to workflow
4. `CMakeLists.txt` - Improved Python library detection

## How It Works

1. **Build Phase**: CMake builds the `.so` files with Python library linking
2. **Bundle Phase**: Dependencies are bundled into the wheel
3. **Fix Phase** (NEW): `fix_wheel_python_linking.sh` verifies and fixes any incorrect Python library links
4. **Test Phase**: Wheel is tested (now properly detects segfaults)

## Verification

After the next GitHub Actions build, check:
1. Build logs should show "Fixing Python library linking in wheel" step
2. The fix script should report what it found and fixed
3. Tests should pass (no more segfaults)

## Testing Locally

You can test the fix script locally:
```bash
# Build a wheel
./build_wheels.sh

# Fix a specific wheel
./fix_wheel_python_linking.sh dist/pc_ble_driver_py-0.17.11-cp311-abi3-macosx_26_0_arm64.whl $(which python3.11)
```

## Expected Results

- ✅ Python 3.8: Should continue working
- ✅ Python 3.9-3.12: Should now work (no more segfaults)
- ✅ Python 3.13: Should work or show a different, more informative error

## Notes

- The fix script creates a backup of the original wheel (`.backup` extension)
- If no fixes are needed, the script reports "No fixes needed"
- The script is idempotent - running it multiple times is safe

