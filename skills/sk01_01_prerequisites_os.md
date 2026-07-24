---
name: oracle-install-prerequisites-os
description: >
  Chuẩn bị hệ điều hành trước khi cài đặt Oracle Database.
  Kích hoạt khi hỏi về: oracle prerequisites, chuẩn bị cài Oracle,
  kernel parameters Oracle, hugepages Oracle, OS limits Oracle,
  packages cần thiết Oracle, oracle user group setup, oinstall dba group,
  directory structure Oracle, ORACLE_BASE ORACLE_HOME setup,
  SELinux Oracle, firewall Oracle, swap space Oracle,
  oracle preinstall package, pre-install check Oracle,
  RHEL Oracle install, OracleLinux install, AIX Oracle, Solaris Oracle,
  NTP Oracle RAC, SSH equivalence RAC, /etc/hosts RAC setup.
---

# SK01-01 · Chuẩn bị OS trước khi cài Oracle

**Phạm vi:** Oracle 11g R2, 12c, 19c, 21c, 23ai, 26ai | Linux RHEL/OL 7/8/9, Solaris, AIX  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)- Bậc thầy DBA, 20 năm kinh nghiệm Thiết kế, Triển khai, Đào tạo, Vận hành, Tối ưu Oracle/System/WebLogic, Founder VietDBA Academy và Cộng đồng DBA Việt Nam.

---

## 1. HARDWARE REQUIREMENTS

| Thành phần | Minimum | Production Recommendation |
|------------|---------|--------------------------|
| RAM | 2 GB | 16 GB+ |
| Swap | 2x RAM (≤2GB RAM), 1.5x (2-16GB), min 16GB | Equal to RAM |
| /tmp | 1 GB | 5 GB |
| ORACLE_BASE | 6.5 GB (software) | 50 GB+ |
| /u01 data | N/A | 200 GB+ (SSD/NVMe khuyến dùng) |
| CPU | 1 core | 8+ cores |

```bash
# Kiểm tra requirements
echo "=== HARDWARE CHECK ==="
grep MemTotal /proc/meminfo
free -h
df -h /tmp /u01
nproc
uname -r -m
```

---

## 2. OS PACKAGES

### 2.1 RHEL / Oracle Linux 8/9 (19c, 21c, 23ai)

```bash
# Phương án 1: Dùng preinstall package (khuyến dùng — tự động cấu hình tất cả)
dnf install -y oracle-database-preinstall-19c   # Oracle 19c
dnf install -y oracle-database-preinstall-21c   # Oracle 21c
dnf install -y oracle-database-preinstall-23c   # Oracle 23ai/26ai

# Phương án 2: Manual install từng package
dnf install -y \
  bc binutils binutils-devel compat-libcap1 \
  elfutils-libelf elfutils-libelf-devel \
  fontconfig-devel glibc glibc-common glibc-devel glibc-headers \
  gcc gcc-c++ ksh libaio libaio-devel libdtrace-ctf-devel \
  libgcc libgomp libstdc++ libstdc++-devel libX11 libXau \
  libXi libXrender libXrender-devel libXtst libxcb \
  libXinerama libXext make nfs-utils net-tools \
  policycoreutils policycoreutils-python-utils \
  procps-ng psmisc smartmontools sysstat \
  unixODBC unixODBC-devel

# Oracle Linux 8/9 thêm:
dnf install -y compat-openssl11 libnsl libnsl2 libibverbs

# Verify packages installed
rpm -qa | grep -E "glibc|libaio|libstdc" | sort
```

### 2.2 RHEL/OL 7 (11g R2, 12c, 19c)

```bash
yum install -y \
  binutils compat-libcap1 compat-libstdc++-33 \
  gcc gcc-c++ glibc glibc-devel ksh libaio libaio-devel \
  libgcc libstdc++ libstdc++-devel libX11 libXau libXi \
  libXrender libXrender-devel libXtst libxcb make \
  net-tools nfs-utils psmisc smartmontools sysstat unixODBC
```

### 2.3 Solaris 11 (SPARC/x86)

```bash
# Solaris 11.4 packages
pkg install system/library/math system/library/c-runtime \
  system/library/gcc-runtime developer/gcc system/dtrace

# Solaris kernel parameters (/etc/system) thêm vào:
set semsys:seminfo_semmsl=32000
set semsys:seminfo_semmni=128
set semsys:seminfo_semopm=100
set semsys:seminfo_semmns=32000
set shmsys:shminfo_shmmax=4294967295
set shmsys:shminfo_shmmni=4096
```

### 2.4 AIX 7.x

```bash
# Filesets cần thiết trên AIX
lslpp -l bos.adt.base bos.perf.libperfstat
# installp -aXYgd /dev/cd0 bos.adt.base

# AIX kernel parameters (không cần đặt, hệ thống tự adjust)
# Nhưng cần kiểm tra:
lsattr -El sys0 | grep maxuproc  # maxuproc >= 8192
chdev -l sys0 -a maxuproc=8192
```

---

## 3. KERNEL PARAMETERS

### 3.1 /etc/sysctl.conf — Production Settings

```bash
cat >> /etc/sysctl.conf << 'EOF'
# Oracle DB - Kernel parameters
# Tham khảo: docs.oracle.com + kinh nghiệm VietDBA production

# Shared Memory
kernel.shmall = 4294967296     # Tổng shared memory pages (tính theo PAGE)
kernel.shmmax = 68719476736    # Max shared memory segment = 64GB (set >= SGA)
kernel.shmmni = 4096           # Max number of shared memory segments

# Semaphores: SEMMSL SEMMNS SEMOPM SEMMNI
kernel.sem = 250 32000 100 128

# File handles
fs.file-max = 6815744
fs.aio-max-nr = 1048576

# Network
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576

# VM
vm.swappiness = 10            # Giảm swap usage (SSD: 1, HDD: 10)
vm.dirty_background_ratio = 3
vm.dirty_ratio = 80
vm.dirty_expire_centisecs = 500
vm.dirty_writeback_centisecs = 100

# RAC: thêm cho interconnect
net.core.optmem_max = 4194304
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 87380 134217728
net.ipv4.tcp_window_scaling = 1
EOF

sysctl -p  # Apply ngay
sysctl -a | grep kernel.shmmax  # Verify
```

### 3.2 HugePages (QUAN TRỌNG — Production bắt buộc)

```bash
# HugePages giúp giảm TLB misses, tăng performance SGA
# LƯU Ý: KHÔNG dùng AMM (memory_target) khi có HugePages

# Tính HugePages cần thiết:
# hugepages_needed = ceil(SGA_MAX_SIZE / hugepage_size)
# Ví dụ: SGA = 32GB, hugepage = 2MB → 32*1024/2 = 16384

# Xem hugepage size hiện tại
grep Hugepagesize /proc/meminfo  # Thường là 2048 kB = 2 MB

# Script tính tự động (chạy sau khi DB đang up)
ORACLE_SGA_MB=$(sqlplus -S / as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT ROUND(SUM(value)/1024/1024) FROM v$sga;
EXIT;
EOF
)
HP_SIZE_KB=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
HP_NEEDED=$(echo "($ORACLE_SGA_MB * 1024 + $HP_SIZE_KB - 1) / $HP_SIZE_KB" | bc)
echo "Hugepages needed: $HP_NEEDED (add 10% buffer)"
HP_WITH_BUFFER=$(( HP_NEEDED + HP_NEEDED / 10 ))

# Set hugepages
echo "vm.nr_hugepages = $HP_WITH_BUFFER" >> /etc/sysctl.conf
sysctl -p

# Verify
grep HugePages /proc/meminfo
# HugePages_Total: 17408
# HugePages_Free:  17408  (sau khi DB start = Total - used)

# Transparent HugePages — PHẢI TẮT cho Oracle
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
# Persistent (GRUB):
grubby --update-kernel=ALL \
  --args="transparent_hugepage=never"
```

### 3.3 /etc/security/limits.conf

```bash
cat >> /etc/security/limits.conf << 'EOF'
# Oracle limits
oracle   soft   nofile     1024
oracle   hard   nofile     65536
oracle   soft   nproc      16384
oracle   hard   nproc      16384
oracle   soft   stack      10240
oracle   hard   stack      32768
oracle   hard   memlock    unlimited
oracle   soft   memlock    unlimited

# Grid/ASM user (RAC)
grid     soft   nofile     1024
grid     hard   nofile     65536
grid     soft   nproc      16384
grid     hard   nproc      16384
grid     hard   memlock    unlimited
grid     soft   memlock    unlimited
EOF

# Verify (với oracle user)
su - oracle -c "ulimit -a"
```

---

## 4. USERS, GROUPS & DIRECTORIES

```bash
# ── Single Instance Setup ─────────────────────────────
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba

useradd -u 54321 -g oinstall \
  -G dba,oper,backupdba,dgdba,kmdba \
  -m -d /home/oracle -s /bin/bash oracle
echo "oracle:$(openssl rand -base64 12)" | chpasswd

# ── RAC thêm groups cho Grid/ASM ────────────────────
groupadd -g 54327 racdba
groupadd -g 54328 asmadmin
groupadd -g 54329 asmdba
groupadd -g 54330 asmoper

useradd -u 54321 -g oinstall \
  -G dba,oper,backupdba,dgdba,kmdba,racdba \
  -m -d /home/oracle -s /bin/bash oracle

useradd -u 54331 -g oinstall \
  -G asmadmin,asmdba,asmoper,dba,racdba \
  -m -d /home/grid -s /bin/bash grid

# ── Directory structure ──────────────────────────────
# Standard OFA (Optimal Flexible Architecture)
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1    # ORACLE_HOME
mkdir -p /u01/app/oracle/admin/ORCL/{adump,dpdump,scripts}
mkdir -p /u01/app/oraInventory
mkdir -p /u01/oradata/ORCL              # Datafiles
mkdir -p /u01/arch                       # Archive logs (nếu không dùng FRA)
mkdir -p /backup/rman                    # RMAN backups

# RAC thêm:
mkdir -p /u01/app/grid/19.3.0           # Grid Home
mkdir -p /u01/app/grid                  # Grid Base

# Permissions
chown -R oracle:oinstall /u01/app/oracle
chown    oracle:oinstall /u01/oradata /u01/arch /backup/rman
chown -R grid:oinstall   /u01/app/grid
chown    grid:oinstall   /u01/app/oraInventory
chmod -R 775 /u01

# ── .bash_profile oracle user ───────────────────────
cat > /home/oracle/.bash_profile << 'EOF'
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Oracle Environment
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export ORACLE_SID=ORCL
export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export PATH=$ORACLE_HOME/bin:/usr/sbin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
export TNS_ADMIN=$ORACLE_HOME/network/admin

# Aliases hữu ích
alias sqlp='sqlplus / as sysdba'
alias tns='cat $TNS_ADMIN/tnsnames.ora'
alias alert='tail -100f $ORACLE_BASE/diag/rdbms/orcl/ORCL/trace/alert_ORCL.log'
EOF
chown oracle:oinstall /home/oracle/.bash_profile
```

---

## 5. SECURITY SETTINGS

### 5.1 SELinux & Firewall

```bash
# SELinux — Permissive (Enforcing có thể gây issue với Oracle)
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
# Hoặc Disabled:
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config

# Firewall — Mở ports cần thiết
firewall-cmd --permanent --add-port=1521/tcp    # Oracle Listener
firewall-cmd --permanent --add-port=5500/tcp    # EM Express
firewall-cmd --permanent --add-port=3938/tcp    # EM Cloud Control Agent
firewall-cmd --permanent --add-port=7809/tcp    # GoldenGate Manager
firewall-cmd --permanent --add-port=2049/tcp    # NFS (nếu cần)
# RAC thêm:
firewall-cmd --permanent --add-port=42424/tcp   # ASM/Clusterware
firewall-cmd --permanent --add-port=6200/tcp    # ONS (Fast Connection Failover)
firewall-cmd --reload
```

### 5.2 NTP (Critical cho RAC)

```bash
# RAC: tất cả nodes phải sync NTP, sai lệch < 1 giây
timedatectl set-timezone Asia/Ho_Chi_Minh
dnf install -y chrony

cat >> /etc/chrony.conf << 'EOF'
server ntp.vietdba.local iburst prefer
server pool.ntp.org iburst
EOF

systemctl enable --now chronyd
chronyc tracking   # Kiểm tra sync
chronyc sources -v
```

---

## 6. RAC-SPECIFIC PREREQUISITES

### 6.1 /etc/hosts và Network

```bash
# /etc/hosts — cấu hình trên CẢ HAI nodes
cat >> /etc/hosts << 'EOF'
# Public IPs
192.168.1.101  node1.vietdba.local  node1
192.168.1.102  node2.vietdba.local  node2

# Virtual IPs (VIP — failover với Clusterware)
192.168.1.111  node1-vip.vietdba.local  node1-vip
192.168.1.112  node2-vip.vietdba.local  node2-vip

# Private interconnect (phải là dedicated network, không route internet)
10.10.1.101    node1-priv.vietdba.local  node1-priv
10.10.1.102    node2-priv.vietdba.local  node2-priv

# SCAN (Single Client Access Name — DNS khuyến dùng, không dùng hosts)
192.168.1.121  orcl-scan.vietdba.local   orcl-scan
192.168.1.122  orcl-scan.vietdba.local   orcl-scan
192.168.1.123  orcl-scan.vietdba.local   orcl-scan
EOF

# Jumbo frames cho interconnect (giảm packet overhead)
ip link set eth1 mtu 9000
echo 'MTU="9000"' >> /etc/sysconfig/network-scripts/ifcfg-eth1
# OL8/9:
nmcli con modify eth1 802-3-ethernet.mtu 9000
nmcli con up eth1
ping -M do -s 8972 10.10.1.102  # Test jumbo frames
```

### 6.2 SSH Equivalence

```bash
# Thực hiện trên TẤT CẢ nodes, cho CẢ oracle và grid users

setup_ssh_equiv() {
  local user=$1
  su - $user -c "
    mkdir -p ~/.ssh && chmod 700 ~/.ssh
    ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -q
    cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
  "
}

setup_ssh_equiv oracle
setup_ssh_equiv grid

# Copy public keys giữa nodes
for user in oracle grid; do
  for node in node1 node2; do
    su - $user -c "ssh-copy-id -i ~/.ssh/id_rsa.pub $user@$node"
  done
done

# Test (không được hỏi password)
su - oracle -c "ssh node2 hostname"
su - grid   -c "ssh node2 hostname"
su - oracle -c "ssh node1 hostname"
su - grid   -c "ssh node1 hostname"
```

### 6.3 ASM Disk Preparation

```bash
# Dùng oracleasm (simple) hoặc udev rules (recommended)

# Phương án 1: oracleasm
dnf install -y oracleasm-support
/usr/sbin/oracleasm configure -i
# Configure: oracle, dba, y, y
/usr/sbin/oracleasm init
/usr/sbin/oracleasm createdisk CRS1 /dev/sdb1
/usr/sbin/oracleasm createdisk CRS2 /dev/sdc1
/usr/sbin/oracleasm createdisk DATA1 /dev/sdd1
/usr/sbin/oracleasm createdisk DATA2 /dev/sde1
/usr/sbin/oracleasm listdisks

# Phương án 2: udev rules (khuyến dùng production)
# Tìm WWN của disks:
for dev in /dev/sd{b,c,d,e,f,g}; do
  echo -n "$dev -> "
  /usr/lib/udev/scsi_id -g -u -d $dev 2>/dev/null || echo "N/A"
done

# Tạo udev rules
cat > /etc/udev/rules.d/99-oracle-asm.rules << 'EOF'
# CRS diskgroup
KERNEL=="sd?1", SUBSYSTEM=="block",
  PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent",
  RESULT=="36000c29aaaaaaaaaaaaaaaaaaaaaa01",
  SYMLINK+="CRS1", OWNER="grid", GROUP="asmadmin", MODE="0660"

KERNEL=="sd?1", SUBSYSTEM=="block",
  PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent",
  RESULT=="36000c29aaaaaaaaaaaaaaaaaaaaaa02",
  SYMLINK+="CRS2", OWNER="grid", GROUP="asmadmin", MODE="0660"

# DATA diskgroup
KERNEL=="sd?1", SUBSYSTEM=="block",
  PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent",
  RESULT=="36000c29aaaaaaaaaaaaaaaaaaaaaa03",
  SYMLINK+="DATA1", OWNER="grid", GROUP="asmadmin", MODE="0660"
EOF

udevadm control --reload-rules
udevadm trigger --type=devices --subsystem-match=block
ls -la /dev/CRS* /dev/DATA*
```

### 6.4 Pre-install Verification

```bash
# Chạy cluvfy TRƯỚC khi install (bắt buộc)
# Grid Home phải được giải nén trước
/u01/app/grid/19.3.0/runcluvfy.sh stage -pre crsinst \
  -n node1,node2 \
  -verbose 2>&1 | tee /tmp/cluvfy_grid.log

grep -E "^Result:|FAILED|CRITICAL" /tmp/cluvfy_grid.log

# Kiểm tra disk discovery
/u01/app/grid/19.3.0/bin/asmtoolg -list  # GUI
/u01/app/grid/19.3.0/bin/asmcmd lsdsk --candidate  # CLI

# Swap check
free -g
# Swap: 0 = không đủ
# Tạo swap file tạm nếu cần:
dd if=/dev/zero of=/swapfile bs=1G count=16
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

---

## 7. QUICK REFERENCE — PRE-INSTALL CHECKLIST

```bash
#!/bin/bash
# pre_install_check.sh — Chạy trước khi install Oracle
echo "====== ORACLE PRE-INSTALL CHECK ======"

check() {
  local name=$1; local cmd=$2; local expect=$3
  result=$(eval "$cmd" 2>/dev/null)
  if [[ "$result" == *"$expect"* ]]; then
    echo "✅ $name: OK"
  else
    echo "❌ $name: FAILED ($result)"
  fi
}

echo "--- OS ---"
check "Kernel" "uname -r" ""
echo "  Kernel: $(uname -r)"
check "RAM >= 2GB" "free -m | awk '/Mem/{print ($2 >= 2000)}'" "1"
check "/tmp >= 1GB" "df /tmp | awk 'NR==2{print ($4 >= 1048576)}'" "1"
check "SELinux Permissive" "getenforce" "Permissive\|Disabled"

echo "--- USERS ---"
id oracle 2>/dev/null && echo "✅ oracle user exists" || echo "❌ oracle user missing"
id grid   2>/dev/null && echo "✅ grid user exists"   || echo "ℹ️ grid user: not needed for single instance"

echo "--- HUGEPAGES ---"
HP=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
THP=$(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null)
[[ $HP -gt 0 ]] && echo "✅ HugePages: $HP pages" || echo "⚠️ HugePages: 0 (consider enabling)"
[[ "$THP" == *"[never]"* ]] && echo "✅ THP: disabled" || echo "❌ THP: ENABLED (disable for production!)"

echo "--- PACKAGES ---"
for pkg in glibc libaio libstdc++ ksh; do
  rpm -q $pkg &>/dev/null && echo "✅ $pkg" || echo "❌ $pkg MISSING"
done

echo "--- DIRECTORIES ---"
for dir in /u01/app/oracle /u01/app/oraInventory /u01/oradata; do
  [[ -d $dir ]] && echo "✅ $dir" || echo "❌ $dir MISSING"
done

echo "======================================"
```

---

**Tài liệu tham khảo:**
- Oracle Database Installation Guide 19c for Linux (docs.oracle.com)
- Oracle RAC Installation Guide (MOS Note 1271135.1)  
- Oracle HugePages Setup Guide (MOS Note 361323.1)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
