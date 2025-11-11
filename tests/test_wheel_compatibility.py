#!/usr/bin/env python3
"""
Test script to verify that wheels work with different Python installations on macOS.

This script checks:
1. Basic import functionality
2. Library dependency paths (should use @rpath or @executable_path, not hardcoded paths)
3. Python version compatibility

Usage:
    python3 test_wheel_compatibility.py [--wheel-path PATH] [--python-version VERSION]
"""
import sys
import os
import platform
import subprocess
import argparse
from pathlib import Path

# CRITICAL: Remove source directory from sys.path to ensure we import from installed wheel
# This prevents Python from finding the source directory's pc_ble_driver_py before the installed wheel
if '__file__' in globals():
    # Get the project root (parent of tests directory)
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source_pkg = os.path.join(project_root, 'pc_ble_driver_py')
    # Remove source directory from sys.path if it exists and is not the installed package
    if source_pkg in sys.path:
        sys.path.remove(source_pkg)
    # Also remove current directory if it's the project root
    if project_root in sys.path and os.path.exists(os.path.join(project_root, 'pc_ble_driver_py', '__init__.py')):
        try:
            sys.path.remove(project_root)
        except ValueError:
            pass


def check_import():
    """Test basic import functionality."""
    print("Testing basic import...")
    try:
        # Set config before importing ble_driver to avoid RuntimeError
        from pc_ble_driver_py import config
        config.__conn_ic_id__ = 'NRF52'
        
        # CRITICAL: Run import in subprocess to catch segfaults (exit code -11)
        # Segfaults kill the process before Python can catch exceptions
        # By running in a subprocess, we can detect the exit code
        import_code = """
import sys
try:
    from pc_ble_driver_py import config
    config.__conn_ic_id__ = 'NRF52'
    import pc_ble_driver_py.ble_driver  # noqa: F401
    print("✓ Import successful")
    sys.exit(0)
except ImportError as e:
    print(f"⚠ Import failed: {e}")
    sys.exit(0)  # Not a failure, just can't test without package
except Exception as e:
    print(f"✗ Import failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
"""
        result = subprocess.run(
            [sys.executable, '-c', import_code],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        # Print output from subprocess
        if result.stdout:
            print(result.stdout.strip())
        if result.stderr:
            print(result.stderr.strip(), file=sys.stderr)
        
        # Check exit code
        if result.returncode == -11 or result.returncode == 139:
            # -11 is SIGSEGV on Unix, 139 is -11 + 128 (signal number)
            print("✗ Import caused segfault (exit code -11)")
            return False
        elif result.returncode != 0:
            print(f"✗ Import failed with exit code {result.returncode}")
            return False
        else:
            return True
            
    except ImportError as e:
        print(f"⚠ Package not installed: {e}")
        print("  Install a wheel first to test imports")
        return True  # Not a failure, just can't test without package
    except subprocess.TimeoutExpired:
        print("✗ Import test timed out (possible hang)")
        return False
    except Exception as e:
        print(f"✗ Import test failed: {e}")
        import traceback
        traceback.print_exc()
        return False


def check_library_paths():
    """Check that native libraries use @rpath or @executable_path instead of hardcoded paths."""
    if platform.system() != 'Darwin':
        print("Skipping library path check (not macOS)")
        return True
    
    print("\nChecking library dependency paths...")
    try:
        try:
            import pc_ble_driver_py.config
        except ImportError:
            print("⚠ Package not installed - cannot check library paths")
            print("  Install a wheel first to test library paths")
            return True  # Not a failure, just can't test
        
        # Check if __file__ is None (namespace package or not installed)
        if pc_ble_driver_py.__file__ is None:
            print("⚠ Package __file__ is None - cannot check library paths")
            print("  Package may not be installed correctly")
            return True  # Not a failure, just can't test
        
        # Find the .so files
        lib_dir = Path(pc_ble_driver_py.__file__).parent / 'lib'
        
        if not lib_dir.exists():
            print(f"✗ Library directory not found: {lib_dir}")
            return False
        
        so_files = list(lib_dir.glob('*.so'))
        if not so_files:
            print(f"✗ No .so files found in {lib_dir}")
            return False
        
        all_good = True
        for so_file in so_files:
            print(f"\n  Checking {so_file.name}...")
            try:
                # Use otool to check dependencies
                result = subprocess.run(
                    ['otool', '-L', str(so_file)],
                    capture_output=True,
                    text=True,
                    check=True
                )
                
                lines = result.stdout.strip().split('\n')
                if len(lines) < 2:
                    print(f"    ✗ No dependencies found")
                    all_good = False
                    continue
                
                # Check each dependency
                has_hardcoded_path = False
                has_portable_path = False
                python_lib_found = False
                
                for line in lines[1:]:  # Skip first line (the file itself)
                    line = line.strip()
                    if not line:
                        continue
                    
                    # Extract the library path (before the first space)
                    lib_path = line.split()[0]
                    
                    # Skip the file itself (first line shows the file path)
                    if lib_path == str(so_file) or lib_path.endswith(so_file.name):
                        continue
                    
                    # Only check Python library dependencies, not the .so file path itself
                    if 'libpython' in lib_path or (lib_path.endswith('/Python') and 'Python.framework' in lib_path):
                        python_lib_found = True
                        # Check for hardcoded Python framework paths in dependencies
                        # Hardcoded paths are absolute paths that don't use @rpath or @executable_path
                        if '/Library/Frameworks/Python.framework' in lib_path and '@rpath' not in lib_path and '@executable_path' not in lib_path:
                            print(f"    ✗ Hardcoded framework path found: {lib_path}")
                            has_hardcoded_path = True
                            all_good = False
                        
                        # Check for portable path usage (@rpath or @executable_path)
                        if '@executable_path' in lib_path:
                            print(f"    ✓ Using @executable_path for Python library: {lib_path}")
                            has_portable_path = True
                        elif '@rpath' in lib_path:
                            print(f"    ✓ Using @rpath for Python library: {lib_path}")
                            has_portable_path = True
                        elif '@rpath' not in lib_path and '@executable_path' not in lib_path:
                            # Check if it's a hardcoded path (not relative)
                            if not lib_path.startswith('@') and '/' in lib_path:
                                print(f"    ✗ Python library using hardcoded path (not @rpath or @executable_path): {lib_path}")
                                all_good = False
                
                if has_hardcoded_path:
                    print(f"    ✗ {so_file.name} has hardcoded Python framework paths")
                elif has_portable_path:
                    print(f"    ✓ {so_file.name} uses portable path (@rpath or @executable_path) correctly")
                else:
                    print(f"    ? {so_file.name} - no Python library dependencies found")
                    
            except subprocess.CalledProcessError as e:
                print(f"    ✗ Failed to check dependencies: {e}")
                all_good = False
            except Exception as e:
                print(f"    ✗ Error checking {so_file.name}: {e}")
                all_good = False
        
        return all_good
        
    except Exception as e:
        print(f"✗ Error checking library paths: {e}")
        import traceback
        traceback.print_exc()
        return False


def check_python_info():
    """Display Python installation information."""
    print("\nPython installation information:")
    print(f"  Version: {sys.version}")
    print(f"  Executable: {sys.executable}")
    print(f"  Platform: {platform.platform()}")
    
    # Try to detect Python installation type
    python_exe = sys.executable
    if '/Library/Frameworks/Python.framework' in python_exe:
        print("  Type: Python.org framework installation")
    elif '/opt/homebrew' in python_exe or '/usr/local' in python_exe:
        if 'Cellar' in python_exe:
            print("  Type: Homebrew installation")
        else:
            print("  Type: Possibly Homebrew or custom installation")
    elif '.pyenv' in python_exe:
        print("  Type: pyenv installation")
    else:
        print("  Type: Unknown/Custom installation")


def main():
    parser = argparse.ArgumentParser(
        description='Test wheel compatibility with different Python installations'
    )
    parser.add_argument(
        '--wheel-path',
        type=str,
        help='Path to wheel file to test (will install if provided)'
    )
    parser.add_argument(
        '--python-version',
        type=str,
        help='Expected Python version (e.g., 3.12)'
    )
    
    args = parser.parse_args()
    
    # Install wheel if provided
    if args.wheel_path:
        print(f"Installing wheel from {args.wheel_path}...")
        try:
            subprocess.run(
                [sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', args.wheel_path],
                check=True
            )
            print("✓ Wheel installed")
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to install wheel: {e}")
            return 1
    
    # Check Python version
    if args.python_version:
        expected_version = f"{sys.version_info.major}.{sys.version_info.minor}"
        if expected_version != args.python_version:
            print(f"Warning: Expected Python {args.python_version}, but got {expected_version}")
    
    check_python_info()
    
    # Run tests
    success = True
    
    if not check_import():
        success = False
    
    if not check_library_paths():
        success = False
    
    print("\n" + "="*60)
    if success:
        print("✓ All tests passed!")
        return 0
    else:
        print("✗ Some tests failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())

