---
name: oracle-awr-ash-addm-analysis
description: >
  AWR, ASH và ADDM Analysis cho Oracle Performance Diagnostics.
  Kích hoạt khi hỏi về: AWR Oracle, Automatic Workload Repository,
  AWR report, ASH Active Session History, ADDM Automatic Database
  Diagnostic Monitor, phân tích hiệu năng Oracle, v$active_session_history,
  dba_hist_active_sess_history, AWR snapshot, AWR baseline,
  AWR compare report, ASH report, ADDM findings, ADDM recommendations,
  dba_hist_sqlstat top SQL AWR, v$sysmetric performance metrics,
  wait events Oracle, DB Time Oracle performance, AAS average active sessions,
  buffer cache hit ratio AWR, redo rate AWR, hard parse ratio,
  ASH sampling, real-time ASH, PDB performance AWR.
---

# SK05-01 · AWR, ASH & ADDM Analysis

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. AWR — AUTOMATIC WORKLOAD REPOSITORY

### 1.1 Snapshot Management

```sql
-- Xem AWR configuration
SELECT snap_interval, retention, topnsql
FROM dba_hist_wr_control;
-- snap_interval: +00000 01:00:00.0 = mỗi 1 giờ
-- retention:     +00008 00:00:00.0 = giữ 8 ngày

-- Điều chỉnh AWR settings
EXEC DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(
  retention => 30*24*60,   -- 30 ngày (phút)
  interval  => 30,         -- Snapshot mỗi 30 phút
  topnsql   => 30          -- Top 30 SQL statements
);

-- Tạo snapshot thủ công (trước/sau khi test)
SELECT DBMS_WORKLOAD_REPOSITORY.CREATE_SNAPSHOT() snap_id FROM dual;

-- Xem snapshots gần đây
SELECT snap_id,
       TO_CHAR(begin_interval_time,'YYYY-MM-DD HH24:MI') begin_time,
       TO_CHAR(end_interval_time,'YYYY-MM-DD HH24:MI')   end_time,
       ROUND((end_interval_time-begin_interval_time)*24*60,1) duration_min
FROM dba_hist_snapshot
WHERE begin_interval_time > SYSDATE - 2
ORDER BY snap_id DESC;

-- Drop snapshots cũ (giải phóng SYSAUX space)
EXEC DBMS_WORKLOAD_REPOSITORY.DROP_SNAPSHOT_RANGE(
  low_snap_id  => 100,
  high_snap_id => 200,
  dbid         => (SELECT dbid FROM v$database)
);

-- Xem SYSAUX space usage
SELECT occupant_name, occupant_desc,
       ROUND(space_usage_kbytes/1024, 2) space_mb
FROM v$sysaux_occupants
WHERE occupant_name = 'SM/AWR';
```

### 1.2 AWR Baselines

```sql
-- AWR Baseline: lưu snapshot range để so sánh
-- Dùng để: so sánh "before patch" vs "after patch"

-- Tạo baseline từ range snapshots
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE(
  start_snap_id  => 1200,
  end_snap_id    => 1224,
  baseline_name  => 'BEFORE_PATCH_19_21',
  expiration     => 30    -- Giữ 30 ngày (null = không expire)
);

-- Tạo baseline template (repeating schedule)
EXEC DBMS_WORKLOAD_REPOSITORY.CREATE_BASELINE_TEMPLATE(
  start_time    => TO_TIMESTAMP('2026-01-15 08:00:00','YYYY-MM-DD HH24:MI:SS'),
  end_time      => TO_TIMESTAMP('2026-01-15 18:00:00','YYYY-MM-DD HH24:MI:SS'),
  baseline_name => 'BUSINESS_HOURS_JAN',
  template_name => 'BUSINESS_HOURS_DAILY',
  expiration    => NULL
);

-- Xem baselines
SELECT baseline_name, baseline_type, start_snap_id, end_snap_id,
       TO_CHAR(start_snap_time,'YYYY-MM-DD HH24:MI') start_time,
       TO_CHAR(end_snap_time,'YYYY-MM-DD HH24:MI')   end_time
FROM dba_hist_baseline
ORDER BY baseline_id;

-- Delete baseline
EXEC DBMS_WORKLOAD_REPOSITORY.DROP_BASELINE(
  baseline_name => 'BEFORE_PATCH_19_21',
  cascade       => FALSE  -- TRUE: xóa cả snapshots
);
```

### 1.3 Tạo AWR Reports

```bash
# ── AWR HTML Report (từ script Oracle) ──────────────────
sqlplus / as sysdba
# Interactive:
@$ORACLE_HOME/rdbms/admin/awrrpt.sql
# 1. Chọn format: html hoặc text
# 2. Nhập số ngày cần xem
# 3. Chọn begin_snap_id và end_snap_id

# ── AWR Text Report (từ SQL) ─────────────────────────────
```

```sql
-- Tạo AWR report text từ SQL (không cần interactive)
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid     => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => &begin_snap_id,
    l_eid      => &end_snap_id,
    l_options  => 0  -- 0=default, 8=show RAC
  )
);

-- AWR HTML report
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_HTML(
    l_dbid     => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => 1200,
    l_eid      => 1224
  )
);

-- AWR Compare Report (so sánh 2 khoảng thời gian)
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_DIFF_REPORT_TEXT(
    dbid1     => (SELECT dbid FROM v$database),
    inst_num1 => 1,
    bid1      => 1200,  -- Period 1: before
    eid1      => 1210,
    dbid2     => (SELECT dbid FROM v$database),
    inst_num2 => 1,
    bid2      => 1300,  -- Period 2: after
    eid2      => 1310
  )
);

-- AWR Global Report (RAC - tất cả instances)
@$ORACLE_HOME/rdbms/admin/awrgrpt.sql
```

### 1.4 Phân tích AWR Key Metrics từ SQL

```sql
-- ── TOP SQL BY CPU TIME (AWR) ─────────────────────────────
SELECT sql_id,
       ROUND(SUM(cpu_time_delta)/1e6, 2)      total_cpu_sec,
       SUM(executions_delta)                  total_execs,
       ROUND(SUM(cpu_time_delta)/1e6
         / NULLIF(SUM(executions_delta),0), 3) cpu_per_exec,
       ROUND(SUM(elapsed_time_delta)/1e6, 2)  total_ela_sec,
       ROUND(SUM(buffer_gets_delta)
         / NULLIF(SUM(executions_delta),0))    gets_per_exec,
       ROUND(SUM(disk_reads_delta)
         / NULLIF(SUM(executions_delta),0))    reads_per_exec
FROM dba_hist_sqlstat s
JOIN dba_hist_snapshot sn
  ON s.snap_id = sn.snap_id AND s.dbid = sn.dbid
  AND s.instance_number = sn.instance_number
WHERE sn.begin_interval_time > SYSDATE - 1   -- 1 ngày gần nhất
GROUP BY sql_id
ORDER BY total_cpu_sec DESC
FETCH FIRST 20 ROWS ONLY;

-- ── TOP SQL BY I/O (DISK READS) ───────────────────────────
SELECT sql_id,
       SUM(disk_reads_delta)                  total_disk_reads,
       SUM(executions_delta)                  execs,
       ROUND(SUM(disk_reads_delta)
         / NULLIF(SUM(executions_delta),0))   reads_per_exec,
       ROUND(SUM(elapsed_time_delta)/1e6, 2)  elapsed_sec
FROM dba_hist_sqlstat s
JOIN dba_hist_snapshot sn
  ON s.snap_id = sn.snap_id AND s.dbid = sn.dbid
  AND s.instance_number = sn.instance_number
WHERE sn.begin_interval_time > SYSDATE - 1
GROUP BY sql_id
ORDER BY total_disk_reads DESC
FETCH FIRST 10 ROWS ONLY;

-- ── SYSTEM METRICS TREND ─────────────────────────────────
SELECT TO_CHAR(sn.begin_interval_time,'HH24:MI') hour,
       ROUND(AVG(CASE WHEN m.metric_name='Host CPU Utilization (%)'
                 THEN m.average END), 1)    host_cpu_pct,
       ROUND(AVG(CASE WHEN m.metric_name='Average Active Sessions'
                 THEN m.average END), 2)    avg_active_sessions,
       ROUND(AVG(CASE WHEN m.metric_name='Buffer Cache Hit Ratio'
                 THEN m.average END), 1)    cache_hit_pct,
       ROUND(AVG(CASE WHEN m.metric_name='Redo Generated Per Sec'
                 THEN m.average END)/1024, 1) redo_kb_per_sec
FROM dba_hist_sysmetric_summary m
JOIN dba_hist_snapshot sn
  ON m.snap_id = sn.snap_id AND m.dbid = sn.dbid
  AND m.instance_number = sn.instance_number
WHERE sn.begin_interval_time > SYSDATE - 1
  AND m.metric_name IN (
    'Host CPU Utilization (%)',
    'Average Active Sessions',
    'Buffer Cache Hit Ratio',
    'Redo Generated Per Sec')
GROUP BY TO_CHAR(sn.begin_interval_time,'HH24:MI')
ORDER BY 1;

-- ── WAIT EVENT HISTORY ───────────────────────────────────
SELECT e.event_name,
       e.wait_class,
       SUM(e.total_waits_delta)           total_waits,
       ROUND(SUM(e.time_waited_micro_delta)/1e6, 2) time_waited_sec,
       ROUND(SUM(e.time_waited_micro_delta)/1e6
         / NULLIF(SUM(e.total_waits_delta),0)*1000, 2) avg_wait_ms
FROM dba_hist_system_event e
JOIN dba_hist_snapshot sn
  ON e.snap_id = sn.snap_id AND e.dbid = sn.dbid
  AND e.instance_number = sn.instance_number
WHERE sn.begin_interval_time > SYSDATE - 1
  AND e.wait_class NOT IN ('Idle','Background')
  AND e.total_waits_delta > 0
GROUP BY e.event_name, e.wait_class
ORDER BY time_waited_sec DESC
FETCH FIRST 15 ROWS ONLY;
```

---

## 2. ASH — ACTIVE SESSION HISTORY

### 2.1 Real-time ASH Analysis

```sql
-- ── SESSIONS ĐANG CHỜ GÌ (real-time) ────────────────────
SELECT event, wait_class,
       COUNT(*) sessions_waiting,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(), 1) pct_of_waits
FROM v$active_session_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '5' MINUTE
  AND session_type = 'FOREGROUND'
  AND session_state = 'WAITING'
GROUP BY event, wait_class
ORDER BY sessions_waiting DESC;

-- ── SQL ĐANG CHIẾM TÀI NGUYÊN NHIỀU NHẤT ────────────────
SELECT ash.sql_id,
       SUBSTR(sq.sql_text, 1, 80) sql_preview,
       COUNT(*) ash_samples,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(), 1) pct_db_time,
       SUM(CASE WHEN ash.session_state='ON CPU' THEN 1 ELSE 0 END) on_cpu_samples,
       SUM(CASE WHEN ash.session_state='WAITING' THEN 1 ELSE 0 END) waiting_samples
FROM v$active_session_history ash
LEFT JOIN v$sql sq ON ash.sql_id = sq.sql_id
WHERE ash.sample_time > SYSTIMESTAMP - INTERVAL '60' MINUTE
  AND ash.session_type = 'FOREGROUND'
GROUP BY ash.sql_id, SUBSTR(sq.sql_text, 1, 80)
ORDER BY ash_samples DESC
FETCH FIRST 10 ROWS ONLY;

-- ── SESSION CỤ THỂ ĐANG LÀM GÌ ────────────────────────
SELECT TO_CHAR(sample_time,'HH24:MI:SS') sample_time,
       sql_id,
       session_state,
       event,
       wait_class,
       blocking_session,
       p1, p2, p3
FROM v$active_session_history
WHERE session_id = &sid
  AND sample_time > SYSTIMESTAMP - INTERVAL '30' MINUTE
ORDER BY sample_time DESC
FETCH FIRST 30 ROWS ONLY;

-- ── HOT OBJECTS (objects gây contention) ─────────────────
SELECT o.owner, o.object_name, o.object_type,
       COUNT(*) ash_samples,
       SUM(CASE WHEN ash.event LIKE 'buffer busy%'
               OR ash.event LIKE 'read by other%'
               THEN 1 ELSE 0 END) io_waits
FROM v$active_session_history ash
JOIN dba_objects o ON ash.current_obj# = o.object_id
WHERE ash.sample_time > SYSTIMESTAMP - INTERVAL '1' HOUR
  AND ash.current_obj# > 0
  AND ash.session_type = 'FOREGROUND'
GROUP BY o.owner, o.object_name, o.object_type
ORDER BY ash_samples DESC
FETCH FIRST 15 ROWS ONLY;
```

### 2.2 Historical ASH Analysis (dba_hist_active_sess_history)

```sql
-- ── ASH TREND THEO GIỜ ───────────────────────────────────
SELECT TO_CHAR(TRUNC(sample_time,'HH24'),'YYYY-MM-DD HH24:00') hour_slot,
       COUNT(*) total_samples,
       ROUND(COUNT(*)/360, 2) avg_active_sessions,  -- 360 samples/giờ (10s interval)
       SUM(CASE WHEN session_state='ON CPU' THEN 1 ELSE 0 END) on_cpu,
       SUM(CASE WHEN wait_class='User I/O' THEN 1 ELSE 0 END) user_io,
       SUM(CASE WHEN wait_class='Concurrency' THEN 1 ELSE 0 END) concurrency,
       SUM(CASE WHEN wait_class='Application' THEN 1 ELSE 0 END) application_wait
FROM dba_hist_active_sess_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '24' HOUR
  AND session_type = 'FOREGROUND'
GROUP BY TRUNC(sample_time,'HH24')
ORDER BY 1;

-- ── TOP SQL TRONG KHOẢNG THỜI GIAN CỤ THỂ ───────────────
SELECT ash.sql_id,
       COUNT(*) db_time_samples,
       ROUND(COUNT(*)/6, 1) db_time_sec,  -- 10s sampling = /6 = minutes
       SUM(CASE WHEN session_state='ON CPU' THEN 1 ELSE 0 END) cpu_samples,
       SUBSTR(st.sql_text, 1, 100) sql_preview
FROM dba_hist_active_sess_history ash
LEFT JOIN dba_hist_sqltext st
  ON ash.sql_id = st.sql_id AND ash.dbid = st.dbid
WHERE ash.sample_time BETWEEN
  TO_TIMESTAMP('2026-01-15 09:00:00','YYYY-MM-DD HH24:MI:SS')
  AND TO_TIMESTAMP('2026-01-15 11:00:00','YYYY-MM-DD HH24:MI:SS')
  AND ash.session_type = 'FOREGROUND'
GROUP BY ash.sql_id, SUBSTR(st.sql_text, 1, 100)
ORDER BY db_time_samples DESC
FETCH FIRST 10 ROWS ONLY;

-- ── ASH REPORT (Oracle standard) ─────────────────────────
@$ORACLE_HOME/rdbms/admin/ashrpt.sql
-- Hoặc từ PL/SQL:
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.ASH_REPORT_TEXT(
    l_btime => TO_DATE('2026-01-15 09:00','YYYY-MM-DD HH24:MI'),
    l_etime => TO_DATE('2026-01-15 11:00','YYYY-MM-DD HH24:MI'),
    l_dbid  => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_options  => 0
  )
);
```

### 2.3 ASH Drill-down Investigation

```sql
-- ── TIMELINE INVESTIGATION: DB chậm lúc mấy giờ? ────────
-- Step 1: Tìm thời điểm peak
SELECT TO_CHAR(sample_time,'HH24:MI') five_min_slot,
       COUNT(*) samples,
       ROUND(COUNT(*)/30, 2) avg_active_sessions  -- /30 = mỗi 5 phút có 30 samples
FROM dba_hist_active_sess_history
WHERE sample_time > SYSDATE - 1
  AND session_type = 'FOREGROUND'
GROUP BY TO_CHAR(sample_time,'HH24:MI')
ORDER BY samples DESC
FETCH FIRST 10 ROWS ONLY;
-- → Tìm ra peak là 10:30-10:35

-- Step 2: Trong peak đó, chờ gì?
SELECT event, COUNT(*) waits
FROM dba_hist_active_sess_history
WHERE sample_time BETWEEN
  TO_TIMESTAMP('2026-01-15 10:30','YYYY-MM-DD HH24:MI')
  AND TO_TIMESTAMP('2026-01-15 10:35','YYYY-MM-DD HH24:MI')
  AND session_type = 'FOREGROUND'
  AND session_state = 'WAITING'
GROUP BY event ORDER BY waits DESC;
-- → Phần lớn chờ "db file sequential read"

-- Step 3: SQL nào gây ra waits đó?
SELECT sql_id, COUNT(*) waits
FROM dba_hist_active_sess_history
WHERE sample_time BETWEEN
  TO_TIMESTAMP('2026-01-15 10:30','YYYY-MM-DD HH24:MI')
  AND TO_TIMESTAMP('2026-01-15 10:35','YYYY-MM-DD HH24:MI')
  AND event = 'db file sequential read'
GROUP BY sql_id ORDER BY waits DESC;
-- → sql_id = 'abc123xyz'

-- Step 4: Xem SQL text và execution plan
SELECT sql_text FROM dba_hist_sqltext WHERE sql_id = 'abc123xyz';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_AWR('abc123xyz'));
-- → Plan đang dùng FULL TABLE SCAN thay vì index
```

---

## 3. ADDM — AUTOMATIC DATABASE DIAGNOSTIC MONITOR

### 3.1 ADDM Reports

```sql
-- Xem ADDM findings gần nhất
SELECT TO_CHAR(snap_time,'YYYY-MM-DD HH24:MI') analysis_time,
       finding_id, type, impact_db_pct,
       message
FROM dba_hist_addm_findings f
JOIN dba_hist_addm_tasks t ON f.task_id = t.task_id AND f.dbid = t.dbid
WHERE t.snap_time > SYSDATE - 7
ORDER BY t.snap_time DESC, impact_db_pct DESC
FETCH FIRST 30 ROWS ONLY;

-- ADDM report cho khoảng thời gian cụ thể
DECLARE
  l_db_id    NUMBER;
  l_inst_num NUMBER;
  l_start    NUMBER;
  l_end      NUMBER;
  l_task_id  NUMBER;
  l_report   CLOB;
BEGIN
  SELECT dbid INTO l_db_id FROM v$database;
  SELECT instance_number INTO l_inst_num FROM v$instance;

  -- Tìm snap IDs gần nhất
  SELECT MIN(snap_id) INTO l_start
  FROM dba_hist_snapshot
  WHERE begin_interval_time > SYSTIMESTAMP - INTERVAL '2' HOUR;

  SELECT MAX(snap_id) INTO l_end
  FROM dba_hist_snapshot
  WHERE end_interval_time < SYSTIMESTAMP;

  -- Tạo ADDM task
  DBMS_ADVISOR.CREATE_TASK(
    advisor_name => 'ADDM',
    task_id      => l_task_id,
    task_name    => 'MANUAL_ADDM_' || TO_CHAR(SYSDATE,'YYYYMMDD_HH24MI')
  );

  DBMS_ADVISOR.SET_TASK_PARAMETER(l_task_id, 'START_SNAPSHOT', l_start);
  DBMS_ADVISOR.SET_TASK_PARAMETER(l_task_id, 'END_SNAPSHOT',   l_end);
  DBMS_ADVISOR.SET_TASK_PARAMETER(l_task_id, 'DB_ID',          l_db_id);
  DBMS_ADVISOR.SET_TASK_PARAMETER(l_task_id, 'INSTANCE',       l_inst_num);

  DBMS_ADVISOR.EXECUTE_TASK(l_task_id);

  -- Get report
  l_report := DBMS_ADVISOR.GET_TASK_REPORT(
    task_id     => l_task_id,
    type        => 'TEXT',
    level       => 'TYPICAL'
  );
  DBMS_OUTPUT.PUT_LINE(SUBSTR(l_report, 1, 32767));
END;
/

-- Xem ADDM recommendations
SELECT finding_id, type, benefit,
       SUBSTR(message, 1, 200) finding_message
FROM dba_advisor_findings
WHERE task_name LIKE 'ADDM%'
ORDER BY benefit DESC NULLS LAST;
```

### 3.2 Hiểu ADDM Findings

```
ADDM Findings phân loại:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROBLEM   → Vấn đề thực sự, impact cao
SYMPTOM   → Triệu chứng của PROBLEM khác
INFORMATIONAL → Thông tin bổ sung, không phải vấn đề

Top ADDM Finding Types:
  "SQL statements consuming significant database time"
  → Fix: Tune SQL, thêm index, update stats

  "Buffer cache hit % too low"
  → Fix: Tăng db_cache_size

  "Undersized PGA"
  → Fix: Tăng pga_aggregate_target

  "High I/O activity"
  → Fix: Kiểm tra disk subsystem, partitioning, index

  "Shared pool issues"
  → Fix: Cursor sharing, pin packages, tăng shared_pool

  "High number of hard parses"
  → Fix: Bind variables, cursor_sharing = FORCE/SIMILAR

  "Checkpoint activity"
  → Fix: Tăng redo log size, checkpoint completion target
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 4. PERFORMANCE METRICS DASHBOARD

```sql
-- ── DAILY PERFORMANCE SUMMARY ────────────────────────────
-- Chạy mỗi sáng để review ngày hôm qua

WITH snap_range AS (
  SELECT MIN(snap_id) snap_start, MAX(snap_id) snap_end
  FROM dba_hist_snapshot
  WHERE begin_interval_time > TRUNC(SYSDATE) - 1
    AND end_interval_time   < TRUNC(SYSDATE)
)
SELECT
  -- DB Time
  ROUND(SUM(CASE WHEN stat_name = 'DB time'
            THEN value END) / 1e6 / 3600, 2)      db_time_hrs,
  -- CPU Time
  ROUND(SUM(CASE WHEN stat_name = 'DB CPU'
            THEN value END) / 1e6 / 3600, 2)      cpu_time_hrs,
  -- Logical Reads
  ROUND(SUM(CASE WHEN stat_name = 'session logical reads'
            THEN value END) / 1e6, 2)             logical_reads_M,
  -- Physical Reads
  ROUND(SUM(CASE WHEN stat_name = 'physical reads'
            THEN value END) / 1e6, 2)             physical_reads_M,
  -- Transactions
  SUM(CASE WHEN stat_name = 'user commits' THEN value END) commits,
  -- Parse
  SUM(CASE WHEN stat_name = 'parse count (hard)' THEN value END) hard_parses,
  -- Redo
  ROUND(SUM(CASE WHEN stat_name = 'redo size'
            THEN value END) / 1024 / 1024 / 1024, 2) redo_gb
FROM dba_hist_sysstat s
JOIN snap_range sr ON s.snap_id BETWEEN sr.snap_start AND sr.snap_end
WHERE stat_name IN (
  'DB time','DB CPU','session logical reads','physical reads',
  'user commits','parse count (hard)','redo size'
);
```

---

## 5. PDB-LEVEL AWR/ASH (12c+)

```sql
-- AWR reports cho từng PDB
SELECT snap_id, con_id, db_time_in_us, cpu_time_in_us,
       TO_CHAR(begin_interval_time,'HH24:MI') begin_time
FROM dba_hist_con_sysmetric_summary
WHERE metric_name = 'DB time'
  AND con_id > 2  -- Chỉ PDB (không phải CDB$ROOT)
  AND begin_interval_time > SYSDATE - 1
ORDER BY con_id, snap_id DESC;

-- ASH per PDB (từ CDB$ROOT)
SELECT p.name pdb_name,
       COUNT(*) ash_samples,
       ROUND(COUNT(*)/360, 2) avg_active_sessions
FROM v$active_session_history ash
JOIN v$pdbs p ON ash.con_id = p.con_id
WHERE ash.sample_time > SYSTIMESTAMP - INTERVAL '1' HOUR
  AND ash.session_type = 'FOREGROUND'
GROUP BY p.name
ORDER BY avg_active_sessions DESC;

-- AWR Report cho PDB cụ thể
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid     => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => &begin_snap,
    l_eid      => &end_snap,
    l_con_name => 'ORCLPDB1'  -- PDB name
  )
);
```

---

## 6. AUTOMATION SCRIPTS

```bash
#!/bin/bash
# awr_daily_report.sh — Tạo AWR report tự động hàng ngày
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

DATE=$(date -d yesterday '+%Y-%m-%d')
REPORT_DIR=/u01/reports/awr

mkdir -p $REPORT_DIR

sqlplus -S / as sysdba << SQLEOF
SET PAGESIZE 0 LINESIZE 200 TRIMSPOOL ON FEEDBACK OFF HEADING OFF
SPOOL $REPORT_DIR/awr_${ORACLE_SID}_${DATE}.txt

SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid     => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => (SELECT MIN(snap_id) FROM dba_hist_snapshot
                   WHERE begin_interval_time > TRUNC(SYSDATE-1)),
    l_eid      => (SELECT MAX(snap_id) FROM dba_hist_snapshot
                   WHERE end_interval_time < TRUNC(SYSDATE))
  )
);

SPOOL OFF
EXIT;
SQLEOF

# Gửi email nếu có issues (check key metrics)
if grep -q "significant database time\|undersized PGA\|parse count" \
   $REPORT_DIR/awr_${ORACLE_SID}_${DATE}.txt; then
  mail -s "⚠️ AWR Alert: $ORACLE_SID $DATE" \
    dba@company.com < $REPORT_DIR/awr_${ORACLE_SID}_${DATE}.txt
fi
echo "AWR report: $REPORT_DIR/awr_${ORACLE_SID}_${DATE}.txt"
```

---

**Tài liệu tham khảo:**
- Oracle Database Performance Tuning Guide 19c — AWR, ASH, ADDM
- Oracle Database 2 Day Performance Tuning Guide
- MOS Note 748642.1 (How to Read an AWR Report)
- www.tranvanbinh.vn
