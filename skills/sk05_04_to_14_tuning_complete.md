---
name: oracle-performance-tuning-complete
description: >
  Oracle Performance Tuning toàn diện: SQL Tuning Advisor, SPM, Memory,
  I/O, Wait Events, Partitioning, Parallel, In-Memory, Real Application Testing.
  Kích hoạt khi hỏi về: SQL Tuning Advisor, DBMS_SQLTUNE, SQL profile Oracle,
  SQL Plan Management SPM, SQL plan baseline, plan stabilization Oracle,
  memory tuning Oracle, SGA tuning, PGA tuning, buffer cache sizing,
  I/O Oracle tuning, disk I/O wait, db file sequential read,
  wait event analysis Oracle, log file sync, enqueue wait,
  buffer busy waits, library cache pin, partitioning performance Oracle,
  partition pruning, partition-wise join, parallel query Oracle,
  DOP degree of parallelism, parallel DML Oracle, In-Memory Oracle,
  INMEMORY column store, IM population, vector join Oracle,
  Real Application Testing, Database Replay, SQL Performance Analyzer SPA.
---

# SK05-04 to SK05-14 · SQL Tuning, SPM, Memory, I/O, Partitioning, Parallel, In-Memory, RAT

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

# SK05-04 · SQL TUNING ADVISOR

## 1. DBMS_SQLTUNE

```sql
-- ── Tune một SQL cụ thể ───────────────────────────────────
DECLARE
  l_task_name VARCHAR2(30);
BEGIN
  -- Tạo task từ sql_id
  l_task_name := DBMS_SQLTUNE.CREATE_TUNING_TASK(
    sql_id      => '3d5x7gq9f8vbh',
    plan_hash_value => NULL,     -- NULL = tất cả plans
    scope       => 'COMPREHENSIVE',
    time_limit  => 300,          -- 5 phút
    task_name   => 'TUNE_ORDERS_001',
    description => 'Tuning slow orders query'
  );

  DBMS_SQLTUNE.EXECUTE_TUNING_TASK('TUNE_ORDERS_001');
END;
/

-- Xem recommendations
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK(
  task_name   => 'TUNE_ORDERS_001',
  type        => 'TEXT',
  level       => 'TYPICAL'  -- BASIC | TYPICAL | ALL
) FROM dual;

-- Accept SQL Profile nếu tốt
EXEC DBMS_SQLTUNE.ACCEPT_SQL_PROFILE(
  task_name    => 'TUNE_ORDERS_001',
  replace      => TRUE,
  force_match  => TRUE  -- Match bất kể literal values
);

-- Tune từ SQL text trực tiếp
DECLARE
  l_sql  CLOB := 'SELECT * FROM orders o
                  JOIN customers c ON o.customer_id = c.customer_id
                  WHERE o.status = ''ACTIVE''';
BEGIN
  DBMS_SQLTUNE.CREATE_TUNING_TASK(
    sql_text    => l_sql,
    user_name   => 'SCOTT',
    scope       => 'COMPREHENSIVE',
    time_limit  => 120,
    task_name   => 'TUNE_SQL_TEXT'
  );
  DBMS_SQLTUNE.EXECUTE_TUNING_TASK('TUNE_SQL_TEXT');
END;
/

-- Tune top SQL từ AWR
EXEC DBMS_SQLTUNE.CREATE_TUNING_TASK(
  begin_snap  => 1200,
  end_snap    => 1210,
  rank_measure1 => 'ELAPSED_TIME',
  num_sqls    => 20,
  task_name   => 'TOP_SQL_TUNING'
);
EXEC DBMS_SQLTUNE.EXECUTE_TUNING_TASK('TOP_SQL_TUNING');
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('TOP_SQL_TUNING') FROM dual;

-- Manage SQL Profiles
SELECT name, sql_text, status, force_matching
FROM dba_sql_profiles
ORDER BY created DESC;

EXEC DBMS_SQLTUNE.ALTER_SQL_PROFILE(
  name       => 'SYS_SQLPROF_01234567890',
  attribute_name => 'STATUS',
  value      => 'DISABLED'
);
EXEC DBMS_SQLTUNE.DROP_SQL_PROFILE('SYS_SQLPROF_01234567890');
```

---

# SK05-05 · SQL PLAN MANAGEMENT (SPM)

## 1. SQL Plan Baselines

```sql
-- ── Capture SQL Plan Baselines ────────────────────────────
-- Phương pháp 1: Tự động capture (cần optimizer_capture_sql_plan_baselines=TRUE)
ALTER SYSTEM SET optimizer_capture_sql_plan_baselines = TRUE SCOPE=BOTH;
ALTER SYSTEM SET optimizer_use_sql_plan_baselines = TRUE SCOPE=BOTH;

-- Phương pháp 2: Capture thủ công từ cursor cache (SQL đang dùng plan tốt)
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(
    sql_id          => '3d5x7gq9f8vbh',
    plan_hash_value => 12345678,  -- Plan hash của plan TỐT
    fixed           => 'YES',     -- YES = Oracle luôn dùng plan này
    enabled         => 'YES'
  );
  DBMS_OUTPUT.PUT_LINE('Loaded ' || l_plans || ' plans');
END;
/

-- Phương pháp 3: Load từ AWR
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_AWR(
    begin_snap => 1200,
    end_snap   => 1210,
    basic_filter => 'sql_id = ''3d5x7gq9f8vbh'''
  );
END;
/

-- ── Xem và manage baselines ──────────────────────────────
SELECT sql_handle, plan_name, sql_text,
       enabled, accepted, fixed, reproduced,
       TO_CHAR(created,'YYYY-MM-DD HH24:MI') created,
       TO_CHAR(last_modified,'YYYY-MM-DD HH24:MI') modified,
       origin      -- MANUAL-LOAD | AUTO-CAPTURE | EVOLVED
FROM dba_sql_plan_baselines
WHERE sql_text LIKE '%orders%'
ORDER BY created DESC;

-- Fix một baseline (Oracle PHẢI dùng plan này)
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.ALTER_SQL_PLAN_BASELINE(
    sql_handle  => 'SQL_1234567890abcdef',
    plan_name   => 'SQL_PLAN_abc123xyz',
    attribute_name => 'FIXED',
    attribute_value => 'YES'
  );
END;
/

-- Evolve baselines (kiểm tra plans mới có tốt hơn không)
DECLARE
  l_report CLOB;
BEGIN
  l_report := DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(
    sql_handle => 'SQL_1234567890abcdef',
    time_limit => 120,
    verify     => 'YES',   -- Test plan trước khi accept
    commit     => 'YES'    -- Tự động accept nếu tốt hơn
  );
  DBMS_OUTPUT.PUT_LINE(l_report);
END;
/

-- Drop baseline
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.DROP_SQL_PLAN_BASELINE(
    sql_handle => 'SQL_1234567890abcdef',
    plan_name  => 'SQL_PLAN_abc123xyz'
  );
END;
/

-- Export/Import baselines (giữa environments)
-- Export:
EXEC DBMS_SPM.PACK_STGTAB_BASELINE(
  table_name     => 'SPM_STAGING',
  sql_handle     => 'SQL_1234567890abcdef'
);
-- Import trên target:
EXEC DBMS_SPM.UNPACK_STGTAB_BASELINE(
  table_name => 'SPM_STAGING',
  fixed      => 'YES'
);
```

---

# SK05-06 · MEMORY TUNING

## 1. SGA Tuning

```sql
-- ── Xem SGA tổng quan ────────────────────────────────────
SELECT component,
       ROUND(current_size/1024/1024/1024, 3) current_gb,
       ROUND(min_size/1024/1024/1024, 3) min_gb,
       ROUND(max_size/1024/1024/1024, 3) max_gb,
       last_oper_type, last_oper_time
FROM v$sga_dynamic_components
ORDER BY current_size DESC;

-- ── Buffer Cache sizing ───────────────────────────────────
-- Xem advice
SELECT size_for_estimate size_mb,
       ROUND(buffers_for_estimate) buffers,
       ROUND(estd_physical_read_factor, 3) io_reduction_factor,
       estd_physical_reads
FROM v$db_cache_advice
WHERE name = 'DEFAULT'
  AND block_size = (SELECT TO_NUMBER(value) FROM v$parameter
                   WHERE name = 'db_block_size')
ORDER BY size_for_estimate;
-- io_reduction_factor < 1 → tăng cache sẽ giảm I/O
-- io_reduction_factor = 1 → đã đủ cache

-- ── Shared Pool tuning ────────────────────────────────────
-- Library Cache miss rate
SELECT ROUND((1 - SUM(pinhits)/SUM(pins))*100, 2) lib_miss_pct
FROM v$librarycache;
-- Mục tiêu: < 1% miss

-- Shared Pool free memory
SELECT ROUND(bytes/1024/1024, 2) free_mb
FROM v$sgastat WHERE pool='shared pool' AND name='free memory';
-- Cần > 10-15% free

-- Dictionary cache hit rate
SELECT ROUND((1 - SUM(getmisses)/SUM(gets))*100, 2) dict_hit_pct
FROM v$rowcache;
-- Mục tiêu: > 95%

-- ── Thay đổi SGA sizes (ASMM mode) ──────────────────────
ALTER SYSTEM SET db_cache_size    = 16G SCOPE=BOTH;
ALTER SYSTEM SET shared_pool_size = 4G  SCOPE=BOTH;
ALTER SYSTEM SET large_pool_size  = 1G  SCOPE=BOTH;
ALTER SYSTEM SET java_pool_size   = 256M SCOPE=BOTH;
ALTER SYSTEM SET streams_pool_size = 512M SCOPE=BOTH;

-- Tắt AMM, enable ASMM:
ALTER SYSTEM SET memory_target     = 0   SCOPE=SPFILE;
ALTER SYSTEM SET sga_target        = 24G SCOPE=BOTH;
ALTER SYSTEM SET pga_aggregate_target = 8G SCOPE=BOTH;

## 2. PGA Tuning

-- ── PGA advice ───────────────────────────────────────────
SELECT pga_target_for_estimate target_mb,
       estd_pga_cache_hit_percentage hit_pct,
       estd_overalloc_count overalloc_count
FROM v$pga_target_advice
ORDER BY pga_target_for_estimate;
-- Tìm điểm: hit_pct = 100% và overalloc_count = 0
-- Đó là optimal PGA target

-- Xem PGA usage
SELECT name, ROUND(value/1024/1024, 2) mb
FROM v$pgastat
WHERE name IN (
  'total PGA inuse',
  'total PGA allocated',
  'maximum PGA allocated',
  'total PGA used for auto workareas',
  'over allocation count',    -- > 0 = PGA quá nhỏ
  'extra bytes read/written'  -- > 0 = spill to disk
);

-- Adjust PGA
ALTER SYSTEM SET pga_aggregate_target = 8G SCOPE=BOTH;
ALTER SYSTEM SET pga_aggregate_limit  = 16G SCOPE=BOTH;  -- Hard ceiling

-- Per-session sort area (override automatic PGA)
ALTER SESSION SET sort_area_size = 134217728;      -- 128MB sort
ALTER SESSION SET workarea_size_policy = MANUAL;   -- Phải set này trước
```

---

# SK05-07 · I/O OPTIMIZATION

```sql
-- ── Kiểm tra I/O per datafile ────────────────────────────
SELECT df.name datafile_name,
       fs.phyrds physical_reads,
       fs.phywrts physical_writes,
       ROUND(fs.readtim*10/NULLIF(fs.phyrds,0), 2) avg_read_ms,
       ROUND(fs.writetim*10/NULLIF(fs.phywrts,0), 2) avg_write_ms,
       fs.avgiotim avg_io_ms
FROM v$datafile df
JOIN v$filestat fs ON df.file# = fs.file#
ORDER BY (fs.phyrds + fs.phywrts) DESC
FETCH FIRST 10 ROWS ONLY;

-- ── ASM disk I/O balance ─────────────────────────────────
SELECT dg.name diskgroup,
       d.name disk_name,
       d.reads, d.writes,
       ROUND(d.read_time/NULLIF(d.reads,0)*1000, 2)  avg_read_ms,
       ROUND(d.write_time/NULLIF(d.writes,0)*1000, 2) avg_write_ms,
       d.hot_reads, d.cold_reads
FROM v$asm_diskgroup dg
JOIN v$asm_disk d ON dg.group_number = d.group_number
ORDER BY (d.reads + d.writes) DESC;
-- Nếu hot_reads >> cold_reads → hot blocks issue
-- Nếu một số disks nhiều hơn = imbalanced I/O → rebalance

-- ── I/O Calibration ──────────────────────────────────────
-- Đo throughput thực của storage
BEGIN
  DBMS_RESOURCE_MANAGER.CALIBRATE_IO(
    num_physical_disks  => 8,       -- Số physical disks
    max_latency         => 10,      -- Max acceptable latency (ms)
    max_iops            => NULL,    -- Output
    max_mbps            => NULL,    -- Output
    actual_latency      => NULL     -- Output
  );
END;
/

-- Xem kết quả calibration
SELECT max_iops, max_mbps, max_pmbps, latency, num_physical_disks,
       calibration_time
FROM dba_rsrc_io_calibrate;

-- ── Direct Path Reads/Writes ─────────────────────────────
-- Direct reads bypass buffer cache → tốt cho large table scans
SHOW PARAMETER db_file_direct_io_count;
-- Kiểm tra parallel query dùng direct reads:
SELECT name, value FROM v$sysstat
WHERE name IN ('physical reads direct', 'physical reads cache');
-- direct >> cache cho DWH workload = BÌNH THƯỜNG
-- direct >> cache cho OLTP = VẤN ĐỀ

-- ── FRA sizing ───────────────────────────────────────────
SELECT name,
       ROUND(space_limit/1024/1024/1024, 2) limit_gb,
       ROUND(space_used/1024/1024/1024, 2) used_gb,
       ROUND(space_reclaimable/1024/1024/1024, 2) reclaimable_gb,
       ROUND(space_used/space_limit*100, 1) pct_used
FROM v$recovery_file_dest;

ALTER SYSTEM SET db_recovery_file_dest_size = 200G SCOPE=BOTH;
```

---

# SK05-08 · WAIT EVENT ANALYSIS

```sql
-- ── TOP WAIT EVENTS HIỆN TẠI ────────────────────────────
SELECT event, wait_class,
       total_waits,
       ROUND(time_waited_micro/1e6, 2) time_sec,
       ROUND(time_waited_micro/1e6/NULLIF(total_waits,0)*1000, 2) avg_wait_ms,
       ROUND(time_waited_micro/SUM(time_waited_micro) OVER()*100, 1) pct_total
FROM v$system_event
WHERE wait_class NOT IN ('Idle','Background')
  AND total_waits > 100
ORDER BY time_waited_micro DESC
FETCH FIRST 15 ROWS ONLY;

-- ── WAIT EVENT DIAGNOSIS TABLE ─────────────────────────
/*
db file sequential read:
  = Index access / single block reads
  High: index inefficient, clustering factor cao, missing index
  Fix: check index design, rebuild index, partitioning

db file scattered read:
  = FTS / multi-block reads
  High: excessive full table scans
  Fix: add indexes, check statistics, partitioning

log file sync:
  = COMMIT waits (LGWR write redo → disk)
  High: too many small commits, slow I/O
  Fix: batch commits, faster storage for redo, log file size

log file parallel write:
  = LGWR writing redo logs
  High: redo log on slow storage
  Fix: dedicated fast disk for redo (SSD/NVMe)

buffer busy waits:
  = Multiple sessions want same block
  High: hot blocks (sequences, right-growing indexes)
  Fix: reverse key index, sequence CACHE↑, hash partitioning

library cache: mutex X / pin:
  = Library cache contention
  High: hard parses, missing bind variables
  Fix: cursor_sharing=FORCE, fix app to use bind variables

enq: TX - row lock contention:
  = Row-level lock waits
  High: blocking sessions, long-running DML
  Fix: find and kill blocking session, investigate app

latch free:
  = Latch contention
  High: high concurrency, memory structures under load
  Fix: check specific latch name, may need Oracle Support

read by other session:
  = Session waiting for another session to read same block
  High: table full scans with parallel, hot blocks
  Fix: check hot blocks, consider partitioning

gc buffer busy acquire/release (RAC):
  = Global cache contention (Cache Fusion)
  High: same blocks accessed on multiple nodes
  Fix: service-based routing, local cache affinity

SQL*Net message from client:
  = Idle wait (application thinks time)
  High = OK if application is doing processing
  Fix if unexpectedly high: connection pooling
*/

-- ── WAIT EVENT DETAIL PER SESSION ────────────────────────
SELECT sw.event, sw.wait_class,
       sw.wait_time_micro/1000 current_wait_ms,
       sw.state,
       s.sid, s.serial#, s.username, s.sql_id
FROM v$session_wait sw
JOIN v$session s ON sw.sid = s.sid
WHERE s.type = 'USER'
  AND sw.event NOT IN (
    'SQL*Net message from client',
    'jobq slave wait',
    'Space Manager: slave idle wait')
ORDER BY sw.wait_time_micro DESC;
```

---

# SK05-09 · PARTITIONING FOR PERFORMANCE

```sql
-- ── RANGE PARTITIONING ───────────────────────────────────
CREATE TABLE sales_data (
  sale_id    NUMBER,
  sale_date  DATE NOT NULL,
  region     VARCHAR2(20),
  amount     NUMBER
)
PARTITION BY RANGE (sale_date)
INTERVAL (NUMTOYMINTERVAL(1,'MONTH'))  -- Auto partition monthly
(
  PARTITION p_before_2024 VALUES LESS THAN (DATE '2024-01-01')
);

-- ── LIST PARTITIONING ────────────────────────────────────
CREATE TABLE orders_geo (
  order_id NUMBER,
  region VARCHAR2(10),
  status VARCHAR2(20),
  amount NUMBER
)
PARTITION BY LIST (region) (
  PARTITION p_north   VALUES ('HN','HP','QB'),
  PARTITION p_central VALUES ('DN','HUE','QNA'),
  PARTITION p_south   VALUES ('HCM','BD','BVT'),
  PARTITION p_others  VALUES (DEFAULT)
);

-- ── HASH PARTITIONING (even distribution) ────────────────
CREATE TABLE transactions (
  txn_id   NUMBER,
  account_id NUMBER,
  txn_date DATE,
  amount   NUMBER
)
PARTITION BY HASH (account_id)
PARTITIONS 16  -- Power of 2 khuyến dùng
STORE IN (DATA_TBS1, DATA_TBS2, DATA_TBS3, DATA_TBS4);

-- ── COMPOSITE: Range-Hash ─────────────────────────────────
CREATE TABLE fact_sales (
  sale_id  NUMBER,
  sale_date DATE,
  region   VARCHAR2(20),
  amount   NUMBER
)
PARTITION BY RANGE (sale_date)
SUBPARTITION BY HASH (region)
SUBPARTITIONS 4
(
  PARTITION p_2024 VALUES LESS THAN (DATE '2025-01-01'),
  PARTITION p_2025 VALUES LESS THAN (DATE '2026-01-01'),
  PARTITION p_2026 VALUES LESS THAN (DATE '2027-01-01')
);

-- ── VERIFY PARTITION PRUNING ─────────────────────────────
-- Partition pruning: Oracle chỉ scan relevant partitions
EXPLAIN PLAN FOR
SELECT * FROM sales_data
WHERE sale_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-31';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,NULL,'PARTITION'));
-- Tìm: "Pstart" và "Pstop" → pruning đang hoạt động
-- Pstart=1 Pstop=1 → chỉ scan 1 partition

-- ── PARTITION-WISE JOIN ───────────────────────────────────
-- Khi cả 2 tables partitioned theo cùng column → parallel join per partition
EXPLAIN PLAN FOR
SELECT s.sale_id, s.amount, t.txn_date
FROM sales_data s JOIN transactions t
  ON s.account_id = t.account_id  -- cùng partition column
WHERE s.sale_date > DATE '2026-01-01';
-- Tìm: "PARTITION JOIN" trong plan

-- ── PARTITIONING MANAGEMENT ──────────────────────────────
-- Thêm partition
ALTER TABLE sales_data ADD PARTITION p_2027
  VALUES LESS THAN (DATE '2028-01-01');

-- Drop partition (nhanh hơn DELETE)
ALTER TABLE sales_data DROP PARTITION p_before_2024;

-- Split partition
ALTER TABLE sales_data SPLIT PARTITION p_2026
  AT (DATE '2026-07-01')
  INTO (PARTITION p_2026_h1, PARTITION p_2026_h2);

-- Merge partitions
ALTER TABLE sales_data MERGE PARTITIONS p_2024, p_2025
  INTO PARTITION p_2024_2025;

-- Truncate partition (nhanh, không tạo undo)
ALTER TABLE sales_data TRUNCATE PARTITION p_old;

-- Move partition (đổi tablespace, rebuild)
ALTER TABLE sales_data MOVE PARTITION p_2024
  TABLESPACE ARCHIVE_TBS;

-- Partition stats
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname    => 'DWH',
  tabname    => 'SALES_DATA',
  partname   => 'P_2026_01',
  granularity => 'PARTITION'
);

-- Xem partition sizes
SELECT partition_name, num_rows,
       ROUND(blocks*8192/1024/1024, 2) size_mb,
       TO_CHAR(last_analyzed,'YYYY-MM-DD') analyzed
FROM dba_tab_partitions
WHERE table_name='SALES_DATA' AND table_owner='DWH'
ORDER BY partition_position DESC;
```

---

# SK05-10 · PARALLEL EXECUTION

```sql
-- ── PARALLEL QUERY ───────────────────────────────────────
-- DOP (Degree of Parallelism): số parallel servers
-- Rule of thumb: DOP = min(CPU_count, #disk_spindles)

-- Force parallel trong query
SELECT /*+ PARALLEL(o, 8) */ COUNT(*), SUM(amount)
FROM orders o
WHERE order_date > SYSDATE - 365;

-- Table-level default DOP
ALTER TABLE orders PARALLEL 8;
ALTER TABLE orders NOPARALLEL;  -- Về serial

-- ── PARALLEL DML ─────────────────────────────────────────
-- Phải enable tường minh cho DML
ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ PARALLEL(target_table, 4) */
INTO target_table
SELECT /*+ PARALLEL(source_table, 4) */
  * FROM source_table WHERE condition;

-- Phải COMMIT sau PARALLEL DML (exclusive lock)
COMMIT;

ALTER SESSION DISABLE PARALLEL DML;

-- ── PARALLEL DDL ─────────────────────────────────────────
CREATE INDEX idx_large_table_col
  ON large_table(column1)
  PARALLEL 8
  NOLOGGING;  -- Kết hợp parallel + nologging = nhanh nhất

-- Sau khi tạo xong:
ALTER INDEX idx_large_table_col NOPARALLEL;
ALTER INDEX idx_large_table_col LOGGING;

-- ── PARALLEL TUNING ─────────────────────────────────────
-- Xem parallel execution statistics
SELECT s.sid, s.qcsid, s.server_group, s.server_set,
       s.degree, s.req_degree
FROM v$px_session s
JOIN v$session ps ON s.qcsid = ps.sid
WHERE ps.username IS NOT NULL;

-- PX downgrade (DOP được giảm)
SELECT qcsid, server_set, degree, req_degree
FROM v$px_session WHERE req_degree != degree;
-- Nếu degree < req_degree = Oracle downgraded DOP (không đủ PX servers)

SHOW PARAMETER parallel_max_servers;
SHOW PARAMETER parallel_min_servers;
ALTER SYSTEM SET parallel_max_servers = 128 SCOPE=BOTH;

-- Parallel degree policy
SHOW PARAMETER parallel_degree_policy;
-- MANUAL: DOP từ hint/table default
-- LIMITED: Oracle tự tính DOP nhưng giới hạn
-- AUTO:    Oracle tự tính DOP dựa trên workload
ALTER SYSTEM SET parallel_degree_policy = 'AUTO' SCOPE=BOTH;

-- Resource Manager với parallel limit
DBMS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
  plan          => 'DEFAULT_PLAN',
  group_or_subplan => 'BATCH_GROUP',
  parallel_server_limit => 25   -- Tối đa 25% parallel servers cho group
);
```

---

# SK05-11 to SK05-12 · IN-MEMORY COLUMN STORE

```sql
-- ── Enable In-Memory ────────────────────────────────────
ALTER SYSTEM SET inmemory_size = 4G SCOPE=SPFILE;
-- Cần restart DB sau khi set

-- Verify
SELECT ROUND(current_size/1024/1024/1024, 2) inmemory_gb
FROM v$inmemory_area;

-- ── Populate tables/columns ─────────────────────────────
-- Toàn bộ table
ALTER TABLE dwh.fact_sales INMEMORY;

-- Với priority (HIGH = populate ngay, CRITICAL = populate first)
ALTER TABLE dwh.dim_customer INMEMORY PRIORITY CRITICAL;

-- Specific columns (giảm memory footprint)
ALTER TABLE dwh.fact_sales
  INMEMORY MEMCOMPRESS FOR QUERY LOW   -- Compression cho query speed
  (sale_id, sale_date, region, amount)  -- Chỉ cần columns này
  NO INMEMORY (description, notes);    -- Exclude heavy columns

-- Compression levels:
-- NO MEMCOMPRESS: không compress (fastest decode)
-- MEMCOMPRESS FOR DML: tối ưu cho DML
-- MEMCOMPRESS FOR QUERY LOW: tốt nhất cho scan (DEFAULT)
-- MEMCOMPRESS FOR QUERY HIGH: compress hơn, decode chậm hơn
-- MEMCOMPRESS FOR CAPACITY LOW/HIGH: compress maximum, chậm nhất

-- ── Xem IM population status ────────────────────────────
SELECT owner, segment_name, partition_name,
       populate_status,      -- COMPLETE | STARTED | NOT STARTED | OUT OF MEMORY
       ROUND(bytes/1024/1024, 2) disk_mb,
       ROUND(inmemory_size/1024/1024, 2) inmemory_mb,
       ROUND((1-inmemory_size/NULLIF(bytes,0))*100, 1) compression_pct
FROM v$im_segments
ORDER BY inmemory_size DESC;

-- Force populate
EXEC DBMS_INMEMORY.POPULATE('DWH', 'FACT_SALES');

-- ── IM Expressions (In-Memory Virtual Columns) ──────────
-- Precompute expressions cho columnar access
ALTER TABLE fact_sales INMEMORY EXPRESSIONS
  IDENTIFY OBJECTS;  -- Auto identify expressions từ query history

-- Xem IM expressions
SELECT table_name, column_name, evaluation_edition
FROM user_im_expressions;

-- ── Verify IM being used (plan) ─────────────────────────
EXPLAIN PLAN FOR
SELECT region, SUM(amount) FROM dwh.fact_sales
WHERE sale_date > DATE '2026-01-01'
GROUP BY region;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,NULL,'TYPICAL'));
-- Tìm: "TABLE ACCESS INMEMORY FULL" → In-Memory đang được dùng

-- IM scan stats
SELECT name, value FROM v$sysstat
WHERE name IN (
  'IM scan rows','IM scan rows projected',
  'IM scan CUs pruned','IM populate accumulated blocks'
);
```

---

# SK05-13 to SK05-14 · REAL APPLICATION TESTING (RAT)

## 1. DATABASE REPLAY

```sql
-- Database Replay: capture workload trên production, replay trên test

-- ── BƯỚC 1: CAPTURE workload (Production) ───────────────
-- Tạo thư mục
CREATE DIRECTORY CAPTURE_DIR AS '/u01/capture';

-- Start capture
EXEC DBMS_WORKLOAD_CAPTURE.START_CAPTURE(
  name           => 'PROD_CAPTURE_2026_01',
  dir            => 'CAPTURE_DIR',
  duration       => 3600,         -- Capture 1 giờ (NULL = manual stop)
  capture_sts    => TRUE,         -- Include SQL Tuning Set
  plsql_mode     => 'EXTENDED'    -- Capture PL/SQL calls
);

-- Thực hiện workload bình thường...

-- Stop capture
EXEC DBMS_WORKLOAD_CAPTURE.FINISH_CAPTURE();

-- Xem capture info
SELECT id, name, status, start_time, end_time,
       capture_size, dir_path
FROM dba_workload_captures
ORDER BY start_time DESC;

-- ── BƯỚC 2: PREPROCESS (Test environment) ────────────────
CREATE DIRECTORY CAPTURE_DIR AS '/u01/capture';

EXEC DBMS_WORKLOAD_REPLAY.PROCESS_CAPTURE(
  capture_dir => 'CAPTURE_DIR'
);

-- ── BƯỚC 3: REPLAY (Test environment) ───────────────────
-- Initialize replay
EXEC DBMS_WORKLOAD_REPLAY.INITIALIZE_REPLAY(
  replay_name => 'REPLAY_AFTER_UPGRADE',
  replay_dir  => 'CAPTURE_DIR'
);

-- Setup connection mapping (source → target connection strings)
EXEC DBMS_WORKLOAD_REPLAY.REMAP_CONNECTION(
  connection_id  => 1,
  replay_connection => '//test-server:1521/TESTDB'
);

-- Prepare clients (external wrc utility)
EXEC DBMS_WORKLOAD_REPLAY.START_REPLAY();

-- Monitor
SELECT name, status, elapsed_time, errors
FROM dba_workload_replays
WHERE id = (SELECT MAX(id) FROM dba_workload_replays);

-- ── BƯỚC 4: COMPARE RESULTS ─────────────────────────────
SELECT * FROM TABLE(
  DBMS_WORKLOAD_REPLAY.COMPARE_PERIOD_REPORT(
    replay_id1 => 1,
    replay_id2 => 2,
    format     => 'TEXT'
  )
);
```

## 2. SQL PERFORMANCE ANALYZER (SPA)

```sql
-- SPA: Test impact của change (upgrade, patch, stats change) lên SQL performance

-- ── BƯỚC 1: Capture SQL Tuning Set ──────────────────────
-- Tạo STS từ cursor cache
EXEC DBMS_SQLTUNE.CREATE_SQLSET(
  sqlset_name => 'STS_BEFORE_UPGRADE',
  description => 'SQL workload before upgrade'
);

DECLARE
  cur DBMS_SQLTUNE.SQLSET_CURSOR;
BEGIN
  OPEN cur FOR
    SELECT VALUE(t) FROM TABLE(
      DBMS_SQLTUNE.SELECT_CURSOR_CACHE(
        basic_filter => 'parsing_schema_name NOT IN (''SYS'',''SYSTEM'')',
        attribute_list => 'ALL'
      )
    ) t;
  DBMS_SQLTUNE.LOAD_SQLSET(
    sqlset_name => 'STS_BEFORE_UPGRADE',
    populate_cursor => cur
  );
  CLOSE cur;
END;
/

-- ── BƯỚC 2: SPA Task - Trước thay đổi ───────────────────
DECLARE
  l_task_name VARCHAR2(30);
BEGIN
  l_task_name := DBMS_SQLPA.CREATE_ANALYSIS_TASK(
    sqlset_name  => 'STS_BEFORE_UPGRADE',
    task_name    => 'SPA_UPGRADE_TEST',
    description  => 'SPA test for upgrade impact'
  );

  -- Execute: lấy plans hiện tại (BEFORE)
  DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
    task_name    => 'SPA_UPGRADE_TEST',
    execution_type => 'EXPLAIN PLAN',       -- Chỉ plans, không chạy
    execution_name => 'BEFORE_UPGRADE'
  );
END;
/

-- ── BƯỚC 3: Thực hiện thay đổi (nâng cấp, patch...) ────
-- ALTER SYSTEM UPGRADE, hoặc apply patch, hoặc change stats...

-- ── BƯỚC 4: SPA Task - Sau thay đổi ─────────────────────
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
  task_name      => 'SPA_UPGRADE_TEST',
  execution_type => 'EXPLAIN PLAN',
  execution_name => 'AFTER_UPGRADE'
);

-- ── BƯỚC 5: Compare ──────────────────────────────────────
EXEC DBMS_SQLPA.EXECUTE_ANALYSIS_TASK(
  task_name        => 'SPA_UPGRADE_TEST',
  execution_type   => 'COMPARE PERFORMANCE',
  execution_params => DBMS_ADVISOR.ARGLIST(
    'execution_name1', 'BEFORE_UPGRADE',
    'execution_name2', 'AFTER_UPGRADE'
  )
);

-- ── BƯỚC 6: Report ───────────────────────────────────────
SELECT DBMS_SQLPA.REPORT_ANALYSIS_TASK(
  task_name      => 'SPA_UPGRADE_TEST',
  type           => 'TEXT',
  level          => 'TYPICAL',
  section        => 'SUMMARY'
) FROM dual;

-- Xem SQL với performance regression
SELECT sql_id, object_type, execution_name,
       elapsed_time_impact,
       elapsed_time_ratio,
       message
FROM dba_advisor_sqlstats
WHERE task_name = 'SPA_UPGRADE_TEST'
  AND elapsed_time_impact < 0  -- Negative = SQL became slower
ORDER BY elapsed_time_impact ASC
FETCH FIRST 20 ROWS ONLY;

-- Fix regression: Dùng SPM để force old plan
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_SQLSET(
    sqlset_name => 'STS_BEFORE_UPGRADE',
    basic_filter => 'sql_id = ''regressed_sql_id''',
    fixed => 'YES'
  );
END;
/
```

---

**Tài liệu tham khảo:**
- Oracle SQL Tuning Guide 19c — SQL Tuning Advisor, SPM, In-Memory
- Oracle Real Application Testing User's Guide 19c
- Oracle Database VLDB and Partitioning Guide 19c
- Oracle Database Parallel Execution User's Guide
- Oracle Database In-Memory Guide 19c
- www.tranvanbinh.vn
