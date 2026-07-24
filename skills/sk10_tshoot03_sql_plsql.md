---
name: oracle-troubleshoot-sql-plsql
description: >
  100 case study khắc phục lỗi SQL và PL/SQL Oracle Database.
  Kích hoạt khi hỏi về: lỗi SQL Oracle, ORA-00936, ORA-00942, ORA-00904,
  lỗi PL/SQL, PLS- error, compile error PL/SQL, ORA-06502, ORA-06512,
  cursor error Oracle, ORA-01403 no data found, ORA-01422,
  too many rows error, mutating table error Oracle, ORA-04091,
  bulk collect error, FORALL error, trigger compile error,
  package invalid Oracle, function return error, exception handling error,
  dynamic SQL error, EXECUTE IMMEDIATE error, NUMBER overflow Oracle,
  VARCHAR2 buffer too small, JSON error Oracle, XML error Oracle.
---

# SK10-CASE-03 · Troubleshooting: SQL và PL/SQL

**Phạm vi:** SQL Syntax/Logic, PL/SQL Compile/Runtime, Cursors, Triggers, Packages  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Số lượng case:** 100 cases thực chiến

---

## KIẾN TRÚC TỔNG QUAN ĐIỂM LỖI SQL/PLSQL

```
SQL & PL/SQL Error Lifecycle
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────────┐
│                  PARSE TIME ERRORS                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │  Syntax  │  │ Semantic │  │  Object  │   Group A      │
│  │  Errors  │  │  Errors  │  │Not Found │   (1-20)       │
│  └──────────┘  └──────────┘  └──────────┘                │
└─────────────────────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│              PL/SQL COMPILE TIME ERRORS                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │   PLS-   │  │  Trigger │  │ Package  │   Group B      │
│  │  Errors  │  │  Compile │  │  Invalid │   (21-40)      │
│  └──────────┘  └──────────┘  └──────────┘                │
└─────────────────────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│               RUNTIME EXECUTION ERRORS                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │  Cursor  │  │Exception │  │   Data   │   Group C-D    │
│  │  Errors  │  │ Handling │  │   Type   │   (41-70)      │
│  └──────────┘  └──────────┘  └──────────┘                │
└─────────────────────────────────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────────┐
│            ADVANCED CONSTRUCTS ERRORS                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group E-F   │
│  │  Bulk    │  │ Dynamic  │  │ JSON/XML │   (71-100)    │
│  │Collect/  │  │   SQL    │  │          │                │
│  │ FORALL   │  │          │  │          │                │
│  └──────────┘  └──────────┘  └──────────┘                │
└─────────────────────────────────────────────────────────┘

Severity: 🔴 BLOCKING (code không chạy) | 🟡 LOGIC (chạy sai kết quả) | 🟢 WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## NHÓM A: SQL SYNTAX & SEMANTIC ERRORS (Case 1-20)

### Case 1: ORA-00936 — missing expression

```sql
🔴 BLOCKING | SELECT statement syntax error

-- Lỗi (thiếu giá trị sau dấu phẩy/operator)
SELECT employee_id, FROM employees WHERE salary > ;

-- Fix
SELECT employee_id, salary FROM employees WHERE salary > 5000;
```

### Case 2: ORA-00942 — table or view does not exist

```sql
🔴 BLOCKING | Object reference sai

-- Chẩn đoán
SELECT owner, object_name, object_type FROM dba_objects
WHERE object_name = 'ORDERS' AND object_type IN ('TABLE','VIEW');

-- Common causes:
-- 1. Sai schema prefix
SELECT * FROM hr.employees;  -- Thay vì chỉ "employees"

-- 2. Thiếu quyền SELECT
GRANT SELECT ON hr.employees TO app_user;

-- 3. Object thực sự chưa tồn tại / đã bị drop
SELECT table_name FROM dba_tables WHERE owner='HR' AND table_name='EMPLOYEES';

-- 4. Case-sensitive nếu tên có quotes khi tạo
SELECT * FROM "Employees";  -- Khác với EMPLOYEES
```

### Case 3: ORA-00904 — invalid identifier

```sql
🔴 BLOCKING | Column name sai hoặc alias chưa định nghĩa

-- Lỗi
SELECT emp_id, salry FROM employees;  -- Typo "salry"

-- Chẩn đoán
SELECT column_name FROM dba_tab_columns
WHERE table_name='EMPLOYEES' AND owner='HR';

-- Fix: kiểm tra đúng tên column
SELECT employee_id, salary FROM employees;
```

### Case 4: ORA-00933 — SQL command not properly ended

```sql
🔴 BLOCKING | Extra clause hoặc syntax thừa

-- Lỗi (ORDER BY trong subquery không hợp lệ ở vị trí này)
SELECT * FROM (SELECT * FROM employees ORDER BY salary) WHERE rownum<=10
ORDER BY hire_date;  -- Conflict

-- Fix: dùng FETCH FIRST hoặc structure lại
SELECT * FROM employees ORDER BY salary FETCH FIRST 10 ROWS ONLY;
```

### Case 5: ORA-00918 — column ambiguously defined

```sql
🔴 BLOCKING | JOIN với column trùng tên ở 2 bảng

-- Lỗi
SELECT employee_id FROM employees e JOIN departments d
ON e.department_id = d.department_id;
-- Nếu cả 2 bảng có "employee_id" → ambiguous

-- Fix: luôn dùng table alias prefix
SELECT e.employee_id FROM employees e JOIN departments d
ON e.department_id = d.department_id;
```

### Case 6: ORA-00920 — invalid relational operator

```sql
🔴 BLOCKING | Operator sai cú pháp

-- Lỗi
SELECT * FROM employees WHERE salary =< 5000;  -- Sai thứ tự

-- Fix
SELECT * FROM employees WHERE salary <= 5000;
```

### Case 7: ORA-01722 — invalid number

```sql
🔴 BLOCKING | Implicit conversion fail

-- Lỗi
SELECT * FROM orders WHERE order_id = 'ABC';  -- order_id là NUMBER

-- Chẩn đoán: tìm dữ liệu không phải số trong cột VARCHAR cần convert
SELECT order_ref FROM orders WHERE NOT REGEXP_LIKE(order_ref, '^[0-9]+$');

-- Fix: validate trước khi convert hoặc dùng TO_NUMBER với exception
SELECT order_id FROM orders WHERE order_id = TO_NUMBER('123');
```

### Case 8: ORA-01858 — not a valid month / ORA-01861 literal does not match format

```sql
🔴 BLOCKING | Date format mismatch

-- Lỗi
SELECT * FROM orders WHERE order_date = '2026-13-45';  -- Invalid date

-- Fix: dùng TO_DATE với format string rõ ràng
SELECT * FROM orders WHERE order_date = TO_DATE('2026-01-15','YYYY-MM-DD');

-- Kiểm tra NLS_DATE_FORMAT session
SELECT * FROM nls_session_parameters WHERE parameter='NLS_DATE_FORMAT';
ALTER SESSION SET NLS_DATE_FORMAT='YYYY-MM-DD';
```

### Case 9: ORA-00979 — not a GROUP BY expression

```sql
🔴 BLOCKING | SELECT column thiếu trong GROUP BY

-- Lỗi
SELECT department_id, employee_name, COUNT(*)
FROM employees GROUP BY department_id;  -- employee_name không trong GROUP BY

-- Fix: thêm vào GROUP BY hoặc dùng aggregate function
SELECT department_id, COUNT(*) FROM employees GROUP BY department_id;
-- Hoặc:
SELECT department_id, MAX(employee_name), COUNT(*)
FROM employees GROUP BY department_id;
```

### Case 10: ORA-01789 — query block has incorrect number of result columns

```sql
🔴 BLOCKING | UNION mismatch số lượng columns

-- Lỗi
SELECT employee_id, name FROM employees
UNION
SELECT department_id FROM departments;  -- Khác số cột

-- Fix: đảm bảo số cột giống nhau
SELECT employee_id, name FROM employees
UNION
SELECT department_id, department_name FROM departments;
```

### Case 11: ORA-01790 — expression must have same datatype as corresponding expression

```sql
🔴 BLOCKING | UNION với data type không khớp

-- Fix: CAST để đảm bảo cùng datatype
SELECT TO_CHAR(employee_id) id, name FROM employees
UNION
SELECT department_id, department_name FROM departments;
```

### Case 12: ORA-00957 — duplicate column name

```sql
🔴 BLOCKING | CREATE TABLE với 2 cột cùng tên

-- Lỗi
CREATE TABLE test (id NUMBER, name VARCHAR2(50), name VARCHAR2(100));

-- Fix: đổi tên 1 trong 2 cột
CREATE TABLE test (id NUMBER, first_name VARCHAR2(50), last_name VARCHAR2(100));
```

### Case 13: ORA-01400 — cannot insert NULL into column

```sql
🔴 BLOCKING | NOT NULL constraint violation

-- Chẩn đoán
SELECT column_name, nullable FROM dba_tab_columns
WHERE table_name='EMPLOYEES' AND nullable='N';

-- Fix: cung cấp giá trị hoặc set DEFAULT
INSERT INTO employees (employee_id, first_name, last_name, email)
VALUES (100, 'John', 'Doe', 'john.doe@company.com');
```

### Case 14: ORA-02290 — check constraint violated

```sql
🟡 LOGIC | Giá trị không thỏa CHECK constraint

-- Chẩn đoán
SELECT constraint_name, search_condition FROM dba_constraints
WHERE table_name='ORDERS' AND constraint_type='C';

-- Fix: kiểm tra giá trị hợp lệ trước khi insert
SELECT search_condition FROM dba_constraints WHERE constraint_name='CHK_STATUS';
-- VD: status phải IN ('PENDING','ACTIVE','COMPLETED')
```

### Case 15: ORA-02291 — integrity constraint violated - parent key not found

```sql
🟡 LOGIC | Foreign Key reference không tồn tại

-- Chẩn đoán
SELECT customer_id FROM orders WHERE customer_id NOT IN (
  SELECT customer_id FROM customers);

-- Fix: đảm bảo parent record tồn tại trước
INSERT INTO customers (customer_id, name) VALUES (500, 'New Customer');
INSERT INTO orders (order_id, customer_id) VALUES (1, 500);
```

### Case 16: ORA-02292 — integrity constraint violated - child record found

```sql
🟡 LOGIC | DELETE parent khi còn child records

-- Chẩn đoán
SELECT COUNT(*) FROM orders WHERE customer_id = 500;

-- Fix 1: xóa child trước
DELETE FROM orders WHERE customer_id = 500;
DELETE FROM customers WHERE customer_id = 500;

-- Fix 2: dùng ON DELETE CASCADE khi tạo FK (thiết kế lại)
ALTER TABLE orders ADD CONSTRAINT fk_orders_cust
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
  ON DELETE CASCADE;
```

### Case 17: ORA-00001 — unique constraint violated

```sql
🟡 LOGIC | Duplicate key trong UNIQUE/PRIMARY KEY

-- Chẩn đoán
SELECT employee_id, COUNT(*) FROM employees
GROUP BY employee_id HAVING COUNT(*) > 1;

-- Fix: dùng MERGE thay vì INSERT để tránh duplicate
MERGE INTO employees t USING (SELECT 100 id FROM dual) s
ON (t.employee_id = s.id)
WHEN NOT MATCHED THEN INSERT (employee_id) VALUES (s.id);
```

### Case 18: ORA-12899 — value too large for column

```sql
🔴 BLOCKING | VARCHAR2/data length vượt giới hạn

-- Chẩn đoán
SELECT column_name, data_length FROM dba_tab_columns
WHERE table_name='EMPLOYEES' AND column_name='EMAIL';

-- Fix: tăng column size hoặc truncate data
ALTER TABLE employees MODIFY email VARCHAR2(200);
-- Hoặc validate length trước khi insert
INSERT INTO employees (email) VALUES (SUBSTR(:long_email, 1, 100));
```

### Case 19: ORA-00947 — not enough values

```sql
🔴 BLOCKING | INSERT thiếu values so với columns

-- Lỗi
INSERT INTO employees (employee_id, first_name, last_name) VALUES (100, 'John');

-- Fix
INSERT INTO employees (employee_id, first_name, last_name) VALUES (100, 'John', 'Doe');
```

### Case 20: ORA-01747 — invalid user.table.column, table.column, or column specification

```sql
🔴 BLOCKING | UPDATE/REFERENCES syntax sai

-- Lỗi
UPDATE employees SET hr.employees.salary = 5000 WHERE employee_id=100;

-- Fix
UPDATE employees SET salary = 5000 WHERE employee_id=100;
```

---

## NHÓM B: PL/SQL COMPILE ERRORS (Case 21-40)

### Case 21: PLS-00103 — Encountered the symbol when expecting one of the following

```sql
🔴 BLOCKING | PL/SQL syntax error chung

-- Lỗi (thiếu THEN)
IF salary > 5000
  v_grade := 'A';
END IF;

-- Fix
IF salary > 5000 THEN
  v_grade := 'A';
END IF;
```

### Case 22: PLS-00201 — identifier must be declared

```sql
🔴 BLOCKING | Biến chưa khai báo hoặc out of scope

-- Lỗi
BEGIN
  v_total := v_total + 1;  -- v_total chưa declare
END;

-- Fix
DECLARE
  v_total NUMBER := 0;
BEGIN
  v_total := v_total + 1;
END;
```

### Case 23: PLS-00306 — wrong number or types of arguments in call

```sql
🔴 BLOCKING | Gọi procedure/function sai số/kiểu tham số

-- Lỗi
EXEC update_salary(100);  -- Procedure cần 2 tham số

-- Chẩn đoán
SELECT argument_name, data_type, position FROM dba_arguments
WHERE object_name='UPDATE_SALARY' ORDER BY position;

-- Fix: cung cấp đủ tham số đúng thứ tự/named notation
EXEC update_salary(p_emp_id => 100, p_new_salary => 6000);
```

### Case 24: PLS-00302 — component must be declared

```sql
🔴 BLOCKING | Record field không tồn tại

-- Lỗi
v_emp.salry := 5000;  -- Typo field name trong %ROWTYPE record

-- Fix: kiểm tra đúng tên field
v_emp.salary := 5000;
```

### Case 25: PLS-00382 — expression is of wrong type

```sql
🔴 BLOCKING | Type mismatch trong assignment

-- Lỗi
DECLARE
  v_count NUMBER;
BEGIN
  v_count := 'ABC';  -- String gán cho NUMBER
END;

-- Fix
DECLARE
  v_count NUMBER;
BEGIN
  v_count := 123;
END;
```

### Case 26: PLS-00049 — bad bind variable

```sql
🔴 BLOCKING | Bind variable không tồn tại trong dynamic SQL

-- Lỗi
EXECUTE IMMEDIATE 'SELECT * FROM employees WHERE id=:1' USING v_id;
-- Nhưng query thực tế dùng :emp_id

-- Fix: đảm bảo bind variable name khớp (hoặc dùng positional :1,:2)
EXECUTE IMMEDIATE 'SELECT * FROM employees WHERE employee_id=:1'
  INTO v_result USING v_id;
```

### Case 27: Package STATUS = INVALID sau khi thay đổi dependent object

```sql
🟡 LOGIC | Cascading invalidation

-- Chẩn đoán
SELECT object_name, object_type, status FROM dba_objects
WHERE owner='SCOTT' AND status='INVALID';

-- Fix: recompile
ALTER PACKAGE pkg_order_mgmt COMPILE;
ALTER PACKAGE pkg_order_mgmt COMPILE BODY;
-- Hoặc compile toàn schema
EXEC DBMS_UTILITY.COMPILE_SCHEMA('SCOTT');
```

### Case 28: PLS-00231 — function may not be used in SQL

```sql
🔴 BLOCKING | Function có side-effect (DML) dùng trong SQL

-- Lỗi: Function chứa INSERT/UPDATE/COMMIT không thể gọi trong SELECT
SELECT my_function_with_dml(id) FROM employees;

-- Fix: tách logic, hoặc dùng PRAGMA AUTONOMOUS_TRANSACTION trong function
CREATE OR REPLACE FUNCTION my_function_with_dml(p_id NUMBER) RETURN NUMBER IS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO log_table VALUES (p_id, SYSDATE);
  COMMIT;
  RETURN p_id;
END;
```

### Case 29: PLS-00372 — In a PL/SQL unit, this form of OPEN... is not allowed

```sql
🔴 BLOCKING | Cursor đã được khai báo với SELECT, không thể OPEN FOR khác

-- Fix: dùng REF CURSOR nếu cần dynamic
DECLARE
  TYPE t_cur IS REF CURSOR;
  c_cur t_cur;
BEGIN
  OPEN c_cur FOR 'SELECT * FROM employees WHERE department_id=:1' USING 60;
END;
```

### Case 30: Trigger compile error — mutating table (ORA-04091)

```sql
🔴 BLOCKING | Trigger query chính table đang trigger (xem thêm Case 41)

-- Lỗi
CREATE TRIGGER trg_check AFTER UPDATE ON employees FOR EACH ROW
BEGIN
  IF (SELECT COUNT(*) FROM employees WHERE department_id=:NEW.department_id) > 100 THEN
    RAISE_APPLICATION_ERROR(-20001,'Too many employees');
  END IF;
END;

-- Fix: dùng Compound Trigger hoặc package state thay vì query trực tiếp
CREATE OR REPLACE TRIGGER trg_check
  FOR UPDATE ON employees COMPOUND TRIGGER
  v_count NUMBER;
  BEFORE STATEMENT IS
  BEGIN
    NULL;
  END BEFORE STATEMENT;
  AFTER STATEMENT IS
  BEGIN
    SELECT COUNT(*) INTO v_count FROM employees GROUP BY department_id
    HAVING COUNT(*) > 100;
  END AFTER STATEMENT;
END trg_check;
```

### Case 31: PLS-00553 — character set name is not recognized

```sql
🟢 WARNING | NLS character set issue trong PL/SQL

-- Fix: kiểm tra NLS_LANG environment variable
SELECT * FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';
```

### Case 32: Package body compile fail nhưng spec OK

```sql
🔴 BLOCKING | Mismatch giữa spec và body

-- Chẩn đoán
SHOW ERRORS PACKAGE BODY pkg_name;
SELECT line, position, text FROM dba_errors
WHERE name='PKG_NAME' AND type='PACKAGE BODY' ORDER BY sequence;

-- Common cause: số lượng/tên tham số procedure trong body không khớp spec
```

### Case 33: ORA-06550 — line X, column X: PLS-XXXXX

```sql
🔴 BLOCKING | Generic PL/SQL compile error wrapper

-- Luôn xem error detail đầy đủ
SHOW ERRORS;
-- Hoặc trong session khác:
SELECT line||':'||position||' '||text FROM dba_errors
WHERE name='PROC_NAME' ORDER BY sequence;
```

### Case 34: Recompile package fail vì dependent object cũng invalid

```sql
🟡 LOGIC | Circular/cascading invalid objects

-- Fix: dùng UTL_RECOMP để compile theo đúng thứ tự dependency
EXEC UTL_RECOMP.RECOMP_SERIAL('SCOTT');
-- Hoặc parallel (nhanh hơn cho nhiều objects):
EXEC UTL_RECOMP.RECOMP_PARALLEL(4, 'SCOTT');
```

### Case 35: PLS-00905 — object is invalid (khi gọi procedure)

```sql
🔴 BLOCKING | Gọi 1 object đang ở trạng thái INVALID

-- Chẩn đoán
SELECT status FROM dba_objects WHERE object_name='PKG_ORDER' AND owner='SCOTT';
-- Compile lại trước khi gọi
ALTER PACKAGE scott.pkg_order COMPILE BODY;
```

### Case 36: Trigger không fire dù DML thực hiện đúng

```sql
🟡 LOGIC | Trigger bị DISABLE

-- Chẩn đoán
SELECT trigger_name, status FROM dba_triggers
WHERE table_name='ORDERS' AND status='DISABLED';

-- Fix
ALTER TRIGGER trg_orders_audit ENABLE;
```

### Case 37: PLS-00302 trong dynamic PL/SQL block (EXECUTE IMMEDIATE)

```sql
🔴 BLOCKING | Lỗi compile bên trong dynamic block

-- Lỗi xảy ra runtime vì syntax bên trong string sai
EXECUTE IMMEDIATE 'BEGIN update_emp(:1); END;' USING v_id;
-- Nếu update_emp không tồn tại → fail lúc runtime, không compile time

-- Fix: test PL/SQL block riêng trước khi đưa vào dynamic SQL
```

### Case 38: Function trả về sai kiểu dữ liệu so với khai báo

```sql
🔴 BLOCKING | Return type mismatch

-- Lỗi
CREATE FUNCTION get_name RETURN VARCHAR2 IS
BEGIN
  RETURN 123;  -- NUMBER thay vì VARCHAR2 (tự convert nhưng có thể gây lỗi khác)
END;

-- Fix: đảm bảo return type khớp
CREATE FUNCTION get_name RETURN VARCHAR2 IS
BEGIN
  RETURN TO_CHAR(123);
END;
```

### Case 39: ORA-04068 sau khi DROP và CREATE lại package

```sql
🟢 WARNING | Session vẫn giữ state cũ

-- Fix: tất cả sessions cần reconnect để pickup package mới
-- Hoặc force invalidate sessions đang dùng package cũ (hiếm khi cần)
```

### Case 40: PLS-00231 khi tạo Function-Based Index

```sql
🔴 BLOCKING | Function dùng trong FBI có side effects

-- Lỗi: function phải DETERMINISTIC để dùng trong index
CREATE FUNCTION calc_total(p_qty NUMBER, p_price NUMBER) RETURN NUMBER IS
BEGIN
  RETURN p_qty * p_price;
END;
-- Thiếu DETERMINISTIC keyword

-- Fix
CREATE OR REPLACE FUNCTION calc_total(p_qty NUMBER, p_price NUMBER)
  RETURN NUMBER DETERMINISTIC IS
BEGIN
  RETURN p_qty * p_price;
END;
```

---

## NHÓM C: CURSOR & EXCEPTION HANDLING (Case 41-55)

### Case 41: ORA-04091 — table is mutating, trigger/function may not see it

```sql
🔴 BLOCKING | Xem chi tiết Case 30 — query table đang bị trigger trên chính nó

-- Fix tốt nhất: Compound Trigger (Oracle 11g+)
CREATE OR REPLACE TRIGGER trg_emp_salary_check
  FOR UPDATE OF salary ON employees COMPOUND TRIGGER
  TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_ids t_ids;
  v_idx PLS_INTEGER := 0;

  AFTER EACH ROW IS
  BEGIN
    v_idx := v_idx + 1;
    v_ids(v_idx) := :NEW.employee_id;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
    v_total NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_total FROM employees
    WHERE employee_id IN (SELECT * FROM TABLE(v_ids));
    -- Process sau khi statement hoàn thành, không còn mutating issue
  END AFTER STATEMENT;
END;
```

### Case 42: ORA-01403 — no data found (không handle exception)

```sql
🟡 LOGIC | SELECT INTO không match row nào

-- Lỗi
DECLARE
  v_salary NUMBER;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE employee_id=99999;
  -- Fail nếu employee_id không tồn tại
END;

-- Fix: luôn handle NO_DATA_FOUND
DECLARE
  v_salary NUMBER;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE employee_id=99999;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    v_salary := 0;
    DBMS_OUTPUT.PUT_LINE('Employee not found');
END;
```

### Case 43: ORA-01422 — exact fetch returns more than requested number of rows

```sql
🟡 LOGIC | SELECT INTO match nhiều hơn 1 row

-- Chẩn đoán
SELECT COUNT(*) FROM employees WHERE last_name='SMITH';

-- Fix: handle TOO_MANY_ROWS hoặc dùng cursor/BULK COLLECT
DECLARE
  v_salary NUMBER;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE last_name='SMITH';
EXCEPTION
  WHEN TOO_MANY_ROWS THEN
    DBMS_OUTPUT.PUT_LINE('Multiple employees found, use cursor instead');
END;
```

### Case 44: Cursor không CLOSE gây ORA-01000 (xem thêm SK10-01 Case 6)

```sql
🟡 LOGIC | Cursor leak trong loop

-- Lỗi: mở cursor trong loop không đóng
FOR i IN 1..1000 LOOP
  OPEN c_cursor;  -- Không CLOSE → leak
  FETCH c_cursor INTO v_data;
END LOOP;

-- Fix: dùng cursor FOR loop (tự động quản lý)
FOR rec IN c_cursor LOOP
  -- process rec
  NULL;
END LOOP;
```

### Case 45: WHEN OTHERS THEN NULL — silent exception swallowing (anti-pattern)

```sql
🟡 LOGIC | Lỗi bị ẩn, khó debug

-- Anti-pattern NGUY HIỂM
BEGIN
  risky_operation();
EXCEPTION
  WHEN OTHERS THEN NULL;  -- Nuốt mọi lỗi, không log gì
END;

-- Fix: luôn log lỗi trước khi xử lý
BEGIN
  risky_operation();
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: '||SQLERRM);
    INSERT INTO error_log VALUES (SYSDATE, SQLCODE, SQLERRM);
    COMMIT;
    -- RAISE;  -- Cân nhắc re-raise nếu cần caller biết
END;
```

### Case 46: ORA-06502 — character string buffer too small

```sql
🔴 BLOCKING | VARCHAR2 variable không đủ lớn

-- Lỗi
DECLARE
  v_name VARCHAR2(10);
BEGIN
  v_name := 'This is a very long name';  -- > 10 chars
END;

-- Fix: tăng kích thước hoặc dùng %TYPE
DECLARE
  v_name employees.first_name%TYPE;  -- Tự động match column size
BEGIN
  v_name := 'This is a very long name';
END;
```

### Case 47: ORA-06512 — at line X (stack trace reference)

```sql
🟢 WARNING | Đây là phần của error message khác, không phải lỗi riêng

-- Luôn đọc CẢ chuỗi lỗi, không chỉ ORA-06512
-- VD: "ORA-01403: no data found ORA-06512: at line 5"
-- → Root cause là ORA-01403, line 5 chỉ là vị trí
DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);  -- Full stack
```

### Case 48: Custom exception không catch được do PRAGMA sai

```sql
🔴 BLOCKING | EXCEPTION_INIT map sai error code

-- Lỗi
DECLARE
  e_custom EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_custom, 20001);  -- Thiếu dấu trừ!
BEGIN
  RAISE_APPLICATION_ERROR(-20001, 'Custom error');
EXCEPTION
  WHEN e_custom THEN  -- Không catch được vì code sai
    NULL;
END;

-- Fix
PRAGMA EXCEPTION_INIT(e_custom, -20001);  -- Đúng: số âm
```

### Case 49: FORALL với SAVE EXCEPTIONS nhưng không check sau đó

```sql
🟡 LOGIC | Lỗi bị bỏ qua âm thầm trong bulk operation

-- Anti-pattern
FORALL i IN 1..v_ids.COUNT SAVE EXCEPTIONS
  UPDATE employees SET salary=v_sals(i) WHERE employee_id=v_ids(i);
-- Không check SQL%BULK_EXCEPTIONS → lỗi bị bỏ qua

-- Fix: luôn check sau FORALL
BEGIN
  FORALL i IN 1..v_ids.COUNT SAVE EXCEPTIONS
    UPDATE employees SET salary=v_sals(i) WHERE employee_id=v_ids(i);
EXCEPTION
  WHEN OTHERS THEN
    FOR i IN 1..SQL%BULK_EXCEPTIONS.COUNT LOOP
      DBMS_OUTPUT.PUT_LINE('Error at index '||SQL%BULK_EXCEPTIONS(i).ERROR_INDEX||
        ': '||SQLERRM(-SQL%BULK_EXCEPTIONS(i).ERROR_CODE));
    END LOOP;
END;
```

### Case 50: Nested exception handler che giấu original error

```sql
🟡 LOGIC | Exception trong exception handler

-- Lỗi: nếu logging fail, mất luôn original error info
BEGIN
  risky_op();
EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO log VALUES (SQLERRM);  -- Nếu insert này fail thì sao?
END;

-- Fix: wrap logging trong block riêng, không để nó che lỗi gốc
DECLARE
  v_original_error VARCHAR2(4000);
BEGIN
  risky_op();
EXCEPTION
  WHEN OTHERS THEN
    v_original_error := SQLERRM;
    BEGIN
      INSERT INTO log VALUES (v_original_error);
      COMMIT;
    EXCEPTION WHEN OTHERS THEN NULL;  -- Logging fail không ảnh hưởng
    END;
    RAISE_APPLICATION_ERROR(-20099, v_original_error);
END;
```

### Case 51: REF CURSOR không đóng đúng cách giữa các calls

```sql
🟡 LOGIC | REF CURSOR leak qua application layer

-- Fix: đảm bảo application code (Java/.NET) luôn close ResultSet/CallableStatement
-- Trên PL/SQL side: đảm bảo OPEN ... FOR chỉ 1 lần trước khi return
```

### Case 52: Cursor attribute %ROWCOUNT trả về sai giá trị

```sql
🟡 LOGIC | Hiểu nhầm về thời điểm %ROWCOUNT update

-- Lưu ý: %ROWCOUNT chỉ update SAU FETCH, không phải sau OPEN
OPEN c_cursor;
DBMS_OUTPUT.PUT_LINE(c_cursor%ROWCOUNT);  -- Luôn = 0 tại đây
FETCH c_cursor INTO v_data;
DBMS_OUTPUT.PUT_LINE(c_cursor%ROWCOUNT);  -- = 1 sau fetch đầu tiên
```

### Case 53: WHEN NO_DATA_FOUND không trigger trong cursor FOR loop (by design)

```sql
🟢 WARNING | Hiểu nhầm về cursor FOR loop behavior

-- Cursor FOR loop tự xử lý NO_DATA_FOUND (loop đơn giản không chạy nếu rỗng)
FOR rec IN (SELECT * FROM employees WHERE department_id=999) LOOP
  -- Nếu không có rows, loop body không chạy, KHÔNG raise exception
  NULL;
END LOOP;
-- Đây là behavior ĐÚNG, không phải lỗi
```

### Case 54: SAVEPOINT không hoạt động như mong đợi sau COMMIT

```sql
🟡 LOGIC | Savepoint bị invalidated bởi COMMIT

-- Lỗi: COMMIT xóa tất cả savepoints
SAVEPOINT sp1;
UPDATE employees SET salary=salary*1.1;
COMMIT;  -- Xóa savepoint sp1!
ROLLBACK TO SAVEPOINT sp1;  -- FAIL: savepoint không còn tồn tại

-- Fix: không COMMIT giữa SAVEPOINT và ROLLBACK TO nếu cần dùng savepoint đó
```

### Case 55: Exception trong Autonomous Transaction không rollback main transaction

```sql
🟢 WARNING | Hiểu nhầm về Autonomous Transaction isolation

-- Đây là BEHAVIOR ĐÚNG: autonomous transaction độc lập hoàn toàn
CREATE PROCEDURE log_action(p_msg VARCHAR2) AS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO log_table VALUES (p_msg);
  COMMIT;  -- Chỉ commit phần autonomous, không ảnh hưởng main transaction
EXCEPTION
  WHEN OTHERS THEN ROLLBACK;  -- Chỉ rollback autonomous part
END;
```

---

## NHÓM D: DATA TYPE & CONVERSION ERRORS (Case 56-70)

### Case 56: ORA-06502 — NUMBER overflow (PLS-00382 related)

```sql
🔴 BLOCKING | Số vượt giới hạn precision

-- Lỗi
DECLARE
  v_amount NUMBER(5,2);  -- Max 999.99
BEGIN
  v_amount := 123456.78;  -- Overflow!
END;

-- Fix: tăng precision hoặc validate trước
DECLARE
  v_amount NUMBER(15,2);
BEGIN
  v_amount := 123456.78;
END;
```

### Case 57: ORA-01438 — value larger than specified precision allows

```sql
🔴 BLOCKING | INSERT/UPDATE với số vượt column precision

-- Chẩn đoán
SELECT column_name, data_precision, data_scale FROM dba_tab_columns
WHERE table_name='ORDERS' AND column_name='AMOUNT';

-- Fix
ALTER TABLE orders MODIFY amount NUMBER(15,2);
```

### Case 58: Implicit datatype conversion gây performance issue (không phải lỗi nhưng cần biết)

```sql
🟡 LOGIC | WHERE clause với implicit conversion làm mất index

-- Vấn đề: nếu order_id là VARCHAR2 nhưng so sánh với NUMBER
SELECT * FROM orders WHERE order_id = 12345;  -- Implicit TO_CHAR/TO_NUMBER
-- → Có thể không dùng được index hiệu quả

-- Fix: explicit conversion đúng kiểu cột
SELECT * FROM orders WHERE order_id = '12345';  -- Nếu order_id là VARCHAR2
```

### Case 59: ORA-01861 — literal does not match format string

```sql
🔴 BLOCKING | TO_DATE format string sai

-- Lỗi
SELECT TO_DATE('15/01/2026','YYYY-MM-DD') FROM dual;  -- Format không khớp

-- Fix
SELECT TO_DATE('15/01/2026','DD/MM/YYYY') FROM dual;
```

### Case 60: NLS_NUMERIC_CHARACTERS gây lỗi convert số có dấu phẩy

```sql
🟡 LOGIC | Locale numeric separator khác nhau

-- Vấn đề: '1,234.56' vs '1.234,56' tùy locale
SELECT * FROM nls_session_parameters WHERE parameter='NLS_NUMERIC_CHARACTERS';

-- Fix: explicit specify khi convert
SELECT TO_NUMBER('1,234.56','999,999.99',
  'NLS_NUMERIC_CHARACTERS=''.,''' ) FROM dual;
```

### Case 61: CLOB to VARCHAR2 conversion fail — ORA-22835

```sql
🔴 BLOCKING | CLOB quá lớn không fit VARCHAR2

-- Lỗi
DECLARE
  v_text VARCHAR2(4000);
BEGIN
  SELECT description INTO v_text FROM documents WHERE id=1;  -- CLOB > 4000 chars
END;

-- Fix: dùng SUBSTR hoặc DBMS_LOB
DECLARE
  v_text VARCHAR2(4000);
  v_clob CLOB;
BEGIN
  SELECT description INTO v_clob FROM documents WHERE id=1;
  v_text := DBMS_LOB.SUBSTR(v_clob, 4000, 1);
END;
```

### Case 62: TIMESTAMP WITH TIME ZONE conversion confusion

```sql
🟡 LOGIC | Timezone offset không như mong đợi

-- Chẩn đoán
SELECT SESSIONTIMEZONE, DBTIMEZONE FROM dual;

-- Fix: explicit AT TIME ZONE khi cần convert
SELECT order_date AT TIME ZONE 'Asia/Ho_Chi_Minh' FROM orders;
```

### Case 63: BOOLEAN type không dùng được trực tiếp trong SQL

```sql
🔴 BLOCKING | PL/SQL BOOLEAN không map sang SQL

-- Lỗi
CREATE TABLE test (is_active BOOLEAN);  -- SQL không có BOOLEAN type

-- Fix: dùng NUMBER(1) hoặc CHAR(1) với CHECK constraint
CREATE TABLE test (
  is_active NUMBER(1) CHECK (is_active IN (0,1))
);
-- PL/SQL BOOLEAN chỉ dùng được trong PL/SQL logic, convert khi cần lưu DB
```

### Case 64: RAW/BLOB data hiển thị sai trong SELECT thông thường

```sql
🟢 WARNING | Binary data cần xử lý đặc biệt

-- Fix: dùng UTL_RAW hoặc DBMS_LOB để convert sang readable format
SELECT UTL_RAW.CAST_TO_VARCHAR2(raw_column) FROM table_with_raw;
```

### Case 65: Implicit rounding gây sai lệch số liệu tài chính

```sql
🟡 LOGIC | NUMBER precision không đủ cho calculation chain

-- Vấn đề: rounding errors tích lũy qua nhiều phép tính
DECLARE
  v_total NUMBER(10,2) := 0;
BEGIN
  FOR i IN 1..1000 LOOP
    v_total := v_total + (1/3);  -- Rounding error tích lũy
  END LOOP;
END;

-- Fix: dùng precision cao hơn cho intermediate calculations
DECLARE
  v_total NUMBER := 0;  -- Không giới hạn precision
BEGIN
  FOR i IN 1..1000 LOOP
    v_total := v_total + (1/3);
  END LOOP;
  v_total := ROUND(v_total, 2);  -- Chỉ round ở bước cuối
END;
```

### Case 66: ORA-01480 — trailing null missing from STR bind value

```sql
🟢 WARNING | Bind variable length mismatch giữa calls

-- Thường gặp khi application bind cùng variable với length khác nhau
-- Fix: đảm bảo bind variable length consistent, hoặc pad string
```

### Case 67: INTERVAL DAY TO SECOND arithmetic confusion

```sql
🟡 LOGIC | Date arithmetic với INTERVAL gây kết quả không như ý

-- Chẩn đoán
SELECT SYSDATE + INTERVAL '1' DAY FROM dual;  -- OK
SELECT SYSDATE + 1 FROM dual;  -- Cũng OK (numeric = days)
SELECT SYSDATE + INTERVAL '24' HOUR FROM dual;  -- OK nhưng khác cú pháp

-- Common mistake: trộn lẫn 2 cách không nhất quán
SELECT SYSDATE + INTERVAL '1 12' DAY TO HOUR FROM dual;  -- 1 ngày 12 giờ
```

### Case 68: VARCHAR2 vs NVARCHAR2 character set confusion

```sql
🟡 LOGIC | Unicode data bị lưu sai vào VARCHAR2

-- Chẩn đoán
SELECT * FROM nls_database_parameters
WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET');

-- Fix: dùng NVARCHAR2 cho dữ liệu cần Unicode đầy đủ nếu DB charset không hỗ trợ
CREATE TABLE multilingual_data (
  content NVARCHAR2(4000)
);
```

### Case 69: ROWID thay đổi sau MOVE/SHRINK table (application cache stale ROWID)

```sql
🟡 LOGIC | Application cache ROWID cũ không còn valid

-- Vấn đề: sau ALTER TABLE MOVE, ROWID values thay đổi
ALTER TABLE orders MOVE TABLESPACE new_tbs;
-- Application nào cache ROWID từ trước sẽ bị lỗi khi dùng lại

-- Fix: KHÔNG cache ROWID qua lâu, hoặc rebuild index sau MOVE
ALTER INDEX idx_orders_pk REBUILD;
```

### Case 70: JSON_VALUE trả về NULL thay vì raise error khi path không tồn tại

```sql
🟢 WARNING | Default behavior của JSON functions

-- Đây là default behavior (NULL ON ERROR)
SELECT JSON_VALUE('{"a":1}', '$.b') FROM dual;  -- Trả về NULL, không lỗi

-- Nếu muốn strict checking:
SELECT JSON_VALUE('{"a":1}', '$.b' ERROR ON ERROR) FROM dual;  -- Raises error
```

---

## NHÓM E: BULK OPERATIONS & DYNAMIC SQL (Case 71-85)

### Case 71: BULK COLLECT — ORA-22160 (element at index does not exist)

```sql
🔴 BLOCKING | Truy cập index không tồn tại trong collection

-- Lỗi
DECLARE
  TYPE t_ids IS TABLE OF NUMBER;
  v_ids t_ids := t_ids(1,2,3);
BEGIN
  DBMS_OUTPUT.PUT_LINE(v_ids(5));  -- Index 5 không tồn tại
END;

-- Fix: check COUNT trước khi access
IF v_ids.COUNT >= 5 THEN
  DBMS_OUTPUT.PUT_LINE(v_ids(5));
END IF;
```

### Case 72: FORALL — ORA-22167 (given index must be greater than zero)

```sql
🔴 BLOCKING | FORALL với index range sai

-- Lỗi
FORALL i IN 0..v_ids.COUNT  -- Bắt đầu từ 0 thay vì 1
  UPDATE employees SET salary=v_sals(i) WHERE employee_id=v_ids(i);

-- Fix: PL/SQL collections thường index từ 1
FORALL i IN 1..v_ids.COUNT
  UPDATE employees SET salary=v_sals(i) WHERE employee_id=v_ids(i);
```

### Case 73: BULK COLLECT LIMIT gây partial processing không hoàn chỉnh

```sql
🟡 LOGIC | Quên loop để xử lý hết tất cả batches

-- Lỗi: chỉ fetch 1 batch rồi dừng
OPEN c_cursor;
FETCH c_cursor BULK COLLECT INTO v_batch LIMIT 1000;
-- Xử lý xong, nhưng QUÊN loop lại nếu còn data
CLOSE c_cursor;

-- Fix: luôn dùng LOOP với EXIT WHEN COUNT=0
OPEN c_cursor;
LOOP
  FETCH c_cursor BULK COLLECT INTO v_batch LIMIT 1000;
  EXIT WHEN v_batch.COUNT = 0;
  -- process v_batch
END LOOP;
CLOSE c_cursor;
```

### Case 74: EXECUTE IMMEDIATE — ORA-00911 invalid character (do thừa semicolon)

```sql
🔴 BLOCKING | Dynamic SQL string chứa ký tự thừa

-- Lỗi
EXECUTE IMMEDIATE 'SELECT * FROM employees;';  -- Semicolon thừa trong string

-- Fix: bỏ semicolon trong dynamic SQL string
EXECUTE IMMEDIATE 'SELECT * FROM employees';
```

### Case 75: SQL Injection vulnerability trong dynamic SQL (security issue)

```sql
🔴 BLOCKING (security) | Dynamic SQL ghép string không an toàn

-- NGUY HIỂM: SQL Injection
v_sql := 'SELECT * FROM employees WHERE name = ''' || p_name || '''';
EXECUTE IMMEDIATE v_sql;
-- Nếu p_name = "x' OR '1'='1" → injection thành công!

-- Fix: LUÔN dùng bind variables
EXECUTE IMMEDIATE 'SELECT * FROM employees WHERE name = :1'
  USING p_name;
```

### Case 76: DBMS_SQL — ORA-01001 invalid cursor (chưa OPEN_CURSOR)

```sql
🔴 BLOCKING | DBMS_SQL workflow sai thứ tự

-- Lỗi
DBMS_SQL.PARSE(v_cursor, 'SELECT...', DBMS_SQL.NATIVE);
-- Thiếu OPEN_CURSOR trước đó

-- Fix: đúng thứ tự DBMS_SQL workflow
v_cursor := DBMS_SQL.OPEN_CURSOR;
DBMS_SQL.PARSE(v_cursor, 'SELECT...', DBMS_SQL.NATIVE);
-- ... DEFINE_COLUMN, EXECUTE, FETCH_ROWS, COLUMN_VALUE
DBMS_SQL.CLOSE_CURSOR(v_cursor);
```

### Case 77: Dynamic SQL với DDL — quên COMMIT implicit

```sql
🟢 WARNING | DDL tự động commit, hiểu nhầm transaction behavior

-- DDL trong EXECUTE IMMEDIATE TỰ ĐỘNG COMMIT (cả transaction trước đó!)
INSERT INTO log_table VALUES (1, 'before ddl');
EXECUTE IMMEDIATE 'CREATE TABLE temp_t (id NUMBER)';  -- Implicit COMMIT!
-- INSERT phía trên ĐÃ ĐƯỢC COMMIT, không thể rollback nữa

-- Cẩn thận: tách rõ logic DML và DDL trong transaction design
```

### Case 78: Parallel FORALL với INDICES OF bỏ sót elements bị xóa

```sql
🟡 LOGIC | Hiểu nhầm về sparse collection sau DELETE

-- Lưu ý: nếu DELETE 1 phần tử trong collection, COUNT giảm nhưng index không liền mạch
v_ids.DELETE(5);  -- Index 5 không còn tồn tại
FORALL i IN 1..v_ids.COUNT  -- SAI: COUNT giờ nhỏ hơn LAST
  ...

-- Fix: dùng INDICES OF để handle sparse collection đúng cách
FORALL i IN INDICES OF v_ids
  UPDATE employees SET salary=v_sals(i) WHERE employee_id=v_ids(i);
```

### Case 79: Dynamic PIVOT — string quá dài vượt VARCHAR2 limit

```sql
🔴 BLOCKING | Dynamic SQL string > 32767 chars

-- Lỗi: quá nhiều columns trong PIVOT IN clause
DECLARE
  v_sql VARCHAR2(32767);
BEGIN
  -- Nếu có hàng nghìn distinct values cần PIVOT, string vượt giới hạn

-- Fix: dùng CLOB thay vì VARCHAR2 cho dynamic SQL rất dài
DECLARE
  v_sql CLOB;
BEGIN
  v_sql := 'SELECT ...';
  EXECUTE IMMEDIATE v_sql;
END;
```

### Case 80: REF CURSOR trả về từ procedure nhưng caller không FETCH hết

```sql
🟡 LOGIC | Resource leak khi REF CURSOR không được consume hoàn toàn

-- Fix (application side): luôn fetch hết hoặc explicit close
-- Trên PL/SQL: đảm bảo procedure trả về REF CURSOR đã OPEN đúng cách, không OPEN 2 lần
```

### Case 81: BULK COLLECT vào %ROWTYPE table nhưng SELECT columns không khớp thứ tự

```sql
🟡 LOGIC | Column order mismatch gây data sai lệch

-- Lỗi: SELECT * có thể không khớp đúng order với %ROWTYPE nếu table đã ALTER
DECLARE
  TYPE t_emp IS TABLE OF employees%ROWTYPE;
  v_emps t_emp;
BEGIN
  SELECT * BULK COLLECT INTO v_emps FROM employees;
  -- An toàn vì %ROWTYPE tự match, nhưng nếu dùng custom record thì rủi ro

-- Fix: luôn dùng named columns thay vì SELECT * khi có custom record type
```

### Case 82: Dynamic SQL DESCRIBE_COLUMNS trả về sai column count

```sql
🟡 LOGIC | DBMS_SQL.DESCRIBE_COLUMNS với query phức tạp

-- Fix: verify column count trước khi loop DEFINE_COLUMN
DBMS_SQL.DESCRIBE_COLUMNS(v_cursor, v_col_count, v_desc_tab);
FOR i IN 1..v_col_count LOOP
  DBMS_SQL.DEFINE_COLUMN(v_cursor, i, v_value, 4000);
END LOOP;
```

### Case 83: EXECUTE IMMEDIATE với RETURNING INTO cho multiple rows fail

```sql
🔴 BLOCKING | RETURNING INTO chỉ hỗ trợ single row trong EXECUTE IMMEDIATE thường

-- Lỗi
EXECUTE IMMEDIATE 'UPDATE employees SET salary=salary*1.1
  WHERE department_id=:1 RETURNING employee_id INTO :2'
  USING 60 RETURNING INTO v_id;  -- Fail nếu match nhiều rows

-- Fix: dùng BULK COLLECT cho multiple rows
EXECUTE IMMEDIATE 'UPDATE employees SET salary=salary*1.1
  WHERE department_id=:1 RETURNING employee_id INTO :2'
  USING 60 RETURNING BULK COLLECT INTO v_ids;
```

### Case 84: Parallel DML trong PL/SQL — quên ENABLE PARALLEL DML

```sql
🟡 LOGIC | PARALLEL hint không có tác dụng nếu thiếu session setting

-- Lỗi: hint có nhưng DML vẫn chạy serial
INSERT /*+ PARALLEL(t,4) */ INTO target_table
SELECT /*+ PARALLEL(s,4) */ * FROM source_table;
-- Thiếu ALTER SESSION trước đó

-- Fix
ALTER SESSION ENABLE PARALLEL DML;
INSERT /*+ PARALLEL(t,4) */ INTO target_table
SELECT /*+ PARALLEL(s,4) */ * FROM source_table;
COMMIT;
```

### Case 85: Dynamic SQL với DDL trong loop gây hard parse storm

```sql
🟡 LOGIC | Performance issue do thiếu caching

-- Anti-pattern: tạo DDL động trong loop lớn
FOR i IN 1..1000 LOOP
  EXECUTE IMMEDIATE 'CREATE TABLE temp_'||i||' (id NUMBER)';
  -- Mỗi lần là 1 hard parse, rất chậm
END LOOP;

-- Fix: tránh pattern này, dùng global temporary table hoặc partition thay vì nhiều tables
```

---

## NHÓM F: JSON / XML & MODERN FEATURES (Case 86-100)

### Case 86: ORA-40441 — JSON syntax error

```sql
🔴 BLOCKING | JSON malformed

-- Lỗi
SELECT JSON_VALUE('{"name":"John"', '$.name') FROM dual;  -- Thiếu dấu }

-- Fix: validate JSON trước
SELECT CASE WHEN '{"name":"John"}' IS JSON THEN 'Valid' ELSE 'Invalid' END FROM dual;
```

### Case 87: JSON_TABLE trả về 0 rows dù data hợp lệ

```sql
🟡 LOGIC | JSON Path expression sai

-- Lỗi: path không khớp cấu trúc thực tế
SELECT * FROM JSON_TABLE('{"items":[{"id":1}]}', '$.item[*]'  -- Sai: "item" thay vì "items"
  COLUMNS (id NUMBER PATH '$.id'));

-- Fix
SELECT * FROM JSON_TABLE('{"items":[{"id":1}]}', '$.items[*]'
  COLUMNS (id NUMBER PATH '$.id'));
```

### Case 88: ORA-31011 — XML parsing failed

```sql
🔴 BLOCKING | Invalid XML structure

-- Chẩn đoán
SELECT XMLType('<root><item>test</root>') FROM dual;  -- Tag không đóng đúng

-- Fix: validate XML structure
SELECT XMLType('<root><item>test</item></root>') FROM dual;
```

### Case 89: XMLTABLE — namespace not declared error

```sql
🔴 BLOCKING | XML namespace prefix không định nghĩa

-- Lỗi
SELECT * FROM XMLTABLE('/ns:root/ns:item'
  PASSING xml_col
  COLUMNS id NUMBER PATH 'ns:id');  -- "ns" namespace chưa khai báo

-- Fix: declare namespace trong XMLTABLE
SELECT * FROM XMLTABLE(
  XMLNAMESPACES('http://example.com' AS "ns"),
  '/ns:root/ns:item' PASSING xml_col
  COLUMNS id NUMBER PATH 'ns:id'
);
```

### Case 90: JSON_OBJECT — duplicate key trong output

```sql
🟡 LOGIC | JSON tự động hợp lệ với duplicate keys (nhưng confusing)

-- Cẩn thận
SELECT JSON_OBJECT('id' VALUE 1, 'id' VALUE 2) FROM dual;
-- Kết quả: {"id":1,"id":2} — Valid JSON nhưng ambiguous khi parse lại

-- Fix: đảm bảo key names unique trong construction logic
```

### Case 91: VECTOR data type — dimension mismatch (23ai/26ai)

```sql
🔴 BLOCKING | Vector embedding sai số chiều

-- Lỗi
CREATE TABLE docs (embedding VECTOR(768));
INSERT INTO docs VALUES (TO_VECTOR('[1,2,3]'));  -- Chỉ 3 dims, cần 768

-- Fix: đảm bảo dimension khớp định nghĩa cột
-- Kiểm tra model output dimension trước khi insert
SELECT VECTOR_DIMS(embedding) FROM docs;
```

### Case 92: JSON Duality View — update conflict (concurrent modification)

```sql
🟡 LOGIC | Optimistic locking conflict trong JSON Duality View

-- Chẩn đoán: version mismatch khi update
-- Fix: implement retry logic ở application layer khi gặp conflict
-- Hoặc dùng ETAG/version field để handle concurrency
```

### Case 93: PIVOT với XML output format không như mong đợi

```sql
🟡 LOGIC | PIVOT XML clause syntax confusion

-- Cú pháp đặc biệt cho PIVOT XML (khác PIVOT thường)
SELECT * FROM (SELECT department_id, job_id, salary FROM employees)
PIVOT XML (SUM(salary) FOR job_id IN (SELECT DISTINCT job_id FROM jobs));
-- Output dạng XML thay vì columns thông thường — đây là expected behavior
```

### Case 94: LISTAGG — ORA-01489 result string too long

```sql
🔴 BLOCKING | Aggregated string vượt 4000 bytes (hoặc 32767 với extended)

-- Lỗi
SELECT LISTAGG(description, ',') WITHIN GROUP (ORDER BY id)
FROM large_table GROUP BY category;  -- Quá nhiều rows, string quá dài

-- Fix: dùng ON OVERFLOW TRUNCATE (19c+)
SELECT LISTAGG(description, ',' ON OVERFLOW TRUNCATE '...' WITH COUNT)
  WITHIN GROUP (ORDER BY id)
FROM large_table GROUP BY category;
```

### Case 95: Regular Expression — REGEXP_SUBSTR trả về NULL không như mong đợi

```sql
🟡 LOGIC | Regex pattern không match do escape characters

-- Lỗi
SELECT REGEXP_SUBSTR('price: $100.50', '\$[0-9.]+') FROM dual;
-- Backslash có thể cần escape khác trong Oracle regex

-- Fix: test pattern riêng, dùng REGEXP_LIKE để verify trước
SELECT REGEXP_SUBSTR('price: $100.50', '\$[0-9]+\.[0-9]+') FROM dual;
```

### Case 96: VECTOR_DISTANCE — ORA error khi so sánh vectors khác dimension

```sql
🔴 BLOCKING | Vector dimension mismatch trong distance calculation

-- Lỗi
SELECT VECTOR_DISTANCE(v1, v2, COSINE) FROM dual
WHERE VECTOR_DIMS(v1) != VECTOR_DIMS(v2);  -- Sẽ fail

-- Fix: đảm bảo cùng model tạo embedding cho cả 2 vectors
```

### Case 97: JSON_MERGEPATCH — patch không apply đúng nested structure

```sql
🟡 LOGIC | JSON_MERGEPATCH semantics khác JSON_TRANSFORM

-- Lưu ý: JSON_MERGEPATCH thay thế HOÀN TOÀN nested object, không merge sâu
SELECT JSON_MERGEPATCH('{"a":{"x":1,"y":2}}', '{"a":{"x":3}}') FROM dual;
-- Kết quả: {"a":{"x":3}} — mất luôn "y":2!

-- Fix: nếu cần deep merge, dùng JSON_TRANSFORM thay thế
```

### Case 98: XMLAGG — output thiếu wrapper element

```sql
🟢 WARNING | XMLAGG cần XMLElement bao ngoài để có root hợp lệ

-- Lỗi: output không có single root element
SELECT XMLAGG(XMLElement("item", employee_id)) FROM employees;
-- Nhiều <item> elements không có wrapper → invalid XML document

-- Fix: bọc trong root element
SELECT XMLElement("items", XMLAGG(XMLElement("item", employee_id)))
FROM employees;
```

### Case 99: Multitenant + Vector Index — index không dùng được cross-PDB

```sql
🟡 LOGIC | Vector Index scope giới hạn trong PDB

-- Hiểu nhầm: Vector Index (như mọi index khác) chỉ valid trong PDB tạo ra nó
-- Không thể query cross-PDB và dùng index đó trực tiếp
-- Fix: thiết kế ứng dụng aware về PDB boundary, hoặc dùng common objects nếu cần share
```

### Case 100: DBMS_VECTOR_CHAIN — timeout khi gọi external LLM API

```sql
🟡 LOGIC | Network timeout trong RAG pipeline (26ai)

-- Chẩn đoán: kiểm tra ACL cho phép outbound connection
SELECT * FROM dba_network_acls;

-- Fix: tăng timeout hoặc kiểm tra network connectivity
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'api.openai.com',
    ace => XS$ACE_TYPE(privilege_list => XS$NAME_LIST('http'),
                       principal_name => 'APP_USER',
                       principal_type => XS_ACL.PTYPE_DB)
  );
END;
/
```

---

## TỔNG KẾT — QUICK REFERENCE TABLE

```
Top 10 Lỗi SQL/PLSQL Thường Gặp Nhất:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. ORA-00942 (Table/view not exist)     → Case 2
2. ORA-01403 (No data found)            → Case 42
3. ORA-04091 (Mutating table)           → Case 30, 41
4. ORA-01722 (Invalid number)           → Case 7
5. ORA-06502 (Buffer too small)         → Case 46
6. ORA-00904 (Invalid identifier)       → Case 3
7. PLS-00201 (Identifier not declared)  → Case 22
8. ORA-01400 (NULL constraint)          → Case 13
9. ORA-00001 (Unique constraint)        → Case 17
10. ORA-01000 (Max cursors / leak)      → Case 44
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Tài liệu tham khảo:**
- Oracle Database Error Messages 19c
- Oracle Database PL/SQL Language Reference 19c
- Oracle AI Vector Search User's Guide 23ai
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
