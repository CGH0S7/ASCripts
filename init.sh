#!/usr/bin/env bash
set -euo pipefail

############################################
# ASC Init Script
# Target: Rocky Linux 10
# GPU: NVIDIA
# RDMA: NVIDIA OFED (no rdma-core)
############################################

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

echo "==> Starting Rockylinux 10 initialization..."

############################################
# 1. System update
############################################
echo "==> Updating system..."
dnf -y update

############################################
# 2. Disable nouveau driver & Kernel Tuning
############################################
echo "==> Disabling nouveau and applying kernel parameters..."

cat >/etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

# Optimized kernel parameters:
# - Disable nouveau
# - Disable mitigations (performance)
# - Disable THP (Transparent Huge Pages) at boot
# - Enable IOMMU passthrough (performance)
grubby --update-kernel=ALL --args="rd.driver.blacklist=nouveau modprobe.blacklist=nouveau mitigations=off transparent_hugepage=never iommu=pt"

dracut --force

############################################
# 3. Disable SELinux
############################################
echo "==> Disabling SELinux..."

if command -v getenforce >/dev/null 2>&1; then
    setenforce 0 || true
fi

sed -ri 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

############################################
# 4. Disable firewall
############################################
echo "==> Disabling firewalld..."

systemctl stop firewalld || true
systemctl disable firewalld || true

############################################
# 5. Enable required repositories
############################################
echo "==> Enabling repositories..."

dnf -y install epel-release
dnf config-manager --set-enabled crb || true

############################################
# 6. Install development toolchain
############################################
echo "==> Installing Development Tools..."

dnf -y groupinstall "Development Tools"

############################################
# 7. Install common HPC / development packages
############################################
echo "==> Installing common development packages..."

dnf -y install \
    kernel-devel \
    kernel-headers \
    elfutils-libelf-devel \
    dkms \
    cmake \
    ninja \
    meson \
    git \
    git-lfs \
    wget \
    curl \
    rsync \
    unzip \
    tar \
    vim \
    tmux \
    htop \
    numactl \
    numactl-devel \
    hwloc \
    hwloc-devel \
    pciutils \
    lsof \
    strace \
    perf \
    python3 \
    python3-devel \
    python3-pip \
    openssl-devel \
    libffi-devel \
    libaio \
    libaio-devel \
    environment-modules \
    pdsh \
    iperf3 \
    fio \
    tuned \
    dstat \
    fish \
    btop \

# NOTE:
# rdma-core is intentionally NOT installed.
# NVIDIA OFED (ofed-core) will provide RDMA userspace and kernel modules.

############################################
# 8. Tuned Configuration for HPC
############################################
echo "==> Configuring tuned for HPC workloads..."

# Create custom tuned profile for HPC
mkdir -p /etc/tuned/hpc-performance

cat >/etc/tuned/hpc-performance/tuned.conf <<'EOF'
[main]
summary=Custom HPC performance profile
include=throughput-performance

[cpu]
force_latency=1
governor=performance

[vm]
transparent_hugepages=never

[sysctl]
vm.swappiness=10
kernel.numa_balancing=0
net.core.somaxconn=4096
EOF

# Enable and start tuned service
systemctl enable --now tuned

# Apply custom tuned profile
tuned-adm profile hpc-performance

echo "==> Tuned profile 'hpc-performance' applied successfully."



############################################
# 9. System Resource Limits
############################################
echo "==> Configuring system limits for HPC..."

cat >>/etc/security/limits.conf <<EOF
# Unlimited memory locking for RDMA
* soft memlock unlimited
* hard memlock unlimited
# Increase open file descriptors
* soft nofile 65535
* hard nofile 65535
# Increase process limits
* soft nproc 65535
* hard nproc 65535
# Unlimited stack size (helps with some MPI apps)
* soft stack unlimited
* hard stack unlimited
EOF

############################################
# 10. SSH Optimization
############################################
echo "==> Optimizing SSH configuration..."

# Disable DNS lookup to speed up login
sed -i 's/^#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config
sed -i 's/^UseDNS yes/UseDNS no/' /etc/ssh/sshd_config

# Client config to avoid strict checking prompts and noise
cat >>/etc/ssh/ssh_config <<EOF
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
EOF

systemctl restart sshd

############################################
# 11. Cleanup
############################################
dnf -y autoremove
dnf clean all

echo "==> Initialization completed successfully."
echo "==> Please reboot the system before installing NVIDIA driver or OFED."
echo ""
read -p "Do you want to reboot the system now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
fi
