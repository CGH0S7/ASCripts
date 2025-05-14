#!/bin/bash

# cpu_control.sh - Script to enable/disable CPU cores on local or remote nodes
# Usage: ./cpu_control.sh [NODE_LIST] <CPU_CORES> <on|off>
# Example: ./cpu_control.sh "{1,3-5,7}" on
#          ./cpu_control.sh node0 "{1,3-5}" on
#          ./cpu_control.sh "{node0,node1}" 2 off
#          ./cpu_control.sh "{node0-node2}" "{1-4}" off

# Function to display usage information
usage() {
    echo "Usage: $0 [NODE_LIST] <CPU_CORES> <on|off>"
    echo "  NODE_LIST: (Optional) Specify target nodes using names, ranges, or combinations in braces."
    echo "             Examples: node0, {node0,node1}, {node0-node2}"
    echo "             If not provided, commands run on local machine."
    echo "  CPU_CORES: Specify cores using numbers, ranges, or combinations in braces."
    echo "             Examples: 1, {1,2}, {1,3-5}, {1-4,6,8-10}"
    echo "  on|off: Specify whether to enable (on) or disable (off) the cores"
    echo ""
    echo "Example: $0 \"{1,3-5}\" on                - Enables cores 1, 3, 4, and 5 on local machine"
    echo "         $0 node0 \"{1,3-5}\" on          - Enables cores on specific node"
    echo "         $0 \"{node0,node1}\" 2 off       - Disables core 2 on multiple nodes"
    exit 1
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root (or with sudo)."
        exit 1
    fi
}

# Validate if CPU core exists
validate_core() {
    local core=$1
    if [ ! -d "/sys/devices/system/cpu/cpu${core}" ]; then
        echo "Warning: CPU core ${core} does not exist, skipping."
        return 1
    fi
    return 0
}

# Function to enable or disable a specific CPU core
set_cpu_state() {
    local core=$1
    local state=$2
    
    # Don't allow turning off core 0 (primary core)
    if [ "$core" -eq 0 ] && [ "$state" -eq 0 ]; then
        echo "Warning: Cannot disable CPU core 0 (primary core), skipping."
        return
    fi
    
    # Check if the core exists
    validate_core "$core" || return
    
    # Check if online control file exists
    if [ ! -f "/sys/devices/system/cpu/cpu${core}/online" ]; then
        echo "Warning: Control file for CPU${core} doesn't exist, skipping."
        return
    fi
    
    # Set the state
    echo "$state" > "/sys/devices/system/cpu/cpu${core}/online"
    
    if [ $? -eq 0 ]; then
        if [ "$state" -eq 1 ]; then
            echo "CPU core ${core} enabled."
        else
            echo "CPU core ${core} disabled."
        fi
    else
        echo "Error: Failed to change state of CPU core ${core}."
    fi
}

# Expand the CPU core list
expand_cpu_list() {
    local cpu_spec=$1
    local expanded_list=""
    
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

# Function to apply CPU state to a specific node
apply_to_node() {
    local node=$1
    local cores=$2
    local state=$3
    
    echo "Applying to node: $node"
    
    # For local operation
    if [[ "$node" == "localhost" ]]; then
        # Expand CPU cores specification locally
        EXPANDED_CORES=$(expand_cpu_list "$cores")
        
        # Apply action to each core
        for core in $EXPANDED_CORES; do
            set_cpu_state "$core" "$state"
        done
    else
        # For remote operation
        # Generate the command to run on the remote node
        remote_cmd="for core in \$(echo $cores | sed 's/{//g' | sed 's/}//g' | sed 's/-/ /g' | xargs -n1 | sort -u); do "
        remote_cmd+="if [[ \$core =~ ^[0-9]+-[0-9]+$ ]]; then "
        remote_cmd+="start=\${core%-*}; end=\${core#*-}; "
        remote_cmd+="for ((i=start; i<=end; i++)); do "
        remote_cmd+="if [ \$i -ne 0 ] || [ $state -eq 1 ]; then "
        remote_cmd+="echo $state | sudo tee /sys/devices/system/cpu/cpu\$i/online >/dev/null && "
        remote_cmd+="echo \"CPU core \$i state set to $state on $node\"; "
        remote_cmd+="else echo \"Warning: Cannot disable CPU core 0 (primary core), skipping.\"; fi; "
        remote_cmd+="done; "
        remote_cmd+="else "
        remote_cmd+="if [ \$core -ne 0 ] || [ $state -eq 1 ]; then "
        remote_cmd+="echo $state | sudo tee /sys/devices/system/cpu/cpu\$core/online >/dev/null && "
        remote_cmd+="echo \"CPU core \$core state set to $state on $node\"; "
        remote_cmd+="else echo \"Warning: Cannot disable CPU core 0 (primary core), skipping.\"; fi; "
        remote_cmd+="fi; done"
        
        # Execute on remote node
        execute_on_node "$node" "$remote_cmd"
    fi
}

# Main script execution starts here

# Parse arguments based on count
if [ $# -eq 2 ]; then
    # No node specified, default to localhost
    NODES="localhost"
    CPU_CORES=$1
    ACTION=$2
elif [ $# -eq 3 ]; then
    # Node(s) specified
    NODES=$1
    CPU_CORES=$2
    ACTION=$3
else
    usage
fi

# Validate action
if [ "$ACTION" != "on" ] && [ "$ACTION" != "off" ]; then
    echo "Error: The action parameter must be 'on' or 'off'."
    usage
fi

# Convert action to numeric value
if [ "$ACTION" == "on" ]; then
    STATE=1
else
    STATE=0
fi

# If operating on local machine only, check root permissions
if [ "$NODES" == "localhost" ]; then
    check_root
fi

# Expand node list if it contains braces or ranges
if [[ "$NODES" == *"{"* ]] || [[ "$NODES" == *"-"* ]]; then
    EXPANDED_NODES=$(expand_node_list "$NODES")
else
    EXPANDED_NODES=$NODES
fi

# Apply for each node
for node in $EXPANDED_NODES; do
    apply_to_node "$node" "$CPU_CORES" "$STATE"
done

echo "CPU control operation completed."
