---
name: oracle-install-single-rac
description: >
  Cài đặt Oracle Database Single Instance và RAC từ A đến Z.
  Kích hoạt khi hỏi về: cài đặt Oracle, install Oracle Database,
  Oracle Single Instance, Oracle RAC install, Grid Infrastructure install,
  silent install Oracle, DBCA tạo database, oracle prerequisites,
  kernel parameters Oracle, hugepages Oracle, ASM setup,
  cluvfy pre-install check, oinstall dba group Oracle,
  oracle 11g install, oracle 12c install, oracle 19c install,
  oracle 21c install, oracle 23ai install, oracle 26ai install,
  response file Oracle install, runInstaller, gridSetup,
  Oracle Base Oracle Home, ORACLE_SID, oratab Oracle.
---

# SK01-A · Cài đặt Oracle: Single Instance & RAC

**Phạm vi:** Oracle 11g R2, 12c, 19c, 21c, 23ai, 26ai  
**Platform:** Linux (RHEL/OL 7/8/9), Solaris 11, AIX 7  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. PRE-INSTALLATION CHECKLIST

### 1.1 OS Prerequisites (RHEL/OL 8/9)

```bash
# ── Kiểm tra hardware requirements ──────────────────────
free -h          # RAM >= 2GB (min), 8GB+ production
df -h /tmp       # /tmp >= 1GB
df -h /u01       # Oracle Base >= 6.5GB software only
nproc            # CPUs
uname -r         # Kernel version

# ── Packages bắt buộc Oracle 19c/21c (RHEL/OL 8) ──────
dnf install -y bc binutils elfutils-libelf elfutils-libelf-devel \
  fontconfig-devel glibc glibc-devel ksh libaio libaio-devel \
  libXrender libXrender-devel libX11 libXau libXi libXtst libgcc \
  libstdc++ libstdc++-devel libxcb libibverbs make net-tools nfs-utils \
  smartmontools sysstat targetcli procps-ng psmisc

# Oracle 19c preinstall package (tự động set kernel params, tạo user)
dnf install -y oracle-database-preinstall-19c

# ── Kernel Parameters — /etc/sysctl.conf ──────────────
cat >> /etc/sysctl.conf << 'EOF'
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 4294967295
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048586
EOF
sysctl -p

# ── HugePages (QUAN TRỌNG — không dùng AMM khi có HugePages) ─
# Tính: SGA_TARGET(GB) * 1024 / 2  = số hugepages cần
# Ví dụ SGA 16GB: 16*1024/2 = 8192
echo "vm.nr_hugepages = 8192" >> /etc/sysctl.conf
sysctl -p

# ── Limits — /etc/security/limits.conf ────────────────
cat >> /etc/security/limits.conf << 'EOF'
oracle soft nofile 1024
oracle hard nofile 65536
oracle soft nproc 16384
oracle hard nproc 16384
oracle soft stack 10240
oracle hard stack 32768
oracle hard memlock unlimited
oracle soft memlock unlimited
EOF

# ── SELinux và Firewall ────────────────────────────────
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
# Firewall: mở port 1521, 5500 (EM Express), 7809 (GoldenGate)
firewall-cmd --permanent --add-port={1521,5500,7809}/tcp
firewall-cmd --reload
```

### 1.2 Users, Groups, Directories

```bash
# Tạo groups
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba
groupadd -g 54327 racdba
groupadd -g 54328 asmadmin
groupadd -g 54329 asmdba

# Tạo oracle user
useradd -u 54321 -g oinstall \
  -G dba,oper,backupdba,dgdba,kmdba,racdba \
  -m -d /home/oracle -s /bin/bash oracle
echo "oracle:Oracle_2026!" | chpasswd

# Tạo grid user (cho RAC/ASM)
useradd -u 54331 -g oinstall \
  -G asmadmin,asmdba,dba,racdba \
  -m -d /home/grid -s /bin/bash grid

# Directories
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1
mkdir -p /u01/app/oraInventory
mkdir -p /u01/app/grid/19.3.0                   # Grid Home
mkdir -p /u01/app/grid                           # Grid Base
chown -R oracle:oinstall /u01/app/oracle
chown -R grid:oinstall   /u01/app/grid
chown    grid:oinstall   /u01/app/oraInventory
chmod -R 775 /u01

# .bash_profile oracle user
cat >> /home/oracle/.bash_profile << 'EOF'
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export ORACLE_SID=ORCL
export NLS_DATE_FORMAT="YYYY-MM-DD HH24:MI:SS"
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
EOF

# .bash_profile grid user (RAC)
cat >> /home/grid/.bash_profile << 'EOF'
export ORACLE_BASE=/u01/app/grid
export ORACLE_HOME=/u01/app/grid/19.3.0
export PATH=$ORACLE_HOME/bin:$PATH
EOF
```

---

## 2. CÀI ĐẶT ORACLE SINGLE INSTANCE

### 2.1 Silent Install Software Only

```bash
# Giải nén Oracle installer
cd /u01/app/oracle/product/19.3.0/dbhome_1
unzip -q /opt/install/LINUX.X64_193000_db_home.zip

# Tạo response file
cat > /tmp/db_install.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=/u01/app/oraInventory
ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
ORACLE_BASE=/u01/app/oracle
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=backupdba
oracle.install.db.OSDGDBA_GROUP=dgdba
oracle.install.db.OSKMDBA_GROUP=kmdba
oracle.install.db.OSRACDBA_GROUP=racdba
SECURITY_UPDATES_VIA_MYORACLESUPPORT=false
DECLINE_SECURITY_UPDATES=true
EOF

# Chạy installer (software only)
su - oracle -c "
  cd /u01/app/oracle/product/19.3.0/dbhome_1
  ./runInstaller -silent -responseFile /tmp/db_install.rsp \
    -ignorePrereqFailure
"

# Chạy root scripts (với root)
/u01/app/oraInventory/orainstRoot.sh
/u01/app/oracle/product/19.3.0/dbhome_1/root.sh

# Verify installation
su - oracle -c "sqlplus -V"
su - oracle -c "$ORACLE_HOME/OPatch/opatch lsinventory"
```

### 2.2 Tạo Database bằng DBCA (Silent)

```bash
# Non-CDB (Oracle 11g, 12c non-CDB)
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL \
  -sid ORCL \
  -characterSet AL32UTF8 \
  -sysPassword Oracle_2026! \
  -systemPassword Oracle_2026! \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType AUTO_SGA \
  -totalMemory 4096 \
  -storageType ASM \
  -asmSysPassword Grid_2026! \
  -diskGroupName DATA \
  -recoveryGroupName FRA \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -ignorePreReqs

# CDB (Oracle 12c+) với PDB
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL \
  -sid ORCL \
  -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -sysPassword Oracle_2026! \
  -systemPassword Oracle_2026! \
  -createAsContainerDatabase true \
  -numberOfPdbs 1 \
  -pdbName ORCLPDB \
  -pdbAdminPassword Oracle_2026! \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType auto_sga \
  -totalMemory 8192 \
  -storageType FS \
  -datafileDestination /u01/oradata \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -ignorePreReqs

# Post-creation validation
sqlplus / as sysdba << 'EOF'
SELECT instance_name, status, database_status FROM v$instance;
SELECT name, cdb, open_mode FROM v$database;
SELECT con_id, name, open_mode FROM v$pdbs;
EXIT;
EOF
```

---

## 3. CÀI ĐẶT ORACLE RAC

### 3.1 Pre-RAC Setup

```bash
# ── SSH Equivalence (thực hiện trên CẢ HAI nodes) ──────
# Node1:
su - grid
ssh-keygen -t rsa -N ""
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
# Copy public key sang node2:
ssh-copy-id grid@node2
ssh-copy-id grid@node1  # Chính nó
# Test:
ssh node2 date

su - oracle
ssh-keygen -t rsa -N ""
ssh-copy-id oracle@node2
ssh-copy-id oracle@node1

# ── ASM Disks — udev rules ────────────────────────────
# Tìm disk WWN
for d in /dev/sd{b,c,d,e,f}; do
  echo "$d: $(udev adm info -q all -n $d | grep 'ID_SERIAL=')"
done

cat >> /etc/udev/rules.d/99-oracle-asm.rules << 'EOF'
KERNEL=="sd?1", SUBSYSTEM=="block",
PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent",
RESULT=="3600508e0000000a96ac1a48ad2a2c3d",
NAME="CRS1", OWNER="grid", GROUP="asmadmin", MODE="0660"

KERNEL=="sd?1", SUBSYSTEM=="block",
PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent",
RESULT=="3600508e0000000b96ac1a48ad2a2c4e",
NAME="DATA1", OWNER="grid", GROUP="asmadmin", MODE="0660"
EOF
udevadm control --reload-rules
udevadm trigger
ls -la /dev/CRS1 /dev/DATA1

# ── Network check ─────────────────────────────────────
# Public:  eth0 — 192.168.1.x (app traffic)
# Private: eth1 — 10.10.1.x  (interconnect — PHẢI dùng jumbo frames)
# VIP:     eth0:1 — 192.168.1.x+10
# SCAN:    3 IPs từ DNS — orcl-scan.vietdba.local
# Set MTU 9000 cho interconnect:
ip link set eth1 mtu 9000
echo "MTU=9000" >> /etc/sysconfig/network-scripts/ifcfg-eth1
```

### 3.2 Cài Grid Infrastructure

```bash
# Giải nén Grid
cd /u01/app/grid/19.3.0
unzip -q /opt/install/LINUX.X64_193000_grid_home.zip

# Response file Grid
cat > /tmp/grid_install.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_crsinstall_response_schema_v19.0.0
INVENTORY_LOCATION=/u01/app/oraInventory
SELECTED_LANGUAGES=en
oracle.install.option=CRS_CONFIG
ORACLE_BASE=/u01/app/grid
oracle.install.asm.OSDBA=asmdba
oracle.install.asm.OSOPER=asmoper
oracle.install.asm.OSASM=asmadmin
oracle.install.crs.config.scanName=orcl-scan.vietdba.local
oracle.install.crs.config.scanPort=1521
oracle.install.crs.config.ClusterType=STANDARD
oracle.install.crs.config.clusterName=orcl-cluster
oracle.install.crs.config.clusterNodes=node1:node1-vip,node2:node2-vip
oracle.install.crs.config.networkInterfaceList=eth0:192.168.1.0:1,eth1:10.10.1.0:5
oracle.install.asm.diskGroup.name=CRS
oracle.install.asm.diskGroup.redundancy=NORMAL
oracle.install.asm.diskGroup.AUSize=4
oracle.install.asm.diskGroup.disks=/dev/CRS1,/dev/CRS2
oracle.install.asm.diskGroup.diskDiscoveryString=/dev/CRS*,/dev/DATA*
oracle.install.asm.storageOption=ASM
oracle.install.asm.monitorPassword=Grid_2026!
DECLINE_SECURITY_UPDATES=true
EOF

# Pre-check (bắt buộc trước khi install)
su - grid -c "
  /u01/app/grid/19.3.0/runcluvfy.sh stage -pre crsinst \
    -n node1,node2 -verbose 2>&1 | tee /tmp/cluvfy_precheck.log
"
grep -E "FAILED|CRITICAL" /tmp/cluvfy_precheck.log

# Install Grid (chạy với grid user, MỘT node thôi)
su - grid -c "
  /u01/app/grid/19.3.0/gridSetup.sh -silent \
    -responseFile /tmp/grid_install.rsp \
    -ignorePrereqFailure
"

# Root scripts — THỨTỰ QUAN TRỌNG:
# Node1 trước:
/u01/app/oraInventory/orainstRoot.sh
/u01/app/grid/19.3.0/root.sh
# Sau khi node1 xong → Node2:
# ssh root@node2 /u01/app/oraInventory/orainstRoot.sh
# ssh root@node2 /u01/app/grid/19.3.0/root.sh

# Verify cluster
crsctl stat res -t
crsctl check crs
srvctl status scan
```

### 3.3 Cài Oracle RAC Database

```bash
# Response file Oracle DB (RAC)
cat > /tmp/db_rac_install.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_dbinstall_response_schema_v19.0.0
oracle.install.option=INSTALL_DB_SWONLY
UNIX_GROUP_NAME=oinstall
INVENTORY_LOCATION=/u01/app/oraInventory
ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
ORACLE_BASE=/u01/app/oracle
oracle.install.db.InstallEdition=EE
oracle.install.db.OSDBA_GROUP=dba
oracle.install.db.OSOPER_GROUP=oper
oracle.install.db.OSBACKUPDBA_GROUP=backupdba
oracle.install.db.OSDGDBA_GROUP=dgdba
oracle.install.db.OSKMDBA_GROUP=kmdba
oracle.install.db.OSRACDBA_GROUP=racdba
oracle.install.db.isRACOneInstall=false
oracle.install.db.rac.serverpoolCardinality=0
DECLINE_SECURITY_UPDATES=true
EOF

# Install Oracle software trên NODE1 (propagate tự động sang node2)
su - oracle -c "
  cd /u01/app/oracle/product/19.3.0/dbhome_1
  ./runInstaller -silent -responseFile /tmp/db_rac_install.rsp
"

# Root scripts trên CẢ HAI nodes
/u01/app/oracle/product/19.3.0/dbhome_1/root.sh
# ssh root@node2 /u01/app/oracle/product/19.3.0/dbhome_1/root.sh

# Tạo RAC Database bằng DBCA
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL \
  -sid ORCL \
  -characterSet AL32UTF8 \
  -sysPassword Oracle_2026! \
  -systemPassword Oracle_2026! \
  -createAsContainerDatabase true \
  -numberOfPdbs 1 \
  -pdbName ORCLPDB \
  -pdbAdminPassword Oracle_2026! \
  -databaseType MULTIPURPOSE \
  -totalMemory 8192 \
  -storageType ASM \
  -asmSysPassword Grid_2026! \
  -diskGroupName DATA \
  -recoveryGroupName FRA \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -nodelist node1,node2 \
  -ignorePreReqs

# Verify RAC
srvctl status database -d ORCL
srvctl config database -d ORCL
SELECT inst_id, instance_name, status FROM gv$instance;
```

---

## 4. ORACLE 26ai INSTALLATION SPECIFICS

```bash
# Oracle 26ai (Database 26c AI) — New features cần setup thêm

# 1. AI Vector Search — không cần cài thêm (built-in từ 23ai)
# Kiểm tra VECTOR data type support:
SELECT * FROM v$option WHERE parameter = 'Vector Search';

# 2. True Cache setup (23ai+)
# True Cache: read-only in-memory cache gần application tier
# Cài Oracle software trên True Cache node
# Cấu hình:
ALTER SYSTEM SET enable_true_cache = TRUE SCOPE=BOTH;

# 3. JSON Relational Duality Views (23ai+)
# Không cần setup đặc biệt, tự động available

# 4. SQL Firewall (23ai+)
EXEC DBMS_SQL_FIREWALL.ENABLE;

# 5. Oracle AI Layer — vector embedding
-- Cài ONNX model cho vector embedding:
EXEC DBMS_VECTOR.LOAD_ONNX_MODEL(
  directory   => 'ONNX_MODEL_DIR',
  file_name   => 'multilingual-e5-small.onnx',
  model_name  => 'DOC_MODEL',
  metadata    => '{"function":"embedding","embeddingOutput":"embedding",
                   "input":{"input":["DATA"]}}'
);
```

---

## 5. POST-INSTALLATION VALIDATION

```bash
# ── Full validation checklist ─────────────────────────
cat > /u01/scripts/post_install_check.sh << 'SCRIPT'
#!/bin/bash
source /home/oracle/.bash_profile
echo "=== POST INSTALL VALIDATION $(date) ==="

# 1. Instance status
echo "[1] Instance Status:"
sqlplus -S / as sysdba << 'EOF'
SELECT instance_name, host_name, version, status, database_status
FROM v$instance;
SELECT name, cdb, open_mode, log_mode FROM v$database;
EOF

# 2. Components valid
echo "[2] DB Components:"
sqlplus -S / as sysdba << 'EOF'
SELECT comp_name, version, status FROM dba_registry
WHERE status != 'VALID';
-- Không có row = tất cả VALID
EOF

# 3. Listener
echo "[3] Listener:"
lsnrctl status

# 4. OPatch inventory
echo "[4] Patches installed:"
$ORACLE_HOME/OPatch/opatch lsinventory | grep -E "^Oracle|Patch"

# 5. Alert log
echo "[5] Alert log errors:"
find $ORACLE_BASE/diag -name "alert_*.log" | \
  xargs grep -E "ORA-|Error" 2>/dev/null | tail -20

echo "=== VALIDATION DONE ==="
SCRIPT
chmod +x /u01/scripts/post_install_check.sh
su - oracle /u01/scripts/post_install_check.sh
```

---

## 6. UNINSTALL ORACLE

```bash
# Bước 1: Xóa database (DBCA)
dbca -silent -deleteDatabase \
  -sourceDB ORCL \
  -sysDBAUserName sys \
  -sysDBAPassword Oracle_2026!

# Bước 2: Deinstall Oracle Home
$ORACLE_HOME/deinstall/deinstall -silent

# Bước 3: Deinstall Grid Home (RAC)
$GRID_HOME/deinstall/deinstall -silent

# Bước 4: Manual cleanup
rm -rf /u01/app/oracle
rm -rf /u01/app/oraInventory
rm -f /etc/oraInst.loc
# /etc/oratab: xóa entries liên quan
sed -i '/ORCL/d' /etc/oratab

# Bước 5: Remove ASM diskgroup labels (nếu cần tái sử dụng disks)
su - grid -c "asmcmd lsdsk"
# Nếu dùng oracleasm:
/usr/sbin/oracleasm deletedisk DATA1
/usr/sbin/oracleasm deletedisk CRS1
```

---

**Tài liệu tham khảo:**
- Oracle Database Installation Guide 19c for Linux: docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/
- Oracle Grid Infrastructure Installation Guide 19c
- MOS Note 1271135.1 (RAC Best Practices)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
