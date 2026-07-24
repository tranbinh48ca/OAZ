---
name: oracle-high-availability
description: >
  Oracle High Availability với DataGuard và GoldenGate.
  Kích hoạt khi hỏi về: DataGuard, Data Guard, standby database,
  physical standby, logical standby, active DataGuard, switchover, failover,
  DGMGRL, broker, fast-start failover, FSFO, observer, redo apply,
  archive gap DataGuard, GoldenGate, OGG, extract, replicat, pump,
  trail file, ggsci, bidirectional replication, zero downtime replication,
  cross-platform replication, heterogeneous replication, OGG abend,
  high availability Oracle, DR setup, disaster recovery Oracle,
  đảm bảo tính sẵn sàng, đồng bộ dữ liệu Oracle.
---

# SK07 · High Availability: Oracle DataGuard & GoldenGate

**Phạm vi:** Oracle 11g, 12c, 19c, 21c — Physical/Logical Standby, Active DG, OGG 19c+  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Tài liệu nền:** QT/DB.01 Phụ lục V, VI — DataGuard & GoldenGate

---

## PHẦN A: ORACLE DATAGUARD

### A1. Kiến trúc DataGuard

```
PRIMARY DB ──→ Redo Transport ──→ STANDBY DB
           ←── Apply Services ←──
```

**Protection modes:**
- `MAX PROTECTION`: Sync, zero data loss, Primary dừng nếu không sync được
- `MAX AVAILABILITY`: Sync nếu có thể, fall back async (khuyến dùng)
- `MAX PERFORMANCE`: Async, tốt nhất cho performance (mặc định)

**Standby types:**
- **Physical Standby**: Block-for-block copy, có thể open READ ONLY (Active DG)
- **Logical Standby**: SQL Apply, có thể mở READ WRITE (chỉ đọc từ DG)

---

### A2. Cài đặt Physical Standby

**Bước 1: Chuẩn bị Primary**

```sql
-- Enable Archive Log (nếu chưa có)
SELECT log_mode FROM v$database;

-- Enable Force Logging
ALTER DATABASE FORCE LOGGING;

-- Enable Supplemental Logging (cần cho logical standby & GoldenGate)
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;

-- Tạo Standby Redo Logs (SRL) — phải nhiều hơn online redo logs 1 group
-- Nếu Primary có 3 groups 200MB:
ALTER DATABASE ADD STANDBY LOGFILE GROUP 10
  '/u01/oradata/ORCL/standby_redo10a.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 11
  '/u01/oradata/ORCL/standby_redo11a.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 12
  '/u01/oradata/ORCL/standby_redo12a.log' SIZE 200M;
ALTER DATABASE ADD STANDBY LOGFILE GROUP 13
  '/u01/oradata/ORCL/standby_redo13a.log' SIZE 200M;

-- Parameters cho DataGuard (spfile)
ALTER SYSTEM SET log_archive_config = 'DG_CONFIG=(ORCL,ORCL_STB)' SCOPE=BOTH;
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=ORCL_STB' SCOPE=BOTH;
ALTER SYSTEM SET log_archive_dest_state_2 = ENABLE SCOPE=BOTH;
ALTER SYSTEM SET fal_server = 'ORCL_STB' SCOPE=BOTH;
ALTER SYSTEM SET standby_file_management = 'AUTO' SCOPE=BOTH;
ALTER SYSTEM SET db_file_name_convert =
  '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/' SCOPE=SPFILE;
ALTER SYSTEM SET log_file_name_convert =
  '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/' SCOPE=SPFILE;
```

**Bước 2: Tạo Standby bằng RMAN Duplicate**

```bash
# Trên Standby server, chạy RMAN
rman target sys/password@ORCL auxiliary sys/password@ORCL_STB

DUPLICATE TARGET DATABASE FOR STANDBY
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT
      'ORCL','ORCL_STB',
      '/u01/oradata/ORCL/','/u01/oradata/ORCL_STB/'
    SET DB_UNIQUE_NAME='ORCL_STB'
    SET LOG_ARCHIVE_DEST_2=
      'SERVICE=ORCL ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
       DB_UNIQUE_NAME=ORCL'
    SET FAL_SERVER='ORCL'
    SET FAL_CLIENT='ORCL_STB'
    SET STANDBY_FILE_MANAGEMENT='AUTO'
  NOFILENAMECHECK;
```

**Bước 3: Start Managed Recovery**

```sql
-- Trên Standby
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- Kiểm tra apply đang chạy
SELECT process, status, sequence#, block#
FROM v$managed_standby;

SELECT thread#, sequence#, applied
FROM v$archived_log
ORDER BY sequence# DESC
FETCH FIRST 10 ROWS ONLY;
```

---

### A3. Active DataGuard

```sql
-- Mở Standby READ ONLY và vẫn apply redo (Active DG)
-- Trên Standby:
ALTER DATABASE OPEN;  -- (Physical standby tự mở READ ONLY sau recover)
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- Kiểm tra Active DG
SELECT open_mode FROM v$database;  -- Phải là: READ ONLY WITH APPLY

-- Far Sync Instance (giảm bandwidth)
-- Far Sync nhận redo synchronously từ Primary, rồi ship async sang Standby
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=FAR_SYNC_1 SYNC AFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=FAR_SYNC_1 MAX_FAILURE=1' SCOPE=BOTH;
```

---

### A4. DataGuard Broker (DGMGRL) — Khuyến dùng

```bash
# Cấu hình Broker trên Primary
sqlplus / as sysdba
ALTER SYSTEM SET dg_broker_start = TRUE SCOPE=BOTH;
-- Tương tự trên Standby

# Kết nối DGMGRL
dgmgrl /

# Tạo configuration
DGMGRL> CREATE CONFIGURATION 'orcl_dg' AS
          PRIMARY DATABASE IS 'ORCL'
          CONNECT IDENTIFIER IS 'ORCL';

DGMGRL> ADD DATABASE 'ORCL_STB' AS
          CONNECT IDENTIFIER IS 'ORCL_STB'
          MAINTAINED AS PHYSICAL;

DGMGRL> ENABLE CONFIGURATION;

# Kiểm tra
DGMGRL> SHOW CONFIGURATION;
DGMGRL> SHOW DATABASE 'ORCL';
DGMGRL> SHOW DATABASE 'ORCL_STB';
DGMGRL> SHOW DATABASE VERBOSE 'ORCL_STB';

# Kiểm tra lag
DGMGRL> SHOW DATABASE 'ORCL_STB' 'ApplyLag';
DGMGRL> SHOW DATABASE 'ORCL_STB' 'TransportLag';
```

---

### A5. SWITCHOVER (Planned — Zero Data Loss)

```bash
# Pre-check trước switchover
dgmgrl /
DGMGRL> SHOW CONFIGURATION;
DGMGRL> VALIDATE DATABASE 'ORCL_STB';

# Switchover (chỉ 1 lệnh với broker)
DGMGRL> SWITCHOVER TO 'ORCL_STB';

# Kiểm tra sau switchover
DGMGRL> SHOW CONFIGURATION;
-- ORCL_STB phải là PRIMARY
-- ORCL phải là PHYSICAL STANDBY

# Verify trên DB mới Primary
sqlplus / as sysdba
SELECT db_unique_name, open_mode FROM v$database;
```

**Manual Switchover (không dùng Broker):**

```sql
-- Trên Primary: kiểm tra sẵn sàng
SELECT switchover_status FROM v$database;
-- Phải là: TO STANDBY hoặc SESSIONS ACTIVE

-- Chuyển Primary → Standby
ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY
  WITH SESSION SHUTDOWN;

-- Trên Standby: chuyển thành Primary
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY
  WITH SESSION SHUTDOWN;
ALTER DATABASE OPEN;
```

---

### A6. FAILOVER (Unplanned — Primary Down)

```bash
# Với Broker (nếu observer configured — FSFO)
# Tự động xảy ra, không cần can thiệp

# Manual Failover với Broker
DGMGRL> FAILOVER TO 'ORCL_STB';

# Manual Failover không có Broker
# Trên Standby:
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
ALTER DATABASE OPEN;

# Reinstate old Primary (sau khi Primary recover)
DGMGRL> REINSTATE DATABASE 'ORCL';
```

---

### A7. Monitoring DataGuard

```sql
-- Apply lag
SELECT name, value, datum_time
FROM v$dataguard_stats
WHERE name IN ('apply lag','transport lag','estimated startup time');

-- Redo apply status
SELECT process, status, sequence#, block#, blocks
FROM v$managed_standby
ORDER BY process;

-- Gap detection
SELECT thread#, low_sequence#, high_sequence#
FROM v$archive_gap;

-- DataGuard status từ Primary
SELECT dest_id, status, target, archiver, schedule,
       destination, valid_role, error
FROM v$archive_dest
WHERE status != 'INACTIVE';
```

---

## PHẦN B: ORACLE GOLDENGATE

### B1. Kiến trúc GoldenGate

```
SOURCE DB                           TARGET DB
  │                                    │
[Extract] ──→ trail files ──→ [Replicat]
  │
[Pump] ──→ remote trail files ──→ [Replicat]
```

**Processes:**
- **Extract**: Đọc redo/archive logs từ Source DB (thay đổi DML/DDL)
- **Pump**: Extract phụ, chuyển trail files sang target server
- **Replicat**: Đọc trail files, apply vào Target DB

**Capture modes:**
- **Classic**: Đọc archive logs/redo log trực tiếp
- **Integrated (khuyến dùng)**: Dùng Oracle LogMiner API, tốt hơn cho RAC, pluggable

---

### B2. Cài đặt GoldenGate Basic

**Chuẩn bị Source DB:**

```sql
-- Enable supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE=BOTH;

-- Tạo GoldenGate user
CREATE USER gg_admin IDENTIFIED BY GG_Admin_1234;
GRANT DBA TO gg_admin;
-- Quyền tối thiểu thay DBA:
GRANT CREATE SESSION TO gg_admin;
GRANT EXECUTE ON DBMS_GOLDENGATE_AUTH TO gg_admin;
EXEC DBMS_GOLDENGATE_AUTH.GRANT_ADMIN_PRIVILEGE('GG_ADMIN');

-- Add supplemental logging cho tables
ALTER TABLE scott.orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- Hoặc cho toàn schema:
EXEC DBMS_CAPTURE_ADM.PREPARE_SCHEMA_INSTANTIATION(
  schema_name => 'SCOTT',
  supplemental_log_data_any => 'ALWAYS');
```

**Cấu hình Manager:**

```bash
# Trong GoldenGate home
./ggsci

GGSCI> CREATE SUBDIRS

GGSCI> EDIT PARAMS MGR
# Trong file:
PORT 7809
DYNAMICPORTLIST 7810-7820
AUTORESTART EXTRACT *, RETRIES 5, WAITMINUTES 1
PURGEOLDEXTRACTS ./dirdat/*, USECHECKPOINTS, MINKEEPDAYS 3

GGSCI> START MGR
GGSCI> INFO MGR
```

**Extract — Đọc redo logs:**

```bash
GGSCI> DBLOGIN USERID gg_admin PASSWORD GG_Admin_1234

# Add Extract (Integrated mode - khuyến dùng)
GGSCI> ADD EXTRACT EXT_SCOTT, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/et, EXTRACT EXT_SCOTT, MEGABYTES 200

# Cấu hình Extract
GGSCI> EDIT PARAMS EXT_SCOTT
```

```
-- File params EXT_SCOTT
EXTRACT EXT_SCOTT
USERID gg_admin, PASSWORD GG_Admin_1234
EXTTRAIL ./dirdat/et
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT

-- Tables cần replicate
TABLE SCOTT.ORDERS;
TABLE SCOTT.CUSTOMERS;
TABLE SCOTT.ORDER_ITEMS;
```

```bash
# Register Extract với database
GGSCI> REGISTER EXTRACT EXT_SCOTT DATABASE

# Start Extract
GGSCI> START EXTRACT EXT_SCOTT
GGSCI> INFO EXTRACT EXT_SCOTT
```

**Pump — Chuyển sang Target:**

```bash
GGSCI> ADD EXTRACT PMP_SCOTT, EXTTRAILSOURCE ./dirdat/et, BEGIN NOW
GGSCI> ADD RMTTRAIL ./dirdat/rt, EXTRACT PMP_SCOTT, MEGABYTES 200

GGSCI> EDIT PARAMS PMP_SCOTT
```

```
-- File params PMP_SCOTT
EXTRACT PMP_SCOTT
USERID gg_admin, PASSWORD GG_Admin_1234
RMTHOST target_server, MGRPORT 7809
RMTTRAIL ./dirdat/rt

TABLE SCOTT.*;
```

```bash
GGSCI> START EXTRACT PMP_SCOTT
```

**Replicat — Apply vào Target:**

```bash
# Trên Target server
GGSCI> DBLOGIN USERID gg_admin PASSWORD GG_Admin_1234
GGSCI> ADD REPLICAT REP_SCOTT, INTEGRATED, EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS REP_SCOTT
```

```
-- File params REP_SCOTT
REPLICAT REP_SCOTT
USERID gg_admin, PASSWORD GG_Admin_1234
ASSUMETARGETDEFS

MAP SCOTT.*, TARGET SCOTT.*;
```

```bash
GGSCI> START REPLICAT REP_SCOTT
GGSCI> INFO ALL
```

---

### B3. Monitoring GoldenGate (Phụ lục VI — QT/DB.01)

```bash
# Xem tất cả processes
GGSCI> INFO ALL

# Lag của từng process
GGSCI> LAG EXTRACT EXT_SCOTT
GGSCI> LAG EXTRACT PMP_SCOTT
GGSCI> LAG REPLICAT REP_SCOTT

# Statistics
GGSCI> STATS EXTRACT EXT_SCOTT, TOTAL
GGSCI> STATS REPLICAT REP_SCOTT, TOTAL

# Xem report file
GGSCI> VIEW REPORT EXT_SCOTT

# Xem GoldenGate event log
GGSCI> VIEW GGSEVT

# Xem checkpoint
GGSCI> INFO EXTRACT EXT_SCOTT, DETAIL
GGSCI> INFO REPLICAT REP_SCOTT, DETAIL

# Xem trail file info
GGSCI> INFO EXTTRAIL ./dirdat/et, DETAIL
```

---

### B4. Thêm/Bớt Bảng vào GoldenGate (Phụ lục VI — QT/DB.01)

```bash
# Bước 1: Dừng processes
GGSCI> STOP EXTRACT PMP_SCOTT
GGSCI> STOP EXTRACT EXT_SCOTT

# Bước 2: Thêm supplemental logging cho bảng mới
GGSCI> DBLOGIN USERID gg_admin PASSWORD pass
GGSCI> ADD TRANDATA SCOTT.NEW_TABLE

# Bước 3: Cập nhật params files
GGSCI> EDIT PARAMS EXT_SCOTT
# Thêm: TABLE SCOTT.NEW_TABLE;
GGSCI> EDIT PARAMS PMP_SCOTT
# Thêm: TABLE SCOTT.NEW_TABLE;
GGSCI> EDIT PARAMS REP_SCOTT
# MAP đã có SCOTT.* → không cần thêm nếu dùng wildcard

# Bước 4: Initial load cho bảng mới (export/import data)
# Phương án 1: Dùng OGG Initial Load Extract
GGSCI> ADD EXTRACT INI_NEW, SOURCEISTABLE
GGSCI> EDIT PARAMS INI_NEW
```

```
EXTRACT INI_NEW
USERID gg_admin, PASSWORD pass
RMTHOST target_server, MGRPORT 7809
RMTTASK REPLICAT, GROUP REP_SCOTT
TABLE SCOTT.NEW_TABLE;
```

```bash
GGSCI> START EXTRACT INI_NEW
# Chờ initial load xong

# Bước 5: Restart replication
GGSCI> START EXTRACT EXT_SCOTT
GGSCI> START EXTRACT PMP_SCOTT
GGSCI> START REPLICAT REP_SCOTT
```

---

### B5. Xử lý lỗi OGG-01519 (Phụ lục VI — QT/DB.01)

```bash
# Lỗi: OGG-01519 GoldenGate bị abend trên Extract/Pump/Replicat
# Nguyên nhân: Column không khớp, data type mismatch, DDL thay đổi

# Bước 1: Xem lỗi chi tiết
GGSCI> VIEW REPORT EXT_SCOTT
# Tìm dòng "ERROR" hoặc "OGG-"

# Bước 2: Kiểm tra tables không khớp
GGSCI> DBLOGIN USERID gg_admin PASSWORD pass
GGSCI> INFO REPLICAT REP_SCOTT, DETAIL

# Bước 3: Nếu do DDL change → Sync lại định nghĩa
GGSCI> STOP EXTRACT EXT_SCOTT
-- Trên source:
-- ALTER TABLE scott.orders ADD new_col VARCHAR2(100);
-- Trên target:
-- ALTER TABLE scott.orders ADD new_col VARCHAR2(100);
-- Restart:
GGSCI> START EXTRACT EXT_SCOTT

# Bước 4: Nếu cần skip lỗi (cẩn thận!)
GGSCI> EDIT PARAMS REP_SCOTT
# Thêm:
# REPERROR (DEFAULT, DISCARD)
# Restart: GGSCI> START REPLICAT REP_SCOTT

# Bước 5: Nếu phải restart từ vị trí mới
GGSCI> STOP REPLICAT REP_SCOTT
GGSCI> ALTER REPLICAT REP_SCOTT, AFTERCSN &csn_number
GGSCI> START REPLICAT REP_SCOTT
```

---

### B6. GoldenGate Cross-Platform (Oracle → PostgreSQL)

```bash
# Extract trên Oracle Source (giống như trên)

# Replicat trên PostgreSQL Target
GGSCI> DBLOGIN SOURCEDB pg_dsn, USERID gg_admin PASSWORD pass

GGSCI> ADD REPLICAT REP_PG, EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS REP_PG
```

```
REPLICAT REP_PG
TARGETDB DSN=pg_conn, USERID postgres, PASSWORD pass
SOURCEDEFS ./dirdef/source_defs.def  -- Cần định nghĩa source

REPERROR (DEFAULT, ABEND)

-- Mapping với column rename nếu cần
MAP SCOTT.ORDERS, TARGET public.orders,
  COLMAP (
    order_id  = order_id,
    cust_id   = cust_id,
    order_date = DATENOW()  -- Transform function
  );
```

```bash
# Tạo source definitions file
GGSCI> DEFGEN TABLE SCOTT.*;  -- Tạo trên source Oracle
# Copy file dirdef/source_defs.def sang target server
```

---

### B7. Monitoring Script — Shell (QT/DB.01)

```bash
#!/bin/bash
# ogg_monitor.sh — Monitor GoldenGate
export OGG_HOME=/u01/goldengate
cd $OGG_HOME

REPORT="/tmp/ogg_report_$(date +%Y%m%d).txt"
echo "=== GoldenGate Monitor $(date) ===" > $REPORT

# Status all processes
echo "[PROCESS STATUS]" >> $REPORT
echo "INFO ALL" | ./ggsci >> $REPORT 2>&1

# Lag check
echo "[LAG STATUS]" >> $REPORT
for proc in EXT_SCOTT PMP_SCOTT REP_SCOTT; do
  echo "LAG $proc" | ./ggsci >> $REPORT 2>&1
done

# Alert nếu có ABEND
if grep -q "ABENDED" $REPORT; then
  echo "⚠️ GoldenGate ABEND detected!" | \
    mail -s "ALERT: OGG Abend" dba-team@company.com < $REPORT
fi

# Alert nếu lag > 5 phút
LAG_SEC=$(echo "LAG REPLICAT REP_SCOTT" | ./ggsci | \
  grep -oP 'Lag\s+\K[\d:]+' | head -1 | awk -F: '{print $1*3600+$2*60+$3}')
if [ "${LAG_SEC:-0}" -gt 300 ]; then
  echo "⚠️ OGG Lag > 5 minutes: ${LAG_SEC}s" | \
    mail -s "ALERT: OGG High Lag" dba-team@company.com
fi
```

---

## Tài liệu tham khảo
- Oracle Data Guard Concepts and Administration 19c
- Oracle GoldenGate Documentation 19c
- QT/DB.01 Phụ lục V, VI — Trần Văn Bình, VietDBA
- MOS Note 1265700.1 (DataGuard best practices)
- www.tranvanbinh.vn
