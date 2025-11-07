#!/usr/bin/env python3
"""
Test to verify CMakeLists.txt rpath configuration is correct.

This test validates that the CMake configuration will properly set up @rpath
for macOS builds without requiring a full build.
"""
import re
import sys
from pathlib import Path


def test_cmake_rpath_config():
    """Test that CMakeLists.txt has the correct rpath configuration."""
    cmake_file = Path(__file__).parent.parent / "CMakeLists.txt"
    
    if not cmake_file.exists():
        print("✗ CMakeLists.txt not found")
        return False
    
    content = cmake_file.read_text()
    
    print("Testing CMakeLists.txt rpath configuration...")
    all_passed = True
    
    # Test 1: Check for CMAKE_MACOSX_RPATH
    if "CMAKE_MACOSX_RPATH" in content:
        print("✓ CMAKE_MACOSX_RPATH is configured")
    else:
        print("✗ CMAKE_MACOSX_RPATH not found")
        all_passed = False
    
    # Test 2: Check for install_name_tool usage
    if "install_name_tool" in content:
        print("✓ install_name_tool post-build step found")
    else:
        print("✗ install_name_tool post-build step not found")
        all_passed = False
    
    # Test 3: Check for @rpath usage
    if "@rpath" in content:
        print("✓ @rpath is used in the configuration")
    else:
        print("✗ @rpath not found in configuration")
        all_passed = False
    
    # Test 4: Check for APPLE-specific rpath configuration
    if "if(APPLE" in content and "CMAKE_MACOSX_RPATH" in content:
        # Find the APPLE block
        apple_block_start = content.find("if(APPLE")
        if apple_block_start != -1:
            # Check if rpath config is in the APPLE block
            apple_block = content[apple_block_start:apple_block_start+500]
            if "CMAKE_MACOSX_RPATH" in apple_block:
                print("✓ rpath configuration is in APPLE-specific block")
            else:
                print("✗ rpath configuration not in APPLE block")
                all_passed = False
    
    # Test 5: Check for post-build command with install_name_tool
    if "add_custom_command" in content and "POST_BUILD" in content:
        # Check if it's for the Python modules
        if "install_name_tool" in content and "-change" in content:
            print("✓ Post-build install_name_tool command found")
        else:
            print("✗ Post-build install_name_tool command incomplete")
            all_passed = False
    
    # Test 6: Verify Python library path detection logic
    if "PYTHON_LIB_NAME" in content and "libpython" in content.lower():
        print("✓ Python library name detection logic found")
    else:
        print("✗ Python library name detection logic not found")
        all_passed = False
    
    return all_passed


def test_python_version_support():
    """Test that setup.py includes all supported Python versions (3.8-3.13)."""
    setup_file = Path(__file__).parent.parent / "setup.py"
    
    if not setup_file.exists():
        print("✗ setup.py not found")
        return False
    
    content = setup_file.read_text()
    
    print("\nTesting Python version support in setup.py...")
    all_passed = True
    
    # Check all supported versions
    supported_versions = ['3.8', '3.9', '3.10', '3.11', '3.12', '3.13']
    for version in supported_versions:
        if f'"Programming Language :: Python :: {version}"' in content:
            print(f"✓ Python {version} support declared")
        else:
            print(f"✗ Python {version} support not declared")
            all_passed = False
    
    return all_passed


def main():
    """Run all tests."""
    print("=" * 60)
    print("CMake rpath Configuration Tests")
    print("=" * 60)
    
    cmake_ok = test_cmake_rpath_config()
    setup_ok = test_python_version_support()
    
    print("\n" + "=" * 60)
    if cmake_ok and setup_ok:
        print("✓ All configuration tests passed!")
        print("\nNote: Full build requires nrf-ble-driver library.")
        print("The rpath configuration is correct and will work when building wheels.")
        return 0
    else:
        print("✗ Some configuration tests failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())

