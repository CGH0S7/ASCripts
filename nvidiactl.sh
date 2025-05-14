#!/bin/bash

# nvidiactl.sh - Script to detach or reattach NVIDIA GPUs
# Usage: ./nvidiactl.sh [node_name] {on|off}
#        ./nvidiactl.sh {node1,node2,...} {on|off}

set -e

# Function to display usage instructions
show_usage() {
    echo "Usage: $0 [node_name] {on|off}"
    echo "   or: $0 {node1,node2,...} {on|off}"
    echo "Examples:"
    echo "   $0 off                # Detach NVIDIA GPUs on local machine"
    echo "   $0 on                 # Reattach NVIDIA GPUs on local machine"
    echo "   $0 node0 off          # Detach NVIDIA GPUs on node0"
    echo "   $0 {node0,node1} on   # Reattach NVIDIA GPUs on node0 and node1"
    exit 1
}

# Function to get NVIDIA GPU PCI addresses
get_nvidia_pci_addresses() {
    local node=$1
    local cmd="lspci -D | grep -i nvidia | grep -v Audio | awk '{print \$1}'"
    
    if [[ -z "$node" || "$node" == "localhost" ]]; then
        eval "$cmd"
    else
        ssh "$node" "$cmd"
    fi
}

# Function to detach an NVIDIA GPU
detach_nvidia_gpu() {
    local node=$1
    local pci_addr=$2
    local escaped_pci_addr=$(echo "$pci_addr" | sed 's/:/\\:/g')
    
    echo "Detaching NVIDIA GPU at PCI address $pci_addr on $node..."
    
    if [[ -z "$node" || "$node" == "localhost" ]]; then
        # Check if device is already unbound
        if [ -e "/sys/bus/pci/drivers/nvidia/$pci_addr" ]; then
            echo -n "$pci_addr" | sudo tee /sys/bus/pci/drivers/nvidia/unbind > /dev/null
        fi
        echo -n "1" | sudo tee "/sys/bus/pci/devices/$escaped_pci_addr/remove" > /dev/null
    else
        ssh "$node" "if [ -e /sys/bus/pci/drivers/nvidia/$pci_addr ]; then \
                      echo -n \"$pci_addr\" | sudo tee /sys/bus/pci/drivers/nvidia/unbind > /dev/null; \
                      fi; \
                      echo -n \"1\" | sudo tee \"/sys/bus/pci/devices/$escaped_pci_addr/remove\" > /dev/null"
    fi
    
    echo "GPU at $pci_addr detached successfully on $node"
}

# Function to reattach all NVIDIA GPUs
reattach_nvidia_gpus() {
    local node=$1
    
    echo "Reattaching all NVIDIA GPUs on $node..."
    
    if [[ -z "$node" || "$node" == "localhost" ]]; then
        echo -n "1" | sudo tee /sys/bus/pci/rescan > /dev/null
    else
        ssh "$node" "echo -n \"1\" | sudo tee /sys/bus/pci/rescan > /dev/null"
    fi
    
    echo "GPU reattachment initiated on $node. The driver should load automatically."
    echo "If not, you may need to reload the NVIDIA driver with: sudo modprobe nvidia"
}

# Parse arguments
if [[ $# -eq 0 || $# -gt 2 ]]; then
    show_usage
fi

# Determine command and nodes
if [[ $# -eq 1 ]]; then
    # Only one argument, must be on/off for local machine
    nodes=("localhost")
    action=$1
elif [[ $# -eq 2 ]]; then
    # Two arguments, first is node(s), second is on/off
    if [[ $1 =~ ^\{.*\}$ ]]; then
        # Handle multiple nodes in brace expansion format
        nodes_str=${1#\{}
        nodes_str=${nodes_str%\}}
        IFS=',' read -ra nodes <<< "$nodes_str"
    else
        # Single node
        nodes=("$1")
    fi
    action=$2
else
    show_usage
fi

# Validate action
if [[ "$action" != "on" && "$action" != "off" ]]; then
    echo "Error: Action must be 'on' or 'off'"
    show_usage
fi

# Process each node
for node in "${nodes[@]}"; do
    node_display=$node
    [[ "$node" == "localhost" ]] && node_display="local machine"
    
    if [[ "$action" == "off" ]]; then
        echo "Processing GPU detachment on $node_display..."
        pci_addresses=$(get_nvidia_pci_addresses "$node")
        
        if [[ -z "$pci_addresses" ]]; then
            echo "No NVIDIA GPUs found on $node_display"
            continue
        fi
        
        while read -r pci_addr; do
            detach_nvidia_gpu "$node" "$pci_addr"
        done <<< "$pci_addresses"
        
    elif [[ "$action" == "on" ]]; then
        echo "Processing GPU reattachment on $node_display..."
        reattach_nvidia_gpus "$node"
    fi
done

echo "Operation completed successfully."
