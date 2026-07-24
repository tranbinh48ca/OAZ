---
name: oracle-storage-performance-object-backup-monitoring
description: >
  Storage, Performance, Object và Backup Monitoring Oracle chuyên sâu.
  Kích hoạt khi hỏi về: storage monitoring Oracle, dung lượng Oracle,
  monitor tablespace growth, datafile monitoring, ASM space monitoring,
  performance monitoring Oracle, real-time performance Oracle,
  object monitoring Oracle, invalid object monitoring,
  index monitoring Oracle, statistics monitoring Oracle,
  backup monitoring Oracle, RMAN monitoring, backup compliance,
  backup verification Oracle, restore test monitoring,
  growth trend Oracle, capacity trend Oracle, monitoring dashboard Oracle,
  proactive monitoring Oracle, threshold alert Oracle,
  v$sysmetric monitoring, AWR-based monitoring.
---

# SK09-02 · Storage, Performance, Object & Backup Monitoring

**Phạm vi:** Oracle Single Instance, RAC  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Tài liệu nền:** QT/DB.01 Phụ lục II — Giám sát chuyên sâu

---

## 1. STORAGE MONITORING

### 1.1 Tablespace Growth Trend

```sql
-- ── Growth trend từ AWR (90 ngày) ─────────────────────────
SELECT tablespace_name,
       TO_CHAR(snap_date,'YYYY-MM') month,
       ROUND(MAX(used_blocks * block_size)/1024/1024/1024, 2) max_used_gb
FROM (
  SELECT ts.tsname tablespace_name,
         s.begin_interval_time snap_date,
         tsu.tablespace_usedsize used_blocks,
         ts.block_size
  FROM dba_hist_tbspc_space_usage tsu
  JOIN dba_hist_tablespace_stat ts
    ON tsu.tablespace_id = ts.ts# AND tsu.snap_id = ts.snap_id
  JOIN dba_hist_snapshot s ON tsu.snap_id = s.snap_id
  WHERE s.begin_interval_time > SYSDATE - 90
)
GROUP BY tablespace_name, TO_CHAR(snap_date,'YYYY-MM')
ORDER BY tablespace_name, month;

-- ── Forecast khi tablespace đầy (linear regression) ───────
WITH trend AS (
  SELECT tablespace_name,
         ROUND(REGR_SLOPE(used_mb, days_ago), 3) growth_mb_per_day
  FROM (
    SELECT ts.tsname tablespace_name,
           ROUND(tsu.tablespace_usedsize * ts.block_size/1024/1024, 2) used_mb,
           ROUND(SYSDATE - s.begin_interval_time) days_ago
    FROM dba_hist_tbspc_space_usage tsu
    JOIN dba_hist_tablespace_stat ts
      ON tsu.tablespace_id=ts.ts# AND tsu.snap_id=ts.snap_id
    JOIN dba_hist_snapshot s ON tsu.snap_id=s.snap_id
    WHERE s.begin_interval_time > SYSDATE - 30
  )
  GROUP BY tablespace_name
)
SELECT t.tablespace_name,
       ROUND(m.used_space/1024, 2) current_used_gb,
       ROUND(m.tablespace_size/1024, 2) total_gb,
       ROUND(t.growth_mb_per_day/1024, 3) growth_gb_per_day,
       ROUND((m.tablespace_size - m.used_space)/NULLIF(t.growth_mb_per_day,0)) days_to_full,
       CASE
         WHEN (m.tablespace_size - m.used_space)/NULLIF(t.growth_mb_per_day,0) < 30
           THEN '🔴 URGENT — Action needed within 30 days'
         WHEN (m.tablespace_size - m.used_space)/NULLIF(t.growth_mb_per_day,0) < 90
           THEN '🟡 Plan expansion within 90 days'
         ELSE '🟢 OK'
       END action_needed
FROM trend t
JOIN dba_tablespace_usage_metrics m ON t.tablespace_name = m.tablespace_name
WHERE t.growth_mb_per_day > 0
ORDER BY days_to_full NULLS LAST;
```

### 1.2 Datafile Monitoring

```sql
-- Datafile autoextend status
SELECT file_name, tablespace_name,
       ROUND(bytes/1024/1024/1024, 2) current_gb,
       autoextensible,
       DECODE(maxbytes, 0, 'UNLIMITED',
              ROUND(maxbytes/1024/1024/1024, 2) || ' GB') max_size,
       ROUND(increment_by * 8192/1024/1024, 0) increment_mb
FROM dba_data_files
ORDER BY tablespace_name, file_name;

-- Datafiles gần đạt MAXSIZE
SELECT file_name, tablespace_name,
       ROUND(bytes/1024/1024/1024, 2) current_gb,
       ROUND(maxbytes/1024/1024/1024, 2) max_gb,
       ROUND(bytes/NULLIF(maxbytes,0)*100, 1) pct_of_max
FROM dba_data_files
WHERE autoextensible = 'YES'
  AND maxbytes > 0
  AND bytes/maxbytes > 0.85  -- > 85% of MAXSIZE
ORDER BY pct_of_max DESC;

-- I/O per datafile (hot files detection)
SELECT df.tablespace_name, df.name datafile,
       fs.phyrds, fs.phywrts,
       ROUND(fs.readtim/NULLIF(fs.phyrds,0), 2)  avg_read_ms,
       ROUND(fs.writetim/NULLIF(fs.phywrts,0), 2) avg_write_ms
FROM v$datafile df
JOIN v$filestat fs ON df.file# = fs.file#
ORDER BY (fs.phyrds + fs.phywrts) DESC
FETCH FIRST 15 ROWS ONLY;
```

### 1.3 ASM Storage Monitoring

```sql
-- ASM Diskgroup capacity và alerting threshold
SELECT dg.name,
       ROUND(dg.total_mb/1024, 2) total_gb,
       ROUND(dg.free_mb/1024, 2)  free_gb,
       ROUND((1-dg.free_mb/NULLIF(dg.total_mb,0))*100, 1) pct_used,
       dg.type redundancy,
       dg.offline_disks
FROM v$asm_diskgroup dg
ORDER BY pct_used DESC;

-- ASM disk balance check (rebalance health)
SELECT dg.name diskgroup, d.disk_number, d.name disk_name,
       d.mode_status, d.state,
       ROUND(d.total_mb/1024, 2) total_gb,
       ROUND(d.free_mb/1024, 2) free_gb,
       ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100, 1) pct_used
FROM v$asm_diskgroup dg
JOIN v$asm_disk d ON dg.group_number = d.group_number
ORDER BY dg.name, pct_used DESC;

-- Imbalance detection (disks trong cùng DG nên cân bằng)
SELECT dg.name diskgroup,
       MAX(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) max_pct,
       MIN(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) min_pct,
       MAX(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) -
       MIN(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) imbalance_pct
FROM v$asm_diskgroup dg
JOIN v$asm_disk d ON dg.group_number = d.group_number
GROUP BY dg.name
HAVING MAX(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) -
       MIN(ROUND((1-d.free_mb/NULLIF(d.total_mb,0))*100,1)) > 10;
-- Imbalance > 10% cần rebalance
```

---

## 2. PERFORMANCE MONITORING

### 2.1 Real-time Performance Dashboard

```sql
-- ── System Metrics Snapshot ───────────────────────────────
SELECT metric_name, ROUND(value, 2) value, metric_unit
FROM v$sysmetric
WHERE group_id = 2  -- 60-second interval
  AND metric_name IN (
    'Host CPU Utilization (%)',
    'Database CPU Time Ratio',
    'Average Active Sessions',
    'Buffer Cache Hit Ratio',
    'Library Cache Hit Ratio',
    'Memory Sorts Ratio',
    'Physical Read Total IO Requests Per Sec',
    'Physical Write Total IO Requests Per Sec',
    'Redo Generated Per Sec',
    'User Transaction Per Sec',
    'SQL Service Response Time',
    'Response Time Per Txn')
ORDER BY metric_name;

-- ── Top SQL by resource consumption (real-time) ───────────
SELECT sql_id,
       ROUND(cpu_time/1e6, 2)     cpu_sec,
       ROUND(elapsed_time/1e6, 2) ela_sec,
       executions,
       buffer_gets, disk_reads,
       parsing_schema_name,
       SUBSTR(sql_text,1,80) sql_preview
FROM v$sqlarea
WHERE last_active_time > SYSDATE - 1/24  -- 1 giờ qua
ORDER BY cpu_time DESC
FETCH FIRST 15 ROWS ONLY;

-- ── Long-running operations ───────────────────────────────
SELECT s.sid, s.serial#, s.username,
       lo.opname, lo.target,
       ROUND(lo.sofar/NULLIF(lo.totalwork,0)*100, 1) pct_complete,
       ROUND(lo.elapsed_seconds/60, 1) elapsed_min,
       ROUND(lo.time_remaining/60, 1) remaining_min
FROM v$session_longops lo
JOIN v$session s ON lo.sid = s.sid AND lo.serial# = s.serial#
WHERE lo.sofar < lo.totalwork AND lo.totalwork > 0
ORDER BY pct_complete DESC;
```

### 2.2 Wait Event Monitoring

```sql
-- ── Top wait events (1 giờ gần nhất) ──────────────────────
SELECT event, wait_class,
       total_waits,
       ROUND(time_waited_micro/1e6, 2) time_sec,
       ROUND(time_waited_micro/1e6/NULLIF(total_waits,0)*1000, 2) avg_wait_ms
FROM v$system_event
WHERE wait_class NOT IN ('Idle','Background')
ORDER BY time_waited_micro DESC
FETCH FIRST 15 ROWS ONLY;

-- ── Active session waits real-time ────────────────────────
SELECT s.sid, s.username, s.event, s.wait_class,
       s.seconds_in_wait, s.blocking_session,
       SUBSTR(q.sql_text,1,80) sql_text
FROM v$session s
LEFT JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.type = 'USER' AND s.status = 'ACTIVE'
  AND s.wait_class != 'Idle'
ORDER BY s.seconds_in_wait DESC;
```

### 2.3 Memory Performance

```sql
-- SGA component sizing
SELECT component, ROUND(current_size/1024/1024/1024, 2) current_gb
FROM v$sga_dynamic_components
ORDER BY current_size DESC;

-- Buffer cache advice
SELECT size_for_estimate, ROUND(estd_physical_read_factor, 2) io_factor
FROM v$db_cache_advice
WHERE name='DEFAULT' AND block_size=(SELECT value FROM v$parameter WHERE name='db_block_size')
ORDER BY size_for_estimate;

-- PGA monitoring
SELECT name, ROUND(value/1024/1024, 2) mb
FROM v$pgastat
WHERE name IN ('total PGA inuse','total PGA allocated',
               'maximum PGA allocated','over allocation count');
```

---

## 3. OBJECT MONITORING

### 3.1 Invalid Objects và Statistics

```sql
-- Invalid objects trend
SELECT owner, object_type, COUNT(*) cnt
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN')
GROUP BY owner, object_type
ORDER BY cnt DESC;

-- Stale statistics monitoring
SELECT owner, table_name,
       TO_CHAR(last_analyzed,'YYYY-MM-DD') last_analyzed,
       num_rows, stale_stats
FROM dba_tab_statistics
WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN')
  AND (last_analyzed IS NULL
       OR last_analyzed < SYSDATE - 14
       OR stale_stats = 'YES')
  AND num_rows > 10000
ORDER BY last_analyzed NULLS FIRST;

-- Unusable indexes
SELECT owner, index_name, table_name, status, last_analyzed
FROM dba_indexes
WHERE status = 'UNUSABLE'
  AND owner NOT IN ('SYS','SYSTEM');

-- Index fragmentation monitoring
SELECT index_name, table_name,
       blevel, leaf_blocks,
       ROUND(leaf_blocks * 8192/1024/1024, 1) index_mb
FROM dba_indexes
WHERE owner = 'APP_USER'
  AND blevel > 3   -- B-tree quá sâu cần rebuild
ORDER BY blevel DESC;
```

### 3.2 Lock và Object Contention Monitoring

```sql
-- Object-level lock monitoring
SELECT o.owner, o.object_name, o.object_type,
       COUNT(*) lock_count,
       LISTAGG(DISTINCT s.username, ',') WITHIN GROUP (ORDER BY s.username) users
FROM v$lock l
JOIN v$session s ON l.sid = s.sid
JOIN dba_objects o ON l.id1 = o.object_id
WHERE l.type = 'TM'
GROUP BY o.owner, o.object_name, o.object_type
HAVING COUNT(*) > 1
ORDER BY lock_count DESC;
```

---

## 4. BACKUP MONITORING

### 4.1 RMAN Backup Compliance

```sql
-- ── Backup history (7 ngày) ───────────────────────────────
SELECT input_type, status,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       TO_CHAR(end_time,'YYYY-MM-DD HH24:MI')   end_time,
       ROUND(input_bytes/1024/1024/1024, 2)  input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) output_gb,
       ROUND(compression_ratio, 2)           compress_ratio,
       time_taken_display elapsed
FROM v$rman_backup_job_details
WHERE start_time > SYSDATE - 7
ORDER BY start_time DESC;

-- ── Backup compliance check (alert nếu fail) ──────────────
SELECT CASE WHEN COUNT(*) = 0 THEN '🔴 NO SUCCESSFUL BACKUP IN 24H!'
            ELSE '🟢 OK: ' || COUNT(*) || ' backup(s) in 24h' END status
FROM v$rman_backup_job_details
WHERE status = 'COMPLETED'
  AND input_type = 'DB FULL'
  AND start_time > SYSDATE - 1;

-- ── Last successful backup per type ───────────────────────
SELECT input_type,
       MAX(start_time) last_backup,
       ROUND(SYSDATE - MAX(start_time), 1) days_since_backup
FROM v$rman_backup_job_details
WHERE status = 'COMPLETED'
GROUP BY input_type
ORDER BY days_since_backup DESC;

-- ── Failed backup jobs ────────────────────────────────────
SELECT session_recid, session_stamp, operation,
       status, object_type,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time
FROM v$rman_status
WHERE status != 'COMPLETED'
  AND start_time > SYSDATE - 7
ORDER BY start_time DESC;
```

### 4.2 RMAN Crosscheck và Validation

```bash
# Verify backups còn tồn tại physically (chạy hàng tuần)
rman target / << 'EOF'
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
LIST EXPIRED BACKUP;
LIST EXPIRED ARCHIVELOG ALL;
EOF

# Validate backup có thể restore được (chạy hàng tháng)
rman target / << 'EOF'
RESTORE DATABASE VALIDATE;
RESTORE ARCHIVELOG ALL VALIDATE;
EOF
```

### 4.3 Backup Monitoring Script

```bash
#!/bin/bash
# backup_monitor.sh — Kiểm tra backup compliance

export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

RESULT=$(sqlplus -S / as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM v$rman_backup_job_details
WHERE status = 'COMPLETED' AND input_type='DB FULL'
  AND start_time > SYSDATE - 1;
EXIT;
EOF
)

if [ "$RESULT" -eq 0 ]; then
  echo "⚠️ NO BACKUP COMPLETED IN LAST 24 HOURS for $ORACLE_SID" | \
    mail -s "CRITICAL: Backup Missing - $ORACLE_SID" dba-team@company.com
fi
```

---

## 5. CONSOLIDATED MONITORING DASHBOARD QUERY

```sql
-- ── Single Query Dashboard (tổng hợp tất cả vào 1 view) ──
CREATE OR REPLACE VIEW v_dba_dashboard AS
SELECT 'Tablespace' category,
       tablespace_name item,
       ROUND(used_percent,1) || '%' value,
       CASE WHEN used_percent >= 90 THEN 'CRITICAL'
            WHEN used_percent >= 80 THEN 'WARNING'
            ELSE 'OK' END status
FROM dba_tablespace_usage_metrics
UNION ALL
SELECT 'ASM Diskgroup', name,
       ROUND((1-free_mb/NULLIF(total_mb,0))*100,1) || '%',
       CASE WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 85 THEN 'CRITICAL'
            WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 70 THEN 'WARNING'
            ELSE 'OK' END
FROM v$asm_diskgroup
UNION ALL
SELECT 'FRA Usage', name,
       ROUND(space_used/NULLIF(space_limit,0)*100,1) || '%',
       CASE WHEN space_used/NULLIF(space_limit,0)*100 >= 85 THEN 'CRITICAL'
            WHEN space_used/NULLIF(space_limit,0)*100 >= 70 THEN 'WARNING'
            ELSE 'OK' END
FROM v$recovery_file_dest
UNION ALL
SELECT 'Invalid Objects', 'Total Count',
       TO_CHAR(COUNT(*)),
       CASE WHEN COUNT(*) > 10 THEN 'WARNING' ELSE 'OK' END
FROM dba_objects WHERE status='INVALID' AND owner NOT IN ('SYS','SYSTEM');

-- Query toàn bộ dashboard
SELECT * FROM v_dba_dashboard
WHERE status != 'OK'
ORDER BY category, status DESC;
```

---

**Tài liệu tham khảo:**
- QT/DB.01 Phụ lục II — Giám sát chuyên sâu, Trần Văn Bình, VietDBA
- Oracle Database Performance Tuning Guide 19c
- www.tranvanbinh.vn
