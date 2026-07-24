---
name: oracle-dataguard-logical-active-broker
description: >
  Oracle DataGuard Logical Standby, Active DataGuard, và Broker (DGMGRL).
  Kích hoạt khi hỏi về: Logical Standby Oracle, SQL Apply DataGuard,
  LogMiner DataGuard, logical standby database create,
  Active DataGuard Oracle, Active DG read-only with apply,
  far sync instance Oracle, real-time query DataGuard,
  DataGuard Broker DGMGRL, dgmgrl Oracle command,
  CREATE CONFIGURATION DGMGRL, ADD DATABASE DGMGRL,
  ENABLE CONFIGURATION DataGuard, SHOW CONFIGURATION DGMGRL,
  fast-start failover FSFO Oracle, observer DataGuard,
  broker properties DataGuard, EDIT DATABASE DGMGRL,
  DataGuard monitoring dgmgrl, validate database DGMGRL.
---

# SK07-02 · Logical Standby, Active DataGuard & Broker (DGMGRL)

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. LOGICAL STANDBY DATABASE

### 1.1 Kiến trúc Logical Standby

```
Logical Standby khác Physical Standby:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Physical Standby:  Redo Apply (block-for-block, identical structure)
Logical Standby:   SQL Apply (LogMiner decode redo → SQL → execute)

Lợi ích Logical Standby:
  + Có thể OPEN READ WRITE để chứa thêm objects khác
  + Có thể tạo thêm indexes khác với Primary (tune riêng cho reporting)
  + Rolling upgrade database version dễ hơn

Hạn chế:
  - Không hỗ trợ TẤT CẢ datatypes (LONG, object types phức tạp)
  - Performance overhead cao hơn Physical (SQL Apply chậm hơn Redo Apply)
  - Schema phải giống Primary cho tables được replicate
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 1.2 Tạo Logical Standby

```sql
-- ── Bước 1: Kiểm tra tables không support Logical Standby ──
-- Chạy trên Primary trước khi convert
EXEC DBMS_LOGSTDBY.BUILD;

SELECT owner, table_name, bad_column
FROM dba_logstdby_unsupported
ORDER BY owner, table_name;

-- ── Bước 2: Tạo Physical Standby trước (xem SK07-01) ──────
-- Logical Standby BẮT BUỘC phải tạo từ Physical Standby

-- ── Bước 3: Convert Physical → Logical ────────────────────
-- Trên Physical Standby, cancel managed recovery trước:
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;

-- Cần một số archived logs cuối cùng để chuyển đổi
SELECT MAX(sequence#) FROM v$archived_log WHERE applied='YES';

-- Trên Primary: tạo LogMiner dictionary trong redo stream
EXEC DBMS_LOGSTDBY.BUILD;

-- Trên Standby: chuyển sang Logical
ALTER DATABASE RECOVER TO LOGICAL STANDBY ORCL_LOGICAL;

-- Restart instance
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE OPEN RESETLOGS;

-- ── Bước 4: Start SQL Apply ────────────────────────────────
ALTER DATABASE START LOGICAL STANDBY APPLY IMMEDIATE;

-- Verify
SELECT applied_scn, latest_scn, applied_time
FROM v$logstdby_progress;

SELECT * FROM v$logstdby_state;
```

### 1.3 Logical Standby Management

```sql
-- ── Skip table khỏi replication ────────────────────────────
EXEC DBMS_LOGSTDBY.SKIP(
  stmt => 'DML',
  schema_name => 'APP',
  object_name => 'TEMP_STAGING_TABLE'
);

-- ── Thêm objects MỚI vào Logical Standby (không có ở Primary) ──
-- Tables/indexes này chỉ tồn tại ở Standby (cho reporting)
ALTER DATABASE GUARD ALL;  -- Bảo vệ replicated objects khỏi local changes
-- Tạo schema riêng cho local objects:
CREATE TABLESPACE reporting_local DATAFILE '+DATA' SIZE 10G;
ALTER DATABASE GUARD NONE;  -- Tạm tắt guard để tạo local objects
CREATE TABLE reporting.local_summary AS SELECT * FROM app.orders;
ALTER DATABASE GUARD ALL;  -- Bật lại guard

-- ── Monitor SQL Apply ──────────────────────────────────────
SELECT event, status, xidusn, xidslt, xidsqn
FROM dba_logstdby_events
ORDER BY event_timestamp DESC
FETCH FIRST 20 ROWS ONLY;

-- Apply lag
SELECT (SYSDATE - applied_time) * 24 * 60 lag_minutes
FROM v$logstdby_progress;

-- Stop/Start SQL Apply
ALTER DATABASE STOP LOGICAL STANDBY APPLY;
ALTER DATABASE START LOGICAL STANDBY APPLY IMMEDIATE;
```

---

## 2. ACTIVE DATAGUARD (Read-Only with Apply)

```sql
-- Active DataGuard: Standby vừa apply redo VỪA cho phép READ ONLY queries
-- Yêu cầu: Active Data Guard license (Enterprise Edition option)

-- ── Enable Active DG ──────────────────────────────────────
-- Đảm bảo managed recovery đang chạy trước
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- Open Standby READ ONLY (vẫn tiếp tục apply)
ALTER DATABASE OPEN READ ONLY;

-- Hoặc trong 1 lệnh:
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;

-- ── Verify Active DG ──────────────────────────────────────
SELECT open_mode FROM v$database;
-- Phải là: READ ONLY WITH APPLY

SELECT process, status FROM v$managed_standby
WHERE process LIKE 'MRP%';
-- MRP0 phải đang APPLYING_LOG

-- ── Test query trên Active DG ─────────────────────────────
SELECT COUNT(*) FROM app.orders;  -- Should work
-- INSERT INTO app.orders VALUES(...);  -- FAILS: ORA-16000 (read only)

-- ── Far Sync Instance (giảm bandwidth, zero data loss) ────
-- Far Sync: nhận redo SYNC từ Primary, ship ASYNC đến Standby xa
-- Dùng khi Primary-Standby quá xa cho SYNC trực tiếp

-- Tạo Far Sync instance (compute-only, không cần datafiles)
-- Trên Far Sync server:
CREATE CONTROLFILE FOR FAR SYNC INSTANCE 'FAR_SYNC1';

-- Primary: redirect SYNC traffic qua Far Sync
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=FAR_SYNC1 SYNC AFFIRM
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=FAR_SYNC1
   MAX_FAILURE=1' SCOPE=BOTH;

-- Far Sync: forward đến Standby thực sự
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB ASYNC
   VALID_FOR=(STANDBY_LOGFILES,STANDBY_ROLE)
   DB_UNIQUE_NAME=ORCL_STB' SCOPE=BOTH;
```

---

## 3. DATAGUARD BROKER (DGMGRL)

### 3.1 Setup Broker

```sql
-- ── Enable Broker (trên CẢ Primary và Standby) ────────────
ALTER SYSTEM SET dg_broker_start = TRUE SCOPE=BOTH;

-- Kiểm tra broker config file
SHOW PARAMETER dg_broker_config_file;
```

```bash
# ── Kết nối DGMGRL ─────────────────────────────────────────
dgmgrl /
# Hoặc: dgmgrl sys/Oracle_2026!@ORCL

# ── Tạo Configuration ──────────────────────────────────────
DGMGRL> CREATE CONFIGURATION 'ORCL_DG_CONFIG' AS
          PRIMARY DATABASE IS 'ORCL_PRIMARY'
          CONNECT IDENTIFIER IS ORCL;

DGMGRL> ADD DATABASE 'ORCL_STB' AS
          CONNECT IDENTIFIER IS ORCL_STB
          MAINTAINED AS PHYSICAL;

# Đặt protection mode
DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;

# Enable configuration (kích hoạt management)
DGMGRL> ENABLE CONFIGURATION;

# ── Kiểm tra ───────────────────────────────────────────────
DGMGRL> SHOW CONFIGURATION;
DGMGRL> SHOW DATABASE 'ORCL_PRIMARY';
DGMGRL> SHOW DATABASE 'ORCL_STB';
DGMGRL> SHOW DATABASE VERBOSE 'ORCL_STB';

DGMGRL> VALIDATE DATABASE 'ORCL_STB';
```

### 3.2 Broker Properties Management

```bash
# ── Edit database properties ───────────────────────────────
DGMGRL> EDIT DATABASE 'ORCL_STB' SET PROPERTY
          'LogArchiveTrace'='0';

DGMGRL> EDIT DATABASE 'ORCL_STB' SET PROPERTY
          'StandbyFileManagement'='AUTO';

# Set redo transport mode
DGMGRL> EDIT DATABASE 'ORCL_PRIMARY' SET PROPERTY
          'LogXptMode'='SYNC';  -- hoặc ASYNC

# Apply lag threshold cho alerts
DGMGRL> EDIT DATABASE 'ORCL_STB' SET PROPERTY
          'ApplyLagThreshold'='30';  -- 30 giây

DGMGRL> EDIT DATABASE 'ORCL_STB' SET PROPERTY
          'TransportLagThreshold'='30';

# ── Lag monitoring ─────────────────────────────────────────
DGMGRL> SHOW DATABASE 'ORCL_STB' 'ApplyLag';
DGMGRL> SHOW DATABASE 'ORCL_STB' 'TransportLag';
DGMGRL> SHOW DATABASE 'ORCL_STB' StatusReport;

# ── Enable/Disable database trong config ──────────────────
DGMGRL> DISABLE DATABASE 'ORCL_STB';
DGMGRL> ENABLE  DATABASE 'ORCL_STB';

# ── Remove database khỏi configuration ────────────────────
DGMGRL> REMOVE DATABASE 'ORCL_STB';
DGMGRL> REMOVE CONFIGURATION;
```

### 3.3 Fast-Start Failover (FSFO)

```bash
# FSFO: Tự động failover khi Primary down (không cần can thiệp DBA)
# Yêu cầu: Observer process chạy liên tục

# ── Configure FSFO ──────────────────────────────────────────
DGMGRL> EDIT CONFIGURATION SET PROTECTION MODE AS MAXAVAILABILITY;

DGMGRL> ENABLE FAST_START FAILOVER;

DGMGRL> EDIT CONFIGURATION SET PROPERTY
          'FastStartFailoverThreshold'='30';  -- 30 giây trước khi failover

DGMGRL> EDIT DATABASE 'ORCL_STB' SET PROPERTY
          'FastStartFailoverTarget'='ORCL_PRIMARY';

# ── Start Observer (chạy trên server thứ 3, độc lập) ──────
dgmgrl sys/Oracle_2026!@ORCL_OBSERVER_CONN
DGMGRL> START OBSERVER;
# Hoặc background:
DGMGRL> START OBSERVER IN BACKGROUND;

# Observer config file
DGMGRL> SHOW FAST_START FAILOVER;

# ── Verify FSFO status ─────────────────────────────────────
DGMGRL> SHOW CONFIGURATION;
# Fast-Start Failover: ENABLED

DGMGRL> SHOW OBSERVER;
# Observer "observer_host" - Master

# ── Test FSFO (simulate Primary failure) ──────────────────
# Kill Primary instance abruptly, observer sẽ tự động failover
# sau FastStartFailoverThreshold giây

# ── Disable FSFO ───────────────────────────────────────────
DGMGRL> DISABLE FAST_START FAILOVER;
DGMGRL> STOP OBSERVER;
```

### 3.4 Broker Configuration Backup

```bash
# Backup configuration file
# $ORACLE_HOME/dbs/dr1ORCL.dat (primary configuration file)
# $ORACLE_HOME/dbs/dr2ORCL.dat (secondary configuration file)

# Show files location
DGMGRL> SHOW DATABASE 'ORCL_PRIMARY' 'DGConnectIdentifier';

# Export configuration as script for documentation
DGMGRL> SHOW CONFIGURATION VERBOSE;
```

---

## 4. DGMGRL COMPREHENSIVE COMMAND REFERENCE

```bash
# ── Connection ────────────────────────────────────────────
dgmgrl /                          # Connect locally as SYSDBA
dgmgrl sys/pass@ORCL              # Connect remotely

# ── Configuration ─────────────────────────────────────────
CREATE CONFIGURATION 'name' AS PRIMARY DATABASE IS 'db' CONNECT IDENTIFIER IS tns;
ADD DATABASE 'db_name' AS CONNECT IDENTIFIER IS tns MAINTAINED AS PHYSICAL;
ENABLE CONFIGURATION;
DISABLE CONFIGURATION;
REMOVE CONFIGURATION;
SHOW CONFIGURATION [VERBOSE];

# ── Database management ───────────────────────────────────
ADD DATABASE 'name' AS CONNECT IDENTIFIER IS tns;
REMOVE DATABASE 'name';
ENABLE DATABASE 'name';
DISABLE DATABASE 'name';
SHOW DATABASE 'name' [VERBOSE];
SHOW DATABASE 'name' 'PropertyName';
EDIT DATABASE 'name' SET PROPERTY 'Name'='Value';
VALIDATE DATABASE 'name';
VALIDATE DATABASE 'name' SPFILE;

# ── Switchover/Failover ───────────────────────────────────
SWITCHOVER TO 'standby_name';
FAILOVER TO 'standby_name';
FAILOVER TO 'standby_name' IMMEDIATE;

# ── Fast-Start Failover ───────────────────────────────────
ENABLE FAST_START FAILOVER;
DISABLE FAST_START FAILOVER;
SHOW FAST_START FAILOVER;
START OBSERVER;
START OBSERVER IN BACKGROUND;
STOP OBSERVER;
SHOW OBSERVER;

# ── Monitoring ─────────────────────────────────────────────
SHOW DATABASE 'name' StatusReport;
SHOW DATABASE 'name' 'ApplyLag';
SHOW DATABASE 'name' 'TransportLag';
SHOW DATABASE 'name' InconsistentProperties;
SHOW DATABASE 'name' InconsistentLogXptProps;

# ── Templates và scripting ────────────────────────────────
# Export config thành script:
HOST echo "show configuration verbose" | dgmgrl / > dg_backup.txt
```

---

**Tài liệu tham khảo:**
- Oracle Data Guard Broker Guide 19c
- Oracle Active Data Guard documentation
- Oracle SQL Apply Logical Standby Guide
- MOS Note 1582460.1 (Fast-Start Failover Best Practices)
- www.tranvanbinh.vn
