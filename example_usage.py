#!/usr/bin/env python3
"""
Simple example showing how to use pc-ble-driver-py in your own project.

This demonstrates the basic setup and initialization.
"""

import sys
from pc_ble_driver_py import config
from pc_ble_driver_py.ble_driver import BLEDriver, BLEEnableParams
from pc_ble_driver_py.observers import BLEDriverObserver


class SimpleBLEObserver(BLEDriverObserver):
    """Simple observer to handle BLE events."""
    
    def on_gap_evt(self, ble_driver, event):
        """Handle GAP (Generic Access Profile) events."""
        print(f"GAP Event: {event.evt_id}")
        # Add your event handling logic here
    
    def on_gattc_evt(self, ble_driver, conn_handle, gattc_evt):
        """Handle GATT Client events."""
        print(f"GATT Client Event: {gattc_evt.evt_id}")
        # Add your GATT client handling logic here
    
    def on_gatts_evt(self, ble_driver, conn_handle, gatts_evt):
        """Handle GATT Server events."""
        print(f"GATT Server Event: {gatts_evt.evt_id}")
        # Add your GATT server handling logic here


def main():
    """Main application entry point."""
    
    # Step 1: Configure for your chip (NRF51 or NRF52)
    config.__conn_ic_id__ = 'NRF52'  # Change to 'NRF51' if using nRF51
    
    # Step 2: Set up serial port
    # On macOS/Linux, this might be something like:
    #   '/dev/tty.usbmodem*' or '/dev/ttyACM0'
    # On Windows, this might be:
    #   'COM3' or 'COM4'
    serial_port = '/dev/tty.usbmodem*'  # Update this to match your device
    baud_rate = 1000000
    
    print(f"Initializing BLE driver on {serial_port}...")
    
    try:
        # Step 3: Create driver instance
        driver = BLEDriver(serial_port=serial_port, baud_rate=baud_rate)
        
        # Step 4: Create and add observer
        observer = SimpleBLEObserver()
        driver.observers_add(observer)
        
        # Step 5: Enable BLE stack
        enable_params = BLEEnableParams(
            vs_uuid_count=1,
            service_changed=0,
            periph_conn_count=0,      # Number of peripheral connections
            central_conn_count=1,      # Number of central connections
            central_sec_count=0,
            max_conn_event_length=0xFFFF,
            max_conn_event_length_conn=0xFFFF
        )
        
        print("Enabling BLE stack...")
        driver.ble_enable(enable_params)
        print("BLE stack enabled successfully!")
        
        # Step 6: Your application logic here
        # For example:
        # - Scan for devices
        # - Connect to a device
        # - Read/write characteristics
        # - etc.
        
        print("\nBLE driver is ready. Add your application logic here.")
        print("Press Ctrl+C to exit...")
        
        # Keep the program running (in a real app, you'd have your event loop here)
        try:
            import time
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nShutting down...")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    
    finally:
        # Step 7: Clean up
        try:
            driver.close()
            print("Driver closed.")
        except:
            pass


if __name__ == '__main__':
    main()

