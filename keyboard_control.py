#!/usr/bin/env python3
"""
Keyboard Control Script for PacMan FPGA Game
Sends WASD or Arrow key commands via UART to FPGA board
"""

import serial
import sys
import select
import termios
import tty

# Configuration
SERIAL_PORT = '/dev/ttyUSB0'  # Linux: /dev/ttyUSB0 or /dev/ttyACM0
                                # Windows: COM3, COM4, etc.
                                # macOS: /dev/cu.usbserial-*
BAUD_RATE = 115200

# Key mappings (ASCII)
KEY_MAP = {
    'w': b'W',  # Up
    'W': b'W',
    's': b'S',  # Down
    'S': b'S',
    'a': b'A',  # Left
    'A': b'A',
    'd': b'D',  # Right
    'D': b'D',
}

def get_key():
    """Get a single keypress from stdin (non-blocking)"""
    if select.select([sys.stdin], [], [], 0) == ([sys.stdin], [], []):
        return sys.stdin.read(1)
    return None

def main():
    print("PacMan Keyboard Control")
    print("=" * 40)
    print(f"Connecting to {SERIAL_PORT} at {BAUD_RATE} baud...")
    
    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.1)
        print(f"Connected! Press WASD keys to control PacMan.")
        print("Press 'q' to quit.\n")
    except serial.SerialException as e:
        print(f"Error: Could not open serial port: {e}")
        print("\nPlease check:")
        print("1. The FPGA board is connected via USB")
        print("2. The correct serial port (try /dev/ttyUSB0, /dev/ttyACM0, or COMx)")
        print("3. You have permission to access the serial port")
        print("\nTo find your serial port:")
        print("  Linux: ls /dev/ttyUSB* or ls /dev/ttyACM*")
        print("  Windows: Check Device Manager for COM ports")
        print("  macOS: ls /dev/cu.usbserial-*")
        sys.exit(1)
    
    # Save terminal settings
    old_settings = termios.tcgetattr(sys.stdin)
    try:
        # Set terminal to raw mode for single character input
        tty.setraw(sys.stdin.fileno())
        
        while True:
            key = get_key()
            if key:
                if key == 'q' or key == '\x03':  # 'q' or Ctrl+C
                    break
                
                # Check if it's an arrow key sequence
                if key == '\x1b':  # ESC sequence start
                    key2 = get_key()
                    if key2 == '[':
                        key3 = get_key()
                        if key3 == 'A':  # Up arrow
                            ser.write(b'W')
                            print("Sent: W (Up)")
                        elif key3 == 'B':  # Down arrow
                            ser.write(b'S')
                            print("Sent: S (Down)")
                        elif key3 == 'C':  # Right arrow
                            ser.write(b'D')
                            print("Sent: D (Right)")
                        elif key3 == 'D':  # Left arrow
                            ser.write(b'A')
                            print("Sent: A (Left)")
                elif key in KEY_MAP:
                    ser.write(KEY_MAP[key])
                    print(f"Sent: {KEY_MAP[key].decode()}")
    
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        # Restore terminal settings
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        ser.close()
        print("\nDisconnected. Goodbye!")

if __name__ == '__main__':
    main()

