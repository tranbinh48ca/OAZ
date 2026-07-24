---
name: oracle-tablespace-asm
description: >
  Quản lý Tablespace, Datafile và ASM Diskgroup Oracle.
  Kích hoạt khi hỏi về: tablespace Oracle, datafile, tạo tablespace,
  thêm datafile, mở rộng tablespace, autoextend Oracle, tablespace full,
  bigfile tablespace, smallfile tablespace, undo tablespace, temp tablespace,
  SYSAUX tablespace, SYSTEM tablespace, drop tablespace, transport tablespace,
  ASM Oracle, Automatic Storage Management, diskgroup Oracle,
  v$asm_diskgroup, asmcmd, ASMCA, create diskgroup, add disk ASM,
  remove disk ASM, rebalance ASM, ASM redundancy normal external high,
  ASM metadata backup, ACFS, ASM filter driver, v$asm_disk.
---

# SK02-03 · Quản lý Tablespace, Datafile & ASM

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. TABLESPACE FUNDAMENTALS

```sql
-- Phân loại tablespace theo mục đích:
-- SYSTEM:   Data dictionary (DBA không nên store data ở đây)
-- SYSAUX:   Auxiliary system data (AWR, Optimizer, etc.)
-- UNDO:     Undo segments cho MVCC
-- TEMP:     Sort, hash operations, global temp tables
-- USERS:    Default cho user data (đổi tên theo project)
-- Tự tạo:  APP_DATA, APP_INDX, APP_LOB, HIST_DATA, etc.

-- Phân loại theo cấu trúc lưu trữ:
-- Smallfile: nhiều datafiles (default, max 1022 datafiles/tablespace)
-- Bigfile:   1 datafile duy nhất nhưng rất lớn (tốt cho ASM, VLDB)

-- Xem tất cả tablespaces
SELECT t.tablespace_name,
       t.contents,           -- PERMANENT, TEMPORARY, UNDO
       t.status,             -- ONLINE, OFFLINE, READ ONLY
       t.bigfile,            -- YES/NO
       t.extent_management,  -- LOCAL/DICTIONARY
       t.segment_space_management  -- AUTO/MANUAL
FROM dba_tablespaces t
ORDER BY t.tablespace_name;

-- Xem usage đầy đủ (production health check hàng ngày)
SELECT ts.tablespace_name,
       ts.contents,
       ROUND(f.total_mb, 2)                    total_mb,
       ROUND(f.total_mb - NVL(fr.free_mb,0), 2) used_mb,
       ROUND(NVL(fr.free_mb,0), 2)              free_mb,
       ROUND((1 - NVL(fr.free_mb,0)/NULLIF(f.total_mb,0))*100, 1) pct_used,
       CASE
         WHEN (1-NVL(fr.free_mb,0)/NULLIF(f.total_mb,0))*100 >= 90 THEN '🔴 CRITICAL'
         WHEN (1-NVL(fr.free_mb,0)/NULLIF(f.total_mb,0))*100 >= 80 THEN '🟡 WARNING'
         ELSE '🟢 OK'
       END status_flag
FROM dba_tablespaces ts
LEFT JOIN (
  SELECT tablespace_name, SUM(bytes)/1024/1024 total_mb
  FROM dba_data_files GROUP BY tablespace_name
  UNION ALL
  SELECT tablespace_name, SUM(bytes)/1024/1024
  FROM dba_temp_files GROUP BY tablespace_name
) f ON ts.tablespace_name = f.tablespace_name
LEFT JOIN (
  SELECT tablespace_name, SUM(bytes)/1024/1024 free_mb
  FROM dba_free_space GROUP BY tablespace_name
) fr ON ts.tablespace_name = fr.tablespace_name
ORDER BY pct_used DESC NULLS LAST;
```

---

## 2. TẠO VÀ QUẢN LÝ TABLESPACE

### 2.1 Tạo Tablespace

```sql
-- Permanent tablespace trên filesystem
CREATE TABLESPACE APP_DATA
  DATAFILE '/u01/oradata/ORCL/app_data01.dbf' SIZE 10G
  AUTOEXTEND ON NEXT 1G MAXSIZE 100G
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  SEGMENT SPACE MANAGEMENT AUTO
  LOGGING;                          -- NOLOGGING cho DWH bulk load

-- Permanent tablespace trên ASM (khuyến dùng production)
CREATE TABLESPACE APP_DATA
  DATAFILE '+DATA'               -- ASM tự đặt tên file
    SIZE 10G AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED
  EXTENT MANAGEMENT LOCAL AUTOALLOCATE
  SEGMENT SPACE MANAGEMENT AUTO;

-- Bigfile tablespace (cho single large file, tốt cho ASM)
CREATE BIGFILE TABLESPACE APP_DATA_BIG
  DATAFILE '+DATA' SIZE 100G
  AUTOEXTEND ON NEXT 10G MAXSIZE UNLIMITED;

-- Tablespace cho INDEX (nên tách riêng khỏi DATA)
CREATE TABLESPACE APP_INDX
  DATAFILE '+DATA' SIZE 5G AUTOEXTEND ON NEXT 512M MAXSIZE 50G;

-- Tablespace cho LOB (CLOB/BLOB)
CREATE TABLESPACE APP_LOB
  DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G MAXSIZE UNLIMITED;

-- Temporary tablespace
CREATE TEMPORARY TABLESPACE TEMP2
  TEMPFILE '+DATA' SIZE 10G AUTOEXTEND ON NEXT 1G MAXSIZE 50G
  EXTENT MANAGEMENT LOCAL UNIFORM SIZE 1M;

-- Tạo temporary tablespace group (19c, nhiều temp tablespaces)
CREATE TEMPORARY TABLESPACE TEMP3
  TEMPFILE '+DATA' SIZE 5G
  TABLESPACE GROUP TEMP_GROUP;
ALTER TABLESPACE TEMP2 TABLESPACE GROUP TEMP_GROUP;

-- UNDO tablespace
CREATE UNDO TABLESPACE UNDOTBS2
  DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G MAXSIZE 200G
  RETENTION GUARANTEE;  -- Đảm bảo không ghi đè undo đang cần
```

### 2.2 Alter Tablespace

```sql
-- Thêm datafile vào tablespace hiện có
ALTER TABLESPACE APP_DATA
  ADD DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G MAXSIZE UNLIMITED;

-- Thêm tempfile vào temp tablespace
ALTER TABLESPACE TEMP
  ADD TEMPFILE '+DATA' SIZE 10G AUTOEXTEND ON NEXT 1G;

-- Resize datafile (tăng hoặc giảm — giảm phải free space đủ)
ALTER DATABASE DATAFILE '/u01/oradata/ORCL/app_data01.dbf' RESIZE 50G;
-- ASM:
ALTER DATABASE DATAFILE '+DATA/ORCL/DATAFILE/app_data.265.1234567890' RESIZE 50G;

-- Enable autoextend cho datafile hiện có
ALTER DATABASE DATAFILE '+DATA/ORCL/DATAFILE/app_data.265.1234567890'
  AUTOEXTEND ON NEXT 2G MAXSIZE UNLIMITED;

-- Offline/Online tablespace (không dùng SYSTEM, UNDO, TEMP)
ALTER TABLESPACE APP_DATA_OLD OFFLINE;
ALTER TABLESPACE APP_DATA_OLD ONLINE;

-- Read-only tablespace (historical data, đỡ backup overhead)
ALTER TABLESPACE HIST_2023 READ ONLY;
ALTER TABLESPACE HIST_2023 READ WRITE;  -- Quay lại

-- Rename tablespace
ALTER TABLESPACE APP_DATA RENAME TO APP_DATA_V2;

-- Drop tablespace (CẨN THẬN!)
DROP TABLESPACE APP_DATA_OLD
  INCLUDING CONTENTS      -- Xóa tất cả segments
  AND DATAFILES           -- Xóa cả file vật lý
  CASCADE CONSTRAINTS;    -- Xóa cả foreign key references

-- Move datafile (12c+ — không cần offline)
ALTER DATABASE MOVE DATAFILE
  '/u01/oradata/ORCL/app_data01.dbf'
  TO '+DATA_NEW';
-- Hoặc rename (đổi ASM alias):
ALTER DATABASE RENAME FILE
  '+DATA/ORCL/DATAFILE/app_data.265.1234567890'
  TO '+DATA_NEW/ORCL/DATAFILE/app_data.265.1234567890';
```

### 2.3 Default Tablespace cho User

```sql
-- Xem default tablespace của users
SELECT username, default_tablespace, temporary_tablespace
FROM dba_users
WHERE username NOT IN ('SYS','SYSTEM','DBSNMP')
ORDER BY username;

-- Thay đổi default tablespace
ALTER USER app_user DEFAULT TABLESPACE APP_DATA;
ALTER USER app_user TEMPORARY TABLESPACE TEMP;

-- Quota trên tablespace
ALTER USER app_user QUOTA 10G ON APP_DATA;
ALTER USER app_user QUOTA UNLIMITED ON APP_INDX;
ALTER USER app_user QUOTA 0 ON SYSTEM;  -- Không cho dùng SYSTEM

-- Xem quota
SELECT username, tablespace_name,
       ROUND(bytes/1024/1024/1024, 2) used_gb,
       DECODE(max_bytes, -1, 'UNLIMITED',
              ROUND(max_bytes/1024/1024/1024, 2)) max_gb
FROM dba_ts_quotas
WHERE username = 'APP_USER';
```

---

## 3. UNDO & TEMP MANAGEMENT

### 3.1 Undo Tablespace

```sql
-- Undo retention (giây) — ảnh hưởng đến ORA-01555
SHOW PARAMETER undo_retention;
ALTER SYSTEM SET undo_retention = 3600 SCOPE=BOTH;  -- 1 giờ

-- Undo tablespace hiện tại
SHOW PARAMETER undo_tablespace;
ALTER SYSTEM SET undo_tablespace = UNDOTBS2 SCOPE=BOTH;

-- Phân tích undo usage
SELECT TO_CHAR(begin_time,'HH24:MI') time_slot,
       undoblks undo_blocks,
       maxquerylen max_query_sec,
       tuned_undoretention tuned_retention,
       ROUND(undoblks * 8192 / 1024 / 1024, 2) undo_mb_used
FROM v$undostat
WHERE begin_time > SYSDATE - 1
ORDER BY begin_time DESC
FETCH FIRST 24 ROWS ONLY;

-- Tính toán undo size cần thiết
-- Công thức: undo_size = undo_retention * undo_blocks_per_sec * block_size
-- Xem undo_blocks_per_sec từ v$undostat

-- Retention guarantee (không ghi đè undo active)
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;    -- Bật
ALTER TABLESPACE UNDOTBS1 RETENTION NOGUARANTEE;  -- Tắt (mặc định)
```

### 3.2 Temp Tablespace

```sql
-- Xem temp usage real-time
SELECT ts.name tablespace_name,
       ROUND(SUM(tu.blocks * ts.block_size)/1024/1024, 2) used_mb,
       ROUND(ts.bytes/1024/1024, 2) total_mb,
       ROUND(SUM(tu.blocks * ts.block_size)/ts.bytes*100, 1) pct_used
FROM v$tempseg_usage tu
JOIN v$tablespace ts ON tu.tablespace = ts.name
GROUP BY ts.name, ts.bytes;

-- Session đang dùng temp nhiều nhất
SELECT s.sid, s.serial#, s.username, s.program,
       ROUND(SUM(tu.blocks * b.block_size)/1024/1024, 2) temp_mb,
       s.sql_id
FROM v$tempseg_usage tu
JOIN v$session s ON tu.session_addr = s.saddr
JOIN (SELECT value block_size FROM v$parameter WHERE name='db_block_size') b ON 1=1
GROUP BY s.sid, s.serial#, s.username, s.program, s.sql_id
ORDER BY temp_mb DESC;

-- Shrink temp tablespace (không có dữ liệu nào đang dùng)
ALTER TABLESPACE TEMP SHRINK SPACE KEEP 5G;
ALTER TABLESPACE TEMP SHRINK TEMPFILE '/u01/oradata/ORCL/temp01.dbf' KEEP 5G;

-- Tạo default temp tablespace group cho tất cả users
ALTER DATABASE DEFAULT TEMPORARY TABLESPACE TEMP_GROUP;
```

---

## 4. ASM — AUTOMATIC STORAGE MANAGEMENT

### 4.1 Kết nối và cơ bản

```bash
# Kết nối ASM instance
export ORACLE_SID=+ASM
sqlplus / as sysasm

# Hoặc dùng ASMCMD
asmcmd
```

```sql
-- Xem diskgroups
SELECT name,
       state,                    -- MOUNTED, DISMOUNTED
       type,                     -- EXTERN, NORMAL, HIGH
       ROUND(total_mb/1024, 2)   total_gb,
       ROUND(free_mb/1024, 2)    free_gb,
       ROUND((total_mb-free_mb)/1024, 2) used_gb,
       ROUND((1-free_mb/NULLIF(total_mb,0))*100, 1) pct_used,
       offline_disks,
       voting_files
FROM v$asm_diskgroup
ORDER BY name;

-- Xem disks trong diskgroup
SELECT dg.name diskgroup,
       d.disk_number,
       d.name disk_name,
       d.path,                   -- OS path của disk
       d.mode_status,            -- ONLINE, OFFLINE, DROPPED
       d.state,                  -- NORMAL, ADDING, DROPPING, etc.
       ROUND(d.total_mb/1024, 2) total_gb,
       ROUND(d.free_mb/1024, 2)  free_gb,
       ROUND(d.reads/1e6, 2)     reads_M,
       ROUND(d.writes/1e6, 2)    writes_M,
       ROUND(d.read_time/NULLIF(d.reads,0)*1000, 3)  avg_read_ms,
       ROUND(d.write_time/NULLIF(d.writes,0)*1000, 3) avg_write_ms
FROM v$asm_diskgroup dg
JOIN v$asm_disk d ON dg.group_number = d.group_number
ORDER BY dg.name, d.disk_number;

-- Xem files trong ASM diskgroup
SELECT dg.name diskgroup,
       f.name, f.type,
       ROUND(f.bytes/1024/1024/1024, 2) size_gb
FROM v$asm_diskgroup dg
JOIN v$asm_file f ON dg.group_number = f.group_number
WHERE dg.name = 'DATA'
ORDER BY f.bytes DESC;
```

### 4.2 Tạo và quản lý Diskgroup

```sql
-- Tạo diskgroup mới (từ ASM instance)
-- EXTERNAL: không có mirroring (dùng storage-level RAID)
CREATE DISKGROUP DATA EXTERNAL REDUNDANCY
  DISK '/dev/DATA1', '/dev/DATA2', '/dev/DATA3'
  ATTRIBUTE 'compatible.asm'    = '19.0',
            'compatible.rdbms'  = '19.0',
            'cell.smart_scan_capable' = 'FALSE',
            'au_size' = '4M';  -- Allocation Unit Size: 1M,2M,4M,8M,16M,32M,64M

-- NORMAL: 2-way mirroring (cần ít nhất 2 failure groups)
CREATE DISKGROUP DATA NORMAL REDUNDANCY
  FAILGROUP fg1 DISK '/dev/DATA1', '/dev/DATA2'
  FAILGROUP fg2 DISK '/dev/DATA3', '/dev/DATA4'
  ATTRIBUTE 'compatible.asm' = '19.0',
            'au_size' = '4M';

-- HIGH: 3-way mirroring (cần ít nhất 3 failure groups)
CREATE DISKGROUP REDO HIGH REDUNDANCY
  FAILGROUP fg1 DISK '/dev/REDO1'
  FAILGROUP fg2 DISK '/dev/REDO2'
  FAILGROUP fg3 DISK '/dev/REDO3'
  ATTRIBUTE 'compatible.asm' = '19.0';

-- Mount/Dismount diskgroup
ALTER DISKGROUP DATA MOUNT;      -- Mount (tự động khi ASM start)
ALTER DISKGROUP DATA DISMOUNT;   -- Dismount (không dùng khi DB đang chạy)

-- Drop diskgroup (CẨN THẬN!)
DROP DISKGROUP DATA
  INCLUDING CONTENTS;  -- Xóa tất cả files

-- Đổi tên diskgroup (12c+)
ALTER DISKGROUP DATA RENAME TO DATA_NEW;
```

### 4.3 Add/Remove Disk

```bash
# Bước 1: Kiểm tra disk mới trên OS
ls -la /dev/oracleasm/disks/     # Nếu dùng oracleasm
ls -la /dev/sd*                  # Block devices
lsblk

# Bước 2: Label disk cho ASM (nếu dùng oracleasm)
/usr/sbin/oracleasm createdisk DATA4 /dev/sde1
/usr/sbin/oracleasm listdisks

# Hoặc dùng udev rules (khuyến dùng)
# /etc/udev/rules.d/99-oracle-asm.rules
```

```sql
-- Bước 3: Add disk vào diskgroup hiện có
ALTER DISKGROUP DATA ADD DISK
  '/dev/DATA4' NAME DATA4;

-- Add với failure group (cho NORMAL/HIGH redundancy)
ALTER DISKGROUP DATA ADD
  FAILGROUP fg1 DISK '/dev/DATA5' NAME DATA5,
  FAILGROUP fg2 DISK '/dev/DATA6' NAME DATA6;

-- Kiểm tra rebalance progress
SELECT group_number, operation, state, power,
       sofar, est_work, est_rate, est_minutes
FROM v$asm_operation;
-- est_minutes: ước tính thời gian còn lại

-- Điều chỉnh rebalance power (1-1024, mặc định 1)
ALTER DISKGROUP DATA REBALANCE POWER 4;

-- Drop disk (ASM tự migrate data sang disks khác)
ALTER DISKGROUP DATA DROP DISK DATA1;
-- Kiểm tra migration xong chưa
SELECT * FROM v$asm_operation WHERE group_number = (
  SELECT group_number FROM v$asm_diskgroup WHERE name='DATA');

-- Drop disk ngay (không migrate, mất dữ liệu nếu không redundancy)
ALTER DISKGROUP DATA DROP DISK DATA1 FORCE;
```

### 4.4 ASMCMD Commands

```bash
# Kết nối ASMCMD
asmcmd [-p]  # -p hiện path đầy đủ

# Navigation
asmcmd> lsdg              # List diskgroups
asmcmd> lsdsk             # List disks
asmcmd> ls                # List files ở root
asmcmd> ls +DATA          # List files trong diskgroup
asmcmd> ls -l +DATA/ORCL/ # List với details
asmcmd> cd +DATA/ORCL
asmcmd> pwd

# File operations
asmcmd> cp +DATA/ORCL/DATAFILE/app_data.265.xxx /tmp/   # Copy ra filesystem
asmcmd> cp /tmp/app_data.265.xxx +DATA/ORCL/DATAFILE/   # Copy vào ASM
asmcmd> rm +DATA/ORCL/DATAFILE/temp_backup.xxx          # Xóa file

# Diskgroup operations
asmcmd> du +DATA            # Disk usage của diskgroup
asmcmd> du +DATA/ORCL/      # Disk usage của DB

# Disk management
asmcmd> lsdsk -G DATA       # List disks trong diskgroup DATA
asmcmd> lsdsk --candidate   # List candidate disks (chưa trong diskgroup)

# Metadata backup/restore
asmcmd> md_backup -g DATA -b /tmp/asm_metadata_DATA.bkp   # Backup metadata
asmcmd> md_restore -b /tmp/asm_metadata_DATA.bkp \
         -g 'old:DATA,new:DATA' -t full \                  # Restore metadata
         -p '+DATA'

# Kiểm tra ASM file type
asmcmd> spbackup +DATA/ORCL/PARAMETERFILE/spfile.289.xxx /tmp/spfileORCL.ora
asmcmd> spset /tmp/spfileORCL.ora  # Set spfile location

# Scrub (check và repair files trong ASM — Enterprise Edition)
asmcmd> scrub -g DATA -r           # Recursive scrub
asmcmd> scrub +DATA/ORCL/DATAFILE/system.xxx
```

### 4.5 ASM Alert và Monitoring

```bash
# ASM alert log
adrci
adrci> show homes
adrci> set home grid/client/+ASM   # Hoặc tìm ASM home
adrci> show alert -tail 50

# Kiểm tra ASM errors
tail -100 $ORACLE_BASE/diag/asm/+asm/+ASM/trace/alert_+ASM.log | \
  grep -E "ORA-|Error|error"

# ASMCA — ASM Configuration Assistant (GUI)
asmca
```

```sql
-- Alert nếu diskgroup sắp đầy
SELECT name,
       ROUND((1-free_mb/NULLIF(total_mb,0))*100, 1) pct_used,
       ROUND(free_mb/1024, 2) free_gb
FROM v$asm_diskgroup
WHERE (1-free_mb/NULLIF(total_mb,0))*100 >= 70  -- Alert ngưỡng 70%
ORDER BY pct_used DESC;

-- Monitor rebalance
SELECT dg.name diskgroup_name,
       op.operation,
       op.state,
       op.power,
       op.sofar,
       op.est_work,
       op.est_minutes
FROM v$asm_operation op
JOIN v$asm_diskgroup dg ON op.group_number = dg.group_number;

-- ASM Client databases
SELECT db.db_name, cl.instance_name, cl.db_version
FROM v$asm_client cl
JOIN v$asm_disk_stat ds ON cl.group_number = ds.group_number
GROUP BY cl.db_name, cl.instance_name, cl.db_version;
```

---

## 5. TRANSPORTABLE TABLESPACE (TTS)

```sql
-- Export tablespace để chuyển sang DB khác (cross-platform)
-- Bước 1: Kiểm tra compatibility
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('APP_DATA,APP_INDX', TRUE);
SELECT * FROM transport_set_violations;  -- Phải rỗng

-- Bước 2: Make tablespace READ ONLY
ALTER TABLESPACE APP_DATA READ ONLY;
ALTER TABLESPACE APP_INDX READ ONLY;

-- Bước 3: Export metadata
expdp system/pass \
  TRANSPORT_TABLESPACES=APP_DATA,APP_INDX \
  TRANSPORT_FULL_CHECK=Y \
  DUMPFILE=tts_export.dmp \
  DIRECTORY=DATA_PUMP_DIR \
  LOGFILE=tts_export.log

-- Bước 4: Copy datafiles + dumpfile sang target server

-- Bước 5: Import trên target
impdp system/pass \
  DUMPFILE=tts_export.dmp \
  DIRECTORY=DATA_PUMP_DIR \
  TRANSPORT_DATAFILES='/u01/oradata/target/app_data01.dbf',
                      '/u01/oradata/target/app_indx01.dbf' \
  LOGFILE=tts_import.log

-- Bước 6: Make tablespace READ WRITE trên cả source và target
ALTER TABLESPACE APP_DATA READ WRITE;  -- Source
ALTER TABLESPACE APP_INDX READ WRITE;  -- Source
-- (Target tự động READ WRITE sau import)
```

---

**Tài liệu tham khảo:**
- Oracle Administrator's Guide 19c — Tablespace Management
- Oracle ASM Administrator's Guide 19c
- QT/DB.01 Phụ lục II.4 — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
