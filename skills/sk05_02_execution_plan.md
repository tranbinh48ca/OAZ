---
name: oracle-execution-plan-analysis
description: >
  Phân tích Execution Plan và SQL Diagnostics Oracle.
  Kích hoạt khi hỏi về: execution plan Oracle, explain plan Oracle,
  DBMS_XPLAN display_cursor, GATHER_PLAN_STATISTICS hint,
  ALLSTATS LAST execution plan, cardinality estimates Oracle,
  rows returned vs estimated Oracle, buffer gets per exec,
  INDEX RANGE SCAN vs FULL TABLE SCAN, NESTED LOOPS HASH JOIN MERGE JOIN,
  predicate information Oracle plan, access predicates filter predicates,
  plan hash value Oracle, adaptive plans Oracle, SQL monitoring,
  v$sql_plan_monitor, DBMS_SQLTUNE sqlset, TKPROF Oracle,
  10046 trace Oracle, SQL trace autotrace, 10053 optimizer trace,
  cardinality feedback Oracle, statistics feedback Oracle.
---

# SK05-02 · Execution Plan Analysis & SQL Diagnostics

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. EXPLAIN PLAN VÀ DISPLAY

### 1.1 EXPLAIN PLAN cơ bản

```sql
-- Bước 1: Tạo plan (không thực thi SQL)
EXPLAIN PLAN FOR
  SELECT o.order_id, o.amount, c.name
  FROM orders o
  JOIN customers c ON o.customer_id = c.customer_id
  WHERE o.status = 'ACTIVE'
    AND o.order_date > SYSDATE - 30;

-- Bước 2: Xem plan
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(
  table_name  => 'PLAN_TABLE',
  statement_id => NULL,
  format      => 'TYPICAL'  -- BASIC | TYPICAL | ALL | ADVANCED
));

-- Format options:
-- BASIC:    Chỉ Id, Operation, Object
-- TYPICAL:  + Rows, Bytes, Cost (default)
-- ALL:      + Partition, Parallel, Predicate
-- ADVANCED: + Column projection, Object statistics
```

### 1.2 DISPLAY_CURSOR — Xem plan của SQL đang/vừa chạy

```sql
-- Đây là cách TỐT NHẤT để xem ACTUAL execution plan

-- Step 1: Chạy SQL với GATHER_PLAN_STATISTICS hint
SELECT /*+ GATHER_PLAN_STATISTICS */
  o.order_id, o.amount, c.name
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.status = 'ACTIVE'
  AND o.order_date > SYSDATE - 30;

-- Step 2: Xem plan với ACTUAL rows
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id      => NULL,   -- NULL = SQL vừa chạy trong session
  cursor_child_no => 0,
  format      => 'ALLSTATS LAST'  -- Hiện actual statistics
));

-- Nếu biết sql_id:
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id      => '3d5x7gq9f8vbh',
  cursor_child_no => 0,
  format      => 'ALLSTATS LAST +PEEKED_BINDS'
));

-- Format ALLSTATS LAST output:
-- Starts: số lần operation được thực hiện
-- E-Rows: Estimated rows (từ optimizer)
-- A-Rows: Actual rows (thực tế)
-- Buffers: logical reads
-- Reads:  physical reads
-- A-Time: actual elapsed time
```

### 1.3 DISPLAY_AWR — Plan lịch sử

```sql
-- Xem plan từ AWR (plan đã captured trong lịch sử)
SELECT * FROM TABLE(
  DBMS_XPLAN.DISPLAY_AWR(
    sql_id          => '3d5x7gq9f8vbh',
    plan_hash_value => 12345678,   -- NULL = tất cả plans
    db_id           => NULL,       -- NULL = current DB
    format          => 'TYPICAL'
  )
);

-- Tìm plan_hash_values từ AWR
SELECT DISTINCT sql_id, plan_hash_value,
       TO_CHAR(MIN(timestamp),'YYYY-MM-DD HH24:MI') first_seen,
       TO_CHAR(MAX(timestamp),'YYYY-MM-DD HH24:MI') last_seen
FROM dba_hist_sql_plan
WHERE sql_id = '3d5x7gq9f8vbh'
GROUP BY sql_id, plan_hash_value
ORDER BY first_seen;
```

---

## 2. ĐỌC VÀ PHÂN TÍCH EXECUTION PLAN

### 2.1 Cấu trúc Plan

```
Plan Output Example:
─────────────────────────────────────────────────────────────
| Id | Operation              | Name      | Rows | Cost |
─────────────────────────────────────────────────────────────
|  0 | SELECT STATEMENT       |           |      |  1234|
|  1 |  HASH JOIN             |           | 5000 |  1234|
|  2 |   TABLE ACCESS BY INDEX| ORDERS    | 5000 |   800|
|* 3 |    INDEX RANGE SCAN    | IDX_ORD_D |      |    20|
|  4 |   TABLE ACCESS FULL    | CUSTOMERS | 100K |   400|
─────────────────────────────────────────────────────────────

Đọc plan: từ trong ra ngoài, từ dưới lên trên (children first)
→ Execution order: 3 → 2 → 4 → 1 → 0

* = Access/Filter predicate tại node này (xem Predicate Information)
```

### 2.2 Join Methods

```
NESTED LOOPS (NL):
  Tốt khi: driving set nhỏ (< vài nghìn rows), có index trên join key
  Tệ khi: cả 2 tables lớn

HASH JOIN:
  Tốt khi: cả 2 tables lớn, không có index hữu ích, parallel execution
  Memory: cần PGA đủ lớn (nếu không → disk spill)
  Tệ khi: non-equi joins (range join)

SORT MERGE JOIN:
  Tốt khi: data đã sorted, non-equi joins (>, <, >=, <=)
  Tệ khi: data lớn, cần sort (memory + disk)

Cross Join/Cartesian Product:
  LUÔN LÀ VẤN ĐỀ nếu không có WHERE clause nối 2 tables
```

### 2.3 Access Paths

```
FULL TABLE SCAN (FTS):
  OK khi: table nhỏ, query lấy > 15-20% rows, không có selective index
  VẤN ĐỀ khi: table lớn, chỉ lấy vài rows, có index phù hợp

INDEX UNIQUE SCAN:
  Tốt nhất: WHERE pk_col = :val (unique index, single value)

INDEX RANGE SCAN:
  Tốt: WHERE indexed_col BETWEEN :lo AND :hi
  Xem clustering factor: thấp = tốt, cao = nhiều random I/O

INDEX FULL SCAN:
  Oracle đọc toàn bộ index theo thứ tự key

INDEX FAST FULL SCAN:
  Đọc toàn index blocks theo physical order (parallel possible)
  Dùng khi query chỉ cần indexed columns

INDEX SKIP SCAN:
  Index composite (col1, col2), query WHERE col2 = :val
  Không có col1 trong WHERE → skip scan (kém hiệu quả)
  Fix: thêm col1 vào WHERE hoặc tạo index (col2)
```

### 2.4 Red Flags trong Execution Plan

```sql
-- Chạy script này để phát hiện vấn đề
SELECT id, operation, options, object_name,
       e_rows, a_rows,
       CASE
         -- Bad cardinality estimate
         WHEN e_rows > 0
          AND ABS(a_rows - e_rows) / GREATEST(e_rows,a_rows) > 0.5
          AND a_rows > 1000
         THEN '⚠️ Cardinality mismatch (E:'||e_rows||' A:'||a_rows||')'
         -- Full scan on large table
         WHEN operation = 'TABLE ACCESS' AND options = 'FULL'
          AND a_rows > 100000
         THEN '⚠️ Full scan returning '||a_rows||' rows'
         -- Cartesian product
         WHEN operation = 'MERGE JOIN' AND options = 'CARTESIAN'
         THEN '❌ CARTESIAN PRODUCT!'
         ELSE NULL
       END issue_flag
FROM (
  SELECT id, operation, options, object_name,
         ROUND(cardinality) e_rows,
         last_output_rows a_rows
  FROM v$sql_plan_statistics_all
  WHERE sql_id = '&sql_id' AND child_number = 0
)
WHERE issue_flag IS NOT NULL;
```

---

## 3. PREDICATE INFORMATION

```sql
-- Xem predicates từ plan
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  FORMAT => 'TYPICAL PREDICATE'  -- Hiện predicate details
));

/*
Predicate Information (identified by operation id):
───────────────────────────────────────────────────
   3 - access("O"."STATUS"='ACTIVE'
              AND "O"."ORDER_DATE">SYSDATE-30)
   4 - filter("C"."REGION"='VN')
   1 - access("O"."CUSTOMER_ID"="C"."CUSTOMER_ID")

access: Điều kiện dùng để traverse index → selective
filter: Áp dụng sau khi fetch rows → có thể bỏ qua nhiều rows

Vấn đề: Filter predicate trên index scan = index chưa optimal
Fix: Tạo composite index (col1, filter_col)
*/

-- Phân biệt access vs filter predicates
-- access predicate: Oracle dùng index để tìm đúng rows
-- filter predicate: Oracle đọc blocks rồi loại bỏ rows không match

-- Nếu thấy: index_col là filter, không phải access
-- → Thứ tự columns trong composite index sai
-- → Access pattern không match leading edge của index
```

---

## 4. ADAPTIVE PLANS (12c+)

```sql
-- Adaptive plan: optimizer thay đổi plan MID-EXECUTION
-- Dựa trên actual rows vs estimated rows

-- Xem nếu plan có adaptive components
SELECT sql_id, plan_hash_value, executions,
       is_resolved_adaptive_plan,
       is_bind_sensitive, is_bind_aware,
       is_shareable
FROM v$sql
WHERE sql_id = '&sql_id';

-- Xem adaptive plan details
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id => '&sql_id',
  format => 'ADAPTIVE'  -- Hiện full adaptive plan tree
));

-- Kiểm soát adaptive plans
ALTER SYSTEM SET optimizer_adaptive_plans = FALSE SCOPE=BOTH;  -- Tắt
ALTER SESSION SET optimizer_adaptive_plans = FALSE;

-- Cardinality Feedback (11g+) → thay đổi plan lần sau
-- Nếu actual rows >> estimated → CF kích hoạt, reoptimize next exec
SELECT sql_id, use_feedback_stats FROM v$sql
WHERE use_feedback_stats = 'Y';

-- Statistics Feedback (12c+) → dùng actual stats để reestimate
SELECT sql_id, is_reoptimizable FROM v$sql
WHERE is_reoptimizable = 'Y';
```

---

## 5. SQL TRACING VÀ TKPROF

### 5.1 Enable Tracing

```sql
-- Event 10046: SQL Trace với bind variables và wait events
-- Level 4 = SQL + binds, Level 8 = SQL + waits, Level 12 = SQL + binds + waits

-- Trace cho session hiện tại
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';
-- Chạy slow query...
ALTER SESSION SET EVENTS '10046 trace name context off';

-- Trace cho session khác (DBA privilege)
EXEC DBMS_MONITOR.SESSION_TRACE_ENABLE(
  session_id => 123,
  serial_num => 45678,
  waits      => TRUE,
  binds      => TRUE
);

-- Hoặc bằng ORADEBUG:
ORADEBUG SETORAPID 12345;  -- OS PID của process
ORADEBUG EVENT 10046 TRACE NAME CONTEXT FOREVER, LEVEL 12;
-- Sau khi test:
ORADEBUG EVENT 10046 TRACE NAME CONTEXT OFF;

-- Tìm trace file
SELECT value FROM v$diag_info WHERE name='Default Trace File';
-- Thường: $ORACLE_BASE/diag/rdbms/orcl/ORCL/trace/
```

### 5.2 TKPROF Analysis

```bash
# Chạy TKPROF để format trace file
tkprof \
  /u01/oracle/diag/rdbms/orcl/ORCL/trace/ORCL_ora_12345.trc \
  /tmp/output.txt \
  sort=exeela \    # Sort by elapsed time
  explain=system/"Oracle_2026!" \
  sys=no \         # Exclude SYS recursive calls
  print=20         # Top 20 SQLs

# Output TKPROF:
# call     count       cpu    elapsed       disk      query    current        rows
# ------- ------  -------- ---------- ---------- ---------- ----------  ----------
# Parse        1      0.01       0.01          0          0          0           0
# Execute      1      0.00       0.00          0          0          0           0
# Fetch      100      2.34      15.67        250     500000          0        1000
#
# Misses in library cache during parse: 1   ← Hard parse
# Parsing user id: 54 (APP_USER)
#
# Rows     Row Source Operation
# -------  ---------------------------------------------------
#    1000  TABLE ACCESS BY INDEX ROWID BATCHED ORDERS (cr=5000 pr=250 ...)
#    1000    INDEX RANGE SCAN IDX_ORDERS_DATE (cr=20 pr=0 ...)

# Sort options:
# exeela = sort by execute elapsed time
# fchela = sort by fetch elapsed time
# execpu = sort by execute CPU time
# prscnt = sort by parse count (finding hard parse issues)
```

### 5.3 SQL Monitor (12c+)

```sql
-- SQL Monitor: real-time monitoring cho long-running SQL
-- Tự động enable khi SQL > 5 giây hoặc parallel

-- Xem SQL đang được monitor
SELECT sql_id, status, sql_text,
       elapsed_time/1e6 ela_sec,
       cpu_time/1e6 cpu_sec,
       buffer_gets,
       disk_reads,
       TO_CHAR(sql_exec_start,'HH24:MI:SS') start_time
FROM v$sql_monitor
WHERE status IN ('EXECUTING','DONE','DONE (ERROR)')
ORDER BY elapsed_time DESC
FETCH FIRST 10 ROWS ONLY;

-- Xem plan với real-time statistics
SELECT dbms_sqltune.report_sql_monitor(
  sql_id     => '&sql_id',
  type       => 'TEXT',   -- TEXT | HTML | ACTIVE
  report_level => 'ALL'
) report
FROM dual;

-- HTML report (mở bằng browser, đẹp hơn)
SELECT dbms_sqltune.report_sql_monitor(
  sql_id   => '&sql_id',
  type     => 'ACTIVE'   -- Interactive HTML
) FROM dual;

-- Force monitor cho SQL
ALTER SESSION SET events '1000 trace name context forever';
-- Hoặc hint:
SELECT /*+ MONITOR */ * FROM large_table;
```

---

## 6. OPTIMIZER 10053 TRACE

```sql
-- 10053: Theo dõi quyết định của Cost-Based Optimizer
-- Dùng khi muốn hiểu TẠI SAO optimizer chọn plan đó

ALTER SESSION SET EVENTS '10053 trace name context forever, level 1';

-- Chạy query (chỉ parse, không cần execute)
EXPLAIN PLAN FOR
SELECT * FROM orders o JOIN customers c ON o.customer_id = c.customer_id
WHERE o.status = 'ACTIVE';

ALTER SESSION SET EVENTS '10053 trace name context off';

-- Đọc trace file
-- Tìm: "SINGLE TABLE ACCESS PATH", "JOIN ORDER DUMP", "BEST_PLAN"
-- Thông tin: table statistics, selectivity, costs, chosen plan
```

---

## 7. AUTOTRACE

```sql
-- AUTOTRACE: xem plan + statistics sau khi chạy SQL
-- Chỉ dùng trong SQL*Plus

-- Enable autotrace
SET AUTOTRACE ON;           -- Chạy SQL + hiện plan + stats
SET AUTOTRACE TRACEONLY;    -- Không hiện kết quả, chỉ plan + stats
SET AUTOTRACE EXPLAIN;      -- Chỉ plan, không stats
SET AUTOTRACE STATISTICS;   -- Chỉ stats, không plan
SET AUTOTRACE OFF;          -- Tắt

-- Ví dụ output statistics:
-- Statistics
-- -------------------------------------------------
-- 0  recursive calls
-- 1001  db block gets
-- 5000  consistent gets   ← Logical reads
-- 200   physical reads    ← Disk reads (nên = 0 cho hot query)
-- 0     redo size
-- 5000  bytes sent via SQL*Net to client
-- 1000  rows processed
```

---

**Tài liệu tham khảo:**
- Oracle Database SQL Tuning Guide 19c — Execution Plans
- DBMS_XPLAN Reference: docs.oracle.com
- Jonathan Lewis — Cost-Based Oracle Fundamentals
- www.tranvanbinh.vn
