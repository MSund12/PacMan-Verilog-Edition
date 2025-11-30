# ISSP Write TCL Script
# Helper script to write values to ISSP control register via Quartus System Console
# Usage: quartus_stp -t issp_write.tcl -s value <hex_value>
#   or: quartus_stp -t issp_write.tcl
#       then call: write_issp <hex_value>

# Configuration - match these with your project
set PROJECT_NAME "PacMan"
set ISSP_INSTANCE_NAME "ISSP_CTRL"

# Function to write value to ISSP
proc write_issp {value} {
    global ISSP_INSTANCE_NAME
    
    # Get device name
    set device_name [lindex [get_device_names] 0]
    
    if {$device_name == ""} {
        puts "Error: No device found. Make sure FPGA is connected."
        return 1
    }
    
    puts "Connecting to device: $device_name"
    
    # Lock device
    device_lock -timeout 10000
    
    # Open device
    if {[catch {open_device -device_name $device_name -update_programming_file} result]} {
        puts "Error opening device: $result"
        device_unlock
        return 1
    }
    
    # Find ISSP instance
    set issp_instance [get_insystem_source_probe_instance_info -device_name $device_name -name $ISSP_INSTANCE_NAME]
    
    if {$issp_instance == ""} {
        puts "Error: ISSP instance '$ISSP_INSTANCE_NAME' not found."
        puts "Available instances:"
        foreach inst [get_insystem_source_probe_instance_info -device_name $device_name] {
            puts "  - $inst"
        }
        close_device
        device_unlock
        return 1
    }
    
    # Convert value to hex (ensure it's 2 digits)
    set hex_value [format "%02X" $value]
    
    # Write to ISSP source (instance_index 0 is the first ISSP instance)
    if {[catch {write_source_data -device_name $device_name -instance_index 0 -value_in_hex $hex_value} result]} {
        puts "Error writing to ISSP: $result"
        close_device
        device_unlock
        return 1
    }
    
    puts "Successfully wrote value $value (0x$hex_value) to ISSP instance '$ISSP_INSTANCE_NAME'"
    
    # Close device
    close_device
    device_unlock
    
    return 0
}

# If script is run with -s value argument, execute write_issp
if {[llength $::argv] >= 2 && [lindex $::argv 0] == "-s"} {
    set value [lindex $::argv 1]
    # Convert hex string to decimal if needed
    if {[string match "0x*" $value] || [string match "0X*" $value]} {
        set value [expr 0x[string range $value 2 end]]
    }
    write_issp $value
    exit
}

# Otherwise, just define the function for interactive use
puts "ISSP Write TCL Script loaded."
puts "Usage: write_issp <value>"
puts "Example: write_issp 0x01  (sets move_up bit)"
puts "Example: write_issp 0x08  (sets move_right bit)"
puts "Example: write_issp 0x00  (clears all bits)"

