#!/usr/bin/env python3
"""Helper script to find and install the best available wheel for current Python version."""
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
    
    # Priority order:
    # 1. Bundled wheel (preferred - self-contained)
    # 2. Exact match: cpXX-abi3-*_arch.whl (e.g., cp312-abi3-*_arm64.whl)
    # 3. For abi3 wheels, also check cp38 (abi3 wheels use cp38 tag for Python 3.8+)
    # 4. Universal2 wheel (if available)
    # 5. Any wheel with matching architecture
    # 6. Any wheel
    
    patterns = [
        # Bundled wheel (preferred) - look for exact Python version first
        f'dist/*{python_tag}-abi3-*{arch}*_bundled.whl',
        f'dist/*{python_tag}-abi3-*_bundled.whl',
        # Exact match for this Python version (wheels are renamed to preserve Python version)
        # Even though they're tagged cp38-abi3 internally, the filename includes the build Python version
        f'dist/*{python_tag}-abi3-*.whl',
        # For abi3 wheels, also check cp38 (abi3 wheels use cp38 tag internally)
        # But we prefer wheels built with the matching Python version
        # This is important because abi3 wheels built with any Python 3.8+ version
        # are tagged as cp38-abi3 internally, but we rename them to preserve the build Python version
    ]
    # Add cp38-abi3 pattern if Python version is 3.8 or later (fallback)
    # Note: This will find wheels that weren't renamed, but we prefer version-specific ones
    python_version_num = int(python_tag.replace('cp', ''))
    if python_version_num >= 38:
        patterns.append('dist/*cp38-abi3-*.whl')
    
    patterns.extend([
        # Universal2 wheel (works on both architectures)
        'dist/*universal*.whl',
        'dist/*universal2*.whl',
        # Architecture-specific wheel with Python tag
        f'dist/*{python_tag}-abi3-*{arch}*.whl',
        # Architecture-specific wheel (any Python version)
        f'dist/*{arch}*.whl',
        # Any wheel with Python tag
        f'dist/*{python_tag}*.whl',
        # Any wheel
        'dist/*.whl'
    ])
    
    for pattern in patterns:
        wheels = glob.glob(pattern)
        if wheels:
            # Prefer exact Python version match
            exact_matches = [w for w in wheels if python_tag in os.path.basename(w)]
            if exact_matches:
                wheel = exact_matches[0]
            else:
                wheel = wheels[0]
            
            if os.path.exists(wheel):
                return wheel
    
    return None

def verify_so_python_version(so_file, expected_version):
    """Verify that .so file is linked to the correct Python version."""
    import subprocess
    try:
        result = subprocess.run(
            ['otool', '-L', so_file],
            capture_output=True,
            text=True,
            check=True
        )
        # Check if it's linked to the expected Python version
        expected_lib = f"libpython{expected_version}.dylib"
        if expected_lib in result.stdout or f"Python.framework/Versions/{expected_version}" in result.stdout:
            return True
        # If linked to wrong version, return False
        for line in result.stdout.split('\n'):
            if 'libpython' in line or 'Python.framework' in line:
                print(f"  ⚠️  {os.path.basename(so_file)} is linked to wrong Python version:")
                print(f"     {line.strip()}")
                print(f"     Expected: {expected_lib}")
                return False
        return True  # No Python library found (might be statically linked)
    except Exception as e:
        print(f"  ⚠️  Could not verify {os.path.basename(so_file)}: {e}")
        return True  # Assume OK if we can't check

def clean_lib_directory():
    """Comprehensively clean the lib directory to prevent cross-version contamination."""
    lib_dir = 'pc_ble_driver_py/lib'
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
    
    if not os.path.exists(lib_dir):
        os.makedirs(lib_dir, exist_ok=True)
        return True
    
    # Clean ALL .so files (they might be from wrong Python version)
    old_so_files = glob.glob(os.path.join(lib_dir, '*.so'))
    if old_so_files:
        print(f"🧹 Cleaning {len(old_so_files)} old .so file(s) to prevent version mismatch...")
        for old_so in old_so_files:
            # Verify before removing (for debugging)
            if not verify_so_python_version(old_so, python_version):
                print(f"  ⚠️  Removing incompatible .so file: {os.path.basename(old_so)}")
            try:
                os.remove(old_so)
                print(f"  ✓ Removed {os.path.basename(old_so)}")
            except Exception as e:
                print(f"  ✗ Failed to remove {os.path.basename(old_so)}: {e}")
    
    # Also clean old Python wrapper files
    old_py_files = [f for f in glob.glob(os.path.join(lib_dir, '*.py')) 
                   if os.path.basename(f) in ['nrf_ble_driver_sd_api_v2.py', 'nrf_ble_driver_sd_api_v5.py', '__init__.py']]
    if old_py_files:
        print(f"🧹 Cleaning {len(old_py_files)} old Python wrapper file(s)...")
        for old_py in old_py_files:
            try:
                os.remove(old_py)
                print(f"  ✓ Removed {os.path.basename(old_py)}")
            except Exception as e:
                print(f"  ✗ Failed to remove {os.path.basename(old_py)}: {e}")
    
    # Verify directory is clean - CRITICAL: fail if not clean
    remaining_so = glob.glob(os.path.join(lib_dir, '*.so'))
    if remaining_so:
        print(f"  ✗ ERROR: {len(remaining_so)} .so file(s) still remain after cleaning!")
        for so in remaining_so:
            print(f"     {os.path.basename(so)}")
        print(f"  This will cause cross-version contamination!")
        return False
    else:
        print(f"  ✓ lib/ directory is clean")
        return True

def main():
    # CRITICAL: Clean old .so files first to prevent cross-version contamination
    # This MUST happen before any build or wheel installation
    # Fail if cleaning doesn't work
    if not clean_lib_directory():
        print("✗ Failed to clean lib/ directory - aborting to prevent contamination")
        return 1
    
    # Check if we should use wheels
    # Default: Build from source for all versions to ensure correct Python version linking
    # Only use wheels if explicitly requested via TOX_USE_WHEELS=true
    # This prevents using wheels built with wrong Python version
    use_wheels = os.getenv('TOX_USE_WHEELS', 'false').lower() == 'true'
    
    if use_wheels:
        wheel = find_wheel()
        if wheel:
            print(f"Installing wheel: {os.path.basename(wheel)}")
            # CRITICAL: Verify wheel is for correct Python version before installing
            # Extract and check the .so files in the wheel
            import tempfile
            import zipfile
            with tempfile.TemporaryDirectory() as tmpdir:
                with zipfile.ZipFile(wheel, 'r') as z:
                    z.extractall(tmpdir)
                # Check .so files in the wheel
                wheel_so_files = glob.glob(os.path.join(tmpdir, 'pc_ble_driver_py/lib/*.so'))
                wheel_ok = True
                for so_file in wheel_so_files:
                    if not verify_so_python_version(so_file, python_version):
                        print(f"✗ ERROR: Wheel {os.path.basename(wheel)} contains .so files for wrong Python version!")
                        print(f"   This will cause segfaults! Building from source instead...")
                        wheel_ok = False
                        break
                
                if not wheel_ok:
                    # Fall through to build from source
                    pass
                else:
                    result = subprocess.run([
                        sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', wheel
                    ])
                    if result.returncode == 0:
                        print(f"✓ Successfully installed wheel (verified Python {python_version})")
                    return result.returncode
        else:
            print("⚠️  No matching wheel found in dist/")
            print("   Expected: dist/*{}-abi3-*{}*.whl".format(get_python_tag(), get_architecture()))
            print("   Building from source as fallback...")
    else:
        print("Building from source (TOX_USE_WHEELS not set or false)")
        print("   Set TOX_USE_WHEELS=true to test wheels")
    
    # Build from source (default behavior)
    build_result = subprocess.run([
        sys.executable, 'setup.py', 'build', '--build-type', 'Release'
    ])
    if build_result.returncode != 0:
        return build_result.returncode
    
    # Copy libraries (prefer matching Python version)
    import shutil
    import platform
    
    # Find build directory for current Python version
    # Pattern: _skbuild/macosx-*-arm64-{version}/cmake-install/...
    build_dirs = glob.glob(f'_skbuild/*/cmake-install/pc_ble_driver_py/lib')
    matching_dir = None
    for build_dir in build_dirs:
        # Extract Python version from path (e.g., macosx-26.0-arm64-3.12)
        # Use exact match with version number to avoid false matches (e.g., "3.9" matching "3.10")
        # The path should contain "-{major}.{minor}" pattern
        version_pattern = f"-{python_version}"
        if version_pattern in build_dir:
            matching_dir = build_dir
            break
    
    if not matching_dir and build_dirs:
        # Don't use fallback - this could cause wrong Python version to be used!
        print(f"⚠️  No build directory found for Python {python_version}")
        print(f"   Available build directories: {[os.path.basename(os.path.dirname(os.path.dirname(d))) for d in build_dirs]}")
        print(f"   This might cause segfaults - rebuilding...")
        # Force a rebuild by returning error, which will cause setup.py build to run again
        return 1
    
    if matching_dir:
        # CRITICAL: Verify lib directory is still clean before copying
        remaining_before = glob.glob(os.path.join('pc_ble_driver_py/lib', '*.so'))
        if remaining_before:
            print(f"✗ ERROR: lib/ directory not clean before copying! Found: {[os.path.basename(f) for f in remaining_before]}")
            return 1
        
        # Copy .so files
        so_files = glob.glob(os.path.join(matching_dir, '*.so'))
        if so_files:
            print(f"Copying {len(so_files)} .so file(s) to pc_ble_driver_py/lib/")
            for so_file in so_files:
                dest = os.path.join('pc_ble_driver_py/lib', os.path.basename(so_file))
                shutil.copy2(so_file, dest)
                # CRITICAL: Verify the copied file is for correct Python version
                if not verify_so_python_version(dest, python_version):
                    print(f"  ✗ ERROR: Copied {os.path.basename(so_file)} but Python version mismatch!")
                    print(f"     This will cause segfaults! Aborting.")
                    # Remove the bad file
                    try:
                        os.remove(dest)
                    except:
                        pass
                    return 1
                print(f"  ✓ Copied {os.path.basename(so_file)} (verified Python {python_version})")
        else:
            print("⚠️  No .so files found to copy")
        
        # Copy Python wrapper files (only from matching build directory)
        wrapper_files = glob.glob(os.path.join(matching_dir, '*.py'))
        # Filter out __pycache__ and only get actual wrapper files
        wrapper_files = [f for f in wrapper_files if os.path.basename(f) in 
                        ['nrf_ble_driver_sd_api_v2.py', 'nrf_ble_driver_sd_api_v5.py', '__init__.py']]
        
        if wrapper_files:
            print(f"Copying {len(wrapper_files)} Python wrapper file(s) to pc_ble_driver_py/lib/")
            for wrapper in wrapper_files:
                dest = os.path.join('pc_ble_driver_py/lib', os.path.basename(wrapper))
                shutil.copy2(wrapper, dest)
                print(f"  ✓ Copied {os.path.basename(wrapper)}")
        else:
            print("⚠️  No Python wrapper files found to copy")
        
        # CRITICAL: Final verification - ensure all .so files are for correct Python version
        final_so = glob.glob(os.path.join('pc_ble_driver_py/lib', '*.so'))
        if not final_so:
            print("✗ ERROR: No .so files in lib/ after build!")
            return 1
        
        # Verify all .so files are linked to correct Python version
        all_correct = True
        for so_file in final_so:
            if not verify_so_python_version(so_file, python_version):
                print(f"✗ ERROR: {os.path.basename(so_file)} is linked to wrong Python version!")
                all_correct = False
        
        if not all_correct:
            print("✗ ERROR: Some .so files are linked to wrong Python version - this will cause segfaults!")
            return 1
        
        print(f"✓ Build complete: {len(final_so)} .so file(s) verified for Python {python_version}")
    else:
        print(f"✗ ERROR: No build directory found for Python {python_version}")
        return 1
    
    # Install editable
    install_result = subprocess.run([
        sys.executable, '-m', 'pip', 'install', '-e', '.', '--no-build-isolation', '--no-deps'
    ])
    
    # Verify installation
    try:
        import pc_ble_driver_py
        lib_path = os.path.join(os.path.dirname(pc_ble_driver_py.__file__), 'lib')
        so_files = [f for f in os.listdir(lib_path) if f.endswith('.so')] if os.path.exists(lib_path) else []
        py_files = [f for f in os.listdir(lib_path) if f.endswith('.py') and 'nrf_ble_driver' in f] if os.path.exists(lib_path) else []
        if so_files and py_files:
            print(f"✓ Verified {len(so_files)} .so files and {len(py_files)} wrapper files accessible")
        else:
            print(f"⚠️  Warning: so_files={len(so_files)}, py_files={len(py_files)}")
    except Exception as e:
        print(f"⚠️  Warning: Could not verify installation: {e}")
    
    return install_result.returncode

if __name__ == '__main__':
    sys.exit(main())
