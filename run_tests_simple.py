#!/usr/bin/env python3
"""
Simple test runner that shows what each test does and runs them on all Python versions.
"""

import subprocess
import sys
import os
from pathlib import Path

# Test descriptions
TEST_DESCRIPTIONS = {
    'test_wheel_compatibility.py': {
        'description': 'Tests wheel compatibility: imports, @rpath usage, Python version compatibility',
        'requires_hardware': False,
    },
    'test_cmake_rpath_config.py': {
        'description': 'Verifies CMake rpath configuration is correct',
        'requires_hardware': False,
    },
    'test_pc_ble_driver_py.py': {
        'description': 'Tests basic package structure and imports',
        'requires_hardware': False,
    },
}

# Python versions to test
PYTHON_VERSIONS = {
    '3.8': ['/usr/local/bin/python3.8'] if os.path.exists('/usr/local/bin/python3.8') else [],
    '3.9': ['/usr/local/bin/python3.9'] if os.path.exists('/usr/local/bin/python3.9') else [],
    '3.10': ['/opt/homebrew/bin/python3.10', '/usr/local/bin/python3.10'],
    '3.11': ['/opt/homebrew/bin/python3.11', '/usr/local/bin/python3.11'],
    '3.12': ['/opt/homebrew/bin/python3.12', '/usr/local/bin/python3.12'],
    '3.13': ['/opt/homebrew/bin/python3.13', '/usr/local/bin/python3.13'],
}

def get_wheel_for_arch(arch):
    """Get appropriate wheel for architecture."""
    wheel_dir = Path('dist')
    if arch == 'arm64':
        wheels = list(wheel_dir.glob('*arm64*.whl'))
        if wheels:
            return str(wheels[0])
    elif arch == 'x86_64':
        wheels = list(wheel_dir.glob('*x86_64*.whl'))
        if wheels:
            return str(wheels[0])
    elif arch == 'universal':
        wheels = list(wheel_dir.glob('*universal2*.whl'))
        if wheels:
            return str(wheels[0])
    
    # Fallback
    wheels = list(wheel_dir.glob('*.whl'))
    if wheels:
        return str(wheels[0])
    return None

def check_python_arch(python_path):
    """Check Python architecture."""
    try:
        result = subprocess.run(['file', python_path], capture_output=True, text=True)
        if 'x86_64' in result.stdout and 'arm64' in result.stdout:
            return 'universal'
        elif 'arm64' in result.stdout:
            return 'arm64'
        elif 'x86_64' in result.stdout:
            return 'x86_64'
    except:
        pass
    return 'unknown'

def run_test(python_path, test_file, wheel_path=None, arch_mode='native'):
    """Run a test."""
    test_path = Path('tests') / test_file
    if not test_path.exists():
        return {'status': 'skipped', 'reason': 'Test file not found'}
    
    # Install wheel if provided
    if wheel_path and os.path.exists(wheel_path):
        try:
            cmd = [python_path, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', wheel_path]
            if arch_mode == 'x86_64':
                cmd = ['arch', '-x86_64'] + cmd
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if result.returncode != 0:
                return {'status': 'error', 'reason': f'Failed to install wheel: {result.stderr[:200]}'}
        except Exception as e:
            return {'status': 'error', 'reason': f'Error installing wheel: {e}'}
    
    # Run test
    cmd = [python_path, str(test_path)]
    if arch_mode == 'x86_64':
        cmd = ['arch', '-x86_64'] + cmd
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        return {
            'status': 'passed' if result.returncode == 0 else 'failed',
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }
    except subprocess.TimeoutExpired:
        return {'status': 'timeout', 'reason': 'Test timed out'}
    except Exception as e:
        return {'status': 'error', 'reason': str(e)}

def main():
    print("=" * 80)
    print("Test Runner - All Python Versions and Architectures")
    print("=" * 80)
    print()
    
    # Show test descriptions
    print("Test Descriptions:")
    print()
    for test_file, info in TEST_DESCRIPTIONS.items():
        print(f"  {test_file}:")
        print(f"    {info['description']}")
        print(f"    Requires hardware: {info['requires_hardware']}")
        print()
    
    # Find available Python versions
    available_pythons = {}
    for version, paths in PYTHON_VERSIONS.items():
        for path in paths:
            if os.path.exists(path):
                try:
                    result = subprocess.run([path, '--version'], capture_output=True, text=True, timeout=2)
                    if result.returncode == 0:
                        arch = check_python_arch(path)
                        key = f"{version}_{arch}"
                        if key not in available_pythons:
                            available_pythons[key] = []
                        available_pythons[key].append({
                            'path': path,
                            'arch': arch,
                            'version': result.stdout.strip()
                        })
                except:
                    pass
    
    if not available_pythons:
        print("❌ No Python versions found!")
        return 1
    
    print("=" * 80)
    print("Available Python Versions")
    print("=" * 80)
    for key, pythons in sorted(available_pythons.items()):
        for py_info in pythons:
            print(f"  {py_info['version']} ({py_info['arch']}): {py_info['path']}")
    print()
    
    # Run tests
    results = {}
    
    for key in sorted(available_pythons.keys()):
        pythons = available_pythons[key]
        for py_info in pythons:
            python_path = py_info['path']
            arch = py_info['arch']
            version_str = py_info['version']
            
            print("=" * 80)
            print(f"Testing: {version_str} ({arch})")
            print(f"Path: {python_path}")
            print("=" * 80)
            print()
            
            # Get wheel
            wheel_path = get_wheel_for_arch(arch)
            if wheel_path:
                print(f"Using wheel: {wheel_path}")
            else:
                print("⚠️  No wheel found")
            print()
            
            # Test native architecture
            version_results = {}
            for test_file in TEST_DESCRIPTIONS.keys():
                print(f"  Running {test_file}...")
                result = run_test(python_path, test_file, wheel_path, 'native')
                version_results[test_file] = result
                
                if result['status'] == 'passed':
                    print(f"    ✅ PASSED")
                elif result['status'] == 'failed':
                    print(f"    ❌ FAILED")
                    if result.get('stderr'):
                        error_lines = result['stderr'].split('\n')[:3]
                        for line in error_lines:
                            if line.strip():
                                print(f"       {line[:70]}")
                elif result['status'] == 'skipped':
                    print(f"    ⏭️  SKIPPED: {result.get('reason', 'Unknown')}")
                elif result['status'] == 'error':
                    print(f"    ⚠️  ERROR: {result.get('reason', 'Unknown')[:70]}")
                else:
                    print(f"    ⚠️  {result['status'].upper()}")
                print()
            
            # Test x86_64 mode if Python is universal
            if arch == 'universal':
                print(f"  Testing in x86_64 mode (Rosetta)...")
                print()
                for test_file in TEST_DESCRIPTIONS.keys():
                    print(f"  Running {test_file} (x86_64)...")
                    result = run_test(python_path, test_file, wheel_path, 'x86_64')
                    version_results[f"{test_file}_x86_64"] = result
                    
                    if result['status'] == 'passed':
                        print(f"    ✅ PASSED")
                    elif result['status'] == 'failed':
                        print(f"    ❌ FAILED")
                        if result.get('stderr'):
                            error_lines = result['stderr'].split('\n')[:3]
                            for line in error_lines:
                                if line.strip():
                                    print(f"       {line[:70]}")
                    elif result['status'] == 'skipped':
                        print(f"    ⏭️  SKIPPED: {result.get('reason', 'Unknown')}")
                    elif result['status'] == 'error':
                        print(f"    ⚠️  ERROR: {result.get('reason', 'Unknown')[:70]}")
                    else:
                        print(f"    ⚠️  {result['status'].upper()}")
                    print()
            
            results[f"{key}_{python_path}"] = version_results
            print()
    
    # Summary
    print("=" * 80)
    print("Summary")
    print("=" * 80)
    print()
    
    total = 0
    passed = 0
    failed = 0
    
    for key, test_results in results.items():
        print(f"{key}:")
        for test_name, result in test_results.items():
            total += 1
            if result['status'] == 'passed':
                passed += 1
                print(f"  ✅ {test_name}")
            else:
                failed += 1
                print(f"  ❌ {test_name}: {result['status']}")
        print()
    
    print(f"Total: {total} | Passed: {passed} | Failed: {failed}")
    print("=" * 80)
    
    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())

