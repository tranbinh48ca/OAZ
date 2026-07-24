---
name: oracle-block-corruption-performance-degradation
description: >
  Block Corruption nâng cao và Performance Degradation troubleshooting Oracle.
  Kích hoạt khi hỏi về: block corruption Oracle, data block corrupted,
  RMAN VALIDATE corruption, DBVERIFY Oracle, ORA-01578 advanced,
  physical corruption logical corruption Oracle, lost write detection,
  database slow Oracle, performance degradation Oracle,
  sudden slowdown Oracle, DB chậm đột ngột, execution plan changed,
  cardinality feedback Oracle, statistics regression Oracle,
  SQL Plan Baseline restore, plan stability Oracle, ADDM analysis slow,
  root cause analysis performance Oracle, baseline comparison Oracle,
  why is my database slow, troubleshoot slow query Oracle.
---

# SK10-02 · Block Corruption Advanced & Performance Degradation

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## PHẦN A: BLOCK CORRUPTION NÂNG CAO

## 1. Phát hiện Corruption Toàn Diện

```bash
# ── RMAN VALIDATE (kiểm tra toàn DB) ─────────────────────
rman target / << 'EOF'
VALIDATE DATABASE;
EOF

# Validate riêng datafile/tablespace
rman target / << 'EOF'
VALIDATE TABLESPACE USERS;
VALIDATE DATAFILE 5;
VALIDATE DATAFILE 5 BLOCK 1000 TO 2000;
EOF

# ── DBVERIFY (utility độc lập, không cần DB mở) ──────────
dbv FILE=/u01/oradata/ORCL/users01.dbf BLOCKSIZE=8192 \
    LOGFILE=/tmp/dbv_output.log

# Kiểm tra phạm vi block cụ thể
dbv FILE=/u01/oradata/ORCL/users01.dbf START=1000 END=2000

# ── ANALYZE TABLE/INDEX VALIDATE STRUCTURE ───────────────
```

```sql
ANALYZE TABLE scott.orders VALIDATE STRUCTURE CASCADE;
ANALYZE INDEX scott.idx_orders_date VALIDATE STRUCTURE;

-- Xem kết quả (nếu có lỗi sẽ raise exception ORA-01498/01499)
SELECT * FROM index_stats;
```

## 2. Phân loại Corruption

```
Loại Corruption:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PHYSICAL CORRUPTION:
  - Block header checksum sai
  - Block không "look like" Oracle block
  - Thường do: disk lỗi, firmware bug, bad sectors
  - Phát hiện: DBVERIFY, RMAN VALIDATE luôn detect được

LOGICAL CORRUPTION:
  - Block header OK nhưng nội dung không nhất quán
  - VD: index entry không khớp table row
  - Thường do: Oracle bug, application bypass constraints
  - Phát hiện: RMAN VALIDATE ... CHECK LOGICAL
              hoặc ANALYZE VALIDATE STRUCTURE

LOST WRITE:
  - I/O subsystem báo "write thành công" nhưng thực tế chưa ghi
  - Thường do: storage cache issue, SAN/NAS misbehavior
  - Phát hiện: DataGuard Lost Write Protection (db_lost_write_protect)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

```bash
# Validate với CHECK LOGICAL (phát hiện cả logical corruption)
rman target / << 'EOF'
BACKUP VALIDATE CHECK LOGICAL DATABASE;
EOF
```

## 3. Lost Write Protection (DataGuard)

```sql
-- Enable lost write detection (Primary + Standby)
ALTER SYSTEM SET db_lost_write_protect = TYPICAL SCOPE=BOTH;
-- TYPICAL: kiểm tra read-only và read-write tablespaces
-- FULL: kiểm tra tất cả tablespaces (kể cả read-only)

-- Khi DataGuard phát hiện lost write:
-- Alert log sẽ có: "Automatic block media recovery"
-- Hoặc: "Lost write detected on Primary"
```

## 4. Recovery Strategy theo mức độ nghiêm trọng

```bash
# Mức 1: Single block corruption — Block Media Recovery
rman target / << 'EOF'
BLOCKRECOVER DATAFILE 5 BLOCK 1234;
EOF

# Mức 2: Multiple blocks, cùng datafile
rman target / << 'EOF'
BLOCKRECOVER CORRUPTION LIST;
EOF

# Mức 3: Toàn bộ datafile corrupt — Restore + Recover
rman target / << 'EOF'
SQL "ALTER DATABASE DATAFILE 5 OFFLINE";
RESTORE DATAFILE 5;
RECOVER DATAFILE 5;
SQL "ALTER DATABASE DATAFILE 5 ONLINE";
EOF

# Mức 4: Nhiều datafiles / toàn DB — Full restore
rman target / << 'EOF'
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
EOF
```

## 5. Khi không có Backup — Last Resort

```sql
-- DBMS_REPAIR (chấp nhận mất data trong block lỗi)
DECLARE
  v_num_corrupt INT;
BEGIN
  DBMS_REPAIR.CHECK_OBJECT(
    schema_name => 'SCOTT',
    object_name => 'ORDERS',
    repair_table_name => 'REPAIR_TABLE',
    corrupt_count => v_num_corrupt
  );
  DBMS_OUTPUT.PUT_LINE('Corrupt blocks: ' || v_num_corrupt);
END;
/

SELECT * FROM repair_table;

BEGIN
  DBMS_REPAIR.FIX_CORRUPT_BLOCKS(
    schema_name => 'SCOTT',
    object_name => 'ORDERS',
    object_type => DBMS_REPAIR.TABLE_OBJECT,
    repair_table_name => 'REPAIR_TABLE');
END;
/

-- Rebuild indexes sau khi fix table (data đã thay đổi)
ALTER INDEX scott.idx_orders_date REBUILD ONLINE;
```

---

## PHẦN B: PERFORMANCE DEGRADATION TROUBLESHOOTING

## 6. Quy trình Chẩn đoán DB Chậm Đột Ngột (5-10 phút)

```sql
-- ── BƯỚC 1: Top waits NGAY LÚC NÀY ────────────────────────
SELECT event, wait_class, COUNT(*) sessions_waiting
FROM v$session
WHERE type='USER' AND status='ACTIVE' AND wait_class!='Idle'
GROUP BY event, wait_class
ORDER BY sessions_waiting DESC;

-- ── BƯỚC 2: Top SQL đang chạy ──────────────────────────────
SELECT s.sid, s.serial#, s.username,
       s.seconds_in_wait, s.event,
       SUBSTR(q.sql_text,1,80) sql_text, q.sql_id
FROM v$session s, v$sql q
WHERE s.sql_id = q.sql_id AND s.type='USER' AND s.status='ACTIVE'
ORDER BY s.seconds_in_wait DESC
FETCH FIRST 10 ROWS ONLY;

-- ── BƯỚC 3: Execution plan có thay đổi không? ─────────────
SELECT sql_id, plan_hash_value,
       ROUND(elapsed_time/1e6,2) elapsed_sec,
       executions,
       TO_CHAR(last_active_time,'HH24:MI:SS') last_run
FROM v$sqlarea
WHERE sql_id = '&sql_id'
ORDER BY last_active_time DESC;

-- So sánh với plan lịch sử từ AWR
SELECT DISTINCT sql_id, plan_hash_value,
       TO_CHAR(MIN(timestamp),'YYYY-MM-DD HH24:MI') first_seen
FROM dba_hist_sql_plan
WHERE sql_id = '&sql_id'
GROUP BY sql_id, plan_hash_value
ORDER BY first_seen;

-- ── BƯỚC 4: System metrics tổng quan ──────────────────────
SELECT metric_name, value, metric_unit
FROM v$sysmetric
WHERE group_id = 2
  AND metric_name IN (
    'Average Active Sessions','Host CPU Utilization (%)',
    'Buffer Cache Hit Ratio','Physical Read Total IO Requests Per Sec')
ORDER BY metric_name;
```

## 7. Root Cause Analysis — Các Nguyên nhân Thường Gặp

### 7.1 Statistics Stale/Sai → Plan Tệ Hơn

```sql
-- Kiểm tra stats có vừa thay đổi gần đây
SELECT owner, table_name, TO_CHAR(last_analyzed,'YYYY-MM-DD HH24:MI') analyzed
FROM dba_tab_statistics
WHERE table_name = 'ORDERS'
ORDER BY last_analyzed DESC;

-- Restore statistics về trước thời điểm gây vấn đề
EXEC DBMS_STATS.RESTORE_TABLE_STATS('SCOTT','ORDERS', SYSDATE - 1/24);

-- Lock statistics (ngăn auto-gather thay đổi lại)
EXEC DBMS_STATS.LOCK_TABLE_STATS('SCOTT','ORDERS');
```

### 7.2 Cardinality Feedback gây Plan Instability

```sql
-- Kiểm tra SQL có đang dùng cardinality feedback không
SELECT sql_id, is_reoptimizable, is_resolved_adaptive_plan
FROM v$sql WHERE sql_id = '&sql_id';

-- Tắt adaptive features nếu gây instability
ALTER SESSION SET optimizer_adaptive_plans = FALSE;
-- Hoặc system-wide:
ALTER SYSTEM SET optimizer_adaptive_plans = FALSE SCOPE=BOTH;
```

### 7.3 SQL Plan Baseline để Fix Regression Ngay Lập Tức

```sql
-- Tìm plan TỐT trong lịch sử (trước khi vấn đề xảy ra)
SELECT sql_id, plan_hash_value,
       ROUND(elapsed_time/1e6,2) elapsed_sec
FROM dba_hist_sqlstat s
JOIN dba_hist_snapshot sn ON s.snap_id=sn.snap_id
WHERE sql_id = '&sql_id'
  AND sn.begin_interval_time < SYSDATE - 1  -- Trước khi vấn đề bắt đầu
ORDER BY elapsed_time/executions ASC
FETCH FIRST 5 ROWS ONLY;

-- Load plan tốt vào SQL Plan Baseline, force dùng
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_AWR(
    sql_id => '&sql_id',
    plan_hash_value => &good_plan_hash,
    fixed => 'YES'
  );
END;
/
```

### 7.4 Locks/Blocking Sessions

```sql
SELECT blocking_session, COUNT(*) blocked_count
FROM v$session WHERE blocking_session IS NOT NULL
GROUP BY blocking_session ORDER BY blocked_count DESC;

-- Kill blocking session sau khi confirm
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;
```

### 7.5 Resource Contention (CPU/I/O/Memory)

```sql
-- CPU saturation check
SELECT metric_name, value FROM v$sysmetric
WHERE metric_name = 'Host CPU Utilization (%)' AND group_id=2;

-- I/O bottleneck
SELECT df.name, fs.phyrds, fs.phywrts,
       ROUND(fs.readtim/NULLIF(fs.phyrds,0),2) avg_read_ms
FROM v$datafile df JOIN v$filestat fs ON df.file#=fs.file#
ORDER BY fs.phyrds DESC FETCH FIRST 10 ROWS ONLY;

-- PGA over-allocation (sort spill to disk)
SELECT name, value FROM v$pgastat
WHERE name IN ('over allocation count','extra bytes read/written');
```

### 7.6 Object-level Issues

```sql
-- Index trở nên unusable/invisible bất ngờ
SELECT index_name, status, visibility
FROM dba_indexes WHERE table_name='ORDERS';

-- Table bị fragment nặng (high HWM)
SELECT table_name, num_rows, blocks, empty_blocks
FROM dba_tables WHERE table_name='ORDERS';

-- Check recent DDL changes
SELECT object_name, object_type, last_ddl_time
FROM dba_objects
WHERE last_ddl_time > SYSDATE - 1
  AND owner = 'SCOTT'
ORDER BY last_ddl_time DESC;
```

## 8. Performance Degradation Decision Tree

```
DB chậm đột ngột?
├── Tất cả queries chậm đều (system-wide)?
│   ├── CPU 100%? → Check top CPU sessions, kill nếu cần
│   ├── I/O subsystem chậm? → Check storage layer, AWR I/O metrics
│   ├── Memory pressure? → Check swap usage, SGA/PGA sizing
│   └── Locks/blocking lan rộng? → Find root blocker, kill
│
└── Chỉ 1 vài SQL cụ thể chậm?
    ├── Plan thay đổi gần đây? → SQL Plan Baseline fix
    ├── Statistics vừa update? → Restore stats hoặc lock stats
    ├── Missing/invalid index? → Rebuild hoặc recreate index
    ├── Data growth (table lớn hơn)? → Cần tune lại (partition, index)
    └── Parameter thay đổi gần đây? → Review change log, rollback nếu cần
```

---

**Tài liệu tham khảo:**
- Oracle Database Backup and Recovery User's Guide 19c — Block Corruption
- Oracle Database Performance Tuning Guide 19c
- MOS Note 472231.1 (Block Corruption Troubleshooting)
- MOS Note 1448507.1 (Diagnosing Sudden Performance Degradation)
- www.tranvanbinh.vn
