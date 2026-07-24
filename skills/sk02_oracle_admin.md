---
name: oracle-database-administration
description: >
  Hướng dẫn đầy đủ quản trị Oracle Database hàng ngày và nâng cao.
  Kích hoạt khi hỏi về: quản trị Oracle, tablespace, datafile, ASM diskgroup,
  redo log, undo, archived log, controlfile, parameter spfile, listener,
  startup shutdown database, RMAN backup recovery, flashback, session lock,
  kill session, user account privilege role, gather statistics, invalid object,
  rebuild index, CDB PDB multitenant pluggable database, scheduler job,
  Enterprise Manager OEM, RAC srvctl. Luôn cung cấp SQL/command thực tế,
  kiểm tra trước và sau khi thực hiện, cảnh báo rủi ro.
---

# SK02 · Quản trị Oracle Database

**Phạm vi:** Oracle 11g, 12c, 19c, 21c, 23ai, 26ai — Single & RAC  
**Tác giả tham khảo:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Tài liệu nền:** QT/DB.01 Phụ lục II — Các thao tác vận hành hệ thống

---

## 1. STARTUP / SHUTDOWN

### 1.1 Startup/Shutdown Oracle Database

```sql
-- Startup các mode
STARTUP                    -- Normal: mount + open
STARTUP NOMOUNT            -- Chỉ đọc pfile/spfile, khởi động instance
STARTUP MOUNT              -- Mount controlfile, chưa mở datafile
STARTUP RESTRICT           -- Open nhưng chỉ cho RESTRICTED SESSION
STARTUP FORCE              -- SHUTDOWN ABORT rồi STARTUP
ALTER DATABASE OPEN;       -- Từ MOUNT → OPEN
ALTER DATABASE OPEN READ ONLY;  -- Open read-only (standby, test)

-- Shutdown các mode
SHUTDOWN NORMAL     -- Chờ tất cả session disconnect (không dùng production khẩn cấp)
SHUTDOWN IMMEDIATE  -- Rollback active transactions, disconnect sessions (khuyến dùng)
SHUTDOWN TRANSACTIONAL  -- Chờ commit/rollback xong rồi shutdown
SHUTDOWN ABORT      -- Dừng ngay, không rollback (cần recovery khi startup lại)

-- Kiểm tra sau startup
SELECT instance_name, host_name, version, status, database_status
FROM   v$instance;
SELECT open_mode, db_unique_name, log_mode, protection_mode
FROM   v$database;
```

### 1.2 Startup/Shutdown Listener

```bash
lsnrctl start [listener_name]
lsnrctl stop  [listener_name]
lsnrctl status
lsnrctl reload   # Reload không downtime
lsnrctl services # Xem services đã đăng ký
```

### 1.3 Startup/Shutdown RAC

```bash
# Dừng/start toàn bộ cluster resources
srvctl stop  database -d ORCL
srvctl start database -d ORCL
srvctl status database -d ORCL

# Dừng/start từng instance
srvctl stop  instance -d ORCL -i ORCL1
srvctl start instance -d ORCL -i ORCL1

# Dừng/start ASM
srvctl stop  asm -n node1
srvctl start asm -n node1

# Dừng/start Clusterware (cẩn thận!)
crsctl stop  crs    # Dừng Clusterware trên node hiện tại
crsctl start crs
crsctl stat  res -t # Xem trạng thái tất cả resources
```

---

## 2. QUẢN LÝ PARAMETER

```sql
-- Xem parameter hiện tại
SHOW PARAMETER sga
SHOW PARAMETER processes
SELECT name, value, description FROM v$parameter WHERE name = 'processes';

-- Thay đổi dynamic parameter (không restart)
ALTER SYSTEM SET processes = 500 SCOPE=BOTH;
ALTER SESSION SET nls_date_format = 'YYYY-MM-DD HH24:MI:SS';

-- Thay đổi cần restart (scope=spfile)
ALTER SYSTEM SET memory_max_target = 8G SCOPE=SPFILE;

-- Reset về default
ALTER SYSTEM RESET open_cursors SCOPE=BOTH;

-- Backup spfile → pfile
CREATE PFILE='/tmp/initORCL_backup.ora' FROM SPFILE;
-- Tạo spfile từ pfile
CREATE SPFILE FROM PFILE='/tmp/initORCL_backup.ora';
```

---

## 3. QUẢN LÝ TABLESPACE & DATAFILE

### 3.1 Tạo và quản lý Tablespace

```sql
-- Tạo tablespace mới (trên filesystem)
CREATE TABLESPACE APP_DATA
  DATAFILE '/u01/oradata/ORCL/app_data01.dbf' SIZE 10G
  AUTOEXTEND ON NEXT 1G MAXSIZE 50G
  EXTENT MANAGEMENT LOCAL
  SEGMENT SPACE MANAGEMENT AUTO;

-- Tạo tablespace trên ASM
CREATE TABLESPACE APP_DATA
  DATAFILE '+DATA' SIZE 10G
  AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;

-- Tạo TEMP tablespace
CREATE TEMPORARY TABLESPACE TEMP2
  TEMPFILE '/u01/oradata/ORCL/temp02.dbf' SIZE 5G
  AUTOEXTEND ON NEXT 512M MAXSIZE 30G;

-- Thêm datafile vào tablespace hiện có
ALTER TABLESPACE APP_DATA
  ADD DATAFILE '/u01/oradata/ORCL/app_data02.dbf' SIZE 10G
  AUTOEXTEND ON NEXT 1G MAXSIZE 50G;

-- Thêm tempfile
ALTER TABLESPACE TEMP
  ADD TEMPFILE '/u01/oradata/ORCL/temp02.dbf' SIZE 5G;

-- Resize datafile
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/app_data01.dbf'
  RESIZE 20G;

-- Drop tablespace (cẩn thận!)
DROP TABLESPACE APP_DATA
  INCLUDING CONTENTS AND DATAFILES
  CASCADE CONSTRAINTS;
```

### 3.2 Kiểm tra Tablespace Usage

```sql
-- Xem usage hiện tại (đơn giản)
SELECT tablespace_name,
       ROUND(used_space/1024,2)      used_gb,
       ROUND(tablespace_size/1024,2) total_gb,
       ROUND(used_percent,1)         pct_used,
       CASE WHEN used_percent >= 90 THEN '⚠️ CRITICAL'
            WHEN used_percent >= 80 THEN '⚡ WARNING'
            ELSE '✓ OK' END          status
FROM   dba_tablespace_usage_metrics
ORDER  BY pct_used DESC;

-- Xem autoextend và maxsize
SELECT df.tablespace_name,
       df.file_name,
       ROUND(df.bytes/1024/1024/1024,2)    size_gb,
       df.autoextensible,
       ROUND(df.maxbytes/1024/1024/1024,2) max_gb
FROM   dba_data_files df
ORDER  BY df.tablespace_name;
```

---

## 4. QUẢN LÝ ASM

```bash
# Kết nối ASM
export ORACLE_SID=+ASM
sqlplus / as sysasm
```

```sql
-- Xem diskgroup status
SELECT name, state, type,
       ROUND(total_mb/1024,2) total_gb,
       ROUND(free_mb/1024,2)  free_gb,
       ROUND((1-free_mb/total_mb)*100,1) pct_used
FROM   v$asm_diskgroup
ORDER  BY name;

-- Tạo diskgroup mới
CREATE DISKGROUP DATA EXTERNAL REDUNDANCY
  DISK '/dev/DATA1', '/dev/DATA2', '/dev/DATA3'
  ATTRIBUTE 'compatible.asm'='19.0',
            'compatible.rdbms'='19.0',
            'au_size'='4M';

-- Add disk vào diskgroup
ALTER DISKGROUP DATA ADD DISK '/dev/DATA4' NAME DATA4;

-- Drop disk (rebalance tự động)
ALTER DISKGROUP DATA DROP DISK DATA1;

-- Kiểm tra rebalance progress
SELECT * FROM v$asm_operation;

-- Xem disks trong diskgroup
SELECT dg.name, d.name, d.path, d.state,
       ROUND(d.total_mb/1024,2) size_gb
FROM   v$asm_diskgroup dg
JOIN   v$asm_disk d ON dg.group_number = d.group_number
ORDER  BY dg.name, d.name;
```

```bash
# ASMCMD commands
asmcmd lsdg              # List diskgroups
asmcmd lsdsk             # List disks
asmcmd du +DATA          # Disk usage
asmcmd ls +DATA/ORCL/    # List files trong diskgroup
asmcmd cp +DATA/ORCL/controlfile01.ctl /tmp/  # Copy file
```

---

## 5. QUẢN LÝ USER, PRIVILEGE, ROLE

```sql
-- Tạo user
CREATE USER app_user
  IDENTIFIED BY "SecurePass_123"
  DEFAULT TABLESPACE APP_DATA
  TEMPORARY TABLESPACE TEMP
  QUOTA 10G ON APP_DATA
  QUOTA UNLIMITED ON INDX;

-- Gán quyền cơ bản
GRANT CREATE SESSION TO app_user;
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE TO app_user;
GRANT SELECT ON hr.employees TO app_user;

-- Tạo role
CREATE ROLE app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON sales.orders TO app_role;
GRANT app_role TO app_user;

-- Đổi password
ALTER USER app_user IDENTIFIED BY "NewPass_456";

-- Lock/Unlock account
ALTER USER app_user ACCOUNT LOCK;
ALTER USER app_user ACCOUNT UNLOCK;

-- Drop user (cẩn thận!)
DROP USER app_user CASCADE;

-- Xem user có gì
SELECT username, account_status, default_tablespace, profile
FROM   dba_users
WHERE  username = 'APP_USER';

SELECT grantee, privilege, admin_option
FROM   dba_sys_privs
WHERE  grantee = 'APP_USER';

SELECT grantee, owner, table_name, privilege
FROM   dba_tab_privs
WHERE  grantee = 'APP_USER';
```

---

## 6. QUẢN LÝ REDO LOG & ARCHIVE

### 6.1 Redo Log Management

```sql
-- Xem status redo log
SELECT l.group#, l.members, l.bytes/1024/1024 size_mb,
       l.status, l.archived, lf.member
FROM   v$log l JOIN v$logfile lf ON l.group# = lf.group#
ORDER  BY l.group#;

-- Thêm redo log group
ALTER DATABASE ADD LOGFILE GROUP 4
  ('/u01/oradata/ORCL/redo04a.log',
   '/u01/oradata/ORCL/redo04b.log') SIZE 500M;

-- Xóa redo log group (phải không ở CURRENT/ACTIVE)
ALTER DATABASE DROP LOGFILE GROUP 4;

-- Force log switch
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;
```

### 6.2 Archive Log Management

```sql
-- Kiểm tra archive mode
SELECT log_mode FROM v$database;

-- Bật archivelog mode
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Xem archive destinations
SELECT dest_id, status, target, archiver, schedule,
       destination, error
FROM   v$archive_dest
WHERE  status != 'INACTIVE';

-- Xem archive log files
SELECT name, sequence#, applied, deleted,
       ROUND(blocks*block_size/1024/1024,2) size_mb
FROM   v$archived_log
WHERE  applied = 'YES'
  AND  deleted = 'NO'
  AND  first_time > SYSDATE - 1
ORDER  BY sequence# DESC
FETCH FIRST 20 ROWS ONLY;

-- Xóa archivelog cũ (qua RMAN)
-- RMAN:
-- DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';
```

---

## 7. BACKUP & RECOVERY VỚI RMAN

### 7.1 Backup

```bash
rman target /
```

```sql
-- Full backup (RMAN)
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '/backup/rman/%d_%T_%s_%p.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '/backup/rman/%d_%T_%s_%p.bkp';
  BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG DELETE INPUT;
  BACKUP CURRENT CONTROLFILE FORMAT '/backup/rman/ctlfile_%T.bkp';
  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}

-- Incremental backup Level 0
BACKUP INCREMENTAL LEVEL 0 DATABASE
  FORMAT '/backup/rman/inc0_%d_%T_%s_%p.bkp';

-- Incremental Level 1 (daily)
BACKUP INCREMENTAL LEVEL 1 DATABASE
  FORMAT '/backup/rman/inc1_%d_%T_%s_%p.bkp';

-- Kiểm tra backup
LIST BACKUP SUMMARY;
LIST BACKUP OF DATABASE COMPLETED AFTER 'SYSDATE-7';
CROSSCHECK BACKUP;
DELETE EXPIRED BACKUP;
```

### 7.2 Recovery

```sql
-- Complete recovery (database crash)
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;

-- Point-in-time recovery (PITR)
STARTUP MOUNT;
SET UNTIL TIME "TO_DATE('2026-01-15 10:00:00','YYYY-MM-DD HH24:MI:SS')";
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;

-- Block media recovery (không cần shutdown)
BLOCKRECOVER DATAFILE 5 BLOCK 100;

-- Flashback database (không cần RMAN)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
FLASHBACK DATABASE TO TIMESTAMP
  TO_TIMESTAMP('2026-01-15 09:00:00','YYYY-MM-DD HH24:MI:SS');
ALTER DATABASE OPEN RESETLOGS;
```

---

## 8. QUẢN LÝ SESSION & LOCK

```sql
-- Xem active sessions
SELECT s.sid, s.serial#, s.username, s.status,
       s.wait_class, s.event,
       s.seconds_in_wait, s.sql_id,
       s.blocking_session,
       s.machine, s.program,
       SUBSTR(q.sql_text,1,80) sql_text
FROM   v$session s
LEFT   JOIN v$sql q ON s.sql_id = q.sql_id
WHERE  s.type = 'USER'
  AND  s.status IN ('ACTIVE','KILLED')
ORDER  BY s.seconds_in_wait DESC;

-- Tìm blocking session tree
SELECT  LPAD(' ', 2*(LEVEL-1)) || s.sid      sid_tree,
        s.blocking_session,
        s.username, s.status,
        s.wait_class, s.event,
        s.seconds_in_wait,
        SUBSTR(q.sql_text,1,60) sql_text
FROM    v$session s
LEFT    JOIN v$sql q ON s.sql_id = q.sql_id
START WITH  s.blocking_session IS NULL
        AND s.sid IN (SELECT blocking_session FROM v$session
                       WHERE blocking_session IS NOT NULL)
CONNECT BY  PRIOR s.sid = s.blocking_session
ORDER SIBLINGS BY s.seconds_in_wait DESC;

-- Kill session (cẩn thận!)
ALTER SYSTEM KILL SESSION '123,456' IMMEDIATE;
-- Trên OS nếu session không chết
SELECT spid FROM v$process p, v$session s
WHERE p.addr = s.paddr AND s.sid = 123;
-- kill -9 <spid>

-- Xem locks
SELECT l.type, l.lmode, l.request,
       s.sid, s.username, s.status,
       SUBSTR(o.object_name,1,30) object_name
FROM   v$lock l
JOIN   v$session s ON l.sid = s.sid
LEFT   JOIN dba_objects o ON l.id1 = o.object_id
WHERE  l.type NOT IN ('MR','RT','FS','AE')
ORDER  BY l.type, s.sid;
```

---

## 9. GATHER STATISTICS

```sql
-- Gather toàn DB (chạy ban đêm, mất nhiều thời gian)
EXEC DBMS_STATS.GATHER_DATABASE_STATS(
  options       => 'GATHER AUTO',
  degree        => 4,
  cascade       => TRUE);

-- Gather schema
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(
  ownname  => 'SCOTT',
  options  => 'GATHER STALE',
  degree   => 4,
  cascade  => TRUE);

-- Gather table
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname          => 'SCOTT',
  tabname          => 'ORDERS',
  estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
  method_opt       => 'FOR ALL COLUMNS SIZE AUTO',
  degree           => 4,
  cascade          => TRUE);

-- Gather partition lớn
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname          => 'SALES',
  tabname          => 'SALES_DATA',
  partname         => 'P_2025_Q4',
  granularity      => 'PARTITION',
  degree           => 8);

-- Tìm tables thiếu/stale statistics
SELECT t.owner, t.table_name,
       t.last_analyzed,
       t.num_rows,
       t.stale_stats
FROM   dba_tab_statistics t
WHERE  t.owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN')
  AND  (t.last_analyzed IS NULL
        OR t.last_analyzed < SYSDATE - 14
        OR t.stale_stats = 'YES')
  AND  t.num_rows > 10000
ORDER  BY t.last_analyzed NULLS FIRST;

-- Kiểm tra auto stats job
SELECT client_name, status
FROM   dba_autotask_client
WHERE  client_name = 'auto optimizer stats collection';
```

---

## 10. QUẢN LÝ OBJECT

```sql
-- Compile invalid objects
-- Cách 1: Script chuẩn Oracle
@$ORACLE_HOME/rdbms/admin/utlrp.sql

-- Cách 2: Compile từng loại
BEGIN
  FOR obj IN (SELECT owner, object_type, object_name
              FROM   dba_objects
              WHERE  status = 'INVALID'
                AND  owner NOT IN ('SYS','SYSTEM')) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER ' || obj.object_type ||
                        ' ' || obj.owner || '.' || obj.object_name ||
                        ' COMPILE';
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

-- Xem invalid objects còn lại
SELECT owner, object_type, object_name, status
FROM   dba_objects
WHERE  status = 'INVALID'
  AND  owner NOT IN ('SYS','SYSTEM')
ORDER  BY owner, object_type;

-- Rebuild unusable indexes
SELECT owner, index_name, table_name, status
FROM   dba_indexes
WHERE  status = 'UNUSABLE'
  AND  owner NOT IN ('SYS','SYSTEM');

-- Rebuild (ONLINE để không lock table)
ALTER INDEX scott.idx_orders_date REBUILD ONLINE;

-- Script rebuild all unusable indexes
BEGIN
  FOR idx IN (SELECT owner, index_name FROM dba_indexes
               WHERE status = 'UNUSABLE'
                 AND owner NOT IN ('SYS','SYSTEM')) LOOP
    EXECUTE IMMEDIATE 'ALTER INDEX ' || idx.owner || '.' ||
                      idx.index_name || ' REBUILD ONLINE';
  END LOOP;
END;
/
```

---

## 11. CDB/PDB MULTITENANT

```sql
-- Xem CDB info
SELECT cdb, con_id, name FROM v$database;
SELECT con_id, name, open_mode, restricted FROM v$pdbs;

-- Tạo PDB mới
CREATE PLUGGABLE DATABASE pdb_new
  ADMIN USER pdb_admin IDENTIFIED BY Admin_1234
  ROLES = (DBA)
  DEFAULT TABLESPACE APP_DATA
    DATAFILE '+DATA' SIZE 1G AUTOEXTEND ON
  PATH_PREFIX = '/u01/oradata/pdb_new/'
  FILE_NAME_CONVERT = ('+DATA/ORCL/pdbseed/','+DATA/ORCL/pdb_new/');

ALTER PLUGGABLE DATABASE pdb_new OPEN;

-- Open/close PDB
ALTER PLUGGABLE DATABASE pdb_new OPEN;
ALTER PLUGGABLE DATABASE pdb_new CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_new OPEN READ ONLY;

-- Auto-open PDB khi CDB restart
ALTER PLUGGABLE DATABASE pdb_new OPEN;
ALTER PLUGGABLE DATABASE pdb_new SAVE STATE;

-- Kết nối vào PDB
ALTER SESSION SET CONTAINER = pdb_new;
-- Hoặc qua connection string: easy connect: host:port/pdb_name

-- Drop PDB
ALTER PLUGGABLE DATABASE pdb_old CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE pdb_old INCLUDING DATAFILES;

-- Clone PDB từ PDB có sẵn
ALTER PLUGGABLE DATABASE pdb_source OPEN READ ONLY;
CREATE PLUGGABLE DATABASE pdb_clone FROM pdb_source
  FILE_NAME_CONVERT = ('+DATA/ORCL/pdb_source/','+DATA/ORCL/pdb_clone/');

-- Query cross-container (từ CDB root)
SELECT con_id, username, account_status
FROM   cdb_users
WHERE  con_id > 2  -- PDBs only
ORDER  BY con_id, username;
```

---

## 12. SCHEDULER & JOBS

```sql
-- Tạo job đơn giản
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'NIGHTLY_STATS_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_STATS.GATHER_SCHEMA_STATS(''SCOTT''); END;',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',
    end_date        => NULL,
    enabled         => TRUE,
    comments        => 'Gather stats for SCOTT schema daily at 2 AM');
END;
/

-- Tạo job chạy script shell
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name    => 'RMAN_BACKUP_JOB',
    job_type    => 'EXECUTABLE',
    job_action  => '/u01/scripts/rman_backup.sh',
    start_date  => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=4',
    enabled     => TRUE);
END;
/

-- Xem jobs
SELECT job_name, job_type, state, last_start_date,
       last_run_duration, next_run_date, enabled
FROM   dba_scheduler_jobs
WHERE  owner = 'SYS'
ORDER  BY last_start_date DESC;

-- Run job ngay
EXEC DBMS_SCHEDULER.RUN_JOB('NIGHTLY_STATS_JOB');

-- Stop, enable, disable, drop
EXEC DBMS_SCHEDULER.STOP_JOB('NIGHTLY_STATS_JOB', force=>TRUE);
EXEC DBMS_SCHEDULER.DISABLE('NIGHTLY_STATS_JOB');
EXEC DBMS_SCHEDULER.ENABLE('NIGHTLY_STATS_JOB');
EXEC DBMS_SCHEDULER.DROP_JOB('NIGHTLY_STATS_JOB');

-- Xem job log
SELECT job_name, log_date, status, error#, additional_info
FROM   dba_scheduler_job_log
WHERE  job_name = 'NIGHTLY_STATS_JOB'
ORDER  BY log_date DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## Tài liệu tham khảo
- Oracle Administrator's Guide 19c: docs.oracle.com/en/database/oracle/oracle-database/19/admin/
- RMAN Backup and Recovery Guide: docs.oracle.com/en/database/oracle/oracle-database/19/bradv/
- QT/DB.01 Phụ lục II — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
