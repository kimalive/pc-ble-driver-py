#!/usr/bin/env python3
"""
Quick test script to verify GitHub release wheels work.
Usage: python test_release_quick.py [python_version] [arch]
Example: python test_release_quick.py 3.12 arm64
"""

import sys
import subprocess
import urllib.request
import tempfile
import os

def test_wheel(python_version, arch='arm64'):
    """Test a wheel from GitHub release"""
    cp_tag_map = {
        '3.8': 'cp38',
        '3.9': 'cp39',
        '3.10': 'cp310',
        '3.11': 'cp311',
        '3.12': 'cp312',
        '3.13': 'cp313',
    }
    
    cp_tag = cp_tag_map.get(python_version)
    if not cp_tag:
        print(f"Unsupported Python version: {python_version}")
        return False
    
    wheel_url = f"https://github.com/kimalive/pc-ble-driver-py/releases/download/v0.17.11/pc_ble_driver_py-0.17.11-{cp_tag}-abi3-macosx_26_0_{arch}.whl"
    
    print(f"Testing wheel: {wheel_url}")
    print(f"Python: {python_version}, Architecture: {arch}")
    print()
    
    # Create temp venv
    with tempfile.TemporaryDirectory() as tmpdir:
        venv_dir = os.path.join(tmpdir, 'venv')
        python_exe = f"python{python_version}"
        
        print(f"Creating virtual environment...")
        subprocess.run([python_exe, '-m', 'venv', venv_dir], check=True)
        
        pip_exe = os.path.join(venv_dir, 'bin', 'pip')
        python_venv = os.path.join(venv_dir, 'bin', 'python')
        
        print(f"Installing wheel...")
        subprocess.run([pip_exe, 'install', '--upgrade', 'pip', '--quiet'], check=True)
        subprocess.run([pip_exe, 'install', wheel_url, '--quiet'], check=True)
        
        print(f"Testing imports...")
        result = subprocess.run([
            python_venv, '-c', '''
import sys
print(f"Python: {sys.version}")

try:
    import pc_ble_driver_py
    print("✓ Imported pc_ble_driver_py")
    
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v5
    print("✓ Imported nrf_ble_driver_sd_api_v5")
    
    import pc_ble_driver_py.lib.nrf_ble_driver_sd_api_v2
    print("✓ Imported nrf_ble_driver_sd_api_v2")
    
    from pc_ble_driver_py.ble_driver import BLEDriver
    print("✓ Imported BLEDriver")
    
    print("")
    print("✓ All tests passed!")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
'''
        ], capture_output=True, text=True)
        
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        
        return result.returncode == 0

if __name__ == '__main__':
    python_version = sys.argv[1] if len(sys.argv) > 1 else '3.12'
    arch = sys.argv[2] if len(sys.argv) > 2 else 'arm64'
    
    success = test_wheel(python_version, arch)
    sys.exit(0 if success else 1)
