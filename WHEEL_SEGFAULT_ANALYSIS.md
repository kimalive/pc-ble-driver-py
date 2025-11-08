# Wheel Segfault Analysis - Python 3.9-3.13 ARM64 Wheels

## Problem Summary

Testing of release wheels from v0.17.11 shows:
- ✅ **Python 3.8 (cp38)**: Works correctly
- ❌ **Python 3.9-3.12 (cp39-cp312)**: Segfault (exit code 139)
- ❌ **Python 3.13 (cp313)**: SystemError (extension module initialization failed)

## Investigation Results

### 1. Wheel Structure ✅
- All wheels have correct structure
- All have `__init__.py` in `lib/`
- All have `.so` files present
- All have bundled nrf-ble-driver dependencies

### 2. Python Version Linking ✅
- All wheels correctly linked to their Python versions:
  - cp38 → `@rpath/libpython3.8.dylib`
  - cp39 → `@rpath/libpython3.9.dylib`
  - cp310 → `@rpath/libpython3.10.dylib`
  - cp311 → `@rpath/libpython3.11.dylib`
  - cp312 → `@rpath/libpython3.12.dylib`
  - cp313 → `@rpath/libpython3.13.dylib`

### 3. GitHub Actions Workflow ✅
- All Python versions use identical build process
- All use same CMake flags
- All use same SWIG version
- All use same build dependencies

### 4. Potential Issues Identified

#### Issue 1: ABI3 Tag Mismatch
- Wheels are tagged as `abi3` (stable ABI)
- Code does NOT use `Py_LIMITED_API` (uses full API for SWIG 4.4.0 compatibility)
- This creates a mismatch: wheels claim abi3 compatibility but use full API
- **Impact**: May cause runtime issues if Python expects limited API but gets full API

#### Issue 2: Possible Build Environment Differences
- Python 3.8 works, but 3.9+ segfault
- Suggests something different about how 3.9+ wheels were built
- Could be:
  - Compiler version differences
  - Library path issues
  - Missing symbols in extension modules
  - ABI incompatibility

## Root Cause Hypothesis

The most likely cause is that the wheels for Python 3.9-3.13 were built with some incompatibility, even though:
1. They're correctly linked to their Python versions
2. They have the correct structure
3. They use the same build process

The segfaults suggest:
- **Runtime ABI mismatch**: The extension modules may have been compiled with flags incompatible with Python 3.9+
- **Missing symbols**: Some required symbols may be missing or incorrectly linked
- **Library loading issues**: The .so files may fail to load correctly in Python 3.9+ environments

## Recommendations

### Immediate Actions

1. **Check GitHub Actions Build Logs**
   - Review logs for Python 3.9-3.13 builds
   - Look for compiler warnings
   - Check for linker errors
   - Verify all dependencies were found correctly

2. **Rebuild Wheels with Additional Verification**
   - Add build-time verification that .so files can be loaded
   - Add post-build testing in GitHub Actions
   - Verify extension module initialization works

3. **Consider Removing ABI3 Tag**
   - Since code doesn't use `Py_LIMITED_API`, wheels shouldn't be tagged as `abi3`
   - Build wheels with version-specific tags (cp39, cp310, etc.) instead of cp38-abi3
   - This would require changes to how scikit-build tags wheels

### Long-term Solutions

1. **Add Post-Build Testing in GitHub Actions**
   - Test each wheel after building
   - Verify imports work before uploading
   - Fail the build if any wheel fails tests

2. **Investigate ABI3 vs Full API**
   - Determine if we can use `Py_LIMITED_API` with SWIG 4.4.0
   - Or ensure wheels are correctly tagged based on actual API usage
   - May need to use different build flags for different Python versions

3. **Add Runtime Verification**
   - Check that .so files can be loaded
   - Verify all required symbols are present
   - Test extension module initialization

## Next Steps

1. Review GitHub Actions build logs for Python 3.9-3.13
2. Compare successful Python 3.8 build with failed 3.9+ builds
3. Consider rebuilding wheels with additional verification
4. Add post-build testing to catch these issues before release

