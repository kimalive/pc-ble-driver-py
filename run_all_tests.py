#!/usr/bin/env python3
"""
Run tests on all supported Python versions and architectures.

This script:
1. Finds available Python versions (3.8-3.13)
2. Tests both arm64 and x86_64 architectures on Apple Silicon
3. Runs software-only tests (no hardware required)
4. Shows what each test does
"""

import subprocess
import sys
import os
import platform
from pathlib import Path
import tempfile
import json

# Supported Python versions
SUPPORTED_VERSIONS = ['3.8', '3.9', '3.10', '3.11', '3.12', '3.13']

# Test files that don't require hardware
SOFTWARE_TESTS = [
    'test_wheel_compatibility.py',
    'test_cmake_rpath_config.py',
    'test_pc_ble_driver_py.py',
]

# Test files that require hardware (will be skipped)
HARDWARE_TESTS = [
    'test_driver_open_close.py',
    'test_programming.py',
    'test_ble_common_api.py',
    'test_rssi.py',
    'test_connection_update.py',
    'test_mtu.py',
    'test_data_length.py',
    'test_server_client.py',
    'test_passkey.py',
    'test_lesc_security.py',
    'test_phy_update.py',
]

def find_python_versions():
    """Find available Python versions."""
    versions = {}
    
    # Check Homebrew Python
    for version in SUPPORTED_VERSIONS:
        for base in ['/opt/homebrew/bin', '/usr/local/bin']:
            python_path = f'{base}/python{version}'
            if os.path.exists(python_path):
                try:
                    result = subprocess.run(
                        [python_path, '--version'],
                        capture_output=True,
                        text=True,
                        timeout=2
                    )
                    if result.returncode == 0:
                        # Check architecture
                        arch_result = subprocess.run(
                            ['file', python_path],
                            capture_output=True,
                            text=True
                        )
                        arch = 'arm64'
                        if 'x86_64' in arch_result.stdout and 'arm64' in arch_result.stdout:
                            arch = 'universal'
                        elif 'x86_64' in arch_result.stdout:
                            arch = 'x86_64'
                        
                        if version not in versions:
                            versions[version] = []
                        versions[version].append({
                            'path': python_path,
                            'arch': arch,
                            'version_string': result.stdout.strip()
                        })
                except:
                    pass
    
    # Check system Python
    if os.path.exists('/usr/bin/python3'):
        try:
            result = subprocess.run(
                ['/usr/bin/python3', '--version'],
                capture_output=True,
                text=True,
                timeout=2
            )
            if result.returncode == 0:
                version_match = result.stdout.strip().split()[1]
                major_minor = '.'.join(version_match.split('.')[:2])
                if major_minor in SUPPORTED_VERSIONS:
                    arch_result = subprocess.run(
                        ['file', '/usr/bin/python3'],
                        capture_output=True,
                        text=True
                    )
                    arch = 'universal' if 'universal' in arch_result.stdout else 'arm64'
                    if major_minor not in versions:
                        versions[major_minor] = []
                    versions[major_minor].append({
                        'path': '/usr/bin/python3',
                        'arch': arch,
                        'version_string': result.stdout.strip()
                    })
        except:
            pass
    
    return versions

def get_wheel_path(arch):
    """Get the appropriate wheel path for the architecture."""
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
    
    # Fallback to any wheel
    wheels = list(wheel_dir.glob('*.whl'))
    if wheels:
        return str(wheels[0])
    return None

def run_test(python_path, test_file, wheel_path=None, arch='native'):
    """Run a test file with the specified Python."""
    test_path = Path('tests') / test_file
    if not test_path.exists():
        return {'status': 'skipped', 'reason': f'Test file not found: {test_file}'}
    
    cmd = [python_path, str(test_path)]
    
    # Install wheel if provided
    if wheel_path and os.path.exists(wheel_path):
        try:
            install_cmd = [python_path, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', wheel_path]
            result = subprocess.run(
                install_cmd,
                capture_output=True,
                text=True,
                timeout=60
            )
            if result.returncode != 0:
                return {'status': 'error', 'reason': f'Failed to install wheel: {result.stderr}'}
        except subprocess.TimeoutExpired:
            return {'status': 'error', 'reason': 'Wheel installation timed out'}
        except Exception as e:
            return {'status': 'error', 'reason': f'Error installing wheel: {e}'}
    
    # Run test
    try:
        env = os.environ.copy()
        if arch == 'x86_64':
            # Force x86_64 mode
            result = subprocess.run(
                ['arch', '-x86_64'] + cmd,
                capture_output=True,
                text=True,
                timeout=120,
                env=env
            )
        else:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=120,
                env=env
            )
        
        return {
            'status': 'passed' if result.returncode == 0 else 'failed',
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr
        }
    except subprocess.TimeoutExpired:
        return {'status': 'timeout', 'reason': 'Test timed out after 120 seconds'}
    except Exception as e:
        return {'status': 'error', 'reason': str(e)}

def main():
    print("=" * 80)
    print("Running Tests on All Python Versions and Architectures")
    print("=" * 80)
    print()
    
    # Find Python versions
    print("Finding available Python versions...")
    versions = find_python_versions()
    
    if not versions:
        print("❌ No supported Python versions found!")
        return 1
    
    print(f"✓ Found Python versions: {', '.join(sorted(versions.keys()))}")
    print()
    
    # Show test descriptions
    print("=" * 80)
    print("Test Descriptions")
    print("=" * 80)
    print()
    print("Software-only tests (will be run):")
    for test in SOFTWARE_TESTS:
        print(f"  • {test}")
    print()
    print("Hardware-required tests (will be skipped):")
    for test in HARDWARE_TESTS:
        print(f"  • {test}")
    print()
    
    # Run tests
    results = {}
    
    for version in sorted(versions.keys()):
        print("=" * 80)
        print(f"Testing Python {version}")
        print("=" * 80)
        print()
        
        for python_info in versions[version]:
            python_path = python_info['path']
            arch = python_info['arch']
            version_str = python_info['version_string']
            
            print(f"\n{'─' * 80}")
            print(f"Python: {version_str}")
            print(f"Path: {python_path}")
            print(f"Architecture: {arch}")
            print(f"{'─' * 80}")
            
            # Get appropriate wheel
            wheel_path = get_wheel_path(arch)
            if wheel_path:
                print(f"Using wheel: {wheel_path}")
            else:
                print("⚠️  No wheel found - tests may fail if package not installed")
            
            # Test native architecture
            print(f"\n📋 Running tests in {arch} mode...")
            version_results = {}
            
            for test_file in SOFTWARE_TESTS:
                print(f"\n  Testing {test_file}...")
                result = run_test(python_path, test_file, wheel_path, arch='native')
                version_results[test_file] = result
                
                if result['status'] == 'passed':
                    print(f"    ✅ PASSED")
                elif result['status'] == 'failed':
                    print(f"    ❌ FAILED (return code: {result.get('returncode', 'N/A')})")
                    if result.get('stderr'):
                        print(f"    Error: {result['stderr'][:200]}")
                elif result['status'] == 'skipped':
                    print(f"    ⏭️  SKIPPED: {result.get('reason', 'Unknown reason')}")
                elif result['status'] == 'error':
                    print(f"    ⚠️  ERROR: {result.get('reason', 'Unknown error')}")
                elif result['status'] == 'timeout':
                    print(f"    ⏱️  TIMEOUT: {result.get('reason', 'Test timed out')}")
            
            # Test x86_64 mode if on Apple Silicon
            if platform.machine() == 'arm64' and arch in ['arm64', 'universal']:
                print(f"\n📋 Running tests in x86_64 mode (Rosetta)...")
                for test_file in SOFTWARE_TESTS:
                    print(f"\n  Testing {test_file} (x86_64)...")
                    result = run_test(python_path, test_file, wheel_path, arch='x86_64')
                    version_results[f"{test_file}_x86_64"] = result
                    
                    if result['status'] == 'passed':
                        print(f"    ✅ PASSED")
                    elif result['status'] == 'failed':
                        print(f"    ❌ FAILED (return code: {result.get('returncode', 'N/A')})")
                        if result.get('stderr'):
                            print(f"    Error: {result['stderr'][:200]}")
                    elif result['status'] == 'skipped':
                        print(f"    ⏭️  SKIPPED: {result.get('reason', 'Unknown reason')}")
                    elif result['status'] == 'error':
                        print(f"    ⚠️  ERROR: {result.get('reason', 'Unknown error')}")
                    elif result['status'] == 'timeout':
                        print(f"    ⏱️  TIMEOUT: {result.get('reason', 'Test timed out')}")
            
            results[f"{version}_{arch}"] = version_results
            print()
    
    # Summary
    print("=" * 80)
    print("Test Summary")
    print("=" * 80)
    print()
    
    total_tests = 0
    passed_tests = 0
    failed_tests = 0
    skipped_tests = 0
    
    for key, version_results in results.items():
        print(f"\n{key}:")
        for test_name, result in version_results.items():
            total_tests += 1
            status = result['status']
            if status == 'passed':
                passed_tests += 1
                print(f"  ✅ {test_name}")
            elif status == 'failed':
                failed_tests += 1
                print(f"  ❌ {test_name}")
            elif status == 'skipped':
                skipped_tests += 1
                print(f"  ⏭️  {test_name}")
            else:
                print(f"  ⚠️  {test_name}: {status}")
    
    print()
    print("=" * 80)
    print(f"Total: {total_tests} | Passed: {passed_tests} | Failed: {failed_tests} | Skipped: {skipped_tests}")
    print("=" * 80)
    
    return 0 if failed_tests == 0 else 1

if __name__ == '__main__':
    sys.exit(main())

