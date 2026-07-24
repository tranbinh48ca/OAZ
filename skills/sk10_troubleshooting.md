---
name: oracle-troubleshooting
description: >
  Hướng dẫn khắc phục lỗi database Oracle và multi-DB. Kích hoạt khi hỏi về:
  ORA error, lỗi Oracle, khắc phục sự cố database, troubleshoot DB,
  ORA-01555, ORA-04031, ORA-00257, ORA-01653, ORA-00020, ORA-01000,
  ORA-01578 block corrupt, ORA-00060 deadlock, database slow, DB chậm,
  performance issue, session blocked, table locked, archive full, tablespace full,
  RMAN backup fail, DataGuard gap, GoldenGate abend, RAC node down,
  node eviction, lỗi PostgreSQL, lỗi MySQL, lỗi SQL Server.
  Cung cấp root cause, steps chẩn đoán, và fix cụ thể.
---

# SK10 · Khắc phục Lỗi Database

**Phạm vi:** Oracle, PostgreSQL, SQL Server, MySQL/MariaDB  
**Tác giả:** Trần Văn Bình — VietDBA  
**Tài liệu nền:** QT/DB.01 Phụ lục IV — Hướng dẫn khắc phục lỗi

---

## PHƯƠNG PHÁP LUẬN TROUBLESHOOTING

```
1. IDENTIFY   → Xác định triệu chứng chính xác
2. ISOLATE    → Thu hẹp phạm vi: DB/OS/Network/App?
3. DIAGNOSE   → Root cause (alert log, trace, AWR, ASH)
4. FIX        → Apply fix, kiểm tra kết quả
5. PREVENT    → Bổ sung monitoring, điều chỉnh cấu hình
```

**Tools chẩn đoán Oracle:**
- Alert log: `$ORACLE_BASE/diag/rdbms/<db>/<SID>/trace/alert_<SID>.log`
- ADRCI: `adrci> show alert -tail 100`
- Trace files: `$ORACLE_BASE/diag/rdbms/<db>/<SID>/trace/`
- AWR: `@$ORACLE_HOME/rdbms/admin/awrrpt.sql`
- ASH: `@$ORACLE_HOME/rdbms/admin/ashrpt.sql`
- TKPROF: phân tích SQL trace

---

## 1. ORA-00257 — Archiver Stuck / Archive Log Full

**Triệu chứng:** Database treo, application không connect được, alert log hiện `ORA-00257: archiver error`

### Chẩn đoán

```bash
# Kiểm tra FRA usage
sqlplus -S / as sysdba << 'EOF'
SELECT name,
       ROUND(space_limit/1024/1024/1024,2) limit_gb,
       ROUND(space_used/1024/1024/1024,2)  used_gb,
       ROUND(space_used/space_limit*100,1) pct_used
FROM v$recovery_file_dest;

-- Kiểm tra archive status
SELECT dest_id, status, target, destination, error
FROM v$archive_dest WHERE status != 'INACTIVE';
EOF

# Kiểm tra disk space
df -h | grep -E "archive|fra|u02"
```

### Fix

```sql
-- Fix 1: Xóa archive log cũ qua RMAN (KHÔNG xóa file thủ công!)
rman target /
DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
CROSSCHECK ARCHIVELOG ALL;
DELETE EXPIRED ARCHIVELOG ALL;

-- Fix 2: Tăng FRA size (nếu có disk)
ALTER SYSTEM SET db_recovery_file_dest_size = 200G SCOPE=BOTH;

-- Fix 3: Thêm archive destination khác
ALTER SYSTEM SET log_archive_dest_2 = 'LOCATION=/u03/arch' SCOPE=BOTH;

-- Sau khi fix, kiểm tra lại
SELECT status FROM v$instance;
ALTER SYSTEM ARCHIVE LOG CURRENT;  -- Thử archive
```

### Phòng ngừa
```sql
-- Cron job xóa archive cũ hàng đêm
-- 0 2 * * * rman target / nocatalog << 'EOF'
-- DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7' FORCE;
-- EOF

-- Monitoring alert khi FRA > 80%
SELECT ROUND(space_used/space_limit*100,1) pct
FROM v$recovery_file_dest;
```

---

## 2. ORA-01653 / ORA-01658 — Tablespace Full

**Triệu chứng:** `ORA-01653: unable to extend table SCOTT.ORDERS by 128 in tablespace DATA`

### Chẩn đoán

```sql
-- Xem tablespace nào full
SELECT tablespace_name,
       ROUND(used_space/1024,2) used_gb,
       ROUND(tablespace_size/1024,2) total_gb,
       ROUND(used_percent,1) pct_used
FROM dba_tablespace_usage_metrics
WHERE used_percent > 80
ORDER BY pct_used DESC;

-- Xem autoextend status
SELECT file_name, tablespace_name,
       ROUND(bytes/1024/1024/1024,2) size_gb,
       autoextensible,
       ROUND(maxbytes/1024/1024/1024,2) max_gb
FROM dba_data_files
WHERE tablespace_name = 'DATA';
```

### Fix

```sql
-- Fix 1: Thêm datafile mới
ALTER TABLESPACE DATA
  ADD DATAFILE '+DATA' SIZE 20G
  AUTOEXTEND ON NEXT 1G MAXSIZE 100G;

-- Fix 2: Resize datafile hiện có
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/data01.dbf'
  RESIZE 50G;

-- Fix 3: Enable autoextend cho datafile hiện có
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/data01.dbf'
  AUTOEXTEND ON NEXT 1G MAXSIZE 100G;

-- Kiểm tra sau fix
SELECT tablespace_name, ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics
WHERE tablespace_name = 'DATA';
```

---

## 3. ORA-01555 — Snapshot Too Old

**Triệu chứng:** Long-running query báo `ORA-01555: snapshot too old: rollback segment number X with name "_SYSSMU10_..."` 

### Root cause: UNDO retention không đủ lớn so với thời gian query

### Chẩn đoán

```sql
-- Kiểm tra undo retention hiện tại
SELECT name, value FROM v$parameter
WHERE name IN ('undo_retention','undo_tablespace');

-- Kiểm tra undo tablespace usage
SELECT tablespace_name,
       ROUND(used_space/1024,2) used_gb,
       ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics
WHERE tablespace_name LIKE 'UNDO%';

-- Phân tích undo usage
SELECT maxquerylen, tuned_undoretention
FROM v$undostat
WHERE begin_time > SYSDATE - 1
ORDER BY begin_time DESC
FETCH FIRST 5 ROWS ONLY;
```

### Fix

```sql
-- Fix 1: Tăng undo_retention (dynamic)
ALTER SYSTEM SET undo_retention = 3600 SCOPE=BOTH;  -- 1 giờ

-- Fix 2: Enable retention guarantee (không tái dùng undo khi còn active)
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;

-- Fix 3: Tăng undo tablespace
ALTER TABLESPACE UNDOTBS1
  ADD DATAFILE '+DATA' SIZE 10G AUTOEXTEND ON NEXT 1G;

-- Fix 4 (application): Dùng flashback query thay SELECT trực tiếp
SELECT * FROM orders AS OF TIMESTAMP
  (SYSTIMESTAMP - INTERVAL '30' MINUTE);
```

---

## 4. ORA-04031 — Shared Pool Full

**Triệu chứng:** `ORA-04031: unable to allocate 65536 bytes of shared memory`

### Chẩn đoán

```sql
-- Kiểm tra shared pool usage
SELECT pool, name,
       ROUND(bytes/1024/1024,2) mb
FROM v$sgastat
WHERE pool = 'shared pool'
ORDER BY bytes DESC
FETCH FIRST 10 ROWS ONLY;

-- Hard parse ratio (cao = nguyên nhân chính)
SELECT ROUND(hard_parses/parse_calls*100,2) hard_parse_pct
FROM (
  SELECT SUM(CASE WHEN name='parse count (hard)' THEN value END) hard_parses,
         SUM(CASE WHEN name='parse count (total)' THEN value END) parse_calls
  FROM v$sysstat
  WHERE name IN ('parse count (hard)','parse count (total)')
);

-- SQL không dùng bind variable
SELECT substr(sql_text,1,60), count(*)
FROM v$sqlarea
WHERE executions = 1
  AND last_active_time > SYSDATE - 1/24
GROUP BY substr(sql_text,1,60)
HAVING count(*) > 10
ORDER BY count(*) DESC;
```

### Fix

```sql
-- Fix 1: Flush shared pool (khẩn cấp, ảnh hưởng performance tạm thời)
ALTER SYSTEM FLUSH SHARED_POOL;

-- Fix 2: Tăng shared_pool_size
ALTER SYSTEM SET shared_pool_size = 4G SCOPE=BOTH;

-- Fix 3: Enable cursor sharing (nếu app không dùng bind variable)
ALTER SYSTEM SET cursor_sharing = 'FORCE' SCOPE=BOTH;

-- Fix 4: Giữ objects trong memory
EXEC DBMS_SHARED_POOL.KEEP('PACKAGE_NAME');
```

---

## 5. ORA-00020 — Max Processes Exceeded

**Triệu chứng:** `ORA-00020: maximum number of processes (300) exceeded`

### Chẩn đoán

```sql
-- Xem current process count
SELECT COUNT(*) current_processes FROM v$process;
SELECT value max_processes FROM v$parameter WHERE name='processes';

-- Tìm session leak
SELECT username, machine, program, COUNT(*) cnt
FROM v$session
WHERE type='USER' AND username IS NOT NULL
GROUP BY username, machine, program
HAVING COUNT(*) > 10
ORDER BY cnt DESC;
```

### Fix

```sql
-- Fix ngay: Kill idle sessions
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;

-- Script kill tất cả idle sessions của một user/program
BEGIN
  FOR s IN (SELECT sid, serial#
            FROM v$session
            WHERE username = 'APP_USER'
              AND status = 'INACTIVE'
              AND last_call_et > 3600) LOOP
    EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' ||
                      s.sid || ',' || s.serial# || ''' IMMEDIATE';
  END LOOP;
END;
/

-- Fix lâu dài: Tăng processes (cần restart DB)
ALTER SYSTEM SET processes = 600 SCOPE=SPFILE;
-- SHUTDOWN IMMEDIATE; STARTUP;

-- Fix triệt để: Connection pooling (DRCP, UCP)
EXEC DBMS_CONNECTION_POOL.CONFIGURE_POOL(
  pool_name  => 'SYS_DEFAULT_CONNECTION_POOL',
  minsize    => 10,
  maxsize    => 100,
  incrsize   => 5);
EXEC DBMS_CONNECTION_POOL.START_POOL;
```

---

## 6. ORA-00060 — Deadlock

**Triệu chứng:** `ORA-00060: deadlock detected while waiting for resource`

### Chẩn đoán

```bash
# Tìm deadlock trace file
find $ORACLE_BASE/diag/rdbms -name "*.trc" -newer /tmp/ref \
  -exec grep -l "deadlock" {} \; | head -5

# Đọc trace file
grep -A 30 "deadlock" /path/to/trace_file.trc
```

```sql
-- Xem lock hiện tại
SELECT l1.sid sid1, l2.sid sid2,
       s1.username user1, s2.username user2,
       o.object_name, l1.type
FROM v$lock l1, v$lock l2, v$session s1, v$session s2, dba_objects o
WHERE l1.block = 1
  AND l2.request > 0
  AND l1.id1 = l2.id1
  AND l1.id2 = l2.id2
  AND s1.sid = l1.sid
  AND s2.sid = l2.sid
  AND o.object_id = l1.id1;
```

### Fix

```sql
-- Kill session gây deadlock (Oracle tự kill một session, nhưng có thể kill thủ công)
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;
```

**Fix triệt để (application):**
- Đảm bảo thứ tự truy cập table nhất quán trong mọi transactions
- Dùng `SELECT ... FOR UPDATE NOWAIT` để fail fast thay vì chờ
- Giảm thời gian giữ lock, commit sớm

---

## 7. ORA-01578 — Block Corruption

**Triệu chứng:** `ORA-01578: ORACLE data block corrupted (file # 5, block # 1234)`

### Chẩn đoán

```sql
-- Xem thông tin block
SELECT * FROM v$database_block_corruption;

-- Kiểm tra corruption với RMAN
-- RMAN:
VALIDATE DATABASE;
VALIDATE DATAFILE 5;
-- Xem kết quả:
SELECT * FROM v$database_block_corruption;

-- Dùng DBMS_REPAIR để phát hiện
BEGIN
  DBMS_REPAIR.CHECK_OBJECT(
    schema_name    => 'SCOTT',
    object_name    => 'ORDERS',
    repair_table_name => 'REPAIR_TABLE');
END;
/
```

### Fix

```sql
-- Fix 1: Block Media Recovery (từ RMAN backup) — tốt nhất
-- RMAN:
BLOCKRECOVER DATAFILE 5 BLOCK 1234;

-- Fix 2: DBMS_REPAIR.FIX_CORRUPT_BLOCKS (nếu không có backup)
-- Cảnh báo: Rows trong block bị mất!
BEGIN
  DBMS_REPAIR.FIX_CORRUPT_BLOCKS(
    schema_name  => 'SCOTT',
    object_name  => 'ORDERS',
    object_type  => DBMS_REPAIR.TABLE_OBJECT,
    repair_table_name => 'REPAIR_TABLE');
END;
/

-- Fix 3: Xuất dữ liệu bảng còn lại, drop và recreate
CREATE TABLE orders_backup AS
  SELECT /*+ ROWID(o) */ * FROM orders o
  WHERE  dbms_rowid.ROWID_BLOCK_NUMBER(ROWID) != 1234;
```

---

## 8. Database Chậm Đột Ngột

**Triệu chứng:** Application báo slow, users phàn nàn

### Chẩn đoán nhanh (5 phút)

```sql
-- Bước 1: Top waits ngay lúc này
SELECT event, wait_class, COUNT(*) sessions_waiting
FROM v$session
WHERE type='USER' AND status='ACTIVE' AND wait_class!='Idle'
GROUP BY event, wait_class
ORDER BY sessions_waiting DESC;

-- Bước 2: Top SQL đang chạy
SELECT s.sid, s.serial#, s.username,
       s.seconds_in_wait,
       s.event,
       SUBSTR(q.sql_text,1,80) sql_text,
       q.sql_id
FROM v$session s, v$sql q
WHERE s.sql_id = q.sql_id
  AND s.type='USER' AND s.status='ACTIVE'
ORDER BY s.seconds_in_wait DESC
FETCH FIRST 10 ROWS ONLY;

-- Bước 3: Execution plan thay đổi?
SELECT sql_id, plan_hash_value,
       ROUND(elapsed_time/1e6,2) elapsed_sec,
       executions,
       TO_CHAR(last_active_time,'HH24:MI:SS') last_run
FROM v$sqlarea
WHERE sql_id = '&sql_id'
ORDER BY last_active_time DESC;

-- Bước 4: System metrics
SELECT metric_name, value, metric_unit
FROM v$sysmetric
WHERE group_id = 2
  AND metric_name IN (
    'Average Active Sessions','Host CPU Utilization (%)',
    'Buffer Cache Hit Ratio','Physical Read Total IO Requests Per Sec')
ORDER BY metric_name;
```

### Root cause thường gặp & Fix

```sql
-- RC 1: Statistics thay đổi → execution plan tệ hơn
-- Fix: Lock statistics hoặc restore plan
EXEC DBMS_STATS.LOCK_TABLE_STATS('SCOTT','ORDERS');
-- Hoặc restore statistics trước thời điểm plan tệ:
EXEC DBMS_STATS.RESTORE_TABLE_STATS('SCOTT','ORDERS',
  SYSDATE - 1/24);  -- Restore về 1 giờ trước

-- RC 2: Plan change → dùng SQL Plan Baseline
SELECT sql_handle, plan_name, enabled, accepted, fixed
FROM dba_sql_plan_baselines
WHERE sql_text LIKE '%orders%';
-- Load plan cũ vào baseline, set fixed=YES

-- RC 3: Table hoặc index cần gather stats
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT','ORDERS',cascade=>TRUE);

-- RC 4: Locks/blocking → kill blocking session
SELECT blocking_session, COUNT(*) FROM v$session
WHERE blocking_session IS NOT NULL
GROUP BY blocking_session;
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;
```

---

## 9. DATAGUARD — GAP RESOLUTION (Phụ lục V)

```sql
-- Kiểm tra gap trên Primary
SELECT thread#, low_sequence#, high_sequence#
FROM v$archive_gap;

-- Kiểm tra trên Standby
SELECT thread#, sequence#, applied
FROM v$archived_log
WHERE applied = 'NO'
ORDER BY sequence# DESC;

-- Kiểm tra apply lag
SELECT name, value, datum_time
FROM v$dataguard_stats
WHERE name IN ('apply lag','transport lag','estimated startup time');
```

```bash
# Fix gap bằng RMAN incremental backup
# Trên Primary:
rman target /
BACKUP INCREMENTAL FROM SCN &current_scn
  DATABASE FORMAT '/tmp/gap_fix_%U.bkp'
  TAG 'GAP_FIX';
BACKUP CURRENT CONTROLFILE FORMAT '/tmp/standby_ctlfile.bkp';

# Copy files sang Standby, rồi:
# Trên Standby:
rman target /
CATALOG START WITH '/tmp/gap_fix_';
RECOVER DATABASE NOREDO;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT;
```

---

## 10. GOLDENGATE ABEND (Phụ lục VI — QT/DB.01)

```bash
# Kiểm tra status tất cả processes
ggsci> info all

# Xem lỗi của process bị abend
ggsci> view report EXTRACT_NAME
ggsci> view ggsevt

# Xem stats
ggsci> stats extract EXTRACT_NAME
```

### OGG-01519 — Fetch column data error

```bash
# Root cause: Schema thay đổi (thêm/bớt column) mà GG chưa được update
# Fix:
ggsci> stop extract EXT_NAME
ggsci> alter extract EXT_NAME, tranlog, begin now
ggsci> start extract EXT_NAME

# Nếu cần resync bảng:
ggsci> dblogin userid gg_user password gg_pass
ggsci> add trandata schema.table_name
```

### Restart process bị abend

```bash
# Dừng process
ggsci> stop extract  EXT_NAME
ggsci> stop pump     PMP_NAME
ggsci> stop replicat REP_NAME

# Kiểm tra trail file
ggsci> info extract EXT_NAME, detail

# Restart
ggsci> start extract  EXT_NAME
ggsci> start pump     PMP_NAME
ggsci> start replicat REP_NAME

# Monitor
ggsci> lag extract EXT_NAME
ggsci> lag replicat REP_NAME
```

---

## 11. RMAN BACKUP FAIL

```sql
-- Xem lịch sử backup
SELECT input_type, status,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start,
       TO_CHAR(end_time,'YYYY-MM-DD HH24:MI') end,
       output_device_type
FROM v$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;

-- Xem chi tiết lỗi RMAN
SELECT session_recid, session_stamp, operation,
       status, object_type, mbytes_processed, start_time
FROM v$rman_status
WHERE start_time > SYSDATE - 1
  AND status != 'COMPLETED'
ORDER BY start_time DESC;
```

```bash
# Diagnostics
rman target /
LIST BACKUP SUMMARY;
CROSSCHECK BACKUP;     # Kiểm tra backup còn tồn tại không
LIST EXPIRED BACKUP;   # Backup đã xóa nhưng catalog chưa biết
DELETE EXPIRED BACKUP; # Dọn catalog

# Test backup
BACKUP VALIDATE DATABASE;   # Không ghi file, chỉ kiểm tra
RESTORE VALIDATE DATABASE;  # Kiểm tra có thể restore không
```

---

## 12. POSTGRESQL — Lỗi phổ biến

```bash
# Table bloat — autovacuum không kịp
psql -U postgres -c "
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) total,
       pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) table_size,
       n_dead_tup dead_tuples
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC LIMIT 10;"

# Manual VACUUM
psql -U postgres -c "VACUUM ANALYZE schema.big_table;"

# Max connections
psql -U postgres -c "SHOW max_connections;"
psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

# Kill idle connections
psql -U postgres -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
  AND state = 'idle'
  AND query_start < NOW() - INTERVAL '1 hour';"

# Replication broken
psql -U postgres -c "SELECT * FROM pg_stat_replication;"
# Nếu slot bị stuck:
psql -U postgres -c "SELECT * FROM pg_replication_slots WHERE active='f';"
psql -U postgres -c "SELECT pg_drop_replication_slot('slot_name');"
```

---

## 13. MYSQL/MARIADB — Lỗi phổ biến

```bash
# Replication lag
mysql -u root -p -e "SHOW SLAVE STATUS\G" | grep -E "Seconds|Running|Error"

# Fix replication error (skip lỗi)
mysql -u root -p -e "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1; START SLAVE;"

# Kiểm tra và sửa table
mysqlcheck --all-databases --check --auto-repair -u root -p

# InnoDB buffer pool (phải > 99%)
mysql -u root -p -e "
SHOW STATUS LIKE 'Innodb_buffer_pool_read%';"

# Long running queries
mysql -u root -p -e "SHOW FULL PROCESSLIST;" | \
  awk '$6>60 {print}'

# Kill query
mysql -u root -p -e "KILL QUERY <process_id>;"
```

---

## 14. ESCALATION — Oracle SR

```bash
# Thu thập thông tin khi mở SR với Oracle Support

# 1. RDA (Remote Diagnostic Agent)
perl rda.pl -S

# 2. OSWatcher (OS metrics)
./startOSWbb.sh 30 48  # Thu thập 48 giờ, mỗi 30 giây

# 3. SQLT (SQL Tuning)
sqlplus / as sysdba
@sqlt.zip  -- Unzip và chạy sqltxecute.sql với SQL_ID

# 4. AWR range
@$ORACLE_HOME/rdbms/admin/awrrpti.sql  -- Interactive

# 5. Alert log và trace files liên quan
find $ORACLE_BASE/diag -name "*.trc" -newer /tmp/incident_time | \
  head -20
```

---

## Tài liệu tham khảo
- QT/DB.01 Phụ lục IV, V, VI — Trần Văn Bình, VietDBA
- Oracle Error Help: docs.oracle.com/error-help/db/
- MOS (My Oracle Support): support.oracle.com
- www.tranvanbinh.vn — Khắc phục lỗi Oracle thực tế
