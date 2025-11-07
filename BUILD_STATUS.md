# Build Status: All Working ✅

**Last Verified:** 2025-11-07  
**Status:** ✅ All local builds and tox tests passing

## Summary

All wheel builds and tests are now working correctly. This document serves as a reference point to prevent future regressions.

## What's Working

### Local Builds
- ✅ `build_wheels.sh` builds wheels for all Python versions (3.8-3.13) and architectures (ARM64, x86_64)
- ✅ Each wheel is correctly linked to its specific Python version's library
- ✅ No cross-version contamination (each Python version gets its own build artifacts)
- ✅ Wheels are correctly named with version-specific tags (cp38, cp39, cp310, etc.)

### Tox Tests
- ✅ All Python versions (3.8-3.13) pass tox tests
- ✅ Tests use pre-built wheels from `dist/` folder
- ✅ No segfaults or import errors
- ✅ Hardware tests work with auto-detection

### GitHub Actions
- ✅ Build workflows configured for x86_64 (Intel macOS) and ARM64 (Apple Silicon)
- ✅ Release workflow creates releases with all wheels
- ✅ All Python versions (3.8-3.13) supported

## Critical Fixes Applied

### 1. CMakeLists.txt
**Problem:** `PYTHON_LIBRARY_FROM_USER_FLAGS` was set from scikit-build's `find_package(PythonExtensions)`, which found Python 3.13 from PATH before `PYTHON_EXECUTABLE` was used. The linker used this wrong library at link time.

**Fix:** Override `PYTHON_LIBRARY_FROM_USER_FLAGS` from `PYTHON_EXECUTABLE` BEFORE linking:
```cmake
# CRITICAL: If PYTHON_EXECUTABLE is provided, determine the correct Python library from it
if(PYTHON_EXECUTABLE AND APPLE)
    execute_process(
        COMMAND ${PYTHON_EXECUTABLE} -c "import sysconfig; libdir = sysconfig.get_config_var('LIBDIR'); libfile = sysconfig.get_config_var('LIBRARY'); libpath = f'{libdir}/{libfile}' if libfile else libdir; print(libpath)"
        OUTPUT_VARIABLE PYTHON_LIB_FROM_EXE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(PYTHON_LIB_FROM_EXE AND EXISTS "${PYTHON_LIB_FROM_EXE}")
        set(PYTHON_LIBRARY_FROM_USER_FLAGS "${PYTHON_LIB_FROM_EXE}")
    endif()
endif()
```

### 2. build_wheels.sh
**Problem:** Old build artifacts in `_skbuild/` were being reused, causing all wheels to be built with Python 3.13.

**Fixes:**
- Clean `_skbuild/` directory at the start
- Clean Python-specific build directories before each build
- Verify Python version matches before building
- Add more CMake flags to force correct Python detection:
  - `-DPython3_EXECUTABLE` (explicit executable)
  - `-DPython3_ROOT_DIR` (explicit root directory)
  - `-DPython3_FIND_VIRTUALENV=ONLY` (prefer virtualenv Python)
- Unset PYTHONPATH and adjust PATH to prevent interference

### 3. .tox_find_wheel.py
**Problem:** Wheels were being used even when they were linked to wrong Python version.

**Fix:** Verify wheel's `.so` files are linked to correct Python version before installing. Fail if wrong version detected.

### 4. GitHub Actions Workflows
**Problem:** Workflows were missing the additional CMake flags and cleaning steps.

**Fix:** Added:
- Clean `_skbuild` before each build
- Additional CMake flags matching `build_wheels.sh`:
  - `-DPython3_EXECUTABLE`
  - `-DPython3_ROOT_DIR`
  - `-DPython3_FIND_VIRTUALENV=ONLY`

## How to Verify Everything is Working

### Local Build
```bash
# Build all wheels
./build_wheels.sh

# Verify all wheels exist
ls -lh dist/*.whl

# Run tox tests (uses pre-built wheels)
tox
```

### Expected Results
- ✅ All 6 Python versions (3.8-3.13) have wheels in `dist/`
- ✅ All tox tests pass
- ✅ No segfaults or import errors
- ✅ Each wheel's `.so` files are linked to correct Python version

## If Tests Fail Again

### Check These First:
1. **Are wheels linked to wrong Python version?**
   ```bash
   otool -L dist/pc_ble_driver_py-*-cp38-abi3-*.whl | grep libpython
   # Should show libpython3.8.dylib, not libpython3.13.dylib
   ```

2. **Is _skbuild contaminated?**
   ```bash
   find _skbuild -name "*3.13*" -type d
   # Should be empty if building for Python 3.8
   ```

3. **Is PYTHON_EXECUTABLE being passed correctly?**
   - Check `build_wheels.sh` logs for "Verified Python version"
   - Check CMake logs for "Overriding PYTHON_LIBRARY_FROM_USER_FLAGS"

### Common Regressions:
- **All wheels built with Python 3.13:** Clean `_skbuild/` and ensure `PYTHON_EXECUTABLE` is passed to CMake
- **Segfaults in tox:** Check wheel's `.so` files are linked to correct Python version
- **Missing wheels:** Check `build_wheels.sh` rename logic and wheel finding

## Files to Monitor

If regressions occur, check these files haven't been modified incorrectly:
- `CMakeLists.txt` - Python library override logic (lines 18-33)
- `build_wheels.sh` - Cleaning and Python version verification
- `.tox_find_wheel.py` - Wheel verification logic
- `.github/workflows/*.yml` - CMake flags and cleaning steps

## Notes

- Each Python version MUST be built with its own Python executable
- `PYTHON_LIBRARY_FROM_USER_FLAGS` MUST be overridden from `PYTHON_EXECUTABLE`
- `_skbuild/` MUST be cleaned between builds to prevent contamination
- Wheels MUST be verified before use in tox tests
