#!/usr/bin/env python3
"""
Wrapper script to automatically detect and use available hardware for tests.
Used by tox to conditionally run hardware tests with automatic port detection.

This script:
1. Automatically detects available Nordic serial ports
2. Uses the first available port(s) for testing
3. Falls back to environment variables if provided
4. Skips gracefully if no hardware is found
"""
import os
import sys
import subprocess
from pathlib import Path

def find_available_ports():
    """
    Automatically detect available Nordic serial ports.
    Returns list of port strings, or empty list if none found.
    """
    try:
        # Set config before importing BLEDriver
        from pc_ble_driver_py import config
        nrf_family = os.getenv('NRF_FAMILY', 'NRF52')
        config.__conn_ic_id__ = nrf_family
        print(f"  Configuring for {nrf_family}...")
        
        from pc_ble_driver_py.ble_driver import BLEDriver
        
        print("  Enumerating serial ports...")
        ports = BLEDriver.enum_serial_ports()
        if not ports:
            print("  No ports found")
            return []
        
        # Return list of port strings
        port_list = [p.port for p in ports]
        print(f"  Found {len(port_list)} port(s)")
        return port_list
    except ImportError as e:
        print(f"Warning: Could not import pc_ble_driver_py: {e}")
        print("  Make sure the package is installed (pip install -e .)")
        return []
    except Exception as e:
        print(f"Warning: Could not enumerate serial ports: {e}")
        import traceback
        traceback.print_exc()
        return []

def main():
    print("=" * 60)
    print("Hardware Test Auto-Detection")
    print("=" * 60)
    
    # Check if ports are explicitly provided via environment
    port_a = os.getenv('PORT_A')
    port_b = os.getenv('PORT_B')
    
    # If not provided, try to auto-detect
    if not port_a or not port_b:
        print("\nAuto-detecting available hardware...")
        available_ports = find_available_ports()
        
        if not available_ports:
            print("\n❌ Hardware test skipped (no Nordic devices found)")
            print("  To run manually, set PORT_A and PORT_B environment variables")
            print("  Example: PORT_A=/dev/tty.usbmodem* tox -e py312")
            return 0
        
        print(f"\n✅ Found {len(available_ports)} Nordic device(s):")
        for i, port in enumerate(available_ports):
            print(f"  {i+1}. {port}")
        
        # Use first port for both if only one device, or use first two if multiple
        # Note: test_driver_open_close.py only needs one port, but Settings requires both
        if not port_a:
            port_a = available_ports[0]
            print(f"\nUsing {port_a} for PORT_A")
        
        if not port_b:
            if len(available_ports) > 1:
                port_b = available_ports[1]
                print(f"Using {port_b} for PORT_B")
            else:
                # Use same port for both (test only needs one)
                port_b = available_ports[0]
                print(f"Using {port_b} for PORT_B (same as PORT_A - only one device available)")
    else:
        print(f"\nUsing provided ports: PORT_A={port_a}, PORT_B={port_b}")
    
    # Get test script path
    test_script = Path(__file__).parent / 'test_driver_open_close.py'
    if not test_script.exists():
        print(f"\n❌ Test script not found: {test_script}")
        return 1
    
    # Build command with all required arguments
    nrf_family = os.getenv('NRF_FAMILY', 'NRF52')
    iterations = os.getenv('ITERATIONS', '1')
    log_level = os.getenv('LOG_LEVEL', 'info')
    driver_log_level = os.getenv('DRIVER_LOG_LEVEL', 'info')
    
    cmd = [
        sys.executable,
        str(test_script),
        '--port-a', port_a,
        '--port-b', port_b,
        '--nrf-family', nrf_family,
        '--iterations', iterations,
        '--log-level', log_level,
        '--driver-log-level', driver_log_level,
    ]
    
    print(f"\n" + "=" * 60)
    print("Running Hardware Test")
    print("=" * 60)
    print(f"  Test: {test_script.name}")
    print(f"  PORT_A: {port_a}")
    print(f"  PORT_B: {port_b}")
    print(f"  NRF_FAMILY: {nrf_family}")
    print(f"  Iterations: {iterations}")
    print(f"  Log Level: {log_level}")
    print(f"  Driver Log Level: {driver_log_level}")
    print("=" * 60)
    print()
    
    # Run test
    result = subprocess.run(cmd, cwd=Path(__file__).parent)
    
    if result.returncode == 0:
        print("\n✅ Hardware test passed!")
    else:
        print(f"\n❌ Hardware test failed with exit code {result.returncode}")
    
    return result.returncode

if __name__ == '__main__':
    sys.exit(main())

