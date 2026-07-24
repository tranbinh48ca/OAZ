---
name: oracle-troubleshoot-database-administration
description: >
  100 case study khắc phục lỗi Quản trị Oracle Database: Tablespace, ASM,
  Undo, Redo, Archive, RMAN Backup/Recovery, Session/Lock, CDB/PDB, Scheduler.
  Kích hoạt khi hỏi về: lỗi tablespace Oracle, ASM diskgroup error,
  ORA-01652 unable to extend, ORA-01115 ASM error, undo tablespace error,
  redo log error Oracle, archivelog error, RMAN backup error advanced,
  RMAN recovery error, session lock error Oracle, CDB PDB error,
  ORA-65040 PDB error, scheduler job error Oracle, DBMS_SCHEDULER failed,
  flashback error Oracle, control file error Oracle, datafile error.
---

# SK10-CASE-02 · Troubleshooting: Quản trị Oracle Database

**Phạm vi:** Tablespace, ASM, Undo/Redo, RMAN, Session/Lock, CDB/PDB, Scheduler  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Số lượng case:** 100 cases thực chiến

---

## KIẾN TRÚC TỔNG QUAN ĐIỂM LỖI TRONG QUẢN TRỊ

```
Oracle Database Administration — Failure Points Map
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────────┐
│                  INSTANCE LAYER                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐              │
│  │   SGA    │  │ Sessions │  │Background│   Group A     │
│  │  Memory  │  │  & Locks │  │Processes │   (1-15)      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘              │
└───────┼─────────────┼─────────────┼──────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼──────────────────────┐
│                  STORAGE LAYER                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │Tablespace│  │   ASM    │  │  Undo/   │   Group B-D   │
│  │ Datafile │  │Diskgroup │  │  Redo    │   (16-50)     │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
└───────┼─────────────┼─────────────┼──────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼──────────────────────┐
│              BACKUP & RECOVERY LAYER                       │
│  ┌──────────────────────────────────┐    Group E         │
│  │     RMAN Backup / Restore /       │    (51-70)         │
│  │     Recovery / Flashback          │                    │
│  └──────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────┘
        │
┌───────▼─────────────────────────────────────────────────┐
│           MULTITENANT & AUTOMATION LAYER                  │
│  ┌──────────┐         ┌──────────┐    Group F-G          │
│  │ CDB/PDB  │         │Scheduler │    (71-100)            │
│  └──────────┘         └──────────┘                        │
└─────────────────────────────────────────────────────────┘

Severity: 🔴 BLOCKING (DB down/inoperable) | 🟡 DEGRADED | 🟢 COSMETIC
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## NHÓM A: INSTANCE / SESSION / LOCK (Case 1-15)

### Case 1: ORA-00018 — maximum number of sessions exceeded

```
🔴 BLOCKING | Instance level

Triệu chứng: Không thể tạo session mới
```

```sql
SHOW PARAMETER sessions;
SELECT COUNT(*) FROM v$session;
-- Fix khẩn cấp: kill idle sessions
SELECT 'ALTER SYSTEM KILL SESSION '''||sid||','||serial#||''' IMMEDIATE;'
FROM v$session WHERE status='INACTIVE' AND last_call_et>3600;
-- Fix lâu dài
ALTER SYSTEM SET sessions=500 SCOPE=SPFILE;  -- cần restart
```

### Case 2: ORA-00604 — error occurred at recursive SQL level

```
🟡 DEGRADED | Recursive SQL failure

Triệu chứng: Lỗi xảy ra trong quá trình Oracle tự thực thi SQL nội bộ
```

```sql
-- Xem error gốc (thường ẩn phía dưới)
-- Common cause: SYSTEM/SYSAUX tablespace đầy, hoặc data dictionary corrupt
SELECT tablespace_name, used_percent FROM dba_tablespace_usage_metrics
WHERE tablespace_name IN ('SYSTEM','SYSAUX');
ALTER TABLESPACE SYSAUX ADD DATAFILE '+DATA' SIZE 5G AUTOEXTEND ON;
```

### Case 3: ORA-00031 — session marked for kill (treo)

```
🟡 DEGRADED | Session stuck in killing state

Triệu chứng: Session đã KILL nhưng vẫn còn trong v$session
```

```sql
SELECT sid, serial#, status, username FROM v$session WHERE status='KILLED';
-- Tìm OS process tương ứng
SELECT p.spid, s.sid FROM v$process p, v$session s
WHERE p.addr=s.paddr AND s.sid=&sid;
```

```bash
# Kill OS process trực tiếp nếu Oracle không tự dọn
kill -9 <spid>
```

### Case 4: ORA-00054 — resource busy and acquire with NOWAIT

```
🟡 DEGRADED | DDL blocked bởi DML

Triệu chứng: ALTER TABLE/DROP fail vì có session đang dùng table
```

```sql
SELECT s.sid, s.serial#, s.username, o.object_name
FROM v$locked_object lo, v$session s, dba_objects o
WHERE lo.session_id=s.sid AND lo.object_id=o.object_id
  AND o.object_name='ORDERS';
-- Kill session đang giữ lock hoặc đợi commit
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;
```

### Case 5: ORA-00031 + ORA-25402 (session khó kill trên RAC)

```
🟡 DEGRADED | RAC — Cross-instance session kill

Triệu chứng: Session ở instance khác không kill được bằng cú pháp thường
```

```sql
-- Cú pháp đúng cho RAC: thêm @instance_id
ALTER SYSTEM KILL SESSION '&sid,&serial#,@&inst_id' IMMEDIATE;
```

### Case 6: ORA-04021 — timeout occurred while waiting to lock object

```
🟡 DEGRADED | DDL timeout do lock contention

Triệu chứng: ALTER/DROP timeout khi object đang bị lock lâu
```

```sql
-- Tìm session block
SELECT blocking_session, sid FROM v$session WHERE blocking_session IS NOT NULL;
-- Tăng DDL_LOCK_TIMEOUT để tránh fail ngay
ALTER SESSION SET ddl_lock_timeout=60;  -- Chờ 60s thay vì fail ngay
```

### Case 7: ORA-01089 — immediate shutdown in progress

```
🟡 DEGRADED | Connection attempt during shutdown

Triệu chứng: Không kết nối được vì DB đang shutdown
```

```bash
# Đợi shutdown hoàn tất rồi startup lại
ps -ef | grep pmon
sqlplus / as sysdba << 'EOF'
STARTUP;
EOF
```

### Case 8: ORA-04025 — maximum allowed library object size exceeded

```
🟡 DEGRADED | Library cache — PL/SQL object quá lớn

Triệu chứng: Package/procedure quá lớn không load được
```

```sql
-- Fix: chia nhỏ package thành nhiều packages
-- Hoặc tăng shared_pool_size
ALTER SYSTEM SET shared_pool_size=6G SCOPE=BOTH;
```

### Case 9: ORA-04068 — existing state of packages has been discarded

```
🟢 COSMETIC | Package state reset (thường do DDL trên package)

Triệu chứng: Session state bị mất sau khi package được recompile
```

```sql
-- Thường tự fix khi reconnect, hoặc:
ALTER SESSION SET plsql_optimize_level=2;  -- Recompile lại nếu cần
EXEC DBMS_UTILITY.COMPILE_SCHEMA('SCOTT');
```

### Case 10: ORA-08177 — cannot serialize access for this transaction

```
🟡 DEGRADED | SERIALIZABLE isolation conflict

Triệu chứng: Transaction conflict ở mức SERIALIZABLE isolation
```

```sql
-- Application cần retry logic cho lỗi này (expected behavior)
-- Hoặc giảm isolation level nếu không cần SERIALIZABLE
ALTER SESSION SET isolation_level=READ COMMITTED;
```

### Case 11: ORA-25408 — can not safely replay call

```
🟡 DEGRADED | TAF replay fail

Triệu chứng: TAF (Transparent Application Failover) không replay được transaction
```

```sql
-- Application cần handle: transaction có thể chưa hoàn thành sau failover
-- Verify state và retry transaction từ application logic
```

### Case 12: ORA-00257 archiver hung — affecting all sessions

```
🔴 BLOCKING | Archive log full ảnh hưởng toàn instance

Triệu chứng: Tất cả connections mới bị từ chối (xem chi tiết SK10-01)
```

```bash
rman target / << 'EOF'
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
EOF
```

### Case 13: ORA-12805 — parallel query server died unexpectedly

```
🟡 DEGRADED | Parallel Execution failure

Triệu chứng: Parallel query bị fail giữa chừng
```

```sql
SELECT * FROM v$px_session;
-- Check PX servers available
SHOW PARAMETER parallel_max_servers;
ALTER SYSTEM SET parallel_max_servers=128 SCOPE=BOTH;
```

### Case 14: ORA-27102 — out of memory (instance startup)

```
🔴 BLOCKING | Instance không startup được — Memory

Triệu chứng: STARTUP fail vì không đủ memory cho SGA
```

```bash
free -g
cat /proc/meminfo | grep HugePages

# Fix: giảm SGA hoặc tăng HugePages/RAM
sqlplus / as sysdba << 'EOF'
ALTER SYSTEM SET sga_max_size=8G SCOPE=SPFILE;
ALTER SYSTEM SET sga_target=8G SCOPE=SPFILE;
EOF
```

### Case 15: ORA-00845 — MEMORY_TARGET not supported (instance start)

```
🔴 BLOCKING | AMM conflict with HugePages

Triệu chứng: STARTUP fail do MEMORY_TARGET không tương thích
```

```bash
# Fix: chuyển sang ASMM (không dùng AMM khi có HugePages)
sqlplus / as sysdba << 'EOF'
ALTER SYSTEM SET memory_target=0 SCOPE=SPFILE;
ALTER SYSTEM SET sga_target=8G SCOPE=SPFILE;
ALTER SYSTEM SET pga_aggregate_target=2G SCOPE=SPFILE;
EOF
```

---

## NHÓM B: TABLESPACE & DATAFILE (Case 16-30)

### Case 16: ORA-01652 — unable to extend temp segment

```
🔴 BLOCKING | TEMP tablespace full

Triệu chứng: Sort/hash operation fail vì TEMP đầy
```

```sql
SELECT tablespace_name, used_percent FROM dba_tablespace_usage_metrics
WHERE tablespace_name LIKE 'TEMP%';
ALTER TABLESPACE TEMP ADD TEMPFILE '+DATA' SIZE 10G AUTOEXTEND ON;
```

### Case 17: ORA-01536 — space quota exceeded for tablespace

```
🟡 DEGRADED | User quota limit

Triệu chứng: User đạt giới hạn quota dù tablespace còn trống
```

```sql
SELECT username, tablespace_name, max_bytes FROM dba_ts_quotas
WHERE username='APP_USER';
ALTER USER app_user QUOTA UNLIMITED ON APP_DATA;
```

### Case 18: ORA-01691 — unable to extend lob segment

```
🔴 BLOCKING | LOB segment tablespace full

Triệu chứng: Insert/update LOB column fail
```

```sql
SELECT segment_name, tablespace_name FROM dba_lobs WHERE table_name='DOCUMENTS';
ALTER TABLESPACE LOB_TBS ADD DATAFILE '+DATA' SIZE 10G AUTOEXTEND ON;
```

### Case 19: ORA-01658 — unable to create INITIAL extent

```
🔴 BLOCKING | Tablespace không đủ contiguous space

Triệu chứng: CREATE TABLE/INDEX fail dù tablespace tổng còn trống
```

```sql
-- Fix: thêm datafile mới (fragmentation issue)
ALTER TABLESPACE DATA ADD DATAFILE '+DATA' SIZE 5G;
```

### Case 20: ORA-03113 sau ALTER DATABASE DATAFILE RESIZE

```
🔴 BLOCKING | Connection lost during resize

Triệu chứng: Mất kết nối khi đang resize datafile lớn
```

```sql
-- Verify resize đã hoàn thành dù connection mất
SELECT file_name, bytes/1024/1024/1024 gb FROM dba_data_files
WHERE file_name LIKE '%data01%';
-- Thường resize vẫn thành công ở background, chỉ session bị disconnect
```

### Case 21: ORA-01110 — data file: error reading file header

```
🔴 BLOCKING | Datafile header corrupt/inaccessible

Triệu chứng: Datafile không đọc được header
```

```bash
# Kiểm tra file tồn tại và permissions
ls -la /u01/oradata/ORCL/data01.dbf
# ASM:
asmcmd ls +DATA/ORCL/DATAFILE/
```

```sql
-- Nếu file mất, restore từ RMAN backup
-- rman target / <<'EOF'
-- RESTORE DATAFILE 5;
-- RECOVER DATAFILE 5;
-- EOF
```

### Case 22: ORA-01116 — error in opening database file

```
🔴 BLOCKING | Datafile missing hoặc permission sai

Triệu chứng: Database không OPEN được do datafile lỗi
```

```bash
# Kiểm tra OS permissions
ls -la /u01/oradata/ORCL/*.dbf
chown oracle:oinstall /u01/oradata/ORCL/*.dbf
chmod 660 /u01/oradata/ORCL/*.dbf
```

### Case 23: ORA-01122 — database file is not identified

```
🔴 BLOCKING | Controlfile/datafile mismatch

Triệu chứng: Controlfile không nhận diện đúng datafile
```

```sql
-- Kiểm tra checksum/SCN mismatch
SELECT file#, checkpoint_change# FROM v$datafile_header;
SELECT file#, checkpoint_change# FROM v$datafile;
-- Thường cần RECOVER hoặc restore controlfile đúng version
```

### Case 24: ORA-01157 — cannot identify datafile (RAC node-specific)

```
🔴 BLOCKING | RAC — Path khác nhau giữa nodes

Triệu chứng: Datafile path không nhất quán giữa các instances RAC
```

```bash
# Đảm bảo ASM diskgroup mounted đồng nhất trên TẤT CẢ nodes
ssh node1 'asmcmd lsdg'
ssh node2 'asmcmd lsdg'
```

### Case 25: ORA-01237 — cannot extend datafile (OS limit)

```
🟡 DEGRADED | OS file size limit reached

Triệu chứng: Datafile không extend được dù tablespace setting cho phép
```

```bash
# Kiểm tra OS file size limits
ulimit -f
# Filesystem limits (ví dụ ext3 giới hạn 2TB/file với block size nhỏ)
df -T /u01/oradata
# Fix: dùng filesystem hỗ trợ large files (ext4, xfs) hoặc thêm datafile mới
```

### Case 26: ORA-19502 — write error on file (write failed)

```
🔴 BLOCKING | I/O error khi ghi datafile

Triệu chứng: Write fail, thường do disk lỗi hoặc storage issue
```

```bash
# Kiểm tra dmesg cho I/O errors
dmesg | grep -E "I/O error|sd[a-z]"
smartctl -a /dev/sdb  # SMART status nếu local disk
```

### Case 27: ORA-25153 — temporary tablespace empty

```
🟡 DEGRADED | TEMP tablespace chưa có tempfile

Triệu chứng: TEMP tablespace tồn tại nhưng không có tempfile
```

```sql
SELECT tablespace_name, file_name FROM dba_temp_files;
ALTER TABLESPACE TEMP ADD TEMPFILE '+DATA' SIZE 5G AUTOEXTEND ON;
```

### Case 28: ORA-30036 — unable to extend UNDO segment (RETENTION GUARANTEE)

```
🔴 BLOCKING | Undo tablespace với GUARANTEE quá nhỏ

Triệu chứng: DML fail vì undo guarantee không đủ space
```

```sql
SELECT tablespace_name, retention FROM dba_tablespaces WHERE contents='UNDO';
-- Fix khẩn cấp: tắt guarantee tạm thời
ALTER TABLESPACE UNDOTBS1 RETENTION NOGUARANTEE;
-- Fix lâu dài: tăng undo size
ALTER TABLESPACE UNDOTBS1 ADD DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON;
```

### Case 29: Datafile autoextend không hoạt động dù đã enable

```
🟡 DEGRADED | Autoextend bị giới hạn bởi MAXSIZE

Triệu chứng: ORA-01653 dù autoextensible=YES
```

```sql
SELECT file_name, bytes, maxbytes, autoextensible
FROM dba_data_files WHERE tablespace_name='DATA';
-- Nếu bytes gần bằng maxbytes:
ALTER DATABASE DATAFILE '+DATA/data01.dbf'
  AUTOEXTEND ON NEXT 1G MAXSIZE UNLIMITED;
```

### Case 30: Bigfile tablespace — không thể add thêm datafile thứ 2

```
🟢 COSMETIC | Hiểu nhầm về Bigfile design

Triệu chứng: ALTER TABLESPACE ADD DATAFILE fail trên Bigfile TBS
```

```sql
-- Đây là DESIGN của Bigfile (1 tablespace = đúng 1 datafile)
-- Fix: resize datafile hiện có thay vì add mới
ALTER DATABASE DATAFILE '+DATA' RESIZE 200G;
-- Hoặc tạo thêm 1 bigfile tablespace mới
CREATE BIGFILE TABLESPACE data2 DATAFILE '+DATA' SIZE 100G;
```

---

## NHÓM C: ASM (Case 31-40)

### Case 31: ORA-15041 — diskgroup space exhausted

```
🔴 BLOCKING | ASM diskgroup full

Triệu chứng: Không thể tạo/extend file trong ASM
```

```sql
SELECT name, free_mb, total_mb FROM v$asm_diskgroup WHERE name='DATA';
-- Fix: add disk mới
ALTER DISKGROUP DATA ADD DISK '/dev/DATA_NEW' NAME DATA_NEW;
```

### Case 32: ORA-15032/ORA-15067 — disk add fails diskgroup full redundancy mismatch

```
🟡 DEGRADED | Mismatched redundancy khi add disk

Triệu chứng: Add disk vào diskgroup NORMAL/HIGH redundancy fail
```

```sql
-- Cần add đủ disks cho từng failure group khi NORMAL/HIGH redundancy
ALTER DISKGROUP DATA ADD
  FAILGROUP fg1 DISK '/dev/DATA5'
  FAILGROUP fg2 DISK '/dev/DATA6';
```

### Case 33: ORA-15196 — invalid ASM block header

```
🔴 BLOCKING | ASM metadata corruption

Triệu chứng: ASM không đọc được block, nghi corrupt
```

```bash
# Cần Oracle Support hỗ trợ nếu nghiêm trọng
# Đầu tiên thử mount lại diskgroup
sqlplus / as sysasm << 'EOF'
ALTER DISKGROUP DATA DISMOUNT;
ALTER DISKGROUP DATA MOUNT;
EOF
```

### Case 34: ORA-15042 — ASM disk is missing

```
🔴 BLOCKING | Physical disk không accessible

Triệu chứng: ASM báo disk mất, diskgroup có thể OFFLINE
```

```bash
# Kiểm tra disk có visible từ OS không
ls -la /dev/DATA*
multipath -ll  # Nếu dùng multipath

# Nếu disk thực sự mất và còn redundancy, ASM tự rebalance
SELECT name, state FROM v$asm_diskgroup;
SELECT name, mode_status, state FROM v$asm_disk WHERE group_number=(
  SELECT group_number FROM v$asm_diskgroup WHERE name='DATA');
```

### Case 35: ORA-15410 — disk too small for diskgroup compatibility

```
🟡 DEGRADED | Disk size không đủ cho metadata mới

Triệu chứng: Add disk fail vì quá nhỏ
```

```sql
-- Fix: dùng disk lớn hơn, hoặc check compatible.asm version requirement
SELECT name, compatibility FROM v$asm_diskgroup WHERE name='DATA';
```

### Case 36: ASM instance crash — diskgroups tự dismount

```
🔴 BLOCKING | ASM instance failure

Triệu chứng: Tất cả databases trên ASM bị ảnh hưởng đột ngột
```

```bash
# Kiểm tra ASM alert log
tail -200 $ORACLE_BASE/diag/asm/+asm/+ASM/trace/alert_+ASM.log

# Restart ASM instance
srvctl start asm
srvctl status asm
```

### Case 37: ORA-15183 — invalid PST contents

```
🔴 BLOCKING | ASM Partnership and Status Table corrupt

Triệu chứng: Diskgroup mount fail với lỗi PST
```

```bash
# Nghiêm trọng — cần Oracle Support
# Thử force mount (RỦI RO mất data nếu redundancy không đủ)
sqlplus / as sysasm << 'EOF'
ALTER DISKGROUP DATA MOUNT FORCE;
EOF
```

### Case 38: ASM rebalance treo (stuck) ở 1 phần trăm cố định

```
🟡 DEGRADED | Rebalance không tiến triển

Triệu chứng: v$asm_operation cho thấy rebalance dừng lại
```

```sql
SELECT * FROM v$asm_operation;
-- Tăng power để force tiến triển
ALTER DISKGROUP DATA REBALANCE POWER 8;
-- Nếu vẫn stuck, có thể cần restart ASM instance (planned maintenance)
```

### Case 39: ORA-15203 — failed to create directory in diskgroup

```
🟡 DEGRADED | ASM directory creation fail

Triệu chứng: Tạo directory trong ASM fail (thường do permissions)
```

```sql
SELECT name, state FROM v$asm_diskgroup WHERE name='DATA';
-- Diskgroup phải MOUNTED và writable
```

### Case 40: ASM disk path thay đổi sau OS reboot (multipath)

```
🟡 DEGRADED | Disk path không persistent

Triệu chứng: Sau reboot, ASM không tìm thấy disk (path đổi từ /dev/sdb → /dev/sdc)
```

```bash
# Fix: dùng udev rules hoặc multipath alias thay vì raw /dev/sdX
multipath -ll
cat /etc/multipath/wwids
# Đảm bảo asm_diskstring dùng pattern ổn định (/dev/mapper/* hoặc /dev/oracleasm/*)
sqlplus / as sysasm << 'EOF'
ALTER SYSTEM SET asm_diskstring='/dev/mapper/DATA*' SCOPE=BOTH;
EOF
```

---

## NHÓM D: UNDO / REDO / ARCHIVE (Case 41-50)

### Case 41: ORA-01555 trong batch job dài

```
🟡 DEGRADED | Xem chi tiết SK10-01

Triệu chứng: Batch job dài bị fail giữa chừng
```

```sql
ALTER SYSTEM SET undo_retention=10800 SCOPE=BOTH;  -- 3 giờ cho batch windows
```

### Case 42: ORA-01547 — warning: RECOVER succeeded but OPEN RESETLOGS would get error

```
🟡 DEGRADED | Recovery incomplete cảnh báo

Triệu chứng: Recovery thành công nhưng OPEN RESETLOGS sẽ fail
```

```sql
-- Thường do thiếu offline datafiles trong recovery
SELECT file#, status FROM v$datafile WHERE status != 'ONLINE';
ALTER DATABASE DATAFILE 8 ONLINE;
-- Sau đó retry RECOVER và OPEN RESETLOGS
```

### Case 43: ORA-00350 — log X of instance ORCL1 needs to be archived

```
🟡 DEGRADED | RAC — Redo log chưa archive xong

Triệu chứng: Operation bị block do redo log instance khác chưa archive
```

```sql
-- Force archive trên instance đó
ALTER SYSTEM ARCHIVE LOG CURRENT;
-- Hoặc check archiver process status
SELECT process, status FROM v$managed_standby WHERE process LIKE 'ARC%';
```

### Case 44: ORA-00321 — log X of thread X cannot be used for log switch

```
🟡 DEGRADED | Redo log corrupt hoặc member missing

Triệu chứng: Log switch fail tại 1 group cụ thể
```

```sql
SELECT group#, status, archived FROM v$log;
SELECT group#, member, status FROM v$logfile;
-- Nếu group hỏng và không cần thiết:
ALTER DATABASE DROP LOGFILE GROUP 3;
ALTER DATABASE ADD LOGFILE GROUP 3 ('+DATA','+FRA') SIZE 500M;
```

### Case 45: ORA-00257 trong môi trường DataGuard (Standby)

```
🔴 BLOCKING | Standby FRA full

Triệu chứng: Standby database treo tương tự Primary
```

```bash
# Trên Standby, xóa applied archive logs
rman target / << 'EOF'
DELETE NOPROMPT ARCHIVELOG ALL APPLIED COMPLETED BEFORE 'SYSDATE-1';
EOF
```

### Case 46: ORA-16038 — log X sequence# X cannot be archived

```
🟡 DEGRADED | Archive destination không hoạt động

Triệu chứng: Archive log fail vì destination lỗi
```

```sql
SELECT dest_id, status, error FROM v$archive_dest WHERE status != 'VALID';
-- Fix destination path/permissions hoặc disable destination lỗi tạm thời
ALTER SYSTEM SET log_archive_dest_state_2=DEFER SCOPE=BOTH;
```

### Case 47: Redo log switch quá thường xuyên (performance impact)

```
🟡 DEGRADED | Redo log size quá nhỏ

Triệu chứng: Log switch > 15 lần/giờ, ảnh hưởng performance
```

```sql
SELECT TO_CHAR(first_time,'YYYY-MM-DD HH24') hour, COUNT(*)
FROM v$log_history WHERE first_time > SYSDATE-1
GROUP BY TO_CHAR(first_time,'YYYY-MM-DD HH24') ORDER BY 1 DESC;
-- Fix: tăng redo log size (add mới size lớn hơn, drop cũ)
ALTER DATABASE ADD LOGFILE GROUP 10 ('+DATA','+FRA') SIZE 2G;
```

### Case 48: ORA-01624 — log X needed for crash recovery of instance

```
🟡 DEGRADED | Không thể drop redo log đang cần cho recovery

Triệu chứng: DROP LOGFILE GROUP fail
```

```sql
-- Force checkpoint trước
ALTER SYSTEM CHECKPOINT;
ALTER SYSTEM SWITCH LOGFILE;
-- Retry drop sau khi status không còn CURRENT/ACTIVE
SELECT group#, status FROM v$log;
```

### Case 49: Undo tablespace switch không hoàn thành

```
🟡 DEGRADED | Undo tablespace cũ vẫn còn active transactions

Triệu chứng: Không drop được undo tablespace cũ sau khi switch
```

```sql
SELECT status, COUNT(*) FROM dba_undo_extents
WHERE tablespace_name='UNDOTBS1' GROUP BY status;
-- Đợi tất cả EXPIRED rồi mới drop
-- Hoặc force bằng cách switch lại và đợi lâu hơn
```

### Case 50: ORA-19809 — limit exceeded for recovery files (FRA full)

```
🔴 BLOCKING | FRA đầy hoàn toàn

Triệu chứng: Mọi backup/archive operation đều fail
```

```sql
SELECT space_used/space_limit*100 pct FROM v$recovery_file_dest;
ALTER SYSTEM SET db_recovery_file_dest_size=200G SCOPE=BOTH;
```

```bash
rman target / << 'EOF'
DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
EOF
```

---

## NHÓM E: RMAN BACKUP / RECOVERY (Case 51-70)

### Case 51: RMAN-06004 — ORACLE error from recovery catalog database

```
🟡 DEGRADED | RMAN Catalog connection issue

Triệu chứng: Không kết nối được recovery catalog
```

```bash
rman target / catalog rman_cat/pass@CATALOG
# Kiểm tra catalog DB còn sống
tnsping CATALOG
```

### Case 52: RMAN-20011 — target database incarnation not found in recovery catalog

```
🟡 DEGRADED | Catalog chưa biết về incarnation hiện tại

Triệu chứng: Sau OPEN RESETLOGS, RMAN không nhận diện DB
```

```bash
rman target / catalog rman_cat/pass@CATALOG << 'EOF'
RESYNC CATALOG;
EOF
```

### Case 53: RMAN-06026 — some targets not found

```
🟡 DEGRADED | Backup piece reference bị thiếu

Triệu chứng: RMAN command không tìm thấy object cần thiết
```

```bash
rman target / << 'EOF'
CROSSCHECK BACKUP;
LIST BACKUP SUMMARY;
EOF
```

### Case 54: ORA-19625 — error identifying file (backup piece deleted ngoài RMAN)

```
🟡 DEGRADED | Backup piece bị xóa thủ công

Triệu chứng: RMAN vẫn nghĩ backup tồn tại nhưng file đã mất
```

```bash
rman target / << 'EOF'
CROSSCHECK BACKUP;
DELETE NOPROMPT EXPIRED BACKUP;
EOF
```

### Case 55: RMAN-03002/ORA-19809 — backup command fail FRA full

```
🔴 BLOCKING | Xem case 50 (liên quan)

Triệu chứng: Backup fail giữa chừng do FRA hết dung lượng
```

```bash
rman target / << 'EOF'
DELETE NOPROMPT OBSOLETE;
EOF
```

### Case 56: RMAN — backup chạy chậm bất thường (performance)

```
🟡 DEGRADED | RMAN throughput thấp

Triệu chứng: Backup mất nhiều thời gian hơn bình thường
```

```bash
# Tăng parallel channels
rman target / << 'EOF'
CONFIGURE DEVICE TYPE DISK PARALLELISM 8;
EOF
# Kiểm tra I/O bottleneck
iostat -x 5 5
```

### Case 57: RMAN-06059 — expected archived log not found, lost of archived log compromises recoverability

```
🔴 BLOCKING | Archive log gap trong backup chain

Triệu chứng: RESTORE/RECOVER fail vì thiếu archive log
```

```bash
rman target / << 'EOF'
CROSSCHECK ARCHIVELOG ALL;
EOF
-- Nếu archive thực sự mất và không có nguồn khác:
-- RECOVER DATABASE UNTIL CANCEL; (PITR đến điểm có archive)
```

### Case 58: ORA-19870 — error reading backup piece

```
🔴 BLOCKING | Backup piece corrupt

Triệu chứng: RESTORE fail vì backup file bị corrupt
```

```bash
rman target / << 'EOF'
RESTORE DATABASE VALIDATE;
EOF
-- Nếu backup corrupt, dùng backup khác (level trước hoặc full backup khác)
LIST BACKUP OF DATABASE;
RESTORE DATABASE FROM TAG 'WEEKLY_FULL';
```

### Case 59: RMAN-20242 — specification does not match any backup in repository

```
🟡 DEGRADED | RMAN không tìm thấy backup theo tiêu chí

Triệu chứng: RESTORE với điều kiện cụ thể không match backup nào
```

```bash
rman target / << 'EOF'
LIST BACKUP SUMMARY;
LIST INCARNATION;
EOF
-- Reset incarnation nếu cần
RESET DATABASE TO INCARNATION 2;
```

### Case 60: ORA-01194 — file 1 needs more recovery to be consistent

```
🟡 DEGRADED | Recovery chưa đủ

Triệu chứng: OPEN DATABASE fail, cần recover thêm
```

```sql
RECOVER DATABASE;
-- Hoặc nếu thiếu archive cụ thể:
RECOVER DATABASE UNTIL CANCEL;
ALTER DATABASE OPEN RESETLOGS;
```

### Case 61: RMAN Duplicate fail — RMAN-05529 listener not configured

```
🔴 BLOCKING | Auxiliary connection issue

Triệu chứng: Active duplicate fail vì target không kết nối được
```

```bash
tnsping TARGET_AUXILIARY
lsnrctl status  # Trên target server
```

### Case 62: ORA-27037 — unable to obtain file status (Restore path issue)

```
🔴 BLOCKING | Restore path không tồn tại

Triệu chứng: RESTORE fail vì thư mục đích chưa tạo
```

```bash
mkdir -p /u01/oradata/TARGET
chown oracle:oinstall /u01/oradata/TARGET
```

### Case 63: RMAN Block Media Recovery fail — backup không có block đó

```
🟡 DEGRADED | BMR không tìm thấy block trong backup

Triệu chứng: BLOCKRECOVER fail
```

```bash
rman target / << 'EOF'
LIST BACKUP OF DATAFILE 5;
EOF
-- Nếu backup không bao gồm block đó (incremental issue), dùng full restore datafile
RESTORE DATAFILE 5;
RECOVER DATAFILE 5;
```

### Case 64: RMAN — compression ratio thấp bất thường

```
🟢 COSMETIC | Backup size lớn hơn expected

Triệu chứng: COMPRESSED BACKUPSET không nén hiệu quả
```

```bash
-- Kiểm tra algorithm đang dùng
rman target / << 'EOF'
SHOW COMPRESSION ALGORITHM;
CONFIGURE COMPRESSION ALGORITHM 'HIGH';
EOF
```

### Case 65: Restore database sang server khác — path conflict

```
🟡 DEGRADED | SET NEWNAME cần thiết

Triệu chứng: Restore fail vì path gốc không tồn tại trên server mới
```

```bash
rman target / auxiliary sys/pass@TARGET << 'EOF'
RUN {
  SET NEWNAME FOR DATAFILE 1 TO '/new_path/system01.dbf';
  SET NEWNAME FOR DATAFILE 2 TO '/new_path/sysaux01.dbf';
  RESTORE DATABASE;
  SWITCH DATAFILE ALL;
  RECOVER DATABASE;
}
EOF
```

### Case 66: ORA-19844 — error during backup data file read

```
🔴 BLOCKING | I/O error trong khi backup đang chạy

Triệu chứng: Backup fail do datafile không đọc được
```

```bash
# Kiểm tra disk health
dmesg | grep -i "I/O error"
# Validate datafile riêng lẻ
rman target / << 'EOF'
VALIDATE DATAFILE 5;
EOF
```

### Case 67: RMAN catalog upgrade required

```
🟡 DEGRADED | Catalog schema version cũ

Triệu chứng: "RMAN-06429: target database is not compatible with this version of RMAN"
```

```bash
rman catalog rman_cat/pass@CATALOG << 'EOF'
UPGRADE CATALOG;
UPGRADE CATALOG;  -- Cần confirm 2 lần
EOF
```

### Case 68: Backup retention policy không cleanup obsolete đúng

```
🟡 DEGRADED | RETENTION POLICY config sai

Triệu chứng: Backup cũ không được tự động đánh dấu OBSOLETE
```

```bash
rman target / << 'EOF'
SHOW RETENTION POLICY;
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
REPORT OBSOLETE;
DELETE NOPROMPT OBSOLETE;
EOF
```

### Case 69: ORA-65041 — operation not allowed from within a pluggable database (RMAN trong PDB)

```
🟡 DEGRADED | RMAN command sai context (PDB vs CDB)

Triệu chứng: Một số RMAN commands chỉ chạy được từ CDB$ROOT
```

```bash
# Kết nối với CDB service thay vì PDB service
rman target sys/pass@CDB_SERVICE
```

### Case 70: Flashback Database fail — ORA-38760 flashback not enabled

```
🟡 DEGRADED | Flashback chưa được bật

Triệu chứng: FLASHBACK DATABASE command fail
```

```sql
SELECT flashback_on FROM v$database;
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE FLASHBACK ON;
ALTER DATABASE OPEN;
```

---

## NHÓM F: CDB / PDB MULTITENANT (Case 71-85)

### Case 71: ORA-65040 — operation not allowed from within a pluggable database

```
🟡 DEGRADED | Command chỉ chạy được từ CDB$ROOT

Triệu chứng: ALTER SYSTEM/DATABASE fail trong PDB context
```

```sql
ALTER SESSION SET CONTAINER=CDB$ROOT;
-- Thực hiện command cần thiết, sau đó quay lại PDB nếu cần
```

### Case 72: ORA-65011 — Pluggable Database does not exist

```
🟡 DEGRADED | PDB name sai hoặc đã drop

Triệu chứng: Connect/ALTER PLUGGABLE DATABASE fail
```

```sql
SELECT name, open_mode FROM v$pdbs;
-- Kiểm tra đúng tên PDB
```

### Case 73: PDB stuck ở trạng thái MOUNTED, không OPEN được

```
🔴 BLOCKING | PDB open fail

Triệu chứng: ALTER PLUGGABLE DATABASE OPEN không thành công
```

```sql
ALTER PLUGGABLE DATABASE pdb1 OPEN;
-- Xem lỗi cụ thể
SELECT * FROM pdb_plug_in_violations WHERE name='PDB1' AND status='PENDING';
-- Common: cần upgrade hoặc thiếu tablespace
```

### Case 74: ORA-65169 — error encountered while attempting to copy file

```
🟡 DEGRADED | PDB clone/plug file operation fail

Triệu chứng: CREATE PLUGGABLE DATABASE ... FROM fail
```

```bash
# Kiểm tra disk space đích
df -h /u01/oradata/
# Kiểm tra permissions
ls -la /u01/oradata/
```

### Case 75: PDB$SEED bị mở READ WRITE nhầm (không nên)

```
🟢 COSMETIC | PDB$SEED state sai

Triệu chứng: PDB$SEED phải luôn READ ONLY
```

```sql
ALTER PLUGGABLE DATABASE pdb$seed CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb$seed OPEN READ ONLY;
```

### Case 76: ORA-65048 — error encountered when processing the current DDL statement (Lockdown Profile)

```
🟡 DEGRADED | Lockdown Profile chặn DDL

Triệu chứng: DDL fail do PDB Lockdown Profile restriction
```

```sql
SELECT lockdown_profile FROM v$pdbs WHERE name='PDB1';
-- Kiểm tra restriction
SELECT * FROM dba_lockdown_profiles WHERE profile_name='<profile>';
-- Có thể cần điều chỉnh profile hoặc dùng CDB$ROOT
```

### Case 77: Common user không login được vào PDB cụ thể

```
🟡 DEGRADED | Common user privilege thiếu CONTAINER=ALL

Triệu chứng: C##user login fail vào 1 PDB cụ thể
```

```sql
-- Đảm bảo grant đúng container scope
GRANT CREATE SESSION TO c##common_user CONTAINER=ALL;
```

### Case 78: PDB datafiles không thấy sau RESTORE CDB

```
🟡 DEGRADED | PDB datafile path issue sau restore

Triệu chứng: PDB không OPEN được sau khi restore toàn CDB
```

```sql
SELECT file_name, con_id FROM cdb_data_files WHERE con_id=(
  SELECT con_id FROM v$pdbs WHERE name='PDB1');
-- Kiểm tra file thực sự tồn tại
```

### Case 79: ORA-65093 — Pluggable Database not in a valid state for unplug

```
🟡 DEGRADED | PDB chưa CLOSE trước khi unplug

Triệu chứng: UNPLUG fail
```

```sql
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb1 UNPLUG INTO '/tmp/pdb1.xml';
```

### Case 80: Application Container — PDB không sync với Application Root

```
🟡 DEGRADED | Application PDB sync issue

Triệu chứng: PDB trong Application Container không nhận update từ App Root
```

```sql
ALTER SESSION SET CONTAINER=app_root;
ALTER PLUGGABLE DATABASE APPLICATION app_name SYNC;
```

### Case 81: ORA-65106 — DDL is restricted... use of bigfile clause

```
🟡 DEGRADED | DDL restriction trong CDB context

Triệu chứng: Một số DDL không cho phép tại CDB level
```

```sql
-- Thực hiện DDL từ trong PDB cụ thể thay vì CDB$ROOT
ALTER SESSION SET CONTAINER=pdb1;
```

### Case 82: PDB Resource Manager — CPU limit không hoạt động

```
🟡 DEGRADED | CDB Resource Plan chưa active

Triệu chứng: PDB vượt CPU allocation dù đã set limit
```

```sql
SHOW PARAMETER resource_manager_plan;
ALTER SYSTEM SET resource_manager_plan='CDB_PLAN' SCOPE=BOTH;
```

### Case 83: ORA-65135 — invalid PDB name

```
🟢 COSMETIC | Naming convention violation

Triệu chứng: CREATE PLUGGABLE DATABASE fail vì tên không hợp lệ
```

```sql
-- PDB name không được bắt đầu bằng số, không chứa ký tự đặc biệt
-- Đặt tên tuân thủ: chữ cái đầu, alphanumeric + underscore
```

### Case 84: Refreshable PDB Clone — refresh fail

```
🟡 DEGRADED | Refresh clone không đồng bộ

Triệu chứng: ALTER PLUGGABLE DATABASE REFRESH fail
```

```sql
SELECT refresh_mode, last_refresh_scn FROM dba_pdbs WHERE pdb_name='PDB_CLONE';
ALTER PLUGGABLE DATABASE pdb_clone CLOSE;
ALTER PLUGGABLE DATABASE pdb_clone REFRESH;
ALTER PLUGGABLE DATABASE pdb_clone OPEN;
```

### Case 85: PDB time zone mismatch sau PLUG vào CDB khác

```
🟡 DEGRADED | Timezone version conflict

Triệu chứng: PDB timezone không khớp CDB mới
```

```sql
SELECT * FROM v$timezone_file;  -- So sánh CDB vs PDB cũ
-- Cần upgrade timezone của PDB để match CDB
```

---

## NHÓM G: SCHEDULER & AUTOMATION (Case 86-100)

### Case 86: DBMS_SCHEDULER job không chạy đúng giờ

```
🟡 DEGRADED | Job scheduling issue

Triệu chứng: Job set chạy 2AM nhưng không chạy
```

```sql
SELECT job_name, enabled, state, next_run_date
FROM dba_scheduler_jobs WHERE job_name='NIGHTLY_JOB';
-- Kiểm tra job có enable không
EXEC DBMS_SCHEDULER.ENABLE('NIGHTLY_JOB');
```

### Case 87: ORA-27468 — "schema.job" is currently executing

```
🟡 DEGRADED | Job đang chạy không stop được

Triệu chứng: STOP_JOB fail vì job stuck
```

```sql
EXEC DBMS_SCHEDULER.STOP_JOB('JOB_NAME', force=>TRUE);
-- Nếu vẫn fail, kill session đang chạy job đó
SELECT session_id FROM dba_scheduler_running_jobs WHERE job_name='JOB_NAME';
ALTER SYSTEM KILL SESSION '&sid,&serial#' IMMEDIATE;
```

### Case 88: Scheduler Window không trigger Maintenance Window jobs

```
🟡 DEGRADED | Window schedule issue

Triệu chứng: Auto stats gathering không chạy trong window
```

```sql
SELECT window_name, enabled, active FROM dba_scheduler_windows;
SELECT client_name, status FROM dba_autotask_client;
EXEC DBMS_AUTO_TASK_ADMIN.ENABLE(
  client_name=>'auto optimizer stats collection',
  operation=>NULL, window_name=>NULL);
```

### Case 89: ORA-27452 — duplicate job/program/schedule name

```
🟢 COSMETIC | Naming conflict khi tạo job

Triệu chứng: CREATE_JOB fail vì tên đã tồn tại
```

```sql
SELECT job_name FROM dba_scheduler_jobs WHERE job_name='MY_JOB';
EXEC DBMS_SCHEDULER.DROP_JOB('MY_JOB', force=>TRUE);
-- Sau đó tạo lại
```

### Case 90: Job chạy nhưng fail silently (không log lỗi rõ ràng)

```
🟡 DEGRADED | Job log không đủ chi tiết

Triệu chứng: Job FAILED nhưng error message không rõ
```

```sql
SELECT log_date, status, additional_info, error#
FROM dba_scheduler_job_log
WHERE job_name='MY_JOB' ORDER BY log_date DESC;
-- Xem thêm job_run_details cho chi tiết hơn
SELECT log_date, error#, errors FROM dba_scheduler_job_run_details
WHERE job_name='MY_JOB' ORDER BY log_date DESC;
```

### Case 91: Job Class resource consumption không như expected

```
🟡 DEGRADED | Job Class chưa map đúng Resource Consumer Group

Triệu chứng: Job priority không hoạt động đúng
```

```sql
SELECT job_class_name, resource_consumer_group
FROM dba_scheduler_job_classes;
EXEC DBMS_SCHEDULER.SET_ATTRIBUTE(
  'MY_JOB_CLASS','resource_consumer_group','LOW_PRIORITY_GROUP');
```

### Case 92: External Job (EXECUTABLE type) fail — OS permission

```
🔴 BLOCKING | External job không chạy được script

Triệu chứng: EXECUTABLE job type fail ngay khi chạy
```

```bash
# Kiểm tra script có executable permission
ls -la /u01/scripts/backup.sh
chmod +x /u01/scripts/backup.sh
chown oracle:oinstall /u01/scripts/backup.sh
```

```sql
-- Kiểm tra credential cho external job (nếu cần)
SELECT credential_name FROM dba_scheduler_jobs WHERE job_name='EXT_JOB';
```

### Case 93: Scheduler job chạy chồng lặp (overlap execution)

```
🟡 DEGRADED | Job không chờ instance trước hoàn thành

Triệu chứng: Nhiều instances của cùng 1 job chạy đồng thời
```

```sql
-- Thêm logic chống overlap trong job hoặc dùng:
EXEC DBMS_SCHEDULER.SET_ATTRIBUTE(
  'MY_JOB','max_run_duration', INTERVAL '1' HOUR);
-- Hoặc check trong job code: nếu đang chạy thì exit
```

### Case 94: ORA-27370 — job slave failed to launch a job

```
🔴 BLOCKING | Job Queue Process issue

Triệu chứng: Job không launch được do thiếu job queue processes
```

```sql
SHOW PARAMETER job_queue_processes;
ALTER SYSTEM SET job_queue_processes=20 SCOPE=BOTH;
```

### Case 95: Chain (Scheduler Chain) bị stuck giữa chừng

```
🟡 DEGRADED | Chain step không tiến triển

Triệu chứng: Multi-step chain dừng lại ở 1 step
```

```sql
SELECT chain_name, state, step_name FROM dba_scheduler_running_chains;
-- Force evaluate chain rule nếu cần
EXEC DBMS_SCHEDULER.EVALUATE_RUNNING_CHAIN('CHAIN_NAME','JOB_NAME','STEP1','TRUE');
```

### Case 96: Job logging history mất do purge quá sớm

```
🟢 COSMETIC | Log retention quá ngắn

Triệu chứng: Không tìm thấy lịch sử job cũ
```

```sql
EXEC DBMS_SCHEDULER.SET_SCHEDULER_ATTRIBUTE('log_history',30);  -- Giữ 30 ngày
```

### Case 97: DBMS_JOB (legacy) không migrate sang DBMS_SCHEDULER

```
🟢 COSMETIC | Legacy job system vẫn hoạt động song song

Triệu chứng: Có cả DBMS_JOB và DBMS_SCHEDULER jobs, khó quản lý
```

```sql
-- Xem legacy jobs
SELECT job, what, next_date FROM dba_jobs;
-- Migrate sang Scheduler (manual conversion cần thiết)
```

### Case 98: Resource Manager Plan không switch theo schedule

```
🟡 DEGRADED | Resource Plan scheduling issue

Triệu chứng: Plan đổi theo giờ không hoạt động (VD: DAY_PLAN/NIGHT_PLAN)
```

```sql
SELECT * FROM dba_scheduler_windows WHERE resource_plan IS NOT NULL;
-- Đảm bảo Window có gán resource_plan đúng
EXEC DBMS_SCHEDULER.SET_ATTRIBUTE(
  'NIGHT_WINDOW','resource_plan','NIGHT_PLAN');
```

### Case 99: AutoTask (auto stats/auto SQL Tuning) tiêu tốn quá nhiều resource

```
🟡 DEGRADED | AutoTask chiếm CPU/IO cao trong maintenance window

Triệu chứng: Performance impact trong window tự động
```

```sql
-- Giảm resource allocation cho AutoTask
EXEC DBMS_AUTO_TASK_ADMIN.DISABLE(
  client_name=>'sql tuning advisor',
  operation=>NULL, window_name=>NULL);
-- Hoặc điều chỉnh maintenance window time/duration
```

### Case 100: Job email notification không gửi được

```
🟢 COSMETIC | Scheduler email integration fail

Triệu chứng: Job hoàn thành nhưng không nhận được email
```

```sql
-- Kiểm tra SMTP config
SELECT DBMS_SCHEDULER.GET_SCHEDULER_ATTRIBUTE('email_server') FROM dual;
EXEC DBMS_SCHEDULER.SET_SCHEDULER_ATTRIBUTE('email_server','smtp.company.com:25');
-- Test gửi email
EXEC DBMS_SCHEDULER.SET_ATTRIBUTE('MY_JOB','email_notification',
  'admin@company.com:[email protected]');
```

---

## TỔNG KẾT — QUICK REFERENCE TABLE

```
Top 10 Lỗi Thường Gặp Nhất (theo tần suất thực tế):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. ORA-01652 (TEMP full)           → Case 16
2. ORA-01555 (Snapshot too old)    → Case 41
3. ORA-00257 (Archiver hung)       → Case 12, 45
4. ORA-01653 (Tablespace full)     → Case 29
5. ORA-04031 (Shared pool)         → SK10-01 Case 2
6. ORA-15041 (ASM diskgroup full)  → Case 31
7. ORA-65040 (CDB/PDB context)     → Case 71
8. RMAN-06059 (Archive gap)        → Case 57
9. ORA-00018 (Max sessions)        → Case 1
10. ORA-27370 (Job queue process)  → Case 94
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Tài liệu tham khảo:**
- Oracle Database Error Messages 19c
- Oracle Database Administrator's Guide 19c
- MOS Note 1352144.1, 33438.1, 836986.1
- QT/DB.01 — Trần Văn Bình, VietDBA
- www.tranvanbinh.vn
