# Testing Wheels - Best Practices

## Important: Always Test with Fresh Installs

When testing wheel fixes (rpath, bundling, etc.), **always** use fresh installations to ensure you're testing the updated wheel, not a cached or old version.

## Quick Test Script

Use `test_wheel_fresh.sh` for reliable testing:

```bash
./test_wheel_fresh.sh dist/pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl python3.12
```

This script:
1. ✅ Uninstalls existing installation
2. ✅ Clears pip cache
3. ✅ Installs with `--force-reinstall --no-deps --no-cache-dir`
4. ✅ Verifies installation location and timestamps
5. ✅ Tests import

## Manual Testing Steps

If you prefer manual testing:

```bash
# 1. Uninstall existing
python3.12 -m pip uninstall -y pc-ble-driver-py

# 2. Clear cache (optional but recommended)
python3.12 -m pip cache purge

# 3. Install with no cache
python3.12 -m pip install --force-reinstall --no-deps --no-cache-dir dist/pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl

# 4. Test import
python3.12 -c "from pc_ble_driver_py.ble_driver import BLEDriver; print('OK')"
```

## Why This Matters

- **Same version number**: If the wheel version doesn't change, pip might use cached version
- **Wheel modifications**: Post-processing (rpath fixes, bundling) modifies wheels in-place
- **Cache issues**: pip cache might serve old wheel even if file changed
- **Verification**: Need to confirm the installed .so matches the wheel's .so

## Checking Wheel Timestamps

Always verify the wheel file timestamp matches when you expect it was modified:

```bash
ls -lht dist/*.whl
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" dist/pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl
```

## Verifying Installation

After installation, verify the installed .so file matches the wheel:

```bash
# Get installation location
python3.12 -c "import pc_ble_driver_py; import os; print(os.path.dirname(pc_ble_driver_py.__file__))"

# Check .so file timestamp
stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" <path_to_installed_so>
```

## Common Issues

### Issue: "Wheel not updating"
- **Cause**: pip cache or same version number
- **Fix**: Use `--force-reinstall --no-cache-dir`

### Issue: "Old .so file still used"
- **Cause**: Installation didn't update, or wrong location
- **Fix**: Verify installation path, uninstall completely first

### Issue: "Test passes but production fails"
- **Cause**: Different Python environment or cache
- **Fix**: Test in clean environment matching production

