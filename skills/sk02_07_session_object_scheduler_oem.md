---
name: oracle-session-object-scheduler-oem
description: >
  Quản lý Session, Lock, Object, Statistics, Scheduler và Oracle Enterprise Manager.
  Kích hoạt khi hỏi về: session Oracle, lock Oracle, kill session Oracle,
  blocking session Oracle, deadlock Oracle, active session Oracle,
  invalid object Oracle, unusable index Oracle, rebuild index Oracle,
  compile object Oracle, gather statistics Oracle, DBMS_STATS,
  stale statistics Oracle, auto stats job Oracle, scheduler Oracle,
  DBMS_SCHEDULER Oracle, job Oracle, cron Oracle, chain Oracle,
  Oracle Enterprise Manager OEM, EM Express Oracle, Cloud Control OEM,
  monitoring targets OEM, OEM patch, OEM jobs, database control.
---

# SK02-07 · Session/Lock · Object · Statistics · Scheduler · OEM

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. QUẢN LÝ SESSION & LOCK

### 1.1 Xem Active Sessions

```sql
-- Active sessions chi tiết (health check hàng ngày)
SELECT s.sid,
       s.serial#,
       s.username,
       s.osuser,
       s.machine,
       s.program,
       s.status,            -- ACTIVE, INACTIVE, KILLED
       s.wait_class,
       s.event,
       s.seconds_in_wait wait_sec,
       s.sql_id,
       s.blocking_session,
       TO_CHAR(s.logon_time,'HH24:MI:SS') logon,
       SUBSTR(q.sql_text, 1, 100) sql_preview
FROM v$session s
LEFT JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.type = 'USER'
  AND s.username IS NOT NULL
  AND s.status IN ('ACTIVE','KILLED')
ORDER BY s.seconds_in_wait DESC;

-- Summary theo status
SELECT status, type, COUNT(*) cnt
FROM v$session
GROUP BY status, type
ORDER BY status, type;

-- Long-running sessions (> 30 phút)
SELECT s.sid, s.serial#, s.username, s.status,
       ROUND(s.last_call_et/60, 1) running_min,
       s.event, s.wait_class, s.sql_id,
       SUBSTR(q.sql_text, 1, 120) sql_text
FROM v$session s
LEFT JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.type = 'USER'
  AND s.status = 'ACTIVE'
  AND s.last_call_et > 1800  -- 30 phút
ORDER BY s.last_call_et DESC;

-- Sessions với progress (long operations)
SELECT s.sid, s.serial#, s.username,
       lo.opname, lo.target,
       ROUND(lo.sofar/NULLIF(lo.totalwork,0)*100, 1) pct_done,
       lo.message,
       ROUND(lo.elapsed_seconds/60, 1) elapsed_min,
       ROUND(lo.time_remaining/60, 1) remaining_min
FROM v$session_longops lo
JOIN v$session s ON lo.sid = s.sid AND lo.serial# = s.serial#
WHERE lo.sofar < lo.totalwork
  AND lo.totalwork > 0
ORDER BY pct_done DESC;
```

### 1.2 Blocking Tree (Lock Analysis)

```sql
-- Blocking session tree (QT/DB.01 Phụ lục II.9)
SELECT LPAD(' ', 2*(LEVEL-1)) || s.sid       AS sid_tree,
       s.serial#,
       s.blocking_session                    AS blocked_by,
       s.username,
       s.status,
       s.wait_class,
       s.event,
       ROUND(s.seconds_in_wait/60, 1)        wait_min,
       ROUND(s.last_call_et/60, 1)           running_min,
       SUBSTR(q.sql_text, 1, 80)             sql_text
FROM v$session s
LEFT JOIN v$sql q ON s.sql_id = q.sql_id
START WITH s.blocking_session IS NULL
       AND s.sid IN (SELECT blocking_session FROM v$session
                      WHERE blocking_session IS NOT NULL)
CONNECT BY PRIOR s.sid = s.blocking_session
ORDER SIBLINGS BY s.seconds_in_wait DESC;

-- Locks đang hold (V$LOCK)
SELECT l.type,
       DECODE(l.type,
         'TM', 'Table Lock (DML)',
         'TX', 'Transaction (Row Lock)',
         'UL', 'User Lock (DBMS_LOCK)',
         l.type) lock_type,
       l.id1, l.id2,
       DECODE(l.lmode,
         0,'None', 1,'Null', 2,'Row-S(SS)', 3,'Row-X(SX)',
         4,'Share(S)', 5,'S/Row-X(SSX)', 6,'Exclusive(X)') lock_mode,
       DECODE(l.request,
         0,'None', 1,'Null', 2,'Row-S', 3,'Row-X',
         4,'Share', 5,'S/Row-X', 6,'Exclusive') request_mode,
       l.block blocking,
       s.sid, s.serial#, s.username, s.status
FROM v$lock l
JOIN v$session s ON l.sid = s.sid
WHERE l.type IN ('TM','TX','UL')
  AND (l.block = 1 OR l.request > 0)
ORDER BY l.block DESC, s.username;
```

### 1.3 Kill Session

```sql
-- Kill session cụ thể (QT/DB.01 Phụ lục II.9)
-- Cẩn thận: confirm với DBA Lead trước khi kill production session

-- Kiểm tra session trước khi kill
SELECT sid, serial#, username, status, last_call_et,
       sql_id, event, machine
FROM v$session
WHERE sid = 445;

-- Kill (Oracle gửi signal, process tự cleanup)
ALTER SYSTEM KILL SESSION '445,12341';            -- Graceful
ALTER SYSTEM KILL SESSION '445,12341' IMMEDIATE;  -- Ngay lập tức (RAC-aware)

-- Nếu kill xong nhưng session vẫn còn (trạng thái KILLED)
-- Tìm OS process và kill trực tiếp
SELECT p.pid, p.spid OS_PID, s.sid, s.serial#, s.username
FROM v$process p
JOIN v$session s ON p.addr = s.paddr
WHERE s.sid = 445;
-- Trên OS: kill -9 <spid>

-- Kill nhiều sessions của một user
BEGIN
  FOR s IN (SELECT sid, serial# FROM v$session
             WHERE username = 'APP_USER'
               AND status = 'INACTIVE'
               AND last_call_et > 3600) LOOP  -- Idle > 1 giờ
    BEGIN
      EXECUTE IMMEDIATE
        'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    EXCEPTION WHEN OTHERS THEN NULL;  -- Ignore lỗi nếu session đã thoát
    END;
  END LOOP;
END;
/

-- Disconnect session (disconnect gracefully, không rollback)
ALTER SYSTEM DISCONNECT SESSION '445,12341' POST_TRANSACTION;
-- Hoặc ngay lập tức:
ALTER SYSTEM DISCONNECT SESSION '445,12341' IMMEDIATE;
```

---

## 2. QUẢN LÝ OBJECT (Phụ lục II.11, II.12)

### 2.1 Invalid Objects

```sql
-- Xem invalid objects
SELECT owner, object_type, object_name, status,
       last_ddl_time
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN',
                    'MDSYS','ORDSYS','EXFSYS','DMSYS','WMSYS',
                    'CTXSYS','ANONYMOUS','XDB','OLAPSYS','ORDDATA')
ORDER BY owner, object_type, object_name;

-- Compile tất cả invalid objects (cách 1: Oracle script)
@$ORACLE_HOME/rdbms/admin/utlrp.sql  -- Parallel compile

-- Compile tất cả invalid objects (cách 2: loop thủ công)
DECLARE
  v_sql VARCHAR2(500);
BEGIN
  FOR obj IN (
    SELECT owner, object_type, object_name
    FROM dba_objects
    WHERE status = 'INVALID'
      AND owner NOT IN ('SYS','SYSTEM','DBSNMP')
      AND object_type IN ('PROCEDURE','FUNCTION','PACKAGE','PACKAGE BODY',
                          'TRIGGER','VIEW','TYPE','TYPE BODY')
    ORDER BY CASE object_type
      WHEN 'TYPE' THEN 1
      WHEN 'TYPE BODY' THEN 2
      WHEN 'PACKAGE' THEN 3
      WHEN 'PACKAGE BODY' THEN 4
      ELSE 5 END
  ) LOOP
    BEGIN
      v_sql := 'ALTER ' || obj.object_type ||
               ' ' || obj.owner || '.' || '"' || obj.object_name || '"' ||
               ' COMPILE';
      IF obj.object_type = 'PACKAGE BODY' THEN
        v_sql := 'ALTER PACKAGE ' || obj.owner || '.' ||
                 '"' || obj.object_name || '" COMPILE BODY';
      END IF;
      EXECUTE IMMEDIATE v_sql;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/

-- Verify sau compile
SELECT COUNT(*) remaining_invalid
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM','DBSNMP');
```

### 2.2 Unusable Indexes (Phụ lục II.11)

```sql
-- Xem unusable indexes
SELECT owner, index_name, table_name, status,
       index_type, uniqueness,
       partitioned
FROM dba_indexes
WHERE status = 'UNUSABLE'
  AND owner NOT IN ('SYS','SYSTEM')
ORDER BY owner, table_name, index_name;

-- Index partitions unusable
SELECT index_owner, index_name, partition_name, status
FROM dba_ind_partitions
WHERE status = 'UNUSABLE'
ORDER BY index_owner, index_name, partition_name;

-- Rebuild một index (ONLINE để không lock table production)
ALTER INDEX scott.idx_orders_date REBUILD ONLINE;

-- Rebuild toàn bộ unusable indexes
DECLARE
  v_sql VARCHAR2(500);
BEGIN
  -- Non-partitioned indexes
  FOR idx IN (
    SELECT owner, index_name
    FROM dba_indexes
    WHERE status = 'UNUSABLE'
      AND owner NOT IN ('SYS','SYSTEM')
      AND partitioned = 'NO'
  ) LOOP
    BEGIN
      v_sql := 'ALTER INDEX ' || idx.owner || '.' || idx.index_name ||
               ' REBUILD ONLINE';
      EXECUTE IMMEDIATE v_sql;
      DBMS_OUTPUT.PUT_LINE('Rebuilt: ' || idx.owner || '.' || idx.index_name);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('FAILED: ' || idx.owner || '.' || idx.index_name ||
                           ' - ' || SQLERRM);
    END;
  END LOOP;

  -- Partitioned index partitions
  FOR idx IN (
    SELECT index_owner, index_name, partition_name
    FROM dba_ind_partitions
    WHERE status = 'UNUSABLE'
  ) LOOP
    BEGIN
      v_sql := 'ALTER INDEX ' || idx.index_owner || '.' || idx.index_name ||
               ' REBUILD PARTITION ' || idx.partition_name || ' ONLINE';
      EXECUTE IMMEDIATE v_sql;
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('FAILED partition: ' || SQLERRM);
    END;
  END LOOP;
END;
/
```

---

## 3. GATHER STATISTICS (Phụ lục II.17)

```sql
-- Gather cho toàn DB (ban đêm, maintenance window)
EXEC DBMS_STATS.GATHER_DATABASE_STATS(
  options       => 'GATHER AUTO',   -- Chỉ stale/missing stats
  degree        => 4,               -- Parallel degree
  cascade       => TRUE,            -- Include indexes
  no_invalidate => FALSE);          -- Invalidate cursors ngay

-- Gather cho schema
EXEC DBMS_STATS.GATHER_SCHEMA_STATS(
  ownname  => 'SCOTT',
  options  => 'GATHER STALE',       -- GATHER STALE | GATHER AUTO | GATHER
  degree   => 4,
  cascade  => TRUE);

-- Gather cho table
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname          => 'SCOTT',
  tabname          => 'ORDERS',
  estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,  -- Tự động tính sample
  method_opt       => 'FOR ALL COLUMNS SIZE AUTO',  -- Auto histogram
  degree           => 4,
  cascade          => TRUE,          -- Include indexes
  no_invalidate    => FALSE);

-- Gather partition lớn (chỉ gather partition mới/stale)
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname          => 'SALES',
  tabname          => 'FACT_SALES',
  partname         => 'P_2026_01',
  granularity      => 'PARTITION',
  degree           => 8);

-- Script gather bảng NON-PARTITION STALE (từ QT/DB.01)
BEGIN
  FOR t IN (
    SELECT owner, table_name
    FROM dba_tab_statistics
    WHERE stale_stats = 'YES'
      AND partitioned  = 'NO'
      AND object_type  = 'TABLE'
      AND owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN',
                        'MDSYS','ORDSYS','EXFSYS','DMSYS','WMSYS',
                        'CTXSYS','ANONYMOUS','XDB','OLAPSYS','ORDDATA')
      AND num_rows     > 10000
  ) LOOP
    BEGIN
      DBMS_STATS.GATHER_TABLE_STATS(
        ownname  => t.owner,
        tabname  => t.table_name,
        degree   => 4,
        cascade  => TRUE,
        no_invalidate => FALSE);
      DBMS_OUTPUT.PUT_LINE('Gathered: '||t.owner||'.'||t.table_name);
    EXCEPTION WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('FAILED: '||t.owner||'.'||t.table_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- Lock statistics (không cho auto stats thay đổi)
EXEC DBMS_STATS.LOCK_TABLE_STATS('SCOTT','ORDERS');
EXEC DBMS_STATS.UNLOCK_TABLE_STATS('SCOTT','ORDERS');
EXEC DBMS_STATS.LOCK_SCHEMA_STATS('SCOTT');

-- Kiểm tra statistics bị lock
SELECT owner, table_name, stattype_locked
FROM dba_tab_statistics
WHERE stattype_locked IS NOT NULL;

-- Restore statistics về version trước (khi stats mới gây regression)
-- Xem history
SELECT savtime, stats_update_time
FROM dba_tab_stats_history
WHERE owner = 'SCOTT' AND table_name = 'ORDERS'
ORDER BY savtime DESC;

-- Restore
EXEC DBMS_STATS.RESTORE_TABLE_STATS(
  ownname  => 'SCOTT',
  tabname  => 'ORDERS',
  as_of_timestamp => SYSTIMESTAMP - INTERVAL '2' HOUR);

-- Auto stats job (Oracle 11g+)
-- Kiểm tra job đang enable không (QT/DB.01)
SELECT client_name, status
FROM dba_autotask_client
WHERE client_name = 'auto optimizer stats collection';

-- Enable/Disable
EXEC DBMS_AUTO_TASK_ADMIN.ENABLE(
  client_name => 'auto optimizer stats collection',
  operation   => NULL, window_name => NULL);
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(
  client_name => 'auto optimizer stats collection',
  operation   => NULL, window_name => NULL);
```

---

## 4. SCHEDULER & JOBS

```sql
-- Tạo job đơn giản
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'NIGHTLY_STATS_JOB',
    job_type        => 'PLSQL_BLOCK',
    job_action      => q'[
      BEGIN
        DBMS_STATS.GATHER_SCHEMA_STATS(
          ownname => 'APP_USER',
          options => 'GATHER STALE',
          degree  => 4, cascade => TRUE);
      END;]',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',
    end_date        => NULL,
    enabled         => TRUE,
    auto_drop       => FALSE,
    comments        => 'Gather stale stats for APP_USER schema at 2 AM');
END;
/

-- Tạo job chạy OS script
BEGIN
  DBMS_SCHEDULER.CREATE_JOB(
    job_name    => 'RMAN_BACKUP_JOB',
    job_type    => 'EXECUTABLE',
    job_action  => '/u01/scripts/rman_backup.sh',
    start_date  => SYSTIMESTAMP,
    repeat_interval => 'FREQ=DAILY; BYHOUR=4; BYMINUTE=0',
    enabled     => TRUE);
END;
/

-- Job với Program và Schedule (tái sử dụng được)
BEGIN
  DBMS_SCHEDULER.CREATE_PROGRAM(
    program_name   => 'PRG_GATHER_STATS',
    program_type   => 'STORED_PROCEDURE',
    program_action => 'PKG_MAINTENANCE.GATHER_ALL_STALE_STATS',
    number_of_arguments => 0,
    enabled        => TRUE);

  DBMS_SCHEDULER.CREATE_SCHEDULE(
    schedule_name   => 'SCH_DAILY_2AM',
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',
    start_date      => SYSTIMESTAMP);

  DBMS_SCHEDULER.CREATE_JOB(
    job_name     => 'JOB_GATHER_STATS_V2',
    program_name => 'PRG_GATHER_STATS',
    schedule_name => 'SCH_DAILY_2AM',
    enabled      => TRUE);
END;
/

-- Job Operations
EXEC DBMS_SCHEDULER.RUN_JOB('NIGHTLY_STATS_JOB');   -- Chạy ngay
EXEC DBMS_SCHEDULER.STOP_JOB('NIGHTLY_STATS_JOB', force=>TRUE);
EXEC DBMS_SCHEDULER.DISABLE('NIGHTLY_STATS_JOB');
EXEC DBMS_SCHEDULER.ENABLE('NIGHTLY_STATS_JOB');
EXEC DBMS_SCHEDULER.DROP_JOB('NIGHTLY_STATS_JOB');

-- Monitoring Jobs
SELECT job_name, job_type, state, enabled,
       last_start_date, last_run_duration,
       next_run_date, run_count, failure_count
FROM dba_scheduler_jobs
WHERE owner = 'SYS'
  AND job_name NOT LIKE 'ORA$%'
ORDER BY last_start_date DESC;

-- Job run history
SELECT log_id, job_name, log_date, status,
       run_duration, cpu_used,
       error#, additional_info
FROM dba_scheduler_job_log
WHERE job_name = 'NIGHTLY_STATS_JOB'
ORDER BY log_date DESC
FETCH FIRST 10 ROWS ONLY;

-- Job run details (đang chạy)
SELECT job_name, session_id,
       TO_CHAR(actual_start_date,'HH24:MI:SS') start_time,
       slave_process_id
FROM dba_scheduler_running_jobs;

-- Windows (Maintenance Windows)
SELECT window_name, enabled, active,
       to_char(next_start_date,'YYYY-MM-DD HH24:MI') next_start,
       duration
FROM dba_scheduler_windows
ORDER BY window_name;
```

---

## 5. ORACLE ENTERPRISE MANAGER (OEM)

### 5.1 EM Express (miễn phí, built-in)

```sql
-- Bật EM Express (truy cập qua browser)
EXEC DBMS_XDB_CONFIG.SETHTTPPORT(5500);
-- Hoặc HTTPS:
EXEC DBMS_XDB_CONFIG.SETHTTPSPORT(5500);

-- Kiểm tra port
SELECT dbms_xdb_config.gethttpport() http,
       dbms_xdb_config.gethttpsport() https
FROM dual;

-- Truy cập: https://server:5500/em

-- PDB EM Express
ALTER SESSION SET CONTAINER = orclpdb;
EXEC DBMS_XDB_CONFIG.SETHTTPSPORT(5501);
-- Truy cập: https://server:5501/em
```

### 5.2 Cloud Control (OEM) — Key Commands

```bash
# Kiểm tra OMS status
$OMS_HOME/bin/emctl status oms
$OMS_HOME/bin/emctl start  oms
$OMS_HOME/bin/emctl stop   oms

# Kiểm tra Agent status (trên từng target server)
$AGENT_HOME/bin/emctl status  agent
$AGENT_HOME/bin/emctl start   agent
$AGENT_HOME/bin/emctl stop    agent
$AGENT_HOME/bin/emctl upload  agent  # Force upload pending metrics
$AGENT_HOME/bin/emctl ping    oms    # Test connectivity

# Discover targets
$AGENT_HOME/bin/emctl config agent addinternaltargets
```

```sql
-- Từ OEM Repository (nếu có access)
-- Xem tất cả targets và status
SELECT target_name, target_type, host_name, availability_status,
       last_metric_upload_time
FROM mgmt$target
WHERE target_type IN ('oracle_database','oracle_listener','host')
ORDER BY availability_status, target_name;

-- Alerts hiện tại
SELECT target_name, metric_column, key_value,
       alert_state, value, timestamp
FROM mgmt$alert_current
WHERE alert_state IN ('CRITICAL','WARNING')
ORDER BY timestamp DESC;
```

### 5.3 Patching qua OEM

```bash
# OEM patching workflow:
# 1. Setup: Patching Setup → My Oracle Support credentials
# 2. Patch Recommendations: Cloud Control → Targets → Patch
# 3. Staging: Stage patch to AGENT server
# 4. Prerequisites: OPatch prereq check
# 5. Apply: Schedule patching job
# 6. Verify: Post-patch verification

# OPatch Auto với OEM
$ORACLE_HOME/OPatch/opatchauto apply /patch/location \
  -oh $ORACLE_HOME \
  -ocmrf /etc/ocm.rsp
```

---

**Tài liệu tham khảo:**
- Oracle Administrator's Guide 19c: Managing Sessions
- Oracle DBMS_SCHEDULER Reference
- Oracle Database 2 Day DBA Guide (OEM)
- QT/DB.01 Phụ lục II — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
