---
name: oracle-user-privilege-management
description: >
  Quản lý User, Privilege, Role, Profile và Password Oracle.
  Kích hoạt khi hỏi về: tạo user Oracle, create user Oracle,
  gán quyền Oracle, grant revoke Oracle, role Oracle, DBA role,
  CREATE SESSION privilege, system privilege Oracle, object privilege,
  profile Oracle, password policy Oracle, account lock unlock Oracle,
  expired password Oracle, FAILED_LOGIN_ATTEMPTS, PASSWORD_LIFE_TIME,
  password verify function Oracle, proxy authentication Oracle,
  common user CDB Oracle, local user PDB Oracle, c## prefix Oracle,
  user Oracle 12c 19c, minimum privilege principle, quota tablespace.
---

# SK02-04 · Quản lý User, Privilege, Role & Profile

**Phạm vi:** Oracle 11g, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. USER MANAGEMENT

### 1.1 Tạo User

```sql
-- User cơ bản
CREATE USER app_user
  IDENTIFIED BY "SecurePass_2026!"
  DEFAULT TABLESPACE app_data
  TEMPORARY TABLESPACE temp
  QUOTA 10G  ON app_data
  QUOTA 5G   ON app_indx
  QUOTA 0    ON system          -- Không cho tạo objects trong SYSTEM
  QUOTA UNLIMITED ON app_lob
  ACCOUNT UNLOCK
  PASSWORD EXPIRE;              -- Bắt đổi password lần đầu login

-- User với profile (giới hạn resource và password policy)
CREATE USER report_user
  IDENTIFIED BY "Report_2026!"
  DEFAULT TABLESPACE app_data
  TEMPORARY TABLESPACE temp
  QUOTA 0 ON app_data           -- Read-only user: không cần quota
  PROFILE report_profile;

-- User với external authentication (OS level)
CREATE USER ops$oracle
  IDENTIFIED EXTERNALLY AS 'oracle';
-- Kết nối: sqlplus /

-- User với global authentication (LDAP/Active Directory)
CREATE USER ldap_user
  IDENTIFIED GLOBALLY AS 'CN=John Doe,OU=DBA,DC=vietdba,DC=local';

-- CDB: Common User (tồn tại trong tất cả containers)
-- Phải có prefix C## (hoặc theo common_user_prefix parameter)
CREATE USER c##common_dba
  IDENTIFIED BY "Pass_2026!"
  CONTAINER = ALL;

-- PDB: Local User (chỉ tồn tại trong PDB hiện tại)
ALTER SESSION SET CONTAINER = orclpdb;
CREATE USER pdb_app_user
  IDENTIFIED BY "Pass_2026!"
  DEFAULT TABLESPACE users;
```

### 1.2 Alter và Drop User

```sql
-- Đổi password
ALTER USER app_user IDENTIFIED BY "NewPass_2026!";

-- Lock/Unlock account
ALTER USER app_user ACCOUNT LOCK;
ALTER USER app_user ACCOUNT UNLOCK;

-- Expire password (buộc đổi password lần login tiếp)
ALTER USER app_user PASSWORD EXPIRE;

-- Đổi default tablespace
ALTER USER app_user DEFAULT TABLESPACE app_data_v2;

-- Thay đổi quota
ALTER USER app_user QUOTA UNLIMITED ON app_data;
ALTER USER app_user QUOTA 0 ON app_data;  -- Không cho tạo mới (data cũ vẫn còn)

-- Thay đổi profile
ALTER USER app_user PROFILE prod_profile;

-- Drop user (phải không có active sessions)
DROP USER app_user;                  -- Lỗi nếu user có objects
DROP USER app_user CASCADE;         -- Drop kể cả tất cả objects
-- Kiểm tra active sessions trước:
SELECT sid, serial# FROM v$session WHERE username = 'APP_USER';
-- Kill sessions nếu cần:
ALTER SYSTEM KILL SESSION '123,456' IMMEDIATE;
```

### 1.3 Xem thông tin User

```sql
-- Thông tin user
SELECT username,
       user_id,
       account_status,    -- OPEN, LOCKED, EXPIRED & LOCKED, etc.
       lock_date,
       expiry_date,
       default_tablespace,
       temporary_tablespace,
       profile,
       authentication_type,
       common,            -- YES = common user (CDB), NO = local user
       con_id
FROM dba_users
WHERE username NOT IN (
  'SYS','SYSTEM','DBSNMP','SYSMAN','OUTLN','MDSYS','ORDSYS',
  'EXFSYS','DMSYS','WMSYS','CTXSYS','ANONYMOUS','XDB',
  'OLAPSYS','SI_INFORMTN_SCHEMA','ORDPLUGINS','ORDDATA'
)
ORDER BY username;

-- Xem quota
SELECT username, tablespace_name,
       DECODE(max_bytes, -1, 'UNLIMITED',
              ROUND(max_bytes/1024/1024/1024,2)||'GB') max_quota,
       ROUND(bytes/1024/1024/1024, 2) used_gb
FROM dba_ts_quotas
WHERE username = 'APP_USER';

-- Sessions của user
SELECT sid, serial#, status, osuser, machine, program,
       logon_time, last_call_et
FROM v$session
WHERE username = 'APP_USER';
```

---

## 2. PRIVILEGE MANAGEMENT

### 2.1 System Privileges

```sql
-- System privilege: quyền thực hiện hành động trên DB
-- Ví dụ: CREATE SESSION, CREATE TABLE, ALTER SYSTEM, DBA

-- Grant system privilege
GRANT CREATE SESSION TO app_user;
GRANT CREATE TABLE, CREATE VIEW, CREATE PROCEDURE TO app_user;
GRANT CREATE SEQUENCE, CREATE TRIGGER TO app_user;

-- Grant với ADMIN OPTION (user có thể grant tiếp cho người khác)
GRANT CREATE TABLE TO app_user WITH ADMIN OPTION;  -- Cẩn thận!

-- Revoke system privilege
REVOKE CREATE TABLE FROM app_user;

-- Xem system privileges của user
SELECT grantee, privilege, admin_option
FROM dba_sys_privs
WHERE grantee = 'APP_USER'
ORDER BY privilege;

-- Xem system privileges bao gồm inherited từ roles
SELECT privilege, admin_option, inherited
FROM session_privs
WHERE privilege NOT IN (
  'CREATE SESSION','SET CONTAINER','UNLIMITED TABLESPACE');

-- Danh sách powerful system privileges cần kiểm soát chặt:
-- ALTER SYSTEM, ALTER DATABASE, CREATE ANY TABLE, DROP ANY TABLE
-- GRANT ANY PRIVILEGE, GRANT ANY ROLE, CREATE USER, DROP USER
-- EXECUTE ANY PROCEDURE, SELECT ANY TABLE, CREATE ANY DIRECTORY
```

### 2.2 Object Privileges

```sql
-- Object privilege: quyền trên object cụ thể (table, view, procedure...)
GRANT SELECT ON hr.employees TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON hr.orders TO app_user;
GRANT SELECT ON hr.orders TO app_user WITH GRANT OPTION;  -- Có thể grant tiếp
GRANT EXECUTE ON hr.pkg_orders TO app_user;
GRANT REFERENCES ON hr.customers TO app_user;  -- FK reference

-- Grant trên toàn schema (dùng PL/SQL loop — không có syntax đơn giản)
BEGIN
  FOR obj IN (SELECT object_name, object_type
              FROM dba_objects WHERE owner = 'HR'
              AND object_type IN ('TABLE','VIEW','SEQUENCE')) LOOP
    EXECUTE IMMEDIATE
      'GRANT SELECT ON HR.' || obj.object_name || ' TO APP_USER';
  END LOOP;
END;
/

-- Revoke object privilege
REVOKE SELECT ON hr.employees FROM app_user;
REVOKE ALL ON hr.orders FROM app_user;

-- Xem object privileges được grant
SELECT grantee, owner, table_name, privilege, grantable
FROM dba_tab_privs
WHERE grantee = 'APP_USER'
ORDER BY owner, table_name, privilege;

-- Xem column-level privileges
SELECT grantee, owner, table_name, column_name, privilege
FROM dba_col_privs
WHERE grantee = 'APP_USER';

-- PUBLIC grants (áp dụng cho tất cả users — cẩn thận!)
GRANT SELECT ON hr.lookup_codes TO PUBLIC;  -- Tất cả users đều có thể SELECT
REVOKE SELECT ON hr.lookup_codes FROM PUBLIC;
-- Xem PUBLIC grants nguy hiểm
SELECT table_name, privilege
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
  AND privilege IN ('EXECUTE','INSERT','UPDATE','DELETE')
ORDER BY table_name;
```

---

## 3. ROLE MANAGEMENT

```sql
-- Role: nhóm privileges, gán cho nhiều users cùng lúc

-- Tạo role
CREATE ROLE app_read_role;
CREATE ROLE app_write_role;
CREATE ROLE app_admin_role;
CREATE ROLE audit_role IDENTIFIED BY "AuditRole_123";  -- Role có password

-- Gán privileges vào role
GRANT SELECT ON hr.employees TO app_read_role;
GRANT SELECT ON hr.orders    TO app_read_role;
GRANT SELECT ON hr.customers TO app_read_role;
GRANT CREATE SESSION TO app_read_role;

GRANT app_read_role TO app_write_role;  -- Role có thể include role khác
GRANT INSERT, UPDATE, DELETE ON hr.orders TO app_write_role;

-- Gán role cho user
GRANT app_read_role TO report_user;
GRANT app_write_role TO app_user;
GRANT app_admin_role TO app_user WITH ADMIN OPTION;

-- Set default roles (roles được activate khi login)
ALTER USER app_user DEFAULT ROLE ALL;            -- Tất cả roles
ALTER USER app_user DEFAULT ROLE app_read_role;  -- Chỉ một role
ALTER USER app_user DEFAULT ROLE NONE;           -- Không activate role nào

-- Enable role trong session (khi không phải default)
SET ROLE app_admin_role;
SET ROLE app_admin_role IDENTIFIED BY "AuditRole_123";
SET ROLE ALL;
SET ROLE NONE;

-- Xem roles của user
SELECT grantee, granted_role, admin_option, default_role
FROM dba_role_privs
WHERE grantee = 'APP_USER';

-- Xem privileges trong role
SELECT role, privilege, admin_option
FROM role_sys_privs
WHERE role = 'APP_READ_ROLE';

SELECT role, owner, table_name, privilege
FROM role_tab_privs
WHERE role = 'APP_READ_ROLE';

-- Xem chuỗi role inheritance (đệ quy)
SELECT role FROM role_role_privs
WHERE granted_role = 'APP_WRITE_ROLE';

-- Drop role
DROP ROLE app_read_role;

-- Predefined Oracle roles quan trọng:
-- DBA: gần như tất cả system privileges
-- CONNECT: CREATE SESSION (11g+)
-- RESOURCE: tạo objects (11g+) — không cần UNLIMITED TABLESPACE
-- SELECT_CATALOG_ROLE: đọc data dictionary views
-- EXECUTE_CATALOG_ROLE: execute catalog packages
-- EXP_FULL_DATABASE / IMP_FULL_DATABASE: Export/Import
-- DATAPUMP_EXP_FULL_DATABASE / DATAPUMP_IMP_FULL_DATABASE
```

---

## 4. PROFILE MANAGEMENT

```sql
-- Profile: giới hạn resource sử dụng và password policy

-- Tạo profile cho Application Users
CREATE PROFILE app_profile LIMIT
  -- Password Policy
  FAILED_LOGIN_ATTEMPTS     5          -- Khóa sau 5 lần sai
  PASSWORD_LOCK_TIME        1/24       -- Khóa 1 giờ
  PASSWORD_LIFE_TIME        90         -- Đổi password mỗi 90 ngày
  PASSWORD_REUSE_TIME       365        -- Không được dùng lại trong 1 năm
  PASSWORD_REUSE_MAX        10         -- Không được dùng lại 10 lần gần nhất
  PASSWORD_GRACE_TIME       7          -- 7 ngày gia hạn sau khi expired
  PASSWORD_VERIFY_FUNCTION  ora12c_strong_verify_function  -- Function kiểm tra độ mạnh
  -- Resource limits (cần RESOURCE LIMIT = TRUE)
  SESSIONS_PER_USER         5          -- Tối đa 5 sessions cùng lúc
  CPU_PER_SESSION           UNLIMITED
  CPU_PER_CALL              3000       -- 30 giây CPU/call
  CONNECT_TIME              480        -- Disconnect sau 8 giờ
  IDLE_TIME                 60         -- Disconnect sau 60 phút idle
  LOGICAL_READS_PER_SESSION UNLIMITED
  LOGICAL_READS_PER_CALL    UNLIMITED;

-- Profile cho Service Account (không expire password)
CREATE PROFILE svc_profile LIMIT
  FAILED_LOGIN_ATTEMPTS     UNLIMITED  -- Service account không nên bị khóa tự động
  PASSWORD_LIFE_TIME        UNLIMITED  -- Không expire (quản lý thủ công)
  PASSWORD_REUSE_TIME       UNLIMITED
  PASSWORD_REUSE_MAX        UNLIMITED
  SESSIONS_PER_USER         UNLIMITED
  IDLE_TIME                 UNLIMITED;

-- Profile cho DBA (nghiêm ngặt hơn)
CREATE PROFILE dba_profile LIMIT
  FAILED_LOGIN_ATTEMPTS     3
  PASSWORD_LOCK_TIME        1/24
  PASSWORD_LIFE_TIME        60
  PASSWORD_REUSE_TIME       365
  PASSWORD_REUSE_MAX        20
  PASSWORD_GRACE_TIME       3
  PASSWORD_VERIFY_FUNCTION  ora12c_strong_verify_function
  IDLE_TIME                 30;        -- DBA session idle 30 phút → disconnect

-- Gán profile
ALTER USER app_user PROFILE app_profile;
ALTER USER sys PROFILE dba_profile;   -- Thay đổi cả SYS

-- Bật resource limit (mặc định OFF)
ALTER SYSTEM SET resource_limit = TRUE SCOPE=BOTH;

-- Xem profiles
SELECT profile, resource_name, resource_type, limit
FROM dba_profiles
WHERE profile IN ('APP_PROFILE','DEFAULT','DBA_PROFILE')
ORDER BY profile, resource_name;

-- Xem users với DEFAULT profile (cần kiểm tra thường xuyên)
SELECT username, profile, account_status
FROM dba_users
WHERE profile = 'DEFAULT'
  AND username NOT IN ('SYS','SYSTEM')
ORDER BY username;

-- Drop profile (phải chắc không có user nào dùng)
DROP PROFILE app_profile;
DROP PROFILE app_profile CASCADE;  -- Force drop, users về DEFAULT profile

-- Tùy chỉnh password verify function
CREATE OR REPLACE FUNCTION custom_verify_password(
  username     IN VARCHAR2,
  password     IN VARCHAR2,
  old_password IN VARCHAR2
) RETURN BOOLEAN IS
  v_len  INTEGER;
  v_dig  INTEGER := 0;
  v_upper INTEGER := 0;
  v_lower INTEGER := 0;
  v_special INTEGER := 0;
BEGIN
  v_len := LENGTH(password);
  -- Tối thiểu 12 ký tự
  IF v_len < 12 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Password phải >= 12 ký tự');
  END IF;
  -- Phải có chữ hoa, thường, số, ký tự đặc biệt
  FOR i IN 1..v_len LOOP
    IF SUBSTR(password, i, 1) BETWEEN '0' AND '9' THEN v_dig := v_dig + 1; END IF;
    IF SUBSTR(password, i, 1) BETWEEN 'A' AND 'Z' THEN v_upper := v_upper + 1; END IF;
    IF SUBSTR(password, i, 1) BETWEEN 'a' AND 'z' THEN v_lower := v_lower + 1; END IF;
    IF INSTR('!@#$%^&*()_+-=[]{}|;:,.<>?/', SUBSTR(password, i, 1)) > 0 THEN
      v_special := v_special + 1;
    END IF;
  END LOOP;
  IF v_dig = 0 THEN RAISE_APPLICATION_ERROR(-20002, 'Phải có ít nhất 1 chữ số'); END IF;
  IF v_upper = 0 THEN RAISE_APPLICATION_ERROR(-20003, 'Phải có chữ in hoa'); END IF;
  IF v_lower = 0 THEN RAISE_APPLICATION_ERROR(-20004, 'Phải có chữ thường'); END IF;
  IF v_special = 0 THEN RAISE_APPLICATION_ERROR(-20005, 'Phải có ký tự đặc biệt'); END IF;
  -- Password không được chứa username
  IF INSTR(UPPER(password), UPPER(username)) > 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'Password không được chứa username');
  END IF;
  RETURN TRUE;
END;
/

-- Gán vào profile
ALTER PROFILE app_profile LIMIT
  PASSWORD_VERIFY_FUNCTION custom_verify_password;
```

---

## 5. KIỂM TRA VÀ SECURITY AUDIT

```sql
-- Users có DBA role (kiểm tra thường xuyên)
SELECT grantee, admin_option
FROM dba_role_privs
WHERE granted_role = 'DBA'
  AND grantee NOT IN ('SYS','SYSTEM','DBA')
ORDER BY grantee;

-- Users có SYSDBA/SYSOPER privilege
SELECT * FROM v$pwfile_users;

-- Default passwords còn tồn tại (nguy hiểm!)
SELECT username, account_status
FROM dba_users_with_defpwd
WHERE account_status = 'OPEN';
-- Fix: ALTER USER <username> IDENTIFIED BY "NewSecurePass!" ACCOUNT UNLOCK;

-- Users OPEN không login trong 90 ngày
SELECT username, account_status,
       ROUND(SYSDATE - NVL(last_login, created)) days_since_login
FROM dba_users
WHERE account_status = 'OPEN'
  AND username NOT IN ('SYS','SYSTEM','DBSNMP')
  AND (last_login IS NULL OR last_login < SYSDATE - 90)
ORDER BY days_since_login DESC;

-- Privilege creep — users có quá nhiều quyền
SELECT grantee, COUNT(*) priv_count
FROM dba_sys_privs
WHERE grantee NOT IN (
  SELECT role FROM dba_roles)  -- Không tính roles
  AND grantee NOT IN ('SYS','SYSTEM','DBA')
GROUP BY grantee
HAVING COUNT(*) > 20
ORDER BY priv_count DESC;

-- ANY privileges (nguy hiểm nhất)
SELECT grantee, privilege
FROM dba_sys_privs
WHERE privilege LIKE '%ANY%'
  AND grantee NOT IN ('SYS','SYSTEM','DBA','IMP_FULL_DATABASE',
                       'EXP_FULL_DATABASE','DATAPUMP_IMP_FULL_DATABASE',
                       'DATAPUMP_EXP_FULL_DATABASE')
ORDER BY grantee, privilege;

-- Script tạo DDL để revoke quyền thừa
SELECT 'REVOKE ' || privilege || ' FROM ' || grantee || ';'
FROM dba_sys_privs
WHERE privilege LIKE '%ANY%'
  AND grantee = 'APP_USER';
```

---

**Tài liệu tham khảo:**
- Oracle Security Guide 19c: Configuring Privilege and Role Authorization
- Oracle Administrator's Guide: Managing Users and Security
- CIS Oracle Database Benchmark
- www.tranvanbinh.vn
