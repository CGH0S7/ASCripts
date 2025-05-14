#!/bin/bash

# cpu_governor_control.sh - Script to control CPU governor on local or remote nodes
# Usage: ./cpu_governor_control.sh [NODE_LIST] <CPU_CORES> <GOVERNOR>
# Example: ./cpu_governor_control.sh "{1,3-5,7}" powersave
#          ./cpu_governor_control.sh node0 "{1,3-5}" performance
#          ./cpu_governor_control.sh "{node0,node1}" all ondemand

# Function to display usage information
usage() {
    echo "Usage: $0 [NODE_LIST] <CPU_CORES> <GOVERNOR>"
    echo "  NODE_LIST: (Optional) Specify target nodes using names, ranges, or combinations in braces."
    echo "             Examples: node0, {node0,node1}, {node0-node2}"
    echo "             If not provided, commands run on local machine."
    echo "  CPU_CORES: Specify cores using numbers, ranges, or combinations in braces, or 'all'"
    echo "             Examples: 1, {1,2}, {1,3-5}, {1-4,6,8-10}, all"
    echo "  GOVERNOR:  CPU governor to set"
    echo "             Common values: performance, powersave, ondemand, conservative, schedutil"
    echo ""
    echo "Example: $0 \"{1,3-5}\" powersave               - Sets cores 1, 3, 4, and 5 to powersave mode on local machine"
    echo "         $0 node0 \"{1,3-5}\" performance       - Sets cores on specific node to performance mode"
    echo "         $0 \"{node0,node1}\" all ondemand      - Sets all cores on multiple nodes to ondemand mode"
    exit 1
}

# Function to check if cpupower is available
check_cpupower() {
    if ! command -v cpupower &> /dev/null; then
        echo "Warning: cpupower command not found. Falling back to sysfs interface."
        return 1
    fi
    return 0
}

# Function to expand the node list
expand_node_list() {
    local node_spec=$1
    local expanded_list=""
    
    # Strip outer braces if present
    node_spec=${node_spec#\{}
    node_spec=${node_spec%\}}
    
    # Split by comma
    IFS=',' read -ra SEGMENTS <<< "$node_spec"
    
    for segment in "${SEGMENTS[@]}"; do
        if [[ $segment =~ ^([^-]+)-([^-]+)$ ]]; then
            # This is a range, extract prefix and number parts
            prefix="${BASH_REMATCH[1]%[0-9]*}"
            start="${BASH_REMATCH[1]#$prefix}"
            end="${BASH_REMATCH[2]#$prefix}"
            
            # Check if start and end are numeric
            if [[ "$start" =~ ^[0-9]+$ ]] && [[ "$end" =~ ^[0-9]+$ ]]; then
                for ((i=start; i<=end; i++)); do
                    expanded_list="$expanded_list $prefix$i"
                done
            else
                # If not numeric range, treat as single node
                expanded_list="$expanded_list $segment"
            fi
        else
            # This is a single node
            expanded_list="$expanded_list $segment"
        fi
    done
    
    echo "$expanded_list"
}

# Expand the CPU core list
expand_cpu_list() {
    local cpu_spec=$1
    local expanded_list=""
    
    # If "all", get all available CPUs
    if [[ "$cpu_spec" == "all" ]]; then
        # Get the number of CPU cores
        cpu_count=$(nproc --all)
        expanded_list=$(seq -s ' ' 0 $((cpu_count-1)))
        echo "$expanded_list"
        return
    fi
    
    # Strip outer braces if present
    cpu_spec=${cpu_spec#\{}
    cpu_spec=${cpu_spec%\}}
    
    # Split by comma
    IFS=',' read -ra SEGMENTS <<< "$cpu_spec"
    
    for segment in "${SEGMENTS[@]}"; do
        if [[ $segment =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # This is a range
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            
            for ((i=start; i<=end; i++)); do
                expanded_list="$expanded_list $i"
            done
        else
            # This is a single number
            expanded_list="$expanded_list $segment"
        fi
    done
    
    echo "$expanded_list"
}

# Function to execute a command on a remote node
execute_on_node() {
    local node=$1
    local command=$2
    
    # Check if it's the local machine
    if [[ "$node" == "localhost" ]]; then
        eval "$command"
    else
        # Execute via SSH
        ssh "$node" "$command"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to execute command on node $node"
            return 1
        fi
    fi
    return 0
}

# Function to validate if a governor is available
validate_governor() {
    local node=$1
    local core=$2
    local governor=$3
    
    # Command to check if the governor is available
    local cmd="if [ -f /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_available_governors ]; then "
    cmd+="grep -q \"$governor\" /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_available_governors; "
    cmd+="if [ \$? -eq 0 ]; then echo 'valid'; else echo 'invalid'; fi; "
    cmd+="else echo 'unknown'; fi"
    
    # Execute the command
    result=$(execute_on_node "$node" "$cmd")
    
    if [[ "$result" == "valid" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to list available governors for a CPU core
list_available_governors() {
    local node=$1
    local core=$2
    
    # Command to list available governors
    local cmd="if [ -f /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_available_governors ]; then "
    cmd+="cat /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_available_governors; "
    cmd+="else echo 'Unknown'; fi"
    
    # Execute the command
    execute_on_node "$node" "$cmd"
}

# Function to set CPU governor for a specific core using cpupower
set_governor_cpupower() {
    local node=$1
    local core=$2
    local governor=$3
    
    # Command to set governor using cpupower
    local cmd="sudo cpupower -c $core frequency-set -g $governor"
    
    # Execute the command
    echo "Setting CPU ${core} governor to ${governor} on ${node} using cpupower..."
    execute_on_node "$node" "$cmd"
    
    # Verify the setting took effect
    local verify_cmd="cat /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_governor"
    local result=$(execute_on_node "$node" "$verify_cmd")
    
    if [[ "$result" == "$governor" ]]; then
        echo "Successfully set CPU ${core} governor to ${governor} on ${node}"
    else
        echo "Failed to set CPU ${core} governor on ${node}. Current governor: ${result}"
    fi
}

# Function to set CPU governor for a specific core using sysfs
set_governor_sysfs() {
    local node=$1
    local core=$2
    local governor=$3
    
    # Command to set governor using sysfs
    local cmd="echo $governor | sudo tee /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_governor > /dev/null"
    
    # Execute the command
    echo "Setting CPU ${core} governor to ${governor} on ${node} using sysfs..."
    execute_on_node "$node" "$cmd"
    
    # Verify the setting took effect
    local verify_cmd="cat /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_governor"
    local result=$(execute_on_node "$node" "$verify_cmd")
    
    if [[ "$result" == "$governor" ]]; then
        echo "Successfully set CPU ${core} governor to ${governor} on ${node}"
    else
        echo "Failed to set CPU ${core} governor on ${node}. Current governor: ${result}"
    fi
}

# Function to apply governor to a specific node
apply_to_node() {
    local node=$1
    local cores=$2
    local governor=$3
    
    echo "Applying to node: $node"
    
    # Check if we're dealing with 'all' cores on a remote node
    if [[ "$cores" == "all" && "$node" != "localhost" ]]; then
        # Get the core count from the remote node
        core_count=$(execute_on_node "$node" "nproc --all")
        # Generate a sequence from 0 to core_count-1
        cores=$(seq -s ' ' 0 $((core_count-1)))
    else
        # Expand CPU cores specification
        cores=$(expand_cpu_list "$cores")
    fi
    
    # Check if cpupower is available on the node
    has_cpupower=false
    if [[ "$node" == "localhost" ]]; then
        check_cpupower && has_cpupower=true
    else
        # Check remotely if cpupower exists
        execute_on_node "$node" "command -v cpupower &> /dev/null" && has_cpupower=true
    fi
    
    # Apply action to each core
    for core in $cores; do
        # Validate the governor is available for this core
        if ! validate_governor "$node" "$core" "$governor"; then
            available=$(list_available_governors "$node" "$core")
            echo "Warning: Governor '$governor' is not available for CPU $core on $node."
            echo "Available governors: $available"
            continue
        fi
        
        # Set the governor using the appropriate method
        if $has_cpupower; then
            set_governor_cpupower "$node" "$core" "$governor"
        else
            set_governor_sysfs "$node" "$core" "$governor"
        fi
    done
}

# Function to get current CPU governor settings
get_current_settings() {
    local node=$1
    local cores=$2
    
    echo "Current CPU governor settings on $node:"
    echo "-----------------------------------------"
    
    # Check if we're dealing with 'all' cores on a remote node
    if [[ "$cores" == "all" && "$node" != "localhost" ]]; then
        # Get the core count from the remote node
        core_count=$(execute_on_node "$node" "nproc --all")
        # Generate a sequence from 0 to core_count-1
        cores=$(seq -s ' ' 0 $((core_count-1)))
    else
        # Expand CPU cores specification
        cores=$(expand_cpu_list "$cores")
    fi
    
    # Get settings for each core
    for core in $cores; do
        # Command to get current governor
        local cmd="if [ -f /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_governor ]; then "
        cmd+="echo -n \"CPU ${core}: \"; cat /sys/devices/system/cpu/cpu${core}/cpufreq/scaling_governor; "
        cmd+="else echo \"CPU ${core}: No frequency scaling information available\"; fi"
        
        # Execute the command
        execute_on_node "$node" "$cmd"
    done
    
    echo "-----------------------------------------"
}

# Main script execution starts here

# Parse arguments based on count
if [ $# -eq 2 ]; then
    # No node specified, default to localhost
    NODES="localhost"
    CPU_CORES=$1
    GOVERNOR=$2
elif [ $# -eq 3 ]; then
    # Node(s) specified
    NODES=$1
    CPU_CORES=$2
    GOVERNOR=$3
else
    usage
fi

# Common CPU governors
valid_governors=("performance" "powersave" "ondemand" "conservative" "schedutil" "userspace")

# Check if the specified governor is in our list of common ones
governor_valid=false
for valid_gov in "${valid_governors[@]}"; do
    if [[ "$GOVERNOR" == "$valid_gov" ]]; then
        governor_valid=true
        break
    fi
done

# Warn if governor is not in our common list
if ! $governor_valid; then
    echo "Warning: '$GOVERNOR' is not a common CPU governor. Common governors are:"
    echo "${valid_governors[*]}"
    echo "Proceeding anyway, but this might fail if the governor is not available on your system."
fi

# Expand node list if it contains braces or ranges
if [[ "$NODES" == *"{"* ]] || [[ "$NODES" == *"-"* ]]; then
    EXPANDED_NODES=$(expand_node_list "$NODES")
else
    EXPANDED_NODES=$NODES
fi

# First display current settings for reference
for node in $EXPANDED_NODES; do
    get_current_settings "$node" "$CPU_CORES"
done

# Apply for each node
for node in $EXPANDED_NODES; do
    apply_to_node "$node" "$CPU_CORES" "$GOVERNOR"
done

echo "CPU governor control operation completed."
