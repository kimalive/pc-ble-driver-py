# Building Wheels for All Python Versions

This document explains how to build wheels for all supported Python versions (3.8-3.13) and architectures (ARM64 and x86_64).

## Quick Start

```bash
# Build all wheels
./build_wheels.sh
```

This will:
1. Build ARM64 wheels for Python 3.8, 3.9, 3.10, 3.11, 3.12, 3.13
2. Attempt to build x86_64 wheels (may fail on Apple Silicon without Intel Python)
3. Place all wheels in the `dist/` directory

## Wheel Naming

Wheels are named with the pattern:
```
pc_ble_driver_py-0.17.10-cpXX-abi3-macosx_26_0_<arch>.whl
```

Where:
- `cpXX` is the Python version tag (e.g., `cp38`, `cp312`)
- `<arch>` is the architecture (`arm64` or `x86_64`)

Examples:
- `pc_ble_driver_py-0.17.10-cp38-abi3-macosx_26_0_arm64.whl` (Python 3.8, ARM64)
- `pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl` (Python 3.12, ARM64)
- `pc_ble_driver_py-0.17.10-cp313-abi3-macosx_26_0_x86_64.whl` (Python 3.13, x86_64)

## How Tox Finds Wheels

The `.tox_find_wheel.py` script automatically finds the correct wheel for each Python version:

1. **Exact match**: Looks for `dist/*cpXX-abi3-*<arch>*.whl` matching the current Python version and architecture
2. **Universal2 fallback**: If no exact match, tries universal2 wheels
3. **Architecture fallback**: Tries any wheel with matching architecture
4. **Build from source**: If no wheel found, builds from source

## Building x86_64 Wheels on Apple Silicon

Building x86_64 wheels on Apple Silicon requires:
- Intel Python installed (or Rosetta 2)
- Or use CI/CD on an Intel Mac

The build script will attempt to build x86_64 wheels but may fail if Intel Python is not available.

## Testing with Tox

After building wheels, tox will automatically use them:

```bash
# Run all tests (uses prebuilt wheels)
./run_tox.sh

# Run tests for specific Python version
./run_tox.sh -e py312

# Run software-only tests
./run_tox.sh -e test-software
```

## Manual Installation

You can also manually install a specific wheel:

```bash
# Install Python 3.12 ARM64 wheel
python3.12 -m pip install --force-reinstall --no-deps \
    dist/pc_ble_driver_py-0.17.10-cp312-abi3-macosx_26_0_arm64.whl
```

## CI/CD Integration

For automated builds, you can use GitHub Actions or similar CI/CD to:
1. Build wheels for all Python versions
2. Build for both ARM64 and x86_64
3. Upload to PyPI or GitHub Releases

Example GitHub Actions workflow:
```yaml
strategy:
  matrix:
    python-version: ['3.8', '3.9', '3.10', '3.11', '3.12', '3.13']
    os: [macos-latest]  # or macos-13 for Intel
```

## Troubleshooting

### Wheel Not Found

If tox can't find a wheel:
1. Check that wheels are in `dist/` directory
2. Verify wheel naming matches the pattern
3. Check that Python version matches (e.g., Python 3.12 needs `cp312` wheel)

### x86_64 Build Fails

If x86_64 builds fail on Apple Silicon:
- This is expected if Intel Python is not installed
- Use CI/CD on an Intel Mac for x86_64 wheels
- Or build Universal2 wheels (combines both architectures)

### Wrong Architecture

If you get architecture mismatch errors:
- Verify you're using the correct wheel for your architecture
- ARM64 Macs need `arm64` wheels
- Intel Macs need `x86_64` wheels
- Universal2 wheels work on both

