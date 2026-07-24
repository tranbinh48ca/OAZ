---
name: oracle-redo-undo-archive
description: >
  Quản lý Redo Log, Undo, Archivelog và Control File Oracle.
  Kích hoạt khi hỏi về: redo log Oracle, online redo log, log switch,
  thêm redo log group, resize redo log Oracle, multiplexed redo log,
  archivelog mode Oracle, archive log Oracle, archive destination,
  archive stuck ORA-00257, archivelog gap, archive log delete,
  undo Oracle, undo retention, undo tablespace, ORA-01555 undo,
  undo_retention parameter, retention guarantee Oracle,
  control file Oracle, multiplexed control file, backup control file,
  recreate control file, controlfile to trace Oracle, SCN Oracle,
  v$log v$logfile v$archived_log v$controlfile v$database v$undostat.
---

# SK02-05 · Redo Log, Undo, Archivelog & Control File

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ONLINE REDO LOG MANAGEMENT

### 1.1 Cấu trúc và nguyên lý

```
Online Redo Log Groups (circular): 
Group 1 → Group 2 → Group 3 → Group 1 (log switch)

- Tối thiểu 2 groups (Oracle yêu cầu), khuyến nghị >= 3
- Mỗi group nên có >= 2 members (multiplexed) để redundancy
- LGWR ghi synchronously; DBWn và CKPT triggered bởi checkpoint
- ARCn copy từ INACTIVE group sang archive log

Log Switch trigger:
  - ALTER SYSTEM SWITCH LOGFILE (manual)
  - Khi group đầy (100%)
  - Checkpoint timeout
  
Size redo log groups:
  - Nhỏ quá: switch quá thường, tăng I/O cho ARCn
  - Lớn quá: crash recovery mất nhiều thời gian
  - Rule of thumb: switch không quá 10-15 lần/giờ (mỗi 4-6 phút/switch)
  - Typical size production: 200MB - 1GB per group
```

### 1.2 Xem trạng thái Redo Log

```sql
-- Xem tất cả redo log groups và status
SELECT l.group#,
       l.members,
       ROUND(l.bytes/1024/1024, 0) size_mb,
       l.status,              -- CURRENT, ACTIVE, INACTIVE, UNUSED
       l.archived,            -- YES/NO
       l.sequence#,
       TO_CHAR(l.first_time,'YYYY-MM-DD HH24:MI:SS') first_time
FROM v$log l
ORDER BY l.group#;

-- Xem file paths của redo logs
SELECT l.group#, l.status, lf.member, lf.status member_status, lf.type
FROM v$log l
JOIN v$logfile lf ON l.group# = lf.group#
ORDER BY l.group#, lf.member;

-- Log switch frequency (phân tích)
SELECT TO_CHAR(first_time,'YYYY-MM-DD HH24') hour_block,
       COUNT(*) switches_per_hour,
       ROUND(60/NULLIF(COUNT(*),0), 1) avg_minutes_between_switch
FROM v$log_history
WHERE first_time > SYSDATE - 3  -- 3 ngày gần nhất
GROUP BY TO_CHAR(first_time,'YYYY-MM-DD HH24')
ORDER BY 1 DESC;
-- Mục tiêu: switches_per_hour <= 15 (switch mỗi 4+ phút)
-- Nếu > 15: redo log size quá nhỏ, cần tăng

-- Tần suất archive log (RAC: từng thread)
SELECT thread#, sequence#,
       TO_CHAR(first_time,'HH24:MI:SS') start_time,
       TO_CHAR(next_time,'HH24:MI:SS')  end_time,
       ROUND(blocks * block_size/1024/1024, 1) size_mb
FROM v$archived_log
WHERE first_time > SYSDATE - 1/24  -- 1 giờ gần nhất
  AND dest_id = 1
ORDER BY first_time DESC;
```

### 1.3 Thêm/Xóa/Resize Redo Log Groups

```sql
-- Thêm redo log group mới
ALTER DATABASE ADD LOGFILE GROUP 4
  ('/u01/oradata/ORCL/redo04a.log',
   '/u01/oradata/ORCL/redo04b.log')   -- 2 members cho redundancy
  SIZE 500M;

-- ASM:
ALTER DATABASE ADD LOGFILE GROUP 4
  ('+DATA', '+FRA')   -- ASM tự đặt tên file
  SIZE 500M;

-- Thêm member vào group hiện có (multiplexing)
ALTER DATABASE ADD LOGFILE MEMBER
  '/u01/oradata/ORCL/redo01b.log' TO GROUP 1,
  '/u01/oradata/ORCL/redo02b.log' TO GROUP 2,
  '/u01/oradata/ORCL/redo03b.log' TO GROUP 3;

-- Xóa redo log member
ALTER DATABASE DROP LOGFILE MEMBER '/u01/oradata/ORCL/redo01_old.log';

-- Xóa redo log group (phải INACTIVE và ARCHIVED)
ALTER DATABASE DROP LOGFILE GROUP 4;
-- Nếu group đang ACTIVE: switch dFirst
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;

-- ── RESIZE REDO LOG ──────────────────────────────────────
-- Không thể resize trực tiếp → phải add mới, drop cũ

-- Bước 1: Tạo groups mới với size mới
ALTER DATABASE ADD LOGFILE GROUP 10
  ('+DATA', '+FRA') SIZE 1G;
ALTER DATABASE ADD LOGFILE GROUP 11
  ('+DATA', '+FRA') SIZE 1G;
ALTER DATABASE ADD LOGFILE GROUP 12
  ('+DATA', '+FRA') SIZE 1G;

-- Bước 2: Force log switch đến groups mới
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;
-- Lặp lại vài lần để groups cũ về INACTIVE

-- Bước 3: Kiểm tra trước khi drop
SELECT group#, status, archived FROM v$log
WHERE group# IN (1,2,3);  -- Phải INACTIVE và YES

-- Bước 4: Drop groups cũ
ALTER DATABASE DROP LOGFILE GROUP 1;
ALTER DATABASE DROP LOGFILE GROUP 2;
ALTER DATABASE DROP LOGFILE GROUP 3;

-- Bước 5: Đổi tên groups mới thành 1,2,3 (tùy chọn — Oracle không cần liên tục)
-- Không thể đổi group# trực tiếp, nhưng không cần thiết
```

---

## 2. UNDO MANAGEMENT

```sql
-- Xem undo tablespace hiện tại
SELECT name, value FROM v$parameter
WHERE name IN ('undo_tablespace','undo_retention','undo_management');

-- Phân tích undo usage (mỗi 10 phút/snapshot)
SELECT TO_CHAR(begin_time,'HH24:MI') time_slot,
       undoblks,                    -- Undo blocks used
       txncount,                    -- Transactions in period
       maxquerylen,                 -- Longest query (seconds)
       maxconcurrency,              -- Max concurrent transactions
       tuned_undoretention,         -- Oracle auto-tuned retention
       ROUND(undoblks * (
         SELECT TO_NUMBER(value) FROM v$parameter
         WHERE name='db_block_size'
       ) / 1024/1024, 2) undo_mb_used
FROM v$undostat
WHERE begin_time > SYSDATE - 1
ORDER BY begin_time DESC;

-- Tính undo size cần thiết
-- Công thức: undo_size = undo_retention * max_undo_generation_rate * block_size
-- Từ v$undostat:
SELECT ROUND(MAX(undoblks) * (SELECT TO_NUMBER(value) FROM v$parameter
             WHERE name='db_block_size') / 1024/1024, 2) || ' MB/10min'
       AS peak_undo_generation
FROM v$undostat
WHERE begin_time > SYSDATE - 7;

-- Kiểm tra ORA-01555 occurrences
SELECT COUNT(*) snapshots_too_old
FROM v$undostat
WHERE ssolderrcnt > 0
  AND begin_time > SYSDATE - 7;

-- Phòng ngừa ORA-01555:
-- 1. Tăng undo_retention
ALTER SYSTEM SET undo_retention = 7200 SCOPE=BOTH;  -- 2 giờ

-- 2. Tăng undo tablespace size
ALTER TABLESPACE UNDOTBS1
  ADD DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G;

-- 3. Enable retention guarantee (không tái dùng undo active)
ALTER TABLESPACE UNDOTBS1 RETENTION GUARANTEE;

-- Xem undo segments
SELECT usn, name, status, xacts active_txns
FROM v$rollstat rs
JOIN v$rollname rn ON rs.usn = rn.usn
ORDER BY usn;

-- Switch undo tablespace (khi cần maintenance trên UNDOTBS1)
CREATE UNDO TABLESPACE UNDOTBS2
  DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 2G;
ALTER SYSTEM SET undo_tablespace = UNDOTBS2 SCOPE=BOTH;
-- Chờ UNDOTBS1 không còn active transactions
SELECT status, COUNT(*) FROM dba_undo_extents
WHERE tablespace_name = 'UNDOTBS1'
GROUP BY status;
-- Sau khi chỉ còn EXPIRED: drop UNDOTBS1
DROP TABLESPACE UNDOTBS1 INCLUDING CONTENTS AND DATAFILES;
```

---

## 3. ARCHIVELOG MANAGEMENT

### 3.1 Bật/Tắt Archivelog Mode

```sql
-- Kiểm tra archive mode
SELECT log_mode FROM v$database;  -- ARCHIVELOG hoặc NOARCHIVELOG

-- Bật archivelog mode (cần restart DB)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- Verify
SELECT log_mode FROM v$database;          -- ARCHIVELOG
ARCHIVE LOG LIST;                          -- Xem archive settings

-- Tắt archivelog (không khuyến nghị production)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE NOARCHIVELOG;
ALTER DATABASE OPEN;
```

### 3.2 Archive Destinations

```sql
-- Xem archive destinations
SELECT dest_id, status, target, archiver, schedule,
       destination, valid_role, valid_type, error
FROM v$archive_dest
WHERE status != 'INACTIVE'
ORDER BY dest_id;

-- Cấu hình archive destinations
-- dest_1: Local archive (bắt buộc)
ALTER SYSTEM SET log_archive_dest_1 =
  'LOCATION=+FRA
   VALID_FOR=(ALL_LOGFILES,ALL_ROLES)
   DB_UNIQUE_NAME=ORCL'
  SCOPE=BOTH;

-- dest_2: Remote standby (DataGuard)
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB
   ASYNC
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=ORCL_STB'
  SCOPE=BOTH;

-- dest_3: Second local location (optional backup)
ALTER SYSTEM SET log_archive_dest_3 =
  'LOCATION=/u03/arch_backup
   VALID_FOR=(ALL_LOGFILES,ALL_ROLES)
   MANDATORY'                          -- MANDATORY = DB stop nếu không archive được
  SCOPE=BOTH;

-- Enable/Disable destinations
ALTER SYSTEM SET log_archive_dest_state_2 = ENABLE SCOPE=BOTH;
ALTER SYSTEM SET log_archive_dest_state_2 = DEFER  SCOPE=BOTH;  -- Tạm tắt

-- Format tên archive file
ALTER SYSTEM SET log_archive_format = '%d_%t_%s_%r.arc' SCOPE=SPFILE;
-- %d=DB name, %t=thread, %s=sequence, %r=resetlog id

-- Archive thủ công (test)
ALTER SYSTEM ARCHIVE LOG CURRENT;  -- Archive log hiện tại
ALTER SYSTEM ARCHIVE LOG ALL;      -- Archive tất cả unarchived logs
ALTER SYSTEM SWITCH LOGFILE;       -- Force log switch
```

### 3.3 Quản lý Archive Log Files

```bash
# Xem archive logs qua RMAN
rman target /
RMAN> LIST ARCHIVELOG ALL;
RMAN> LIST ARCHIVELOG COMPLETED BEFORE 'SYSDATE-7';

# Xóa archive logs cũ hơn 7 ngày (qua RMAN — an toàn nhất)
RMAN> DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';
# Với noprompt:
RMAN> DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';

# Script cron tự động xóa archive cũ
cat > /u01/scripts/cleanup_arch.sh << 'EOF'
#!/bin/bash
export ORACLE_SID=ORCL
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
rman target / << 'RMAN'
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-7';
EXIT;
RMAN
EOF
chmod +x /u01/scripts/cleanup_arch.sh
# Cron: 0 3 * * * oracle /u01/scripts/cleanup_arch.sh >> /var/log/rman_cleanup.log 2>&1
```

```sql
-- Xem archive logs từ SQL
SELECT sequence#, name, applied, deleted,
       ROUND(blocks * block_size/1024/1024, 1) size_mb,
       TO_CHAR(first_time,'YYYY-MM-DD HH24:MI') first_time,
       TO_CHAR(completion_time,'YYYY-MM-DD HH24:MI') completion_time
FROM v$archived_log
WHERE first_time > SYSDATE - 2
  AND dest_id = 1
  AND deleted = 'NO'
ORDER BY sequence# DESC;

-- Archive log gap (DataGuard)
SELECT thread#, low_sequence#, high_sequence# gap_size
FROM v$archive_gap;

-- FRA usage (Fast Recovery Area)
SELECT name,
       ROUND(space_limit/1024/1024/1024, 2)     limit_gb,
       ROUND(space_used/1024/1024/1024, 2)       used_gb,
       ROUND(space_reclaimable/1024/1024/1024, 2) reclaimable_gb,
       ROUND(space_used/NULLIF(space_limit,0)*100, 1) pct_used,
       number_of_files
FROM v$recovery_file_dest;
-- Nếu pct_used > 85%: cleanup hoặc tăng db_recovery_file_dest_size
ALTER SYSTEM SET db_recovery_file_dest_size = 500G SCOPE=BOTH;
```

---

## 4. CONTROL FILE MANAGEMENT

```sql
-- Xem control files
SELECT name, status, is_recovery_dest_file
FROM v$controlfile;
-- Production nên có >= 3 control files trên các disks khác nhau

-- Xem control file thông tin
SELECT value FROM v$parameter WHERE name='control_files';

-- Thêm control file (multiplexing) — cần restart
-- Bước 1: Shutdown
SHUTDOWN IMMEDIATE;

-- Bước 2: Copy control file trên OS
-- cp /u01/oradata/ORCL/control01.ctl /u02/oradata/ORCL/control03.ctl
-- Hoặc ASM: ASMCMD cp +DATA/ORCL/CONTROLFILE/current.xxx +FRA/ORCL/CONTROLFILE/

-- Bước 3: Cập nhật SPFILE
ALTER SYSTEM SET control_files =
  '/u01/oradata/ORCL/control01.ctl',
  '/u02/oradata/ORCL/control02.ctl',
  '/u03/oradata/ORCL/control03.ctl'
  SCOPE=SPFILE;

-- Bước 4: Startup
STARTUP;

-- Verify
SELECT name FROM v$controlfile;

-- Backup control file (quan trọng!)
-- Binary backup:
ALTER DATABASE BACKUP CONTROLFILE TO '/tmp/control_backup.ctl';
-- Text backup (có thể dùng để recreate):
ALTER DATABASE BACKUP CONTROLFILE TO TRACE;  -- Tạo trace file
ALTER DATABASE BACKUP CONTROLFILE TO TRACE AS '/tmp/controlfile_recreate.sql';

-- RMAN backup control file (thực hiện sau mỗi structural change):
-- RMAN> BACKUP CURRENT CONTROLFILE FORMAT '/backup/rman/ctlfile_%T.bkp';

-- Xem SCN (System Change Number) hiện tại
SELECT current_scn FROM v$database;
-- SCN dùng cho PITR và Flashback

-- Kiểm tra nội dung control file
SELECT type, record_size, records_total, records_used
FROM v$controlfile_record_section
ORDER BY type;

-- Recreate control file (khi mất tất cả control files — disaster recovery)
STARTUP NOMOUNT;
CREATE CONTROLFILE REUSE DATABASE "ORCL"
  NORESETLOGS    -- Nếu không có resetlogs cần thiết
  ARCHIVELOG
  MAXLOGFILES 32
  MAXLOGMEMBERS 3
  MAXDATAFILES 200
  MAXINSTANCES 8
  MAXLOGHISTORY 1000
  LOGFILE
    GROUP 1 ('+DATA/ORCL/ONLINELOG/group_1.log') SIZE 500M,
    GROUP 2 ('+DATA/ORCL/ONLINELOG/group_2.log') SIZE 500M,
    GROUP 3 ('+DATA/ORCL/ONLINELOG/group_3.log') SIZE 500M
  DATAFILE
    '+DATA/ORCL/DATAFILE/system.dbf',
    '+DATA/ORCL/DATAFILE/sysaux.dbf',
    '+DATA/ORCL/DATAFILE/undotbs1.dbf',
    '+DATA/ORCL/DATAFILE/users.dbf'
  CHARACTER SET AL32UTF8;
-- Sau đó:
RECOVER DATABASE;
ALTER DATABASE OPEN;
```

---

## 5. STANDBY REDO LOGS (DataGuard)

```sql
-- Standby Redo Logs cần thiết cho DataGuard real-time apply
-- Số lượng: cần nhiều hơn online redo log groups 1 (per thread)
-- Nếu có 3 online log groups → cần 4 standby redo log groups

-- Thêm Standby Redo Log groups
ALTER DATABASE ADD STANDBY LOGFILE GROUP 10
  ('+DATA', '+FRA') SIZE 500M;  -- Cùng size với online redo logs
ALTER DATABASE ADD STANDBY LOGFILE GROUP 11
  ('+DATA', '+FRA') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 12
  ('+DATA', '+FRA') SIZE 500M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 13
  ('+DATA', '+FRA') SIZE 500M;

-- Xem standby redo logs
SELECT group#, sequence#, bytes/1024/1024 size_mb, archived, status
FROM v$standby_log
ORDER BY group#;

-- Kiểm tra có SRL chưa
SELECT COUNT(*) standby_redo_groups FROM v$standby_log;
-- Phải > 0 nếu dùng DataGuard với real-time apply
```

---

**Tài liệu tham khảo:**
- Oracle Administrator's Guide 19c: Managing Redo Log Files
- Oracle Administrator's Guide 19c: Managing the Control Files
- Oracle Administrator's Guide 19c: Managing Archived Redo Log Files
- QT/DB.01 Phụ lục II.7, II.10 — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
