#!/usr/bin/env python3
"""
Post-build hook to bundle nrf-ble-driver dependencies into wheels.
This is called after wheel is built to add dependencies.
"""
import os
import sys
import shutil
import zipfile
import tempfile
from pathlib import Path

VCPKG_ROOT = os.getenv('VCPKG_ROOT', '/Users/kbalive/Devel/OpenSource/vcpkg')
# Determine architecture from VCPKG_ROOT or environment
# Default to arm64-osx for local builds, but allow override via VCPKG_TRIPLET
VCPKG_TRIPLET = os.getenv('VCPKG_TRIPLET', 'arm64-osx')
VCPKG_LIB_DIR = f"{VCPKG_ROOT}/installed/{VCPKG_TRIPLET}/lib"

def bundle_dependencies(wheel_path):
    """Bundle nrf-ble-driver dependencies into a wheel."""
    if not os.path.exists(wheel_path):
        return False
    
    if not os.path.exists(VCPKG_LIB_DIR):
        print(f"⚠️  VCPKG_LIB_DIR not found: {VCPKG_LIB_DIR}")
        print("   Skipping bundling (wheels may not work without vcpkg libraries)")
        return False
    
    print(f"Bundling dependencies into: {os.path.basename(wheel_path)}")
    
    # Libraries to bundle
    libs_to_bundle = [
        "libnrf-ble-driver-sd_api_v2.4.1.4.dylib",
        "libnrf-ble-driver-sd_api_v5.4.1.4.dylib",
    ]
    
    # Check which libraries exist
    existing_libs = []
    for lib in libs_to_bundle:
        lib_path = os.path.join(VCPKG_LIB_DIR, lib)
        if os.path.exists(lib_path):
            existing_libs.append((lib, lib_path))
        else:
            print(f"  ⚠️  {lib} not found (may not be needed)")
    
    if not existing_libs:
        print("  ⚠️  No libraries to bundle (using static linking)")
        return False
    
    # Extract wheel
    temp_dir = tempfile.mkdtemp()
    try:
        with zipfile.ZipFile(wheel_path, 'r') as zip_ref:
            zip_ref.extractall(temp_dir)
        
        # Create deps directory
        deps_dir = os.path.join(temp_dir, 'pc_ble_driver_py', 'lib', 'deps')
        os.makedirs(deps_dir, exist_ok=True)
        
        # Copy libraries
        bundled = False
        for lib_name, lib_path in existing_libs:
            dest = os.path.join(deps_dir, lib_name)
            shutil.copy2(lib_path, dest)
            print(f"  ✓ Bundled: {lib_name}")
            bundled = True
        
        if not bundled:
            return False
        
        # Update .so files to use bundled libraries
        import subprocess
        lib_dir = os.path.join(temp_dir, 'pc_ble_driver_py', 'lib')
        for so_file in Path(lib_dir).glob('*.so'):
            if 'deps' not in str(so_file):
                # Add @loader_path/deps to rpath
                subprocess.run(
                    ['install_name_tool', '-add_rpath', '@loader_path/deps', str(so_file)],
                    capture_output=True
                )
                print(f"  ✓ Updated rpath in {so_file.name}")
        
        # Recreate wheel
        # Note: Backup is created temporarily during bundling, but will be cleaned up by build script
        backup_path = f"{wheel_path}.backup"
        if not os.path.exists(backup_path):
            shutil.copy2(wheel_path, backup_path)
        
        with zipfile.ZipFile(wheel_path, 'w', zipfile.ZIP_DEFLATED) as zip_ref:
            for root, dirs, files in os.walk(temp_dir):
                for file in files:
                    file_path = os.path.join(root, file)
                    arc_name = os.path.relpath(file_path, temp_dir)
                    zip_ref.write(file_path, arc_name)
        
        # Calculate size
        old_size = os.path.getsize(backup_path) / (1024 * 1024)
        new_size = os.path.getsize(wheel_path) / (1024 * 1024)
        print(f"  ✓ Bundled wheel: {old_size:.1f}MB → {new_size:.1f}MB")
        return True
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: bundle_into_wheel.py <wheel_file>")
        sys.exit(1)
    
    wheel_path = sys.argv[1]
    if bundle_dependencies(wheel_path):
        print("✓ Bundling complete")
        sys.exit(0)
    else:
        print("⚠️  Bundling skipped or failed")
        sys.exit(1)
