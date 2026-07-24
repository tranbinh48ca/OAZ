---
name: oracle-install-patch-upgrade
description: >
  Hướng dẫn chuyên sâu về cài đặt, patching, upgrading và migration Oracle Database
  (Single Instance và RAC) từ 11g đến 26ai. Kích hoạt khi người dùng hỏi về:
  cài đặt Oracle, install Oracle, setup database, OPatch, patch Oracle, CPU patch,
  upgrade Oracle, nâng cấp database, DBUA, AutoUpgrade, migration database,
  DataPump expdp impdp, RMAN duplicate, uninstall Oracle, silent install,
  Grid Infrastructure, Oracle 19c install, Oracle 21c, Oracle 23ai, Oracle 26ai.
  Ưu tiên dùng skill này trước khi trả lời trực tiếp — luôn cung cấp steps đầy đủ,
  commands thực tế, pre-check và post-validation.
---

# SK01 · Cài đặt · Patching · Upgrading · Migration Oracle Database

**Phạm vi:** Oracle 11g R2, 12c, 18c, 19c, 21c, 23ai, 26ai — Single Instance và RAC  
**Platform:** Linux (RHEL/OL/SLES), Solaris, AIX  
**Tác giả tham khảo:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. CHUẨN BỊ MÔI TRƯỜNG (Pre-Installation)

### 1.1 OS Requirements — Linux

```bash
# Kiểm tra kernel version
uname -r  # RHEL 8: 4.18+, RHEL 7: 3.10+

# Packages bắt buộc (RHEL/OL 8)
dnf install -y bc binutils elfutils-libelf elfutils-libelf-devel \
  fontconfig-devel glibc glibc-devel ksh libaio libaio-devel \
  libXrender libXrender-devel libX11 libXau libXi libXtst \
  libgcc libstdc++ libstdc++-devel libxcb make net-tools \
  nfs-utils python python-configshell python-rtslib \
  smartmontools sysstat targetcli

# Kernel parameters — /etc/sysctl.conf
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = 2097152
kernel.shmmax = 4294967295    # >= physical RAM / 2
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576

# Apply
sysctl -p

# Limits — /etc/security/limits.conf
oracle soft nofile 1024
oracle hard nofile 65536
oracle soft nproc 16384
oracle hard nproc 16384
oracle soft stack 10240
oracle hard stack 32768
oracle hard memlock unlimited
oracle soft memlock unlimited

# HugePages (tính theo SGA size)
# Ví dụ SGA = 16GB: hugepages = (16*1024) / 2 = 8192
echo "vm.nr_hugepages = 8192" >> /etc/sysctl.conf
sysctl -p
```

### 1.2 User, Group, Directory

```bash
# Tạo groups và user
groupadd -g 54321 oinstall
groupadd -g 54322 dba
groupadd -g 54323 oper
groupadd -g 54324 backupdba
groupadd -g 54325 dgdba
groupadd -g 54326 kmdba
groupadd -g 54327 racdba
groupadd -g 54328 asmadmin
groupadd -g 54329 asmdba

useradd -u 54321 -g oinstall -G dba,oper,backupdba,dgdba,kmdba,racdba \
  -m -d /home/oracle -s /bin/bash oracle

# Directories
mkdir -p /u01/app/oracle/product/19.3.0/dbhome_1
mkdir -p /u01/app/oraInventory
chown -R oracle:oinstall /u01
chmod -R 775 /u01

# .bash_profile cho oracle user
cat >> /home/oracle/.bash_profile << 'EOF'
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=$ORACLE_BASE/product/19.3.0/dbhome_1
export ORACLE_SID=ORCL
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:/lib:/usr/lib
export CLASSPATH=$ORACLE_HOME/jlib:$ORACLE_HOME/rdbms/jlib
EOF
```

### 1.3 Pre-Check với cluvfy (RAC)

```bash
# Pre-check trước khi install Grid Infrastructure
$GRID_HOME/runcluvfy.sh stage -pre crsinst -n node1,node2 \
  -r 19.3 -verbose

# Pre-check trước khi install Oracle DB
$GRID_HOME/runcluvfy.sh stage -pre dbinst -n node1,node2 \
  -d $ORACLE_HOME -verbose
```

---

## 2. CÀI ĐẶT ORACLE SINGLE INSTANCE

### 2.1 Silent Install (19c/21c)

```bash
# Giải nén installer
cd /u01/app/oracle/product/19.3.0/dbhome_1
unzip -q /path/to/LINUX.X64_193000_db_home.zip

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

# Chạy install (software only)
./runInstaller -silent -responseFile /tmp/db_install.rsp \
  -ignorePrereqFailure -skipPrereqs

# Chạy root scripts sau khi install
/u01/app/oraInventory/orainstRoot.sh
/u01/app/oracle/product/19.3.0/dbhome_1/root.sh
```

### 2.2 Tạo Database bằng DBCA (Silent)

```bash
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL -sid ORCL \
  -responseFile NO_VALUE \
  -characterSet AL32UTF8 \
  -sysPassword Oracle_1234 \
  -systemPassword Oracle_1234 \
  -createAsContainerDatabase true \
  -numberOfPdbs 1 \
  -pdbName ORCLPDB \
  -pdbAdminPassword Oracle_1234 \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType auto_sga \
  -totalMemory 4096 \
  -storageType FS \
  -datafileDestination /u01/app/oracle/oradata \
  -redoLogFileSize 200 \
  -emConfiguration NONE \
  -ignorePreReqs
```

---

## 3. CÀI ĐẶT ORACLE GRID INFRASTRUCTURE + RAC

### 3.1 Chuẩn bị thêm cho RAC

```bash
# SSH equivalence giữa các nodes
ssh-keygen -t rsa
# Copy public key sang node2
ssh-copy-id oracle@node2
ssh-copy-id grid@node2

# Shared storage — ASM disks (udev rules)
cat >> /etc/udev/rules.d/99-oracle-asmdevices.rules << 'EOF'
KERNEL=="sd?1", SUBSYSTEM=="block", \
  PROGRAM=="/usr/lib/udev/scsi_id -g -u -d /dev/$parent", \
  RESULT=="3600508e00000000abcd1234", \
  NAME="DATA1", OWNER="grid", GROUP="asmadmin", MODE="0660"
EOF
udevadm control --reload-rules && udevadm trigger

# Kiểm tra disk
ls -la /dev/DATA*
```

### 3.2 Install Grid Infrastructure

```bash
# Response file Grid
cat > /tmp/grid_install.rsp << 'EOF'
oracle.install.responseFileVersion=/oracle/install/rspfmt_crsinstall_response_schema_v19.0.0
INVENTORY_LOCATION=/u01/app/oraInventory
oracle.install.option=CRS_CONFIG
ORACLE_BASE=/u01/app/grid
oracle.install.asm.OSDBA=asmdba
oracle.install.asm.OSOPER=asmoper
oracle.install.asm.OSASM=asmadmin
oracle.install.crs.config.scanName=orcl-scan.vietdba.local
oracle.install.crs.config.scanPort=1521
oracle.install.crs.config.clusterName=orcl-cluster
oracle.install.crs.config.clusterNodes=node1:node1-vip,node2:node2-vip
oracle.install.crs.config.networkInterfaceList=eth0:192.168.1.0:1,eth1:10.10.1.0:5
oracle.install.asm.diskGroup.name=CRS
oracle.install.asm.diskGroup.redundancy=NORMAL
oracle.install.asm.diskGroup.AUSize=4
oracle.install.asm.diskGroup.disks=/dev/CRS1,/dev/CRS2
oracle.install.asm.diskGroup.diskDiscoveryString=/dev/CRS*
oracle.install.asm.monitorPassword=Grid_1234
DECLINE_SECURITY_UPDATES=true
EOF

cd $GRID_HOME
./gridSetup.sh -silent -responseFile /tmp/grid_install.rsp

# Root scripts (chạy trên TẤT CẢ nodes)
# Node 1 trước:
/u01/app/oraInventory/orainstRoot.sh
/u01/app/grid/root.sh
# Node 2:
/u01/app/oraInventory/orainstRoot.sh
/u01/app/grid/root.sh

# Kiểm tra cluster
crsctl stat res -t
```

---

## 4. PATCHING

### 4.1 OPatch — Patch đơn lẻ

```bash
# Kiểm tra OPatch version (cần >= yêu cầu của patch)
$ORACLE_HOME/OPatch/opatch version

# Cập nhật OPatch nếu cần
cd $ORACLE_HOME
unzip -q /path/to/p6880880_190000_Linux-x86-64.zip -d .

# Pre-check conflict
cd /path/to/PATCH_DIR
$ORACLE_HOME/OPatch/opatch prereq CheckConflictAgainstOHWithDetail \
  -ph ./

# Apply patch (DB đang up vẫn apply được với rolling)
# 1. Shutdown DB (non-RAC)
sqlplus / as sysdba << 'EOF'
shutdown immediate
EOF

# 2. Apply
$ORACLE_HOME/OPatch/opatch apply -silent

# 3. Startup
sqlplus / as sysdba << 'EOF'
startup
@$ORACLE_HOME/rdbms/admin/catbundle.sql psu apply
EOF

# Kiểm tra
$ORACLE_HOME/OPatch/opatch lsinventory | grep -i "patch"
```

### 4.2 OPatchAuto — RAC Rolling Patch (không downtime)

```bash
# Download patch (Quarterly Release Update)
# Ví dụ: patch 35943157 (19.21 RU)

# Pre-check
$ORACLE_HOME/OPatch/opatchauto apply \
  /path/to/35943157 -analyze

# Apply rolling (Grid + DB cùng lúc, rolling từng node)
$ORACLE_HOME/OPatch/opatchauto apply \
  /path/to/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME

# Rollback nếu cần
$ORACLE_HOME/OPatch/opatchauto rollback \
  /path/to/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME
```

### 4.3 Kiểm tra Patch đã apply

```bash
$ORACLE_HOME/OPatch/opatch lsinventory -detail -oh $ORACLE_HOME
# Hoặc từ SQL
SELECT patch_id, patch_uid, version, action, action_time
FROM   sys.registry$history
ORDER  BY action_time DESC;
```

---

## 5. UPGRADING

### 5.1 AutoUpgrade (Oracle 19c+) — Recommended

```bash
# Bước 1: Phân tích (Analyze mode)
java -jar $ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode analyze \
  -config /tmp/autoupgrade.cfg

# Config file
cat > /tmp/autoupgrade.cfg << 'EOF'
global.autoupg_log_dir=/u01/autoupgrade_logs

upg1.dbname=ORCL
upg1.start_time=NOW
upg1.source_home=/u01/app/oracle/product/11.2.0/dbhome_1
upg1.target_home=/u01/app/oracle/product/19.3.0/dbhome_1
upg1.sid=ORCL
upg1.log_dir=/u01/autoupgrade_logs/ORCL
upg1.upgrade_node=localhost
upg1.target_version=19
upg1.run_utluppkg=yes
EOF

# Bước 2: Fixups (sửa issues trước upgrade)
java -jar $ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode fixups -config /tmp/autoupgrade.cfg

# Bước 3: Deploy (upgrade thực sự)
java -jar $ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode deploy -config /tmp/autoupgrade.cfg

# Monitor tiến trình
java -jar $ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode deploy -config /tmp/autoupgrade.cfg &
# Trong cửa sổ khác:
lsj          # list jobs
status -job 1  # status của job
```

### 5.2 Post-Upgrade Validation

```bash
# Chạy post-upgrade fixup script
sqlplus / as sysdba << 'EOF'
@$ORACLE_HOME/rdbms/admin/utluppkg.sql
@$ORACLE_HOME/rdbms/admin/catuppst.sql
EOF

# Compile invalid objects
sqlplus / as sysdba << 'EOF'
@$ORACLE_HOME/rdbms/admin/utlrp.sql
EOF

# Kiểm tra version và components
SELECT comp_name, version, status FROM dba_registry ORDER BY 1;
SELECT * FROM v$instance;

# Timezone upgrade nếu cần
SELECT * FROM v$timezone_file;
```

---

## 6. MIGRATION

### 6.1 DataPump — expdp/impdp

```bash
# Export toàn bộ schema
expdp system/password@source_db \
  schemas=SCOTT,HR,SALES \
  directory=DATA_PUMP_DIR \
  dumpfile=migration_%U.dmp \
  logfile=export.log \
  parallel=4 \
  compression=ALL \
  exclude=STATISTICS

# Import vào target DB
impdp system/password@target_db \
  schemas=SCOTT,HR,SALES \
  directory=DATA_PUMP_DIR \
  dumpfile=migration_%U.dmp \
  logfile=import.log \
  parallel=4 \
  remap_tablespace=OLD_TBS:NEW_TBS \
  transform=SEGMENT_ATTRIBUTES:N

# Network link (không cần dumpfile)
impdp system/password@target_db \
  schemas=SCOTT \
  network_link=SOURCE_DBLINK \
  logfile=import_network.log \
  parallel=4
```

### 6.2 RMAN Active Duplicate (zero-downtime copy)

```bash
# Trên target server, chạy với RMAN:
rman target sys/password@source auxiliary sys/password@target << 'EOF'
DUPLICATE TARGET DATABASE TO target_db
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT 'source_db','target_db',
                            '/source_path','/target_path'
    SET DB_UNIQUE_NAME='target_db'
    SET LOG_ARCHIVE_DEST_1='LOCATION=/u01/arch'
    SET CONTROL_FILES='/u01/oradata/control01.ctl'
  LOGFILE
    GROUP 1 '/u01/oradata/redo01.log' SIZE 200M,
    GROUP 2 '/u01/oradata/redo02.log' SIZE 200M
  NOFILENAMECHECK;
EOF
```

### 6.3 Transportable Tablespace (TTS)

```bash
# 1. Source: Make tablespace read-only
ALTER TABLESPACE DATA_TBS READ ONLY;

# 2. Export metadata
expdp system/pwd transport_tablespaces=DATA_TBS \
  transport_full_check=y \
  dumpfile=tts_export.dmp \
  directory=DATA_PUMP_DIR

# 3. Copy datafiles và dumpfile sang target

# 4. Target: Import
impdp system/pwd dumpfile=tts_export.dmp \
  directory=DATA_PUMP_DIR \
  transport_datafiles='/u01/oradata/data_tbs01.dbf'

# 5. Target: Make read-write
ALTER TABLESPACE DATA_TBS READ WRITE;
```

---

## 7. UNINSTALL ORACLE

```bash
# Bước 1: Xóa database
dbca -silent -deleteDatabase \
  -sourceDB ORCL \
  -sysDBAUserName sys \
  -sysDBAPassword Oracle_1234

# Bước 2: Deinstall Oracle Home
$ORACLE_HOME/deinstall/deinstall \
  -silent \
  -checkonly  # preview trước

$ORACLE_HOME/deinstall/deinstall -silent

# Bước 3: Manual cleanup nếu cần
rm -rf /u01/app/oracle
rm -rf /u01/app/oraInventory
rm -f /etc/oraInst.loc
rm -f /etc/oratab
```

---

## 8. CHECKLIST PRE/POST INSTALL

### Pre-Install Checklist
- [ ] Swap space >= 2x RAM (hoặc ít nhất 16GB)
- [ ] `/tmp` >= 1GB
- [ ] Disk space: `$ORACLE_BASE` >= 7.5GB (phần mềm), data volumes
- [ ] Kernel parameters đã set
- [ ] OS limits (ulimit) đã cấu hình
- [ ] HugePages đã cấu hình (không dùng AMM khi có HugePages)
- [ ] SELinux: permissive hoặc disabled
- [ ] Firewall: port 1521 (listener), 1158 (EM), 5500 (EM Express)
- [ ] NTP sync giữa các nodes (RAC)
- [ ] SSH equivalence (RAC)

### Post-Install Checklist
- [ ] `SELECT * FROM v$instance;` — STATUS = OPEN
- [ ] `SELECT comp_name, status FROM dba_registry;` — tất cả VALID
- [ ] `lsnrctl status` — listener đang chạy
- [ ] RMAN test backup
- [ ] Alert log không có errors
- [ ] `opatch lsinventory` — patch được ghi nhận

---

## 9. TROUBLESHOOTING INSTALL PHỔ BIẾN

| Lỗi | Nguyên nhân | Fix |
|-----|-------------|-----|
| `[INS-08101] Unexpected error` | Missing package | `dnf install -y libnsl compat-libstdc++-33` |
| `ORA-01034 not available` | DB không start | Check alert log, startup manual |
| Swap insufficient | Swap nhỏ | Tạo swapfile tạm: `dd if=/dev/zero of=/swapfile bs=1G count=8` |
| `rootpre.sh` failure | Permission | Chạy với root, check `/tmp` permission |
| cluvfy SCAN failure | DNS/GNS | Config `/etc/hosts` entries cho SCAN |

---

## Tài liệu tham khảo
- Oracle DB Installation Guide: docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/
- MOS Note 1405213.1 (19c known issues)
- AutoUpgrade Guide: docs.oracle.com/en/database/oracle/oracle-database/19/upgrd/
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
