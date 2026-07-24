---
name: oracle-install-single-instance
description: >
  Cài đặt Oracle Database Single Instance chi tiết.
  Kích hoạt khi hỏi về: cài Oracle Single Instance, install Oracle 19c,
  Oracle silent install, runInstaller Oracle, response file Oracle,
  DBCA create database, tạo database Oracle, Oracle 11g install,
  Oracle 12c install, Oracle 19c install single, Oracle 21c install,
  Oracle 23ai install, Oracle 26ai install, dbhome_1,
  orainstRoot.sh root.sh, software only install Oracle,
  create DB DBCA silent, general purpose template Oracle,
  CDB create database, PDB create first, post install validation.
---

# SK01-02 · Cài đặt Oracle Database Single Instance

**Phạm vi:** Oracle 11g R2 → 26ai | Linux RHEL/OL  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. DOWNLOAD & EXTRACT

```bash
# Oracle 19c (19.3.0) — LINUX.X64_193000_db_home.zip
# Từ: edelivery.oracle.com hoặc support.oracle.com (MOS)

# Tạo ORACLE_HOME và giải nén VÀO THƯ MỤC ĐÓ (khác 18c trở về trước)
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
mkdir -p $ORACLE_HOME
cd $ORACLE_HOME
unzip -q /opt/install/LINUX.X64_193000_db_home.zip

# Oracle 21c
mkdir -p /u01/app/oracle/product/21.3.0/dbhome_1
cd /u01/app/oracle/product/21.3.0/dbhome_1
unzip -q /opt/install/LINUX.X64_213000_db_home.zip

# Oracle 11g R2 — giải nén 2 files rồi chạy installer
unzip p10404530_112040_Linux-x86-64_1of7.zip
unzip p10404530_112040_Linux-x86-64_2of7.zip
cd database/  # Thư mục tạo ra sau khi unzip
```

---

## 2. SILENT INSTALL — SOFTWARE ONLY

```bash
# ── Tạo response file ───────────────────────────────────
cat > /tmp/db_install_19c.rsp << 'EOF'
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

# ── Chạy installer (với oracle user) ───────────────────
su - oracle << 'INSTALL'
cd /u01/app/oracle/product/19.3.0/dbhome_1
./runInstaller -silent \
  -responseFile /tmp/db_install_19c.rsp \
  -waitforcompletion \
  -ignorePrereqFailure
INSTALL

# ── Chạy root scripts (với root) ──────────────────────
/u01/app/oraInventory/orainstRoot.sh
/u01/app/oracle/product/19.3.0/dbhome_1/root.sh

# ── Verify software install ────────────────────────────
su - oracle -c "sqlplus -V"
su - oracle -c "\$ORACLE_HOME/OPatch/opatch lsinventory | head -20"
```

---

## 3. TẠO DATABASE VỚI DBCA (SILENT)

### 3.1 Oracle 19c/21c — CDB với PDB (Khuyến dùng)

```bash
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
  -storageType FS \
  -datafileDestination /u01/oradata \
  -recoveryAreaDestination /u01/fra \
  -recoveryAreaSize 51200 \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -enableArchive true \
  -archiveLogDest /u01/arch \
  -ignorePreReqs
DBCA
```

### 3.2 Oracle 19c trên ASM

```bash
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
  -totalMemory 16384 \
  -storageType ASM \
  -diskGroupName DATA \
  -recoveryGroupName FRA \
  -asmSysPassword "Grid_2026!" \
  -redoLogFileSize 500 \
  -emConfiguration NONE \
  -enableArchive true \
  -ignorePreReqs
DBCA
```

### 3.3 Oracle 11g R2 — Non-CDB

```bash
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCL11G \
  -sid ORCL11G \
  -characterSet AL32UTF8 \
  -sysPassword "Oracle_2026!" \
  -systemPassword "Oracle_2026!" \
  -databaseType MULTIPURPOSE \
  -memoryMgmtType AUTO_SGA \
  -totalMemory 4096 \
  -storageType FS \
  -datafileDestination /u01/oradata \
  -redoLogFileSize 200 \
  -emConfiguration NONE \
  -nodeinfo localhost
```

### 3.4 DBCA Response File (phức tạp hơn)

```bash
# Khi cần nhiều options hơn, dùng response file
dbca -silent -createDatabase \
  -responseFile /tmp/dbca.rsp

cat > /tmp/dbca.rsp << 'EOF'
[CREATEDATABASE]
GDBNAME=ORCL
SID=ORCL
TEMPLATENAME=General_Purpose.dbc
CHARACTERSET=AL32UTF8
NATIONALCHARACTERSET=AL16UTF16
SYSPASSWORD=Oracle_2026!
SYSTEMPASSWORD=Oracle_2026!
DBSNMPPASSWORD=Oracle_2026!
PDBADMINPASSWORD=Oracle_2026!
CREATEASCONTAINERDATABASE=true
NUMBEROFPDBS=1
PDBNAME=ORCLPDB
STORAGETYPE=FS
DATAFILEDESTINATION=/u01/oradata
RECOVERYAREADESTINATION=/u01/fra
DATABASETYPE=MULTIPURPOSE
AUTOMATICMEMORYMANAGEMENT=FALSE
TOTALMEMORYMGMTTYPE=AUTO_SGA
TOTALMEMORY=8192
EMCONFIGURATION=NONE
ENABLEARCHIVE=true
ARCHIVELOGDEST=/u01/arch
REDOLOGFILESIZE=500
SAMPLESCHEMA=false
EOF
```

---

## 4. CẤU HÌNH SAU CÀI ĐẶT

### 4.1 /etc/oratab

```bash
# File này giúp dbstart/dbshut và oraenv
cat /etc/oratab
# Format: SID:ORACLE_HOME:Y/N (Y=auto start)

# Thêm hoặc sửa:
echo "ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y" >> /etc/oratab

# Oracle startup service (systemd)
cat > /etc/systemd/system/oracle-db.service << 'EOF'
[Unit]
Description=Oracle Database Service
After=network.target

[Service]
Type=forking
User=oracle
Group=oinstall
Environment="ORACLE_BASE=/u01/app/oracle"
Environment="ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1"
Environment="ORACLE_SID=ORCL"
ExecStart=/u01/app/oracle/product/19.3.0/dbhome_1/bin/dbstart \
  /u01/app/oracle/product/19.3.0/dbhome_1
ExecStop=/u01/app/oracle/product/19.3.0/dbhome_1/bin/dbshut \
  /u01/app/oracle/product/19.3.0/dbhome_1
TimeoutStartSec=600
TimeoutStopSec=600
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable oracle-db
systemctl start oracle-db
```

### 4.2 Listener Configuration

```bash
# listener.ora — tự tạo khi DBCA chạy
# Verify listener
lsnrctl status
lsnrctl services

# Thêm vào /etc/rc.local cho auto-start (legacy)
echo "su - oracle -c 'lsnrctl start'" >> /etc/rc.local

# Systemd service cho listener
cat > /etc/systemd/system/oracle-listener.service << 'EOF'
[Unit]
Description=Oracle Listener
After=network.target
Before=oracle-db.service

[Service]
Type=forking
User=oracle
Group=oinstall
Environment="ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1"
ExecStart=/u01/app/oracle/product/19.3.0/dbhome_1/bin/lsnrctl start
ExecStop=/u01/app/oracle/product/19.3.0/dbhome_1/bin/lsnrctl stop
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
systemctl enable oracle-listener
```

### 4.3 Post-Install Validation SQL

```sql
-- Kết nối và validate
sqlplus / as sysdba

-- 1. Instance & Database status
SELECT instance_name, host_name, version_full, status
FROM v$instance;

SELECT name, cdb, open_mode, log_mode, db_unique_name
FROM v$database;

-- 2. PDB status (nếu CDB)
SELECT con_id, name, open_mode FROM v$pdbs ORDER BY con_id;

-- 3. All components valid
SELECT comp_name, version_full, status
FROM dba_registry
ORDER BY comp_name;
-- Status phải là VALID cho tất cả

-- 4. Invalid objects (phải = 0)
SELECT COUNT(*) invalid_objects
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN');

-- 5. Alert log clean
SELECT message_text FROM v$diag_alert_ext
WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
  AND message_type IN (3,4)  -- ERROR, INCIDENT
ORDER BY originating_timestamp;

-- 6. Listener registered services
SELECT s.name, s.network_name FROM v$services s ORDER BY s.name;

-- 7. Default settings
SHOW PARAMETER sga_target;
SHOW PARAMETER pga_aggregate_target;
SHOW PARAMETER db_recovery_file_dest;
SHOW PARAMETER log_archive_dest_1;

-- 8. Test connection với user thường
CREATE USER test_user IDENTIFIED BY "Test_2026!"
  DEFAULT TABLESPACE USERS QUOTA 100M ON USERS;
GRANT CREATE SESSION TO test_user;
CONNECT test_user/"Test_2026!"@ORCL
SELECT 'Connection OK: '||USER||' @ '||INSTANCE_NAME FROM v$instance;
DROP USER test_user;
```

---

## 5. ORACLE 23ai/26ai SPECIFIC SETUP

```bash
# Oracle 23ai Free Edition (Developer/Testing)
# Dùng rpm package đơn giản hơn

# Download: oracle-database-free-23ai-1.0-1.el8.x86_64.rpm
dnf localinstall -y oracle-database-free-23ai-1.0-1.el8.x86_64.rpm

# Configure (interactive)
/etc/init.d/oracle-free-23ai configure

# Hoặc silent với password:
(echo "Oracle_2026!"; echo "Oracle_2026!") | \
  /etc/init.d/oracle-free-23ai configure

# Kết nối:
su - oracle
sqlplus sys/"Oracle_2026!"@//localhost:1521/FREE as sysdba
sqlplus sys/"Oracle_2026!"@//localhost:1521/FREEPDB1 as sysdba
```

```sql
-- 23ai/26ai: Verify new features
-- AI Vector Search
SELECT * FROM v$option WHERE parameter = 'Vector Search';

-- JSON Relational Duality
SELECT * FROM v$option WHERE parameter = 'Oracle JSON';

-- SQL Firewall
SELECT status FROM v$option WHERE parameter = 'Oracle SQL Firewall';

-- True Cache
SHOW PARAMETER enable_true_cache;

-- VECTOR data type test
CREATE TABLE vector_test (
  id     NUMBER,
  embed  VECTOR(1536)  -- 1536-dimension embedding
);
DROP TABLE vector_test;
```

---

## 6. UNINSTALL ORACLE SINGLE INSTANCE

```bash
# Bước 1: Drop database
su - oracle << 'EOF'
dbca -silent -deleteDatabase \
  -sourceDB ORCL \
  -sysDBAUserName sys \
  -sysDBAPassword "Oracle_2026!"
EOF

# Bước 2: Deinstall Oracle Home
$ORACLE_HOME/deinstall/deinstall \
  -silent \
  -checkonly  # Preview trước

$ORACLE_HOME/deinstall/deinstall -silent

# Bước 3: Cleanup thủ công
rm -rf /u01/app/oracle
rm -rf /u01/app/oraInventory
rm -rf /u01/oradata /u01/fra /u01/arch
rm -f  /etc/oraInst.loc
sed -i '/^ORCL:/d' /etc/oratab

# Bước 4: Remove users/groups (optional)
userdel -r oracle
groupdel dba oinstall oper
```

---

**Tài liệu tham khảo:**
- Oracle Database Installation Guide 19c (docs.oracle.com/ladbi)
- Oracle Database 2 Day DBA (docs.oracle.com/2day-dba)
- MOS Note 885643.1 (Installing Oracle Database 19c)
- www.tranvanbinh.vn
