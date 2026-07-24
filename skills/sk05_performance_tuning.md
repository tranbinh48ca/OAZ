---
name: oracle-performance-tuning
description: >
  Tối ưu hiệu năng Oracle Database và SQL Tuning chuyên sâu.
  Kích hoạt khi hỏi về: tối ưu Oracle, SQL chậm, query chậm, SQL tuning,
  explain plan, execution plan, AWR report phân tích, ASH analysis,
  wait events, buffer cache hit ratio, index optimization, missing index,
  full table scan, optimizer statistics, SQL plan baseline, SPM,
  parallel execution, partitioning performance, In-Memory column store,
  SGA PGA tuning, I/O optimization, top SQL by CPU, top SQL by IO,
  SQL Tuning Advisor, ADDM, performance degradation, database slow.
  Cung cấp giải pháp cụ thể với SQL, hints, recommendations.
---

# SK05 · Tối ưu Hiệu năng & SQL Tuning

**Phạm vi:** Oracle 11g, 12c, 19c, 21c, 23ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. AWR / ASH / ADDM ANALYSIS

### 1.1 Tạo và đọc AWR Report

```sql
-- Tìm snapshot IDs cần phân tích
SELECT snap_id,
       TO_CHAR(begin_interval_time,'YYYY-MM-DD HH24:MI') begin_time,
       TO_CHAR(end_interval_time,'YYYY-MM-DD HH24:MI')   end_time,
       ROUND((end_interval_time-begin_interval_time)*24*60) duration_min
FROM dba_hist_snapshot
WHERE begin_interval_time BETWEEN SYSDATE-1 AND SYSDATE
ORDER BY snap_id DESC;

-- Tạo AWR report dạng text (thay snap_id)
SELECT OUTPUT FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid   => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid      => &begin_snap,
    l_eid      => &end_snap));

-- Tạo ADDM report
BEGIN
  DBMS_ADVISOR.QUICK_TUNE(
    advisor_name => DBMS_ADVISOR.ADDM_ADVISOR,
    task_name    => 'ADDM_TASK_001',
    attr1        => &begin_snap,
    attr2        => &end_snap);
END;
/
SELECT DBMS_ADVISOR.GET_TASK_REPORT('ADDM_TASK_001') FROM dual;
```

### 1.2 Top SQL từ AWR

```sql
-- Top SQL by CPU trong khoảng thời gian
SELECT sql_id,
       ROUND(SUM(cpu_time_delta)/1e6,2) cpu_sec,
       SUM(executions_delta) execs,
       ROUND(SUM(cpu_time_delta)/1e6/NULLIF(SUM(executions_delta),0),3) cpu_per_exec,
       ROUND(SUM(elapsed_time_delta)/1e6,2) ela_sec,
       ROUND(SUM(buffer_gets_delta)/NULLIF(SUM(executions_delta),0),0) gets_per_exec
FROM dba_hist_sqlstat s
JOIN dba_hist_snapshot sn USING (snap_id, dbid, instance_number)
WHERE sn.begin_interval_time > SYSDATE - 1
GROUP BY sql_id
ORDER BY cpu_sec DESC
FETCH FIRST 15 ROWS ONLY;

-- Xem SQL text từ AWR
SELECT sql_text FROM dba_hist_sqltext WHERE sql_id = '&sql_id';

-- Top SQL by Physical Reads (I/O heavy)
SELECT sql_id,
       SUM(disk_reads_delta) total_disk_reads,
       ROUND(SUM(disk_reads_delta)/NULLIF(SUM(executions_delta),0),0) reads_per_exec
FROM dba_hist_sqlstat s
JOIN dba_hist_snapshot sn USING (snap_id, dbid, instance_number)
WHERE sn.begin_interval_time > SYSDATE - 1
GROUP BY sql_id
ORDER BY total_disk_reads DESC
FETCH FIRST 10 ROWS ONLY;
```

### 1.3 ASH — Active Session History

```sql
-- Sessions đang chờ gì trong 1 giờ qua
SELECT event, wait_class,
       COUNT(*) samples,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(),1) pct,
       ROUND(COUNT(*)*10/60,1) avg_active_sessions
FROM v$active_session_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '60' MINUTE
  AND session_type = 'FOREGROUND'
  AND session_state = 'WAITING'
GROUP BY event, wait_class
ORDER BY samples DESC
FETCH FIRST 10 ROWS ONLY;

-- SQL nào đang chiếm nhiều nhất
SELECT sql_id, sql_plan_hash_value,
       COUNT(*) samples,
       ROUND(COUNT(*)*100/SUM(COUNT(*)) OVER(),1) pct
FROM v$active_session_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '60' MINUTE
  AND session_type = 'FOREGROUND'
GROUP BY sql_id, sql_plan_hash_value
ORDER BY samples DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## 2. EXECUTION PLAN

### 2.1 Đọc Execution Plan

```sql
-- Xem plan của SQL đang chạy (không cần chạy lại)
SELECT * FROM TABLE(
  DBMS_XPLAN.DISPLAY_CURSOR('&sql_id', NULL, 'ALLSTATS LAST'));

-- Xem plan từ AWR (lịch sử)
SELECT * FROM TABLE(
  DBMS_XPLAN.DISPLAY_AWR('&sql_id', &plan_hash_value));

-- EXPLAIN PLAN thủ công
EXPLAIN PLAN FOR
  SELECT * FROM orders o
  JOIN customers c ON o.cust_id = c.cust_id
  WHERE o.order_date > SYSDATE - 30;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, NULL, 'TYPICAL'));

-- Plan với Actual Rows (phải có GATHER_PLAN_STATISTICS hint)
SELECT /*+ GATHER_PLAN_STATISTICS */ *
FROM orders WHERE order_date > SYSDATE - 30;

SELECT * FROM TABLE(
  DBMS_XPLAN.DISPLAY_CURSOR(FORMAT=>'ALLSTATS LAST'));
```

### 2.2 Đọc kết quả Plan — những điểm cần chú ý

```
Rows  | Bytes | Cost | Time     | Operation
------|-------|------|----------|---------
 1000 |  50K  |  500 | 00:00:06 | TABLE ACCESS FULL ← ⚠️ Nếu bảng lớn
    1 |   50  |    5 | 00:00:01 | INDEX RANGE SCAN  ← ✓ Tốt
```

**Red flags:**
- `TABLE ACCESS FULL` trên bảng lớn → thiếu index
- `Rows` thực tế >> Rows ước tính → statistics lỗi thời
- `NESTED LOOPS` với nhiều rows → nên dùng `HASH JOIN`
- `SORT (MERGE JOIN)` trên large table → index join sẽ tốt hơn
- `Buffers` rất cao → full scan hoặc index không selective

---

## 3. INDEX DESIGN & OPTIMIZATION

### 3.1 Phân tích Index

```sql
-- Index usage (từ 19c: v$index_usage_info)
SELECT index_name, table_name,
       total_access_count,
       total_rows_returned,
       bucket_0_access_count  -- Chưa bao giờ dùng
FROM v$index_usage_info
WHERE owner = 'SCOTT'
ORDER BY total_access_count ASC;

-- Index hiện có và clustering factor
SELECT index_name, index_type, uniqueness,
       num_rows, distinct_keys,
       clustering_factor,
       ROUND(clustering_factor/num_rows*100,1) cf_ratio_pct
FROM dba_indexes
WHERE table_name = 'ORDERS'
  AND owner = 'SCOTT'
ORDER BY index_name;
-- CF gần num_rows = data sắp xếp ngẫu nhiên (index range scan tốn I/O)
-- CF gần blocks  = data sắp xếp gần với index order (index rất hiệu quả)

-- Missing indexes từ AWR/ADDM (qua SQL Access Advisor)
BEGIN
  DBMS_ADVISOR.QUICK_TUNE(
    advisor_name => DBMS_ADVISOR.SQLACCESS_ADVISOR,
    task_name    => 'IDX_ADVISOR',
    attr1        => 'SELECT * FROM orders WHERE cust_id = :1 AND status = :2');
END;
/
SELECT * FROM dba_advisor_recommendations
WHERE task_name = 'IDX_ADVISOR';
```

### 3.2 Tạo Index tối ưu

```sql
-- B-tree index thông thường (ONLINE để không lock table)
CREATE INDEX idx_orders_cust_date
  ON orders(cust_id, order_date)
  TABLESPACE INDX
  ONLINE;

-- Function-based index (khi query dùng function)
-- Query: WHERE UPPER(last_name) = 'NGUYEN'
CREATE INDEX idx_emp_upper_lastname
  ON employees(UPPER(last_name));

-- Invisible index (test trước khi apply)
CREATE INDEX idx_test ON orders(status) INVISIBLE;
-- Test với: ALTER SESSION SET optimizer_use_invisible_indexes = TRUE;
-- Nếu tốt → ALTER INDEX idx_test VISIBLE;

-- Partial index (19c+, chỉ index rows thỏa điều kiện)
CREATE INDEX idx_orders_active
  ON orders(order_id)
  WHERE status = 'ACTIVE';  -- Chỉ index orders đang active

-- Composite index: thứ tự cột quan trọng
-- Rule: Equality columns trước, Range column cuối
-- Query: WHERE cust_id = :1 AND order_date BETWEEN :2 AND :3
-- Index: (cust_id, order_date) ← đúng thứ tự
CREATE INDEX idx_orders_cust_date ON orders(cust_id, order_date) ONLINE;
```

---

## 4. SQL TUNING ADVISOR

```sql
-- Chạy SQL Tuning Advisor cho một SQL cụ thể
DECLARE
  l_task_name VARCHAR2(30);
BEGIN
  l_task_name := DBMS_SQLTUNE.CREATE_TUNING_TASK(
    sql_id     => '&sql_id',
    time_limit => 60,
    task_name  => 'TUNE_SQL_001',
    description => 'Tune slow orders query');

  DBMS_SQLTUNE.EXECUTE_TUNING_TASK(task_name => 'TUNE_SQL_001');
END;
/

-- Xem recommendations
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('TUNE_SQL_001')
FROM dual;

-- Accept SQL Profile nếu tốt
EXEC DBMS_SQLTUNE.ACCEPT_SQL_PROFILE(
  task_name    => 'TUNE_SQL_001',
  task_owner   => 'SYS',
  replace      => TRUE,
  force_match  => TRUE);

-- Xem SQL Profiles đã có
SELECT name, sql_text, status, force_matching
FROM dba_sql_profiles
ORDER BY created DESC;

-- Drop SQL Profile không cần nữa
EXEC DBMS_SQLTUNE.DROP_SQL_PROFILE('SYS_SQLPROF_...');
```

---

## 5. SQL PLAN MANAGEMENT (SPM)

```sql
-- Capture baseline cho SQL đang chạy tốt
DECLARE
  l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_CURSOR_CACHE(
    sql_id          => '&sql_id',
    plan_hash_value => &plan_hash,
    fixed           => 'YES',   -- Fix plan này
    enabled         => 'YES');
  DBMS_OUTPUT.PUT_LINE('Plans loaded: ' || l_plans);
END;
/

-- Xem SQL Plan Baselines
SELECT sql_handle, plan_name, enabled, accepted, fixed,
       reproduced, origin,
       TO_CHAR(created,'YYYY-MM-DD HH24:MI') created
FROM dba_sql_plan_baselines
WHERE sql_text LIKE '%orders%'
ORDER BY created DESC;

-- Evolve baseline (kiểm tra plan mới có tốt hơn không)
DECLARE
  report CLOB;
BEGIN
  report := DBMS_SPM.EVOLVE_SQL_PLAN_BASELINE(
    sql_handle => 'SQL_xxxxxxxxxxxxxxx',
    time_limit => 30,
    verify     => 'YES',
    commit     => 'YES');
  DBMS_OUTPUT.PUT_LINE(report);
END;
/

-- Drop baseline không cần
DECLARE
  n INTEGER;
BEGIN
  n := DBMS_SPM.DROP_SQL_PLAN_BASELINE(
    sql_handle => 'SQL_xxx',
    plan_name  => 'SQL_PLAN_xxx');
END;
/
```

---

## 6. MEMORY TUNING

```sql
-- SGA/PGA hiện tại
SELECT component, current_size/1024/1024/1024 current_gb,
       min_size/1024/1024/1024 min_gb,
       max_size/1024/1024/1024 max_gb
FROM v$sga_dynamic_components
ORDER BY current_size DESC;

-- Buffer Cache Hit Ratio (mục tiêu >= 95%)
SELECT ROUND(
  (1 - phys_reads / (db_blk_gets + consist_gets)) * 100, 2
) buffer_hit_ratio_pct
FROM (
  SELECT SUM(value) phys_reads
  FROM v$sysstat WHERE name = 'physical reads'
), (
  SELECT SUM(value) db_blk_gets
  FROM v$sysstat WHERE name = 'db block gets'
), (
  SELECT SUM(value) consist_gets
  FROM v$sysstat WHERE name = 'consistent gets'
);

-- Library Cache Hit Ratio (mục tiêu >= 99%)
SELECT ROUND(
  SUM(pinhits)/SUM(pins)*100, 2
) library_hit_ratio_pct
FROM v$librarycache;

-- Shared Pool Free (cần giữ > 10%)
SELECT name, ROUND(bytes/1024/1024,2) mb
FROM v$sgastat
WHERE pool = 'shared pool'
  AND name IN ('free memory', 'sql area', 'library cache')
ORDER BY bytes DESC;

-- PGA usage
SELECT name, ROUND(value/1024/1024,2) mb
FROM v$pgastat
WHERE name IN (
  'total PGA inuse', 'total PGA allocated',
  'total PGA used for auto workareas',
  'PGA memory freed back to OS')
ORDER BY value DESC;

-- Resize SGA dynamically
ALTER SYSTEM SET db_cache_size    = 8G  SCOPE=BOTH;
ALTER SYSTEM SET shared_pool_size = 3G  SCOPE=BOTH;

-- Resize PGA
ALTER SYSTEM SET pga_aggregate_target = 4G SCOPE=BOTH;
```

---

## 7. PARTITIONING FOR PERFORMANCE

```sql
-- Tạo Range Partition table
CREATE TABLE sales_data (
  sale_id    NUMBER,
  sale_date  DATE NOT NULL,
  amount     NUMBER,
  region     VARCHAR2(20)
)
PARTITION BY RANGE (sale_date) INTERVAL (NUMTOYMINTERVAL(1,'MONTH'))
(PARTITION p_before_2024 VALUES LESS THAN (DATE '2024-01-01'))
TABLESPACE APP_DATA;

-- Kiểm tra partition pruning trong plan
EXPLAIN PLAN FOR
SELECT * FROM sales_data
WHERE sale_date BETWEEN DATE '2024-01-01' AND DATE '2024-01-31';
-- Tìm: "Pstart" và "Pstop" trong plan → pruning hoạt động

-- List partition (cho categorical data)
CREATE TABLE orders (
  order_id  NUMBER,
  region    VARCHAR2(10),
  status    VARCHAR2(20)
)
PARTITION BY LIST (region) (
  PARTITION p_north  VALUES ('HN','BN','TN'),
  PARTITION p_south  VALUES ('HCM','BD','DN'),
  PARTITION p_others VALUES (DEFAULT)
);

-- Xem partition info
SELECT partition_name, num_rows,
       TO_CHAR(last_analyzed,'YYYY-MM-DD') analyzed
FROM dba_tab_partitions
WHERE table_name = 'SALES_DATA'
  AND table_owner = 'SCOTT'
ORDER BY partition_position DESC;

-- Gather stats chỉ cho partition mới
EXEC DBMS_STATS.GATHER_TABLE_STATS(
  ownname    => 'SCOTT',
  tabname    => 'SALES_DATA',
  partname   => 'SYS_P_2024_01',
  granularity => 'PARTITION');
```

---

## 8. COMMON TUNING HINTS

```sql
-- Index hint (buộc dùng index cụ thể)
SELECT /*+ INDEX(o idx_orders_cust_date) */
  o.order_id, o.amount
FROM orders o
WHERE o.cust_id = 1234
  AND o.order_date > SYSDATE - 30;

-- Full scan hint (khi full scan tốt hơn index)
SELECT /*+ FULL(o) */ * FROM orders o
WHERE status IN ('CANCELLED','REFUNDED');

-- Parallel hint
SELECT /*+ PARALLEL(o,4) */ COUNT(*)
FROM orders o
WHERE order_date > SYSDATE - 365;

-- Hash join hint (thay nested loops)
SELECT /*+ USE_HASH(o c) */
  o.order_id, c.cust_name
FROM orders o, customers c
WHERE o.cust_id = c.cust_id
  AND o.order_date > SYSDATE - 30;

-- No-merge view hint
SELECT /*+ NO_MERGE(v) */
  v.region, SUM(v.amount)
FROM (SELECT region, amount FROM orders WHERE status='COMPLETED') v
GROUP BY v.region;
```

---

## 9. TOP SQL REAL-TIME

```sql
-- Top SQL đang chạy ngay lúc này (từ v$sql)
SELECT sql_id,
       ROUND(cpu_time/1e6,2) cpu_sec,
       ROUND(elapsed_time/1e6,2) ela_sec,
       executions,
       ROUND(elapsed_time/1e6/NULLIF(executions,0),3) ela_per_exec,
       buffer_gets,
       ROUND(buffer_gets/NULLIF(executions,0),0) gets_per_exec,
       disk_reads,
       parsing_schema_name schema_name,
       SUBSTR(sql_text,1,80) sql_preview
FROM v$sqlarea
WHERE last_active_time > SYSDATE - 1/24  -- 1 giờ qua
  AND executions > 0
ORDER BY cpu_time DESC
FETCH FIRST 15 ROWS ONLY;

-- SQL Top by Logical Reads (Buffer Gets)
SELECT sql_id, buffer_gets,
       ROUND(buffer_gets/NULLIF(executions,0),0) gets_per_exec,
       executions,
       parsing_schema_name,
       SUBSTR(sql_text,1,80) sql_preview
FROM v$sqlarea
WHERE last_active_time > SYSDATE - 1/24
ORDER BY buffer_gets DESC
FETCH FIRST 10 ROWS ONLY;
```

---

## Tài liệu tham khảo
- Oracle Database Performance Tuning Guide 19c
- Oracle SQL Tuning Guide
- Jonathan Lewis — Cost-Based Oracle Fundamentals
- www.tranvanbinh.vn — Khóa học Tối ưu Oracle
