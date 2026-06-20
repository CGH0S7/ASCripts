# ASCripts

A collection of power control and operations scripts used in ASC24-26 cluster competitions. Supports local and multi-node remote operations.

---

## Script Index

### `cpuctl.sh` — CPU Core On/Off Control

Enable or disable specific CPU cores on local or remote nodes. (Not compatible with EPYC processors.)

```
Usage: ./cpuctl.sh [NODE_LIST] <CPU_CORES> <on|off>

Arguments:
  NODE_LIST    (Optional) Target nodes with brace expansion: node0, {node0,node1}, {node0-node2}
              Runs on local machine if omitted.
  CPU_CORES    Core numbers with brace expansion: 1, {1,2}, {1,3-5}, {1-4,6,8-10}
  on|off       Enable (on) or disable (off) cores

Examples:
  ./cpuctl.sh "{1,3-5}" on               # Enable cores 1,3,4,5 locally
  ./cpuctl.sh node0 "{1,3-5}" on         # Enable cores on node0
  ./cpuctl.sh "{node0,node1}" 2 off      # Disable core 2 on node0 and node1
```

**Notes:** Requires root. Core 0 cannot be disabled. Passwordless SSH is needed for remote nodes.

---

### `cpugovctl.sh` — CPU Governor Control

Set the frequency governor for specific CPU cores on local or remote nodes.

```
Usage: ./cpugovctl.sh [NODE_LIST] <CPU_CORES> <GOVERNOR>

Arguments:
  NODE_LIST    (Optional) Target nodes, same syntax as cpuctl.sh
  CPU_CORES    Core numbers, or "all" for every core
  GOVERNOR     Scaling governor: performance, powersave, ondemand, conservative, schedutil

Examples:
  ./cpugovctl.sh "{1,3-5}" powersave              # Set powersave locally
  ./cpugovctl.sh node0 "{1,3-5}" performance      # Set performance on node0
  ./cpugovctl.sh "{node0,node1}" all ondemand     # Set all cores to ondemand on multiple nodes
```

**Notes:** Prefers `cpupower` when available, falls back to sysfs. Current settings are displayed before making changes.

---

### `nvidiactl.sh` — NVIDIA GPU PCI Detach/Reattach

Remove or rescan NVIDIA GPUs on the PCI bus on local or remote nodes. (Field testing at ASC26 showed that removing GPUs from PCI doesn't significantly reduce power draw.)

```
Usage: ./nvidiactl.sh [node_name] {on|off}
       ./nvidiactl.sh {node1,node2,...} {on|off}

Arguments:
  node_name    Target node(s) with brace expansion: {node0,node1}
  on           Rescan PCI bus to reload GPUs
  off          Unbind driver and remove GPUs from PCI bus

Examples:
  ./nvidiactl.sh off                  # Remove all NVIDIA GPUs locally
  ./nvidiactl.sh on                   # Reload GPUs locally
  ./nvidiactl.sh node0 off            # Remove GPUs on node0
  ./nvidiactl.sh {node0,node1} on     # Reload GPUs on multiple nodes
```

**Notes:** If the driver doesn't auto-bind after rescan, run `modprobe nvidia` manually. Manual fallback:

```bash
# Find NVIDIA PCI addresses
lspci -D | grep -i nvidia

# Manual detach (example: 0000:ac:00.0)
echo -n "0000:ac:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/unbind
echo -n 1 | sudo tee /sys/bus/pci/devices/0000:ac:00.0/remove
```

---

### `nvidiasmictl.sh` — NVIDIA GPU Clock / Power Control

Control GPU graphics clock, memory clock, and power limits via `nvidia-smi`. Supports local and remote nodes.

```
Usage: ./nvidiasmictl.sh [NODE_LIST] <COMMAND> <GPU_IDS> [VALUE]

Commands:
  clock  <GPU_IDS> <MHz>    Lock GPU graphics clock frequency
  mem    <GPU_IDS> <MHz>    Lock GPU memory clock frequency
  power  <GPU_IDS> <Watt>   Set GPU power limit
  info   <GPU_IDS>          Display GPU status (model/power/clocks/temp)
  reset  <GPU_IDS>          Reset GPU to default settings

GPU_IDS: 0, "0,2,3", all

Examples:
  ./nvidiasmictl.sh power 0 150                  # Set GPU 0 power limit to 150W
  ./nvidiasmictl.sh clock "0,1" 900              # Set GPU 0,1 graphics clock to 900MHz
  ./nvidiasmictl.sh node0 info all               # Show info for all GPUs on node0
  ./nvidiasmictl.sh "{node0,node1}" power all 200 # Set power limit 200W on multiple nodes
  ./nvidiasmictl.sh reset all                    # Reset all GPUs locally
```

**Notes:** Requires NVIDIA driver and `nvidia-smi`. Passwordless SSH is needed for remote nodes.

---

### `manual_parallel.py` — BMC IPMI Fan Control

Control server fan speed via BMC HTTP API with multi-process parallel control across nodes. (The most effective power control script — thanks to the QLU teammates.)

Default BMC credentials for ASC servers: `admin` / `admin`.

```
Usage: python manual_parallel.py <node_spec> [rate]

If fans don't obey the setting, use:
  watch -n 5 python manual_parallel.py <node_spec> [rate]

Arguments:
  node_spec    Node range: 1, 1-5, 2-4, etc.
  rate         Fan speed percentage (0-100), default 20

Examples:
  python manual_parallel.py 1-5 30    # Set nodes 1-5 fans to 30%
  python manual_parallel.py 1 20      # Set node 1 fan to 20%
  python manual_parallel.py 2-4       # Set nodes 2-4 fans to default 20%
```

**Notes:** Edit `N1_bmc_host` through `N5_bmc_host` in the script to match actual BMC IPs, plus the `username`/`password` credentials. HTTPS access required; certificate verification is disabled.

Recommended to pair with `tuned-adm profile throughput-performance/hpc-compute/balanced/powersave` — power draw can generally be kept within limits.

---

### `init.sh` — Rocky Linux 10 HPC Node Initialization

Complete Rocky Linux 10 initialization script covering system updates through environment configuration.

**Execution steps:**

1. System update (`dnf update`)
2. Disable Nouveau driver and configure kernel parameters (disable mitigations, THP, enable IOMMU passthrough)
3. Disable SELinux
4. Disable firewalld
5. Enable EPEL/CRB repositories
6. Install "Development Tools" group
7. Install common HPC/dev packages (kernel-devel, DKMS, numactl, hwloc, perf, Python3 scientific stack, iperf3, fio, tmux, fish, btop, mosh, ipmitool, etc.)
8. Configure tuned with `hpc-compute` profile
9. Configure system resource limits (memlock, nofile, nproc, stack)
10. Optimize SSH (disable DNS lookup, client skip host key check)
11. Install Node.js/npm and AI coding agents (claude-code, codex)
12. Clean up and prompt for reboot

```
Usage: sudo ./init.sh
```

**Notes:** Rocky Linux 10 only. A reboot is required after execution. Install NVIDIA driver and OFED after the reboot.

---

### `agent-port.sh` — AI Agent Config Backup / Restore

Back up and restore `.claude` and `.codex` configuration directories from user home directories for cross-server migration.

```
Usage:
  Backup all users:    ./agent-port.sh
  Backup single user:  ./agent-port.sh -u <username>
  Restore:             ./agent-port.sh <tarball>
  Restore to another:  ./agent-port.sh -t <target_user> <tarball>

Examples:
  ./agent-port.sh                                            # Back up all users
  ./agent-port.sh -u alice                                   # Back up only alice
  ./agent-port.sh agent-configs-20260101.tar.gz              # Restore to matching users
  ./agent-port.sh -t bob agent-configs-alice-20260101.tar.gz # Restore alice → bob
```

**Notes:** Requires root. Only backs up users with UID >= 1000. `-t` cross-user restore only works with single-user backup archives.

---

### `sshx` — SSH TUI Management Tool (Rust)

A convenient server management tool — straightforward UI, easy to pick up and use. Built by Gemini and Deepseek. Upstream: https://github.com/CGH0S7/sshx

This repository provides a pre-built binary for Rocky Linux 9.6.

---

## Acknowledgements

Scripts written manually and enhanced by AI from ASC24 through ASC26. Thanks to the Claude model series for implementation improvements, and to the QLU teammates who shared the fan control script during ASC25.
