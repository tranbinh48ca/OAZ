---
name: oracle-common-ora-errors-troubleshooting
description: >
  Khắc phục các lỗi ORA phổ biến nhất Oracle Database.
  Kích hoạt khi hỏi về: ORA-01555 snapshot too old, ORA-04031 shared pool,
  ORA-00257 archiver error, ORA-01653 unable to extend table,
  ORA-00020 maximum processes, ORA-01000 maximum open cursors,
  ORA-01578 data block corrupted, ORA-00060 deadlock detected,
  lỗi Oracle thường gặp, khắc phục lỗi Oracle, ORA error fix,
  unable to extend tablespace Oracle, too many open cursors Oracle,
  shared pool full Oracle, undo retention error Oracle,
  archiver stuck Oracle, archive log full Oracle,
  Oracle error troubleshooting guide, fix ORA error.
---

# SK10-01 · Common ORA Errors: 01555, 04031, 00257, 01653, 00020, 01000, 01578, 00060

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ORA-01555: SNAPSHOT TOO OLD

**Triệu chứng:** `ORA-01555: snapshot too old: rollback segment number X with name "_SYSSMU.." too small`

### Root Cause
Undo data cần cho read-consistent view đã bị ghi đè (undo retention không đủ so với thời gian query chạy).

### Chẩn đoán

```sql
-- Kiểm tra undo retention hiện tại
SELECT name, value FROM v$parameter
WHERE name IN ('undo_retention','undo_tablespace','undo_management');

-- Kiểm tra undo tablespace usage
SELECT tablespace_name, ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics
WHERE tablespace_name LIKE 'UNDO%';

-- Phân tích undo statistics — tìm pattern gây lỗi
SELECT TO_CHAR(begin_time,'YYYY-MM-DD HH24:MI') time_slot,
       undoblks, maxquerylen, ssolderrcnt,
       tuned_undoretention
FROM v$undostat
WHERE ssolderrcnt > 0
ORDER BY begin_time DESC;
```

### Fix

```sql
-- Fix 1: Tăng undo_retention
ALTER SYSTEM SET undo_retention = 7200 SCOPE=BOTH;  -- 2 giờ

-- Fix 2: Tăng kích thước undo tablespace
ALTER TABLESPACE UNDOTBS1
  ADD DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G MAXSIZE 100G;

-- Fix 3: Enable retention guarantee (không tái dùng undo đang active)
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;
-- LƯU Ý: GUARANTEE có thể gây ORA-30036 (không thể extend undo)
--        nếu undo tablespace quá nhỏ cho workload

-- Fix 4 (application-level): Dùng flashback query thay vì long-running cursor
-- Hoặc: chia nhỏ query lớn thành batch nhỏ hơn (giảm query elapsed time)
```

### Phòng ngừa
- Đảm bảo `undo_retention` >= thời gian query dài nhất trong hệ thống
- Tránh long-running SELECT trên bảng có DML tần suất cao
- Dùng `DBMS_STATS` AUTO_SAMPLE_SIZE thay vì FULL scan cho bảng lớn

---

## 2. ORA-04031: UNABLE TO ALLOCATE SHARED MEMORY

**Triệu chứng:** `ORA-04031: unable to allocate 65536 bytes of shared memory ("shared pool","SQL","sga heap","KGLH0")`

### Root Cause
Shared Pool không đủ free memory để cấp phát cursor mới, thường do quá nhiều hard parses (thiếu bind variables) hoặc shared_pool_size quá nhỏ.

### Chẩn đoán

```sql
-- Shared pool free memory
SELECT name, ROUND(bytes/1024/1024,2) mb
FROM v$sgastat
WHERE pool='shared pool' AND name IN ('free memory','sql area','library cache')
ORDER BY bytes DESC;

-- Hard parse ratio (cao = nguyên nhân chính)
SELECT ROUND(
  (SELECT value FROM v$sysstat WHERE name='parse count (hard)') /
  NULLIF((SELECT value FROM v$sysstat WHERE name='parse count (total)'),0) * 100, 2
) hard_parse_pct FROM dual;

-- SQL không dùng bind variable (literal SQL)
SELECT SUBSTR(sql_text,1,60) sql_pattern, COUNT(*) cnt
FROM v$sqlarea
WHERE executions = 1
  AND last_active_time > SYSDATE - 1/24
GROUP BY SUBSTR(sql_text,1,60)
HAVING COUNT(*) > 10
ORDER BY cnt DESC;
```

### Fix

```sql
-- Fix khẩn cấp: Flush shared pool (ảnh hưởng performance tạm thời!)
ALTER SYSTEM FLUSH SHARED_POOL;

-- Fix lâu dài 1: Tăng shared_pool_size
ALTER SYSTEM SET shared_pool_size = 4G SCOPE=BOTH;

-- Fix lâu dài 2: Force cursor sharing (nếu app không dùng bind variables)
ALTER SYSTEM SET cursor_sharing = 'FORCE' SCOPE=BOTH;
-- FORCE: chuyển literal thành bind variable tự động (cẩn thận với DSS workload)

-- Fix 3: Pin packages quan trọng (tránh bị flush)
EXEC DBMS_SHARED_POOL.KEEP('SCOTT.PKG_ORDER_MGMT');

-- Fix 4: Giảm fragmentation (nếu nhiều chunks nhỏ)
SHOW PARAMETER shared_pool_reserved_size;
ALTER SYSTEM SET shared_pool_reserved_size = 200M SCOPE=BOTH;
```

---

## 3. ORA-00257: ARCHIVER ERROR

**Triệu chứng:** `ORA-00257: archiver error. Connect internal only, until freed.` — Database treo hoàn toàn, không nhận connections mới.

### Root Cause
FRA (Fast Recovery Area) hoặc archive destination đầy, ARCn process không thể ghi archived redo logs.

### Chẩn đoán

```sql
-- Kiểm tra FRA usage
SELECT name,
       ROUND(space_limit/1024/1024/1024,2) limit_gb,
       ROUND(space_used/1024/1024/1024,2)  used_gb,
       ROUND(space_used/NULLIF(space_limit,0)*100,1) pct_used
FROM v$recovery_file_dest;

-- Archive destination status
SELECT dest_id, status, error FROM v$archive_dest
WHERE status != 'INACTIVE';
```

### Fix (THỰC HIỆN NGAY KHI DB TREO)

```sql
-- Fix 1: Xóa archive log cũ qua RMAN (KHÔNG xóa file thủ công bằng OS!)
-- Kết nối: sqlplus / as sysdba (vẫn connect được dù "internal only")
rman target /
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;

-- Fix 2: Tăng FRA size ngay (nếu còn disk)
ALTER SYSTEM SET db_recovery_file_dest_size = 500G SCOPE=BOTH;

-- Fix 3: Thêm archive destination khác (disk khác)
ALTER SYSTEM SET log_archive_dest_2 = 'LOCATION=/u03/arch' SCOPE=BOTH;

-- Sau khi fix, kiểm tra DB hoạt động lại
SELECT status FROM v$instance;
ALTER SYSTEM ARCHIVE LOG CURRENT;  -- Test archive thành công
```

### Phòng ngừa

```bash
# Cron job xóa archive cũ hàng đêm
# 0 2 * * * rman target / nocatalog << 'EOF'
# DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';
# EOF

# Monitoring alert khi FRA > 80%
```

---

## 4. ORA-01653: UNABLE TO EXTEND TABLE

**Triệu chứng:** `ORA-01653: unable to extend table SCOTT.ORDERS by 128 in tablespace DATA`

### Root Cause
Tablespace hết không gian, không thể extend datafile thêm (đã đạt MAXSIZE hoặc disk hết dung lượng).

### Chẩn đoán

```sql
-- Tablespace nào đầy
SELECT tablespace_name, ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics
WHERE used_percent > 80 ORDER BY pct DESC;

-- Datafile autoextend status
SELECT file_name, tablespace_name,
       ROUND(bytes/1024/1024/1024,2) size_gb,
       autoextensible,
       ROUND(maxbytes/1024/1024/1024,2) max_gb
FROM dba_data_files WHERE tablespace_name = 'DATA';
```

### Fix

```sql
-- Fix 1: Thêm datafile mới
ALTER TABLESPACE DATA
  ADD DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 1G MAXSIZE 100G;

-- Fix 2: Resize datafile hiện có
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/data01.dbf' RESIZE 50G;

-- Fix 3: Enable autoextend nếu chưa bật
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/data01.dbf'
  AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;

-- Verify
SELECT tablespace_name, ROUND(used_percent,1) pct
FROM dba_tablespace_usage_metrics WHERE tablespace_name='DATA';
```

---

## 5. ORA-00020: MAXIMUM NUMBER OF PROCESSES EXCEEDED

**Triệu chứng:** `ORA-00020: maximum number of processes (300) exceeded`

### Chẩn đoán

```sql
SELECT COUNT(*) current_processes FROM v$process;
SELECT value max_processes FROM v$parameter WHERE name='processes';

-- Connection leak detection
SELECT username, machine, program, COUNT(*) cnt
FROM v$session WHERE type='USER' AND username IS NOT NULL
GROUP BY username, machine, program
HAVING COUNT(*) > 20 ORDER BY cnt DESC;
```

### Fix

```sql
-- Fix ngay: Kill idle sessions
SELECT 'ALTER SYSTEM KILL SESSION '''||sid||','||serial#||''' IMMEDIATE;'
FROM v$session WHERE status='INACTIVE' AND last_call_et > 3600;

-- Fix lâu dài: Tăng processes (cần restart DB)
ALTER SYSTEM SET processes = 600 SCOPE=SPFILE;
-- SHUTDOWN IMMEDIATE; STARTUP;

-- Fix triệt để: Connection pooling (DRCP)
EXEC DBMS_CONNECTION_POOL.CONFIGURE_POOL(
  pool_name => 'SYS_DEFAULT_CONNECTION_POOL',
  minsize=>10, maxsize=>100, incrsize=>5);
EXEC DBMS_CONNECTION_POOL.START_POOL;
```

---

## 6. ORA-01000: MAXIMUM OPEN CURSORS EXCEEDED

**Triệu chứng:** `ORA-01000: maximum open cursors exceeded`

### Root Cause
Application không close cursors (cursor leak), thường do thiếu `cursor.close()` trong code hoặc PL/SQL loop mở cursor không đóng.

### Chẩn đoán

```sql
SHOW PARAMETER open_cursors;

-- Sessions với nhiều open cursors nhất
SELECT s.sid, s.username, s.program, COUNT(*) open_cursors
FROM v$open_cursor s
GROUP BY s.sid, s.username, s.program
ORDER BY open_cursors DESC
FETCH FIRST 10 ROWS ONLY;

-- Chi tiết cursors của 1 session
SELECT sql_text, COUNT(*) cnt
FROM v$open_cursor
WHERE sid = &sid
GROUP BY sql_text
ORDER BY cnt DESC;
```

### Fix

```sql
-- Fix ngay: Tăng open_cursors (dynamic, không cần restart)
ALTER SYSTEM SET open_cursors = 1000 SCOPE=BOTH;

-- Fix triệt để (application code):
-- 1. Đảm bảo đóng cursor sau khi dùng (try-finally pattern)
-- 2. PL/SQL: dùng cursor FOR loop (tự động đóng) thay vì OPEN/FETCH/CLOSE thủ công
-- 3. Kiểm tra connection pool: connections không bị leak

-- Identify code pattern gây leak (PL/SQL cursor không CLOSE)
-- Review application logs/code review cần thiết
```

---

## 7. ORA-01578: ORACLE DATA BLOCK CORRUPTED

**Triệu chứng:** `ORA-01578: ORACLE data block corrupted (file # 5, block # 1234)`

### Chẩn đoán

```sql
SELECT * FROM v$database_block_corruption;
```

```bash
rman target / << 'EOF'
VALIDATE DATABASE;
VALIDATE DATAFILE 5;
EOF
```

### Fix (theo mức độ ưu tiên)

```bash
# Fix 1 (TỐT NHẤT): Block Media Recovery từ RMAN backup
rman target / << 'EOF'
BLOCKRECOVER DATAFILE 5 BLOCK 1234;
EOF

# Fix 2: Recover toàn datafile nếu nhiều blocks bị lỗi
rman target / << 'EOF'
SQL "ALTER DATABASE DATAFILE 5 OFFLINE";
RESTORE DATAFILE 5;
RECOVER DATAFILE 5;
SQL "ALTER DATABASE DATAFILE 5 ONLINE";
EOF
```

```sql
-- Fix 3 (KHẨN CẤP, KHÔNG CÓ BACKUP — rows trong block sẽ mất!)
BEGIN
  DBMS_REPAIR.FIX_CORRUPT_BLOCKS(
    schema_name  => 'SCOTT',
    object_name  => 'ORDERS',
    object_type  => DBMS_REPAIR.TABLE_OBJECT,
    repair_table_name => 'REPAIR_TABLE');
END;
/

-- Fix 4: Export data còn lại trước khi fix (backup phòng ngừa)
CREATE TABLE orders_backup AS
  SELECT /*+ ROWID(o) */ * FROM orders o
  WHERE DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID) != 1234;
```

---

## 8. ORA-00060: DEADLOCK DETECTED

**Triệu chứng:** `ORA-00060: deadlock detected while waiting for resource`

### Chẩn đoán

```bash
# Tìm deadlock trace file
find $ORACLE_BASE/diag/rdbms -name "*.trc" -newer /tmp/ref \
  -exec grep -l "deadlock" {} \;

grep -A 30 "DEADLOCK DETECTED" /path/to/trace_file.trc
```

```sql
-- Xem lock hiện tại liên quan
SELECT l1.sid sid1, l2.sid sid2,
       s1.username user1, s2.username user2,
       o.object_name
FROM v$lock l1, v$lock l2, v$session s1, v$session s2, dba_objects o
WHERE l1.block=1 AND l2.request>0
  AND l1.id1=l2.id1 AND l1.id2=l2.id2
  AND s1.sid=l1.sid AND s2.sid=l2.sid
  AND o.object_id=l1.id1;
```

### Fix
Oracle TỰ ĐỘNG kill 1 session để break deadlock (không cần DBA can thiệp ngay). Nhưng cần fix root cause ở application:

```sql
-- Verify session đã bị Oracle tự động kill
SELECT sid, serial#, status FROM v$session WHERE sid IN (&sid1, &sid2);
```

**Fix triệt để (application level):**
- Đảm bảo thứ tự truy cập tables NHẤT QUÁN trong mọi transactions (luôn lock table A trước B)
- Dùng `SELECT ... FOR UPDATE NOWAIT` để fail-fast thay vì chờ
- Giảm thời gian giữ lock, commit sớm hơn
- Review application code paths có thể gây circular wait

---

**Tài liệu tham khảo:**
- Oracle Error Messages Reference 19c (docs.oracle.com/error-help)
- MOS Note 1352144.1 (ORA-04031 Troubleshooting)
- MOS Note 33438.1 (ORA-01555 Troubleshooting)
- www.tranvanbinh.vn
