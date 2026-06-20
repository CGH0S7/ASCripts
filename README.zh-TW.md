# ASCripts

ASC24-26 使用過的叢集功耗控制與維運管理指令稿集合，支援本機及多節點遠端操作。

---

## 指令稿列表

### `cpuctl.sh` — CPU 核心開關控制

啟用或關閉指定的 CPU 核心，支援本機和遠端節點操作。（該指令稿無法用於 EPYC 處理器。）

```
用法: ./cpuctl.sh [NODE_LIST] <CPU_CORES> <on|off>

參數:
  NODE_LIST    (可選) 目標節點，支援花括號範圍語法: node0, {node0,node1}, {node0-node2}
              不指定則在本機執行
  CPU_CORES    核心編號，支援花括號範圍: 1, {1,2}, {1,3-5}, {1-4,6,8-10}
  on|off       開啟 (on) 或關閉 (off) 核心

範例:
  ./cpuctl.sh "{1,3-5}" on               # 本機開啟核心 1,3,4,5
  ./cpuctl.sh node0 "{1,3-5}" on         # 遠端 node0 開啟核心
  ./cpuctl.sh "{node0,node1}" 2 off      # 關閉 node0,node1 上的核心 2
```

**注意事項:** 需要 root 權限；核心 0 無法關閉；遠端節點需設定 SSH 免密碼登入。

---

### `cpugovctl.sh` — CPU 調頻策略控制

設定指定 CPU 核心的 frequency governor，支援本機和遠端節點操作。

```
用法: ./cpugovctl.sh [NODE_LIST] <CPU_CORES> <GOVERNOR>

參數:
  NODE_LIST    (可選) 目標節點，語法同 cpuctl.sh
  CPU_CORES    核心編號或 "all" 表示全部核心
  GOVERNOR     調頻策略: performance, powersave, ondemand, conservative, schedutil

範例:
  ./cpugovctl.sh "{1,3-5}" powersave              # 本機設定 powersave
  ./cpugovctl.sh node0 "{1,3-5}" performance      # 遠端節點設定 performance
  ./cpugovctl.sh "{node0,node1}" all ondemand     # 多節點全部核心設為 ondemand
```

**注意事項:** 優先使用 `cpupower` 命令，若不可用則退回 sysfs 介面。執行前會顯示目前設定以供參考。

---

### `nvidiactl.sh` — NVIDIA GPU PCI 匯流排彈出/恢復

從 PCI 匯流排移除或重新掃描 NVIDIA GPU，支援本機和遠端節點操作。（ASC26 現場測試發現彈出顯示卡似乎並不會降低多少功耗。）

```
用法: ./nvidiactl.sh [node_name] {on|off}
      ./nvidiactl.sh {node1,node2,...} {on|off}

參數:
  node_name    目標節點，支援花括號多節點: {node0,node1}
  on           重新掃描 PCI 匯流排載入 GPU (rescan)
  off          解綁驅動並從 PCI 匯流排移除 GPU

範例:
  ./nvidiactl.sh off                  # 本機移除所有 NVIDIA GPU
  ./nvidiactl.sh on                   # 本機重新載入 GPU
  ./nvidiactl.sh node0 off            # 遠端 node0 移除 GPU
  ./nvidiactl.sh {node0,node1} on     # 遠端多節點重新載入 GPU
```

**注意事項:** 重新載入後如驅動未自動綁定，需手動執行 `modprobe nvidia`。若指令稿執行失敗，可手動操作：

```bash
# 檢視 NVIDIA PCI 位址
lspci -D | grep -i nvidia

# 手動彈出 (以 0000:ac:00.0 為例)
echo -n "0000:ac:00.0" | sudo tee /sys/bus/pci/drivers/nvidia/unbind
echo -n 1 | sudo tee /sys/bus/pci/devices/0000:ac:00.0/remove
```

---

### `nvidiasmictl.sh` — NVIDIA GPU 頻率/功耗控制

基於 `nvidia-smi` 控制 GPU 的圖形時脈、顯示記憶體時脈和功耗上限，支援本機和遠端節點。

```
用法: ./nvidiasmictl.sh [NODE_LIST] <COMMAND> <GPU_IDS> [VALUE]

命令:
  clock  <GPU_IDS> <MHz>    鎖定 GPU 圖形時脈頻率
  mem    <GPU_IDS> <MHz>    鎖定 GPU 顯示記憶體時脈頻率
  power  <GPU_IDS> <Watt>   設定 GPU 功耗上限
  info   <GPU_IDS>          檢視 GPU 目前狀態 (型號/功耗/頻率/溫度)
  reset  <GPU_IDS>          重設 GPU 到預設值

GPU_IDS: 0, "0,2,3", all

範例:
  ./nvidiasmictl.sh power 0 150                  # 本機 GPU 0 功耗限制 150W
  ./nvidiasmictl.sh clock "0,1" 900              # 本機 GPU 0,1 圖形時脈 900MHz
  ./nvidiasmictl.sh node0 info all               # 檢視 node0 全部 GPU 資訊
  ./nvidiasmictl.sh "{node0,node1}" power all 200 # 多節點全部 GPU 功耗限制 200W
  ./nvidiasmictl.sh reset all                    # 重設本機全部 GPU
```

**注意事項:** 需要安裝 NVIDIA 驅動及 `nvidia-smi` 命令；遠端節點需 SSH 免密碼登入。

---

### `manual_parallel.py` — BMC IPMI 風扇控制

透過 BMC 的 HTTP API 控制伺服器風扇轉速，使用多行程平行控制多個節點。（最好用的功耗控制指令稿，感謝 QLU 的同仁。）

ASC 伺服器的 IPMI 帳號密碼預設都是 `admin`。

```
用法: python manual_parallel.py <node_spec> [rate]

如果出現風扇不受控制的情況，可改用：
  watch -n 5 python manual_parallel.py <node_spec> [rate]

參數:
  node_spec    節點範圍: 1, 1-5, 2-4 等
  rate         風扇轉速百分比 (0-100)，預設 20

範例:
  python manual_parallel.py 1-5 30    # 節點 1-5 風扇設為 30%
  python manual_parallel.py 1 20      # 節點 1 風扇設為 20%
  python manual_parallel.py 2-4       # 節點 2-4 風扇使用預設 20%
```

**注意事項:** 使用前需修改指令稿中的 `N1_bmc_host` ~ `N5_bmc_host` 為實際 BMC IP 位址，以及 `username`/`password` 憑證。BMC API 需要 HTTPS 存取且忽略憑證驗證。

建議搭配 `tuned-adm profile throughput-performance/hpc-compute/balanced/powersave` 使用，功耗基本上能控制在不超過限制。

---

### `init.sh` — Rocky Linux 10 HPC 節點初始化

Rocky Linux 10 系統初始化指令稿，完成從系統更新到環境設定的全流程。

**執行步驟:**

1. 系統更新 (`dnf update`)
2. 禁用 Nouveau 驅動並設定核心參數（關閉 mitigations、THP、啟用 IOMMU passthrough）
3. 停用 SELinux
4. 關閉 firewalld
5. 啟用 EPEL/CRB 軟體庫
6. 安裝 Development Tools 組包
7. 安裝 HPC/開發常用套件（kernel-devel、DKMS、numactl、hwloc、perf、Python3 科學計算棧、iperf3、fio、tmux、fish、btop、mosh、ipmitool 等）
8. 設定 tuned 為 `hpc-compute` 模式
9. 設定系統資源限制（memlock、nofile、nproc、stack）
10. 最佳化 SSH 設定（停用 DNS 查詢、用戶端跳過主機金鑰檢查）
11. 安裝 Node.js/npm 及 AI 程式助手（claude-code、codex）
12. 清理並提示重新啟動

```
用法: sudo ./init.sh
```

**注意事項:** 僅適用於 Rocky Linux 10；執行後需要重新啟動系統；重啟後方可安裝 NVIDIA 驅動和 OFED。

---

### `agent-port.sh` — AI Agent 設定備份/還原

備份和還原使用者目錄下的 `.claude` 和 `.codex` 設定目錄，用於跨伺服器遷移 AI 程式助手設定。

```
用法:
  備份全部使用者:   ./agent-port.sh
  備份單一使用者:   ./agent-port.sh -u <username>
  還原備份:         ./agent-port.sh <tarball>
  還原到指定使用者: ./agent-port.sh -t <target_user> <tarball>

範例:
  ./agent-port.sh                                            # 備份所有使用者的設定
  ./agent-port.sh -u alice                                   # 僅備份 alice 的設定
  ./agent-port.sh agent-configs-20260101.tar.gz              # 還原到對應使用者
  ./agent-port.sh -t bob agent-configs-alice-20260101.tar.gz # 將 alice 的備份還原到 bob
```

**注意事項:** 需要 root 權限；僅備份 UID >= 1000 的一般使用者；`-t` 跨使用者還原僅適用於單使用者備份檔。

---

### `sshx` — Rust 編寫的 SSH TUI 管理工具

非常方便的伺服器管理工具，使用方法清晰易懂，打開就能上手。由 Gemini 和 Deepseek 共同開發，上游地址在 https://github.com/CGH0S7/sshx

本軟體庫提供的是在 Rocky 9.6 上構建的二進位檔案:D

---

## 致謝

指令稿由人工編寫 + AI 輔助完善，從 ASC24 迭代到 ASC26。感謝 Claude 等模型對指令稿實現的增強，以及 QLU 的好朋友在 ASC25 賽場上贈予的風扇控制指令稿。
