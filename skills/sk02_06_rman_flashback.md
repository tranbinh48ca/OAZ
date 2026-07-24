---
name: oracle-rman-backup-flashback
description: >
  RMAN Backup, Recovery và Flashback Technologies Oracle.
  Kích hoạt khi hỏi về: RMAN Oracle, backup Oracle, RMAN backup,
  full backup RMAN, incremental backup level 0 level 1,
  archivelog backup RMAN, controlfile backup, RMAN recovery,
  restore database RMAN, recover database, PITR Oracle,
  point-in-time recovery Oracle, RMAN catalog, recovery catalog,
  block media recovery, RMAN validate, crosscheck backup,
  delete expired backup, RMAN retention policy, FRA fast recovery area,
  flashback Oracle, flashback query, flashback table, flashback drop,
  recycle bin Oracle, flashback database, flashback transaction query,
  AS OF timestamp Oracle, versions between Oracle, DBMS_FLASHBACK.
---

# SK02-06 · RMAN Backup, Recovery & Flashback Technologies

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. RMAN FUNDAMENTALS

```bash
# Kết nối RMAN
rman target /                           # Target là local DB (ORACLE_SID)
rman target sys/pass@ORCL              # Target qua TNS
rman target sys/pass@ORCL catalog rman_cat/pass@CATDB  # Với Recovery Catalog

# Các mode kết nối
rman target / nocatalog               # Không dùng catalog (control file catalog)
```

```sql
-- RMAN Configuration (quan trọng — set một lần)
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
-- Hoặc:
CONFIGURE RETENTION POLICY TO REDUNDANCY 2;  -- Giữ 2 backup sets

CONFIGURE BACKUP OPTIMIZATION ON;           -- Skip nếu file không thay đổi
CONFIGURE COMPRESSION ALGORITHM 'HIGH';    -- BASIC | LOW | MEDIUM | HIGH
CONFIGURE DEVICE TYPE DISK PARALLELISM 4 BACKUP TYPE TO COMPRESSED BACKUPSET;
CONFIGURE CONTROLFILE AUTOBACKUP ON;       -- Tự động backup controlfile
CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '+FRA/%F';

-- Set archive log deletion policy (DataGuard)
CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY;

-- Xem cấu hình hiện tại
SHOW ALL;

-- Xem space usage
SELECT * FROM v$flash_recovery_area_usage;
```

---

## 2. BACKUP STRATEGIES

### 2.1 Full Backup

```bash
# Full backup cơ bản (script production)
rman target / << 'EOF'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_%s_%p.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_%s_%p.bkp';

  BACKUP AS COMPRESSED BACKUPSET
    TAG 'FULL_WEEKLY'
    DATABASE
    PLUS ARCHIVELOG DELETE INPUT;

  BACKUP CURRENT CONTROLFILE
    FORMAT '+FRA/ORCL/RMAN/controlfile_%T_%s.bkp';

  BACKUP SPFILE
    FORMAT '+FRA/ORCL/RMAN/spfile_%T_%s.bkp';

  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;

  DELETE NOPROMPT OBSOLETE;
}
EOF
```

### 2.2 Incremental Backup

```bash
# ── Chiến lược Incremental Strategy ──────────────────────
# Chủ nhật: Level 0 (full baseline)
# Thứ 2-7:  Level 1 (chỉ changed blocks từ Level 0 hoặc Level 1 gần nhất)

# Level 0 — Chủ nhật
rman target / << 'EOF'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_L0_%s_%p.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_L0_%s_%p.bkp';

  BACKUP INCREMENTAL LEVEL 0
    AS COMPRESSED BACKUPSET
    TAG 'INC0_SUNDAY'
    DATABASE;

  BACKUP ARCHIVELOG ALL DELETE INPUT;
  BACKUP CURRENT CONTROLFILE;
  DELETE NOPROMPT OBSOLETE;

  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}
EOF

# Level 1 — Thứ 2-7
rman target / << 'EOF'
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_L1_%s_%p.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK FORMAT '+FRA/ORCL/RMAN/%d_%T_L1_%s_%p.bkp';

  BACKUP INCREMENTAL LEVEL 1
    AS COMPRESSED BACKUPSET
    TAG 'INC1_DAILY'
    DATABASE;

  BACKUP ARCHIVELOG ALL DELETE INPUT;
  BACKUP CURRENT CONTROLFILE;

  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}
EOF

# Incremental Merge với Image Copy (Block Change Tracking)
-- Bật Block Change Tracking (Enterprise Edition)
ALTER DATABASE ENABLE BLOCK CHANGE TRACKING
  USING FILE '+DATA/ORCL/CHANGETRACKING/rman_change_track.f';

-- Kiểm tra BCT
SELECT status, filename, bytes/1024/1024 size_mb
FROM v$block_change_tracking;

-- Incremental Merge với Image Copy (không cần full backup thường xuyên)
rman target / << 'EOF'
RUN {
  RECOVER COPY OF DATABASE WITH TAG 'DAILY_COPY';  -- Merge incremental vào copy
  BACKUP INCREMENTAL LEVEL 1 FOR RECOVER OF COPY
    WITH TAG 'DAILY_COPY' DATABASE;
}
EOF
```

### 2.3 Specific Backup Types

```bash
# Backup chỉ archivelog
rman target / << 'EOF'
BACKUP ARCHIVELOG ALL
  FORMAT '+FRA/ORCL/RMAN/arch_%d_%T_%s_%p.bkp'
  DELETE INPUT;
EOF

# Backup một tablespace cụ thể
rman target / << 'EOF'
BACKUP TABLESPACE USERS, APP_DATA
  FORMAT '+FRA/ORCL/RMAN/tbs_%d_%T_%s_%p.bkp';
EOF

# Backup một datafile cụ thể
rman target / << 'EOF'
BACKUP DATAFILE 5
  FORMAT '+FRA/ORCL/RMAN/df5_%T_%s_%p.bkp';
EOF

# Backup standby controlfile (từ Primary, cho Standby setup)
rman target / << 'EOF'
BACKUP CURRENT CONTROLFILE FOR STANDBY
  FORMAT '/tmp/standby_controlfile.bkp';
EOF

# Validate backup (không ghi, chỉ kiểm tra)
rman target / << 'EOF'
BACKUP VALIDATE DATABASE;          -- Check DB có thể backup không
RESTORE DATABASE VALIDATE;        -- Check backup có thể restore không
RESTORE TABLESPACE USERS VALIDATE; -- Check từng tablespace
EOF
```

---

## 3. RECOVERY OPERATIONS

### 3.1 Complete Recovery

```bash
# Database down hoàn toàn (data files bị hỏng)
rman target / << 'EOF'
STARTUP MOUNT;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
EOF

# Restore/Recover một tablespace (DB vẫn open)
rman target / << 'EOF'
ALTER TABLESPACE USERS OFFLINE;
RESTORE TABLESPACE USERS;
RECOVER TABLESPACE USERS;
ALTER TABLESPACE USERS ONLINE;
EOF

# Restore/Recover một datafile (DB vẫn open)
rman target / << 'EOF'
SQL "ALTER DATABASE DATAFILE 5 OFFLINE";
RESTORE DATAFILE 5;
RECOVER DATAFILE 5;
SQL "ALTER DATABASE DATAFILE 5 ONLINE";
EOF
```

### 3.2 Point-in-Time Recovery (PITR)

```bash
# Recover đến một thời điểm cụ thể
rman target / << 'EOF'
STARTUP MOUNT;
SET UNTIL TIME "TO_DATE('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')";
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;  -- Bắt buộc sau PITR
EOF

# Recover đến SCN cụ thể
rman target / << 'EOF'
STARTUP MOUNT;
SET UNTIL SCN 1234567;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;
EOF

# Recover đến sequence cụ thể
rman target / << 'EOF'
STARTUP MOUNT;
SET UNTIL SEQUENCE 150 THREAD 1;
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN RESETLOGS;
EOF

# Table-level recovery (19c+ — recover chỉ một table)
rman target / << 'EOF'
RECOVER TABLE scott.orders
  UNTIL TIME "TO_DATE('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')"
  AUXILIARY DESTINATION '/tmp/table_recovery'
  DATAPUMP DESTINATION '/tmp/table_recovery_dp'
  DUMP FILE 'orders_recovery.dmp'
  NOTABLEIMPORT;                -- Chỉ export, không import tự động
-- Sau đó dùng impdp để import vào target
EOF
```

### 3.3 Block Media Recovery

```bash
# Recover từng block bị corrupt (không cần shutdown DB)
rman target / << 'EOF'
-- Xem corrupt blocks
SELECT * FROM v$database_block_corruption;

-- Recover block cụ thể
BLOCKRECOVER DATAFILE 5 BLOCK 1234;
BLOCKRECOVER DATAFILE 5 BLOCK 1234, 1235, 1236;  -- Multiple blocks

-- Recover tất cả corrupt blocks
BLOCKRECOVER CORRUPTION LIST;

-- Verify sau recovery
VALIDATE DATAFILE 5 BLOCK 1234;
EOF
```

---

## 4. BACKUP CATALOG & MAINTENANCE

```bash
# Crosscheck — verify backups còn tồn tại không
rman target / << 'EOF'
CROSSCHECK BACKUP;           -- Check tất cả
CROSSCHECK BACKUP OF DATABASE;
CROSSCHECK ARCHIVELOG ALL;
LIST EXPIRED BACKUP;         -- Backup không còn accessible
DELETE NOPROMPT EXPIRED BACKUP;  -- Xóa expired records
EOF

# Delete obsolete backups (theo retention policy)
rman target / << 'EOF'
REPORT OBSOLETE;             -- Xem trước
DELETE NOPROMPT OBSOLETE;    -- Xóa thật
EOF

# Report
rman target / << 'EOF'
LIST BACKUP SUMMARY;
LIST BACKUP OF DATABASE COMPLETED AFTER 'SYSDATE-7';
LIST ARCHIVELOG ALL COMPLETED AFTER 'SYSDATE-1';

REPORT NEED BACKUP;          -- Files cần backup
REPORT UNRECOVERABLE;        -- Files không thể recover (nologging)
REPORT SCHEMA;               -- DB schema tại thời điểm RMAN ghi
EOF
```

---

## 5. FLASHBACK TECHNOLOGIES

### 5.1 Flashback Query

```sql
-- Xem data ở quá khứ (không cần restore)
-- Điều kiện: undo còn đủ (undo_retention đủ lớn)

-- Flashback Query với AS OF TIMESTAMP
SELECT * FROM orders
AS OF TIMESTAMP SYSTIMESTAMP - INTERVAL '2' HOUR
WHERE order_id = 1234;

-- Flashback Query với AS OF SCN
SELECT current_scn FROM v$database;  -- Lấy SCN hiện tại trước
-- ... sau khi xảy ra vấn đề ...
SELECT * FROM orders
AS OF SCN 12345678
WHERE order_id = 1234;

-- Khôi phục dữ liệu bị xóa nhầm (undeletion pattern)
INSERT INTO orders
SELECT * FROM orders
AS OF TIMESTAMP TO_TIMESTAMP('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')
WHERE order_id IN (101, 102, 103);  -- Rows đã bị DELETE
COMMIT;

-- VERSIONS BETWEEN — xem tất cả versions của row
SELECT versions_starttime, versions_endtime, versions_operation,
       versions_xid, order_id, status, amount
FROM orders
VERSIONS BETWEEN TIMESTAMP
  TO_TIMESTAMP('2026-01-15 09:00:00','YYYY-MM-DD HH24:MI:SS')
  AND TO_TIMESTAMP('2026-01-15 11:00:00','YYYY-MM-DD HH24:MI:SS')
WHERE order_id = 1234;
-- versions_operation: I=Insert, U=Update, D=Delete
```

### 5.2 Flashback Table

```sql
-- Flashback Table: restore toàn bộ table về trạng thái trước đây
-- Không cần đưa DB về MOUNT mode

-- Bước 1: Enable row movement (cho phép flashback table)
ALTER TABLE orders ENABLE ROW MOVEMENT;

-- Bước 2: Flashback table về timestamp
FLASHBACK TABLE orders
TO TIMESTAMP TO_TIMESTAMP('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS');

-- Hoặc về SCN
FLASHBACK TABLE orders TO SCN 12345678;

-- Flashback nhiều tables cùng lúc
FLASHBACK TABLE orders, order_items
TO TIMESTAMP SYSTIMESTAMP - INTERVAL '1' HOUR;

-- Sau khi flashback, disable row movement lại nếu cần
ALTER TABLE orders DISABLE ROW MOVEMENT;

-- Lưu ý:
-- Flashback Table không restore DDL changes (ALTER TABLE ADD COLUMN...)
-- Flashback Table không hoạt động nếu PURGE đã xảy ra
-- Nếu không có đủ undo → lỗi ORA-01555
```

### 5.3 Flashback Drop (Recycle Bin)

```sql
-- Khi DROP TABLE, Oracle chuyển vào Recycle Bin (không xóa ngay)
DROP TABLE orders;

-- Xem Recycle Bin
SELECT object_name,        -- Tên original
       original_name,      -- Object name trong recycle bin
       type,
       droptime,
       can_undrop,
       space
FROM recyclebin;

-- Restore table từ Recycle Bin
FLASHBACK TABLE orders TO BEFORE DROP;

-- Restore và đổi tên (khi bị conflict)
FLASHBACK TABLE "BIN$AbCdEf...==$0" TO BEFORE DROP
  RENAME TO orders_recovered;

-- Purge một object khỏi Recycle Bin (không thể recover nữa)
PURGE TABLE orders;

-- Purge toàn bộ Recycle Bin của user hiện tại
PURGE RECYCLEBIN;

-- Purge toàn bộ Recycle Bin (DBA)
PURGE DBA RECYCLEBIN;

-- Purge Recycle Bin của tablespace
PURGE TABLESPACE app_data;

-- DROP TABLE và bỏ qua Recycle Bin hoàn toàn
DROP TABLE orders PURGE;  -- Không thể recover!

-- Tắt Recycle Bin (không khuyến nghị)
ALTER SESSION SET recyclebin = OFF;
ALTER SYSTEM SET recyclebin = OFF SCOPE=BOTH;  -- Tắt cho toàn DB
```

### 5.4 Flashback Database

```sql
-- Flashback Database: đưa toàn bộ DB về thời điểm trước
-- Yêu cầu: ARCHIVELOG mode + Flashback Logging bật

-- Bật Flashback Logging
ALTER DATABASE FLASHBACK ON;

-- Kiểm tra
SELECT flashback_on, oldest_flashback_time, oldest_flashback_scn
FROM v$database;

-- Cấu hình Flashback Retention
ALTER SYSTEM SET db_flashback_retention_target = 2880 SCOPE=BOTH;
-- 2880 phút = 48 giờ giữ flashback log

-- Xem flashback log usage
SELECT * FROM v$flashback_database_log;

-- Thực hiện Flashback Database (cần MOUNT mode)
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;

-- Flashback đến timestamp
FLASHBACK DATABASE
TO TIMESTAMP TO_TIMESTAMP('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS');

-- Hoặc đến SCN
FLASHBACK DATABASE TO SCN 12345678;

-- Sau khi flashback:
-- Option 1: Mở với RESETLOGS (timeline mới, không thể apply redo sau thời điểm đó)
ALTER DATABASE OPEN RESETLOGS;

-- Option 2: Mở READ ONLY để verify trước
ALTER DATABASE OPEN READ ONLY;
-- Xem data để verify...
-- Nếu đúng:
SHUTDOWN;
STARTUP MOUNT;
ALTER DATABASE OPEN RESETLOGS;
-- Nếu sai (cần đi tiếp theo timeline):
ALTER DATABASE RECOVER TO BEFORE RESETLOGS;  -- Undo flashback
ALTER DATABASE OPEN;
```

### 5.5 Flashback Transaction Query

```sql
-- Xem chi tiết transaction (DML) đã xảy ra
SELECT xid,
       start_timestamp,
       commit_timestamp,
       logon_user,
       undo_sql                    -- SQL để undo thay đổi đó
FROM flashback_transaction_query
WHERE table_name = 'ORDERS'
  AND table_owner = 'SCOTT'
  AND start_timestamp > SYSTIMESTAMP - INTERVAL '2' HOUR
ORDER BY start_timestamp DESC;

-- Áp dụng undo_sql để khôi phục
-- Ví dụ undo_sql: "INSERT INTO SCOTT.ORDERS VALUES(1234, ...)"
-- (Cho row bị DELETE)

-- DBMS_FLASHBACK package
-- Bật flashback context (cho session)
EXEC DBMS_FLASHBACK.ENABLE_AT_TIME(SYSTIMESTAMP - INTERVAL '1' HOUR);
SELECT * FROM orders WHERE order_id = 1234;  -- Thấy data 1 giờ trước
EXEC DBMS_FLASHBACK.DISABLE;

-- Lấy SCN tại thời điểm cụ thể
SELECT DBMS_FLASHBACK.GET_SYSTEM_CHANGE_NUMBER scn_now FROM dual;
SELECT TIMESTAMP_TO_SCN(
  TO_TIMESTAMP('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')
) scn_at_time FROM dual;
SELECT SCN_TO_TIMESTAMP(12345678) time_at_scn FROM dual;
```

---

## 6. RMAN BEST PRACTICES CHECKLIST

```bash
# 1. Kiểm tra backup hàng ngày (vào script monitoring)
rman target / << 'EOF'
LIST BACKUP OF DATABASE COMPLETED AFTER 'SYSDATE-2';
REPORT NEED BACKUP DAYS 2;
EOF

# 2. Verify backup hàng tuần
rman target / << 'EOF'
RESTORE DATABASE VALIDATE;
EOF

# 3. Test restore hàng tháng (trên server khác hoặc environment test)
rman target sys/pass@PROD auxiliary sys/pass@TEST << 'EOF'
DUPLICATE TARGET DATABASE TO test_db
  FROM ACTIVE DATABASE
  SPFILE
    PARAMETER_VALUE_CONVERT 'ORCL','TEST_DB'
    SET DB_UNIQUE_NAME='TEST_DB'
  NOFILENAMECHECK;
EOF

# 4. Alert khi backup fail (script monitoring)
# Check v$rman_backup_job_details hoặc alert log
```

```sql
-- Xem backup history
SELECT input_type,
       status,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time,
       TO_CHAR(end_time,'YYYY-MM-DD HH24:MI')   end_time,
       ROUND(input_bytes/1024/1024/1024, 2)  input_gb,
       ROUND(output_bytes/1024/1024/1024, 2) output_gb,
       ROUND(compression_ratio, 2)           compress_ratio,
       time_taken_display elapsed
FROM v$rman_backup_job_details
WHERE start_time > SYSDATE - 14
ORDER BY start_time DESC;

-- Alert nếu backup không thành công trong 24h
SELECT COUNT(*) no_successful_backup
FROM v$rman_backup_job_details
WHERE status = 'COMPLETED'
  AND input_type = 'DB FULL'
  AND start_time > SYSDATE - 1;
-- Nếu = 0: chưa có backup thành công
```

---

**Tài liệu tham khảo:**
- Oracle Backup and Recovery User's Guide 19c
- Oracle Database Backup and Recovery Reference 19c
- QT/DB.01 Phụ lục II.2 — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
