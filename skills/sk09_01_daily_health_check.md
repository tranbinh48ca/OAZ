---
name: oracle-daily-health-check-checklist
description: >
  Daily Health Check Checklist Oracle theo chuẩn QT/DB.01.
  Kích hoạt khi hỏi về: daily health check Oracle, kiểm tra hàng ngày Oracle,
  checklist vận hành database, morning check Oracle DBA,
  health check script Oracle, database status check,
  QT/DB.01 kiểm tra định kỳ, quy trình kiểm tra Oracle,
  daily DBA tasks, database monitoring checklist,
  shift handover Oracle DBA, kiểm tra alert log hàng ngày,
  kiểm tra tablespace hàng ngày, kiểm tra session hàng ngày,
  kiểm tra backup hàng ngày, end of day report Oracle,
  start of day check Oracle, automated health check Oracle.
---

# SK09-01 · Daily Health Check Checklist (theo QT/DB.01)

**Phạm vi:** Oracle Single Instance, RAC, DataGuard  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Tài liệu nền:** QT/DB.01 Phụ lục I — Quy trình kiểm tra định kỳ

---

## 1. CHECKLIST TỔNG QUAN HÀNG NGÀY

```
DAILY HEALTH CHECK — Buổi sáng (08:00) và Cuối ngày (17:00)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ 1. Database Status (instance up, open mode)
□ 2. Listener Status (tất cả listeners running)
□ 3. ASM Diskgroup Status (mounted, free space)
□ 4. Tablespace Usage (< 85% threshold)
□ 5. Session Summary (active/inactive/blocked)
□ 6. Backup Status (RMAN backup completed trong 24h)
□ 7. Archive Log / FRA Usage (< 80%)
□ 8. Alert Log Errors (ORA- errors trong 24h)
□ 9. Invalid Objects Count
□ 10. DataGuard Status (nếu có) — lag, gap
□ 11. RAC Cluster Status (nếu RAC) — all nodes UP
□ 12. Scheduled Jobs Status (failed jobs)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 2. SCRIPT KIỂM TRA TOÀN DIỆN

```sql
-- ===== ORACLE DAILY HEALTH CHECK — QT/DB.01 =====
-- Chạy 2 lần/ngày: 08:00 (đầu ca) và 17:00 (cuối ca)
SET PAGESIZE 100 LINESIZE 200 FEEDBACK OFF

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  1. DATABASE & INSTANCE STATUS                ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT instance_name, host_name, version,
       status, database_status, logins,
       TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       ROUND(SYSDATE - startup_time, 1) uptime_days
FROM v$instance;

SELECT name, db_unique_name, open_mode, log_mode,
       protection_mode, database_role
FROM v$database;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  2. LISTENER STATUS (chạy lệnh OS riêng)      ║
PROMPT ║  lsnrctl status                                ║
PROMPT ╚══════════════════════════════════════════════╝

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  3. ASM DISKGROUP STATUS                       ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT name, state, type,
       ROUND(total_mb/1024, 2) total_gb,
       ROUND(free_mb/1024, 2)  free_gb,
       ROUND((1-free_mb/NULLIF(total_mb,0))*100, 1) pct_used,
       CASE WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 85 THEN '🔴 CRITICAL'
            WHEN (1-free_mb/NULLIF(total_mb,0))*100 >= 70 THEN '🟡 WARNING'
            ELSE '🟢 OK' END status_flag
FROM v$asm_diskgroup
ORDER BY pct_used DESC;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  4. TABLESPACE USAGE                           ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT tablespace_name,
       ROUND(used_space/1024, 2)      used_gb,
       ROUND(tablespace_size/1024, 2) total_gb,
       ROUND(used_percent, 1)         pct_used,
       CASE WHEN used_percent >= 90 THEN '🔴 CRITICAL'
            WHEN used_percent >= 80 THEN '🟡 WARNING'
            ELSE '🟢 OK' END status_flag
FROM dba_tablespace_usage_metrics
ORDER BY pct_used DESC;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  5. SESSION SUMMARY                            ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT status, COUNT(*) cnt,
       ROUND(COUNT(*)*100/(SELECT value FROM v$parameter
             WHERE name='sessions'), 1) pct_of_max
FROM v$session
WHERE type = 'USER'
GROUP BY status
ORDER BY status;

PROMPT --- Blocking Sessions ---
SELECT s.sid, s.serial#, s.username, s.blocking_session,
       s.wait_class, s.event,
       ROUND(s.seconds_in_wait/60, 1) wait_min,
       SUBSTR(q.sql_text,1,60) sql_text
FROM v$session s
LEFT JOIN v$sql q ON s.sql_id = q.sql_id
WHERE s.blocking_session IS NOT NULL
   OR s.sid IN (SELECT blocking_session FROM v$session
                 WHERE blocking_session IS NOT NULL)
ORDER BY s.seconds_in_wait DESC;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  6. RMAN BACKUP STATUS (24h gần nhất)         ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT input_type,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       status,
       ROUND(input_bytes/1024/1024/1024, 2)  input_gb,
       ROUND(elapsed_seconds/60, 1)          elapsed_min
FROM v$rman_backup_job_details
WHERE start_time > SYSDATE - 1
ORDER BY start_time DESC;

PROMPT --- Backup compliance check ---
SELECT CASE WHEN COUNT(*) = 0 THEN '🔴 NO BACKUP IN 24H!'
            ELSE '🟢 Backup OK (' || COUNT(*) || ' job(s))' END status
FROM v$rman_backup_job_details
WHERE status = 'COMPLETED'
  AND start_time > SYSDATE - 1;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  7. FRA / ARCHIVE LOG USAGE                    ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT name,
       ROUND(space_limit/1024/1024/1024, 2) limit_gb,
       ROUND(space_used/1024/1024/1024, 2)  used_gb,
       ROUND(space_used/NULLIF(space_limit,0)*100, 1) pct_used,
       CASE WHEN space_used/NULLIF(space_limit,0)*100 >= 85 THEN '🔴 CRITICAL'
            WHEN space_used/NULLIF(space_limit,0)*100 >= 70 THEN '🟡 WARNING'
            ELSE '🟢 OK' END status_flag
FROM v$recovery_file_dest;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  8. ALERT LOG ERRORS (24h gần nhất)            ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT TO_CHAR(originating_timestamp,'YYYY-MM-DD HH24:MI') ts,
       SUBSTR(message_text,1,150) message
FROM v$diag_alert_ext
WHERE originating_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
  AND message_type IN (3,4)  -- ERROR, INCIDENT_ERROR
ORDER BY originating_timestamp DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  9. INVALID OBJECTS                             ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT owner, object_type, COUNT(*) cnt
FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM','DBSNMP','SYSMAN')
GROUP BY owner, object_type
ORDER BY owner, object_type;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  10. UNUSABLE INDEXES                           ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT owner, index_name, table_name, status
FROM dba_indexes
WHERE status = 'UNUSABLE'
  AND owner NOT IN ('SYS','SYSTEM');

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  11. SCHEDULED JOBS STATUS (24h)                ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT job_name, status,
       TO_CHAR(log_date,'YYYY-MM-DD HH24:MI') log_date,
       error#, additional_info
FROM dba_scheduler_job_log
WHERE log_date > SYSDATE - 1
  AND status != 'SUCCEEDED'
ORDER BY log_date DESC;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  12. TOP WAIT EVENTS (1h gần nhất)              ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT event, wait_class,
       ROUND(time_waited_micro/1e6, 2) time_sec,
       total_waits
FROM v$system_event
WHERE wait_class NOT IN ('Idle','Background')
  AND total_waits > 0
ORDER BY time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;

PROMPT ╔══════════════════════════════════════════════╗
PROMPT ║  13. SYSTEM PERFORMANCE METRICS                 ║
PROMPT ╚══════════════════════════════════════════════╝
SELECT metric_name, ROUND(value,2) value, metric_unit
FROM v$sysmetric
WHERE group_id = 2
  AND metric_name IN (
    'Buffer Cache Hit Ratio',
    'Library Cache Hit Ratio',
    'Host CPU Utilization (%)',
    'Average Active Sessions',
    'Physical Read Total IO Requests Per Sec',
    'User Transaction Per Sec')
ORDER BY metric_name;
```

---

## 3. RAC-SPECIFIC CHECKS (Bổ sung nếu RAC)

```bash
# Cluster resources status
crsctl stat res -t

# All nodes online
olsnodes -n

# SCAN status
srvctl status scan
srvctl status scan_listener
```

```sql
-- All instances up
SELECT inst_id, instance_name, status FROM gv$instance ORDER BY inst_id;

-- GC wait check
SELECT inst_id, event,
       ROUND(time_waited_micro/1e6, 2) time_sec
FROM gv$system_event
WHERE event LIKE 'gc%'
ORDER BY inst_id, time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## 4. DATAGUARD-SPECIFIC CHECKS (Bổ sung nếu có Standby)

```sql
-- Apply lag và transport lag
SELECT name, value, datum_time
FROM v$dataguard_stats
WHERE name IN ('apply lag','transport lag','estimated startup time');

-- Archive gap check
SELECT thread#, low_sequence#, high_sequence# FROM v$archive_gap;
-- Empty result = OK

-- DataGuard role
SELECT database_role, protection_mode, switchover_status FROM v$database;
```

```bash
# Hoặc qua Broker
dgmgrl / "SHOW CONFIGURATION;"
```

---

## 5. SHELL SCRIPT TỰ ĐỘNG HÓA

```bash
#!/bin/bash
# daily_health_check.sh — Tự động hóa kiểm tra hàng ngày
# Chạy qua cron: 0 8,17 * * * /u01/scripts/daily_health_check.sh

export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

DATE=$(date '+%Y%m%d_%H%M')
REPORT_DIR=/u01/reports/health_check
REPORT_FILE=${REPORT_DIR}/hc_${ORACLE_SID}_${DATE}.txt
MAIL_TO="dba-team@company.com"

mkdir -p $REPORT_DIR

echo "===== Daily Health Check - $ORACLE_SID - $(date) =====" > $REPORT_FILE

# 1. Listener
echo "" >> $REPORT_FILE
echo "[LISTENER STATUS]" >> $REPORT_FILE
lsnrctl status 2>&1 | grep -E "Status|Uptime|Service|Instance" >> $REPORT_FILE

# 2. SQL checks
sqlplus -S / as sysdba << SQLEOF >> $REPORT_FILE 2>&1
SET LINESIZE 200 PAGESIZE 50 TRIMSPOOL ON FEEDBACK OFF
@/u01/scripts/health_check.sql
EXIT;
SQLEOF

# 3. Disk space check (OS level)
echo "" >> $REPORT_FILE
echo "[OS DISK SPACE]" >> $REPORT_FILE
df -h | grep -E "u01|oradata|fra" >> $REPORT_FILE

# 4. Determine alert level
ALERT_LEVEL="OK"
if grep -q "CRITICAL\|🔴" $REPORT_FILE; then
  ALERT_LEVEL="CRITICAL"
elif grep -q "WARNING\|🟡" $REPORT_FILE; then
  ALERT_LEVEL="WARNING"
fi

# 5. Send report
SUBJECT="[$ALERT_LEVEL] Daily Health Check - $ORACLE_SID - $(date +%Y-%m-%d\ %H:%M)"
mail -s "$SUBJECT" $MAIL_TO < $REPORT_FILE

echo "Report saved: $REPORT_FILE"
echo "Alert level: $ALERT_LEVEL"

# 6. Cleanup old reports (giữ 30 ngày)
find $REPORT_DIR -name "hc_*.txt" -mtime +30 -delete
```

---

## 6. SHIFT HANDOVER TEMPLATE

```markdown
## DBA Shift Handover Report — [Ngày/Ca]

### 1. Database Status
- [ ] Tất cả databases UP và OPEN
- [ ] RAC: tất cả nodes/instances UP
- [ ] DataGuard: lag trong ngưỡng cho phép

### 2. Issues trong ca (nếu có)
| Thời gian | Database | Vấn đề | Trạng thái | Người xử lý |
|-----------|----------|--------|------------|-------------|
| | | | | |

### 3. Backup Status
- [ ] Full/Incremental backup completed
- [ ] Archive log backup OK
- [ ] FRA usage trong ngưỡng

### 4. Pending Tasks / Cần theo dõi
- [ ] _____________________________________
- [ ] _____________________________________

### 5. Scheduled Activities (ca tiếp theo)
- [ ] _____________________________________

### Người bàn giao: _____________ | Người nhận: _____________
### Thời gian: _____________
```

---

**Tài liệu tham khảo:**
- QT/DB.01 Phụ lục I — Quy trình kiểm tra định kỳ, Trần Văn Bình, VietDBA
- Oracle Database Administrator's Guide 19c
- www.tranvanbinh.vn
