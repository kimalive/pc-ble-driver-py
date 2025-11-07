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

def main():
    # Check if we should use wheels
    # Default: Use wheels for Python 3.12 (has import issues with source build)
    # For other versions, build from source by default
    default_use_wheels = 'true' if sys.version_info[:2] == (3, 12) else 'false'
    use_wheels = os.getenv('TOX_USE_WHEELS', default_use_wheels).lower() == 'true'
    
    if use_wheels:
        wheel = find_wheel()
        if wheel:
            print(f"Installing wheel: {os.path.basename(wheel)}")
            result = subprocess.run([
                sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', wheel
            ])
            if result.returncode == 0:
                print(f"✓ Successfully installed wheel")
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
    python_version = f"{sys.version_info.major}.{sys.version_info.minor}"
    
    # CRITICAL: Clean old .so files first to prevent using wrong Python version's libraries
    lib_dir = 'pc_ble_driver_py/lib'
    if os.path.exists(lib_dir):
        old_so_files = glob.glob(os.path.join(lib_dir, '*.so'))
        if old_so_files:
            print(f"Cleaning {len(old_so_files)} old .so file(s) to prevent version mismatch...")
            for old_so in old_so_files:
                os.remove(old_so)
                print(f"  Removed {os.path.basename(old_so)}")
        # Also clean old Python wrapper files
        old_py_files = [f for f in glob.glob(os.path.join(lib_dir, '*.py')) 
                       if os.path.basename(f) in ['nrf_ble_driver_sd_api_v2.py', 'nrf_ble_driver_sd_api_v5.py', '__init__.py']]
        if old_py_files:
            print(f"Cleaning {len(old_py_files)} old Python wrapper file(s)...")
            for old_py in old_py_files:
                os.remove(old_py)
                print(f"  Removed {os.path.basename(old_py)}")
    
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
        # Copy .so files
        so_files = glob.glob(os.path.join(matching_dir, '*.so'))
        if so_files:
            print(f"Copying {len(so_files)} .so file(s) to pc_ble_driver_py/lib/")
            for so_file in so_files:
                shutil.copy2(so_file, 'pc_ble_driver_py/lib/')
                print(f"  Copied {os.path.basename(so_file)}")
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
                print(f"  Copied {os.path.basename(wrapper)}")
        else:
            print("⚠️  No Python wrapper files found to copy")
    else:
        print("⚠️  No build directory found")
    
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
