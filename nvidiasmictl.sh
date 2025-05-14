#!/bin/bash

# nvidia_power_control.sh - Script to control NVIDIA GPU clock speeds and power limits
# Usage: ./nvidia_power_control.sh [NODE_LIST] <COMMAND> <GPU_IDS> <VALUE>
# Example: ./nvidia_power_control.sh clock 0 900       # Set GPU 0 clock to 900MHz locally
#          ./nvidia_power_control.sh node0 power "0,1" 150  # Set power limit to 150W for GPUs 0,1 on node0
#          ./nvidia_power_control.sh "{node0,node1}" reset all  # Reset all GPUs on node0 and node1

# Function to display usage information
usage() {
    echo "Usage: $0 [NODE_LIST] <COMMAND> <GPU_IDS> [VALUE]"
    echo ""
    echo "  NODE_LIST: (Optional) Specify target nodes using names, ranges, or combinations in braces."
    echo "             Examples: node0, {node0,node1}, {node0-node2}"
    echo "             If not provided, commands run on local machine."
    echo ""
    echo "  COMMAND: Action to perform on the GPUs"
    echo "           clock  - Set GPU graphics clock speed limit (in MHz)"
    echo "           power  - Set GPU power limit (in Watts)"
    echo "           mem    - Set GPU memory clock speed limit (in MHz)"
    echo "           info   - Display current GPU settings"
    echo "           reset  - Reset GPU to default settings"
    echo ""
    echo "  GPU_IDS: Specify GPU IDs as numbers, comma-separated list, or 'all'"
    echo "           Examples: 0, \"0,2,3\", all"
    echo ""
    echo "  VALUE:   Value to set (required for clock, power, and mem commands)"
    echo "           For clock: MHz (e.g., 900 for 900MHz)"
    echo "           For power: Watts (e.g., 150 for 150W)"
    echo "           For mem: MHz (e.g., 5000 for 5000MHz)"
    echo ""
    echo "Examples:"
    echo "  $0 power 0 150                      - Set power limit to 150W for GPU 0 on local machine"
    echo "  $0 clock \"0,1\" 900                  - Set clock speed to 900MHz for GPUs 0 and 1 on local machine"
    echo "  $0 node0 info all                   - Display info for all GPUs on node0"
    echo "  $0 \"{node0,node1}\" power all 200    - Set power limit to 200W for all GPUs on node0 and node1"
    echo "  $0 reset all                        - Reset all GPUs on local machine to default settings"
    exit 1
}

# Function to check if nvidia-smi is available
check_nvidia_smi() {
    if ! command -v nvidia-smi &> /dev/null; then
        echo "Error: nvidia-smi command not found. Please ensure NVIDIA drivers are installed correctly."
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

# Function to get list of available GPUs
get_gpu_list() {
    local node=$1
    local gpu_ids=$2
    
    # If requesting all GPUs, query the system
    if [[ "$gpu_ids" == "all" ]]; then
        if [[ "$node" == "localhost" ]]; then
            # Get GPU count locally
            gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits)
            # Generate list from 0 to (count-1)
            gpu_list=$(seq -s ',' 0 $((gpu_count-1)))
        else
            # Get GPU count remotely
            gpu_list=$(ssh "$node" "nvidia-smi --query-gpu=count --format=csv,noheader,nounits | xargs -I{} seq -s ',' 0 \$(({}1))")
        fi
    else
        # Use the provided list
        gpu_list=$gpu_ids
    fi
    
    echo "$gpu_list"
}

# Function to display current GPU information
show_gpu_info() {
    local node=$1
    local gpu_list=$2
    
    # Replace commas with spaces for the command
    gpu_list_spaced=${gpu_list//,/ }
    
    # Command for displaying GPU info
    cmd="echo 'GPU Information on $node:';"
    cmd+="echo '---------------------------------';"
    
    for gpu_id in $gpu_list_spaced; do
        cmd+="echo -n 'GPU $gpu_id: ';"
        cmd+="nvidia-smi --query-gpu=name --format=csv,noheader -i $gpu_id;"
        cmd+="echo 'Power Limit: ';"
        cmd+="nvidia-smi --query-gpu=power.limit --format=csv,noheader -i $gpu_id;"
        cmd+="echo 'Current Power Draw: ';"
        cmd+="nvidia-smi --query-gpu=power.draw --format=csv,noheader -i $gpu_id;"
        cmd+="echo 'Graphics Clock: ';"
        cmd+="nvidia-smi --query-gpu=clocks.current.graphics --format=csv,noheader -i $gpu_id;"
        cmd+="echo 'Memory Clock: ';"
        cmd+="nvidia-smi --query-gpu=clocks.current.memory --format=csv,noheader -i $gpu_id;"
        cmd+="echo 'Temperature: ';"
        cmd+="nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader -i $gpu_id;"
        cmd+="echo '---------------------------------';"
    done
    
    execute_on_node "$node" "$cmd"
}

# Function to set GPU clock speed
set_gpu_clock() {
    local node=$1
    local gpu_list=$2
    local clock_value=$3
    
    # Replace commas with spaces for the command
    gpu_list_spaced=${gpu_list//,/ }
    
    # Command for setting GPU clock
    cmd="for gpu_id in $gpu_list_spaced; do "
    cmd+="echo 'Setting GPU \$gpu_id graphics clock to ${clock_value}MHz on $node';"
    cmd+="sudo nvidia-smi -i \$gpu_id --lock-gpu-clocks=$clock_value,$clock_value;"
    cmd+="if [ \$? -eq 0 ]; then echo 'Success!'; else echo 'Failed!'; fi;"
    cmd+="done"
    
    execute_on_node "$node" "$cmd"
}

# Function to set GPU memory clock speed
set_gpu_mem_clock() {
    local node=$1
    local gpu_list=$2
    local mem_clock=$3
    
    # Replace commas with spaces for the command
    gpu_list_spaced=${gpu_list//,/ }
    
    # Command for setting GPU memory clock
    cmd="for gpu_id in $gpu_list_spaced; do "
    cmd+="echo 'Setting GPU \$gpu_id memory clock to ${mem_clock}MHz on $node';"
    cmd+="sudo nvidia-smi -i \$gpu_id --lock-memory-clocks=$mem_clock,$mem_clock;"
    cmd+="if [ \$? -eq 0 ]; then echo 'Success!'; else echo 'Failed!'; fi;"
    cmd+="done"
    
    execute_on_node "$node" "$cmd"
}

# Function to set GPU power limit
set_gpu_power() {
    local node=$1
    local gpu_list=$2
    local power_value=$3
    
    # Replace commas with spaces for the command
    gpu_list_spaced=${gpu_list//,/ }
    
    # Command for setting GPU power limit
    cmd="for gpu_id in $gpu_list_spaced; do "
    cmd+="echo 'Setting GPU \$gpu_id power limit to ${power_value}W on $node';"
    cmd+="sudo nvidia-smi -i \$gpu_id -pl $power_value;"
    cmd+="if [ \$? -eq 0 ]; then echo 'Success!'; else echo 'Failed!'; fi;"
    cmd+="done"
    
    execute_on_node "$node" "$cmd"
}

# Function to reset GPU settings to default
reset_gpu() {
    local node=$1
    local gpu_list=$2
    
    # Replace commas with spaces for the command
    gpu_list_spaced=${gpu_list//,/ }
    
    # Command for resetting GPU
    cmd="for gpu_id in $gpu_list_spaced; do "
    cmd+="echo 'Resetting GPU \$gpu_id on $node';"
    cmd+="sudo nvidia-smi -i \$gpu_id -rgc;"  # Reset GPU clocks
    cmd+="sudo nvidia-smi -i \$gpu_id -rmc;"  # Reset memory clocks
    cmd+="sudo nvidia-smi -i \$gpu_id -rpl;"  # Reset power limit
    cmd+="echo 'Reset complete for GPU \$gpu_id';"
    cmd+="done"
    
    execute_on_node "$node" "$cmd"
}

# Main script execution starts here

# Parse arguments based on count
if [[ $# -lt 2 ]]; then
    usage
fi

# Check if first argument could be a node specification
if [[ $1 == *"node"* || $1 == *"{"* ]]; then
    NODES=$1
    shift
    if [[ $# -lt 2 ]]; then
        usage
    fi
else
    # No node specified, default to localhost
    NODES="localhost"
fi

COMMAND=$1
GPU_IDS=$2
VALUE=$3

# Validate command
case "$COMMAND" in
    clock|power|mem|info|reset)
        # Valid command
        ;;
    *)
        echo "Error: Invalid command '$COMMAND'"
        usage
        ;;
esac

# Check if value is required but not provided
if [[ "$COMMAND" =~ ^(clock|power|mem)$ && -z "$VALUE" ]]; then
    echo "Error: Command '$COMMAND' requires a value"
    usage
fi

# If operating on local machine only, check nvidia-smi
if [[ "$NODES" == "localhost" ]]; then
    check_nvidia_smi || exit 1
fi

# Expand node list if it contains braces or ranges
if [[ "$NODES" == *"{"* || "$NODES" == *"-"* ]]; then
    EXPANDED_NODES=$(expand_node_list "$NODES")
else
    EXPANDED_NODES=$NODES
fi

# Apply for each node
for node in $EXPANDED_NODES; do
    echo "Processing node: $node"
    
    # Get list of GPUs to work with
    GPU_LIST=$(get_gpu_list "$node" "$GPU_IDS")
    
    # Execute the requested command
    case "$COMMAND" in
        info)
            show_gpu_info "$node" "$GPU_LIST"
            ;;
        clock)
            set_gpu_clock "$node" "$GPU_LIST" "$VALUE"
            ;;
        mem)
            set_gpu_mem_clock "$node" "$GPU_LIST" "$VALUE"
            ;;
        power)
            set_gpu_power "$node" "$GPU_LIST" "$VALUE"
            ;;
        reset)
            reset_gpu "$node" "$GPU_LIST"
            ;;
    esac
done

echo "NVIDIA GPU control operation completed."
