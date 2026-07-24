---
name: oracle-dataguard-switchover-failover-gap
description: >
  Oracle DataGuard Switchover, Failover, Gap Resolution và Monitoring.
  Kích hoạt khi hỏi về: switchover Oracle DataGuard, failover Oracle DataGuard,
  COMMIT TO SWITCHOVER Oracle, switchover_status v$database,
  manual switchover DataGuard, DGMGRL switchover failover,
  archive gap DataGuard, v$archive_gap Oracle, gap resolution DataGuard,
  FAL fetch archive log Oracle, resolve gap DataGuard manually,
  reinstate database DataGuard, REINSTATE DGMGRL,
  v$dataguard_stats Oracle, apply lag transport lag monitoring,
  DataGuard monitoring script, ORA-16401 ORA-16191 DataGuard errors,
  redo transport DataGuard troubleshooting, FAILOVER ALLOW DATA LOSS,
  zero data loss failover, planned unplanned failover Oracle.
---

# SK07-03 · DataGuard Switchover, Failover & Gap Resolution

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. SWITCHOVER (Planned — Zero Data Loss)

### 1.1 Switchover với Broker (Khuyến dùng)

```bash
# ── Pre-check trước khi switchover ────────────────────────
dgmgrl /
DGMGRL> SHOW CONFIGURATION;
DGMGRL> VALIDATE DATABASE 'ORCL_STB';
# Phải show: Ready for Switchover: Yes

# ── Thực hiện Switchover (1 lệnh duy nhất!) ───────────────
DGMGRL> SWITCHOVER TO 'ORCL_STB';

# Broker tự động thực hiện:
# 1. Đảm bảo Primary và Standby đồng bộ hoàn toàn
# 2. Convert Primary → Standby
# 3. Convert Standby → Primary
# 4. Restart cả 2 databases với role mới

# ── Verify sau switchover ─────────────────────────────────
DGMGRL> SHOW CONFIGURATION;
# ORCL_STB     - Primary database
# ORCL_PRIMARY - Physical standby database

# Kiểm tra từ SQL trên DB mới là Primary:
sqlplus / as sysdba
SELECT db_unique_name, database_role, open_mode FROM v$database;
```

### 1.2 Manual Switchover (không dùng Broker)

```sql
-- ── Bước 1: Trên PRIMARY hiện tại - Kiểm tra sẵn sàng ──────
SELECT switchover_status FROM v$database;
-- Phải là: TO STANDBY hoặc SESSIONS ACTIVE
-- Nếu NOT ALLOWED: kiểm tra archive logs đã ship hết chưa

-- ── Bước 2: Convert PRIMARY → STANDBY ─────────────────────
ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY
  WITH SESSION SHUTDOWN;
-- WITH SESSION SHUTDOWN: ngắt tất cả sessions hiện có

-- Shutdown và startup mount
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- Start managed recovery (giờ là Standby)
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- ── Bước 3: Trên STANDBY hiện tại - Convert → PRIMARY ─────
-- Đợi standby đã apply hết redo logs trước
SELECT applied_scn FROM v$standby_log;  -- Hoặc check archive gap

ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY
  WITH SESSION SHUTDOWN;

ALTER DATABASE OPEN;

-- ── Bước 4: Verify ─────────────────────────────────────────
SELECT db_unique_name, database_role, open_mode FROM v$database;
-- DB mới Primary: PRIMARY, READ WRITE
-- DB mới Standby: PHYSICAL STANDBY, MOUNTED (hoặc READ ONLY WITH APPLY)

-- ── Bước 5: Cập nhật connection strings/application ────────
-- Application phải point tới Primary mới (qua SCAN nếu RAC,
-- hoặc cập nhật tnsnames.ora / DNS nếu Single Instance)
```

### 1.3 Switchover Troubleshooting

```sql
-- Switchover bị stuck — kiểm tra nguyên nhân
SELECT switchover_status FROM v$database;
/*
Values:
  SESSIONS ACTIVE       = Có active sessions, cần WITH SESSION SHUTDOWN
  SWITCHOVER PENDING    = Đang trong quá trình chuyển
  TO STANDBY            = Sẵn sàng switchover
  NOT ALLOWED            = Không thể (kiểm tra logs/archive gap)
  RESOLVABLE GAP         = Archive gap có thể resolve trước
  RECOVERY NEEDED        = Standby cần recovery trước
*/

-- Nếu NOT ALLOWED, kiểm tra archive log đã hết chưa
SELECT thread#, MAX(sequence#) FROM v$archived_log
GROUP BY thread#;
SELECT thread#, sequence# FROM v$log WHERE status='CURRENT';

-- Force log switch trước switchover để đảm bảo đồng bộ
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM ARCHIVE LOG CURRENT;

-- Nếu treo do active sessions:
SELECT sid, serial#, username, status FROM v$session WHERE type='USER';
-- Kill sessions không cần thiết trước khi switchover
```

---

## 2. FAILOVER (Unplanned — Primary Down)

### 2.1 Failover với Broker

```bash
# ── Failover graceful (FSFO enabled - tự động) ────────────
# Nếu Fast-Start Failover đã enable, Observer tự động thực hiện
# khi phát hiện Primary down > FastStartFailoverThreshold giây

dgmgrl /
DGMGRL> SHOW FAST_START FAILOVER;
DGMGRL> SHOW OBSERVER;

# ── Manual Failover (FSFO chưa enable) ────────────────────
DGMGRL> FAILOVER TO 'ORCL_STB';
# Broker tự động:
# 1. Finish applying tất cả available redo
# 2. Convert Standby → Primary
# 3. Disable old Primary trong configuration (cần REINSTATE sau)

# ── Failover với data loss (Primary mất hoàn toàn) ────────
DGMGRL> FAILOVER TO 'ORCL_STB' IMMEDIATE;
# Failover ngay không đợi pending redo (có thể mất data chưa transport)
```

### 2.2 Manual Failover (không Broker)

```sql
-- ── Trên Standby: Finish recovery với redo có sẵn ─────────
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
-- FINISH: apply redo còn trong standby redo logs, sau đó dừng

-- Nếu Primary đã chết hoàn toàn (không thể lấy thêm redo):
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH FORCE;

-- ── Activate Standby thành Primary ─────────────────────────
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
ALTER DATABASE OPEN;

-- ── Verify ───────────────────────────────────────────────
SELECT db_unique_name, database_role, open_mode FROM v$database;

-- ── Update application connections ─────────────────────────
-- Repoint application tới DB mới là Primary
```

### 2.3 Reinstate Old Primary (sau Failover)

```bash
# Sau failover, Primary cũ (nếu phục hồi) cần REINSTATE
# để trở thành Standby mới (tự động sync lại qua pg_rewind tương tự)

# ── Với Broker (đơn giản nhất) ─────────────────────────────
dgmgrl /
DGMGRL> REINSTATE DATABASE 'ORCL_PRIMARY';
# Broker tự động dùng Flashback Database để rewind old primary
# về điểm trước failover, rồi convert thành Standby

# ── Manual Reinstate (không Broker) ───────────────────────
# Yêu cầu: Flashback Database đã enable trên old Primary

# Trên old Primary (giờ cần thành Standby):
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- Flashback về trước thời điểm failover
SELECT standby_became_primary_scn FROM v$database;  -- (Chạy trên Standby/new Primary)

-- Trên old Primary:
FLASHBACK DATABASE TO SCN <standby_became_primary_scn>;

-- Convert thành Physical Standby
ALTER DATABASE CONVERT TO PHYSICAL STANDBY;

SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- Restart managed recovery
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;
```

---

## 3. GAP RESOLUTION

### 3.1 Phát hiện Gap

```sql
-- ── Trên Primary: kiểm tra gap ────────────────────────────
SELECT thread#, low_sequence#, high_sequence#
FROM v$archive_gap;
-- Empty = no gap

-- ── Trên Standby: archive logs chưa applied ───────────────
SELECT thread#, sequence#, applied
FROM v$archived_log
WHERE applied = 'NO'
ORDER BY sequence# DESC;

-- Kiểm tra missing sequences
SELECT thread#, sequence#
FROM v$archived_log
WHERE thread# = 1
ORDER BY sequence#;
-- Tìm sequence numbers bị thiếu trong dãy liên tiếp

-- ── FAL (Fetch Archive Log) statistics ────────────────────
SELECT * FROM v$archive_dest_status
WHERE status != 'INACTIVE';
```

### 3.2 Automatic Gap Resolution (FAL)

```sql
-- FAL tự động fetch archive logs bị thiếu từ FAL_SERVER
-- Đảm bảo cấu hình đúng:
SHOW PARAMETER fal_server;
ALTER SYSTEM SET fal_server = 'ORCL_PRIMARY' SCOPE=BOTH;  -- Trên Standby

-- Force resync (nếu FAL không tự động trigger)
ALTER SYSTEM SWITCH LOGFILE;  -- Trên Primary, force archive

-- Standby tự động request gap khi MRP detect missing sequence
-- Monitor RFS/FAL trong alert log:
-- "FAL[client]: Failed to request gap sequence"
-- "FAL[client]: All gaps have been resolved"
```

### 3.3 Manual Gap Resolution (RMAN Incremental)

```bash
# Khi FAL không tự resolve được (network issue, archive bị xóa)
# Dùng RMAN incremental backup từ SCN

# ── Bước 1: Lấy SCN hiện tại của Standby ─────────────────
sqlplus / as sysdba
SELECT current_scn FROM v$database;
-- Hoặc:
SELECT checkpoint_change# FROM v$datafile_header WHERE rownum=1;

# ── Bước 2: Trên Primary - tạo incremental backup từ SCN ──
rman target / << 'EOF'
BACKUP INCREMENTAL FROM SCN 123456789
  DATABASE FORMAT '/tmp/gap_resolve_%U.bkp'
  TAG 'GAP_FIX';
BACKUP CURRENT CONTROLFILE FOR STANDBY
  FORMAT '/tmp/standby_ctl_gap_fix.bkp';
EOF

# ── Bước 3: Copy backup sang Standby ─────────────────────
scp /tmp/gap_resolve_*.bkp oracle@standby:/tmp/
scp /tmp/standby_ctl_gap_fix.bkp oracle@standby:/tmp/

# ── Bước 4: Trên Standby - Apply incremental ─────────────
# Cancel managed recovery trước
sqlplus / as sysdba << 'EOF'
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
EOF

rman target / << 'EOF'
CATALOG START WITH '/tmp/gap_resolve_';
RECOVER DATABASE NOREDO;
EOF

# ── Bước 5: Restart managed recovery ─────────────────────
sqlplus / as sysdba << 'EOF'
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;
EOF

# Verify gap resolved
SELECT thread#, low_sequence#, high_sequence# FROM v$archive_gap;
```

---

## 4. MONITORING DATAGUARD

```sql
-- ── Lag monitoring (chạy định kỳ) ─────────────────────────
SELECT name, value, datum_time, time_computed
FROM v$dataguard_stats
WHERE name IN ('apply lag','transport lag','estimated startup time');

-- ── Apply rate ─────────────────────────────────────────────
SELECT process, status, sequence#, block#, blocks,
       ROUND(blocks*8192/1024/1024, 2) mb_applied
FROM v$managed_standby
WHERE process LIKE 'MRP%' OR process LIKE 'RFS%'
ORDER BY process;

-- ── Redo transport status ─────────────────────────────────
SELECT dest_id, dest_name, status, type,
       transmit_mode, error
FROM v$archive_dest_status
WHERE status != 'INACTIVE';

-- ── Database health summary ────────────────────────────────
SELECT name, db_unique_name, database_role, open_mode,
       protection_mode, protection_level,
       switchover_status, flashback_on
FROM v$database;

-- ── Alert log monitoring script ───────────────────────────
-- Tìm DataGuard related events trong alert log
```

```bash
#!/bin/bash
# dg_monitor.sh — Monitor DataGuard health, alert nếu có vấn đề
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

ALERT_THRESHOLD_SEC=300  # Alert nếu lag > 5 phút
EMAIL="dba-team@company.com"

LAG_SEC=$(sqlplus -S / as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT EXTRACT(SECOND FROM TO_DSINTERVAL(value)) +
       EXTRACT(MINUTE FROM TO_DSINTERVAL(value))*60 +
       EXTRACT(HOUR FROM TO_DSINTERVAL(value))*3600
FROM v$dataguard_stats WHERE name='apply lag';
EXIT;
EOF
)

if [ -z "$LAG_SEC" ]; then
  LAG_SEC=0
fi

if (( $(echo "$LAG_SEC > $ALERT_THRESHOLD_SEC" | bc -l) )); then
  echo "DataGuard Apply Lag: ${LAG_SEC}s exceeds threshold" | \
    mail -s "ALERT: DataGuard Lag High on $ORACLE_SID" $EMAIL
fi

# Check for gaps
GAP_COUNT=$(sqlplus -S / as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT COUNT(*) FROM v$archive_gap;
EXIT;
EOF
)

if [ "$GAP_COUNT" -gt 0 ]; then
  echo "DataGuard has $GAP_COUNT archive gap(s)!" | \
    mail -s "ALERT: DataGuard Gap Detected on $ORACLE_SID" $EMAIL
fi

echo "DG Check: Lag=${LAG_SEC}s Gaps=${GAP_COUNT}"
```

---

## 5. COMMON DATAGUARD ERRORS

```
ORA-16401: archivelog rejected by RFS
  → Standby database name mismatch hoặc DB_UNIQUE_NAME sai
  → Fix: Kiểm tra log_archive_config trên cả Primary/Standby

ORA-16191: Primary log shipping client not logged on standby
  → Password file không sync giữa Primary/Standby
  → Fix: Copy lại password file, đảm bảo SYS password giống nhau

ORA-16009: remote archive log destination must be a STANDBY database
  → log_archive_dest_2 trỏ sai database
  → Fix: Kiểm tra TNS alias và DB_UNIQUE_NAME

ORA-01017: invalid username/password
  → RFS connection auth failure
  → Fix: orapwd lại, đảm bảo REMOTE_LOGIN_PASSWORDFILE=EXCLUSIVE

ORA-16737: the redo transport service for standby database has an error
  → Network hoặc listener issue
  → Fix: Test tnsping, kiểm tra firewall, listener status

FAL[client]: Error fetching gap sequence
  → FAL_SERVER không thể cung cấp archive log
  → Fix: kiểm tra archive logs còn tồn tại trên Primary,
         hoặc dùng RMAN incremental để resolve gap thủ công
```

---

**Tài liệu tham khảo:**
- Oracle Data Guard Broker Guide 19c: Switchover and Failover
- Oracle Data Guard Concepts and Administration: Role Transitions
- MOS Note 1581345.1 (DataGuard Switchover Best Practices)
- MOS Note 836986.1 (DataGuard Gap Resolution)
- www.tranvanbinh.vn
