---
name: oracle-ops-maintenance-oem-kpi-incident-ai
description: >
  Oracle Vận hành toàn diện: Periodic Maintenance, OEM/Zabbix, KPI/SLA,
  Change Management, Capacity Planning, Incident Management, AI-assisted Monitoring.
  Kích hoạt khi hỏi về: periodic maintenance Oracle, bảo trì định kỳ Oracle,
  weekly monthly maintenance checklist, OEM Oracle Enterprise Manager,
  Zabbix Oracle monitoring, Zabbix Oracle template,
  KPI Oracle database, SLA database, service level agreement Oracle,
  change management Oracle, quy trình thay đổi Oracle,
  capacity planning Oracle, capacity forecast Oracle,
  incident management Oracle, P1 P2 P3 incident Oracle,
  emergency response Oracle, escalation Oracle DBA,
  AI assisted monitoring Oracle, Claude API health check,
  automated DBA Oracle, anomaly detection Oracle database,
  predictive maintenance Oracle, machine learning Oracle monitoring.
---

# SK09-03 to SK09-13 · Periodic Maintenance, OEM/Zabbix, KPI/SLA, Change Management, Capacity Planning, Incident Management & AI Monitoring

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Tài liệu nền:** QT/DB.01 — Quy trình vận hành toàn diện

---

# SK09-03 · PERIODIC MAINTENANCE (Weekly/Monthly)

## 1. Weekly Maintenance Checklist

```bash
#!/bin/bash
# weekly_maintenance.sh — QT/DB.01 Phụ lục III

echo "===== WEEKLY MAINTENANCE — $(date) ====="

echo "[1] OS Disk Space"
df -h | grep -v tmpfs

echo "[2] CRS Status (RAC)"
crsctl stat res -t 2>/dev/null

echo "[3] OCR Integrity"
ocrcheck 2>/dev/null

echo "[4] Voting Disk Status"
crsctl query css votedisk 2>/dev/null

echo "[5] RMAN Crosscheck"
rman target / << 'EOF'
CROSSCHECK BACKUP;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED BACKUP;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
EOF

echo "[6] Gather Stale Statistics"
sqlplus -S / as sysdba << 'EOF'
BEGIN
  FOR t IN (SELECT owner, table_name FROM dba_tab_statistics
             WHERE stale_stats='YES' AND owner NOT IN ('SYS','SYSTEM')
             AND num_rows > 10000) LOOP
    BEGIN
      DBMS_STATS.GATHER_TABLE_STATS(t.owner, t.table_name, degree=>4, cascade=>TRUE);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/
EXIT;
EOF
```

```sql
-- [7] Log switch frequency analysis (target: 15-30 phút/switch)
SELECT TO_CHAR(first_time,'YYYY-MM-DD HH24') hour_slot,
       COUNT(*) switches
FROM v$log_history
WHERE first_time > SYSDATE - 7
GROUP BY TO_CHAR(first_time,'YYYY-MM-DD HH24')
ORDER BY 1 DESC;

-- [8] AWR weekly report
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid => (SELECT MIN(snap_id) FROM dba_hist_snapshot WHERE begin_interval_time > SYSDATE-7),
    l_eid => (SELECT MAX(snap_id) FROM dba_hist_snapshot)
  )
);

-- [9] Index rebuild check (fragmentation)
SELECT owner, index_name, blevel, leaf_blocks
FROM dba_indexes
WHERE owner NOT IN ('SYS','SYSTEM') AND blevel > 3
ORDER BY blevel DESC;
```

## 2. Monthly Maintenance Checklist

```sql
-- [1] Full statistics gather (toàn bộ schema)
BEGIN
  DBMS_STATS.GATHER_DATABASE_STATS(options=>'GATHER', degree=>8, cascade=>TRUE);
END;
/

-- [2] Patch level review
SELECT patch_id, TO_CHAR(action_time,'YYYY-MM-DD') applied, status
FROM dba_registry_sqlpatch ORDER BY action_time DESC;

-- [3] Security audit (xem SK04 cho chi tiết)
SELECT username, account_status, ROUND(SYSDATE-last_login) days_inactive
FROM dba_users WHERE account_status='OPEN' AND last_login < SYSDATE-90;

-- [4] Capacity trend report (xem SK09-07)

-- [5] DR/Backup restore test (cần test environment)
-- Restore latest backup lên test server, verify data integrity
```

```bash
# [6] Full database validate
rman target / << 'EOF'
BACKUP VALIDATE DATABASE;
RESTORE DATABASE VALIDATE;
EOF

# [7] Wallet backup verify (nếu dùng TDE)
sqlplus -S / as sysdba << 'EOF'
SELECT key_id, backed_up FROM v$encryption_keys WHERE backed_up='NO';
EOF
```

---

# SK09-04 · ORACLE ENTERPRISE MANAGER (OEM) INTEGRATION

```bash
# ── EM Express (built-in, miễn phí) ──────────────────────
sqlplus / as sysdba << 'EOF'
EXEC DBMS_XDB_CONFIG.SETHTTPSPORT(5500);
EOF
# Access: https://server:5500/em

# ── EM Cloud Control Agent commands ───────────────────────
$AGENT_HOME/bin/emctl status agent
$AGENT_HOME/bin/emctl start  agent
$AGENT_HOME/bin/emctl stop   agent
$AGENT_HOME/bin/emctl upload agent   # Force metric upload
$AGENT_HOME/bin/emctl config agent addinternaltargets

# ── OMS Management ────────────────────────────────────────
$OMS_HOME/bin/emctl status oms -details
$OMS_HOME/bin/emctl start  oms
$OMS_HOME/bin/emctl stop   oms
```

```sql
-- Query từ OEM Repository (nếu có access)
SELECT target_name, target_type, host_name, availability_status,
       last_metric_upload_time
FROM mgmt$target
WHERE target_type IN ('oracle_database','host')
ORDER BY availability_status, target_name;

-- Current alerts
SELECT target_name, metric_column, alert_state, value, timestamp
FROM mgmt$alert_current
WHERE alert_state IN ('CRITICAL','WARNING')
ORDER BY timestamp DESC;
```

```bash
# ── EM CLI automation (emcli) ──────────────────────────────
emcli login -username=sysman -password=Password_2026!
emcli sync
emcli get_targets -targets="%database%"
emcli get_metric_current -target_name=ORCL -target_type=oracle_database \
  -metric=tablespaceUsage
```

---

# SK09-05 · ZABBIX INTEGRATION

## 1. Zabbix Agent với Oracle Template

```bash
# ── Cài đặt Zabbix Agent ───────────────────────────────────
dnf install -y zabbix-agent2

cat > /etc/zabbix/zabbix_agent2.d/oracle.conf << 'EOF'
UserParameter=oracle.tbs.usage[*],/u01/scripts/zbx_check_tbs.sh $1
UserParameter=oracle.session.count,/u01/scripts/zbx_check_session.sh
UserParameter=oracle.archive.gap,/u01/scripts/zbx_check_gap.sh
UserParameter=oracle.backup.status,/u01/scripts/zbx_check_backup.sh
UserParameter=oracle.uptime,/u01/scripts/zbx_check_uptime.sh
EOF

systemctl restart zabbix-agent2
```

```bash
# ── zbx_check_tbs.sh ──────────────────────────────────────
#!/bin/bash
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
TBS_NAME=$1

sqlplus -S / as sysdba << EOF
SET HEADING OFF FEEDBACK OFF
SELECT ROUND(used_percent,1) FROM dba_tablespace_usage_metrics
WHERE tablespace_name = '$TBS_NAME';
EXIT;
EOF
```

```bash
# ── zbx_check_backup.sh ────────────────────────────────────
#!/bin/bash
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

sqlplus -S / as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM v$rman_backup_job_details
WHERE status='COMPLETED' AND start_time > SYSDATE-1;
EXIT;
EOF
```

## 2. Zabbix Items và Triggers

```yaml
# Zabbix items configuration (UI hoặc API)
items:
  - key: oracle.tbs.usage[SYSTEM]
    name: "Tablespace SYSTEM Usage %"
    type: Zabbix agent
    value_type: Numeric (float)
    update_interval: 5m

  - key: oracle.session.count
    name: "Active Session Count"
    update_interval: 1m

  - key: oracle.archive.gap
    name: "DataGuard Archive Gap"
    update_interval: 5m

  - key: oracle.backup.status
    name: "RMAN Backup Status 24h"
    update_interval: 1h

triggers:
  - name: "Tablespace usage critical"
    expression: "last(/Oracle DB/oracle.tbs.usage[SYSTEM])>=90"
    priority: High

  - name: "No backup in 24h"
    expression: "last(/Oracle DB/oracle.backup.status)=0"
    priority: Disaster

  - name: "DataGuard gap detected"
    expression: "last(/Oracle DB/oracle.archive.gap)>0"
    priority: High
```

```bash
# Zabbix sender — push metrics directly (alternative to pull)
zabbix_sender -z zabbix-server -s "OracleDB01" \
  -k oracle.tbs.usage[SYSTEM] -o 75.5
```

---

# SK09-06 · KPI / SLA MANAGEMENT

## 1. KPI Definitions

```
Database KPI Standards (theo QT/DB.01):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| KPI                        | Target          | Critical    |
|-----------------------------|-----------------|-------------|
| Database Uptime             | >= 99.9%        | < 99.5%     |
| Backup Success Rate         | 100%            | < 100%      |
| RPO (DataGuard)              | < 1 phút        | > 5 phút    |
| RTO (Failover time)          | < 5 phút        | > 15 phút   |
| Tablespace Usage             | < 85%           | >= 90%      |
| Buffer Cache Hit Ratio       | >= 95%          | < 90%       |
| Max Concurrent Sessions      | < 80% of max    | >= 90%      |
| Invalid Objects               | 0               | > 10        |
| Avg Query Response Time      | < 100ms         | > 500ms     |
| Archive Log Gap (DataGuard)  | 0               | > 0         |
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. SLA Monitoring Queries

```sql
-- ── Uptime Calculation (tháng hiện tại) ───────────────────
SELECT ROUND((1 - (
  SELECT NVL(SUM(downtime_minutes),0) FROM downtime_log
  WHERE EXTRACT(MONTH FROM downtime_start) = EXTRACT(MONTH FROM SYSDATE)
) / (EXTRACT(DAY FROM SYSDATE) * 24 * 60)) * 100, 3) uptime_pct
FROM dual;

-- ── Backup Success Rate ───────────────────────────────────
SELECT
  ROUND(SUM(CASE WHEN status='COMPLETED' THEN 1 ELSE 0 END)
        / COUNT(*) * 100, 2) success_rate_pct,
  COUNT(*) total_jobs
FROM v$rman_backup_job_details
WHERE start_time > TRUNC(SYSDATE,'MM');

-- ── Response Time SLA ──────────────────────────────────────
SELECT metric_name, ROUND(AVG(value),2) avg_value,
       ROUND(MAX(value),2) max_value
FROM dba_hist_sysmetric_summary
WHERE metric_name = 'SQL Service Response Time'
  AND begin_interval_time > TRUNC(SYSDATE,'MM')
GROUP BY metric_name;
```

## 3. SLA Report Template

```sql
-- Monthly SLA Report Generator
CREATE OR REPLACE VIEW v_monthly_sla_report AS
SELECT
  TO_CHAR(SYSDATE,'YYYY-MM') report_month,
  'Backup Success Rate' kpi_name,
  ROUND(SUM(CASE WHEN status='COMPLETED' THEN 1 ELSE 0 END)/COUNT(*)*100,2) actual_value,
  100 target_value,
  CASE WHEN ROUND(SUM(CASE WHEN status='COMPLETED' THEN 1 ELSE 0 END)/COUNT(*)*100,2) >= 100
       THEN 'MET' ELSE 'MISSED' END sla_status
FROM v$rman_backup_job_details
WHERE start_time > TRUNC(SYSDATE,'MM')
UNION ALL
SELECT TO_CHAR(SYSDATE,'YYYY-MM'), 'Tablespace Compliance',
       ROUND(AVG(CASE WHEN used_percent < 85 THEN 100 ELSE 0 END),2),
       100,
       CASE WHEN AVG(CASE WHEN used_percent < 85 THEN 100 ELSE 0 END) >= 95
            THEN 'MET' ELSE 'MISSED' END
FROM dba_tablespace_usage_metrics;

SELECT * FROM v_monthly_sla_report;
```

---

# SK09-07 · CAPACITY PLANNING

```sql
-- ── Storage Growth Forecast (90 ngày lịch sử) ─────────────
WITH monthly_growth AS (
  SELECT TO_CHAR(begin_interval_time,'YYYY-MM') month,
         ROUND(SUM(tablespace_usedsize * block_size)/1024/1024/1024,2) total_gb
  FROM dba_hist_tbspc_space_usage tsu
  JOIN dba_hist_tablespace_stat ts ON tsu.tablespace_id=ts.ts# AND tsu.snap_id=ts.snap_id
  JOIN dba_hist_snapshot s ON tsu.snap_id=s.snap_id
  WHERE s.begin_interval_time > ADD_MONTHS(SYSDATE,-6)
  GROUP BY TO_CHAR(begin_interval_time,'YYYY-MM')
)
SELECT month, total_gb,
       total_gb - LAG(total_gb) OVER (ORDER BY month) growth_gb
FROM monthly_growth
ORDER BY month;

-- ── CPU/Memory capacity trend ──────────────────────────────
SELECT TO_CHAR(s.begin_interval_time,'YYYY-MM') month,
       ROUND(AVG(m.value),1) avg_cpu_pct,
       ROUND(MAX(m.value),1) peak_cpu_pct
FROM dba_hist_sysmetric_summary m
JOIN dba_hist_snapshot s ON m.snap_id=s.snap_id
WHERE m.metric_name='Host CPU Utilization (%)'
  AND s.begin_interval_time > ADD_MONTHS(SYSDATE,-6)
GROUP BY TO_CHAR(s.begin_interval_time,'YYYY-MM')
ORDER BY month;

-- ── Session growth trend (capacity for max_sessions) ──────
SELECT TO_CHAR(s.begin_interval_time,'YYYY-MM-DD') day,
       ROUND(MAX(m.value)) peak_sessions
FROM dba_hist_sysmetric_summary m
JOIN dba_hist_snapshot s ON m.snap_id=s.snap_id
WHERE m.metric_name = 'Current Logons Count'
  AND s.begin_interval_time > SYSDATE - 90
GROUP BY TO_CHAR(s.begin_interval_time,'YYYY-MM-DD')
ORDER BY day;
```

## Capacity Planning Report Template

```markdown
## Capacity Planning Report — [Quarter/Year]

### Storage Capacity
| Tablespace | Current GB | 6-Month Growth | Forecast 12mo | Action Required |
|------------|-----------|-----------------|----------------|-------------------|
| | | | | |

### Compute Capacity
| Metric | Current Avg | Current Peak | 6-Month Trend | Recommendation |
|--------|-------------|---------------|------------------|------------------|
| CPU | | | | |
| Memory | | | | |
| Sessions | | | | |

### Recommendations
1. _____________________________________
2. _____________________________________

### Budget Impact
- Storage expansion: _____ GB needed by [date]
- Compute upgrade: _____ recommended by [date]
```

---

# SK09-08 · CHANGE MANAGEMENT

## Change Request Workflow (theo QT/DB.01)

```
Quy trình thay đổi (Change Management):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Request    → App Team submit Change Request (CR)
2. Review     → DBA Lead đánh giá impact, risk
3. Approval   → Lãnh đạo phê duyệt (theo mức độ ảnh hưởng)
4. Schedule   → Lên lịch maintenance window
5. Backup     → Backup trước khi thực hiện thay đổi
6. Execute    → Thực hiện thay đổi theo runbook
7. Validate   → Kiểm tra sau thay đổi
8. Rollback   → Nếu fail, rollback theo plan
9. Close      → Đóng CR, cập nhật documentation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Approval Matrix:
| Loại thay đổi              | Cấp phê duyệt        |
|------------------------------|------------------------|
| Cấp quyền user thường        | DBA Tổ trưởng         |
| Cấp quyền bảng nhạy cảm      | LĐTCT                 |
| DDL trên production           | LĐTT (>5 phút: LĐTCT) |
| Patch/Upgrade Database         | LĐTCT                 |
| Cài đặt DB mới                 | LĐTT (cần nguồn lực)  |
```

## Change Request Template

```markdown
## Change Request Form

**CR ID:** ______ | **Date:** ______ | **Requestor:** ______

### Change Details
- Database: ______
- Change Type: [ ] DDL [ ] Data [ ] Config [ ] Patch [ ] Other
- Description: _______________________________________________

### Risk Assessment
- Impact Level: [ ] Low [ ] Medium [ ] High [ ] Critical
- Downtime Required: ______ minutes
- Rollback Plan: _______________________________________________

### Approval
- DBA Lead: ______ Date: ______
- Manager (if High/Critical): ______ Date: ______

### Execution
- Scheduled Window: ______
- Executed By: ______
- Actual Start/End: ______
- Status: [ ] Success [ ] Rolled Back [ ] Partial

### Post-Change Validation
- [ ] Application connectivity verified
- [ ] Performance baseline checked
- [ ] No new errors in alert log
```

---

# SK09-09 · INCIDENT MANAGEMENT

## 1. Incident Classification

```
| Priority | Mô tả | Response Time | Resolution Time |
|----------|--------|-----------------|--------------------|
| P1 | DB down, mất data, ảnh hưởng 100% user | 15 phút | 4 giờ |
| P2 | Performance nghiêm trọng, core function fail | 30 phút | 8 giờ |
| P3 | Một function lỗi, có workaround | 2 giờ | 24 giờ |
| P4 | Yêu cầu cải tiến, không khẩn cấp | Next sprint | - |
```

## 2. Emergency Response Procedures

```bash
#!/bin/bash
# emergency_response.sh — P1 Incident Response

ORACLE_SID=$1
echo "===== EMERGENCY RESPONSE: $ORACLE_SID ====="
echo "Time: $(date)"

# Step 1: Is DB alive?
if ! sqlplus -S / as sysdba <<< "SELECT 1 FROM dual;" &>/dev/null; then
  echo "❌ DATABASE DOWN — Attempting recovery startup"
  sqlplus / as sysdba << 'EOF'
STARTUP;
EOF
  # Nếu startup fail, escalate ngay
fi

# Step 2: Quick diagnostics
sqlplus -S / as sysdba << 'EOF'
SET LINESIZE 200
SELECT 'Sessions' metric, COUNT(*) value FROM v$session WHERE type='USER'
UNION ALL
SELECT 'Blocking', COUNT(*) FROM v$session WHERE blocking_session IS NOT NULL
UNION ALL
SELECT 'TBS Critical', COUNT(*) FROM dba_tablespace_usage_metrics WHERE used_percent>=90;
EOF

echo "===== Notify on-call DBA Lead ====="
# Integration với PagerDuty/OpsGenie API
curl -X POST https://api.pagerduty.com/incidents \
  -H "Authorization: Token token=YOUR_TOKEN" \
  -d '{"incident":{"type":"incident","title":"P1: '"$ORACLE_SID"' Down"}}'
```

## 3. Incident Report Template

```markdown
## Incident Report — [Incident ID]

**Priority:** P1/P2/P3 | **Status:** Open/Resolved | **Date:** ______

### Timeline
| Time | Event | Action Taken |
|------|--------|---------------|
| | Detected | |
| | Response started | |
| | Root cause identified | |
| | Fix applied | |
| | Resolved | |

### Root Cause
_______________________________________________

### Impact
- Affected systems: ______
- Duration: ______ minutes
- Users affected: ______

### Resolution
_______________________________________________

### Prevention (Action Items)
1. _______________________________________________
2. _______________________________________________
```

---

# SK09-10 to SK09-13 · AI-ASSISTED MONITORING

## 1. Claude API Integration cho Health Check Analysis

```python
#!/usr/bin/env python3
# ai_health_analyzer.py — Phân tích health check report bằng Claude API

import anthropic
import subprocess
import json
from datetime import datetime

client = anthropic.Anthropic(api_key="YOUR_API_KEY")

def collect_health_data():
    """Thu thập dữ liệu health check từ Oracle"""
    sql_script = """
    SET HEADING OFF FEEDBACK OFF
    SELECT JSON_OBJECT(
      'tablespaces' VALUE (
        SELECT JSON_ARRAYAGG(JSON_OBJECT(
          'name' VALUE tablespace_name,
          'pct_used' VALUE ROUND(used_percent,1)
        )) FROM dba_tablespace_usage_metrics
      ),
      'sessions' VALUE (
        SELECT COUNT(*) FROM v$session WHERE type='USER'
      ),
      'invalid_objects' VALUE (
        SELECT COUNT(*) FROM dba_objects WHERE status='INVALID'
      ),
      'blocking_sessions' VALUE (
        SELECT COUNT(*) FROM v$session WHERE blocking_session IS NOT NULL
      )
    ) FROM dual;
    """
    result = subprocess.run(
        ['sqlplus', '-S', '/', 'as', 'sysdba'],
        input=sql_script, capture_output=True, text=True
    )
    return result.stdout

def analyze_with_claude(health_data):
    """Gửi data cho Claude phân tích và đề xuất hành động"""
    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1000,
        messages=[{
            "role": "user",
            "content": f"""Bạn là Oracle DBA chuyên gia. Phân tích health check data sau
            và đưa ra: 1) Mức độ nghiêm trọng (OK/WARNING/CRITICAL)
            2) Vấn đề cần chú ý 3) Hành động đề xuất.
            Trả lời ngắn gọn bằng tiếng Việt.

            Data: {health_data}"""
        }]
    )
    return message.content[0].text

def main():
    print(f"=== AI Health Check Analysis - {datetime.now()} ===")
    health_data = collect_health_data()
    analysis = analyze_with_claude(health_data)
    print(analysis)

    # Nếu CRITICAL, gửi alert
    if "CRITICAL" in analysis:
        send_alert(analysis)

def send_alert(message):
    # Integration với email/Slack
    subprocess.run(['mail', '-s', 'AI-Detected Critical Issue',
                    'dba-team@company.com'], input=message, text=True)

if __name__ == "__main__":
    main()
```

## 2. Anomaly Detection với Statistical Baseline

```sql
-- ── Tạo baseline cho anomaly detection ────────────────────
CREATE TABLE metric_baseline (
  metric_name VARCHAR2(100),
  hour_of_day NUMBER,
  day_of_week VARCHAR2(10),
  avg_value   NUMBER,
  stddev_value NUMBER,
  sample_count NUMBER
);

-- Build baseline từ AWR history (30 ngày)
INSERT INTO metric_baseline
SELECT metric_name,
       EXTRACT(HOUR FROM begin_interval_time) hour_of_day,
       TO_CHAR(begin_interval_time,'DY') day_of_week,
       AVG(value), STDDEV(value), COUNT(*)
FROM dba_hist_sysmetric_summary s
JOIN dba_hist_snapshot sn ON s.snap_id=sn.snap_id
WHERE sn.begin_interval_time > SYSDATE - 30
  AND metric_name IN ('Average Active Sessions','Host CPU Utilization (%)',
                       'SQL Service Response Time')
GROUP BY metric_name, EXTRACT(HOUR FROM begin_interval_time),
         TO_CHAR(begin_interval_time,'DY');

-- ── Anomaly detection query (real-time vs baseline) ──────
SELECT m.metric_name, m.value current_value,
       b.avg_value baseline_avg,
       b.stddev_value baseline_stddev,
       ROUND((m.value - b.avg_value) / NULLIF(b.stddev_value,0), 2) z_score,
       CASE WHEN ABS((m.value - b.avg_value) / NULLIF(b.stddev_value,0)) > 3
            THEN '🔴 ANOMALY DETECTED'
            WHEN ABS((m.value - b.avg_value) / NULLIF(b.stddev_value,0)) > 2
            THEN '🟡 UNUSUAL'
            ELSE '🟢 NORMAL'
       END status
FROM v$sysmetric m
JOIN metric_baseline b
  ON m.metric_name = b.metric_name
  AND b.hour_of_day = EXTRACT(HOUR FROM SYSDATE)
  AND b.day_of_week = TO_CHAR(SYSDATE,'DY')
WHERE m.group_id = 2
  AND m.metric_name IN ('Average Active Sessions','Host CPU Utilization (%)');
```

## 3. AI-Powered Automated Daily Report

```python
#!/usr/bin/env python3
# ai_daily_report.py — Tổng hợp + phân tích + gửi báo cáo hàng ngày

import anthropic
import subprocess
from datetime import datetime

client = anthropic.Anthropic(api_key="YOUR_API_KEY")

def get_full_health_report():
    """Thu thập đầy đủ AWR, alert log, backup status"""
    queries = {
        'awr_summary': "SELECT output FROM TABLE(DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(...))",
        'alert_errors': "SELECT message_text FROM v$diag_alert_ext WHERE originating_timestamp > SYSDATE-1 AND message_type IN (3,4)",
        'backup_status': "SELECT status, start_time FROM v$rman_backup_job_details WHERE start_time > SYSDATE-1"
    }
    results = {}
    for key, sql in queries.items():
        # Execute via sqlplus, capture output
        results[key] = run_sql(sql)
    return results

def generate_executive_summary(data):
    """Claude tạo báo cáo điều hành dễ hiểu cho management"""
    prompt = f"""Bạn là DBA Lead. Dựa trên dữ liệu kỹ thuật sau, viết báo cáo
    điều hành (executive summary) ngắn gọn cho ban lãnh đạo, bằng tiếng Việt,
    tập trung vào: tình trạng tổng thể, rủi ro, hành động cần thiết.

    Dữ liệu: {data}"""

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=800,
        messages=[{"role": "user", "content": prompt}]
    )
    return message.content[0].text

def main():
    data = get_full_health_report()
    summary = generate_executive_summary(data)

    # Gửi email với cả technical detail và executive summary
    send_report(summary, data)

if __name__ == "__main__":
    main()
```

## 4. Best Practices cho AI-Assisted Monitoring

```
Nguyên tắc khi dùng AI trong DBA Operations:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. AI hỗ trợ PHÂN TÍCH, không tự động THỰC THI thay đổi
   → Human-in-the-Loop bắt buộc cho mọi DDL/production changes

2. AI tốt cho:
   - Tóm tắt logs dài thành insights ngắn gọn
   - Phát hiện patterns/anomalies từ historical data
   - Đề xuất root cause dựa trên symptoms
   - Generate draft scripts (cần DBA review trước khi chạy)
   - Translate technical findings → business language

3. AI KHÔNG nên:
   - Tự động chạy DDL/DML mà không có approval
   - Quyết định failover/switchover một mình
   - Thay thế hoàn toàn DBA judgment cho critical decisions

4. Audit trail:
   - Log mọi AI-suggested actions
   - DBA phải review và approve trước khi execute
   - Track AI accuracy theo thời gian để cải thiện prompts

5. Security:
   - KHÔNG gửi sensitive data (passwords, PII) vào AI API
   - Sanitize output trước khi log
   - Dùng API key riêng cho mỗi environment (prod/test tách biệt)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Tài liệu tham khảo — SK09-03 đến SK09-13:**
- QT/DB.01 Phụ lục III, XII — Trần Văn Bình, VietDBA
- Oracle Enterprise Manager Documentation 13c
- Zabbix Documentation: zabbix.com/documentation
- Anthropic Claude API Documentation: docs.claude.com
- ITIL Incident Management Framework
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
