---
name: oracle-tde-network-encryption
description: >
  Oracle TDE và Network Encryption toàn diện.
  Kích hoạt khi hỏi về: TDE Oracle, Transparent Data Encryption Oracle,
  Oracle wallet, keystore Oracle TDE, tablespace encryption Oracle,
  column encryption Oracle, master key Oracle, MEK Oracle,
  ADMINISTER KEY MANAGEMENT Oracle, auto-login wallet Oracle,
  key rotation Oracle TDE, TDE RAC DataGuard Oracle,
  TDE export import Oracle, TDE backup RMAN Oracle,
  Oracle Advanced Security encryption, native network encryption Oracle,
  sqlnet.ora encryption SQLNET.ENCRYPTION_SERVER, SSL TLS Oracle,
  TCPS Oracle listener, orapki Oracle certificate, SSL_VERSION Oracle,
  cipher suite Oracle, Oracle client server encryption,
  network encryption required requested accepted, SEC_PROTOCOL_ERROR Oracle.
---

# SK04-02 · TDE & Network Encryption

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. TRANSPARENT DATA ENCRYPTION (TDE)

### 1.1 TDE Architecture

```
TDE Data Flow:
┌─────────────────────────────────────────────────────────┐
│  User SQL → Oracle Engine → Buffer Cache → Datafile     │
│                                              ↑            │
│                                         [Encrypt/Decrypt]│
│                                              ↑            │
│               Tablespace/Column Encryption Key (TEK/CEK) │
│                                              ↑            │
│                    Master Encryption Key (MEK) in Wallet  │
└─────────────────────────────────────────────────────────┘

Keystore types:
  Password Wallet:  Manual open sau DB restart (sản xuất có AVDF/OKV)
  Auto-login:       Tự động mở (file .sso, thuận tiện nhưng portable)
  Local Auto-login: Tự động mở CHỈ trên host này (an toàn hơn)
  HSM:              Hardware Security Module (enterprise)
  OKV:              Oracle Key Vault (centralized key management)

TDE features:
  - Tablespace encryption (19c+: ONLINE, no downtime)
  - Column encryption (10g+)
  - RMAN backup encryption (transparent)
  - DataPump export encryption
  - Redo log encryption (19c+)
```

### 1.2 Setup TDE Keystore

```sql
-- ── Step 1: Cấu hình wallet location ─────────────────────
-- Option A: Dùng wallet_root parameter (12c+, khuyến dùng)
ALTER SYSTEM SET wallet_root = '/u01/oracle/wallet' SCOPE=SPFILE;
ALTER SYSTEM SET tde_configuration = 'KEYSTORE_CONFIGURATION=FILE' SCOPE=SPFILE;
-- RESTART DATABASE

-- Option B: Cấu hình trong sqlnet.ora (legacy)
-- ENCRYPTION_WALLET_LOCATION =
--   (SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=/u01/oracle/wallet)))

-- ── Step 2: Tạo Keystore ──────────────────────────────────
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "WalletPass_2026!Secure";
-- Tạo ewallet.p12 trong thư mục wallet

-- ── Step 3: Open Keystore ────────────────────────────────
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPass_2026!Secure"
  CONTAINER = ALL;   -- Cho tất cả CDB containers

-- ── Step 4: Tạo Master Encryption Key (MEK) ──────────────
ADMINISTER KEY MANAGEMENT SET KEY
  USING TAG 'Initial MEK - 2026 Q1'
  IDENTIFIED BY "WalletPass_2026!Secure"
  WITH BACKUP USING 'mek_initial_backup'
  CONTAINER = ALL;

-- ── Kiểm tra keystore status ─────────────────────────────
SELECT wrl_type, wrl_parameter, status, wallet_type,
       wallet_order, master_key_id, fully_backed_up
FROM v$encryption_wallet;
-- STATUS: OPEN, OPEN_NO_MASTER_KEY, CLOSED, NOT_AVAILABLE
-- WALLET_TYPE: PASSWORD, AUTOLOGIN, UNKNOWN

-- Xem key history
SELECT key_id, tag,
       TO_CHAR(creation_time,'YYYY-MM-DD HH24:MI')   created,
       TO_CHAR(activation_time,'YYYY-MM-DD HH24:MI') activated,
       backed_up, keystore_type, creator
FROM v$encryption_keys
ORDER BY activation_time DESC;
```

### 1.3 Tablespace Encryption

```sql
-- ── Tạo mới encrypted tablespace ─────────────────────────
CREATE TABLESPACE sensitive_pii
  DATAFILE '+DATA' SIZE 20G AUTOEXTEND ON NEXT 1G
  ENCRYPTION USING 'AES256'    -- AES128 | AES192 | AES256 | 3DES168
  DEFAULT STORAGE (ENCRYPT);   -- Tất cả objects sẽ được encrypt

-- ── Encrypt existing tablespace (19c+, ONLINE = no downtime) ──
ALTER TABLESPACE app_data ENCRYPTION ONLINE
  USING 'AES256' ENCRYPT;

-- Theo dõi tiến trình encryption
SELECT target, operation_mode, status,
       ROUND(sofar/totalwork*100, 1) pct_complete,
       elapsed_seconds,
       ROUND(elapsed_seconds * (1 - sofar/totalwork) / 60, 1) est_remaining_min
FROM v$encryption_progress;

-- Offline encryption (cần tablespace offline — cũ hơn 19c)
-- ALTER TABLESPACE app_data OFFLINE;
-- ALTER TABLESPACE app_data ENCRYPTION OFFLINE ENCRYPT;
-- ALTER TABLESPACE app_data ONLINE;

-- ── Decrypt tablespace ────────────────────────────────────
ALTER TABLESPACE sensitive_pii ENCRYPTION ONLINE DECRYPT;

-- ── Thay đổi encryption algorithm ────────────────────────
ALTER TABLESPACE app_data ENCRYPTION ONLINE
  REKEY USING 'AES256';   -- Rekey với algorithm mới

-- ── Kiểm tra encryption status ───────────────────────────
SELECT t.tablespace_name, t.encrypted,
       e.encryptionalg, e.encryptedts, e.status
FROM dba_tablespaces t
LEFT JOIN v$encrypted_tablespaces e ON t.tablespace_name = (
  SELECT ts.name FROM v$tablespace ts WHERE ts.ts# = e.ts#
)
ORDER BY t.tablespace_name;

-- Comprehensive encryption status
SELECT 'KEYSTORE STATUS' section, status || ' (' || wallet_type || ')' detail
FROM v$encryption_wallet
UNION ALL
SELECT 'ENCRYPTED TABLESPACES', COUNT(*) || ' tablespace(s)'
FROM dba_tablespaces WHERE encrypted = 'YES'
UNION ALL
SELECT 'UNENCRYPTED TABLESPACES', COUNT(*) || ' tablespace(s)'
FROM dba_tablespaces WHERE encrypted = 'NO'
  AND tablespace_name NOT IN ('SYSTEM','SYSAUX','TEMP','UNDOTBS1');
```

### 1.4 Column Encryption

```sql
-- ── Column encryption khi tạo table ──────────────────────
CREATE TABLE hr.sensitive_employees (
  employee_id   NUMBER          PRIMARY KEY,
  first_name    VARCHAR2(100),
  last_name     VARCHAR2(100),
  -- NO SALT: có thể tạo index, dùng trong WHERE clause
  tax_id        VARCHAR2(20)    ENCRYPT USING 'AES256' NO SALT,
  ssn           CHAR(9)         ENCRYPT USING 'AES256' NO SALT,
  -- WITH SALT (default): bảo mật hơn, không index được
  bank_account  VARCHAR2(30)    ENCRYPT,
  -- Mỗi dòng khác nhau ngay cả cùng giá trị
  credit_card   VARCHAR2(20)    ENCRYPT USING 'AES256'
);

-- ── Encrypt column trong table hiện có ────────────────────
ALTER TABLE hr.employees MODIFY (
  salary        ENCRYPT USING 'AES256' NO SALT,
  commission_pct ENCRYPT USING 'AES256' NO SALT
);

-- ── Decrypt column ────────────────────────────────────────
ALTER TABLE hr.employees MODIFY (
  salary DECRYPT
);

-- ── Index trên encrypted column (chỉ với NO SALT) ─────────
CREATE INDEX idx_sensitive_emp_ssn ON hr.sensitive_employees(tax_id);
CREATE INDEX idx_emp_salary ON hr.employees(salary);

-- ── Xem column encryption info ────────────────────────────
SELECT owner, table_name, column_name, encryption_alg, salt
FROM dba_encrypted_columns
WHERE owner = 'HR'
ORDER BY table_name, column_name;

-- ── Best practices: Column vs Tablespace ─────────────────
/*
  Tablespace encryption (khuyến dùng cho 19c+):
    ✓ Encrypt tất cả objects trong TBS tự động
    ✓ ONLINE encryption, không cần downtime
    ✓ Transparent với applications
    ✓ Performance overhead thấp hơn column encryption
    ✓ Redo log cũng được encrypt

  Column encryption:
    ✓ Granular control: chỉ encrypt specific columns
    ✗ Không index được (trừ NO SALT)
    ✗ Performance overhead cao hơn
    ✗ Không encrypt redo log entries
    ✓ Vẫn tốt khi chỉ cần protect specific columns
*/
```

### 1.5 Auto-Login Wallet

```sql
-- ── Auto-login wallet ────────────────────────────────────
-- DB tự mở wallet sau restart, không cần DBA mở thủ công
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "WalletPass_2026!Secure";
-- Tạo file: /u01/oracle/wallet/cwallet.sso

-- ── Local Auto-login (safer: tied to this host only) ─────
ADMINISTER KEY MANAGEMENT CREATE LOCAL AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "WalletPass_2026!Secure";
-- File cwallet.sso không portable sang server khác

-- ── Verify auto-login sau restart ────────────────────────
SELECT status, wallet_type FROM v$encryption_wallet;
-- wallet_type = AUTOLOGIN hoặc LOCAL_AUTOLOGIN

-- ── Đổi wallet password ───────────────────────────────────
ADMINISTER KEY MANAGEMENT ALTER KEYSTORE PASSWORD
  IDENTIFIED BY "WalletPass_2026!Secure"
  SET "NewWalletPass_2026!";

-- Cập nhật auto-login sau khi đổi password
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "NewWalletPass_2026!";

-- ── Close wallet ─────────────────────────────────────────
ADMINISTER KEY MANAGEMENT SET KEYSTORE CLOSE
  IDENTIFIED BY "WalletPass_2026!Secure";

-- Open lại sau close
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPass_2026!Secure"
  CONTAINER = ALL;
```

### 1.6 Key Rotation

```sql
-- ── Rotate Master Encryption Key (annual best practice) ───
-- Key cũ được giữ lại để decrypt existing data
ADMINISTER KEY MANAGEMENT SET KEY
  USING TAG 'MEK Annual Rotation 2026-Q2'
  IDENTIFIED BY "WalletPass_2026!Secure"
  WITH BACKUP USING 'pre_rotation_backup_2026q2'
  CONTAINER = ALL;

-- ── Rekey tablespace encryption keys ─────────────────────
-- Thực hiện sau MEK rotation để re-encrypt DEKs với new MEK
ADMINISTER KEY MANAGEMENT REKEY ENCRYPTION KEYS
  USING TAG 'Rekey 2026-Q2'
  IDENTIFIED BY "WalletPass_2026!Secure"
  CONTAINER = ALL;

-- ── Verify rotation ───────────────────────────────────────
SELECT key_id, tag, creator, backed_up,
       TO_CHAR(activation_time,'YYYY-MM-DD HH24:MI') activated
FROM v$encryption_keys
ORDER BY activation_time DESC;

-- ── Backup wallet (CRITICAL) ─────────────────────────────
ADMINISTER KEY MANAGEMENT BACKUP KEYSTORE
  USING 'backup_tag_2026q2'
  IDENTIFIED BY "WalletPass_2026!Secure"
  TO '/backup/wallet/';

-- Kiểm tra không backup wallets chưa backup
SELECT key_id, tag, backed_up
FROM v$encryption_keys
WHERE backed_up = 'NO';
-- Nếu có rows → chạy backup ngay!
```

### 1.7 TDE với RAC và DataGuard

```sql
-- ── TDE trong RAC ─────────────────────────────────────────
-- Tất cả RAC nodes phải có access tới CÙNG wallet
-- Options:
--   1. Shared NFS mount: tất cả nodes mount cùng NFS path
--   2. ASM wallet (19.8+): lưu trong ASM
--   3. Oracle Key Vault: centralized

-- NFS approach: cấu hình wallet_root trỏ tới NFS
ALTER SYSTEM SET wallet_root = '/u01/shared_wallet' SCOPE=SPFILE;
-- /u01/shared_wallet phải được mount trên TẤT CẢ nodes

-- ASM-based wallet (19.8+)
ALTER SYSTEM SET wallet_root = '+DATA' SCOPE=SPFILE;

-- Mở wallet trên TẤT CẢ instances (từ mỗi node)
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPass_2026!Secure"
  CONTAINER = ALL;

-- Verify tất cả nodes
SELECT inst_id, wrl_type, status, wallet_type
FROM gv$encryption_wallet
ORDER BY inst_id;

-- ── TDE trong DataGuard ───────────────────────────────────
-- Standby PHẢI có cùng wallet với Primary
-- OPTION 1: Copy wallet thủ công
-- scp /u01/oracle/wallet/ewallet.p12 oracle@standby:/u01/oracle/wallet/
-- scp /u01/oracle/wallet/cwallet.sso oracle@standby:/u01/oracle/wallet/

-- OPTION 2: Export/Import keys
-- Primary → Export keys:
ADMINISTER KEY MANAGEMENT EXPORT ENCRYPTION KEYS
  WITH SECRET "ExportSecret_2026"
  TO '/tmp/primary_keys_export.p12'
  IDENTIFIED BY "WalletPass_2026!Secure"
  WITH BACKUP;

-- scp /tmp/primary_keys_export.p12 oracle@standby:/tmp/

-- Standby → Import keys:
ADMINISTER KEY MANAGEMENT IMPORT ENCRYPTION KEYS
  WITH SECRET "ExportSecret_2026"
  FROM '/tmp/primary_keys_export.p12'
  IDENTIFIED BY "WalletPass_2026!Secure"
  WITH BACKUP;

-- OPTION 3: Oracle Key Vault (enterprise solution)
-- Cả Primary và Standby kết nối tới cùng OKV cluster
-- Không cần sync wallet thủ công
```

### 1.8 TDE với RMAN và DataPump

```bash
# ── RMAN Backup với TDE ──────────────────────────────────
# Encrypted datafiles được backup as-is (encrypted)
# Wallet phải OPEN khi cần restore

# Encrypt RMAN backup sets
rman target /
CONFIGURE ENCRYPTION FOR DATABASE ON;
CONFIGURE ENCRYPTION ALGORITHM 'AES256';
SET ENCRYPTION IDENTIFIED BY "BackupEncPass_2026!" ONLY;
BACKUP DATABASE PLUS ARCHIVELOG;

# Transparent backup (khi wallet đang open)
BACKUP DATABASE;  # Backup encrypted transparently

# Restore requires wallet open
STARTUP MOUNT;
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPass_2026!Secure";
RESTORE DATABASE;
RECOVER DATABASE;
ALTER DATABASE OPEN;
```

```bash
# ── DataPump Export với Encryption ───────────────────────
expdp system/"Oracle_2026!"@ORCL \
  schemas=HR,SALES \
  directory=DATA_PUMP_DIR \
  dumpfile=hr_sales_encrypted_%U.dmp \
  logfile=export_encrypted.log \
  ENCRYPTION=ALL \
  ENCRYPTION_ALGORITHM=AES256 \
  ENCRYPTION_PASSWORD="DumpPass_2026!"

# Import
impdp system/"Oracle_2026!"@TARGET \
  directory=DATA_PUMP_DIR \
  dumpfile=hr_sales_encrypted_%U.dmp \
  ENCRYPTION_PASSWORD="DumpPass_2026!"
```

---

## 2. NETWORK ENCRYPTION

### 2.1 Native Network Encryption (NNE)

```bash
# NNE encrypts data in transit (không cần certificates)
# Cấu hình trong $ORACLE_HOME/network/admin/sqlnet.ora

# ── Server sqlnet.ora ─────────────────────────────────────
cat >> $ORACLE_HOME/network/admin/sqlnet.ora << 'EOF'
# Oracle Native Network Encryption
# Values: REQUIRED | REQUESTED | ACCEPTED | REJECTED
SQLNET.ENCRYPTION_SERVER            = REQUIRED   # Server yêu cầu
SQLNET.ENCRYPTION_CLIENT            = REQUIRED   # Client yêu cầu
SQLNET.ENCRYPTION_TYPES_SERVER      = (AES256, AES192, AES128)
SQLNET.ENCRYPTION_TYPES_CLIENT      = (AES256, AES192, AES128)

# Crypto Checksum (data integrity)
SQLNET.CRYPTO_CHECKSUM_SERVER       = REQUIRED
SQLNET.CRYPTO_CHECKSUM_CLIENT       = REQUIRED
SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = (SHA256, SHA384, SHA512)
SQLNET.CRYPTO_CHECKSUM_TYPES_CLIENT = (SHA256, SHA384, SHA512)
EOF

# Reload listener
lsnrctl reload LISTENER
```

```sql
-- Kiểm tra encryption cho sessions hiện tại
SELECT s.sid, s.username, s.machine, s.program,
       n.network_service_banner
FROM v$session s
JOIN v$session_connect_info n ON s.sid = n.sid
WHERE n.network_service_banner NOT LIKE 'Oracle Bequeath%'
  AND s.type = 'USER'
  AND n.network_service_banner IS NOT NULL
ORDER BY s.username;
-- Tìm: "AES256 Encryption" / "SHA256 Checksum"

-- Kiểm tra session của mình
SELECT network_service_banner
FROM v$session_connect_info
WHERE sid = SYS_CONTEXT('USERENV','SID');

-- Kiểm tra unencrypted connections (compliance violation)
SELECT s.sid, s.username, s.machine, s.program, s.status
FROM v$session s
WHERE s.type = 'USER'
  AND s.username IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM v$session_connect_info n
    WHERE n.sid = s.sid
      AND n.network_service_banner LIKE '%Encryption%'
  )
ORDER BY s.username;
```

### 2.2 SSL/TLS với TCPS

```bash
# ── Setup Oracle Wallet cho SSL ───────────────────────────

# Tạo wallet
mkdir -p /u01/oracle/ssl_wallet
orapki wallet create -wallet /u01/oracle/ssl_wallet \
  -pwd WalletSSL_2026! -auto_login

# Tạo self-signed certificate (production: dùng CA)
orapki wallet add \
  -wallet /u01/oracle/ssl_wallet \
  -pwd WalletSSL_2026! \
  -dn "CN=db-server.vietdba.vn,OU=DBA,O=VietDBA,C=VN" \
  -keysize 2048 \
  -self_signed \
  -validity 3650

# Export server certificate để distribute cho clients
orapki wallet export \
  -wallet /u01/oracle/ssl_wallet \
  -pwd WalletSSL_2026! \
  -dn "CN=db-server.vietdba.vn,OU=DBA,O=VietDBA,C=VN" \
  -cert /tmp/db_server_cert.pem

# Xem wallet contents
orapki wallet display -wallet /u01/oracle/ssl_wallet

# ── listener.ora: Add TCPS address ───────────────────────
cat >> $ORACLE_HOME/network/admin/listener.ora << 'EOF'
# TCP listener (standard)
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL=TCP)(HOST=db-server.vietdba.vn)(PORT=1521))
    )
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL=TCPS)(HOST=db-server.vietdba.vn)(PORT=2484))
    )
  )

SSL_CLIENT_AUTHENTICATION = FALSE   # TRUE requires client certificates

WALLET_LOCATION =
  (SOURCE=(METHOD=FILE)
    (METHOD_DATA=(DIRECTORY=/u01/oracle/ssl_wallet)))
EOF

# ── Server sqlnet.ora: SSL settings ──────────────────────
cat >> $ORACLE_HOME/network/admin/sqlnet.ora << 'EOF'
# SSL/TLS Settings
SSL_VERSION          = 1.2           # Minimum TLS 1.2 (never < 1.1)
SSL_CIPHER_SUITES    = (
  TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
  TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
  TLS_RSA_WITH_AES_256_CBC_SHA256,
  TLS_RSA_WITH_AES_128_CBC_SHA256
)

WALLET_LOCATION =
  (SOURCE=(METHOD=FILE)
    (METHOD_DATA=(DIRECTORY=/u01/oracle/ssl_wallet)))

# Require SSL for all connections
SQLNET.AUTHENTICATION_SERVICES = (TCPS,BEQ)
EOF

# ── Start listener ────────────────────────────────────────
lsnrctl stop LISTENER
lsnrctl start LISTENER
lsnrctl status LISTENER
```

```bash
# ── Client: Setup client wallet ────────────────────────────
mkdir -p /home/user/oracle_wallet
orapki wallet create -wallet /home/user/oracle_wallet -pwd ClientPwd_2026! -auto_login

# Import server certificate vào client wallet
orapki wallet add \
  -wallet /home/user/oracle_wallet \
  -pwd ClientPwd_2026! \
  -trusted_cert -cert /tmp/db_server_cert.pem

# ── Client tnsnames.ora ───────────────────────────────────
cat >> $TNS_ADMIN/tnsnames.ora << 'EOF'
ORCL_SSL =
  (DESCRIPTION=
    (ADDRESS=(PROTOCOL=TCPS)(HOST=db-server.vietdba.vn)(PORT=2484))
    (CONNECT_DATA=(SERVICE_NAME=ORCL.vietdba.vn))
    (SECURITY=(SSL_SERVER_CERT_DN="CN=db-server.vietdba.vn,OU=DBA,O=VietDBA,C=VN"))
  )
EOF

# ── Client sqlnet.ora ─────────────────────────────────────
cat >> $TNS_ADMIN/sqlnet.ora << 'EOF'
WALLET_LOCATION =
  (SOURCE=(METHOD=FILE)
    (METHOD_DATA=(DIRECTORY=/home/user/oracle_wallet)))
SSL_VERSION = 1.2
EOF

# Test SSL connection
sqlplus user/pass@ORCL_SSL
```

### 2.3 Connection Security Controls

```bash
# ── sqlnet.ora: Complete security settings ────────────────
cat > $ORACLE_HOME/network/admin/sqlnet.ora << 'EOF'
# Oracle Net Configuration - Secure Production Settings

# Naming
NAMES.DIRECTORY_PATH = (TNSNAMES, HOSTNAME)

# ━━━ NETWORK ENCRYPTION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SQLNET.ENCRYPTION_SERVER            = REQUIRED
SQLNET.ENCRYPTION_CLIENT            = REQUIRED
SQLNET.ENCRYPTION_TYPES_SERVER      = (AES256, AES192, AES128)
SQLNET.ENCRYPTION_TYPES_CLIENT      = (AES256, AES192, AES128)

SQLNET.CRYPTO_CHECKSUM_SERVER       = REQUIRED
SQLNET.CRYPTO_CHECKSUM_CLIENT       = REQUIRED
SQLNET.CRYPTO_CHECKSUM_TYPES_SERVER = (SHA256, SHA512)
SQLNET.CRYPTO_CHECKSUM_TYPES_CLIENT = (SHA256, SHA512)

# ━━━ TIMEOUTS AND SECURITY ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SQLNET.EXPIRE_TIME              = 10     # Keepalive probe (minutes)
SQLNET.INBOUND_CONNECT_TIMEOUT  = 60     # Connection timeout (seconds)
SQLNET.RECV_TIMEOUT             = 30     # Receive timeout (seconds)
SQLNET.SEND_TIMEOUT             = 30     # Send timeout (seconds)

# ━━━ NODE RESTRICTIONS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TCP.VALIDNODE_CHECKING          = YES
TCP.INVITED_NODES               = (192.168.1.0/24, 10.10.1.0/24, 127.0.0.1)
# TCP.EXCLUDED_NODES             = (1.2.3.4, 5.6.7.0/24)

# ━━━ SSL/TLS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SSL_VERSION                     = 1.2
SSL_CIPHER_SUITES               = (TLS_RSA_WITH_AES_256_CBC_SHA256,
                                    TLS_RSA_WITH_AES_128_CBC_SHA256)

# ━━━ AUTHENTICATION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SQLNET.AUTHENTICATION_SERVICES  = (NONE)   # Disable OS authentication

# ━━━ LOGGING ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DIAG_ADR_ENABLED                = ON
EOF
```

```sql
-- ── Protocol Error Handling ───────────────────────────────
-- Chống brute force và DoS
ALTER SYSTEM SET sec_max_failed_login_attempts = 3 SCOPE=SPFILE;
-- Disconnect sau 3 failed login attempts

ALTER SYSTEM SET sec_protocol_error_trace_action = LOG SCOPE=BOTH;
-- LOG | ALERT | NONE

ALTER SYSTEM SET sec_protocol_error_further_action =
  '(DELAY,3),(DROP,6)' SCOPE=SPFILE;
-- After error: delay 3s, after 6 errors: drop connection

-- Ẩn Oracle version từ unauthenticated connections
ALTER SYSTEM SET sec_return_server_release_banner = FALSE SCOPE=SPFILE;

-- Kiểm tra SQL*Net security parameters
SELECT name, value FROM v$parameter
WHERE name IN (
  'sec_max_failed_login_attempts',
  'sec_protocol_error_trace_action',
  'sec_protocol_error_further_action',
  'sec_return_server_release_banner',
  'remote_login_passwordfile'
);
```

---

## 3. DATA IN REST vs DATA IN TRANSIT MATRIX

```sql
-- ── Security coverage check ───────────────────────────────
SELECT 'Data at Rest (Tablespaces)' category,
       tablespace_name, encrypted status
FROM dba_tablespaces
WHERE tablespace_name NOT IN ('SYSTEM','SYSAUX','TEMP','UNDOTBS1')
ORDER BY tablespace_name;

-- Network connections check
SELECT s.sid, s.username, s.machine,
       CASE
         WHEN n.network_service_banner LIKE '%AES%'
           THEN '✅ Encrypted (NNE)'
         WHEN n.network_service_banner LIKE '%SSL%'
           THEN '✅ Encrypted (SSL)'
         WHEN s.machine LIKE '%localhost%'
           THEN '⚠️ Local (BEQ - OK)'
         ELSE '❌ UNENCRYPTED!'
       END network_security
FROM v$session s
LEFT JOIN v$session_connect_info n ON s.sid = n.sid
WHERE s.type = 'USER' AND s.username IS NOT NULL
GROUP BY s.sid, s.username, s.machine, n.network_service_banner
ORDER BY 4, s.username;

-- Check DataPump dumps encrypted
SELECT owner, job_name, operation, job_mode,
       CASE state WHEN 'EXECUTING' THEN 'Running'
                  WHEN 'COMPLETED' THEN 'Done'
                  ELSE state END job_state
FROM dba_datapump_jobs
WHERE operation = 'EXPORT';

-- RMAN encryption status
SHOW PARAMETER encrypt;  -- In RMAN
```

---

**Tài liệu tham khảo:**
- Oracle Advanced Security Administrator's Guide 19c
- Oracle TDE Best Practices: MOS Note 1228021.1
- Oracle Network Encryption: docs.oracle.com/network-security
- orapki Reference: docs.oracle.com/orapki
- www.tranvanbinh.vn
