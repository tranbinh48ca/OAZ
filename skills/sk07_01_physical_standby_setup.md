---
name: oracle-dataguard-physical-standby
description: >
  Oracle DataGuard Physical Standby setup và cấu hình toàn diện.
  Kích hoạt khi hỏi về: DataGuard Oracle, Physical Standby Oracle,
  setup DataGuard, cấu hình DataGuard, tạo standby database,
  RMAN duplicate for standby, standby redo log Oracle,
  force logging Oracle, supplemental logging DataGuard,
  log_archive_dest_2 DataGuard, fal_server fal_client Oracle,
  standby_file_management Oracle, db_unique_name DataGuard,
  managed recovery DataGuard, RECOVER MANAGED STANDBY DATABASE,
  real-time apply DataGuard, protection mode DataGuard,
  maximum availability maximum performance maximum protection,
  DataGuard 19c setup, DataGuard RAC standby, primary standby Oracle.
---

# SK07-01 · DataGuard Physical Standby: Setup & Configuration

**Phạm vi:** Oracle 11g R2 → 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. DATAGUARD ARCHITECTURE

```
DataGuard Architecture:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRIMARY DB                          STANDBY DB
┌──────────────┐                   ┌──────────────┐
│ Application  │                   │              │
│   Writes     │                   │   Read Only  │
├──────────────┤  Redo Transport   │  (Active DG) │
│ LGWR/ARCn    │ ════════════════► │ RFS Process  │
│              │   (sync/async)    │              │
├──────────────┤                   ├──────────────┤
│ Online Redo  │                   │ Standby Redo │
│   Logs       │                   │   Logs (SRL) │
└──────────────┘                   └──────────────┘
                                           │
                                    Apply Services
                                    (MRP - Managed
                                     Recovery Process)
                                           │
                                           ▼
                                    ┌──────────────┐
                                    │  Standby     │
                                    │  Datafiles   │
                                    └──────────────┘

Protection Modes:
  MAX PROTECTION:   Sync, zero data loss, Primary stalls if can't sync
  MAX AVAILABILITY: Sync preferred, falls back to async (RECOMMENDED)
  MAX PERFORMANCE:  Async always (DEFAULT, best performance)

Standby Types:
  Physical Standby: Block-for-block copy via Redo Apply
  Logical Standby:  SQL Apply, can be opened READ WRITE for other data
  Snapshot Standby:  Temporarily writable, then revert to standby
```

---

## 2. PRE-REQUISITES VÀ CHUẨN BỊ PRIMARY

```sql
-- ── Bước 1: Kiểm tra Archivelog Mode ──────────────────────
SELECT log_mode FROM v$database;
-- Phải là ARCHIVELOG

-- Nếu chưa, enable:
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- ── Bước 2: Force Logging (BẮT BUỘC cho DataGuard) ────────
ALTER DATABASE FORCE LOGGING;
SELECT force_logging FROM v$database;
-- Phải là YES (ngăn NOLOGGING operations gây mất sync)

-- ── Bước 3: Standby Redo Logs (SRL) ───────────────────────
-- Số lượng SRL = số Online Redo Log groups + 1 (PER THREAD nếu RAC)
SELECT thread#, COUNT(*) online_groups
FROM v$log GROUP BY thread#;

-- Tạo Standby Redo Logs (cùng size với Online Redo Logs)
ALTER DATABASE ADD STANDBY LOGFILE GROUP 10
  ('+DATA','+FRA') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 11
  ('+DATA','+FRA') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 12
  ('+DATA','+FRA') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 13
  ('+DATA','+FRA') SIZE 500M;  -- N+1 groups

-- Verify
SELECT group#, thread#, sequence#, bytes/1024/1024 size_mb, status
FROM v$standby_log ORDER BY group#;

-- ── Bước 4: Static Listener Entry (cần cho RFS connection) ──
-- listener.ora trên Primary - thêm static registration:
cat >> $ORACLE_HOME/network/admin/listener.ora << 'EOF'
SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = ORCL_DGMGRL)
      (ORACLE_HOME = /u01/app/oracle/product/19.3.0/dbhome_1)
      (SID_NAME = ORCL)
    )
  )
EOF
lsnrctl reload

-- ── Bước 5: TNS entries (cả Primary và Standby) ──────────
cat >> $TNS_ADMIN/tnsnames.ora << 'EOF'
ORCL =
  (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=primary-server)(PORT=1521))
   (CONNECT_DATA=(SERVICE_NAME=ORCL)))

ORCL_STB =
  (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=standby-server)(PORT=1521))
   (CONNECT_DATA=(SERVICE_NAME=ORCL_STB)))
EOF

-- ── Bước 6: Password File (phải GIỐNG HỆT) ───────────────
-- Copy password file từ Primary sang Standby:
-- scp $ORACLE_HOME/dbs/orapwORCL oracle@standby:$ORACLE_HOME/dbs/orapwORCL_STB
```

---

## 3. CẤU HÌNH PRIMARY DATABASE

```sql
-- ── Set DB_UNIQUE_NAME (phải UNIQUE giữa Primary/Standby) ──
SHOW PARAMETER db_unique_name;
-- Nếu chưa set: ALTER SYSTEM SET db_unique_name=ORCL_PRIMARY SCOPE=SPFILE;

-- ── DataGuard Configuration Parameters ────────────────────
ALTER SYSTEM SET log_archive_config =
  'DG_CONFIG=(ORCL_PRIMARY,ORCL_STB)' SCOPE=BOTH;

-- Destination 1: Local archive (bắt buộc)
ALTER SYSTEM SET log_archive_dest_1 =
  'LOCATION=USE_DB_RECOVERY_FILE_DEST
   VALID_FOR=(ALL_LOGFILES,ALL_ROLES)
   DB_UNIQUE_NAME=ORCL_PRIMARY' SCOPE=BOTH;

-- Destination 2: Remote standby
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB ASYNC
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=ORCL_STB' SCOPE=BOTH;

ALTER SYSTEM SET log_archive_dest_state_1 = ENABLE SCOPE=BOTH;
ALTER SYSTEM SET log_archive_dest_state_2 = ENABLE SCOPE=BOTH;

-- FAL (Fetch Archive Log) settings — gap resolution
ALTER SYSTEM SET fal_server = 'ORCL_STB' SCOPE=BOTH;

-- Standby file management — tự động thêm datafile mới
ALTER SYSTEM SET standby_file_management = 'AUTO' SCOPE=BOTH;

-- Convert paths nếu Standby dùng path khác
ALTER SYSTEM SET db_file_name_convert =
  '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/' SCOPE=SPFILE;
ALTER SYSTEM SET log_file_name_convert =
  '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/' SCOPE=SPFILE;

-- ── Verify config ──────────────────────────────────────────
SELECT dest_id, status, target, archiver, schedule,
       destination, error
FROM v$archive_dest
WHERE status != 'INACTIVE';
```

---

## 4. TẠO PHYSICAL STANDBY (RMAN ACTIVE DUPLICATE)

```bash
# ── Trên Standby server: chuẩn bị môi trường ──────────────
mkdir -p /u01/oradata/ORCL_STB
mkdir -p /u01/fra/ORCL_STB
mkdir -p /u01/app/oracle/admin/ORCL_STB/adump

# Tạo minimal pfile
cat > $ORACLE_HOME/dbs/initORCL_STB.ora << 'EOF'
db_name=ORCL
db_unique_name=ORCL_STB
EOF

# Tạo password file (hoặc copy từ Primary)
orapwd file=$ORACLE_HOME/dbs/orapwORCL_STB password="Oracle_2026!" force=y

# Startup NOMOUNT
export ORACLE_SID=ORCL_STB
sqlplus / as sysdba << 'EOF'
STARTUP NOMOUNT PFILE='$ORACLE_HOME/dbs/initORCL_STB.ora';
EOF

# ── RMAN Active Duplicate (chạy từ Standby hoặc Primary) ──
rman target sys/"Oracle_2026!"@ORCL \
     auxiliary sys/"Oracle_2026!"@ORCL_STB << 'EOF'

DUPLICATE TARGET DATABASE FOR STANDBY
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT
      'ORCL_PRIMARY','ORCL_STB',
      '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/'
    SET DB_UNIQUE_NAME = 'ORCL_STB'
    SET FAL_SERVER     = 'ORCL_PRIMARY'
    SET LOG_ARCHIVE_CONFIG = 'DG_CONFIG=(ORCL_PRIMARY,ORCL_STB)'
    SET LOG_ARCHIVE_DEST_2 =
      'SERVICE=ORCL_PRIMARY ASYNC
       VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
       DB_UNIQUE_NAME=ORCL_PRIMARY'
    SET STANDBY_FILE_MANAGEMENT = 'AUTO'
    SET CONTROL_FILES =
      '/u01/oradata/ORCL_STB/control01.ctl',
      '/u01/fra/ORCL_STB/control02.ctl'
    SET AUDIT_FILE_DEST = '/u01/app/oracle/admin/ORCL_STB/adump'
    SET LOG_ARCHIVE_MAX_PROCESSES = '4'
  NOFILENAMECHECK
  DORECOVER;   -- Tự động bắt đầu Managed Recovery

EOF
```

---

## 5. START MANAGED RECOVERY

```sql
-- ── Bắt đầu Real-time Apply ────────────────────────────────
-- Chạy trên Standby
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;
-- USING CURRENT LOGFILE: real-time apply từ standby redo logs
-- DISCONNECT: chạy background, không block session

-- ── Kiểm tra apply đang chạy ───────────────────────────────
SELECT process, status, sequence#, block#, blocks
FROM v$managed_standby
ORDER BY process;

-- Cancel managed recovery (khi cần maintenance)
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;

-- Resume sau khi cancel
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;
```

---

## 6. POST-SETUP VALIDATION

```sql
-- ── Kiểm tra trạng thái Standby ───────────────────────────
SELECT name, db_unique_name, database_role, open_mode,
       protection_mode, protection_level
FROM v$database;

-- Apply lag và transport lag
SELECT name, value, datum_time
FROM v$dataguard_stats
WHERE name IN ('apply lag','transport lag','estimated startup time');

-- ── Test log shipping ─────────────────────────────────────
-- Trên Primary:
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG CURRENT;

-- Trên Standby: verify sequence được apply
SELECT thread#, sequence#, applied, first_time, next_time
FROM v$archived_log
WHERE thread# = 1
ORDER BY sequence# DESC
FETCH FIRST 10 ROWS ONLY;

-- ── Kiểm tra gaps ─────────────────────────────────────────
SELECT thread#, low_sequence#, high_sequence#
FROM v$archive_gap;
-- Empty result = no gaps (GOOD!)

-- ── Compare datafile counts ───────────────────────────────
-- Primary:
SELECT COUNT(*) FROM v$datafile;
-- Standby (phải giống nhau):
SELECT COUNT(*) FROM v$datafile;
```

---

## 7. ENABLE FLASHBACK CHO STANDBY (Recommended)

```sql
-- Cho phép Flashback Database trên Standby (dùng cho switchback)
ALTER DATABASE FLASHBACK ON;

SELECT flashback_on FROM v$database;

-- Set flashback retention
ALTER SYSTEM SET db_flashback_retention_target = 1440 SCOPE=BOTH;  -- 24h
```

---

**Tài liệu tham khảo:**
- Oracle Data Guard Concepts and Administration 19c
- Oracle Data Guard Broker (cho quản lý dễ hơn — xem SK07-04)
- MOS Note 1265700.1 (DataGuard Best Practices)
- www.tranvanbinh.vn
