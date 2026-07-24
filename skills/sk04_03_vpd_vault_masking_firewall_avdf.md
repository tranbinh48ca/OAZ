---
name: oracle-vpd-vault-label-masking-firewall-avdf
description: >
  Oracle VPD, Database Vault, Label Security, Data Masking/Redaction,
  SQL Firewall 23ai, Privilege Analysis, AVDF, Security Hardening.
  Kích hoạt khi hỏi về: VPD Oracle Virtual Private Database,
  row level security Oracle RLS, DBMS_RLS add_policy Oracle,
  policy function Oracle VPD, multi-tenant security Oracle VPD,
  Oracle Database Vault realm, command rule Oracle Vault,
  Oracle Database Vault separation of duties, protect DBA Oracle Vault,
  Oracle Label Security OLS, sensitivity label Oracle OLS,
  SA_POLICY_ADMIN OLS, label component level compartment group Oracle,
  Oracle Data Redaction, DBMS_REDACT Oracle, mask data Oracle,
  full partial regex redaction Oracle, Oracle SQL Firewall 23ai,
  DBMS_SQL_FIREWALL Oracle, capture allow list enforce SQL Firewall,
  AVDF Oracle Audit Vault Database Firewall, central audit Oracle,
  Privilege Analysis DBMS_PRIVILEGE_CAPTURE Oracle,
  Oracle security hardening CIS benchmark, security checklist Oracle.
---

# SK04-03 · VPD, Database Vault, Label Security, Data Masking, SQL Firewall & AVDF

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. VIRTUAL PRIVATE DATABASE (VPD)

### 1.1 VPD Concepts

```
VPD = Row-Level Security (RLS) trên Oracle:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. User gửi: SELECT * FROM employees
2. Oracle gọi policy function → trả về WHERE predicate
3. Oracle tự động rewrite:
   SELECT * FROM employees WHERE <policy_predicate>
4. User chỉ thấy filtered rows (transparent)

Policy types:
  STATIC:                  Function chạy 1 lần/session (cache) — nhanh nhất
  SHARED_STATIC:           Shared across users cùng predicate
  CONTEXT_SENSITIVE:       Re-evaluate khi context thay đổi
  SHARED_CONTEXT_SENSITIVE: Context sensitive + shared
  DYNAMIC:                 Re-evaluate mỗi statement — chậm nhất, flexible nhất

Use cases:
  - Multi-tenant SaaS: tenant isolation
  - Row-level security: staff → own department only
  - Data segregation: region-based data partitioning
  - Column masking: hide sensitive columns
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 1.2 Tạo VPD Policies

```sql
-- ── Setup Application Context ─────────────────────────────
CREATE CONTEXT hr_ctx USING pkg_hr_context;

CREATE OR REPLACE PACKAGE pkg_hr_context AS
  PROCEDURE set_context(p_user VARCHAR2, p_dept NUMBER);
END;
/
CREATE OR REPLACE PACKAGE BODY pkg_hr_context AS
  PROCEDURE set_context(p_user VARCHAR2, p_dept NUMBER) AS
  BEGIN
    DBMS_SESSION.SET_CONTEXT('HR_CTX', 'APP_USER',  p_user);
    DBMS_SESSION.SET_CONTEXT('HR_CTX', 'DEPT_ID',   p_dept);
    DBMS_SESSION.SET_CONTEXT('HR_CTX', 'IS_MANAGER',
      CASE WHEN p_dept > 0 THEN 'Y' ELSE 'N' END);
  END;
END;
/

-- ── Policy Function ───────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_emp_security(
  p_schema IN VARCHAR2,
  p_object IN VARCHAR2
) RETURN VARCHAR2 AS
  v_user    VARCHAR2(100) := SYS_CONTEXT('USERENV','SESSION_USER');
  v_dept_id VARCHAR2(10)  := SYS_CONTEXT('HR_CTX','DEPT_ID');
BEGIN
  -- SYS, HR_ADMIN: no restriction
  IF v_user IN ('SYS','SYSTEM','HR_ADMIN','HR_OWNER') THEN
    RETURN '';  -- Empty predicate = see everything
  END IF;

  -- Manager: see own department
  IF SYS_CONTEXT('HR_CTX','IS_MANAGER') = 'Y' AND v_dept_id IS NOT NULL THEN
    RETURN 'department_id = ' || v_dept_id;
  END IF;

  -- Regular employee: see only their own record
  RETURN 'employee_id = (SELECT employee_id FROM hr.user_mapping
                          WHERE username = ''' || v_user || ''')';
END fn_emp_security;
/

-- ── Apply VPD Policy ─────────────────────────────────────
BEGIN
  DBMS_RLS.ADD_POLICY(
    object_schema    => 'HR',
    object_name      => 'EMPLOYEES',
    policy_name      => 'EMP_VPD_POLICY',
    function_schema  => 'SYS',
    policy_function  => 'FN_EMP_SECURITY',
    statement_types  => 'SELECT,INSERT,UPDATE,DELETE',
    update_check     => TRUE,     -- Apply predicate on INSERT/UPDATE target
    enable           => TRUE,
    policy_type      => DBMS_RLS.SHARED_CONTEXT_SENSITIVE,
    -- STATIC: cache per session (fastest for simple cases)
    -- CONTEXT_SENSITIVE: re-eval when context changes
    -- DYNAMIC: re-eval every statement
    namespace        => 'HR_CTX',
    attribute        => 'DEPT_ID'   -- Re-eval khi attribute này thay đổi
  );
END;
/

-- ── Multi-tenant VPD (SaaS pattern) ─────────────────────
CREATE CONTEXT saas_ctx USING pkg_saas_auth;

CREATE OR REPLACE FUNCTION fn_tenant_isolation(
  p_schema IN VARCHAR2,
  p_object IN VARCHAR2
) RETURN VARCHAR2 AS
  v_tenant_id VARCHAR2(50) := SYS_CONTEXT('SAAS_CTX','TENANT_ID');
BEGIN
  IF v_tenant_id IS NULL THEN
    RETURN '1=2';  -- No tenant context = see nothing
  END IF;
  RETURN 'tenant_id = ''' || v_tenant_id || '''';
END;
/

-- Apply to all tenant tables
BEGIN
  FOR tbl IN (
    SELECT table_name FROM user_tables
    WHERE table_name NOT IN ('TENANT_CONFIG','SYSTEM_LOG')
  ) LOOP
    BEGIN
      DBMS_RLS.ADD_POLICY(
        object_schema   => 'SAAS_APP',
        object_name     => tbl.table_name,
        policy_name     => 'TENANT_ISOLATION',
        function_schema => 'SYS',
        policy_function => 'FN_TENANT_ISOLATION',
        statement_types => 'SELECT,INSERT,UPDATE,DELETE',
        update_check    => TRUE,
        policy_type     => DBMS_RLS.SHARED_CONTEXT_SENSITIVE
      );
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Skipped: '||tbl.table_name||': '||SQLERRM);
    END;
  END LOOP;
END;
/

-- ── Column Masking VPD ────────────────────────────────────
-- Trả về NULL WHERE policy → hide columns cho unauthorized users
CREATE OR REPLACE FUNCTION fn_mask_salary(
  p_schema IN VARCHAR2,
  p_object IN VARCHAR2
) RETURN VARCHAR2 AS
BEGIN
  IF SYS_CONTEXT('USERENV','SESSION_USER') NOT IN
     ('HR_ADMIN','FINANCE','PAYROLL') THEN
    RETURN NULL;  -- Policy không filter rows
  END IF;
  RETURN NULL;  -- Authorized users see everything
END;
/

BEGIN
  DBMS_RLS.ADD_POLICY(
    object_schema       => 'HR',
    object_name         => 'EMPLOYEES',
    policy_name         => 'SALARY_COLUMN_MASK',
    function_schema     => 'SYS',
    policy_function     => 'FN_MASK_SALARY',
    statement_types     => 'SELECT',
    policy_type         => DBMS_RLS.SHARED_CONTEXT_SENSITIVE,
    sec_relevant_cols   => 'SALARY,COMMISSION_PCT,ANNUAL_SALARY',
    sec_relevant_cols_opt => DBMS_RLS.ALL_ROWS
    -- ALL_ROWS: show row với masked columns = NULL
    -- (no option): don't show row if accessing masked columns
  );
END;
/

-- ── Manage VPD Policies ───────────────────────────────────
EXEC DBMS_RLS.ENABLE_POLICY('HR','EMPLOYEES','EMP_VPD_POLICY', TRUE);  -- Enable
EXEC DBMS_RLS.ENABLE_POLICY('HR','EMPLOYEES','EMP_VPD_POLICY', FALSE); -- Disable
EXEC DBMS_RLS.DROP_POLICY('HR','EMPLOYEES','EMP_VPD_POLICY');
EXEC DBMS_RLS.REFRESH_POLICY('HR','EMPLOYEES','EMP_VPD_POLICY'); -- Sau khi sửa fn

-- Xem tất cả VPD policies
SELECT object_owner, object_name, policy_name, policy_function,
       stmt_type, enable, static_policy, policy_type, sec_relevant_cols
FROM dba_policies
WHERE object_owner = 'HR'
ORDER BY object_name, policy_name;
```

---

## 2. ORACLE DATABASE VAULT

### 2.1 Enable và Setup

```sql
-- Kiểm tra Database Vault
SELECT * FROM v$option WHERE parameter = 'Oracle Database Vault';
-- VALUE: TRUE = installed

-- Enable Database Vault (cần SYS + DV_OWNER, DV_ACCTMGR accounts)
-- Chạy dvca (Database Vault Configuration Assistant):
-- $ORACLE_HOME/bin/dvca -action option -oh $ORACLE_HOME -jdbc ...

-- Hoặc từ SQL (sau khi DV installed):
EXEC DVSYS.DBMS_MACADM.ENABLE_DV;
-- Restart DB sau khi enable

-- Verify
SELECT name, status FROM dba_dv_status;
-- DV_APP_PROTECTION: TRUE
-- DV_ENABLED: TRUE
```

### 2.2 Realms

```sql
-- Realm = protective zone cho database objects
-- Ngay cả DBA không thể access objects trong realm
-- (trừ khi được authorize)

-- ── Tạo realm ────────────────────────────────────────────
BEGIN
  DVSYS.DBMS_MACADM.CREATE_REALM(
    realm_name    => 'PII_PROTECTION_REALM',
    description   => 'Protect PII data from DBAs and privileged users',
    enabled       => 'Y',
    audit_options => DVSYS.DBMS_MACUTL.G_REALM_AUDIT_FAIL
                  + DVSYS.DBMS_MACUTL.G_REALM_AUDIT_SUCCESS
  );
END;
/

-- ── Add objects vào realm ─────────────────────────────────
BEGIN
  -- Specific table
  DVSYS.DBMS_MACADM.ADD_OBJECT_TO_REALM(
    realm_name   => 'PII_PROTECTION_REALM',
    object_owner => 'HR',
    object_name  => 'EMPLOYEES',
    object_type  => 'TABLE'
  );
  -- All tables in schema
  DVSYS.DBMS_MACADM.ADD_OBJECT_TO_REALM(
    realm_name   => 'PII_PROTECTION_REALM',
    object_owner => 'FIN',
    object_name  => '%',       -- Wildcard: ALL objects
    object_type  => 'TABLE'
  );
  -- Package
  DVSYS.DBMS_MACADM.ADD_OBJECT_TO_REALM(
    realm_name   => 'PII_PROTECTION_REALM',
    object_owner => 'HR',
    object_name  => 'PKG_PAYROLL',
    object_type  => 'PACKAGE'
  );
END;
/

-- ── Authorize participants ────────────────────────────────
BEGIN
  -- Authorized user (access objects in realm)
  DVSYS.DBMS_MACADM.ADD_AUTH_TO_REALM(
    realm_name   => 'PII_PROTECTION_REALM',
    grantee      => 'HR_APP_USER',
    auth_options => DVSYS.DBMS_MACUTL.G_REALM_AUTH_PARTICIPANT
    -- G_REALM_AUTH_OWNER: can grant access to others
    -- G_REALM_AUTH_PARTICIPANT: can access but not grant
  );
  -- Role authorized
  DVSYS.DBMS_MACADM.ADD_AUTH_TO_REALM(
    realm_name   => 'PII_PROTECTION_REALM',
    grantee      => 'HR_AUTHORIZED_ROLE',
    auth_options => DVSYS.DBMS_MACUTL.G_REALM_AUTH_PARTICIPANT
  );
END;
/

-- ── Xem realms ───────────────────────────────────────────
SELECT realm_name, description, enabled, audit_options
FROM dba_dv_realm ORDER BY realm_name;

SELECT grantee, realm_name, auth_options
FROM dba_dv_realm_auth ORDER BY realm_name, grantee;

SELECT realm_name, object_owner, object_name, object_type
FROM dba_dv_realm_object ORDER BY realm_name;
```

### 2.3 Command Rules

```sql
-- Command Rule: control khi nào commands được phép
-- Ví dụ: TRUNCATE chỉ trong maintenance window

-- ── Tạo Rule Set ─────────────────────────────────────────
BEGIN
  DVSYS.DBMS_MACADM.CREATE_RULE_SET(
    rule_set_name  => 'MAINTENANCE_WINDOW_RULESET',
    description    => 'Allow only during scheduled maintenance',
    enabled        => 'Y',
    eval_options   => 1,   -- 1=All rules must be TRUE, 2=Any rule TRUE
    audit_options  => DVSYS.DBMS_MACUTL.G_RULESET_AUDIT_FAIL,
    fail_options   => DVSYS.DBMS_MACUTL.G_RULESET_FAIL_SHOW,
    fail_message   => 'This operation is only allowed during maintenance window',
    fail_code      => -20050
  );

  -- Rule: chỉ cho phép Sat-Sun, 1AM-5AM
  DVSYS.DBMS_MACADM.CREATE_RULE(
    rule_name => 'IS_MAINTENANCE_TIME_RULE',
    rule_expr => 'TO_CHAR(SYSDATE,''DY'') IN (''SAT'',''SUN'')
                  AND TO_NUMBER(TO_CHAR(SYSDATE,''HH24'')) BETWEEN 1 AND 5'
  );

  DVSYS.DBMS_MACADM.ADD_RULE_TO_RULE_SET(
    rule_set_name => 'MAINTENANCE_WINDOW_RULESET',
    rule_name     => 'IS_MAINTENANCE_TIME_RULE'
  );
END;
/

-- ── Tạo Command Rules ────────────────────────────────────
BEGIN
  -- TRUNCATE TABLE chỉ trong maintenance
  DVSYS.DBMS_MACADM.CREATE_COMMAND_RULE(
    command       => 'TRUNCATE TABLE',
    rule_set_name => 'MAINTENANCE_WINDOW_RULESET',
    object_owner  => 'APP',
    object_name   => '%',    -- All tables
    enabled       => 'Y'
  );
  -- DROP TABLE globally restricted
  DVSYS.DBMS_MACADM.CREATE_COMMAND_RULE(
    command       => 'DROP TABLE',
    rule_set_name => 'MAINTENANCE_WINDOW_RULESET',
    object_owner  => '%',
    object_name   => '%',
    enabled       => 'Y'
  );
END;
/

-- ── Xem command rules ────────────────────────────────────
SELECT command, object_owner, object_name, rule_set_name, enabled
FROM dba_dv_command_rule
ORDER BY command;
```

---

## 3. ORACLE LABEL SECURITY (OLS)

```sql
-- Label Security = Mandatory Access Control (MAC)
-- Mỗi row có sensitivity label, user có clearance label
-- Chỉ access được row khi user clearance >= row label

-- ── Setup OLS Policy ─────────────────────────────────────
BEGIN
  SA_SYSDBA.CREATE_POLICY(
    policy_name    => 'DATA_SENSITIVITY',
    column_name    => 'OLS_LABEL',        -- Column thêm vào table
    default_options => 'READ_CONTROL,WRITE_CONTROL,LABEL_DEFAULT'
  );
END;
/

-- ── Tạo Label Components ─────────────────────────────────
-- LEVELS (số lớn = nhạy cảm hơn)
SA_COMPONENTS.CREATE_LEVEL('DATA_SENSITIVITY', 40, 'TOP_SECRET',   'TS');
SA_COMPONENTS.CREATE_LEVEL('DATA_SENSITIVITY', 30, 'SECRET',       'S');
SA_COMPONENTS.CREATE_LEVEL('DATA_SENSITIVITY', 20, 'CONFIDENTIAL', 'C');
SA_COMPONENTS.CREATE_LEVEL('DATA_SENSITIVITY', 10, 'PUBLIC',       'P');

-- COMPARTMENTS (không có hierarchy, độc lập)
SA_COMPONENTS.CREATE_COMPARTMENT('DATA_SENSITIVITY', 100, 'FINANCE',  'FIN');
SA_COMPONENTS.CREATE_COMPARTMENT('DATA_SENSITIVITY', 200, 'HR',       'HR');
SA_COMPONENTS.CREATE_COMPARTMENT('DATA_SENSITIVITY', 300, 'LEGAL',    'LEG');

-- GROUPS (có hierarchy)
SA_COMPONENTS.CREATE_GROUP('DATA_SENSITIVITY', 10, 'VIETNAM', 'VN', NULL);
SA_COMPONENTS.CREATE_GROUP('DATA_SENSITIVITY', 20, 'APAC',   'APAC', 'VN');
SA_COMPONENTS.CREATE_GROUP('DATA_SENSITIVITY', 30, 'GLOBAL', 'GLOB', 'APAC');

-- ── Tạo Labels ───────────────────────────────────────────
-- Format: LEVEL:COMPARTMENTS:GROUPS
SA_LABEL_ADMIN.CREATE_LABEL('DATA_SENSITIVITY', 1001, 'PUBLIC',             TRUE);
SA_LABEL_ADMIN.CREATE_LABEL('DATA_SENSITIVITY', 1002, 'CONFIDENTIAL:HR:VN', TRUE);
SA_LABEL_ADMIN.CREATE_LABEL('DATA_SENSITIVITY', 1003, 'SECRET:HR,FIN:APAC', TRUE);
SA_LABEL_ADMIN.CREATE_LABEL('DATA_SENSITIVITY', 1004, 'TOP_SECRET:HR,FIN,LEG:GLOBAL', TRUE);

-- ── Apply Policy to Table ──────────────────────────────────
SA_POLICY_ADMIN.APPLY_TABLE_POLICY(
  policy_name   => 'DATA_SENSITIVITY',
  schema_name   => 'HR',
  table_name    => 'EMPLOYEES',
  table_options => 'LABEL_DEFAULT,READ_CONTROL,WRITE_CONTROL'
);

-- ── Grant User Labels ─────────────────────────────────────
SA_USER_ADMIN.SET_USER_LABELS(
  policy_name    => 'DATA_SENSITIVITY',
  user_name      => 'HR_STAFF',
  max_read_label  => 'SECRET:HR:VN',        -- Max they can read
  max_write_label => 'CONFIDENTIAL:HR:VN',  -- Max they can write
  def_label       => 'CONFIDENTIAL:HR:VN',  -- Default for new rows
  row_label       => 'CONFIDENTIAL:HR:VN'
);

SA_USER_ADMIN.SET_USER_LABELS(
  policy_name    => 'DATA_SENSITIVITY',
  user_name      => 'HR_ADMIN',
  max_read_label  => 'TOP_SECRET:HR,FIN,LEG:GLOBAL',
  max_write_label => 'SECRET:HR:APAC',
  def_label       => 'CONFIDENTIAL:HR:VN',
  row_label       => NULL  -- Use max_write as row label
);

-- Xem user labels
SELECT user_name, max_read_label, min_write_label,
       def_label, row_label
FROM dba_sa_users
WHERE policy_name = 'DATA_SENSITIVITY';
```

---

## 4. ORACLE DATA REDACTION (Data Masking In-Database)

### 4.1 Full Redaction

```sql
-- Full Redaction: replace với default value (0, NULL, etc.)
-- Stored data không thay đổi, chỉ OUTPUT bị mask
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    column_name     => 'SALARY',
    policy_name     => 'MASK_SALARY_FULL',
    function_type   => DBMS_REDACT.FULL,   -- Return 0 for NUMBER
    expression      => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
                        NOT IN (''HR_ADMIN'',''PAYROLL'',''FINANCE'')'
  );
END;
/

-- Full redaction for multiple columns
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema   => 'FIN',
    object_name     => 'CUSTOMERS',
    column_name     => 'BANK_ACCOUNT',
    policy_name     => 'MASK_BANK_FULL',
    function_type   => DBMS_REDACT.FULL,   -- Return '' for VARCHAR
    expression      => '1=1'  -- Always redact
  );
END;
/
```

### 4.2 Partial Redaction

```sql
-- Partial Redaction: mask phần của value

-- ── Predefined patterns ───────────────────────────────────
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema      => 'FIN',
    object_name        => 'CUSTOMERS',
    column_name        => 'CREDIT_CARD_NUMBER',
    policy_name        => 'MASK_CC_PARTIAL',
    function_type      => DBMS_REDACT.PARTIAL,
    -- Predefined patterns:
    -- DBMS_REDACT.REDACT_CCN16_F12: xxxxxxxxxxxx1234 (12 masked, 4 visible)
    -- DBMS_REDACT.REDACT_US_SSN_ENTIRE: xxx-xx-xxxx
    -- DBMS_REDACT.REDACT_US_SSN_L4: xxx-xx-1234
    -- DBMS_REDACT.REDACT_DATE_MILLENNIUM: 01/01/2000
    function_parameters => DBMS_REDACT.REDACT_CCN16_F12,
    expression => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
                   != ''PAYMENT_ADMIN'''
  );
END;
/

-- ── Custom partial masking ────────────────────────────────
-- Format: input_width, output_type, redact_char, skip_chars, start_col, end_col
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema      => 'HR',
    object_name        => 'EMPLOYEES',
    column_name        => 'EMAIL',
    policy_name        => 'MASK_EMAIL_PARTIAL',
    function_type      => DBMS_REDACT.PARTIAL,
    -- Mask first 4 chars of local part: xxxx@domain.com
    function_parameters => '1,VCHAR,x,@,1,4',
    expression => '1=1'
  );
END;
/

-- ── Phone number masking ─────────────────────────────────
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema      => 'SALES',
    object_name        => 'CONTACTS',
    column_name        => 'PHONE_NUMBER',
    policy_name        => 'MASK_PHONE',
    function_type      => DBMS_REDACT.PARTIAL,
    -- Keep last 4 digits: (xxx) xxx-1234
    function_parameters => '7,VCHAR,x,,1,7',
    expression => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
                   NOT IN (''SALES_MANAGER'',''CRM_ADMIN'')'
  );
END;
/
```

### 4.3 Regular Expression Redaction

```sql
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema         => 'HR',
    object_name           => 'EMPLOYEES',
    column_name           => 'SOCIAL_SECURITY_NUMBER',
    policy_name           => 'MASK_SSN_REGEX',
    function_type         => DBMS_REDACT.REGEXP,
    -- Pattern: match SSN format
    regexp_pattern        => '(\d{3})-(\d{2})-(\d{4})',
    -- Replacement: show only last 4 digits
    regexp_replace_string => 'XXX-XX-\3',
    regexp_position       => 1,
    regexp_occurrence     => 0,    -- All occurrences
    regexp_match_parameter => 'i',
    expression => '1=1'
  );
END;
/

-- ── Manage Redaction Policies ─────────────────────────────
-- Update policy expression (change who gets redacted)
EXEC DBMS_REDACT.ALTER_POLICY(
  object_schema  => 'HR',
  object_name    => 'EMPLOYEES',
  policy_name    => 'MASK_SALARY_FULL',
  action         => DBMS_REDACT.MODIFY_EXPRESSION,
  expression     => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'')
                     NOT IN (''HR_ADMIN'',''PAYROLL'',''FINANCE'',
                              ''CFO'',''CEO'')'
);

-- Enable/Disable
EXEC DBMS_REDACT.DISABLE_POLICY('HR','EMPLOYEES','MASK_SALARY_FULL');
EXEC DBMS_REDACT.ENABLE_POLICY('HR','EMPLOYEES','MASK_SALARY_FULL');

-- Drop policy
EXEC DBMS_REDACT.DROP_POLICY('HR','EMPLOYEES','MASK_SALARY_FULL');

-- Xem policies
SELECT object_schema, object_name, policy_name, column_name,
       function_type, expression, enable
FROM dba_redact_policies
WHERE object_schema = 'HR'
ORDER BY object_name, column_name;
```

---

## 5. ORACLE SQL FIREWALL (23ai)

### 5.1 SQL Firewall Architecture

```
SQL Firewall Flow:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 1: CAPTURE (1-2 weeks production use)
  → Application executes SQL normally
  → SQL Firewall records all SQL statements for app_user

Phase 2: CREATE ALLOW LIST
  → Convert captured SQL to whitelist
  → Review and optionally add/remove SQL

Phase 3: ENFORCE
  → Enable enforcement mode
  → SQL not in allowlist → BLOCKED or OBSERVED
  → Violations logged to dba_sql_firewall_violations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 5.2 Setup và Configure

```sql
-- ── Enable SQL Firewall ──────────────────────────────────
EXEC DBMS_SQL_FIREWALL.ENABLE;
SELECT status FROM v$sql_firewall_status;

-- ── Phase 1: Start Capture ────────────────────────────────
BEGIN
  DBMS_SQL_FIREWALL.CREATE_CAPTURE(
    username        => 'APP_USER',
    top_level_only  => TRUE,   -- Chỉ capture top-level SQL
    start_time      => SYSTIMESTAMP
  );
  DBMS_SQL_FIREWALL.ENABLE_CAPTURE(username => 'APP_USER');
END;
/

-- Xem capture status
SELECT username, status, capture_id, start_timestamp
FROM dba_sql_firewall_captures
WHERE username = 'APP_USER';

-- ── Monitor captured SQL ─────────────────────────────────
SELECT sql_text, occurrence_count,
       TO_CHAR(first_exec_time,'YYYY-MM-DD HH24:MI') first_seen,
       TO_CHAR(last_exec_time,'YYYY-MM-DD HH24:MI') last_seen
FROM dba_sql_firewall_captured_sql
WHERE username = 'APP_USER'
ORDER BY occurrence_count DESC;

-- ── Phase 2: Stop capture và tạo Allow List ───────────────
EXEC DBMS_SQL_FIREWALL.STOP_CAPTURE(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.CREATE_ALLOW_LIST(username => 'APP_USER');

-- Xem allowed SQL
SELECT sql_id, sql_text, last_exec_time
FROM dba_sql_firewall_allowed_sql
WHERE username = 'APP_USER'
ORDER BY occurrence_count DESC;

-- ── Add/Remove từ Allow List ─────────────────────────────
-- Add SQL not captured (e.g., admin maintenance SQL)
BEGIN
  DBMS_SQL_FIREWALL.ADD_ALLOWED_SQL(
    username => 'APP_USER',
    sql_text => 'SELECT * FROM app.lookup_codes WHERE code_type = :1',
    contexts => NULL
  );
END;
/

-- Remove SQL từ allow list
BEGIN
  DBMS_SQL_FIREWALL.DELETE_ALLOWED_SQL(
    username => 'APP_USER',
    sql_id   => '3d5x7abc123' -- sql_id from dba_sql_firewall_allowed_sql
  );
END;
/

-- ── Phase 3: Enable Enforcement ──────────────────────────
BEGIN
  DBMS_SQL_FIREWALL.ENABLE_ALLOW_LIST(
    username => 'APP_USER',
    enforce  => DBMS_SQL_FIREWALL.ENFORCE_SQL,
    -- ENFORCE_SQL:  Block unauthorized SQL
    -- ENFORCE_TCP:  Block unauthorized TCP context (IP, port, program)
    -- ENFORCE_ALL:  Both SQL and TCP
    block    => TRUE     -- TRUE: block; FALSE: observe only (log but allow)
  );
END;
/

-- ── Monitor Violations ────────────────────────────────────
SELECT event_id, username, sql_text,
       client_ip, client_os_user, client_program,
       violation_type, -- SQL_VIOLATION | CONTEXT_VIOLATION
       TO_CHAR(event_time,'YYYY-MM-DD HH24:MI:SS') event_time,
       -- Context info
       client_port, os_program
FROM dba_sql_firewall_violations
WHERE event_time > SYSDATE - 7
ORDER BY event_time DESC;

-- Summary: top violating SQL
SELECT username, sql_text, COUNT(*) violation_count,
       MAX(event_time) last_violation
FROM dba_sql_firewall_violations
WHERE event_time > SYSDATE - 30
GROUP BY username, sql_text
ORDER BY violation_count DESC
FETCH FIRST 20 ROWS ONLY;

-- ── Manage SQL Firewall ──────────────────────────────────
EXEC DBMS_SQL_FIREWALL.DISABLE_ALLOW_LIST(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.DROP_ALLOW_LIST(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.DROP_CAPTURE(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.DISABLE;  -- Disable globally
```

---

## 6. PRIVILEGE ANALYSIS

```sql
-- Phân tích quyền nào thực sự được dùng → implement Least Privilege

-- ── Tạo capture ──────────────────────────────────────────
BEGIN
  DBMS_PRIVILEGE_CAPTURE.CREATE_CAPTURE(
    name        => 'CAPTURE_APP_USER_90DAYS',
    description => 'Track privilege usage for APP_USER',
    type        => DBMS_PRIVILEGE_CAPTURE.G_CONTEXT,
    condition   => 'SYS_CONTEXT(''USERENV'',''SESSION_USER'') = ''APP_USER'''
  );
END;
/

EXEC DBMS_PRIVILEGE_CAPTURE.ENABLE_CAPTURE('CAPTURE_APP_USER_90DAYS');

-- Run application normally for 2-4 weeks...

EXEC DBMS_PRIVILEGE_CAPTURE.DISABLE_CAPTURE('CAPTURE_APP_USER_90DAYS');
EXEC DBMS_PRIVILEGE_CAPTURE.GENERATE_RESULT('CAPTURE_APP_USER_90DAYS');

-- ── Analyze results ──────────────────────────────────────
-- Privileges USED (keep these)
SELECT username, used_role, used_priv, used_owner,
       used_object_name, used_object_type
FROM dba_used_privs
WHERE capture = 'CAPTURE_APP_USER_90DAYS'
ORDER BY used_priv, used_object_name;

-- Privileges NOT USED (candidates to revoke!)
SELECT username, sys_priv, object_priv,
       object_owner, object_name, object_type
FROM dba_unused_privs
WHERE capture = 'CAPTURE_APP_USER_90DAYS'
ORDER BY sys_priv NULLS LAST, object_priv;

-- Generate REVOKE scripts
SELECT 'REVOKE ' || sys_priv || ' FROM ' || username || ';' revoke_stmt
FROM dba_unused_privs
WHERE capture = 'CAPTURE_APP_USER_90DAYS'
  AND sys_priv IS NOT NULL
UNION ALL
SELECT 'REVOKE ' || object_priv || ' ON ' ||
       object_owner || '.' || object_name ||
       ' FROM ' || username || ';'
FROM dba_unused_privs
WHERE capture = 'CAPTURE_APP_USER_90DAYS'
  AND object_priv IS NOT NULL;
```

---

## 7. ORACLE AVDF (AUDIT VAULT & DATABASE FIREWALL)

```sql
-- AVDF = Enterprise product cho centralized audit management

-- ── Architecture ─────────────────────────────────────────
/*
Multiple Database Sources (Oracle, SQL Server, MySQL, PostgreSQL)
         │
         ↓ (Audit Vault Agents)
┌─────────────────────────────────────────────────────────┐
│               Audit Vault Server                        │
│  ├── Centralized Audit Data Warehouse                   │
│  ├── Real-time Alerting Engine                          │
│  ├── Compliance Reports (SOX, PCI-DSS, HIPAA, GDPR)    │
│  └── Retention Management                               │
└─────────────────────────────────────────────────────────┘
         │
         ↓ (Database Firewall)
┌─────────────────────────────────────────────────────────┐
│               Oracle Database Firewall                  │
│  ├── Inline mode: block SQL before reaching DB          │
│  ├── Monitor mode: observe only                         │
│  └── Policy: allow/warn/block SQL patterns              │
└─────────────────────────────────────────────────────────┘
*/

-- ── Prepare Oracle DB for AVDF collection ────────────────
-- Enable audit (Unified Auditing khuyến dùng)
-- AVDF Agent sẽ collect từ UNIFIED_AUDIT_TRAIL

-- Configure audit policies cho AVDF
CREATE AUDIT POLICY avdf_comprehensive
  ACTIONS ALL
  EVALUATE PER ACCESS;
AUDIT POLICY avdf_comprehensive BY USERS WITH GRANTED ROLES DBA;

-- Ensure AUD$ accessible
ALTER SYSTEM SET audit_sys_operations = TRUE SCOPE=SPFILE;

-- ── AVDF Agent setup (OS commands) ───────────────────────
-- Install AVDF Agent on DB server:
-- rpm -ivh /tmp/avdf_agent.rpm
-- /opt/avdf/agent/bin/agentctl start

-- ── AVDF Policy examples ─────────────────────────────────
/*
In AVDF Console → Firewall Policy:
1. Allowlist policy:
   - Allow: application server IPs with specific SQL patterns
   - Block: ALL other SQL

2. Blocking policy:
   - Block: known SQL injection patterns
   - Block: UNION SELECT attacks
   - Block: sys/system table direct access

3. Alert policy:
   - Alert: SELECT on salary/PII tables by unexpected users
   - Alert: Failed login > 5 times in 5 minutes
   - Alert: DBA access during non-business hours
*/

-- ── AVDF Compliance Reports ──────────────────────────────
/*
Built-in compliance report templates:
- Oracle AVDF → Reports → Compliance:
  * PCI-DSS Report: Card data access tracking
  * SOX Report: Financial data change tracking
  * HIPAA Report: Healthcare data access
  * GDPR Report: EU personal data tracking
  * ISO 27001: Information security events
  * Custom: Define own report
*/
```

---

## 8. SECURITY HARDENING CHECKLIST

```sql
-- ── Oracle CIS Benchmark Security Checks ─────────────────

-- 1. Default accounts locked
SELECT username, account_status
FROM dba_users
WHERE username IN (
  'SCOTT','HR','OE','SH','PM','IX','BI',
  'ANONYMOUS','XDB','ORDPLUGINS','ORDSYS',
  'SI_INFORMTN_SCHEMA','DIP','APEX_PUBLIC_USER',
  'FLOWS_FILES','ORDDATA'
)
AND account_status != 'LOCKED';
-- Fix: ALTER USER <name> ACCOUNT LOCK;

-- 2. Default passwords (vulnerability!)
SELECT username, account_status
FROM dba_users_with_defpwd
WHERE account_status = 'OPEN';
-- Fix: ALTER USER <name> IDENTIFIED BY "NewSecurePass_2026!";

-- 3. Dangerous PUBLIC grants
SELECT table_name, grantee, privilege
FROM dba_tab_privs
WHERE grantee = 'PUBLIC'
  AND privilege = 'EXECUTE'
  AND table_name IN ('UTL_FILE','UTL_HTTP','UTL_TCP','UTL_SMTP',
                     'DBMS_ADVISOR','DBMS_JAVA','UTL_MAIL',
                     'DBMS_RANDOM','HTTPURITYPE');
-- Fix: REVOKE EXECUTE ON UTL_HTTP FROM PUBLIC;

-- 4. ANY privileges (over-privileged users)
SELECT grantee, privilege
FROM dba_sys_privs
WHERE privilege LIKE '%ANY%'
  AND grantee NOT IN ('SYS','SYSTEM','DBA','IMP_FULL_DATABASE',
                       'EXP_FULL_DATABASE','DATAPUMP_IMP_FULL_DATABASE',
                       'DATAPUMP_EXP_FULL_DATABASE','AQ_ADMINISTRATOR_ROLE',
                       'EXECUTE_CATALOG_ROLE','SELECT_CATALOG_ROLE',
                       'OEM_MONITOR','OEM_ADVISOR')
ORDER BY grantee, privilege;

-- 5. DBA role: minimal users
SELECT grantee, granted_role, admin_option
FROM dba_role_privs
WHERE granted_role = 'DBA'
  AND grantee NOT IN ('SYS','SYSTEM','DBCA_INTERNAL','DBA')
ORDER BY grantee;

-- 6. SYSDBA: only necessary users
SELECT * FROM v$pwfile_users;

-- 7. Audit sys operations
SHOW PARAMETER audit_sys_operations;
-- Should be TRUE
ALTER SYSTEM SET audit_sys_operations = TRUE SCOPE=SPFILE;

-- 8. Remote login passwordfile
SHOW PARAMETER remote_login_passwordfile;
-- Should be EXCLUSIVE (not SHARED)
ALTER SYSTEM SET remote_login_passwordfile = EXCLUSIVE SCOPE=SPFILE;

-- 9. UTL_FILE_DIR deprecated
SHOW PARAMETER utl_file_dir;
-- Should be empty (use DIRECTORY objects instead)

-- 10. Password policy (DEFAULT profile)
SELECT profile, resource_name, limit
FROM dba_profiles
WHERE profile = 'DEFAULT'
  AND resource_name IN (
    'FAILED_LOGIN_ATTEMPTS',   -- Should be <= 10
    'PASSWORD_LIFE_TIME',       -- Should be <= 365
    'PASSWORD_REUSE_TIME',      -- Should be >= 365
    'PASSWORD_REUSE_MAX',       -- Should be >= 20
    'PASSWORD_LOCK_TIME',       -- Should be >= 1/24 (1 hour)
    'PASSWORD_GRACE_TIME',      -- Should be <= 7
    'PASSWORD_VERIFY_FUNCTION'  -- Should not be NULL
  );

-- 11. Inactive users
SELECT username,
       ROUND(SYSDATE - NVL(last_login, created)) days_inactive,
       account_status
FROM dba_users
WHERE account_status = 'OPEN'
  AND (last_login IS NULL OR last_login < SYSDATE - 90)
  AND username NOT IN ('SYS','SYSTEM','DBSNMP','DBCA_INTERNAL',
                        'APEX_PUBLIC_USER','APEX_REST_PUBLIC_USER')
ORDER BY days_inactive DESC;
-- Fix: ALTER USER <name> ACCOUNT LOCK;

-- 12. Privilege creep detection
SELECT grantee, COUNT(*) priv_count
FROM dba_sys_privs
WHERE grantee NOT IN (
  SELECT role FROM dba_roles  -- Exclude role grantees
)
AND grantee NOT IN ('SYS','SYSTEM','DBA')
GROUP BY grantee
HAVING COUNT(*) > 30  -- Too many system privileges
ORDER BY priv_count DESC;

-- ── Security Hardening Action Script ─────────────────────
-- Lock unnecessary accounts
BEGIN
  FOR u IN (
    SELECT username FROM dba_users
    WHERE username IN ('SCOTT','HR','OE','SH','PM','IX','BI')
      AND account_status = 'OPEN'
  ) LOOP
    EXECUTE IMMEDIATE 'ALTER USER '||u.username||' ACCOUNT LOCK';
    DBMS_OUTPUT.PUT_LINE('Locked: '||u.username);
  END LOOP;
END;
/

-- Revoke PUBLIC execute on dangerous packages
BEGIN
  FOR pkg IN (
    SELECT table_name FROM dba_tab_privs
    WHERE grantee = 'PUBLIC'
      AND privilege = 'EXECUTE'
      AND table_name IN ('UTL_FILE','UTL_HTTP','UTL_TCP','UTL_SMTP')
  ) LOOP
    EXECUTE IMMEDIATE 'REVOKE EXECUTE ON '||pkg.table_name||' FROM PUBLIC';
    DBMS_OUTPUT.PUT_LINE('Revoked: '||pkg.table_name);
  END LOOP;
END;
/
```

---

**Tài liệu tham khảo:**
- Oracle Database Security Guide 19c: VPD, Database Vault, OLS
- Oracle Data Redaction: docs.oracle.com/redaction
- Oracle SQL Firewall Guide 23ai: docs.oracle.com/sql-firewall
- Oracle AVDF Documentation: docs.oracle.com/avdf
- CIS Oracle Database Benchmark v2.x
- MOS Note 207671.1 (Security Checklist)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
