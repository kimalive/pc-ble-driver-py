# Testing GitHub Release Wheels

## Current Status

The release [v0.17.11](https://github.com/kimalive/pc-ble-driver-py/releases/tag/v0.17.11) currently has issues:
- Only Python 3.8 wheels are available (should have 3.8-3.13)
- Wheels appear to be invalid/corrupted
- Version mismatch: wheels are 0.17.10 but release is 0.17.11

## How to Test (Once Wheels Are Fixed)

### 1. List Available Wheels

```bash
python3.12 list_release_wheels.py v0.17.11
```

### 2. Test a Specific Wheel

**ARM64 (Apple Silicon):**
```bash
# Python 3.12
pip install https://github.com/kimalive/pc-ble-driver-py/releases/download/v0.17.11/pc_ble_driver_py-0.17.11-cp312-abi3-macosx_26_0_arm64.whl

# Python 3.8
pip install https://github.com/kimalive/pc-ble-driver-py/releases/download/v0.17.11/pc_ble_driver_py-0.17.11-cp38-abi3-macosx_26_0_arm64.whl
```

**x86_64 (Intel Mac):**
```bash
# Python 3.12
pip install https://github.com/kimalive/pc-ble-driver-py/releases/download/v0.17.11/pc_ble_driver_py-0.17.11-cp312-abi3-macosx_26_0_x86_64.whl
```

### 3. Verify Installation

```python
python -c "
import pc_ble_driver_py
from pc_ble_driver_py.ble_driver import BLEDriver
print('✓ Installation successful!')
print(f'Version: {pc_ble_driver_py.__version__ if hasattr(pc_ble_driver_py, \"__version__\") else \"Unknown\"}')
"
```

### 4. Run Full Test Suite

```bash
# Using the test script
./test_release_wheel.sh 3.12 arm64

# Or using Python script
python3.12 test_release_quick.py 3.12 arm64
```

## Expected Wheels

The release should contain:
- **ARM64**: Python 3.8, 3.9, 3.10, 3.11, 3.12, 3.13 (6 wheels)
- **x86_64**: Python 3.8, 3.9, 3.10, 3.11, 3.12, 3.13 (6 wheels)
- **Total**: 12 wheels

## Next Steps

1. Fix GitHub Actions workflow to build all Python versions
2. Ensure wheels are correctly named (0.17.11, not 0.17.10)
3. Verify wheels are valid before uploading
4. Upload all wheels to the release
