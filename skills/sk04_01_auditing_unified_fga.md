---
name: oracle-auditing-unified-traditional-fga
description: >
  Oracle Auditing toàn diện: Unified Auditing, Traditional Audit, Login/Logout,
  DDL Audit, FGA Fine-Grained Auditing, Audit Triggers.
  Kích hoạt khi hỏi về: Oracle audit, bật audit Oracle, unified auditing Oracle,
  CREATE AUDIT POLICY Oracle, DML audit Oracle, privilege audit Oracle,
  audit login Oracle, audit logon logoff Oracle, audit DDL Oracle,
  EVALUATE PER SESSION PER ACCESS, FGA fine-grained auditing DBMS_FGA,
  FGA handler procedure, unified_audit_trail Oracle, audit records Oracle,
  DBMS_AUDIT_MGMT purge Oracle, traditional auditing AUDIT statement Oracle,
  audit by access by session, dba_audit_trail aud$ Oracle,
  audit trigger Oracle, custom audit table Oracle,
  logon trigger logoff trigger DDL trigger Oracle,
  sys.fga_log$ dba_fga_audit_trail, audit condition WHEN Oracle,
  audit policy evaluate per session per instance per access.
---

# SK04-01 · Oracle Auditing: Unified, Traditional, FGA & Triggers

**Phạm vi:** Oracle 11g (Traditional) → 12c+ (Unified) → 23ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. KIẾN TRÚC AUDIT ORACLE

```
Oracle Audit Framework (3 tầng):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1] Unified Auditing (12c+ khuyến dùng)
    ├── CREATE AUDIT POLICY ... ACTIONS/PRIVILEGES
    ├── Condition-based (WHEN), Per-session/access/instance
    ├── Storage: AUDSYS.AUD$UNIFIED → unified_audit_trail
    └── Views: UNIFIED_AUDIT_TRAIL, AUDIT_UNIFIED_POLICIES

[2] Fine-Grained Auditing (FGA, 9i+)
    ├── DBMS_FGA.ADD_POLICY — Audit specific ROWS
    ├── Điều kiện: WHERE clause trên từng row
    ├── Storage: SYS.FGA_LOG$ → dba_fga_audit_trail
    └── Handler: Custom PL/SQL procedure khi audit fires

[3] Traditional Auditing (11g, Mixed Mode)
    ├── AUDIT <statement/privilege/object>
    ├── Storage: SYS.AUD$ (DB) hoặc OS file
    └── Views: DBA_AUDIT_TRAIL, DBA_AUDIT_SESSION

[4] Audit Triggers (Custom)
    ├── AFTER LOGON / BEFORE LOGOFF ON DATABASE
    ├── AFTER DDL ON DATABASE
    ├── AFTER INSERT/UPDATE/DELETE FOR EACH ROW
    └── Custom storage, maximum flexibility
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 2. UNIFIED AUDITING (12c+)

### 2.1 Kiểm tra và Enable

```sql
-- Kiểm tra Unified Auditing mode
SELECT value FROM v$option WHERE parameter = 'Unified Auditing';
-- TRUE  = Pure Unified Auditing (khuyến dùng)
-- FALSE = Mixed Mode (cả Traditional lẫn Unified)

-- Enable Pure Unified Auditing (thực hiện trên OS khi DB offline)
-- cd $ORACLE_HOME/rdbms/lib && make -f ins_rdbms.mk uniaud_on ioracle

-- Kiểm tra policies đang enabled
SELECT policy_name, enabled_option, entity_name, entity_type,
       success, failure, inherited
FROM audit_unified_enabled_policies
ORDER BY policy_name;

-- Kiểm tra tất cả policies đã tạo
SELECT policy_name, audit_option, audit_option_type,
       object_schema, object_name, object_type,
       condition_eval_opt, common
FROM audit_unified_policies
ORDER BY policy_name, audit_option;

-- Predefined Oracle audit policies (mặc định)
SELECT policy_name FROM audit_unified_enabled_policies
WHERE policy_name LIKE 'ORA$%';
-- ORA$LOGON_FAILURES, ORA$ALL_TOPLEVEL_ACTIONS, etc.
```

### 2.2 Tạo DML Audit Policies

```sql
-- ── Policy cho DML trên bảng nhạy cảm ────────────────────
CREATE AUDIT POLICY pol_sensitive_dml
  ACTIONS
    SELECT ON hr.employees,
    INSERT ON hr.employees,
    UPDATE ON hr.employees,
    DELETE ON hr.employees,
    SELECT ON fin.salary_history,
    INSERT ON fin.salary_history,
    UPDATE ON fin.salary_history,
    DELETE ON fin.salary_history,
    EXECUTE ON hr.pkg_payroll
  WHEN 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
        NOT IN (''HR_ADMIN'',''FIN_ADMIN'',''SYS'')'
  EVALUATE PER ACCESS;   -- Ghi audit record mỗi lần access

-- Enable policy cho tất cả users
AUDIT POLICY pol_sensitive_dml;

-- Enable chỉ cho users cụ thể
AUDIT POLICY pol_sensitive_dml BY app_user, reporting_user;

-- Enable khi fail (access denied)
AUDIT POLICY pol_sensitive_dml WHENEVER NOT SUCCESSFUL;

-- Enable khi success
AUDIT POLICY pol_sensitive_dml WHENEVER SUCCESSFUL;

-- ── PER SESSION vs PER ACCESS ────────────────────────────
-- PER SESSION:  1 record/session kể cả access 1000 lần (tiết kiệm storage)
-- PER ACCESS:   1 record/access (chi tiết nhất, tốn storage)
-- PER INSTANCE: 1 record/instance restart (rất ít dùng)

CREATE AUDIT POLICY pol_select_session
  ACTIONS SELECT ON hr.employees
  EVALUATE PER SESSION;  -- 1 session = 1 audit record

CREATE AUDIT POLICY pol_select_access
  ACTIONS SELECT ON hr.employees
  EVALUATE PER ACCESS;   -- Mỗi SELECT = 1 audit record

-- ── Policy với WHEN condition phức tạp ────────────────────
CREATE AUDIT POLICY pol_bulk_select
  ACTIONS SELECT ON sales.orders
  WHEN 'SYS_CONTEXT(''USERENV'',''MODULE'') LIKE ''%EXPORT%''
        OR SYS_CONTEXT(''USERENV'',''IP_ADDRESS'')
           NOT BETWEEN ''10.0.0.1'' AND ''10.0.0.254'''
  EVALUATE PER ACCESS;
AUDIT POLICY pol_bulk_select;

-- Disable / Drop policy
NOAUDIT POLICY pol_sensitive_dml;
DROP AUDIT POLICY pol_sensitive_dml;
```

### 2.3 Audit Login / Logoff

```sql
-- ── Audit tất cả logon / logoff ───────────────────────────
CREATE AUDIT POLICY pol_all_logons
  ACTIONS LOGON, LOGOFF;
AUDIT POLICY pol_all_logons;

-- ── Audit FAILED logins (security monitoring) ─────────────
CREATE AUDIT POLICY pol_failed_logins
  ACTIONS LOGON
  WHENEVER NOT SUCCESSFUL;
AUDIT POLICY pol_failed_logins;

-- ── Audit logins từ IP không tin cậy ─────────────────────
CREATE AUDIT POLICY pol_unknown_ip_logon
  ACTIONS LOGON
  WHEN 'SYS_CONTEXT(''USERENV'',''IP_ADDRESS'') IS NULL
        OR SYS_CONTEXT(''USERENV'',''IP_ADDRESS'')
           NOT LIKE ''192.168.%'''
  EVALUATE PER SESSION;
AUDIT POLICY pol_unknown_ip_logon WHENEVER NOT SUCCESSFUL;

-- ── Audit privileged logins ───────────────────────────────
CREATE AUDIT POLICY pol_priv_logins
  PRIVILEGES SYSDBA, SYSOPER, SYSBACKUP, SYSDG, SYSKM, SYSRAC;
AUDIT POLICY pol_priv_logins;

-- ── Audit after-hours access ──────────────────────────────
CREATE AUDIT POLICY pol_after_hours_logon
  ACTIONS LOGON
  WHEN 'TO_NUMBER(TO_CHAR(SYSDATE,''HH24''))
        NOT BETWEEN 7 AND 20
        OR TO_CHAR(SYSDATE,''DY'') IN (''SAT'',''SUN'')'
  EVALUATE PER SESSION;
AUDIT POLICY pol_after_hours_logon;

-- Query: Failed login attempts report
SELECT db_username,
       userhost,
       COUNT(*) failed_attempts,
       MIN(event_timestamp) first_try,
       MAX(event_timestamp) last_try,
       LISTAGG(DISTINCT TO_CHAR(return_code), ',')
         WITHIN GROUP (ORDER BY return_code) error_codes
FROM unified_audit_trail
WHERE action_name = 'LOGON'
  AND return_code != 0
  AND event_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
GROUP BY db_username, userhost
HAVING COUNT(*) >= 3
ORDER BY failed_attempts DESC;

-- Query: All logon activity
SELECT TO_CHAR(event_timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       db_username, os_username, userhost,
       authentication_type, action_name, return_code,
       client_identifier
FROM unified_audit_trail
WHERE action_name IN ('LOGON','LOGOFF')
  AND event_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
ORDER BY event_timestamp DESC
FETCH FIRST 100 ROWS ONLY;
```

### 2.4 Audit DDL

```sql
-- ── Audit toàn bộ DDL ────────────────────────────────────
CREATE AUDIT POLICY pol_ddl_all
  ACTIONS
    CREATE TABLE, ALTER TABLE, DROP TABLE, TRUNCATE TABLE,
    CREATE INDEX, ALTER INDEX, DROP INDEX,
    CREATE VIEW, DROP VIEW,
    CREATE SEQUENCE, DROP SEQUENCE,
    CREATE PROCEDURE, ALTER PROCEDURE, DROP PROCEDURE,
    CREATE FUNCTION, ALTER FUNCTION, DROP FUNCTION,
    CREATE PACKAGE, ALTER PACKAGE, DROP PACKAGE,
    CREATE PACKAGE BODY, DROP PACKAGE BODY,
    CREATE TRIGGER, ALTER TRIGGER, DROP TRIGGER,
    CREATE TYPE, ALTER TYPE, DROP TYPE,
    CREATE SYNONYM, DROP SYNONYM,
    CREATE DATABASE LINK, DROP DATABASE LINK,
    CREATE MATERIALIZED VIEW, DROP MATERIALIZED VIEW
  EVALUATE PER ACCESS;
AUDIT POLICY pol_ddl_all;

-- ── Audit privilege changes (GRANT/REVOKE) ────────────────
CREATE AUDIT POLICY pol_priv_changes
  ACTIONS
    GRANT, REVOKE,
    CREATE ROLE, DROP ROLE, ALTER ROLE,
    CREATE USER, DROP USER, ALTER USER,
    CREATE PROFILE, DROP PROFILE, ALTER PROFILE
  EVALUATE PER ACCESS;
AUDIT POLICY pol_priv_changes;

-- ── Audit destructive DDL với condition ───────────────────
CREATE AUDIT POLICY pol_drop_objects
  ACTIONS DROP TABLE, TRUNCATE TABLE, DROP INDEX,
          DROP USER, DROP PROCEDURE, DROP PACKAGE
  WHEN 'SYS_CONTEXT(''USERENV'',''SESSION_USER'') != ''SYS'''
  EVALUATE PER ACCESS;
AUDIT POLICY pol_drop_objects;

-- ── Audit DDL trên production schema bởi DBA ─────────────
CREATE AUDIT POLICY pol_dba_on_app
  ACTIONS ALL
  WHEN '1=1'
  EVALUATE PER ACCESS;
AUDIT POLICY pol_dba_on_app
  BY USERS WITH GRANTED ROLES DBA;

-- Query: DDL history
SELECT TO_CHAR(event_timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       db_username, os_username,
       action_name, object_schema, object_name, object_type,
       sql_text, return_code, userhost
FROM unified_audit_trail
WHERE action_name IN (
  'CREATE TABLE','DROP TABLE','ALTER TABLE','TRUNCATE TABLE',
  'CREATE INDEX','DROP INDEX',
  'GRANT','REVOKE',
  'CREATE USER','DROP USER','ALTER USER')
  AND event_timestamp > SYSDATE - 30
ORDER BY event_timestamp DESC;

-- Query: DDL trong giờ cao điểm
SELECT TO_CHAR(event_timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       db_username, action_name, object_name,
       CASE WHEN EXTRACT(HOUR FROM event_timestamp) NOT BETWEEN 8 AND 18
                 OR TO_CHAR(event_timestamp,'DY') IN ('SAT','SUN')
            THEN '⚠️ OFF-HOURS DDL'
            ELSE 'Business hours'
       END time_flag
FROM unified_audit_trail
WHERE action_name IN ('DROP TABLE','TRUNCATE TABLE','DROP USER',
                       'GRANT ANY PRIVILEGE')
  AND event_timestamp > SYSDATE - 7
ORDER BY event_timestamp DESC;
```

### 2.5 Audit System Privileges

```sql
-- ── Audit powerful system privileges ─────────────────────
CREATE AUDIT POLICY pol_dangerous_privs
  PRIVILEGES
    CREATE ANY TABLE, DROP ANY TABLE, ALTER ANY TABLE,
    SELECT ANY TABLE, INSERT ANY TABLE, UPDATE ANY TABLE, DELETE ANY TABLE,
    CREATE ANY PROCEDURE, DROP ANY PROCEDURE, EXECUTE ANY PROCEDURE,
    CREATE ANY INDEX, DROP ANY INDEX,
    GRANT ANY PRIVILEGE, GRANT ANY ROLE, GRANT ANY OBJECT PRIVILEGE,
    BECOME USER,
    ALTER SYSTEM, ALTER DATABASE,
    CREATE ANY DIRECTORY, DROP ANY DIRECTORY,
    EXEMPT ACCESS POLICY,        -- Bypass VPD
    AUDIT SYSTEM,
    SELECT ANY DICTIONARY;
AUDIT POLICY pol_dangerous_privs;

-- ── Audit DBA role members' activities ────────────────────
CREATE AUDIT POLICY pol_dba_role_users
  ACTIONS ALL
  EVALUATE PER ACCESS;
AUDIT POLICY pol_dba_role_users BY USERS WITH GRANTED ROLES DBA;
```

### 2.6 Đọc Unified Audit Trail

```sql
-- ── Xem audit records gần đây ────────────────────────────
SELECT TO_CHAR(event_timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       unified_audit_policies                policy_matched,
       db_username, os_username,
       action_name,
       object_schema, object_name,
       sql_text,
       return_code,        -- 0=success, ORA-error=failure
       userhost, client_identifier,
       authentication_type,
       system_privilege_used,
       execution_id
FROM unified_audit_trail
WHERE event_timestamp > SYSTIMESTAMP - INTERVAL '24' HOUR
ORDER BY event_timestamp DESC
FETCH FIRST 100 ROWS ONLY;

-- ── Top SQL by audit count ────────────────────────────────
SELECT sql_text,
       COUNT(*) audit_count,
       COUNT(DISTINCT db_username) distinct_users,
       MAX(event_timestamp) last_seen
FROM unified_audit_trail
WHERE event_timestamp > SYSDATE - 7
  AND sql_text IS NOT NULL
GROUP BY sql_text
ORDER BY audit_count DESC
FETCH FIRST 20 ROWS ONLY;

-- ── Security Summary Dashboard ────────────────────────────
SELECT 'Total Events (24h)'     metric,
       COUNT(*)||''              value
FROM unified_audit_trail
WHERE event_timestamp > SYSDATE - 1
UNION ALL
SELECT 'Failed Logins (24h)',
       COUNT(*)||''
FROM unified_audit_trail
WHERE action_name = 'LOGON'
  AND return_code != 0
  AND event_timestamp > SYSDATE - 1
UNION ALL
SELECT 'DDL Operations (7d)',
       COUNT(*)||''
FROM unified_audit_trail
WHERE action_name IN ('CREATE TABLE','DROP TABLE','ALTER TABLE',
                       'GRANT','REVOKE')
  AND event_timestamp > SYSDATE - 7
UNION ALL
SELECT 'Off-Hours Access (7d)',
       COUNT(*)||''
FROM unified_audit_trail
WHERE (EXTRACT(HOUR FROM event_timestamp) NOT BETWEEN 7 AND 20
       OR TO_CHAR(event_timestamp,'DY') IN ('SAT','SUN'))
  AND event_timestamp > SYSDATE - 7;
```

---

## 3. FINE-GRAINED AUDITING (FGA)

### 3.1 FGA Policies với DBMS_FGA

```sql
-- ── FGA: Audit SELECT khi access sensitive columns ────────
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_SALARY_ACCESS',
    -- Chỉ audit khi query access columns này
    audit_column    => 'SALARY,COMMISSION_PCT,ANNUAL_SALARY',
    -- Điều kiện: audit khi user KHÔNG phải HR authorized
    audit_condition => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
                        NOT IN (''HR_ADMIN'',''PAYROLL'',''SYS'')',
    -- Handler: gọi procedure khi audit fires
    handler_schema  => 'SEC_ADMIN',
    handler_module  => 'PKG_SECURITY.FGA_HANDLER',
    enable          => TRUE,
    statement_types => 'SELECT,UPDATE',   -- SELECT | INSERT | UPDATE | DELETE
    audit_trail     => DBMS_FGA.DB        -- DB | OS | DB+EXTENDED | XML
                     + DBMS_FGA.EXTENDED  -- EXTENDED: include SQL text
  );
END;
/

-- ── FGA với AMOUNT threshold (large transactions) ─────────
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'FIN',
    object_name     => 'TRANSACTIONS',
    policy_name     => 'FGA_LARGE_TXN_AUDIT',
    audit_condition => 'AMOUNT > 500000000',  -- > 500M VND
    audit_column    => 'AMOUNT,ACCOUNT_NO,RECIPIENT',
    handler_schema  => 'SEC_ADMIN',
    handler_module  => 'PKG_SECURITY.HIGH_RISK_HANDLER',
    enable          => TRUE,
    statement_types => 'SELECT,INSERT,UPDATE',
    audit_trail     => DBMS_FGA.DB + DBMS_FGA.EXTENDED
  );
END;
/

-- ── FGA cho VIP customer data ─────────────────────────────
BEGIN
  DBMS_FGA.ADD_POLICY(
    object_schema   => 'SALES',
    object_name     => 'CUSTOMERS',
    policy_name     => 'FGA_VIP_CUSTOMERS',
    audit_condition => 'TIER = ''PLATINUM''
                        OR CREDIT_LIMIT > 1000000000',
    audit_column    => 'CREDIT_LIMIT,PAYMENT_METHOD,BANK_ACCOUNT,CONTACT',
    enable          => TRUE,
    statement_types => 'SELECT,INSERT,UPDATE',
    audit_trail     => DBMS_FGA.DB + DBMS_FGA.EXTENDED
  );
END;
/

-- ── FGA Handler Procedure ─────────────────────────────────
CREATE OR REPLACE PACKAGE sec_admin.pkg_security AS
  PROCEDURE fga_handler(
    p_schema IN VARCHAR2,
    p_object IN VARCHAR2,
    p_policy IN VARCHAR2
  );
  PROCEDURE high_risk_handler(
    p_schema IN VARCHAR2,
    p_object IN VARCHAR2,
    p_policy IN VARCHAR2
  );
END pkg_security;
/

CREATE OR REPLACE PACKAGE BODY sec_admin.pkg_security AS

  PROCEDURE fga_handler(
    p_schema IN VARCHAR2,
    p_object IN VARCHAR2,
    p_policy IN VARCHAR2
  ) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
    v_sql    VARCHAR2(4000);
    v_module VARCHAR2(200);
  BEGIN
    v_module := SYS_CONTEXT('USERENV','MODULE');
    v_sql    := SUBSTR(SYS_CONTEXT('USERENV','CURRENT_SQL'), 1, 3990);

    INSERT INTO sec_admin.fga_alert_log (
      alert_time, db_user, os_user, client_ip,
      client_program, object_accessed, policy_name,
      sql_text, session_id
    ) VALUES (
      SYSTIMESTAMP,
      SYS_CONTEXT('USERENV','SESSION_USER'),
      SYS_CONTEXT('USERENV','OS_USER'),
      SYS_CONTEXT('USERENV','IP_ADDRESS'),
      v_module,
      p_schema || '.' || p_object,
      p_policy,
      v_sql,
      SYS_CONTEXT('USERENV','SESSIONID')
    );
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN ROLLBACK;  -- Never fail
  END fga_handler;

  PROCEDURE high_risk_handler(
    p_schema IN VARCHAR2,
    p_object IN VARCHAR2,
    p_policy IN VARCHAR2
  ) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    -- Log to alert table
    fga_handler(p_schema, p_object, p_policy);

    -- Send immediate alert via DBMS_ALERT (requires listener)
    DBMS_ALERT.SIGNAL(
      'SECURITY_ALERT',
      'HIGH RISK: ' || p_policy || ' triggered by ' ||
      SYS_CONTEXT('USERENV','SESSION_USER') ||
      ' from ' || SYS_CONTEXT('USERENV','IP_ADDRESS')
    );
    COMMIT;
  EXCEPTION
    WHEN OTHERS THEN ROLLBACK;
  END high_risk_handler;

END pkg_security;
/

-- ── Manage FGA Policies ───────────────────────────────────
EXEC DBMS_FGA.ENABLE_POLICY('HR','EMPLOYEES','FGA_SALARY_ACCESS');
EXEC DBMS_FGA.DISABLE_POLICY('HR','EMPLOYEES','FGA_SALARY_ACCESS');
EXEC DBMS_FGA.DROP_POLICY('HR','EMPLOYEES','FGA_SALARY_ACCESS');

-- Xem tất cả FGA policies
SELECT object_schema, object_name, policy_name,
       policy_column, policy_text, enabled, statement_types,
       handler_schema || '.' || handler_module handler,
       audit_trail
FROM dba_audit_policies
ORDER BY object_schema, object_name;

-- ── Đọc FGA Audit Trail ──────────────────────────────────
SELECT TO_CHAR(timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       db_user, os_user, userhost,
       object_schema, object_name, policy_name,
       sql_text, ext_name
FROM dba_fga_audit_trail
WHERE timestamp > SYSDATE - 7
ORDER BY timestamp DESC
FETCH FIRST 100 ROWS ONLY;

-- FGA access pattern analysis
SELECT db_user,
       object_schema || '.' || object_name accessed_object,
       policy_name,
       COUNT(*) access_count,
       MIN(timestamp) first_access,
       MAX(timestamp) last_access
FROM dba_fga_audit_trail
WHERE timestamp > SYSDATE - 30
GROUP BY db_user, object_schema, object_name, policy_name
ORDER BY access_count DESC;
```

---

## 4. TRADITIONAL AUDITING (11g / Mixed Mode)

```sql
-- Kiểm tra và enable
SHOW PARAMETER audit_trail;
-- Values: NONE, OS, DB, DB EXTENDED, XML, XML EXTENDED

ALTER SYSTEM SET audit_trail = 'DB,EXTENDED' SCOPE=SPFILE;
-- Cần restart DB sau khi thay đổi

-- ── Statement Auditing ────────────────────────────────────
AUDIT TABLE;                                  -- CREATE/DROP/TRUNCATE TABLE
AUDIT TABLE BY scott BY ACCESS;               -- Chỉ user scott
AUDIT TABLE BY SESSION;                       -- 1 record/session

AUDIT INDEX;                                  -- CREATE/DROP/ALTER INDEX
AUDIT VIEW;                                   -- CREATE/DROP VIEW

-- Login auditing
AUDIT SESSION;                                -- Tất cả logins
AUDIT SESSION BY ACCESS;                      -- Mỗi login = 1 record
AUDIT SESSION WHENEVER NOT SUCCESSFUL;        -- Failed logins only
AUDIT SESSION BY suspect_user BY ACCESS;

-- ── Privilege Auditing ───────────────────────────────────
AUDIT CREATE ANY TABLE BY ACCESS;
AUDIT DROP ANY TABLE BY ACCESS;
AUDIT SELECT ANY TABLE BY APP_USER;
AUDIT GRANT ANY PRIVILEGE BY ACCESS;
AUDIT CREATE USER BY ACCESS;
AUDIT DROP USER BY ACCESS;
AUDIT ALTER USER BY ACCESS;

-- ── Object Auditing ──────────────────────────────────────
AUDIT SELECT ON hr.employees;                 -- SELECT trên table
AUDIT INSERT, UPDATE, DELETE ON hr.employees BY ACCESS;
AUDIT ALL ON hr.salary_history;              -- Tất cả DML

-- ── Disable Auditing ─────────────────────────────────────
NOAUDIT TABLE;
NOAUDIT SESSION;
NOAUDIT SELECT ON hr.employees;
NOAUDIT ALL ON hr.salary_history;

-- ── Xem Traditional Audit Trail ──────────────────────────
SELECT username, os_username, userhost, terminal,
       TO_CHAR(timestamp,'YYYY-MM-DD HH24:MI:SS') ts,
       action_name, obj_name, obj_privilege,
       session_id, returncode,
       sql_text, sql_bind            -- Chỉ có với DB EXTENDED
FROM dba_audit_trail
WHERE timestamp > SYSDATE - 7
ORDER BY timestamp DESC
FETCH FIRST 100 ROWS ONLY;

-- Login failures từ Traditional Audit
SELECT username, userhost, terminal,
       TO_CHAR(timestamp,'YYYY-MM-DD HH24:MI:SS') failed_time,
       returncode error_code
FROM dba_audit_session
WHERE returncode != 0
  AND timestamp > SYSDATE - 1
ORDER BY timestamp DESC;

-- Xem current audit settings
SELECT audit_option, success, failure FROM dba_stmt_audit_opts;
SELECT user_name, audit_option, success, failure
FROM dba_stmt_audit_opts WHERE user_name IS NOT NULL;
SELECT owner, object_name, sel, ins, upd, del, exe
FROM dba_obj_audit_opts WHERE object_name = 'EMPLOYEES';
```

---

## 5. AUDIT TRIGGERS (CUSTOM)

### 5.1 DML Audit Trigger

```sql
-- ── Setup audit table ─────────────────────────────────────
CREATE TABLE custom_audit_log (
  log_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  log_timestamp   TIMESTAMP        DEFAULT SYSTIMESTAMP NOT NULL,
  table_name      VARCHAR2(130)    NOT NULL,
  operation       VARCHAR2(10)     NOT NULL,
  db_user         VARCHAR2(130)    DEFAULT SYS_CONTEXT('USERENV','SESSION_USER'),
  os_user         VARCHAR2(100)    DEFAULT SYS_CONTEXT('USERENV','OS_USER'),
  client_ip       VARCHAR2(50)     DEFAULT SYS_CONTEXT('USERENV','IP_ADDRESS'),
  client_host     VARCHAR2(200)    DEFAULT SYS_CONTEXT('USERENV','HOST'),
  client_program  VARCHAR2(200)    DEFAULT SYS_CONTEXT('USERENV','MODULE'),
  session_id      NUMBER           DEFAULT SYS_CONTEXT('USERENV','SESSIONID'),
  old_values      CLOB,
  new_values      CLOB,
  primary_key_val VARCHAR2(200)
) TABLESPACE audit_tbs;

CREATE INDEX idx_cal_user_ts   ON custom_audit_log(db_user, log_timestamp);
CREATE INDEX idx_cal_table     ON custom_audit_log(table_name, log_timestamp);
CREATE INDEX idx_cal_operation ON custom_audit_log(operation);

-- ── DML Audit Trigger ─────────────────────────────────────
CREATE OR REPLACE TRIGGER trg_employees_full_audit
  AFTER INSERT OR UPDATE OR DELETE ON hr.employees
  FOR EACH ROW
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_op   VARCHAR2(10);
  v_old  CLOB;
  v_new  CLOB;
BEGIN
  v_op := CASE WHEN INSERTING THEN 'INSERT'
               WHEN UPDATING  THEN 'UPDATE'
               WHEN DELETING  THEN 'DELETE' END;

  -- Serialize OLD values as JSON
  IF NOT INSERTING THEN
    v_old := JSON_OBJECT(
      'employee_id'   VALUE :OLD.employee_id,
      'first_name'    VALUE :OLD.first_name,
      'last_name'     VALUE :OLD.last_name,
      'email'         VALUE :OLD.email,
      'hire_date'     VALUE TO_CHAR(:OLD.hire_date,'YYYY-MM-DD'),
      'job_id'        VALUE :OLD.job_id,
      'salary'        VALUE :OLD.salary,
      'department_id' VALUE :OLD.department_id,
      'manager_id'    VALUE :OLD.manager_id
    );
  END IF;

  -- Serialize NEW values as JSON
  IF NOT DELETING THEN
    v_new := JSON_OBJECT(
      'employee_id'   VALUE :NEW.employee_id,
      'first_name'    VALUE :NEW.first_name,
      'last_name'     VALUE :NEW.last_name,
      'email'         VALUE :NEW.email,
      'hire_date'     VALUE TO_CHAR(:NEW.hire_date,'YYYY-MM-DD'),
      'job_id'        VALUE :NEW.job_id,
      'salary'        VALUE :NEW.salary,
      'department_id' VALUE :NEW.department_id,
      'manager_id'    VALUE :NEW.manager_id
    );
  END IF;

  INSERT INTO custom_audit_log (
    table_name, operation, old_values, new_values, primary_key_val
  ) VALUES (
    'HR.EMPLOYEES', v_op, v_old, v_new,
    NVL(TO_CHAR(:NEW.employee_id), TO_CHAR(:OLD.employee_id))
  );
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN
    -- NEVER let audit trigger fail the business transaction!
    ROLLBACK;
    -- Optionally: log to alert log
    -- SYS.DBMS_SYSTEM.KSDWRT(2, 'AUDIT TRIGGER FAILED: ' || SQLERRM);
END trg_employees_full_audit;
/

-- ── Salary change audit (focused trigger) ────────────────
CREATE TABLE salary_change_audit (
  audit_id      NUMBER GENERATED ALWAYS AS IDENTITY,
  employee_id   NUMBER           NOT NULL,
  old_salary    NUMBER           NOT NULL,
  new_salary    NUMBER           NOT NULL,
  change_pct    NUMBER(5,2),
  change_reason VARCHAR2(500),
  changed_by    VARCHAR2(130)    DEFAULT SYS_CONTEXT('USERENV','SESSION_USER'),
  changed_date  TIMESTAMP        DEFAULT SYSTIMESTAMP,
  approved_by   VARCHAR2(130),
  client_ip     VARCHAR2(50)     DEFAULT SYS_CONTEXT('USERENV','IP_ADDRESS')
);

CREATE OR REPLACE TRIGGER trg_salary_audit
  AFTER UPDATE OF salary ON hr.employees
  FOR EACH ROW
  WHEN (OLD.salary != NEW.salary OR NEW.salary IS NULL)
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO salary_change_audit (
    employee_id, old_salary, new_salary,
    change_pct, change_reason, approved_by
  ) VALUES (
    :NEW.employee_id,
    :OLD.salary,
    :NEW.salary,
    ROUND((:NEW.salary - :OLD.salary) / NULLIF(:OLD.salary, 0) * 100, 2),
    SYS_CONTEXT('USERENV','CLIENT_INFO'),   -- App sets reason here
    SYS_CONTEXT('USERENV','CLIENT_IDENTIFIER')
  );
  COMMIT;
EXCEPTION
  WHEN OTHERS THEN ROLLBACK;
END trg_salary_audit;
/
```

### 5.2 Login / Logout Triggers

```sql
-- ── Audit tables cho session tracking ────────────────────
CREATE TABLE session_audit (
  session_id      NUMBER           NOT NULL,
  serial_num      NUMBER,
  event_type      VARCHAR2(10)     NOT NULL,   -- LOGON / LOGOFF
  event_time      TIMESTAMP        DEFAULT SYSTIMESTAMP,
  db_user         VARCHAR2(130),
  os_user         VARCHAR2(100),
  client_ip       VARCHAR2(50),
  client_host     VARCHAR2(200),
  client_program  VARCHAR2(200),
  client_terminal VARCHAR2(200),
  auth_type       VARCHAR2(100),
  logoff_time     TIMESTAMP,
  session_duration_sec NUMBER
);

-- ── AFTER LOGON Trigger ───────────────────────────────────
CREATE OR REPLACE TRIGGER trg_after_logon
  AFTER LOGON ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO session_audit (
    session_id, event_type, db_user, os_user,
    client_ip, client_host, client_program, client_terminal,
    auth_type
  ) VALUES (
    SYS_CONTEXT('USERENV','SESSIONID'),
    'LOGON',
    SYS_CONTEXT('USERENV','SESSION_USER'),
    SYS_CONTEXT('USERENV','OS_USER'),
    SYS_CONTEXT('USERENV','IP_ADDRESS'),
    SYS_CONTEXT('USERENV','HOST'),
    SYS_CONTEXT('USERENV','MODULE'),
    SYS_CONTEXT('USERENV','TERMINAL'),
    SYS_CONTEXT('USERENV','AUTHENTICATION_TYPE')
  );
  COMMIT;

  -- Optional: Alert on suspicious login
  IF SYS_CONTEXT('USERENV','AUTHENTICATION_TYPE') = 'PROXY'
    AND SYS_CONTEXT('USERENV','SESSION_USER') IN ('SYS','SYSTEM')
  THEN
    DBMS_ALERT.SIGNAL('SECURITY_ALERT',
      'Proxy login as SYS/SYSTEM from ' ||
      SYS_CONTEXT('USERENV','IP_ADDRESS'));
    COMMIT;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;  -- Never block login
END trg_after_logon;
/

-- ── BEFORE LOGOFF Trigger ─────────────────────────────────
CREATE OR REPLACE TRIGGER trg_before_logoff
  BEFORE LOGOFF ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_login_time   TIMESTAMP;
  v_duration_sec NUMBER;
BEGIN
  -- Find matching logon record
  BEGIN
    SELECT event_time INTO v_login_time
    FROM session_audit
    WHERE session_id = SYS_CONTEXT('USERENV','SESSIONID')
      AND event_type = 'LOGON'
      AND logoff_time IS NULL
    ORDER BY event_time DESC
    FETCH FIRST 1 ROW ONLY;

    v_duration_sec := EXTRACT(SECOND FROM (SYSTIMESTAMP - v_login_time))
                    + EXTRACT(MINUTE FROM (SYSTIMESTAMP - v_login_time)) * 60
                    + EXTRACT(HOUR   FROM (SYSTIMESTAMP - v_login_time)) * 3600;

    -- Update logon record with logoff time
    UPDATE session_audit
    SET logoff_time = SYSTIMESTAMP,
        session_duration_sec = v_duration_sec
    WHERE session_id = SYS_CONTEXT('USERENV','SESSIONID')
      AND event_type = 'LOGON'
      AND logoff_time IS NULL;

  EXCEPTION
    WHEN NO_DATA_FOUND THEN NULL;
  END;

  -- Insert logoff event
  INSERT INTO session_audit (
    session_id, event_type, db_user, os_user,
    client_ip, client_program
  ) VALUES (
    SYS_CONTEXT('USERENV','SESSIONID'),
    'LOGOFF',
    SYS_CONTEXT('USERENV','SESSION_USER'),
    SYS_CONTEXT('USERENV','OS_USER'),
    SYS_CONTEXT('USERENV','IP_ADDRESS'),
    SYS_CONTEXT('USERENV','MODULE')
  );
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN ROLLBACK;
END trg_before_logoff;
/

-- ── Failed Login Trigger (AFTER SERVERERROR) ──────────────
CREATE TABLE failed_login_log (
  log_id       NUMBER GENERATED ALWAYS AS IDENTITY,
  attempt_time TIMESTAMP DEFAULT SYSTIMESTAMP,
  db_user      VARCHAR2(130),
  os_user      VARCHAR2(100),
  client_ip    VARCHAR2(50),
  client_host  VARCHAR2(200),
  error_code   NUMBER,
  error_msg    VARCHAR2(500)
);

CREATE OR REPLACE TRIGGER trg_failed_login
  AFTER SERVERERROR ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  -- Only capture login-related errors
  IF ORA_IS_SERVERERROR(1017) OR   -- Invalid username/password
     ORA_IS_SERVERERROR(28000) OR  -- Account locked
     ORA_IS_SERVERERROR(28001) OR  -- Password expired
     ORA_IS_SERVERERROR(28003) OR  -- Password verification failed
     ORA_IS_SERVERERROR(28007) THEN -- Password cannot be reused
    INSERT INTO failed_login_log (
      db_user, os_user, client_ip, client_host,
      error_code, error_msg
    ) VALUES (
      SYS_CONTEXT('USERENV','SESSION_USER'),
      SYS_CONTEXT('USERENV','OS_USER'),
      SYS_CONTEXT('USERENV','IP_ADDRESS'),
      SYS_CONTEXT('USERENV','HOST'),
      ORA_SERVER_ERROR(1),
      ORA_SERVER_ERROR_MSG(1)
    );
    COMMIT;
  END IF;
EXCEPTION
  WHEN OTHERS THEN ROLLBACK;
END trg_failed_login;
/
```

### 5.3 DDL Audit Trigger

```sql
-- ── DDL Audit Table ───────────────────────────────────────
CREATE TABLE ddl_audit_log (
  log_id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_time    TIMESTAMP        DEFAULT SYSTIMESTAMP,
  event_type    VARCHAR2(30)     NOT NULL,   -- CREATE, ALTER, DROP, GRANT, etc.
  object_type   VARCHAR2(30),               -- TABLE, INDEX, USER, etc.
  object_owner  VARCHAR2(130),
  object_name   VARCHAR2(128),
  ddl_user      VARCHAR2(130)    DEFAULT USER,
  client_ip     VARCHAR2(50)     DEFAULT SYS_CONTEXT('USERENV','IP_ADDRESS'),
  client_program VARCHAR2(200)   DEFAULT SYS_CONTEXT('USERENV','MODULE'),
  ddl_sql       CLOB,
  is_system     CHAR(1)          DEFAULT 'N'
) TABLESPACE audit_tbs;

CREATE INDEX idx_ddl_user ON ddl_audit_log(ddl_user, event_time);
CREATE INDEX idx_ddl_obj  ON ddl_audit_log(object_owner, object_name);

-- ── DDL Audit Trigger ─────────────────────────────────────
CREATE OR REPLACE TRIGGER trg_ddl_audit
  AFTER DDL ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
  v_sql_text CLOB := '';
  v_sql_arr  DBMS_STANDARD.ORA_NAME_LIST_T;
  v_sql_cnt  NUMBER;
BEGIN
  -- Lấy full DDL SQL text
  BEGIN
    v_sql_cnt := ORA_SQL_TXT(v_sql_arr);
    FOR i IN 1..v_sql_cnt LOOP
      v_sql_text := v_sql_text || v_sql_arr(i);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Skip internal system DDL
  IF ORA_DICT_OBJ_OWNER IN ('SYS','SYSTEM','DBSNMP','OUTLN',
                              'MDSYS','ORDSYS','EXFSYS','DMSYS')
     AND USER IN ('SYS','SYSTEM') THEN
    RETURN;
  END IF;

  INSERT INTO ddl_audit_log (
    event_type, object_type, object_owner, object_name,
    ddl_user, ddl_sql,
    is_system
  ) VALUES (
    ORA_SYSEVENT,           -- CREATE, ALTER, DROP, GRANT, REVOKE, etc.
    ORA_DICT_OBJ_TYPE,      -- TABLE, INDEX, PROCEDURE, USER, etc.
    ORA_DICT_OBJ_OWNER,     -- Schema owner
    ORA_DICT_OBJ_NAME,      -- Object name
    SYS_CONTEXT('USERENV','SESSION_USER'),
    SUBSTR(v_sql_text, 1, 32767),
    CASE WHEN ORA_DICT_OBJ_OWNER IN ('SYS','SYSTEM')
         THEN 'Y' ELSE 'N' END
  );
  COMMIT;

EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK;
    -- Log to OS alert log as last resort
    BEGIN
      SYS.DBMS_SYSTEM.KSDWRT(2,
        'DDL AUDIT TRIGGER ERROR: ' || SQLERRM || ' Event: ' ||
        ORA_SYSEVENT || ' On: ' || ORA_DICT_OBJ_NAME);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END trg_ddl_audit;
/

-- ── DB Startup / Shutdown Triggers ────────────────────────
CREATE TABLE db_lifecycle_log (
  log_id     NUMBER GENERATED ALWAYS AS IDENTITY,
  event_type VARCHAR2(20)    NOT NULL,
  event_time TIMESTAMP       DEFAULT SYSTIMESTAMP,
  event_user VARCHAR2(130)   DEFAULT USER,
  host_name  VARCHAR2(200)   DEFAULT SYS_CONTEXT('USERENV','HOST')
);

CREATE OR REPLACE TRIGGER trg_db_startup_audit
  AFTER STARTUP ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO db_lifecycle_log (event_type, event_user)
  VALUES ('STARTUP', USER);
  COMMIT;
EXCEPTION WHEN OTHERS THEN ROLLBACK;
END;
/

CREATE OR REPLACE TRIGGER trg_db_shutdown_audit
  BEFORE SHUTDOWN ON DATABASE
DECLARE
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO db_lifecycle_log (event_type, event_user)
  VALUES ('SHUTDOWN', USER);
  COMMIT;
EXCEPTION WHEN OTHERS THEN ROLLBACK;
END;
/
```

---

## 6. AUDIT TRAIL MANAGEMENT

```sql
-- ── DBMS_AUDIT_MGMT: Setup ────────────────────────────────
-- Initialize cleanup framework
EXEC DBMS_AUDIT_MGMT.INIT_CLEANUP(
  audit_trail_type         => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
  default_cleanup_interval => 24   -- Cleanup interval: hours
);

-- Set archive timestamp (records older than this will be purged)
EXEC DBMS_AUDIT_MGMT.SET_LAST_ARCHIVE_TIMESTAMP(
  audit_trail_type  => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
  last_archive_time => SYSTIMESTAMP - INTERVAL '90' DAY  -- Keep 90 days
);

-- Manual purge
EXEC DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
  audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
  use_last_arch_timestamp => TRUE
);

-- Create scheduled purge job
BEGIN
  DBMS_AUDIT_MGMT.CREATE_PURGE_JOB(
    audit_trail_type           => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
    audit_trail_purge_interval => 24,
    audit_trail_purge_name     => 'UNIFIED_AUDIT_PURGE_NIGHTLY',
    use_last_arch_timestamp    => TRUE
  );
END;
/

-- Constants cho audit_trail_type:
-- DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED    = Unified audit trail
-- DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD   = Traditional DB audit (AUD$)
-- DBMS_AUDIT_MGMT.AUDIT_TRAIL_FGA_STD   = FGA audit (FGA_LOG$)
-- DBMS_AUDIT_MGMT.AUDIT_TRAIL_ALL        = Tất cả

-- Xem purge jobs
SELECT job_name, job_status, audit_trail_type, audit_trail_purge_interval
FROM dba_audit_mgmt_cleanup_jobs;

-- Drop purge job
EXEC DBMS_AUDIT_MGMT.DROP_PURGE_JOB('UNIFIED_AUDIT_PURGE_NIGHTLY');

-- ── SYSAUX tablespace monitoring ──────────────────────────
SELECT occupant_name,
       ROUND(space_usage_kbytes/1024, 2) space_mb,
       occupant_desc
FROM v$sysaux_occupants
WHERE occupant_name LIKE '%AUDIT%'
ORDER BY space_usage_kbytes DESC;

-- Move audit trail to dedicated tablespace
EXEC DBMS_AUDIT_MGMT.SET_AUDIT_TRAIL_PROPERTY(
  audit_trail_type             => DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
  audit_trail_property         => DBMS_AUDIT_MGMT.TABLESPACE_OPTION,
  audit_trail_property_value   => 'AUDIT_DATA_TBS'  -- Dedicated tablespace
);

-- ── Traditional Audit purge ──────────────────────────────
-- Purge AUD$ (Traditional)
EXEC DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
  audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_AUD_STD,
  use_last_arch_timestamp => FALSE  -- Warning: deletes without archive check
);

-- Purge FGA_LOG$
EXEC DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
  audit_trail_type        => DBMS_AUDIT_MGMT.AUDIT_TRAIL_FGA_STD,
  use_last_arch_timestamp => TRUE
);

-- ── Archive audit trail before purge ─────────────────────
-- Best practice: Export audit records to external storage first
-- Then update last_archive_timestamp
-- Then purge

-- Export to external file (Python/shell script approach)
-- SELECT * FROM unified_audit_trail
-- WHERE event_timestamp < SYSTIMESTAMP - INTERVAL '90' DAY
-- → Write to compressed file on backup storage
-- THEN: UPDATE last_archive_timestamp
-- THEN: CLEAN_AUDIT_TRAIL
```

---

## 7. AUDIT SECURITY REPORTS

```sql
-- ── Report 1: Security Events Summary ────────────────────
SELECT action_name,
       COUNT(*) total,
       SUM(CASE WHEN return_code != 0 THEN 1 ELSE 0 END) failures,
       COUNT(DISTINCT db_username) distinct_users
FROM unified_audit_trail
WHERE event_timestamp > SYSDATE - 7
GROUP BY action_name
HAVING COUNT(*) > 0
ORDER BY total DESC;

-- ── Report 2: User Activity Timeline ─────────────────────
SELECT db_username,
       TO_CHAR(TRUNC(event_timestamp,'HH24'),'YYYY-MM-DD HH24:00') hour_slot,
       COUNT(*) events
FROM unified_audit_trail
WHERE event_timestamp > SYSDATE - 3
GROUP BY db_username, TRUNC(event_timestamp,'HH24')
ORDER BY db_username, hour_slot;

-- ── Report 3: Privilege Escalation Attempts ───────────────
SELECT event_timestamp, db_username, action_name,
       system_privilege_used, object_schema, object_name,
       return_code, sql_text, userhost
FROM unified_audit_trail
WHERE (system_privilege_used IS NOT NULL
       OR action_name IN ('GRANT','REVOKE','CREATE USER','DROP USER','ALTER USER'))
  AND return_code != 0
  AND event_timestamp > SYSDATE - 30
ORDER BY event_timestamp DESC;

-- ── Report 4: Data Exfiltration Detection ─────────────────
SELECT db_username, userhost, client_identifier,
       COUNT(*) select_count,
       COUNT(DISTINCT sql_text) distinct_queries
FROM unified_audit_trail
WHERE action_name = 'SELECT'
  AND object_name IN ('EMPLOYEES','CUSTOMERS','SALARY_HISTORY',
                       'TRANSACTIONS','CREDIT_CARDS')
  AND event_timestamp > SYSDATE - 1
GROUP BY db_username, userhost, client_identifier
HAVING COUNT(*) > 500  -- More than 500 SELECT in 24 hours
ORDER BY select_count DESC;
```

---

**Tài liệu tham khảo:**
- Oracle Database Security Guide 19c: Configuring Audit Policies
- DBMS_FGA Reference: docs.oracle.com/database/oracle/packages/dbms_fga
- DBMS_AUDIT_MGMT Reference
- MOS Note 1299527.1 (Unified Auditing in 12c)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
