---
name: oracle-security
description: >
  Bảo mật Oracle Database toàn diện. Kích hoạt khi hỏi về:
  bảo mật Oracle, audit Oracle, TDE encryption, transparent data encryption,
  Oracle Database Vault, VPD virtual private database, row level security,
  unified auditing, FGA fine-grained auditing, privilege analysis,
  Oracle Label Security OLS, data masking, SQL Firewall 23ai,
  network encryption SSL TLS Oracle, Oracle Advanced Security,
  hardening Oracle, CIS benchmark Oracle, AVDF audit vault,
  database security assessment, tạo audit policy, kiểm tra quyền Oracle.
---

# SK04 · Bảo mật Oracle Database

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. UNIFIED AUDITING (12c+)

```sql
-- Kiểm tra unified audit bật chưa
SELECT value FROM v$option WHERE parameter = 'Unified Auditing';

-- Tạo audit policy
CREATE AUDIT POLICY pol_sensitive_data
  ACTIONS SELECT ON hr.employees,
           INSERT ON hr.employees,
           UPDATE ON hr.employees,
           DELETE ON hr.employees
  WHEN 'SYS_CONTEXT(''USERENV'',''OS_USER'') != ''oracle'''
  EVALUATE PER SESSION;

AUDIT POLICY pol_sensitive_data;

-- Audit privilege
CREATE AUDIT POLICY pol_sys_privs
  PRIVILEGES CREATE USER, DROP USER,
              ALTER USER, GRANT ANY PRIVILEGE
  ACTIONS GRANT;
AUDIT POLICY pol_sys_privs;

-- Audit unsuccessful logins
CREATE AUDIT POLICY pol_failed_login
  ACTIONS LOGON
  WHEN 'SYS_CONTEXT(''USERENV'',''AUTHENTICATION_TYPE'') IS NULL'
  EVALUATE PER SESSION;
AUDIT POLICY pol_failed_login WHENEVER NOT SUCCESSFUL;

-- Xem audit records
SELECT event_timestamp, db_username, action_name,
       object_schema, object_name, sql_text
FROM unified_audit_trail
WHERE event_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
  AND object_schema = 'HR'
ORDER BY event_timestamp DESC
FETCH FIRST 50 ROWS ONLY;

-- Purge audit trail
BEGIN
  DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
    audit_trail_type       => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
    use_last_arch_timestamp => TRUE);
END;
/
```

---

## 2. TRANSPARENT DATA ENCRYPTION (TDE)

```sql
-- Bước 1: Cấu hình keystore
ADMINISTER KEY MANAGEMENT CREATE KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "WalletPassword_123";

-- Bước 2: Open keystore
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPassword_123";

-- Bước 3: Tạo master key
ADMINISTER KEY MANAGEMENT SET KEY
  IDENTIFIED BY "WalletPassword_123"
  WITH BACKUP;

-- Bước 4: Encrypt tablespace (19c+)
ALTER TABLESPACE sensitive_data ENCRYPTION ONLINE
  USING 'AES256' ENCRYPT;

-- Encrypt column (11g+)
ALTER TABLE hr.employees
  MODIFY (salary ENCRYPT USING 'AES256' NO SALT);

-- Auto-login wallet (không cần mở thủ công sau restart)
ADMINISTER KEY MANAGEMENT CREATE AUTO_LOGIN KEYSTORE
  FROM KEYSTORE '/u01/oracle/wallet'
  IDENTIFIED BY "WalletPassword_123";

-- Xem trạng thái keystore
SELECT wallet_type, wallet_order, status, fully_backed_up
FROM v$encryption_wallet;

-- Xem tablespace encrypted
SELECT tablespace_name, encrypted FROM dba_tablespaces;

-- Key rotation (hàng năm)
ADMINISTER KEY MANAGEMENT SET KEY
  IDENTIFIED BY "WalletPassword_123"
  WITH BACKUP USING 'annual_rotation_2026';
```

---

## 3. VIRTUAL PRIVATE DATABASE (VPD)

```sql
-- Tạo policy function (trả về WHERE clause)
CREATE OR REPLACE FUNCTION fn_orders_security(
  schema_name IN VARCHAR2,
  table_name  IN VARCHAR2
) RETURN VARCHAR2 AS
  v_user VARCHAR2(100) := SYS_CONTEXT('USERENV','SESSION_USER');
BEGIN
  -- Manager thấy tất cả, nhân viên chỉ thấy của mình
  IF v_user = 'MANAGER_USER' THEN
    RETURN '';  -- Không filter
  ELSE
    RETURN 'sales_rep_id = (SELECT rep_id FROM sales_reps WHERE username = ''' ||
           v_user || ''')';
  END IF;
END;
/

-- Apply VPD policy
BEGIN
  DBMS_RLS.ADD_POLICY(
    object_schema   => 'SALES',
    object_name     => 'ORDERS',
    policy_name     => 'pol_orders_rls',
    function_schema => 'SYS',
    policy_function => 'fn_orders_security',
    statement_types => 'SELECT, INSERT, UPDATE, DELETE',
    update_check    => TRUE,
    enable          => TRUE);
END;
/

-- Kiểm tra policies
SELECT object_name, policy_name, function, enable,
       statement_types
FROM dba_policies
WHERE object_name = 'ORDERS';
```

---

## 4. PRIVILEGE ANALYSIS

```sql
-- Bật Privilege Analysis
BEGIN
  DBMS_PRIVILEGE_CAPTURE.CREATE_CAPTURE(
    name          => 'ANALYZE_APP_USER',
    description   => 'Phân tích quyền APP_USER dùng thực tế',
    type          => DBMS_PRIVILEGE_CAPTURE.G_DATABASE,
    condition     => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'') = ''APP_USER''');
  DBMS_PRIVILEGE_CAPTURE.ENABLE_CAPTURE('ANALYZE_APP_USER');
END;
/

-- Sau 1-2 tuần sử dụng bình thường, disable và generate report
EXEC DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('ANALYZE_APP_USER');
EXEC DBMS_PRIVILEGE_CAPTURE.GENERATE_RESULT('ANALYZE_APP_USER');

-- Xem quyền ĐƯỢC DÙNG
SELECT username, used_privilege, object_owner, object_name
FROM dba_used_privs
WHERE capture = 'ANALYZE_APP_USER';

-- Xem quyền KHÔNG dùng (ứng viên để revoke)
SELECT username, used_privilege
FROM dba_unused_privs
WHERE capture = 'ANALYZE_APP_USER';
```

---

## 5. ORACLE SQL FIREWALL (23ai/23c+)

```sql
-- Bật SQL Firewall
EXEC DBMS_SQL_FIREWALL.ENABLE;

-- Bắt đầu capture allowed SQL list cho user
EXEC DBMS_SQL_FIREWALL.CREATE_CAPTURE(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.ENABLE_CAPTURE(username => 'APP_USER');

-- Sau giai đoạn capture (chạy application bình thường 1-2 tuần)
EXEC DBMS_SQL_FIREWALL.STOP_CAPTURE(username => 'APP_USER');

-- Tạo allow list từ capture
EXEC DBMS_SQL_FIREWALL.CREATE_ALLOW_LIST(username => 'APP_USER');

-- Bật enforcement
EXEC DBMS_SQL_FIREWALL.ENABLE_ALLOW_LIST(
  username    => 'APP_USER',
  enforce     => DBMS_SQL_FIREWALL.ENFORCE_SQL,
  block       => TRUE);

-- Xem violations
SELECT username, sql_text, violation_type, fire_time
FROM dba_sql_firewall_violations
ORDER BY fire_time DESC;
```

---

## 6. SECURITY HARDENING CHECKLIST

```sql
-- 1. Tắt default accounts
SELECT username, account_status FROM dba_users
WHERE username IN ('SCOTT','HR','OE','SH','PM','IX','BI')
  AND account_status = 'OPEN';
-- Fix: ALTER USER SCOTT ACCOUNT LOCK;

-- 2. Password policy chặt
SELECT profile, resource_name, limit
FROM dba_profiles
WHERE profile = 'DEFAULT'
  AND resource_name IN (
    'FAILED_LOGIN_ATTEMPTS',
    'PASSWORD_LIFE_TIME',
    'PASSWORD_REUSE_TIME',
    'PASSWORD_VERIFY_FUNCTION');

-- Tạo profile chặt hơn
CREATE PROFILE app_profile LIMIT
  FAILED_LOGIN_ATTEMPTS     5
  PASSWORD_LIFE_TIME        90
  PASSWORD_REUSE_TIME       365
  PASSWORD_REUSE_MAX        10
  PASSWORD_LOCK_TIME        1/24  -- 1 giờ
  PASSWORD_GRACE_TIME       7
  PASSWORD_VERIFY_FUNCTION  ora12c_strong_verify_function;

-- 3. Revoke PUBLIC grants nguy hiểm
SELECT grantee, table_name, privilege
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
  AND privilege = 'EXECUTE'
  AND table_name IN ('UTL_FILE','UTL_HTTP','UTL_SMTP','DBMS_ADVISOR');

-- 4. Kiểm tra DBA role không cần thiết
SELECT grantee, granted_role, admin_option
FROM dba_role_privs
WHERE granted_role = 'DBA'
  AND grantee NOT IN ('SYS','SYSTEM','DBA')
ORDER BY grantee;
```

---

**Tài liệu tham khảo:** Oracle Security Guide 19c, CIS Oracle Benchmark, www.tranvanbinh.vn
