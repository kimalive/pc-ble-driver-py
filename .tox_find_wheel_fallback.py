#!/usr/bin/env python3
"""Helper script to find and install wheel, with fallback to building from source."""
import glob
import os
import sys
import subprocess
import platform

def get_python_tag():
    """Get Python tag for current Python version (e.g., cp38, cp312)."""
    major, minor = sys.version_info[:2]
    return f"cp{major}{minor}"

def get_architecture():
    """Get current architecture."""
    machine = platform.machine().lower()
    if machine == 'arm64' or machine == 'aarch64':
        return 'arm64'
    elif machine == 'x86_64' or machine == 'amd64':
        return 'x86_64'
    else:
        return machine

def find_wheel():
    """Find the best available wheel for current Python version and architecture."""
    python_tag = get_python_tag()
    arch = get_architecture()
    
    print(f"Looking for wheel: Python {sys.version_info.major}.{sys.version_info.minor} ({python_tag}), Architecture: {arch}")
    
    patterns = [
        f'dist/*{python_tag}-abi3-*.whl',
        'dist/*universal*.whl',
        'dist/*universal2*.whl',
        f'dist/*{python_tag}-abi3-*{arch}*.whl',
        f'dist/*{arch}*.whl',
        f'dist/*{python_tag}*.whl',
        'dist/*.whl'
    ]
    
    for pattern in patterns:
        wheels = glob.glob(pattern)
        if wheels:
            exact_matches = [w for w in wheels if python_tag in os.path.basename(w)]
            if exact_matches:
                wheel = exact_matches[0]
            else:
                wheel = wheels[0]
            
            if os.path.exists(wheel):
                return wheel
    
    return None

def test_wheel_import(wheel):
    """Test if wheel can be imported without segfault."""
    print(f"Testing wheel import: {os.path.basename(wheel)}")
    # Install wheel temporarily
    result = subprocess.run([
        sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', '--quiet', wheel
    ], capture_output=True)
    
    if result.returncode != 0:
        print(f"  ✗ Failed to install wheel")
        return False
    
    # Try to import
    test_result = subprocess.run([
        sys.executable, '-c',
        'from pc_ble_driver_py import config; config.__conn_ic_id__ = "NRF52"; import pc_ble_driver_py.ble_driver'
    ], capture_output=True, timeout=5)
    
    if test_result.returncode == 0:
        print(f"  ✓ Wheel import works")
        return True
    else:
        print(f"  ✗ Wheel segfaults or fails to import (exit code: {test_result.returncode})")
        # Uninstall failed wheel
        subprocess.run([sys.executable, '-m', 'pip', 'uninstall', '-y', 'pc-ble-driver-py'], 
                      capture_output=True)
        return False

def main():
    # Check if we should skip wheel testing (for faster development)
    if os.getenv('TOX_SKIP_WHEEL_TEST', '').lower() == 'true':
        print("Skipping wheel test (TOX_SKIP_WHEEL_TEST=true)")
        wheel = find_wheel()
        if wheel:
            print(f"Installing wheel: {os.path.basename(wheel)}")
            result = subprocess.run([
                sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', wheel
            ])
            return result.returncode
        else:
            print("No wheel found, building from source...")
    else:
        wheel = find_wheel()
        if wheel:
            # Test if wheel works
            if test_wheel_import(wheel):
                print(f"✓ Using working wheel: {os.path.basename(wheel)}")
                return 0
            else:
                print(f"⚠️  Wheel found but segfaults, falling back to building from source...")
        else:
            print("⚠️  No matching wheel found in dist/")
    
    # Fall back to building from source
    print("Building from source as fallback...")
    build_result = subprocess.run([
        sys.executable, 'setup.py', 'build', '--build-type', 'Release'
    ])
    if build_result.returncode != 0:
        return build_result.returncode
    
    # Copy libraries
    import shutil
    libs = glob.glob('_skbuild/*/cmake-install/pc_ble_driver_py/lib/*.so')
    for lib in libs:
        shutil.copy2(lib, 'pc_ble_driver_py/lib/')
    
    # Install editable
    install_result = subprocess.run([
        sys.executable, '-m', 'pip', 'install', '-e', '.', '--no-build-isolation', '--no-deps'
    ])
    return install_result.returncode

if __name__ == '__main__':
    sys.exit(main())
