# Fixing Universal2 Wheel Python Version Compatibility

## Problem

The Universal2 wheel has mixed Python versions:
- **x86_64 slice**: Built with Python 3.12 → requires `libpython3.12.dylib`
- **arm64 slice**: Built with Python 3.13 → requires `libpython3.13.dylib`

When Python 3.8-3.12 (on ARM64) tries to use the wheel, it loads the arm64 slice which requires Python 3.13, causing segfaults.

## Solution

Rebuild the ARM64 wheel with Python 3.12, then recreate the Universal2 wheel.

### Step 1: Rebuild ARM64 Wheel with Python 3.12

```bash
cd /Users/kbalive/Devel/OpenSource/pc-ble-driver-py

export VCPKG_ROOT=/Users/kbalive/Devel/OpenSource/vcpkg
export CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake
export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/arm64-osx

# Build ARM64 wheel with Python 3.12
/usr/local/bin/python3.12 setup.py bdist_wheel --build-type Release \
    -- -DCMAKE_OSX_ARCHITECTURES=arm64

# This creates: dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_arm64.whl
```

### Step 2: Recreate Universal2 Wheel

```bash
# Use the create_universal2_wheel.sh script
./create_universal2_wheel.sh \
    dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_arm64.whl \
    dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_x86_64.whl \
    dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_universal2.whl
```

Or manually:

```bash
# Extract both wheels
mkdir -p /tmp/universal2_build
cd /tmp/universal2_build

unzip -q /Users/kbalive/Devel/OpenSource/pc-ble-driver-py/dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_arm64.whl
unzip -q /Users/kbalive/Devel/OpenSource/pc-ble-driver-py/dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_x86_64.whl

# Combine .so files using lipo
lipo -create \
    pc_ble_driver_py/lib/_nrf_ble_driver_sd_api_v5.so \
    -output pc_ble_driver_py/lib/_nrf_ble_driver_sd_api_v5.so

lipo -create \
    pc_ble_driver_py/lib/_nrf_ble_driver_sd_api_v2.so \
    -output pc_ble_driver_py/lib/_nrf_ble_driver_sd_api_v2.so

# Recreate wheel (use wheel package or zip)
cd /Users/kbalive/Devel/OpenSource/pc-ble-driver-py
python3 -m wheel pack /tmp/universal2_build
```

## Why This Happens

Even with `cp38-abi3` (Python 3.8+ stable ABI), the **native libraries** are still linked against the specific Python version used to build them. The `abi3` tag only applies to the Python code, not the C++ extensions.

## Verification

After rebuilding, verify both slices use Python 3.12:

```bash
otool -L dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_universal2.whl \
    | grep -A 1 "architecture x86_64" | grep python
otool -L dist/pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_universal2.whl \
    | grep -A 1 "architecture arm64" | grep python
```

Both should show `@rpath/libpython3.12.dylib`.

## Result

After rebuilding:
- ✅ Both x86_64 and arm64 slices require `libpython3.12.dylib`
- ✅ Works with Python 3.8-3.13 (Python 3.12 library is available in all)
- ✅ All tox tests should pass

