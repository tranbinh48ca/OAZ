---
name: oracle-cdb-pdb-multitenant
description: >
  Oracle Multitenant CDB/PDB Administration.
  Kích hoạt khi hỏi về: CDB Oracle, PDB Oracle, multitenant Oracle,
  Container Database, Pluggable Database, tạo PDB, create PDB,
  clone PDB, unplug PDB, plug PDB, drop PDB, open close PDB,
  PDB lockdown profile, common user CDB, local user PDB,
  CDB$ROOT, PDB$SEED, container query CDB_, v$pdbs, v$containers,
  PDB backup RMAN, PDB archivelog, PDB flashback, PDB export import,
  application container Oracle, PDB service, PDB resource plan,
  Oracle 12c multitenant, 19c CDB, shared services CDB,
  PDB snapshot carousel, thin cloning PDB.
---

# SK02-08 · Oracle CDB/PDB Multitenant Administration

**Phạm vi:** Oracle 12c, 19c, 21c, 23ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. KIẾN TRÚC MULTITENANT

```
CDB (Container Database)
│
├── CDB$ROOT     — System container (common objects, metadata)
├── PDB$SEED     — Seed PDB (template cho tạo PDB mới — READ ONLY)
├── ORCLPDB1     — Application PDB 1
├── ORCLPDB2     — Application PDB 2
└── ORCLPDB3     — Application PDB 3

Common Objects: tồn tại trong CDB$ROOT, visible từ tất cả containers
Local Objects:  chỉ tồn tại trong PDB

Connections:
  → CDB$ROOT:  connect với SID hoặc service ORCL (CDB service)
  → PDB:       connect với service ORCLPDB1 (PDB service name)
```

```sql
-- Kiểm tra có phải CDB không
SELECT cdb, name, open_mode FROM v$database;
-- cdb=YES → CDB

-- Xem tất cả containers
SELECT con_id, name, open_mode, restricted, guid
FROM v$containers
ORDER BY con_id;

-- Xem tất cả PDBs
SELECT con_id, name, open_mode, restricted
FROM v$pdbs
ORDER BY con_id;

-- Container hiện tại
SELECT sys_context('USERENV','CON_NAME') current_container,
       sys_context('USERENV','CON_ID')   container_id
FROM dual;

-- Switch container (từ CDB$ROOT)
ALTER SESSION SET CONTAINER = orclpdb1;
-- Quay lại CDB$ROOT:
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

---

## 2. QUẢN LÝ PDB

### 2.1 Tạo PDB

```sql
-- Tạo PDB từ PDB$SEED (default)
CREATE PLUGGABLE DATABASE pdb_app1
  ADMIN USER pdb_admin IDENTIFIED BY "PdbAdmin_2026!"
  ROLES = (DBA)
  DEFAULT TABLESPACE app_data
    DATAFILE SIZE 1G AUTOEXTEND ON
  TEMPFILE REUSE
  FILE_NAME_CONVERT = (
    '/u01/oradata/ORCL/pdbseed/',
    '/u01/oradata/ORCL/pdb_app1/'
  )
  PATH_PREFIX = '/u01/oradata/ORCL/pdb_app1/'
  STORAGE (MAXSIZE 100G MAX_SHARED_TEMP_SIZE 10G)
  NOLOGGING;

-- Tạo PDB từ CDB$ROOT với ASM
CREATE PLUGGABLE DATABASE pdb_app2
  ADMIN USER pdb_admin IDENTIFIED BY "PdbAdmin_2026!"
  DEFAULT TABLESPACE users
    DATAFILE '+DATA' SIZE 1G AUTOEXTEND ON
  FILE_NAME_CONVERT = ('+DATA/ORCL/PDBSEED/', '+DATA/ORCL/PDB_APP2/');

-- Clone PDB từ PDB khác
-- Bước 1: Source PDB phải OPEN READ ONLY
ALTER PLUGGABLE DATABASE pdb_app1 OPEN READ ONLY;

-- Bước 2: Clone
CREATE PLUGGABLE DATABASE pdb_app1_clone
  FROM pdb_app1
  FILE_NAME_CONVERT = (
    '/u01/oradata/ORCL/pdb_app1/',
    '/u01/oradata/ORCL/pdb_app1_clone/'
  );

-- Clone không cần đưa source về READ ONLY (19c+)
CREATE PLUGGABLE DATABASE pdb_app1_hotclone
  FROM pdb_app1
  FILE_NAME_CONVERT = (...)
  SNAPSHOT COPY;   -- ASM Snapshot (thin clone — tiết kiệm disk, 19c EE)

-- Thin Clone (19c+, không sao chép data)
CREATE PLUGGABLE DATABASE pdb_thin_clone
  FROM pdb_app1
  SNAPSHOT COPY;   -- Cần ASM với ADVM

-- Relocate PDB (12.2+) — move PDB sang CDB khác không downtime
CREATE PLUGGABLE DATABASE pdb_app1
  FROM pdb_app1@source_cdb_link
  RELOCATE
  FILE_NAME_CONVERT = (...)
  AVAILABILITY MAX;  -- Zero downtime
```

### 2.2 Open/Close PDB

```sql
-- Open một PDB
ALTER PLUGGABLE DATABASE pdb_app1 OPEN;
ALTER PLUGGABLE DATABASE pdb_app1 OPEN READ ONLY;
ALTER PLUGGABLE DATABASE pdb_app1 OPEN READ ONLY RESTRICTED;

-- Open tất cả PDBs
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL EXCEPT pdb_maintenance OPEN;

-- Close PDB
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE;  -- Chờ sessions thoát

-- Close tất cả
ALTER PLUGGABLE DATABASE ALL CLOSE;

-- Save state (PDB tự động open sau khi CDB restart)
ALTER PLUGGABLE DATABASE pdb_app1 OPEN;
ALTER PLUGGABLE DATABASE pdb_app1 SAVE STATE;

-- Verify saved states
SELECT con_name, state FROM dba_pdb_saved_states;

-- Discard saved state
ALTER PLUGGABLE DATABASE pdb_app1 DISCARD STATE;

-- Trigger tự động open tất cả PDB khi CDB startup
-- Tạo trigger trong CDB$ROOT:
CREATE OR REPLACE TRIGGER auto_open_pdbs
  AFTER STARTUP ON DATABASE
BEGIN
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ALL OPEN';
END;
/
```

### 2.3 Drop PDB

```sql
-- Unplug PDB trước (tạo XML manifest để có thể plug vào CDB khác)
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_app1
  UNPLUG INTO '/tmp/pdb_app1.xml';
-- Sau unplug, PDB không còn accessible

-- Drop PDB (giữ files — để plug vào nơi khác)
DROP PLUGGABLE DATABASE pdb_app1 KEEP DATAFILES;

-- Drop PDB và xóa luôn files (không thể recover!)
DROP PLUGGABLE DATABASE pdb_app1 INCLUDING DATAFILES;

-- Plug PDB từ XML manifest vào CDB khác
CREATE PLUGGABLE DATABASE pdb_app1
  USING '/tmp/pdb_app1.xml'
  NOCOPY                  -- Giữ nguyên files tại chỗ cũ
  TEMPFILE REUSE;
-- Hoặc COPY để sao chép files sang location mới:
-- COPY FILE_NAME_CONVERT = ('/old/path/', '/new/path/')
```

---

## 3. USER & PRIVILEGE TRONG MULTITENANT

```sql
-- Common User: tồn tại trong tất cả containers
-- Prefix bắt buộc: C## (hoặc theo common_user_prefix parameter)

-- Tạo Common User (từ CDB$ROOT)
CREATE USER c##common_dba
  IDENTIFIED BY "CommonDBA_2026!"
  CONTAINER = ALL;

-- Grant privilege trong tất cả containers
GRANT CREATE SESSION TO c##common_dba CONTAINER=ALL;
GRANT DBA TO c##common_dba CONTAINER=ALL;

-- Grant chỉ trong CDB$ROOT
GRANT SYSDBA TO c##common_dba CONTAINER=CURRENT;

-- Local User: chỉ trong PDB hiện tại
ALTER SESSION SET CONTAINER = pdb_app1;
CREATE USER app_local_user
  IDENTIFIED BY "LocalUser_2026!";
GRANT CREATE SESSION, CREATE TABLE TO app_local_user;

-- Cross-container queries (từ CDB$ROOT)
-- CDB_ views: xem data từ tất cả containers
SELECT con_id, username, account_status
FROM cdb_users
WHERE username = 'APP_LOCAL_USER'
ORDER BY con_id;

SELECT con_id, tablespace_name, contents
FROM cdb_tablespaces
WHERE con_id > 2  -- PDB only (1=CDB$ROOT, 2=PDB$SEED)
ORDER BY con_id, tablespace_name;

SELECT con_id, owner, object_name, object_type, status
FROM cdb_objects
WHERE owner = 'APP_USER'
  AND status = 'INVALID'
ORDER BY con_id;
```

---

## 4. BACKUP & RECOVERY CHO CDB/PDB

```sql
-- Backup toàn bộ CDB (bao gồm tất cả PDBs)
-- RMAN:
-- BACKUP DATABASE PLUS ARCHIVELOG;  -- Backup all

-- Backup chỉ một PDB
-- RMAN:
-- BACKUP PLUGGABLE DATABASE pdb_app1;

-- Backup Root + một PDB
-- RMAN:
-- BACKUP DATABASE ROOT PLUGGABLE DATABASE pdb_app1;

-- Restore một PDB (không ảnh hưởng PDB khác)
-- RMAN:
-- ALTER PLUGGABLE DATABASE pdb_app1 CLOSE;
-- RESTORE PLUGGABLE DATABASE pdb_app1;
-- RECOVER PLUGGABLE DATABASE pdb_app1;
-- ALTER PLUGGABLE DATABASE pdb_app1 OPEN RESETLOGS;

-- PITR cho PDB
-- RMAN:
-- SET UNTIL TIME "TO_DATE('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')";
-- RESTORE PLUGGABLE DATABASE pdb_app1;
-- RECOVER PLUGGABLE DATABASE pdb_app1;
-- ALTER PLUGGABLE DATABASE pdb_app1 OPEN RESETLOGS;

-- DataPump Export/Import cho PDB
-- Export:
-- expdp c##common_dba/pass@ORCL
--   FULL=Y DUMPFILE=pdb_app1_full.dmp
--   EXCLUDE=DIRECTORY LOGFILE=pdb_app1_exp.log
--   CLUSTER=N
--   CONTAINER=pdb_app1

-- Import vào PDB khác:
-- impdp c##common_dba/pass@ORCLPDB2
--   FULL=Y DUMPFILE=pdb_app1_full.dmp
--   REMAP_TABLESPACE=app_data:app_data2

-- Flashback PDB
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE IMMEDIATE;
FLASHBACK PLUGGABLE DATABASE pdb_app1
  TO TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR;
ALTER PLUGGABLE DATABASE pdb_app1 OPEN RESETLOGS;
```

---

## 5. PDB LOCKDOWN PROFILES

```sql
-- PDB Lockdown Profile: giới hạn quyền của user trong PDB
-- Ngăn DBA trong PDB làm những việc ảnh hưởng CDB

-- Tạo lockdown profile (từ CDB$ROOT hoặc Application Root)
CREATE LOCKDOWN PROFILE app_lockdown_profile;

-- Các loại lockdown:
-- Disable features
ALTER LOCKDOWN PROFILE app_lockdown_profile
  DISABLE FEATURE = ('XDB_PROTOCOLS');      -- Tắt XDB HTTP/FTP

-- Disable statements
ALTER LOCKDOWN PROFILE app_lockdown_profile
  DISABLE STATEMENT = ('ALTER SYSTEM')      -- Không cho ALTER SYSTEM
  CLAUSE = ('FLUSH SHARED_POOL');

-- Disable options
ALTER LOCKDOWN PROFILE app_lockdown_profile
  DISABLE OPTION = ('Partitioning');        -- Tắt Partitioning feature

-- Giới hạn đặc biệt
ALTER LOCKDOWN PROFILE app_lockdown_profile
  DISABLE STATEMENT = ('ALTER PLUGGABLE DATABASE')
  CLAUSE = ('CLOSE','OPEN');

-- Assign profile cho PDB
ALTER PLUGGABLE DATABASE pdb_app1
  LOCKDOWN = app_lockdown_profile;

-- Verify
SELECT profile_name, rule_type, rule, clause, clause_option, status
FROM dba_lockdown_profiles
WHERE profile_name = 'APP_LOCKDOWN_PROFILE';

-- Xem PDBs với lockdown profile
SELECT name, lockdown_profile
FROM v$pdbs
WHERE lockdown_profile IS NOT NULL;

-- Drop lockdown profile
DROP LOCKDOWN PROFILE app_lockdown_profile;
```

---

## 6. PDB SERVICES & RESOURCE MANAGEMENT

```sql
-- Mỗi PDB có service tự động (service name = PDB name)
-- Kết nối vào PDB qua service name:
-- sqlplus app_user/pass@host:1521/pdb_app1

-- Tạo service bổ sung trong PDB
ALTER SESSION SET CONTAINER = pdb_app1;
EXEC DBMS_SERVICE.CREATE_SERVICE('PDB1_APP_SVC','PDB1_APP_SVC.vietdba.local');
EXEC DBMS_SERVICE.START_SERVICE('PDB1_APP_SVC');

-- Resource Management cho PDB (từ CDB level)
-- Mỗi PDB có thể có limit về CPU và memory

-- Tạo CDB Resource Plan
BEGIN
  DBMS_RESOURCE_MANAGER.CREATE_PENDING_AREA();

  -- Tạo CDB plan
  DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN(
    plan    => 'CDB_RESOURCE_PLAN',
    comment => 'Resource plan for all PDBs');

  -- Allocate CPU cho từng PDB
  DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
    plan             => 'CDB_RESOURCE_PLAN',
    pluggable_database => 'PDB_APP1',
    shares           => 3,     -- Priority 3 (weight)
    utilization_limit => 80,   -- Max 80% CPU
    parallel_server_limit => 50);

  DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
    plan             => 'CDB_RESOURCE_PLAN',
    pluggable_database => 'PDB_APP2',
    shares           => 1,
    utilization_limit => 50,
    parallel_server_limit => 25);

  -- Default directive cho PDBs không được specify
  DBMS_RESOURCE_MANAGER.CREATE_CDB_PLAN_DIRECTIVE(
    plan             => 'CDB_RESOURCE_PLAN',
    pluggable_database => 'ORA$DEFAULT_PDB_DIRECTIVE',
    shares           => 1,
    utilization_limit => 20);

  DBMS_RESOURCE_MANAGER.VALIDATE_PENDING_AREA();
  DBMS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA();
END;
/

-- Activate plan
ALTER SYSTEM SET RESOURCE_MANAGER_PLAN = 'CDB_RESOURCE_PLAN' SCOPE=BOTH;

-- Memory limit cho PDB (SGA/PGA)
ALTER PLUGGABLE DATABASE pdb_app1 DEFAULT TABLESPACE app_data;
-- Memory limits:
-- ALTER SYSTEM SET DB_CACHE_SIZE = 2G SCOPE=BOTH CONTAINER=pdb_app1; -- 19c+
```

---

## 7. USEFUL MULTITENANT QUERIES

```sql
-- Tổng hợp trạng thái tất cả PDBs
SELECT p.con_id,
       p.name pdb_name,
       p.open_mode,
       p.restricted,
       ROUND(SUM(f.bytes)/1024/1024/1024, 2) total_gb,
       p.recovery_status,
       p.logging
FROM v$pdbs p
LEFT JOIN cdb_data_files f ON p.con_id = f.con_id
WHERE p.con_id > 2  -- Không tính PDB$SEED và CDB$ROOT
GROUP BY p.con_id, p.name, p.open_mode, p.restricted,
         p.recovery_status, p.logging
ORDER BY p.con_id;

-- Sessions per PDB
SELECT p.name pdb_name, COUNT(*) sessions
FROM v$session s
JOIN v$pdbs p ON s.con_id = p.con_id
WHERE s.type = 'USER'
GROUP BY p.name
ORDER BY sessions DESC;

-- Alert log messages per PDB
SELECT p.name pdb_name,
       e.originating_timestamp,
       e.message_text
FROM v$diag_alert_ext e
JOIN v$pdbs p ON e.con_id = p.con_id
WHERE e.originating_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
  AND e.message_type IN (2,3)
ORDER BY e.originating_timestamp DESC
FETCH FIRST 20 ROWS ONLY;

-- Tablespace usage per PDB
SELECT p.name pdb_name,
       t.tablespace_name,
       ROUND(m.used_space/1024, 2) used_gb,
       ROUND(m.tablespace_size/1024, 2) total_gb,
       ROUND(m.used_percent, 1) pct_used
FROM cdb_tablespace_usage_metrics m
JOIN v$pdbs p ON m.con_id = p.con_id
JOIN cdb_tablespaces t ON m.con_id = t.con_id
                       AND m.tablespace_name = t.tablespace_name
WHERE p.con_id > 2
  AND m.used_percent >= 70
ORDER BY m.used_percent DESC;
```

---

**Tài liệu tham khảo:**
- Oracle Multitenant Administrator's Guide 19c
- Oracle Database 2 Day + Multitenant Database Guide
- Oracle CDB/PDB Best Practices (MOS Note 1545012.1)
- www.tranvanbinh.vn
