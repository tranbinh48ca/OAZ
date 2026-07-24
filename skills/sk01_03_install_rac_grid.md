---
name: oracle-install-rac-grid-infrastructure
description: >
  Cài đặt Oracle RAC và Grid Infrastructure từ A đến Z.
  Kích hoạt khi hỏi về: Oracle RAC install, Grid Infrastructure install,
  cài Oracle RAC, clusterware install, ASM RAC, SCAN listener,
  VIP RAC, interconnect RAC, gridSetup.sh, voting disk, OCR Oracle,
  CRS Oracle RAC, CRSD OCSSD CSSD, RAC 2 node install,
  RAC 3 node install, RAC database create DBCA, srvctl RAC,
  gv$instance RAC, cluvfy RAC pre-check, root.sh Grid,
  orainstRoot.sh, GI 19c install, Grid 12c 19c 21c.
---

# SK01-03 · Cài đặt Oracle Grid Infrastructure & RAC

**Phạm vi:** Oracle Grid Infrastructure + RAC 11g R2, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. KIẾN TRÚC RAC OVERVIEW

```
Shared Storage (ASM Diskgroups)
         │
         ├── CRS  Diskgroup: Voting Disk, OCR (đồng bộ cluster metadata)
         ├── DATA Diskgroup: Database Datafiles
         └── FRA  Diskgroup: Fast Recovery Area, Archive Logs

Node 1 ──────────────────────────────────── Node 2
Public:  192.168.1.101                      192.168.1.102
VIP:     192.168.1.111                      192.168.1.112
Private: 10.10.1.101 (interconnect MTU9000) 10.10.1.102
SCAN:    orcl-scan (3 IPs từ DNS load balance)

Grid Infrastructure per node:
  - CSS (Cluster Sync Services) — Heartbeat, voting
  - CRS (Cluster Ready Services) — Resource management
  - OHAS (Oracle HAS) — Start/stop local resources
  - GINS (Grid Interprocess Network Service)
```

---

## 2. CÀI ĐẶT GRID INFRASTRUCTURE

### 2.1 Extract và Pre-check

```bash
# ── Giải nén Grid Home (grid user) ─────────────────
su - grid
mkdir -p /u01/app/grid/19.3.0
cd /u01/app/grid/19.3.0
unzip -q /opt/install/LINUX.X64_193000_grid_home.zip

# ── Pre-check TRƯỚC KHI INSTALL (bắt buộc) ─────────
/u01/app/grid/19.3.0/runcluvfy.sh stage -pre crsinst \
  -n node1,node2 \
  -r 19.3 \
  -verbose 2>&1 | tee /tmp/cluvfy_grid_pre.log

# Review và fix failed checks
grep -E "FAILED|CRITICAL|WARNING" /tmp/cluvfy_grid_pre.log | head -30

# Common failures và fix:
# - "NTP offset" → sync chrony
# - "SSH equivalence" → setup ssh keys
# - "Disk permissions" → chmod 660 /dev/ASM*, chown grid:asmadmin
# - "Packages missing" → dnf install
# - "SCAN resolution" → fix DNS hoặc /etc/hosts
```

### 2.2 Response File Grid 19c

```bash
cat > /tmp/grid_install_19c.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_crsinstall_response_schema_v19.0.0

# Inventory
INVENTORY_LOCATION=/u01/app/oraInventory
SELECTED_LANGUAGES=en

# Installation Option
oracle.install.option=CRS_CONFIG
ORACLE_BASE=/u01/app/grid

# OS Groups
oracle.install.asm.OSDBA=asmdba
oracle.install.asm.OSOPER=asmoper
oracle.install.asm.OSASM=asmadmin

# Cluster Configuration
oracle.install.crs.config.clusterName=orcl-cluster
oracle.install.crs.config.clusterNodes=node1:node1-vip:HUB,node2:node2-vip:HUB
oracle.install.crs.config.ClusterType=STANDARD

# SCAN
oracle.install.crs.config.scanName=orcl-scan.vietdba.local
oracle.install.crs.config.scanPort=1521

# Network Interfaces: name:subnet:role (1=public,5=private,3=ASM)
oracle.install.crs.config.networkInterfaceList=eth0:192.168.1.0:1,eth1:10.10.1.0:5

# Storage
oracle.install.crs.config.storageOption=LOCAL_ASM_STORAGE

# ASM Configuration
oracle.install.asm.diskGroup.name=CRS
oracle.install.asm.diskGroup.redundancy=NORMAL
oracle.install.asm.diskGroup.AUSize=4
oracle.install.asm.diskGroup.disks=/dev/CRS1,/dev/CRS2
oracle.install.asm.diskGroup.diskDiscoveryString=/dev/CRS*,/dev/DATA*,/dev/FRA*
oracle.install.asm.monitorPassword=Grid_2026!
oracle.install.asm.storageOption=ASM

# Ignore prerequisites
DECLINE_SECURITY_UPDATES=true
EOF
```

### 2.3 Chạy Grid Installer

```bash
su - grid << 'INSTALL'
/u01/app/grid/19.3.0/gridSetup.sh \
  -silent \
  -responseFile /tmp/grid_install_19c.rsp \
  -ignorePrereqFailure 2>&1 | tee /tmp/grid_install.log
INSTALL

# Theo dõi log
tail -f /tmp/grid_install.log

# Khi installer yêu cầu chạy root scripts:
# Node 1 (chạy với root, đợi xong):
/u01/app/oraInventory/orainstRoot.sh
/u01/app/grid/19.3.0/root.sh
# Sau khi node1 hoàn thành root.sh → Node 2:
# ssh root@node2 "/u01/app/oraInventory/orainstRoot.sh"
# ssh root@node2 "/u01/app/grid/19.3.0/root.sh"

# Confirm installer (nếu chạy foreground)
# [ENTER] khi được yêu cầu
```

### 2.4 Verify Grid Installation

```bash
# Cluster status
crsctl stat res -t
crsctl check cluster -all
crsctl check crs

# SCAN
srvctl status scan
srvctl config  scan
# SCAN IPs phải có 3 addresses nếu DNS cấu hình đúng

# ASM CRS diskgroup
su - grid -c "asmcmd lsdg"
# CRS diskgroup phải MOUNTED

# Verify từ mọi nodes
crsctl query css votedisk   # Voting disks
ocrcheck                    # OCR integrity
clsecho -n node1 -m hello   # Cluster messaging test
```

---

## 3. ADD MORE ASM DISKGROUPS

```bash
# Sau khi Grid install, tạo thêm DATA và FRA diskgroups
su - grid -c "
asmca -silent -createDiskGroup \
  -diskGroupName DATA \
  -disk '/dev/DATA1,/dev/DATA2' \
  -redundancy EXTERNAL \
  -au_size 4 \
  -compatible.asm 19.0 \
  -compatible.rdbms 19.0
"

su - grid -c "
asmca -silent -createDiskGroup \
  -diskGroupName FRA \
  -disk '/dev/FRA1' \
  -redundancy EXTERNAL \
  -au_size 4 \
  -compatible.asm 19.0 \
  -compatible.rdbms 19.0
"

# Verify
su - grid -c "asmcmd lsdg"
```

---

## 4. CÀI ĐẶT ORACLE DATABASE SOFTWARE (RAC)

```bash
# RAC DB software phải cài trên TẤT CẢ nodes
# Từ 12c: có thể chạy installer 1 lần, tự propagate sang nodes khác

# Response file Oracle DB for RAC
cat > /tmp/db_rac_19c.rsp << 'EOF'
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
oracle.install.db.rac.serverpoolCardinality=0
DECLINE_SECURITY_UPDATES=true
EOF

# Install (từ node1, oracle user)
su - oracle << 'INSTALL'
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1
cd /u01/app/oracle/product/19.3.0/dbhome_1
unzip -q /opt/install/LINUX.X64_193000_db_home.zip

./runInstaller -silent \
  -responseFile /tmp/db_rac_19c.rsp \
  -waitforcompletion \
  -ignorePrereqFailure
INSTALL

# Root scripts (CẢ HAI nodes, KHÔNG cần đợi thứ tự như Grid)
/u01/app/oracle/product/19.3.0/dbhome_1/root.sh
# ssh root@node2 "/u01/app/oracle/product/19.3.0/dbhome_1/root.sh"
```

---

## 5. TẠO RAC DATABASE

### 5.1 DBCA Silent RAC Database

```bash
# Tạo RAC CDB với PDB
su - oracle << 'DBCA'
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL \
  -sid ORCL \
  -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -sysPassword "Oracle_2026!" \
  -systemPassword "Oracle_2026!" \
  -createAsContainerDatabase true \
  -numberOfPdbs 1 \
  -pdbName ORCLPDB \
  -pdbAdminPassword "Oracle_2026!" \
  -databaseType MULTIPURPOSE \
  -automaticMemoryManagement false \
  -totalMemory 8192 \
  -storageType ASM \
  -asmSysPassword "Grid_2026!" \
  -diskGroupName DATA \
  -recoveryGroupName FRA \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -nodelist node1,node2 \
  -enableArchive true \
  -ignorePreReqs
DBCA
```

### 5.2 Verify RAC Database

```bash
# Cluster resources
srvctl status database  -d ORCL
srvctl status instance  -d ORCL -i ORCL1
srvctl status instance  -d ORCL -i ORCL2
srvctl status service   -d ORCL
srvctl status listener
srvctl status scan
srvctl status scan_listener
srvctl config  database -d ORCL
```

```sql
-- Verify từ SQL (kết nối qua SCAN)
sqlplus sys/"Oracle_2026!"@orcl-scan:1521/ORCL as sysdba

-- Tất cả instances
SELECT inst_id, instance_name, host_name, status,
       database_status
FROM gv$instance
ORDER BY inst_id;

-- Database info
SELECT name, cdb, open_mode, log_mode, cluster_database
FROM v$database;

-- Services registered
SELECT inst_id, name, network_name FROM gv$services
ORDER BY inst_id, name;

-- Interconnect
SELECT inst_id, name, ip_address FROM gv$cluster_interconnects;

-- GCS/GES (Cache Fusion health)
SELECT inst_id,
       gc_cr_blocks_received, gc_current_blocks_received,
       gc_cr_blocks_served,   gc_current_blocks_served
FROM gv$sysstat
WHERE name IN (
  'gc cr blocks received','gc current blocks received',
  'gc cr blocks served','gc current blocks served')
ORDER BY inst_id;
```

---

## 6. RAC MANAGEMENT COMMANDS

```bash
# ── Database start/stop ──────────────────────────────
srvctl start  database -d ORCL
srvctl stop   database -d ORCL -stopoption immediate
srvctl restart database -d ORCL

# ── Instance per node ───────────────────────────────
srvctl start  instance -d ORCL -node node1
srvctl stop   instance -d ORCL -node node2 -stopoption abort

# ── Cluster resources ───────────────────────────────
crsctl stat res -t                # Tất cả resources
crsctl stat res ora.ORCL.db -v   # Verbose 1 resource
crsctl start  res ora.ORCL.db    # Start manually
crsctl stop   res ora.ORCL.db

# ── ASM ─────────────────────────────────────────────
srvctl status asm
srvctl start  asm -node node1
asmcmd lsdg              # List diskgroups
asmcmd lsdsk -G DATA     # List disks in DATA

# ── Cluster management ───────────────────────────────
crsctl check crs               # Health check
crsctl stop  crs               # Stop Clusterware (1 node)
crsctl start crs
crsctl stop  cluster -all      # Stop ALL nodes (cẩn thận!)

# ── OCR & Voting ────────────────────────────────────
ocrcheck                       # OCR integrity
ocrconfig -showbackup          # OCR backup list
crsctl query css votedisk      # Voting disk status
```

---

**Tài liệu tham khảo:**
- Oracle Grid Infrastructure Installation Guide 19c
- Oracle RAC Administration Guide 19c
- MOS Note 1053147.1 (RAC Checklist 19c)
- www.tranvanbinh.vn
