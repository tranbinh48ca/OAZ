---
name: oracle-monitoring-operations
description: >
  Quy trình giám sát, vận hành và khai thác cơ sở dữ liệu Oracle hàng ngày.
  Kích hoạt khi hỏi về: giám sát database, health check, kiểm tra định kỳ,
  vận hành oracle, check session, check tablespace, check backup, check ASM,
  check listener, check cluster, alert log, monitoring script, KPI database,
  checklist vận hành, bảo trì định kỳ, AWR report, capacity planning,
  quy trình phối hợp DBA, incident management, daily check oracle.
  Cung cấp SQL scripts, checklist thực tế dựa trên QT/DB.01.
---

# SK09 · Giám sát · Vận hành · Khai thác Database

**Phạm vi:** Oracle, PostgreSQL, SQL Server, MySQL/MariaDB  
**Tác giả:** Trần Văn Bình — VietDBA  
**Tài liệu nền:** QT/DB.01 Phụ lục I, II, III — Kiểm tra định kỳ, Vận hành, Bảo trì

---

## 1. KPI CƠ SỞ DỮ LIỆU

| KPI | Oracle | PostgreSQL | SQL Server | MySQL |
|-----|--------|------------|------------|-------|
| Uptime | ≥ 99.9% | ≥ 99.9% | ≥ 99.9% | ≥ 99.9% |
| Backup success | 100% | 100% | 100% | 100% |
| Archive gap (DataGuard) | 0 | 0 WAL lag | 0 | 0 |
| Tablespace used | < 85% | < 85% | < 85% | < 85% |
| Buffer cache hit ratio | ≥ 95% | — | ≥ 90% | ≥ 90% |
| Max sessions used | < 80% | — | — | — |
| Index invalid | 0 | — | — | — |
| Invalid objects | 0 | — | — | — |

---

## 2. DAILY HEALTH CHECK — ORACLE (Phụ lục I)

### 2.1 Script Health Check Tổng hợp

```sql
-- ===== ORACLE DAILY HEALTH CHECK =====
-- Chạy mỗi sáng, lưu output vào log

PROMPT ===== 1. DATABASE STATUS =====
SELECT instance_name, host_name, version,
       status, database_status, logins,
       TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       ROUND(SYSDATE - startup_time,1) uptime_days
FROM   v$instance;

SELECT open_mode, log_mode, protection_mode,
       db_unique_name
FROM   v$database;

PROMPT ===== 2. SESSION SUMMARY =====
SELECT status,
       COUNT(*) cnt,
       ROUND(COUNT(*)*100 /
             (SELECT value FROM v$parameter WHERE name='sessions'),1) pct_of_max
FROM   v$session
WHERE  type = 'USER'
GROUP  BY status
ORDER  BY status;

SELECT value max_sessions FROM v$parameter WHERE name = 'sessions';

PROMPT ===== 3. ACTIVE & BLOCKING SESSIONS =====
SELECT s.sid, s.serial#, s.username, s.status,
       s.wait_class, s.event,
       s.seconds_in_wait wait_sec,
       s.blocking_session,
       SUBSTR(s.machine,1,20) machine,
       SUBSTR(q.sql_text,1,60) sql_text
FROM   v$session s
LEFT   JOIN v$sql q ON s.sql_id = q.sql_id
WHERE  s.type = 'USER'
  AND  s.status IN ('ACTIVE','KILLED')
ORDER  BY s.seconds_in_wait DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT ===== 4. TABLESPACE USAGE =====
SELECT tablespace_name,
       ROUND(used_space/1024,2)      used_gb,
       ROUND(tablespace_size/1024,2) total_gb,
       ROUND(used_percent,1)         pct_used,
       CASE WHEN used_percent >= 90 THEN 'CRITICAL ⚠️'
            WHEN used_percent >= 80 THEN 'WARNING ⚡'
            ELSE 'OK ✓' END          status_flag
FROM   dba_tablespace_usage_metrics
ORDER  BY pct_used DESC;

PROMPT ===== 5. ASM DISKGROUP STATUS =====
SELECT name, state, type,
       ROUND(total_mb/1024,2) total_gb,
       ROUND(free_mb/1024,2)  free_gb,
       ROUND((1-free_mb/NULLIF(total_mb,0))*100,1) pct_used,
       CASE WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 85 THEN 'CRITICAL'
            WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 70 THEN 'WARNING'
            ELSE 'OK' END status_flag
FROM   v$asm_diskgroup
ORDER  BY name;

PROMPT ===== 6. INVALID OBJECTS =====
SELECT owner, object_type, COUNT(*) cnt
FROM   dba_objects
WHERE  status = 'INVALID'
  AND  owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN',
                     'MDSYS','ORDSYS','EXFSYS','DMSYS')
GROUP  BY owner, object_type
ORDER  BY owner, object_type;

PROMPT ===== 7. UNUSABLE INDEXES =====
SELECT owner, index_name, table_name, status
FROM   dba_indexes
WHERE  status = 'UNUSABLE'
  AND  owner NOT IN ('SYS','SYSTEM')
ORDER  BY owner;

PROMPT ===== 8. STALE / MISSING STATISTICS =====
SELECT owner, table_name,
       TO_CHAR(last_analyzed,'YYYY-MM-DD') last_analyzed,
       num_rows,
       stale_stats
FROM   dba_tab_statistics
WHERE  owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN')
  AND  (last_analyzed IS NULL
        OR last_analyzed < SYSDATE - 14
        OR stale_stats = 'YES')
  AND  num_rows > 10000
ORDER  BY last_analyzed NULLS FIRST
FETCH FIRST 20 ROWS ONLY;

PROMPT ===== 9. RMAN BACKUP STATUS (7 ngày) =====
SELECT input_type,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       status,
       ROUND(input_bytes/1024/1024/1024,2) input_gb,
       ROUND(elapsed_seconds/60,1)         elapsed_min
FROM   v$rman_backup_job_details
WHERE  start_time > SYSDATE - 7
ORDER  BY start_time DESC;

PROMPT ===== 10. FRA USAGE =====
SELECT name,
       ROUND(space_limit/1024/1024/1024,2) limit_gb,
       ROUND(space_used/1024/1024/1024,2)  used_gb,
       ROUND(space_used/NULLIF(space_limit,0)*100,1) pct_used
FROM   v$recovery_file_dest;

PROMPT ===== 11. TOP WAIT EVENTS (last hour) =====
SELECT event, wait_class,
       ROUND(time_waited_micro/1e6,2) time_sec,
       total_waits,
       ROUND(time_waited_micro/SUM(time_waited_micro) OVER()*100,1) pct
FROM   v$system_event
WHERE  wait_class != 'Idle'
  AND  total_waits > 0
ORDER  BY time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT ===== 12. ALERT LOG ERRORS (last 24h) =====
SELECT originating_timestamp,
       SUBSTR(message_text,1,200) message
FROM   v$diag_alert_ext
WHERE  originating_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
  AND  message_type IN (3,4)  -- ERROR, INCIDENT
ORDER  BY originating_timestamp DESC
FETCH FIRST 20 ROWS ONLY;
```

### 2.2 Shell Script — Daily Check (tự động gửi email)

```bash
#!/bin/bash
# daily_health_check.sh — VietDBA QT/DB.01
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
DATE=$(date '+%Y-%m-%d %H:%M')
REPORT="/tmp/db_health_${ORACLE_SID}_$(date +%Y%m%d).txt"
MAIL_TO="dba-team@company.com"

echo "===== Oracle Health Check - $ORACLE_SID - $DATE =====" > $REPORT
echo "" >> $REPORT

# 1. Check listener
echo "[LISTENER STATUS]" >> $REPORT
lsnrctl status 2>&1 | grep -E "Status|Uptime|Service" >> $REPORT
echo "" >> $REPORT

# 2. Check alert log errors (last 24h)
echo "[ALERT LOG ERRORS]" >> $REPORT
find $ORACLE_BASE/diag/rdbms -name "alert_*.log" -exec \
  awk -v date="$(date -d '1 day ago' '+%a %b %d')" \
  '$0 ~ date,0 {if (/ORA-|Error|error/) print}' {} \; >> $REPORT 2>/dev/null
echo "" >> $REPORT

# 3. SQL checks
sqlplus -S / as sysdba << SQLEOF >> $REPORT 2>&1
SET LINESIZE 200 PAGESIZE 50 TRIMSPOOL ON
SET FEEDBACK OFF HEADING ON
@/u01/scripts/health_check.sql
EXIT;
SQLEOF

# 4. Gửi email nếu có vấn đề
if grep -q "CRITICAL\|ORA-\|UNUSABLE\|INVALID" $REPORT; then
  SUBJECT="⚠️ ALERT: Oracle DB Health Check - $ORACLE_SID - $DATE"
else
  SUBJECT="✓ OK: Oracle DB Health Check - $ORACLE_SID - $DATE"
fi

mail -s "$SUBJECT" $MAIL_TO < $REPORT
echo "Report sent: $REPORT"
```

---

## 3. CHECKLIST BẢO TRÌ ĐỊNH KỲ (Phụ lục III)

### 3.1 Weekly Maintenance Checklist

```bash
#!/bin/bash
# weekly_maintenance.sh — QT/DB.01 Phụ lục III

echo "===== WEEKLY MAINTENANCE CHECKLIST ====="

# 3.1 Kiểm tra disk space
echo "[DISK SPACE]"
df -h | grep -v tmpfs

# 3.2 Kiểm tra CRS status (RAC)
echo "[CRS STATUS]"
crsctl stat res -t

# 3.3 Kiểm tra OCR
echo "[OCR STATUS]"
ocrcheck

# 3.4 Kiểm tra Voting Disk
echo "[VOTING DISK]"
crsctl query css votedisk

# 3.5 Test archive switch
echo "[ARCHIVE SWITCH TEST]"
sqlplus -S / as sysdba << 'EOF'
ALTER SYSTEM SWITCH LOGFILE;
SELECT sequence#, applied, name FROM v$archived_log
WHERE sequence# = (SELECT MAX(sequence#) FROM v$archived_log);
EXIT;
EOF
```

```sql
-- 3.6 Kiểm tra tần suất log switch (lý tưởng: 15-30 phút/lần)
SELECT TO_CHAR(first_time,'YYYY-MM-DD HH24') hour_slot,
       COUNT(*) switches_count
FROM   v$log_history
WHERE  first_time > SYSDATE - 3
GROUP  BY TO_CHAR(first_time,'YYYY-MM-DD HH24')
ORDER  BY 1 DESC;

-- 3.7 Chạy và kiểm tra AWR report
SELECT snap_id,
       TO_CHAR(begin_interval_time,'YYYY-MM-DD HH24:MI') begin_time,
       TO_CHAR(end_interval_time,'YYYY-MM-DD HH24:MI')   end_time
FROM   dba_hist_snapshot
WHERE  begin_interval_time > SYSDATE - 1
ORDER  BY snap_id DESC;

-- Tạo AWR report (từ snap ID 100 đến 110)
-- @$ORACLE_HOME/rdbms/admin/awrrpt.sql
-- Hoặc:
SELECT dbms_workload_repository.awr_report_text(
         dbid          => (SELECT dbid FROM v$database),
         inst_num      => 1,
         bid           => 100,
         eid           => 110)
FROM   dual;

-- 3.8 Performance tổng quát
SELECT metric_name,
       ROUND(value,2) value,
       metric_unit
FROM   v$sysmetric
WHERE  group_id = 2
  AND  metric_name IN (
    'Buffer Cache Hit Ratio',
    'Library Cache Hit Ratio',
    'Memory Sorts Ratio',
    'Physical Read Total IO Requests Per Sec',
    'User Transaction Per Sec',
    'Average Active Sessions',
    'DB Block Changes Per Sec')
ORDER  BY metric_name;
```

---

## 4. MONITORING PostgreSQL

```bash
# Kiểm tra service
systemctl status postgresql-14
systemctl status patroni   # Nếu dùng Patroni HA

# Kiểm tra không gian trống
df -h | grep pgdata

# Xem log
tail -100 /var/log/postgresql/postgresql-$(date +%Y-%m-%d).log | \
  grep -E "ERROR|FATAL|PANIC"

# Kiểm tra replication lag
psql -U postgres -c "
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       (sent_lsn - replay_lsn) AS lag_bytes
FROM pg_stat_replication;"

# Kiểm tra database size
psql -U postgres -c "
SELECT datname,
       pg_size_pretty(pg_database_size(datname)) db_size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;"

# Kiểm tra connections
psql -U postgres -c "
SELECT count(*) total,
       sum(CASE WHEN state='active' THEN 1 ELSE 0 END) active,
       sum(CASE WHEN state='idle'   THEN 1 ELSE 0 END) idle,
       sum(CASE WHEN wait_event_type IS NOT NULL THEN 1 ELSE 0 END) waiting
FROM pg_stat_activity WHERE pid <> pg_backend_pid();"

# Kiểm tra long-running queries
psql -U postgres -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration,
       query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
  AND state = 'active';"
```

---

## 5. MONITORING SQL SERVER

```sql
-- Kiểm tra database status
SELECT name, state_desc, log_reuse_wait_desc,
       is_read_only, user_access_desc
FROM   sys.databases
ORDER  BY name;

-- Kiểm tra disk usage
EXEC sp_helpdb;

-- Kiểm tra space per database
SELECT DB_NAME(database_id) db_name,
       ROUND(SUM(size) * 8.0/1024/1024,2) size_gb
FROM   sys.master_files
WHERE  type = 0
GROUP  BY database_id
ORDER  BY size_gb DESC;

-- Active sessions & blocking
SELECT r.session_id, r.status, r.blocking_session_id,
       r.wait_type, r.wait_time/1000.0 wait_sec,
       r.cpu_time/1000.0 cpu_sec,
       SUBSTRING(t.text,1,80) sql_text
FROM   sys.dm_exec_requests r
CROSS  APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE  r.session_id > 50
ORDER  BY r.wait_time DESC;

-- Kiểm tra backup history (7 ngày)
SELECT d.name, b.type,
       MAX(b.backup_finish_date) last_backup,
       DATEDIFF(HOUR, MAX(b.backup_finish_date), GETDATE()) hours_ago
FROM   sys.databases d
LEFT   JOIN msdb.dbo.backupset b ON d.name = b.database_name
  AND  b.backup_finish_date > DATEADD(DAY,-7,GETDATE())
WHERE  d.database_id > 4
GROUP  BY d.name, b.type
ORDER  BY d.name, b.type;

-- AlwaysOn AG status
SELECT ag.name ag_name, ar.role_desc,
       ars.synchronization_state_desc,
       ars.synchronization_health_desc,
       ars.log_send_queue_size,
       ars.redo_queue_size
FROM   sys.availability_groups ag
JOIN   sys.dm_hadr_availability_replica_states ars
  ON   ag.group_id = ars.group_id
JOIN   sys.availability_replicas ar
  ON   ars.replica_id = ar.replica_id;
```

---

## 6. MONITORING MySQL/MariaDB

```sql
-- Kiểm tra status
SHOW GLOBAL STATUS LIKE 'Threads_connected';
SHOW GLOBAL STATUS LIKE 'Uptime';

-- Slow queries
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- Kiểm tra replication
SHOW SLAVE STATUS\G
-- Quan trọng: Seconds_Behind_Master, Slave_IO_Running, Slave_SQL_Running

-- Connections
SELECT count(*) total,
       SUM(CASE WHEN command='Sleep' THEN 1 ELSE 0 END) idle,
       SUM(CASE WHEN command<>'Sleep' THEN 1 ELSE 0 END) active
FROM   information_schema.processlist;

-- InnoDB status
SHOW ENGINE INNODB STATUS\G

-- Buffer pool hit ratio (phải > 99%)
SELECT ROUND(
         (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100,
       2) hit_ratio_pct
FROM (
  SELECT variable_value Innodb_buffer_pool_reads
  FROM   information_schema.global_status
  WHERE  variable_name = 'Innodb_buffer_pool_reads'
) t1,
(
  SELECT variable_value Innodb_buffer_pool_read_requests
  FROM   information_schema.global_status
  WHERE  variable_name = 'Innodb_buffer_pool_read_requests'
) t2;
```

---

## 7. QUYTRÌNH PHỐI HỢP CÔNG VIỆC (Phụ lục XII — QT/DB.01)

| Loại yêu cầu | Quy trình | Cấp phê duyệt |
|---|---|---|
| Tạo/khóa user | App Team → văn bản → DBA Team | LĐTCT (hệ thống Core) |
| Cấp quyền DB | App Admin → Lãnh đạo PA → DBA Tổ trưởng → DBA thực hiện → Thu hồi sau | LĐTCT (bảng nhạy cảm) |
| Update bảng/thủ tục | App Admin → Lãnh đạo PA → DBA → App test → confirm | LĐTT (ảnh hưởng > 5 phút: LĐTCT) |
| Tối ưu SQL | App Admin → DBA → App test | LĐTT |
| Bổ sung GoldenGate | App Admin → DBA | LĐTT (chú ý tăng tải) |
| Giải phóng session | App Admin → DBA (cc lãnh đạo 2 phòng) | — |
| Kiểm tra lỗi/chậm | App Admin → DBA Tổ trưởng | Theo quy trình ứng cứu nếu diện rộng |
| Cài đặt DB mới | Phòng App → văn bản → Lãnh đạo Phòng Hạ tầng | LĐTT (cần nguồn lực) |

---

## 8. INCIDENT MANAGEMENT

### 8.1 Phân loại Incident

| Priority | Mô tả | Response | Resolution |
|---------|--------|----------|------------|
| P1 | DB down, data loss, 100% user ảnh hưởng | 15 phút | 4 giờ |
| P2 | Performance degradation nghiêm trọng, core function fail | 30 phút | 8 giờ |
| P3 | Một function bị lỗi, có workaround | 2 giờ | 24 giờ |
| P4 | Yêu cầu thay đổi, cải tiến | Next sprint | — |

### 8.2 Emergency Response Script

```bash
#!/bin/bash
# emergency_check.sh — Chạy khi nhận alert P1

export ORACLE_SID=$1
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

echo "===== EMERGENCY DB CHECK ====="
echo "DB: $ORACLE_SID | Time: $(date)"

# Kiểm tra DB còn sống không
if ! sqlplus -S / as sysdba <<< "SELECT 1 FROM dual;" > /dev/null 2>&1; then
  echo "❌ DATABASE DOWN - Attempting startup..."
  sqlplus / as sysdba << 'EOF'
  STARTUP;
  EXIT;
EOF
  exit 1
fi

# Snapshot nhanh tình trạng
sqlplus -S / as sysdba << 'EOF'
SET LINESIZE 200 PAGESIZE 50

-- Sessions
SELECT status, COUNT(*) FROM v$session WHERE type='USER' GROUP BY status;

-- Top waits
SELECT event, COUNT(*) cnt
FROM v$session WHERE type='USER' AND status='ACTIVE' AND wait_class!='Idle'
GROUP BY event ORDER BY cnt DESC FETCH FIRST 5 ROWS ONLY;

-- Blocking sessions
SELECT blocking_session, COUNT(*) blocked
FROM v$session WHERE blocking_session IS NOT NULL
GROUP BY blocking_session ORDER BY blocked DESC;

-- Tablespace critical
SELECT tablespace_name, ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics WHERE used_percent >= 90;

EXIT;
EOF

# Tail alert log
echo "--- ALERT LOG (last 50 lines) ---"
find $ORACLE_BASE/diag/rdbms -name "alert_*.log" | \
  head -1 | xargs tail -50 | grep -E "ORA-|Error|warning" | tail -20
```

---

## 9. CAPACITY PLANNING

```sql
-- Tablespace growth trend (từ AWR)
SELECT tablespace_name,
       TO_CHAR(snap_date,'YYYY-MM') month,
       ROUND(MAX(used_blocks * block_size)/1024/1024/1024,2) max_used_gb
FROM (
  SELECT ts.tsname tablespace_name,
         s.begin_interval_time snap_date,
         tsu.tablespace_usedsize used_blocks,
         ts.block_size
  FROM   dba_hist_tbspc_space_usage tsu
  JOIN   dba_hist_tablespace_stat ts
    ON   tsu.tablespace_id = ts.ts# AND tsu.snap_id = ts.snap_id
  JOIN   dba_hist_snapshot s ON tsu.snap_id = s.snap_id
  WHERE  s.begin_interval_time > SYSDATE - 90
)
GROUP BY tablespace_name, TO_CHAR(snap_date,'YYYY-MM')
ORDER BY tablespace_name, month;

-- Forecast khi tablespace đầy (dựa trên trend 30 ngày)
WITH trend AS (
  SELECT tablespace_name,
         ROUND(REGR_SLOPE(used_mb, days_ago),2) growth_mb_per_day
  FROM (
    SELECT ts.tsname tablespace_name,
           ROUND(tsu.tablespace_usedsize * ts.block_size/1024/1024,2) used_mb,
           ROUND(SYSDATE - s.begin_interval_time) days_ago
    FROM   dba_hist_tbspc_space_usage tsu
    JOIN   dba_hist_tablespace_stat ts ON tsu.tablespace_id=ts.ts# AND tsu.snap_id=ts.snap_id
    JOIN   dba_hist_snapshot s ON tsu.snap_id=s.snap_id
    WHERE  s.begin_interval_time > SYSDATE - 30
  )
  GROUP BY tablespace_name
)
SELECT t.tablespace_name,
       ROUND(m.used_space/1024,2) current_used_gb,
       ROUND(m.tablespace_size/1024,2) total_gb,
       ROUND(t.growth_mb_per_day/1024,3) growth_gb_day,
       ROUND((m.tablespace_size - m.used_space) / NULLIF(t.growth_mb_per_day,0)) days_to_full
FROM   trend t
JOIN   dba_tablespace_usage_metrics m ON t.tablespace_name = m.tablespace_name
WHERE  t.growth_mb_per_day > 0
ORDER  BY days_to_full NULLS LAST;
```

---

## Tài liệu tham khảo
- QT/DB.01 — Trần Văn Bình, VietDBA (2024)
- Oracle Database Reference V$views: docs.oracle.com
- www.tranvanbinh.vn — Scripts và hướng dẫn thực chiến
