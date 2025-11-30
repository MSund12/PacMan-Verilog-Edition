#!/usr/bin/env python3
"""
ISSP Keyboard Control Script for PacMan FPGA Game
Sends WASD key commands via JTAG/ISSP to FPGA board
Uses Quartus System Console to write ISSP registers

SETUP INSTRUCTIONS:
1. Install Python dependencies:
   - pip install keyboard  (recommended, requires admin on Windows)
   - OR use built-in msvcrt (Windows only, less responsive)

2. Ensure Quartus Prime is installed and quartus_stp is in PATH
   - Or update QUARTUS_STP path in this script

3. Compile and program your FPGA with the updated design:
   - Open PacMan.qpf in Quartus Prime
   - Compile the project (Processing > Start Compilation)
   - Program the FPGA (Tools > Programmer)

4. Run this script:
   - python keyboard_control_issp.py

CONTROLS:
  W = Move Up
  S = Move Down
  A = Move Left
  D = Move Right
  Enter = Start Game
  Q or ESC = Quit
"""

import subprocess
import sys
import os
import time

# Try to import keyboard library (Windows-compatible)
try:
    import keyboard
    HAS_KEYBOARD = True
except ImportError:
    HAS_KEYBOARD = False
    try:
        import msvcrt
        HAS_MSVCRT = True
    except ImportError:
        HAS_MSVCRT = False

# Configuration
QUARTUS_STP = "quartus_stp"  # Quartus System Console executable
PROJECT_NAME = "PacMan"  # Your Quartus project name
ISSP_INSTANCE = "ISSP_CTRL"  # ISSP instance name from Verilog

# Control register bit mapping (5 bits total)
# Bit 0: move_up (W)
# Bit 1: move_down (S)
# Bit 2: move_left (A)
# Bit 3: move_right (D)
# Bit 4: start_game (Enter)

def get_quartus_path():
    """Try to find Quartus installation path"""
    # Common Quartus installation paths on Windows
    possible_paths = [
        r"C:\intelFPGA_lite\20.1\quartus\bin64\quartus_stp.exe",
        r"C:\altera\20.1\quartus\bin64\quartus_stp.exe",
        r"C:\intelFPGA\20.1\quartus\bin64\quartus_stp.exe",
    ]
    
    # Check if quartus_stp is in PATH
    try:
        result = subprocess.run(["where", "quartus_stp"], 
                              capture_output=True, text=True, shell=True)
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip().split('\n')[0]
    except:
        pass
    
    # Check common installation paths
    for path in possible_paths:
        if os.path.exists(path):
            return path
    
    return "quartus_stp"  # Fallback to assuming it's in PATH

def write_issp_value(value):
    """
    Write a value to ISSP register using Quartus System Console
    value: 5-bit integer (0-31) representing control register
    """
    quartus_stp = get_quartus_path()
    
    # Create TCL script to write ISSP value
    tcl_script = f"""
# Connect to device
set device_name [lindex [get_device_names] 0]
device_lock -timeout 10000
open_device -device_name $device_name -update_programming_file

# Access ISSP instance
set issp_instance [get_insystem_source_probe_instance_info -device_name $device_name -name "{ISSP_INSTANCE}"]

if {{$issp_instance != ""}} {{
    # Write value to ISSP source
    write_source_data -device_name $device_name -instance_index 0 -value_in_hex [format "%02X" {value}]
    puts "Wrote value {value} (0x[format %02X {value}]) to ISSP"
}} else {{
    puts "Error: ISSP instance '{ISSP_INSTANCE}' not found"
}}

# Close device
close_device
device_unlock
"""
    
    # Write TCL script to temporary file
    tcl_file = "issp_write_temp.tcl"
    try:
        with open(tcl_file, 'w') as f:
            f.write(tcl_script)
        
        # Execute Quartus System Console
        cmd = [quartus_stp, "-t", tcl_file]
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.getcwd())
        
        if result.returncode != 0:
            print(f"Warning: Quartus command returned error: {result.stderr}")
            return False
        
        return True
    except Exception as e:
        print(f"Error executing Quartus command: {e}")
        return False
    finally:
        # Clean up temporary TCL file
        if os.path.exists(tcl_file):
            try:
                os.remove(tcl_file)
            except:
                pass

def get_key_windows_msvcrt():
    """Get keypress using msvcrt (Windows, non-blocking)"""
    if msvcrt.kbhit():
        key = msvcrt.getch()
        if key == b'\x1b':  # ESC
            return 'q'
        elif key == b'w' or key == b'W':
            return 'w'
        elif key == b's' or key == b'S':
            return 's'
        elif key == b'a' or key == b'A':
            return 'a'
        elif key == b'd' or key == b'D':
            return 'd'
        elif key == b'\r':  # Enter
            return 'enter'
    return None

def main():
    print("PacMan ISSP Keyboard Control")
    print("=" * 40)
    print(f"Using Quartus System Console: {get_quartus_path()}")
    print(f"Project: {PROJECT_NAME}")
    print(f"ISSP Instance: {ISSP_INSTANCE}")
    print("\nControls:")
    print("  W = Move Up")
    print("  S = Move Down")
    print("  A = Move Left")
    print("  D = Move Right")
    print("  Enter = Start Game")
    print("  Q or ESC = Quit")
    print("\nConnecting to FPGA via JTAG...")
    
    # Initialize ISSP to 0
    if not write_issp_value(0):
        print("Warning: Could not initialize ISSP. Make sure:")
        print("1. FPGA board is connected via USB Blaster")
        print("2. Quartus Prime is installed and in PATH")
        print("3. Project has been compiled and programmed")
        print("4. ISSP instance name matches in Verilog code")
        response = input("\nContinue anyway? (y/n): ")
        if response.lower() != 'y':
            sys.exit(1)
    
    print("Connected! Press keys to control PacMan.\n")
    
    current_value = 0
    last_written_value = None
    
    try:
        if HAS_KEYBOARD:
            # Use keyboard library (better for Windows)
            print("Using keyboard library for input...")
            
            def on_key_event(event):
                nonlocal current_value, last_written_value
                key = event.name.lower()
                
                if key == 'q' or key == 'esc':
                    return False
                
                # Update control register bits
                if key == 'w':
                    current_value = current_value | 0x01  # Set bit 0
                elif key == 's':
                    current_value = current_value | 0x02  # Set bit 1
                elif key == 'a':
                    current_value = current_value | 0x04  # Set bit 2
                elif key == 'd':
                    current_value = current_value | 0x08  # Set bit 3
                elif key == 'enter':
                    current_value = current_value | 0x10  # Set bit 4
                
                # Write to ISSP only if value changed
                if current_value != last_written_value:
                    write_issp_value(current_value)
                    last_written_value = current_value
                    # Reset after a short delay to generate pulse
                    time.sleep(0.05)
                    current_value = 0
                    write_issp_value(0)
                    last_written_value = 0
                
                return True
            
            # Set up keyboard hooks
            keyboard.on_press_key('w', lambda e: on_key_event(e))
            keyboard.on_press_key('s', lambda e: on_key_event(e))
            keyboard.on_press_key('a', lambda e: on_key_event(e))
            keyboard.on_press_key('d', lambda e: on_key_event(e))
            keyboard.on_press_key('enter', lambda e: on_key_event(e))
            keyboard.on_press_key('q', lambda e: False)
            keyboard.on_press_key('esc', lambda e: False)
            
            # Wait for quit
            keyboard.wait('q')
            
        elif HAS_MSVCRT:
            # Use msvcrt (Windows built-in, less ideal)
            print("Using msvcrt for input (press keys repeatedly)...")
            
            while True:
                key = get_key_windows_msvcrt()
                
                if key == 'q':
                    break
                
                if key:
                    # Update control register based on key
                    if key == 'w':
                        write_issp_value(0x01)  # move_up
                        time.sleep(0.05)
                        write_issp_value(0x00)
                    elif key == 's':
                        write_issp_value(0x02)  # move_down
                        time.sleep(0.05)
                        write_issp_value(0x00)
                    elif key == 'a':
                        write_issp_value(0x04)  # move_left
                        time.sleep(0.05)
                        write_issp_value(0x00)
                    elif key == 'd':
                        write_issp_value(0x08)  # move_right
                        time.sleep(0.05)
                        write_issp_value(0x00)
                    elif key == 'enter':
                        write_issp_value(0x10)  # start_game
                        time.sleep(0.05)
                        write_issp_value(0x00)
                
                time.sleep(0.01)  # Small delay to prevent CPU spinning
        else:
            print("Error: No keyboard input library available.")
            print("Please install 'keyboard' library: pip install keyboard")
            print("Or use Windows with msvcrt support.")
            sys.exit(1)
    
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        # Reset ISSP to 0 on exit
        write_issp_value(0)
        print("\nDisconnected. Goodbye!")

if __name__ == '__main__':
    main()

