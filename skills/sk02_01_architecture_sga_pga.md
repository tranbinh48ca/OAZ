---
name: oracle-architecture-sga-pga
description: >
  Kiến trúc Oracle Database: SGA, PGA, background processes, memory structures.
  Kích hoạt khi hỏi về: kiến trúc Oracle, Oracle architecture, SGA, PGA,
  shared pool, buffer cache, large pool, java pool, redo log buffer,
  PGA aggregate target, work area memory, ASMM AMM, automatic memory management,
  background process Oracle, DBWn LGWR CKPT SMON PMON ARCn MMON,
  Oracle instance vs database, data dictionary, control file, datafile,
  Oracle memory components, SGA target, memory_target Oracle,
  v$sga v$sgastat v$pga_target_advice, resize SGA PGA Oracle.
---

# SK02-01 · Kiến trúc Oracle Database: SGA, PGA & Memory

**Phạm vi:** Oracle 11g, 12c, 19c, 21c, 23ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. TỔNG QUAN KIẾN TRÚC

```
┌─────────────────────────────────────────────────────────┐
│                    ORACLE INSTANCE                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │                      SGA                         │  │
│  │  ┌────────────┐ ┌──────────┐ ┌───────────────┐  │  │
│  │  │Buffer Cache│ │Shared    │ │Redo Log Buffer│  │  │
│  │  │(DB Cache)  │ │Pool      │ │               │  │  │
│  │  ├────────────┤ ├──────────┤ ├───────────────┤  │  │
│  │  │Large Pool  │ │Java Pool │ │Streams Pool   │  │  │
│  │  └────────────┘ └──────────┘ └───────────────┘  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  Background Processes: DBWn LGWR CKPT SMON PMON ARCn... │
└─────────────────────────────────────────────────────────┘
               │                        │
               ▼                        ▼
        ┌─────────┐              ┌─────────────┐
        │  PGA    │              │  DATABASE   │
        │(per     │              │ ┌─Control   │
        │session) │              │ ├─Datafiles │
        └─────────┘              │ └─Redo Logs │
                                 └─────────────┘
```

---

## 2. SGA — SYSTEM GLOBAL AREA

### 2.1 Buffer Cache

```sql
-- Buffer Cache: lưu data blocks từ datafiles (hot cache)
-- Mục tiêu: Buffer Cache Hit Ratio >= 95%

-- Xem buffer cache size hiện tại
SELECT component, current_size/1024/1024/1024 current_gb,
       min_size/1024/1024/1024 min_gb,
       max_size/1024/1024/1024 max_gb
FROM v$sga_dynamic_components
WHERE component = 'DEFAULT buffer cache';

-- Hit ratio
SELECT ROUND(
  (1 - phys_reads/(db_blk_gets + consist_gets)) * 100, 2
) hit_ratio_pct
FROM (
  SELECT SUM(value) phys_reads  FROM v$sysstat WHERE name='physical reads cache'
), (
  SELECT SUM(value) db_blk_gets FROM v$sysstat WHERE name='db block gets'
), (
  SELECT SUM(value) consist_gets FROM v$sysstat WHERE name='consistent gets'
);

-- Advice: nên tăng buffer cache lên bao nhiêu?
SELECT size_for_estimate size_mb,
       buffers_for_estimate,
       ROUND(estd_physical_read_factor, 2) io_factor,
       estd_physical_reads
FROM v$db_cache_advice
WHERE name = 'DEFAULT' AND block_size = (
  SELECT value FROM v$parameter WHERE name = 'db_block_size'
)
ORDER BY size_for_estimate;
-- io_factor < 1: tăng cache sẽ giảm I/O
-- io_factor = 1: kích thước hiện tại OK

-- Multiple buffer pools
-- KEEP pool: giữ "nóng" objects thường dùng
ALTER TABLE hr.lookup_codes STORAGE (BUFFER_POOL KEEP);
-- RECYCLE pool: dùng cho full table scan lớn, không giữ lại
ALTER TABLE dwh.fact_sales STORAGE (BUFFER_POOL RECYCLE);
```

### 2.2 Shared Pool

```sql
-- Shared Pool gồm: Library Cache + Data Dictionary Cache
-- Library Cache: lưu parsed SQL, PL/SQL code
-- Dictionary Cache: lưu metadata từ data dictionary

-- Xem shared pool breakdown
SELECT name, ROUND(bytes/1024/1024, 2) mb
FROM v$sgastat
WHERE pool = 'shared pool'
ORDER BY bytes DESC
FETCH FIRST 15 ROWS ONLY;

-- Library Cache Hit Ratio (mục tiêu >= 99%)
SELECT ROUND(SUM(pinhits)/SUM(pins)*100, 2) lib_cache_hit_pct
FROM v$librarycache;

-- Shared Pool Free (cần giữ > 5-10%)
SELECT ROUND(bytes/1024/1024, 2) free_mb
FROM v$sgastat
WHERE pool = 'shared pool' AND name = 'free memory';

-- Hard parse count (cao = Shared Pool bị áp lực)
SELECT name, value
FROM v$sysstat
WHERE name IN (
  'parse count (total)',
  'parse count (hard)',
  'parse count (failures)'
);

-- Xem SQL đang chiếm Shared Pool nhiều nhất
SELECT sql_id, sharable_mem/1024/1024 mb,
       executions, loads,
       SUBSTR(sql_text, 1, 80) sql_preview
FROM v$sqlarea
ORDER BY sharable_mem DESC
FETCH FIRST 10 ROWS ONLY;

-- Pin object vào Shared Pool (không bị flush)
EXEC DBMS_SHARED_POOL.KEEP('SCOTT.PKG_ORDER_MGMT', 'P');
EXEC DBMS_SHARED_POOL.UNKEEP('SCOTT.PKG_ORDER_MGMT', 'P');
-- Types: 'P'=Package, 'Q'=Sequence, 'R'=Trigger, 'T'=Type, 'C'=Cursor

-- Xem objects đã pinned
SELECT owner, name, namespace, kept
FROM v$db_object_cache
WHERE kept = 'YES';
```

### 2.3 Redo Log Buffer

```sql
-- Redo Log Buffer: circular buffer lưu redo entries trước khi LGWR ghi
-- Nếu buffer đầy → log buffer space wait event

-- Kiểm tra Redo Log Buffer size
SELECT name, value/1024/1024 mb
FROM v$parameter
WHERE name = 'log_buffer';

-- Log buffer space waits (cao = cần tăng log_buffer)
SELECT total_waits, time_waited_micro/1000000 time_sec
FROM v$system_event
WHERE event = 'log buffer space';

-- Điều chỉnh (thường 32MB-128MB đủ)
ALTER SYSTEM SET log_buffer = 67108864 SCOPE=SPFILE;
-- Cần restart DB để có hiệu lực

-- Redo generation rate
SELECT ROUND(value/1024/1024, 2) redo_mb_per_call
FROM v$sysstat
WHERE name = 'redo size';
```

### 2.4 Large Pool, Java Pool, Streams Pool

```sql
-- Large Pool: dùng cho RMAN I/O slaves, MTS, parallel query
SELECT ROUND(current_size/1024/1024, 2) mb
FROM v$sga_dynamic_components
WHERE component = 'large pool';

-- Nếu RMAN backup chậm do "resmgr: cpu quantum" wait:
ALTER SYSTEM SET large_pool_size = 512M SCOPE=BOTH;

-- Java Pool: chỉ cần khi dùng Java trong DB (Oracle JVM)
SELECT ROUND(current_size/1024/1024, 2) mb
FROM v$sga_dynamic_components
WHERE component = 'java pool';

-- Streams Pool (GoldenGate Integrated Extract dùng)
SELECT ROUND(current_size/1024/1024, 2) mb
FROM v$sga_dynamic_components
WHERE component = 'streams pool';
-- GoldenGate cần >= 1GB Streams Pool
ALTER SYSTEM SET streams_pool_size = 1G SCOPE=BOTH;
```

---

## 3. PGA — PROGRAM GLOBAL AREA

```sql
-- PGA: private memory cho mỗi server process
-- Dùng cho: sort operations, hash joins, bitmap operations, PL/SQL arrays

-- Xem PGA stats
SELECT name, ROUND(value/1024/1024, 2) mb
FROM v$pgastat
WHERE name IN (
  'total PGA inuse',
  'total PGA allocated',
  'maximum PGA allocated',
  'total PGA used for auto workareas',
  'over allocation count',    -- > 0 = PGA_AGGREGATE_TARGET quá nhỏ
  'bytes processed',
  'extra bytes read/written'  -- > 0 = sort spilled to disk
);

-- PGA Advice
SELECT ROUND(pga_target_for_estimate/1024/1024/1024, 2) target_gb,
       estd_pga_cache_hit_percentage hit_pct,
       estd_overalloc_count
FROM v$pga_target_advice
ORDER BY pga_target_for_estimate;
-- Tìm điểm mà hit_pct đạt 100% và không có overalloc

-- Adjust PGA target
ALTER SYSTEM SET pga_aggregate_target = 4G SCOPE=BOTH;

-- PGA hard limit (19c+)
ALTER SYSTEM SET pga_aggregate_limit = 8G SCOPE=BOTH;

-- Workarea per operation type
SELECT operation_type,
       COUNT(*) operations,
       ROUND(SUM(actual_mem_used)/1024/1024, 2) mem_mb,
       SUM(CASE WHEN policy = 'MANUAL' THEN 1 ELSE 0 END) manual_ops,
       SUM(number_passes) disk_passes   -- > 0 = spill to disk
FROM v$sql_workarea_active
GROUP BY operation_type;
```

---

## 4. AUTOMATIC MEMORY MANAGEMENT (AMM/ASMM)

```sql
-- Ba chế độ quản lý memory:
-- 1. MANUAL: DBA set từng component thủ công
-- 2. ASMM (Automatic Shared Memory Management): tự điều chỉnh SGA components
-- 3. AMM (Automatic Memory Management): tự điều chỉnh cả SGA + PGA

-- Xem chế độ hiện tại
SELECT name, value
FROM v$parameter
WHERE name IN (
  'memory_target',        -- AMM: > 0 = AMM enabled
  'memory_max_target',
  'sga_target',           -- ASMM: > 0 = ASMM enabled
  'sga_max_size',
  'pga_aggregate_target'
);

-- ASMM (khuyến dùng cho production với HugePages)
-- HugePages KHÔNG dùng được với AMM!
ALTER SYSTEM SET sga_target          = 16G SCOPE=BOTH;
ALTER SYSTEM SET pga_aggregate_target = 4G SCOPE=BOTH;
-- Tắt AMM:
ALTER SYSTEM SET memory_target = 0 SCOPE=SPFILE;

-- AMM (thuận tiện nhưng không dùng với HugePages)
ALTER SYSTEM SET memory_target     = 20G SCOPE=BOTH;
ALTER SYSTEM SET memory_max_target = 24G SCOPE=SPFILE;

-- Xem SGA tổng hiện tại
SELECT ROUND(SUM(value)/1024/1024/1024, 2) total_sga_gb
FROM v$sga;

-- Chi tiết SGA components
SELECT component,
       ROUND(current_size/1024/1024/1024, 3) current_gb,
       ROUND(min_size/1024/1024/1024, 3) min_gb,
       ROUND(max_size/1024/1024/1024, 3) max_gb,
       last_oper_type,
       last_oper_time
FROM v$sga_dynamic_components
ORDER BY current_size DESC;
```

---

## 5. BACKGROUND PROCESSES

```sql
-- Xem tất cả background processes đang chạy
SELECT name, description, error_number, pmon_status
FROM v$bgprocess
WHERE paddr != '00'
ORDER BY name;

-- Chi tiết từng process quan trọng:

/*
DBWn (Database Writer):  Ghi dirty blocks từ Buffer Cache → Datafiles
  - Trigger: checkpoint, dirty buffers > threshold, no free buffers
  - Tuning: db_writer_processes = số CPU cores / 8 (tối thiểu 1)

LGWR (Log Writer): Ghi Redo Log Buffer → Online Redo Logs
  - Trigger: commit, 1/3 buffer đầy, mỗi 3 giây
  - Critical: bottleneck của log file sync wait

CKPT (Checkpoint): Ghi checkpoint info → Control files, Datafiles
  - Fast commit writes checkpoint SCN

SMON (System Monitor): Recovery sau crash, coalesces free extents
PMON (Process Monitor): Cleanup failed user processes, deregisters listeners
MMON (Memory Monitor): AWR snapshots, ADDM alerts
ARCn (Archiver): Copy online redo logs → archive log destinations
RECO (Recoverer): Resolve distributed transactions

Thêm 19c+:
AQPC (AQ Process Coordinator)
CJQ0 (Job Queue Coordinator)
FBDA (Flashback Data Archiver)
DBRM (Database Resource Manager)
*/

-- Xem database writer processes
SHOW PARAMETER db_writer_processes;

-- Kiểm tra DBWn đang bận không (write time cao)
SELECT ROUND(single_blk_rds_latency, 2) read_ms,
       ROUND(dbwr_ios, 0) write_ops
FROM v$filestat fs
JOIN v$datafile df ON fs.file# = df.file#
WHERE ROWNUM <= 5
ORDER BY dbwr_ios DESC;

-- Số archiver processes
SHOW PARAMETER log_archive_max_processes;
ALTER SYSTEM SET log_archive_max_processes = 4 SCOPE=BOTH;
```

---

## 6. ORACLE DATABASE vs INSTANCE

```sql
-- Instance: memory (SGA) + processes → có thể có nhiều instances / 1 DB (RAC)
-- Database: tập hợp files (datafiles, redo logs, control files)

-- Phân biệt:
SELECT i.instance_name,  -- Tên instance (ORACLE_SID)
       i.host_name,
       i.status,          -- OPEN, MOUNTED, STARTED
       d.name,            -- Tên database (DB_NAME)
       d.db_unique_name,
       d.open_mode,       -- READ WRITE, READ ONLY WITH APPLY
       d.log_mode,        -- ARCHIVELOG, NOARCHIVELOG
       d.cdb              -- YES nếu là Container Database
FROM v$instance i, v$database d;

-- Control files
SELECT name, status FROM v$controlfile;

-- Datafiles
SELECT file#, name, status, ROUND(bytes/1024/1024/1024, 2) size_gb
FROM v$datafile ORDER BY file#;

-- Online Redo Logs
SELECT l.group#, l.members, l.bytes/1024/1024 size_mb, l.status,
       lf.member log_file_path
FROM v$log l JOIN v$logfile lf ON l.group# = lf.group#
ORDER BY l.group#;
```

---

## 7. PARAMETER MANAGEMENT

```sql
-- Phân loại parameters:
-- Static: chỉ có hiệu lực sau khi restart (scope=SPFILE)
-- Dynamic: có hiệu lực ngay (scope=BOTH hoặc scope=MEMORY)
-- Session-level: chỉ ảnh hưởng session hiện tại

-- Xem parameter và scope
SELECT name, value, isses_modifiable, issys_modifiable,
       isinstance_modifiable, description
FROM v$parameter
WHERE name IN ('sga_target','pga_aggregate_target','processes',
               'open_cursors','cursor_sharing','db_cache_size')
ORDER BY name;
-- isses_modifiable: Y = ALTER SESSION có thể thay
-- issys_modifiable: IMMEDIATE = ngay lập tức, DEFERRED = session mới, FALSE = phải restart

-- Thay đổi dynamic parameter
ALTER SYSTEM SET open_cursors = 500 SCOPE=BOTH;
ALTER SESSION SET nls_date_format = 'YYYY-MM-DD HH24:MI:SS';

-- Thay đổi static (cần restart)
ALTER SYSTEM SET processes = 600 SCOPE=SPFILE;

-- Reset parameter về default
ALTER SYSTEM RESET cursor_sharing SCOPE=BOTH SID='*';

-- Backup và restore SPFILE
CREATE PFILE='/tmp/initORCL_backup.ora' FROM SPFILE;
CREATE SPFILE FROM PFILE='/tmp/initORCL_backup.ora';

-- Xem SPFILE location
SELECT value FROM v$parameter WHERE name='spfile';

-- Hidden parameters (cần cẩn thận, chỉ thay khi có chỉ định từ Oracle Support)
SELECT ksppinm name, ksppstvl value, ksppdesc description
FROM x$ksppi x, x$ksppcv y
WHERE x.indx = y.indx
  AND ksppinm LIKE '%&parameter_name%';
```

---

## 8. DATA DICTIONARY

```sql
-- Ba tầng data dictionary views:
-- DBA_: tất cả objects trong DB (cần DBA privilege)
-- ALL_: objects mà user hiện tại có quyền truy cập
-- USER_: objects thuộc user hiện tại

-- Dynamic performance views (V$):
-- Tồn tại trong memory, mất khi DB restart

-- Static data dictionary views quan trọng
SELECT 'DBA_OBJECTS: ' || COUNT(*) FROM dba_objects;
SELECT 'DBA_TABLES: '  || COUNT(*) FROM dba_tables;
SELECT 'DBA_INDEXES: ' || COUNT(*) FROM dba_indexes;
SELECT 'DBA_USERS: '   || COUNT(*) FROM dba_users;

-- Xem tất cả V$ views
SELECT view_name FROM v$fixed_view_definition ORDER BY view_name;

-- Xem nội dung data dictionary
SELECT table_name, comments
FROM dictionary
WHERE table_name LIKE 'DBA_TAB%'
ORDER BY table_name;

-- Xem các thống kê cần biết
SELECT * FROM v$version;
SELECT * FROM v$option WHERE value = 'TRUE';  -- Features enabled
SELECT * FROM v$license;                       -- License limits
```

---

**Tài liệu tham khảo:**
- Oracle Database Concepts 19c — docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/
- Oracle Memory Architecture: docs.oracle.com/en/database/oracle/oracle-database/19/cncpt/memory-architecture.html
- www.tranvanbinh.vn
