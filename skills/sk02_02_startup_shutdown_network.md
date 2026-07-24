---
name: oracle-startup-shutdown-network
description: >
  Startup, Shutdown Oracle Database và quản lý Listener, Network.
  Kích hoạt khi hỏi về: startup Oracle, shutdown Oracle, mount database,
  nomount Oracle, open database, restrict mode Oracle, startup force,
  shutdown immediate abort transactional, pfile spfile Oracle,
  listener Oracle, lsnrctl, tnsnames.ora, sqlnet.ora, listener.ora,
  listener registration Oracle, service registration Oracle,
  dynamic registration, SCAN listener RAC, local listener,
  Oracle Net, connection string Oracle, connect descriptor,
  easy connect Oracle, ldap Oracle Net, TNS Oracle.
---

# SK02-02 · Startup, Shutdown & Oracle Net

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. STARTUP DATABASE

```sql
-- ── CÁC BƯỚC STARTUP ─────────────────────────────────────
-- NOMOUNT: Instance khởi động, đọc pfile/spfile, tạo SGA, start background processes
-- MOUNT:   Control file được đọc, biết về datafiles và redo logs (chưa mở)
-- OPEN:    Datafiles và redo logs được mở, ready cho user connections

-- STARTUP bình thường (NOMOUNT → MOUNT → OPEN)
STARTUP;

-- Từng bước (khi cần thực hiện thao tác ở từng giai đoạn)
STARTUP NOMOUNT;  -- Chỉ cần khi: tạo DB mới, restore controlfile
ALTER DATABASE MOUNT;   -- Mount control file
ALTER DATABASE OPEN;    -- Open datafiles, redo logs

-- Startup với tham số đặc biệt
STARTUP RESTRICT;          -- Open nhưng chỉ cho user có RESTRICTED SESSION privilege
STARTUP MOUNT EXCLUSIVE;   -- Exclusive mount (không chia sẻ - chỉ non-RAC)
STARTUP FORCE;             -- Shutdown ABORT rồi STARTUP (dùng khi hung)
STARTUP READ ONLY;         -- Open read-only (test, reporting)
STARTUP PFILE='/tmp/initORCL_test.ora';  -- Dùng pfile thay spfile

-- Từ OPEN chuyển về RESTRICT (không cần restart)
ALTER SYSTEM ENABLE RESTRICTED SESSION;
-- Chỉ user có RESTRICTED SESSION có thể kết nối mới
-- User đang kết nối KHÔNG bị disconnect

-- Quay lại bình thường
ALTER SYSTEM DISABLE RESTRICTED SESSION;

-- Kiểm tra trạng thái instance
SELECT instance_name, status, database_status, logins,
       TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI:SS') startup_time,
       ROUND(SYSDATE - startup_time, 2) uptime_days
FROM v$instance;
```

---

## 2. SHUTDOWN DATABASE

```sql
-- ── 4 CHẾ ĐỘ SHUTDOWN ────────────────────────────────────

-- SHUTDOWN NORMAL (rất ít dùng production)
-- Chờ tất cả users disconnect, không chấp nhận kết nối mới
-- Có thể chờ hàng giờ nếu có idle connections
SHUTDOWN NORMAL;

-- SHUTDOWN TRANSACTIONAL (hiếm dùng)
-- Chờ tất cả active transactions commit/rollback, rồi disconnect
-- Không chấp nhận kết nối mới
SHUTDOWN TRANSACTIONAL;

-- SHUTDOWN IMMEDIATE ← KHUYẾN DÙNG cho production
-- Rollback tất cả active transactions
-- Disconnect tất cả sessions ngay lập tức
-- Clean shutdown — không cần crash recovery khi startup lại
SHUTDOWN IMMEDIATE;

-- SHUTDOWN ABORT ← CHỈ DÙNG KHI KHẨN CẤP
-- Dừng instance ngay lập tức như rút điện
-- Cần instance recovery (crash recovery) khi startup lại
-- Dùng khi: SHUTDOWN IMMEDIATE hang, instance không phản hồi
SHUTDOWN ABORT;

-- ── SHUTDOWN SAFETY CHECKLIST ─────────────────────────────
-- Trước khi shutdown production:
-- 1. Thông báo cho users/application team
-- 2. Chờ active transactions quan trọng hoàn thành
-- 3. Tạm dừng application connections
-- 4. Kiểm tra active sessions
SELECT COUNT(*), status FROM v$session
WHERE type = 'USER' AND username IS NOT NULL
GROUP BY status;

-- 5. Kill sessions nếu cần (tùy chính sách)
SELECT 'ALTER SYSTEM KILL SESSION ''' || sid || ',' || serial# || ''' IMMEDIATE;'
FROM v$session
WHERE type = 'USER' AND status = 'ACTIVE' AND username IS NOT NULL;

-- 6. Shutdown
SHUTDOWN IMMEDIATE;
```

---

## 3. LISTENER MANAGEMENT

### 3.1 listener.ora

```bash
# $ORACLE_HOME/network/admin/listener.ora

LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = dbserver01.vietdba.local)(PORT = 1521))
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))
    )
  )

# Tự động đăng ký services (khuyến dùng, không cần SID_LIST)
# Oracle instances sẽ tự đăng ký với listener qua pmon

# Nếu cần static registration (cần cho external procedures, RMAN catalog):
SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = ORCL.vietdba.local)
      (ORACLE_HOME   = /u01/app/oracle/product/19.3.0/dbhome_1)
      (SID_NAME      = ORCL)
    )
  )

# Logging
LOGGING_LISTENER       = ON
LOG_FILE_LISTENER      = /u01/app/oracle/diag/tnslsnr/dbserver01/listener/alert/log.xml
LOG_DIRECTORY_LISTENER = /u01/app/oracle/diag/tnslsnr/dbserver01/listener/alert
```

### 3.2 lsnrctl Commands

```bash
# Start/Stop/Status
lsnrctl start [listener_name]    # Nếu không có tên = LISTENER
lsnrctl stop  [listener_name]
lsnrctl status [listener_name]
lsnrctl reload [listener_name]   # Reload config không downtime

# Xem services đã đăng ký
lsnrctl services [listener_name]

# Dynamic registration (Oracle instance tự đăng ký)
lsnrctl set log_status ON
lsnrctl show log_status

# RAC: Local listener và SCAN listener
# Local listener (trên từng node, xử lý local connections)
lsnrctl status LISTENER_NODE1

# SCAN listener (qua Grid Infrastructure)
srvctl status scan_listener
srvctl start  scan_listener
srvctl config scan_listener

# Multiple listeners trên nhiều ports
lsnrctl start LISTENER_1521
lsnrctl start LISTENER_1522

# Trace listener (để debug)
lsnrctl trace user LISTENER  # user | admin | support | off
```

### 3.3 Dynamic Service Registration

```sql
-- Kiểm tra service registration
SELECT s.name service_name, s.network_name,
       i.instance_name, i.status
FROM v$services s, v$instance i
WHERE 1=1
ORDER BY s.name;

-- Parameter điều khiển registration
SELECT name, value FROM v$parameter
WHERE name IN ('local_listener','remote_listener','service_names');

-- RAC: local_listener phải trỏ đúng VIP
ALTER SYSTEM SET local_listener =
  '(ADDRESS=(PROTOCOL=TCP)(HOST=node1-vip)(PORT=1521))' SCOPE=BOTH;

-- remote_listener trỏ đến SCAN listener
ALTER SYSTEM SET remote_listener = 'orcl-scan:1521' SCOPE=BOTH;

-- Đăng ký services ngay (không chờ pmon cycle)
ALTER SYSTEM REGISTER;

-- Tạo service bổ sung (cho connection pooling, TAF)
EXEC DBMS_SERVICE.CREATE_SERVICE(
  service_name => 'APP_SVC',
  network_name => 'APP_SVC.vietdba.local');
EXEC DBMS_SERVICE.START_SERVICE('APP_SVC');

-- Xem tất cả services
SELECT name, network_name, clb_goal, goal
FROM dba_services
ORDER BY name;
```

---

## 4. TNSNAMES.ORA & SQLNET.ORA

### 4.1 tnsnames.ora

```bash
# $ORACLE_HOME/network/admin/tnsnames.ora
# Hoặc tập trung: /etc/oracle/network/admin/tnsnames.ora

# Basic connection descriptor
ORCL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = dbserver01.vietdba.local)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCL.vietdba.local)
    )
  )

# Failover (cho HA, không phải RAC)
ORCL_HA =
  (DESCRIPTION =
    (FAILOVER = ON)
    (LOAD_BALANCE = OFF)
    (ADDRESS_LIST =
      (ADDRESS = (PROTOCOL=TCP)(HOST=primary-db)(PORT=1521))
      (ADDRESS = (PROTOCOL=TCP)(HOST=standby-db)(PORT=1521))
    )
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCL)
    )
  )

# RAC connection (qua SCAN)
ORCL_RAC =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=orcl-scan.vietdba.local)(PORT=1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = APP_SVC.vietdba.local)
    )
  )

# TAF (Transparent Application Failover) trong tnsnames
ORCL_TAF =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=orcl-scan)(PORT=1521))
    (CONNECT_DATA =
      (SERVICE_NAME = APP_SVC)
      (FAILOVER_MODE =
        (TYPE = SELECT)     # SELECT = resume current query; SESSION = reconnect only
        (METHOD = BASIC)
        (RETRIES = 5)
        (DELAY = 3)
      )
    )
  )

# CDB/PDB connection
ORCLPDB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=dbserver01)(PORT=1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ORCLPDB.vietdba.local)  # PDB service name
    )
  )
```

### 4.2 sqlnet.ora

```bash
# $ORACLE_HOME/network/admin/sqlnet.ora

# Names resolution order
NAMES.DIRECTORY_PATH = (TNSNAMES, ONAMES, HOSTNAME, LDAP)

# Client authentication
SQLNET.AUTHENTICATION_SERVICES = (NONE)  # NTS cho Windows

# Wallet location (TDE, Advanced Security)
WALLET_LOCATION =
  (SOURCE =
    (METHOD = FILE)
    (METHOD_DATA =
      (DIRECTORY = /u01/oracle/wallet)
    )
  )

# Encryption (Oracle Advanced Security - cần license)
SQLNET.ENCRYPTION_SERVER = required   # required | requested | accepted | rejected
SQLNET.ENCRYPTION_CLIENT = required
SQLNET.ENCRYPTION_TYPES_SERVER = (AES256, AES192, AES128)
SQLNET.ENCRYPTION_TYPES_CLIENT = (AES256, AES192, AES128)

# Checksum
SQLNET.CRYPTO_CHECKSUM_SERVER = required
SQLNET.CRYPTO_CHECKSUM_CLIENT = required
SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = (SHA256, SHA384, SHA512)

# Expired password
SQLNET.EXPIRE_TIME = 10            # Keepalive probe mỗi 10 phút
TCP.VALIDNODE_CHECKING = YES       # Check valid nodes
TCP.INVITED_NODES = (192.168.1.0/24, 10.0.0.0/8)  # Whitelist
TCP.EXCLUDED_NODES = (1.2.3.4)    # Blacklist

# Connection timeout
SQLNET.INBOUND_CONNECT_TIMEOUT = 60  # 60 giây timeout

# Log
DIAG_ADR_ENABLED = ON
LOG_DIRECTORY_CLIENT = /u01/oracle/diag/clients
```

### 4.3 Easy Connect

```bash
# Easy Connect (không cần tnsnames.ora)
# Format: user/pass@host:port/service_name
sqlplus scott/tiger@dbserver01:1521/ORCL.vietdba.local

# Easy Connect Plus (19c+) - nhiều options hơn
sqlplus scott/tiger@"dbserver01:1521/ORCL?connect_timeout=10&transport_connect_timeout=3"

# JDBC connection string
# jdbc:oracle:thin:@//dbserver01:1521/ORCL.vietdba.local

# Python cx_Oracle / oracledb
# import oracledb
# conn = oracledb.connect(user='scott', password='tiger',
#   host='dbserver01', port=1521, service_name='ORCL')
```

---

## 5. TROUBLESHOOTING LISTENER

```bash
# Listener không start
lsnrctl start
# Kiểm tra port 1521 đã bị chiếm chưa:
ss -tlnp | grep 1521
lsof -i :1521

# Test kết nối
tnsping ORCL
tnsping ORCL 5  # 5 lần test

# Test từ client
sqlplus user/pass@tns_alias

# ORA-12541: TNS no listener
# → Listener chưa start hoặc sai host/port trong tnsnames
lsnrctl status
cat $ORACLE_HOME/network/admin/tnsnames.ora | grep -A5 ORCL

# ORA-12514: TNS listener does not currently know of service
# → Service chưa đăng ký với listener
lsnrctl services
-- Trong DB:
ALTER SYSTEM REGISTER;
-- Nếu vẫn không, kiểm tra local_listener parameter:
SHOW PARAMETER local_listener;

# ORA-12170: TNS Connect timeout
# → Firewall chặn, hoặc network issue
telnet dbserver01 1521
nc -zv dbserver01 1521

# ORA-01017: invalid username/password
# → Sai password hoặc case-sensitive (12c+ password case-sensitive)
-- Reset password:
ALTER USER scott IDENTIFIED BY tiger;

# Listener log
tail -100 $ORACLE_BASE/diag/tnslsnr/$(hostname)/listener/alert/log.xml
# Hoặc dùng adrci:
adrci> show homes
adrci> set home listener/listener/$(hostname)/listener
adrci> show alert -tail 50
```

---

**Tài liệu tham khảo:**
- Oracle Net Services Administrator's Guide 19c
- Oracle Database Administrator's Guide: Starting/Stopping
- www.tranvanbinh.vn
