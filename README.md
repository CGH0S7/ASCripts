# ASCripts

ASC24-26 使用过的集群功耗控制与运维管理脚本集合，支持本地及多节点远程操作。

---

## 脚本列表

### `cpuctl.sh` — CPU 核心开关控制

启用或关闭指定的 CPU 核心，支持本地和远程节点操作。（该脚本无法用于EPYC处理器）

```
用法: ./cpuctl.sh [NODE_LIST] <CPU_CORES> <on|off>

参数:
  NODE_LIST    (可选) 目标节点，支持花括号范围语法: node0, {node0,node1}, {node0-node2}
              不指定则在本地执行
  CPU_CORES    核心编号，支持花括号范围: 1, {1,2}, {1,3-5}, {1-4,6,8-10}
  on|off       开启 (on) 或关闭 (off) 核心

示例:
  ./cpuctl.sh "{1,3-5}" on               # 本地开启核心 1,3,4,5
  ./cpuctl.sh node0 "{1,3-5}" on         # 远程 node0 开启核心
  ./cpuctl.sh "{node0,node1}" 2 off      # 关闭 node0,node1 上的核心 2
```

**注意事项:** 需要 root 权限；核心 0 无法关闭；远程节点需配置 SSH 免密登录。

---

### `cpugovctl.sh` — CPU 调频策略控制

设置指定 CPU 核心的 frequency governor，支持本地和远程节点操作。

```
用法: ./cpugovctl.sh [NODE_LIST] <CPU_CORES> <GOVERNOR>

参数:
  NODE_LIST    (可选) 目标节点，语法同 cpuctl.sh
  CPU_CORES    核心编号或 "all" 表示全部核心
  GOVERNOR     调频策略: performance, powersave, ondemand, conservative, schedutil

示例:
  ./cpugovctl.sh "{1,3-5}" powersave              # 本地设置 powersave
  ./cpugovctl.sh node0 "{1,3-5}" performance      # 远程节点设置 performance
  ./cpugovctl.sh "{node0,node1}" all ondemand     # 多节点全部核心设为 ondemand
```

**注意事项:** 优先使用 `cpupower` 命令，若不可用则回退到 sysfs 接口。执行前会显示当前设置以供参考。

---

### `nvidiactl.sh` — NVIDIA GPU PCI 总线弹出/恢复

从 PCI 总线移除或重新扫描 NVIDIA GPU，支持本地和远程节点操作。(ASC26现场测试发现弹出显卡似乎并不会降低多少功耗)

```
用法: ./nvidiactl.sh [node_name] {on|off}
      ./nvidiactl.sh {node1,node2,...} {on|off}

参数:
  node_name    目标节点，支持花括号多节点: {node0,node1}
  on           重新扫描 PCI 总线加载 GPU (rescan)
  off          解绑驱动并从 PCI 总线移除 GPU

示例:
  ./nvidiactl.sh off                  # 本地移除所有 NVIDIA GPU
  ./nvidiactl.sh on                   # 本地重新加载 GPU
  ./nvidiactl.sh node0 off            # 远程 node0 移除 GPU
  ./nvidiactl.sh {node0,node1} on     # 远程多节点重新加载 GPU
```

**注意事项:** 重新加载后如驱动未自动绑定，需手动执行 `modprobe nvidia`。若脚本执行失败，可手工操作:

```bash
# 查看 NVIDIA PCI 地址
lspci -D | grep -i nvidia

# 手动弹出 (以 0000:ac:00.0 为例)
echo -n "0000:ac:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/unbind
echo -n 1 | sudo tee /sys/bus/pci/devices/0000:ac:00.0/remove
```

---

### `nvidiasmictl.sh` — NVIDIA GPU 频率/功耗控制

基于 `nvidia-smi` 控制 GPU 的图形时钟、显存时钟和功耗上限，支持本地和远程节点。

```
用法: ./nvidiasmictl.sh [NODE_LIST] <COMMAND> <GPU_IDS> [VALUE]

命令:
  clock  <GPU_IDS> <MHz>    锁定 GPU 图形时钟频率
  mem    <GPU_IDS> <MHz>    锁定 GPU 显存时钟频率
  power  <GPU_IDS> <Watt>   设置 GPU 功耗上限
  info   <GPU_IDS>          查看 GPU 当前状态 (型号/功耗/频率/温度)
  reset  <GPU_IDS>          重置 GPU 到默认设置

GPU_IDS: 0, "0,2,3", all

示例:
  ./nvidiasmictl.sh power 0 150                  # 本地 GPU 0 功耗限制 150W
  ./nvidiasmictl.sh clock "0,1" 900              # 本地 GPU 0,1 图形时钟 900MHz
  ./nvidiasmictl.sh node0 info all               # 查看 node0 全部 GPU 信息
  ./nvidiasmictl.sh "{node0,node1}" power all 200 # 多节点全部 GPU 功耗限制 200W
  ./nvidiasmictl.sh reset all                    # 重置本地全部 GPU
```

**注意事项:** 需要安装 NVIDIA 驱动及 `nvidia-smi` 命令；远程节点需 SSH 免密。

---

### `manual_parallel.py` — BMC IPMI 风扇控制

通过 BMC 的 HTTP API 控制服务器风扇转速，使用多进程并行控制多个节点。（最好用的功耗控制脚本，感谢QLU的同仁）

ASC服务器的 IMPI 账号密码默认都是 admin

```
用法: python manual_parallel.py <node_spec> [rate]

如果出现风扇不听话的情况可以改为 watch -n 5 python manual_parallel.py <node_spec> [rate] 强制转速

参数:
  node_spec    节点范围: 1, 1-5, 2-4 等
  rate         风扇转速百分比 (0-100)，默认 20

示例:
  python manual_parallel.py 1-5 30    # 节点 1-5 风扇设为 30%
  python manual_parallel.py 1 20      # 节点 1 风扇设为 20%
  python manual_parallel.py 2-4       # 节点 2-4 风扇使用默认 20%
```

**注意事项:** 使用前需修改脚本中的 `N1_bmc_host` ~ `N5_bmc_host` 为实际 BMC IP 地址，以及 `username`/`password` 凭据。BMC API 需要 HTTPS 访问且忽略证书验证。

建议配合 tund-adm profile throughput-performance/hpc-compute/balanced/powersave 使用，功耗基本能控制不超限制。

---

### `init.sh` — Rocky Linux 10 HPC 节点初始化

Rocky Linux 10 系统初始化脚本，完成从系统更新到环境配置的全流程。

**执行步骤:**

1. 系统更新 (`dnf update`)
2. 禁用 Nouveau 驱动并配置内核参数 (关闭 mitigations、THP、启用 IOMMU passthrough)
3. 禁用 SELinux
4. 关闭 firewalld
5. 启用 EPEL/CRB 仓库
6. 安装 Development Tools 组包
7. 安装 HPC/开发常用包 (kernel-devel, DKMS, numactl, hwloc, perf, Python3 科学计算栈, iperf3, fio, tmux, fish, btop, mosh, ipmitool 等)
8. 配置 tuned 为 `hpc-compute` 模式
9. 配置系统资源限制 (memlock, nofile, nproc, stack)
10. 优化 SSH 配置 (禁用 DNS 查询, 客户端跳过主机密钥检查)
11. 安装 Node.js/npm 及 AI 编程助手 (claude-code, codex)
12. 清理并提示重启

```
用法: sudo ./init.sh
```

**注意事项:** 仅适用于 Rocky Linux 10；执行后需要重启系统；重启后方可安装 NVIDIA 驱动和 OFED。

---

### `agent-port.sh` — AI Agent 配置备份/恢复

备份和恢复用户目录下的 `.claude` 和 `.codex` 配置目录，用于跨服务器迁移 AI 编程助手配置。

```
用法:
  备份全部用户:   ./agent-port.sh
  备份单个用户:   ./agent-port.sh -u <username>
  恢复备份:       ./agent-port.sh <tarball>
  恢复到指定用户: ./agent-port.sh -t <target_user> <tarball>

示例:
  ./agent-port.sh                              # 备份所有用户的配置
  ./agent-port.sh -u alice                     # 仅备份 alice 的配置
  ./agent-port.sh agent-configs-20260101.tar.gz # 恢复到对应用户
  ./agent-port.sh -t bob agent-configs-alice-20260101.tar.gz  # 将 alice 的备份恢复到 bob
```

**注意事项:** 需要 root 权限；仅备份 UID >= 1000 的常规用户；`-t` 跨用户恢复仅适用于单用户备份包。

---

### `sshx` - Rust 编写的ssh tui管理工具

非常方便的服务器管理工具，使用方法清晰易懂打开就能上手 :D

由 Gemini 和 Deepseek 共同完成制作，上游地址在 https://github.com/CGH0S7/sshx

本仓库提供的是 Rocky 9.6 上构建的二进制文件。

## 致谢

脚本由人工编写 + AI 辅助完善从ASC24迭代到ASC26，感谢 Claude 等模型对脚本实现的增强，以及 QLU 的好朋友在 ASC25 赛场上赠予的风扇控制脚本。
