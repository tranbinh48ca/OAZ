---
name: oracle-plsql-complete
description: >
  PL/SQL Oracle toàn diện từ cơ bản đến nâng cao.
  Kích hoạt khi hỏi về: PL/SQL Oracle, PL/SQL block structure,
  DECLARE BEGIN EXCEPTION END Oracle, variable declaration Oracle,
  %TYPE %ROWTYPE Oracle, IF ELSIF ELSE Oracle, LOOP FOR WHILE Oracle,
  CURSOR Oracle, explicit cursor implicit cursor, cursor FOR loop,
  ref cursor Oracle, SYS_REFCURSOR, exception handling Oracle,
  WHEN OTHERS SQLCODE SQLERRM Oracle, RAISE RAISE_APPLICATION_ERROR,
  stored procedure Oracle, function Oracle, package Oracle spec body,
  trigger Oracle DML DDL INSTEAD OF, dynamic SQL EXECUTE IMMEDIATE,
  DBMS_SQL Oracle, bulk collect FORALL Oracle, SAVE EXCEPTIONS Oracle,
  collections Oracle nested table varray associative array,
  DBMS_OUTPUT UTL_FILE UTL_MAIL Oracle packages, autonomous transaction,
  pipelined function Oracle, object types Oracle, PL/SQL performance.
---

# SK03-03 to SK03-10 · PL/SQL Complete Guide

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

# SK03-03 · PL/SQL BLOCK STRUCTURE & FUNDAMENTALS

## 1. Block Structure

```sql
-- Anonymous block (không lưu vào DB)
DECLARE
  -- Declaration section (optional)
  v_emp_name   VARCHAR2(100);
  v_salary     NUMBER(10,2) := 0;
  v_count      PLS_INTEGER  := 0;
  v_date       DATE         := SYSDATE;
  v_bool       BOOLEAN      := TRUE;
  c_max_sal    CONSTANT NUMBER := 50000;  -- Constant
BEGIN
  -- Execution section (required)
  SELECT first_name || ' ' || last_name, salary
  INTO v_emp_name, v_salary
  FROM employees
  WHERE employee_id = 100;

  IF v_salary > c_max_sal THEN
    DBMS_OUTPUT.PUT_LINE('High earner: ' || v_emp_name);
  ELSE
    DBMS_OUTPUT.PUT_LINE('Employee: ' || v_emp_name ||
                         ' Salary: ' || v_salary);
  END IF;

EXCEPTION
  -- Exception handling section (optional)
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Employee not found');
  WHEN TOO_MANY_ROWS THEN
    DBMS_OUTPUT.PUT_LINE('Multiple employees found');
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
    RAISE;  -- Re-raise exception
END;
/
```

## 2. Data Types và Variables

```sql
DECLARE
  -- Anchored types (từ DB schema)
  v_name     employees.first_name%TYPE;        -- Lấy type từ column
  v_emp_rec  employees%ROWTYPE;                -- Entire row record
  v_dept_rec departments%ROWTYPE;

  -- Record type (định nghĩa tự)
  TYPE emp_info_t IS RECORD (
    id       employees.employee_id%TYPE,
    name     VARCHAR2(100),
    salary   employees.salary%TYPE,
    dept     departments.department_name%TYPE
  );
  v_emp_info emp_info_t;

  -- Subtypes
  SUBTYPE salary_t IS NUMBER(10,2);
  v_sal salary_t;

  -- Collections (xem SK03-07)
  TYPE id_list_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_ids id_list_t;

BEGIN
  -- Dùng %ROWTYPE
  SELECT * INTO v_emp_rec FROM employees WHERE employee_id = 100;
  DBMS_OUTPUT.PUT_LINE(v_emp_rec.first_name || ' ' || v_emp_rec.last_name);

  -- Dùng record type
  SELECT e.employee_id, e.first_name || ' ' || e.last_name,
         e.salary, d.department_name
  INTO v_emp_info
  FROM employees e JOIN departments d
    ON e.department_id = d.department_id
  WHERE e.employee_id = 100;
END;
/
```

## 3. Control Flow

```sql
DECLARE
  v_score NUMBER := 85;
  v_grade CHAR(1);
BEGIN
  -- ── IF/ELSIF/ELSE ─────────────────────────────────────
  IF v_score >= 90 THEN
    v_grade := 'A';
  ELSIF v_score >= 80 THEN
    v_grade := 'B';
  ELSIF v_score >= 70 THEN
    v_grade := 'C';
  ELSE
    v_grade := 'F';
  END IF;

  -- ── CASE ─────────────────────────────────────────────
  v_grade := CASE
    WHEN v_score >= 90 THEN 'A'
    WHEN v_score >= 80 THEN 'B'
    WHEN v_score >= 70 THEN 'C'
    ELSE 'F'
  END;

  -- ── Basic LOOP với EXIT ────────────────────────────────
  DECLARE v_i NUMBER := 1;
  BEGIN
    LOOP
      EXIT WHEN v_i > 5;
      DBMS_OUTPUT.PUT_LINE('Iteration: ' || v_i);
      v_i := v_i + 1;
    END LOOP;
  END;

  -- ── WHILE LOOP ───────────────────────────────────────
  DECLARE v_i NUMBER := 1;
  BEGIN
    WHILE v_i <= 5 LOOP
      DBMS_OUTPUT.PUT_LINE('While: ' || v_i);
      v_i := v_i + 1;
    END LOOP;
  END;

  -- ── FOR LOOP (numeric) ───────────────────────────────
  FOR i IN 1..10 LOOP
    DBMS_OUTPUT.PUT_LINE('For: ' || i);
  END LOOP;

  FOR i IN REVERSE 10..1 LOOP  -- Đếm ngược
    DBMS_OUTPUT.PUT_LINE('Reverse: ' || i);
  END LOOP;

  -- ── CONTINUE (11g+) ──────────────────────────────────
  FOR i IN 1..10 LOOP
    CONTINUE WHEN MOD(i, 2) = 0;  -- Skip even numbers
    DBMS_OUTPUT.PUT_LINE('Odd: ' || i);
  END LOOP;
END;
/
```

## 4. Exception Handling

```sql
DECLARE
  -- User-defined exceptions
  e_salary_too_high EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_salary_too_high, -20001);  -- Link to error code

  v_salary NUMBER;
BEGIN
  SELECT salary INTO v_salary FROM employees WHERE employee_id = &emp_id;

  -- Raise user-defined exception
  IF v_salary > 30000 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Salary ' || v_salary || ' too high!');
  END IF;

  -- Raise predefined exception
  IF v_salary < 0 THEN
    RAISE VALUE_ERROR;
  END IF;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Employee not found. SQLCODE: ' || SQLCODE);

  WHEN TOO_MANY_ROWS THEN
    DBMS_OUTPUT.PUT_LINE('Multiple employees: ' || SQLERRM);

  WHEN e_salary_too_high THEN
    DBMS_OUTPUT.PUT_LINE('Custom error: ' || SQLERRM);

  WHEN VALUE_ERROR THEN
    DBMS_OUTPUT.PUT_LINE('Value error occurred');

  WHEN DUP_VAL_ON_INDEX THEN
    DBMS_OUTPUT.PUT_LINE('Duplicate key violation');

  WHEN OTHERS THEN
    -- Log full error info
    DBMS_OUTPUT.PUT_LINE('Unexpected error:');
    DBMS_OUTPUT.PUT_LINE('  Code: ' || SQLCODE);
    DBMS_OUTPUT.PUT_LINE('  Msg:  ' || SQLERRM);
    DBMS_OUTPUT.PUT_LINE('  Trace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    RAISE;  -- Re-raise to caller
END;
/

-- Error logging best practice
CREATE OR REPLACE PROCEDURE log_error(
  p_proc_name IN VARCHAR2,
  p_error_msg IN VARCHAR2
) AS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO error_log (log_date, proc_name, error_code, error_msg, error_stack)
  VALUES (SYSTIMESTAMP, p_proc_name, SQLCODE, SQLERRM,
          DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
  COMMIT;
END;
/
```

---

# SK03-04 · CURSORS

## 1. Implicit Cursors

```sql
BEGIN
  UPDATE employees SET salary = salary * 1.1
  WHERE department_id = 60;

  -- SQL%ROWCOUNT, SQL%FOUND, SQL%NOTFOUND, SQL%ISOPEN
  IF SQL%FOUND THEN
    DBMS_OUTPUT.PUT_LINE('Updated: ' || SQL%ROWCOUNT || ' rows');
  ELSE
    DBMS_OUTPUT.PUT_LINE('No rows updated');
  END IF;
  COMMIT;
END;
/
```

## 2. Explicit Cursors

```sql
DECLARE
  -- Cursor declaration
  CURSOR c_emp (p_dept_id NUMBER, p_min_sal NUMBER) IS
    SELECT employee_id, first_name, last_name, salary
    FROM employees
    WHERE department_id = p_dept_id
      AND salary >= p_min_sal
    ORDER BY salary DESC
    FOR UPDATE OF salary NOWAIT;  -- Lock rows for update

  v_emp_rec c_emp%ROWTYPE;

BEGIN
  -- Open cursor with parameters
  OPEN c_emp(60, 5000);

  LOOP
    FETCH c_emp INTO v_emp_rec;
    EXIT WHEN c_emp%NOTFOUND;

    -- Process row
    UPDATE employees SET salary = salary * 1.05
    WHERE CURRENT OF c_emp;  -- Update locked row (FOR UPDATE cursor only)

    DBMS_OUTPUT.PUT_LINE(
      v_emp_rec.first_name || ': ' || v_emp_rec.salary ||
      ' → ' || ROUND(v_emp_rec.salary * 1.05, 2)
    );
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Total: ' || c_emp%ROWCOUNT || ' employees');
  CLOSE c_emp;
  COMMIT;
END;
/

-- ── Cursor FOR Loop (simpler, auto open/close) ────────────
BEGIN
  FOR emp IN (
    SELECT employee_id, first_name, salary, department_id
    FROM employees
    WHERE salary > 8000
    ORDER BY department_id, salary DESC
  ) LOOP
    -- emp.employee_id, emp.first_name, etc.
    DBMS_OUTPUT.PUT_LINE(emp.first_name || ' | ' || emp.salary);
  END LOOP;
END;
/
```

## 3. REF CURSOR (Dynamic Cursors)

```sql
-- Weak REF CURSOR (SYS_REFCURSOR)
CREATE OR REPLACE PROCEDURE get_employees(
  p_dept_id  IN  NUMBER,
  p_cursor   OUT SYS_REFCURSOR
) AS
BEGIN
  IF p_dept_id IS NULL THEN
    OPEN p_cursor FOR
      SELECT employee_id, first_name, salary FROM employees;
  ELSE
    OPEN p_cursor FOR
      SELECT employee_id, first_name, salary FROM employees
      WHERE department_id = p_dept_id;
  END IF;
END;
/

-- Strong REF CURSOR (typed)
DECLARE
  TYPE emp_cur_t IS REF CURSOR RETURN employees%ROWTYPE;
  c_emp emp_cur_t;
  v_rec employees%ROWTYPE;
BEGIN
  OPEN c_emp FOR SELECT * FROM employees WHERE salary > 10000;
  LOOP
    FETCH c_emp INTO v_rec;
    EXIT WHEN c_emp%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_rec.first_name);
  END LOOP;
  CLOSE c_emp;
END;
/
```

---

# SK03-05 · STORED PROCEDURES & FUNCTIONS

## 1. Procedures

```sql
CREATE OR REPLACE PROCEDURE update_employee_salary(
  p_employee_id  IN  employees.employee_id%TYPE,
  p_pct_increase IN  NUMBER,
  p_new_salary   OUT employees.salary%TYPE,
  p_status       OUT VARCHAR2
) AS
  v_current_salary employees.salary%TYPE;
  v_max_salary     NUMBER := 30000;
  e_too_high       EXCEPTION;
BEGIN
  -- Validate input
  IF p_pct_increase < 0 OR p_pct_increase > 100 THEN
    RAISE VALUE_ERROR;
  END IF;

  -- Get current salary (lock row)
  SELECT salary INTO v_current_salary
  FROM employees
  WHERE employee_id = p_employee_id
  FOR UPDATE NOWAIT;

  -- Calculate new salary
  p_new_salary := ROUND(v_current_salary * (1 + p_pct_increase/100), 2);

  -- Validate new salary
  IF p_new_salary > v_max_salary THEN
    p_new_salary := v_max_salary;
  END IF;

  -- Apply update
  UPDATE employees
  SET salary = p_new_salary,
      last_updated = SYSDATE
  WHERE employee_id = p_employee_id;

  COMMIT;
  p_status := 'SUCCESS: ' || v_current_salary || ' → ' || p_new_salary;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    p_status := 'ERROR: Employee ' || p_employee_id || ' not found';
    p_new_salary := NULL;
  WHEN OTHERS THEN
    ROLLBACK;
    p_status := 'ERROR: ' || SQLERRM;
    p_new_salary := NULL;
END update_employee_salary;
/

-- Call procedure
DECLARE
  v_new_sal NUMBER;
  v_status  VARCHAR2(200);
BEGIN
  update_employee_salary(100, 10, v_new_sal, v_status);
  DBMS_OUTPUT.PUT_LINE('Status: ' || v_status);
END;
/
```

## 2. Functions

```sql
-- Deterministic function (optimizer can cache result)
CREATE OR REPLACE FUNCTION get_dept_avg_salary(
  p_dept_id IN NUMBER
) RETURN NUMBER
DETERMINISTIC IS
  v_avg_sal NUMBER;
BEGIN
  SELECT AVG(salary) INTO v_avg_sal
  FROM employees WHERE department_id = p_dept_id;
  RETURN NVL(v_avg_sal, 0);
EXCEPTION
  WHEN NO_DATA_FOUND THEN RETURN 0;
  WHEN OTHERS THEN RAISE;
END;
/

-- Function dùng trong SQL
SELECT department_id, department_name,
       get_dept_avg_salary(department_id) avg_salary
FROM departments
ORDER BY avg_salary DESC;

-- Pipelined function (trả về rows như table)
CREATE OR REPLACE TYPE emp_rec_t AS OBJECT (
  employee_id NUMBER,
  full_name   VARCHAR2(100),
  salary      NUMBER
);
/
CREATE OR REPLACE TYPE emp_table_t AS TABLE OF emp_rec_t;
/

CREATE OR REPLACE FUNCTION get_dept_employees(p_dept_id NUMBER)
  RETURN emp_table_t PIPELINED AS
BEGIN
  FOR emp IN (
    SELECT employee_id, first_name || ' ' || last_name full_name, salary
    FROM employees WHERE department_id = p_dept_id
    ORDER BY salary DESC
  ) LOOP
    PIPE ROW(emp_rec_t(emp.employee_id, emp.full_name, emp.salary));
  END LOOP;
  RETURN;  -- Required for PIPELINED
END;
/

-- Dùng như table
SELECT * FROM TABLE(get_dept_employees(60));
-- Can join with other tables:
SELECT e.*, d.department_name
FROM TABLE(get_dept_employees(60)) e
CROSS JOIN departments d WHERE d.department_id = 60;
```

---

# SK03-06 · PACKAGES

```sql
-- ── Package Specification ─────────────────────────────────
CREATE OR REPLACE PACKAGE pkg_hr_manager AS
  -- Public constants
  c_max_salary    CONSTANT NUMBER        := 50000;
  c_default_dept  CONSTANT NUMBER        := 10;

  -- Public types
  TYPE emp_info_t IS RECORD (
    id      employees.employee_id%TYPE,
    name    VARCHAR2(100),
    salary  employees.salary%TYPE
  );
  TYPE emp_list_t IS TABLE OF emp_info_t;

  -- Public exceptions
  e_invalid_salary EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_invalid_salary, -20100);

  -- Public subprograms
  FUNCTION  get_employee(p_id IN NUMBER) RETURN emp_info_t;
  PROCEDURE hire_employee(
    p_first_name  IN VARCHAR2,
    p_last_name   IN VARCHAR2,
    p_salary      IN NUMBER,
    p_dept_id     IN NUMBER,
    p_emp_id      OUT NUMBER
  );
  PROCEDURE update_salary(p_emp_id IN NUMBER, p_new_sal IN NUMBER);
  FUNCTION  dept_headcount(p_dept_id IN NUMBER) RETURN NUMBER;
  FUNCTION  get_dept_team(p_dept_id IN NUMBER) RETURN emp_list_t PIPELINED;

END pkg_hr_manager;
/

-- ── Package Body ─────────────────────────────────────────
CREATE OR REPLACE PACKAGE BODY pkg_hr_manager AS
  -- Private variables (package-level state, persists for session)
  g_call_count   PLS_INTEGER := 0;
  g_last_emp_id  NUMBER;

  -- Private procedure (not in spec)
  PROCEDURE log_activity(p_action VARCHAR2) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO hr_activity_log VALUES(SYSDATE, USER, p_action);
    COMMIT;
  END;

  -- Initialization block (runs once when package is first used)
  -- (at bottom of package body)

  FUNCTION get_employee(p_id IN NUMBER) RETURN emp_info_t AS
    v_rec emp_info_t;
  BEGIN
    g_call_count := g_call_count + 1;
    SELECT employee_id, first_name||' '||last_name, salary
    INTO v_rec.id, v_rec.name, v_rec.salary
    FROM employees WHERE employee_id = p_id;
    g_last_emp_id := p_id;
    RETURN v_rec;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20099, 'Employee '||p_id||' not found');
  END;

  PROCEDURE hire_employee(
    p_first_name IN VARCHAR2, p_last_name IN VARCHAR2,
    p_salary IN NUMBER, p_dept_id IN NUMBER, p_emp_id OUT NUMBER
  ) AS
  BEGIN
    IF p_salary < 0 OR p_salary > c_max_salary THEN
      RAISE_APPLICATION_ERROR(-20100,
        'Salary must be 0-' || c_max_salary);
    END IF;
    INSERT INTO employees(employee_id, first_name, last_name,
                          email, hire_date, job_id, salary, department_id)
    VALUES(employee_seq.NEXTVAL, p_first_name, p_last_name,
           LOWER(p_first_name)||'.'||LOWER(p_last_name)||'@co.vn',
           SYSDATE, 'IT_PROG', p_salary, p_dept_id)
    RETURNING employee_id INTO p_emp_id;
    COMMIT;
    log_activity('HIRE employee ' || p_emp_id);
  END;

  PROCEDURE update_salary(p_emp_id IN NUMBER, p_new_sal IN NUMBER) AS
  BEGIN
    IF p_new_sal > c_max_salary THEN
      RAISE e_invalid_salary;
    END IF;
    UPDATE employees SET salary = p_new_sal WHERE employee_id = p_emp_id;
    IF SQL%ROWCOUNT = 0 THEN
      RAISE NO_DATA_FOUND;
    END IF;
    COMMIT;
    log_activity('UPDATE salary emp ' || p_emp_id || ' → ' || p_new_sal);
  END;

  FUNCTION dept_headcount(p_dept_id IN NUMBER) RETURN NUMBER AS
    v_count NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_count FROM employees
    WHERE department_id = p_dept_id;
    RETURN v_count;
  END;

  FUNCTION get_dept_team(p_dept_id IN NUMBER)
    RETURN emp_list_t PIPELINED AS
    v_rec emp_info_t;
  BEGIN
    FOR e IN (SELECT employee_id, first_name||' '||last_name, salary
              FROM employees WHERE department_id = p_dept_id) LOOP
      v_rec.id := e.employee_id;
      v_rec.name := e.first_name||' '||e.last_name;
      v_rec.salary := e.salary;
      PIPE ROW(v_rec);
    END LOOP;
  END;

BEGIN
  -- Package initialization block
  DBMS_OUTPUT.PUT_LINE('pkg_hr_manager initialized for ' || USER);
  g_call_count := 0;
END pkg_hr_manager;
/

-- ── Sử dụng package ──────────────────────────────────────
DECLARE
  v_emp pkg_hr_manager.emp_info_t;
  v_new_id NUMBER;
BEGIN
  -- Call function
  v_emp := pkg_hr_manager.get_employee(100);
  DBMS_OUTPUT.PUT_LINE(v_emp.name || ': ' || v_emp.salary);

  -- Call procedure
  pkg_hr_manager.hire_employee('Binh','Tran',12000,60, v_new_id);

  -- Constant
  DBMS_OUTPUT.PUT_LINE('Max salary: ' || pkg_hr_manager.c_max_salary);
END;
/

-- Pipelined function in SELECT
SELECT id, name, salary FROM TABLE(pkg_hr_manager.get_dept_team(60));
```

---

# SK03-07 · COLLECTIONS

```sql
-- ── 1. ASSOCIATIVE ARRAY (INDEX BY) ───────────────────────
-- Most flexible, in-memory only, can use STRING keys
DECLARE
  TYPE salary_by_name_t IS TABLE OF NUMBER
    INDEX BY VARCHAR2(100);                 -- String key
  TYPE emp_by_id_t IS TABLE OF employees%ROWTYPE
    INDEX BY PLS_INTEGER;                   -- Integer key

  v_salaries  salary_by_name_t;
  v_employees emp_by_id_t;
  v_key       VARCHAR2(100);

BEGIN
  -- Populate
  v_salaries('John') := 5000;
  v_salaries('Jane') := 7000;
  v_salaries('Bob')  := 6500;

  -- Iterate
  v_key := v_salaries.FIRST;
  WHILE v_key IS NOT NULL LOOP
    DBMS_OUTPUT.PUT_LINE(v_key || ': ' || v_salaries(v_key));
    v_key := v_salaries.NEXT(v_key);
  END LOOP;

  -- Collection methods
  DBMS_OUTPUT.PUT_LINE('Count: ' || v_salaries.COUNT);
  DBMS_OUTPUT.PUT_LINE('Exists John: ' || CASE WHEN v_salaries.EXISTS('John') THEN 'Y' ELSE 'N' END);
  v_salaries.DELETE('Bob');  -- Delete element
  v_salaries.DELETE;         -- Delete all
END;
/

-- ── 2. NESTED TABLE ──────────────────────────────────────
-- Stored in DB, unbounded, can use MULTISET operations
CREATE OR REPLACE TYPE num_list_t AS TABLE OF NUMBER;
/

DECLARE
  v_nums num_list_t := num_list_t(1, 2, 3, 4, 5);
  v_more num_list_t := num_list_t(4, 5, 6, 7, 8);
BEGIN
  -- Extend and add
  v_nums.EXTEND;
  v_nums(v_nums.LAST) := 6;
  v_nums.EXTEND(3);  -- Add 3 NULL slots

  -- MULTISET operations
  DECLARE
    v_union     num_list_t := v_nums MULTISET UNION v_more;
    v_intersect num_list_t := v_nums MULTISET INTERSECT v_more;
    v_except    num_list_t := v_nums MULTISET EXCEPT v_more;
  BEGIN
    -- Use in SQL
    SELECT column_value FROM TABLE(v_intersect);
  END;

  -- Delete specific elements
  v_nums.DELETE(3);  -- Delete element at index 3
  v_nums.DELETE(2,4); -- Delete elements 2 through 4

  -- Trim from end
  v_nums.TRIM;    -- Remove last element
  v_nums.TRIM(2); -- Remove last 2 elements
END;
/

-- ── 3. VARRAY (Variable-size Array) ─────────────────────
-- Fixed max size, stored inline in table
CREATE OR REPLACE TYPE phone_varray_t AS VARRAY(5) OF VARCHAR2(20);
/

DECLARE
  v_phones phone_varray_t := phone_varray_t(
    '0912345678', '0987654321', '0901234567'
  );
BEGIN
  DBMS_OUTPUT.PUT_LINE('Phones: ' || v_phones.COUNT);
  v_phones.EXTEND;
  v_phones(v_phones.LAST) := '0961111111';

  FOR i IN v_phones.FIRST..v_phones.LAST LOOP
    DBMS_OUTPUT.PUT_LINE(i || ': ' || v_phones(i));
  END LOOP;
END;
/

-- Collection in SQL (TABLE function)
SELECT t.column_value phone
FROM TABLE(phone_varray_t('0912345678','0987654321')) t;
```

---

# SK03-08 · BULK OPERATIONS

```sql
-- ── BULK COLLECT ─────────────────────────────────────────
-- Fetch nhiều rows vào collection một lần (nhanh hơn row-by-row 10-100x)

DECLARE
  TYPE emp_id_t  IS TABLE OF employees.employee_id%TYPE;
  TYPE emp_sal_t IS TABLE OF employees.salary%TYPE;
  TYPE emp_rec_t IS TABLE OF employees%ROWTYPE;

  v_ids    emp_id_t;
  v_sals   emp_sal_t;
  v_emps   emp_rec_t;

BEGIN
  -- Bulk collect entire table
  SELECT employee_id, salary
  BULK COLLECT INTO v_ids, v_sals
  FROM employees
  WHERE department_id = 60;

  DBMS_OUTPUT.PUT_LINE('Fetched: ' || v_ids.COUNT || ' employees');

  -- With LIMIT (cho bảng lớn, tránh memory issue)
  DECLARE
    CURSOR c_all IS SELECT * FROM large_orders;
    v_batch emp_rec_t;
    BATCH_SIZE CONSTANT PLS_INTEGER := 1000;
  BEGIN
    OPEN c_all;
    LOOP
      FETCH c_all BULK COLLECT INTO v_batch LIMIT BATCH_SIZE;
      EXIT WHEN v_batch.COUNT = 0;

      -- Process batch
      FOR i IN 1..v_batch.COUNT LOOP
        -- Process v_batch(i)
        NULL;
      END LOOP;

      DBMS_OUTPUT.PUT_LINE('Processed batch: ' || v_batch.COUNT);
    END LOOP;
    CLOSE c_all;
  END;
END;
/

-- ── FORALL (bulk DML — tốt hơn loop DML nhiều lần) ───────
DECLARE
  TYPE id_t  IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE sal_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_ids  id_t;
  v_sals sal_t;
  v_errors NUMBER := 0;
BEGIN
  -- Load data to update
  SELECT employee_id, salary * 1.1
  BULK COLLECT INTO v_ids, v_sals
  FROM employees WHERE department_id = 60;

  -- Bulk update (single context switch vs N individual updates)
  BEGIN
    FORALL i IN 1..v_ids.COUNT
      SAVE EXCEPTIONS  -- Tiếp tục khi có lỗi, lưu exceptions
      UPDATE employees
      SET salary = v_sals(i)
      WHERE employee_id = v_ids(i);

    DBMS_OUTPUT.PUT_LINE('Updated: ' || SQL%ROWCOUNT);

  EXCEPTION
    WHEN OTHERS THEN
      v_errors := SQL%BULK_EXCEPTIONS.COUNT;
      FOR i IN 1..v_errors LOOP
        DBMS_OUTPUT.PUT_LINE(
          'Error at index ' || SQL%BULK_EXCEPTIONS(i).ERROR_INDEX ||
          ': ' || SQLERRM(-SQL%BULK_EXCEPTIONS(i).ERROR_CODE)
        );
      END LOOP;
  END;

  COMMIT;
END;
/

-- ── FORALL with INSERT ────────────────────────────────────
DECLARE
  TYPE t_emp IS TABLE OF employees%ROWTYPE;
  v_new_emps t_emp;
BEGIN
  -- Build collection
  SELECT * BULK COLLECT INTO v_new_emps
  FROM staging_employees WHERE validated = 'Y';

  -- Bulk insert
  FORALL i IN v_new_emps.FIRST..v_new_emps.LAST
    INSERT INTO employees VALUES v_new_emps(i);

  -- With INDICES OF (skip deleted elements)
  v_new_emps.DELETE(3);
  FORALL i IN INDICES OF v_new_emps  -- Skip index 3
    INSERT INTO employees VALUES v_new_emps(i);

  -- With VALUES OF (use specific indices from another array)
  FORALL i IN VALUES OF (1, 5, 10)
    INSERT INTO employees VALUES v_new_emps(i);

  COMMIT;
END;
/
```

---

# SK03-09 · TRIGGERS

```sql
-- ── DML Trigger ──────────────────────────────────────────
CREATE OR REPLACE TRIGGER trg_emp_audit
  BEFORE INSERT OR UPDATE OR DELETE ON employees
  FOR EACH ROW
DECLARE
  v_operation VARCHAR2(10);
BEGIN
  v_operation := CASE
    WHEN INSERTING THEN 'INSERT'
    WHEN UPDATING  THEN 'UPDATE'
    WHEN DELETING  THEN 'DELETE'
  END;

  -- :OLD = value before change, :NEW = value after change
  IF INSERTING THEN
    :NEW.created_date := SYSDATE;
    :NEW.created_by   := USER;
  END IF;

  IF UPDATING THEN
    IF :OLD.salary != :NEW.salary THEN
      -- Log salary change
      INSERT INTO salary_audit_log
        (employee_id, old_salary, new_salary, change_date, changed_by)
      VALUES
        (:NEW.employee_id, :OLD.salary, :NEW.salary, SYSDATE, USER);
    END IF;
  END IF;

  -- Prevent unauthorized DML
  IF DELETING AND USER NOT IN ('HR_ADMIN', 'SYS') THEN
    RAISE_APPLICATION_ERROR(-20001, 'Only HR_ADMIN can delete employees');
  END IF;

  -- Prevent weekend DML
  IF TO_CHAR(SYSDATE, 'DY') IN ('SAT', 'SUN') THEN
    RAISE_APPLICATION_ERROR(-20002, 'No DML allowed on weekends');
  END IF;

END trg_emp_audit;
/

-- ── INSTEAD OF Trigger (on View) ─────────────────────────
CREATE OR REPLACE TRIGGER trg_emp_dept_v_ins
  INSTEAD OF INSERT ON employee_dept_v  -- View trigger
  FOR EACH ROW
DECLARE
  v_dept_id NUMBER;
BEGIN
  -- Find or create department
  SELECT department_id INTO v_dept_id
  FROM departments WHERE department_name = :NEW.department_name;

  -- Insert into base table
  INSERT INTO employees(employee_id, first_name, last_name,
                         email, hire_date, job_id, salary, department_id)
  VALUES(employee_seq.NEXTVAL, :NEW.first_name, :NEW.last_name,
         :NEW.email, SYSDATE, :NEW.job_id, :NEW.salary, v_dept_id);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20003, 'Department not found: ' || :NEW.department_name);
END;
/

-- ── DDL Trigger ──────────────────────────────────────────
CREATE OR REPLACE TRIGGER trg_ddl_audit
  AFTER DDL ON DATABASE
BEGIN
  INSERT INTO ddl_audit_log(event_type, object_owner, object_name,
                             object_type, event_date, ddl_user)
  VALUES(ORA_SYSEVENT, ORA_DICT_OBJ_OWNER, ORA_DICT_OBJ_NAME,
         ORA_DICT_OBJ_TYPE, SYSDATE, USER);
EXCEPTION
  WHEN OTHERS THEN NULL;  -- DDL trigger không nên fail
END;
/

-- ── Compound Trigger (12c+, giải quyết mutating table) ───
CREATE OR REPLACE TRIGGER trg_salary_check
  FOR UPDATE OF salary ON employees
  COMPOUND TRIGGER
  -- Package-level variables for compound trigger
  TYPE id_list_t IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  v_emp_ids id_list_t;
  v_idx     PLS_INTEGER := 0;

  BEFORE EACH ROW IS
  BEGIN
    IF :NEW.salary > :OLD.salary * 2 THEN
      RAISE_APPLICATION_ERROR(-20010, 'Salary increase > 100% requires approval');
    END IF;
  END BEFORE EACH ROW;

  AFTER EACH ROW IS
  BEGIN
    v_idx := v_idx + 1;
    v_emp_ids(v_idx) := :NEW.employee_id;
  END AFTER EACH ROW;

  AFTER STATEMENT IS
  BEGIN
    FORALL i IN 1..v_emp_ids.COUNT
      INSERT INTO salary_change_log VALUES(v_emp_ids(i), SYSDATE, USER);
    COMMIT;
  END AFTER STATEMENT;
END trg_salary_check;
/

-- Disable/Enable triggers
ALTER TRIGGER trg_emp_audit DISABLE;
ALTER TRIGGER trg_emp_audit ENABLE;
ALTER TABLE employees DISABLE ALL TRIGGERS;
ALTER TABLE employees ENABLE ALL TRIGGERS;
```

---

# SK03-10 · DYNAMIC SQL

```sql
-- ── EXECUTE IMMEDIATE ────────────────────────────────────
DECLARE
  v_table  VARCHAR2(30) := 'EMPLOYEES';
  v_column VARCHAR2(30) := 'SALARY';
  v_sql    VARCHAR2(4000);
  v_count  NUMBER;
  v_cursor SYS_REFCURSOR;
BEGIN
  -- Simple DDL
  EXECUTE IMMEDIATE 'TRUNCATE TABLE staging_table';
  EXECUTE IMMEDIATE 'DROP TABLE temp_table PURGE';
  EXECUTE IMMEDIATE 'CREATE TABLE temp_t (id NUMBER, name VARCHAR2(100))';

  -- DML with bind variables (phòng SQL injection!)
  EXECUTE IMMEDIATE
    'UPDATE employees SET salary = :new_sal WHERE employee_id = :emp_id'
    USING 15000, 100;

  -- SELECT INTO
  EXECUTE IMMEDIATE
    'SELECT COUNT(*) FROM ' || v_table || ' WHERE ' || v_column || ' > :threshold'
    INTO v_count
    USING 10000;

  -- DDL/DML with RETURNING
  EXECUTE IMMEDIATE
    'INSERT INTO orders VALUES(seq.NEXTVAL, :amt) RETURNING order_id INTO :id'
    USING 5000 RETURNING INTO v_count;

  -- Dynamic REF CURSOR
  EXECUTE IMMEDIATE
    'SELECT * FROM ' || v_table || ' WHERE department_id = :dept'
    RETURNING INTO v_cursor
    USING 60;
  -- Actually: OPEN v_cursor FOR 'SELECT...' USING 60; is cleaner

  -- Open REF CURSOR dynamically (cleaner for queries)
  OPEN v_cursor FOR
    'SELECT employee_id, first_name FROM ' || v_table ||
    ' WHERE department_id = :1 AND salary > :2'
    USING 60, 5000;

  -- Fetch from cursor
  DECLARE
    v_id   NUMBER;
    v_name VARCHAR2(100);
  BEGIN
    LOOP
      FETCH v_cursor INTO v_id, v_name;
      EXIT WHEN v_cursor%NOTFOUND;
      DBMS_OUTPUT.PUT_LINE(v_id || ': ' || v_name);
    END LOOP;
    CLOSE v_cursor;
  END;
END;
/

-- ── DBMS_SQL (advanced dynamic SQL) ──────────────────────
-- Dùng khi không biết số/type của columns tại compile time
DECLARE
  v_cursor     INTEGER;
  v_status     INTEGER;
  v_desc_tab   DBMS_SQL.DESC_TAB;
  v_col_count  INTEGER;
  v_col_val    VARCHAR2(4000);
  v_num_val    NUMBER;
BEGIN
  v_cursor := DBMS_SQL.OPEN_CURSOR;

  DBMS_SQL.PARSE(v_cursor,
    'SELECT employee_id, first_name, salary FROM employees WHERE rownum <= 5',
    DBMS_SQL.NATIVE);

  -- Describe columns
  DBMS_SQL.DESCRIBE_COLUMNS(v_cursor, v_col_count, v_desc_tab);

  -- Define output variables
  DBMS_SQL.DEFINE_COLUMN(v_cursor, 1, v_num_val);
  DBMS_SQL.DEFINE_COLUMN(v_cursor, 2, v_col_val, 100);
  DBMS_SQL.DEFINE_COLUMN(v_cursor, 3, v_num_val);

  v_status := DBMS_SQL.EXECUTE(v_cursor);

  LOOP
    EXIT WHEN DBMS_SQL.FETCH_ROWS(v_cursor) = 0;
    DBMS_SQL.COLUMN_VALUE(v_cursor, 1, v_num_val);
    DBMS_OUTPUT.PUT_LINE('ID: ' || v_num_val);
    DBMS_SQL.COLUMN_VALUE(v_cursor, 2, v_col_val);
    DBMS_OUTPUT.PUT_LINE('Name: ' || v_col_val);
  END LOOP;

  DBMS_SQL.CLOSE_CURSOR(v_cursor);
END;
/
```

---

# SK03-11 · BUILT-IN PACKAGES

```sql
-- ── DBMS_OUTPUT ────────────────────────────────────────
SET SERVEROUTPUT ON SIZE UNLIMITED;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Simple line');
  DBMS_OUTPUT.PUT('Part 1 ');
  DBMS_OUTPUT.PUT('Part 2');
  DBMS_OUTPUT.NEW_LINE;  -- Flush current line
  DBMS_OUTPUT.ENABLE(1000000);  -- Buffer size
  DBMS_OUTPUT.DISABLE;
END;
/

-- ── UTL_FILE (file I/O) ───────────────────────────────
CREATE OR REPLACE DIRECTORY DATA_DIR AS '/u01/data';

DECLARE
  v_file   UTL_FILE.FILE_TYPE;
  v_line   VARCHAR2(32767);
  v_writer UTL_FILE.FILE_TYPE;
BEGIN
  -- Write to file
  v_writer := UTL_FILE.FOPEN('DATA_DIR', 'output.csv', 'W', 32767);
  UTL_FILE.PUT_LINE(v_writer, 'EMP_ID,NAME,SALARY');
  FOR emp IN (SELECT employee_id, first_name, salary FROM employees) LOOP
    UTL_FILE.PUT_LINE(v_writer,
      emp.employee_id || ',' || emp.first_name || ',' || emp.salary);
  END LOOP;
  UTL_FILE.FCLOSE(v_writer);

  -- Read from file
  v_file := UTL_FILE.FOPEN('DATA_DIR', 'input.txt', 'R');
  LOOP
    BEGIN
      UTL_FILE.GET_LINE(v_file, v_line);
      DBMS_OUTPUT.PUT_LINE(v_line);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN EXIT;
    END;
  END LOOP;
  UTL_FILE.FCLOSE(v_file);
END;
/

-- ── DBMS_LOCK ────────────────────────────────────────
-- Application-level locking
DECLARE
  v_lock_handle VARCHAR2(128);
  v_status      NUMBER;
BEGIN
  DBMS_LOCK.ALLOCATE_UNIQUE('MY_APP_LOCK_PROCESS_X', v_lock_handle);
  v_status := DBMS_LOCK.REQUEST(v_lock_handle,
    DBMS_LOCK.X_MODE, 10, TRUE);  -- Exclusive, 10s timeout, release on commit

  IF v_status = 0 THEN
    -- Got lock, do work
    DBMS_OUTPUT.PUT_LINE('Lock acquired');
    -- ... do exclusive work ...
    v_status := DBMS_LOCK.RELEASE(v_lock_handle);
  ELSE
    RAISE_APPLICATION_ERROR(-20050, 'Could not acquire lock: ' || v_status);
  END IF;
END;
/

-- ── DBMS_METADATA ────────────────────────────────────
-- Get DDL of any object
SELECT DBMS_METADATA.GET_DDL('TABLE', 'EMPLOYEES', 'SCOTT') FROM dual;
SELECT DBMS_METADATA.GET_DDL('INDEX', 'IDX_EMP_DEPT', 'SCOTT') FROM dual;
SELECT DBMS_METADATA.GET_DEPENDENT_DDL('TRIGGER', 'EMPLOYEES', 'SCOTT') FROM dual;

-- ── DBMS_UTILITY ─────────────────────────────────────
DECLARE
  v_time NUMBER;
BEGIN
  v_time := DBMS_UTILITY.GET_TIME;  -- Centiseconds
  -- ... code ...
  DBMS_OUTPUT.PUT_LINE('Elapsed: ' ||
    (DBMS_UTILITY.GET_TIME - v_time)/100 || ' seconds');

  -- Format call stack
  DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_CALL_STACK);
  DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/

-- ── DBMS_CRYPTO ──────────────────────────────────────
DECLARE
  v_key    RAW(32);
  v_data   RAW(32767);
  v_enc    RAW(32767);
  v_dec    RAW(32767);
BEGIN
  -- Generate random key
  v_key := DBMS_CRYPTO.RANDOMBYTES(32);  -- 256-bit key
  v_data := UTL_RAW.CAST_TO_RAW('Sensitive Data Here');

  -- Encrypt
  v_enc := DBMS_CRYPTO.ENCRYPT(
    src  => v_data,
    typ  => DBMS_CRYPTO.ENCRYPT_AES256 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5,
    key  => v_key
  );

  -- Decrypt
  v_dec := DBMS_CRYPTO.DECRYPT(src => v_enc, typ => DBMS_CRYPTO.ENCRYPT_AES256 +
    DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5, key => v_key);

  DBMS_OUTPUT.PUT_LINE(UTL_RAW.CAST_TO_VARCHAR2(v_dec));
END;
/
```

---

# SK03-12 · XML & JSON

## 1. XML in Oracle

```sql
-- ── XMLType ─────────────────────────────────────────────
DECLARE
  v_xml XMLType;
BEGIN
  v_xml := XMLType('<employee>
    <id>100</id>
    <name>Steven King</name>
    <salary>24000</salary>
  </employee>');

  -- Extract values
  DBMS_OUTPUT.PUT_LINE(
    v_xml.extract('/employee/name/text()').getStringVal()
  );
END;
/

-- XML from relational (XMLElement, XMLForest, XMLAgg)
SELECT XMLELEMENT("Employees",
         XMLAGG(
           XMLELEMENT("Employee",
             XMLFOREST(employee_id AS "Id",
                       first_name  AS "FirstName",
                       salary      AS "Salary"
             )
           ) ORDER BY employee_id
         )
       ) employees_xml
FROM employees WHERE department_id = 60;

-- XMLQUERY (XQuery)
SELECT XMLQUERY('/employee/name/text()'
         PASSING XMLType('<employee><name>Binh Tran</name></employee>')
         RETURNING CONTENT).getStringVal() emp_name
FROM dual;

-- XMLTABLE (XML to relational rows)
SELECT x.*
FROM   orders_xml o,
       XMLTABLE('/orders/order'
         PASSING o.xml_data
         COLUMNS
           order_id  NUMBER        PATH 'id',
           cust_name VARCHAR2(100) PATH 'customer/name',
           amount    NUMBER        PATH 'amount',
           items     XMLTYPE       PATH 'items'
       ) x;
```

## 2. JSON in Oracle (12c+)

```sql
-- ── JSON Storage and Constraint ──────────────────────────
CREATE TABLE orders_json (
  id   NUMBER PRIMARY KEY,
  data CLOB CONSTRAINT chk_json CHECK (data IS JSON (STRICT))
);

INSERT INTO orders_json VALUES(1,
  '{"orderId":1,"customer":{"name":"Binh","region":"VN"},
    "items":[{"product":"Oracle Course","qty":1,"price":5000}],
    "total":5000,"status":"ACTIVE"}');

-- ── JSON_VALUE (extract scalar) ──────────────────────────
SELECT id,
  JSON_VALUE(data, '$.customer.name')       cust_name,
  JSON_VALUE(data, '$.total' RETURNING NUMBER) total_amount,
  JSON_VALUE(data, '$.status')              status,
  JSON_VALUE(data, '$.customer.region'
    DEFAULT 'Unknown' ON ERROR)             region
FROM orders_json;

-- ── JSON_QUERY (extract object/array) ────────────────────
SELECT JSON_QUERY(data, '$.items') items_array,
       JSON_QUERY(data, '$.customer' WITH WRAPPER) customer_obj
FROM orders_json;

-- ── JSON_TABLE (JSON to relational) ──────────────────────
SELECT jt.*
FROM orders_json o,
     JSON_TABLE(o.data, '$'
       COLUMNS (
         order_id  NUMBER       PATH '$.orderId',
         cust_name VARCHAR2(100) PATH '$.customer.name',
         region    VARCHAR2(50)  PATH '$.customer.region',
         total     NUMBER        PATH '$.total',
         status    VARCHAR2(20)  PATH '$.status',
         -- Nested array
         NESTED PATH '$.items[*]'
         COLUMNS (
           product  VARCHAR2(100) PATH '$.product',
           quantity NUMBER         PATH '$.qty',
           price    NUMBER         PATH '$.price'
         )
       )
     ) jt;

-- ── JSON_OBJECT, JSON_ARRAY (generate JSON) ──────────────
SELECT JSON_OBJECT(
  'empId'   VALUE e.employee_id,
  'name'    VALUE e.first_name || ' ' || e.last_name,
  'salary'  VALUE e.salary,
  'dept'    VALUE d.department_name,
  'phones'  VALUE JSON_ARRAY('0912345678', '0987654321'),
  ABSENT ON NULL  -- Skip NULL values
) employee_json
FROM employees e
JOIN departments d ON e.department_id = d.department_id
WHERE e.employee_id = 100;

-- ── JSON Aggregation ─────────────────────────────────────
SELECT department_id,
  JSON_ARRAYAGG(
    JSON_OBJECT(
      'id'     VALUE employee_id,
      'name'   VALUE first_name,
      'salary' VALUE salary
    )
    ORDER BY salary DESC
  ) dept_employees
FROM employees
GROUP BY department_id;

-- ── JSON_MERGEPATCH (update JSON, 19c+) ──────────────────
UPDATE orders_json
SET data = JSON_MERGEPATCH(data, '{"status":"COMPLETED","completedAt":"2026-01-15"}')
WHERE id = 1;

-- ── IS JSON condition ────────────────────────────────────
SELECT id FROM orders_json WHERE data IS JSON;
SELECT id FROM orders_json WHERE data IS NOT JSON;

-- JSON Path expressions
SELECT JSON_VALUE(data, '$.items[0].price') first_item_price,  -- First array element
       JSON_VALUE(data, '$.items[*].price') all_prices         -- All prices
FROM orders_json;
```

---

# SK03-13 · AI VECTOR SEARCH (Oracle 23ai/26ai)

```sql
-- ── VECTOR Data Type ──────────────────────────────────────
-- Lưu trữ vector embeddings từ AI models (OpenAI, HuggingFace, etc.)

CREATE TABLE knowledge_base (
  id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  doc_id      VARCHAR2(100),
  chunk_seq   NUMBER,
  chunk_text  CLOB,
  source_url  VARCHAR2(500),
  embedding   VECTOR(1536, FLOAT32),  -- OpenAI ada-002: 1536 dims
  created_at  TIMESTAMP DEFAULT SYSTIMESTAMP
);

-- Load ONNX model vào DB (Oracle built-in inference)
CREATE OR REPLACE DIRECTORY ONNX_DIR AS '/u01/onnx_models';
EXECUTE DBMS_VECTOR.LOAD_ONNX_MODEL(
  directory  => 'ONNX_DIR',
  file_name  => 'all-minilm-l6-v2.onnx',
  model_name => 'MINILM_MODEL',
  metadata   => JSON(
    '{"function":"embedding",
      "embeddingOutput":"embedding",
      "input":{"input":["DATA"]}}'
  )
);

-- ── Generate Embeddings ──────────────────────────────────
-- Insert với embedding từ Oracle-hosted model
INSERT INTO knowledge_base (doc_id, chunk_seq, chunk_text, embedding)
SELECT 'DOC001', ROWNUM, chunk_text,
       VECTOR_EMBEDDING(MINILM_MODEL USING chunk_text AS DATA)
FROM doc_chunks
WHERE doc_id = 'DOC001';

-- Insert với embedding từ external API (Python/REST, stored as raw vector)
-- App sends pre-computed embedding as string
INSERT INTO knowledge_base (doc_id, chunk_seq, chunk_text, embedding)
VALUES ('DOC002', 1, 'Oracle DBA best practices',
  TO_VECTOR('[0.123, -0.456, 0.789, ...]'));  -- Array của floats

-- ── Vector Distance Functions ─────────────────────────────
-- VECTOR_DISTANCE(vec1, vec2, metric)
-- Metrics: COSINE, EUCLIDEAN, DOT, MANHATTAN, HAMMING

-- Find similar documents (semantic search)
DECLARE
  v_query_text  VARCHAR2(4000) := 'How to backup Oracle database?';
  v_query_vec   VECTOR;
BEGIN
  -- Generate embedding for query
  SELECT VECTOR_EMBEDDING(MINILM_MODEL USING v_query_text AS DATA)
  INTO v_query_vec FROM dual;

  -- Find top-5 most similar chunks
  FOR result IN (
    SELECT doc_id, chunk_text,
           VECTOR_DISTANCE(embedding, v_query_vec, COSINE) distance,
           1 - VECTOR_DISTANCE(embedding, v_query_vec, COSINE) similarity
    FROM knowledge_base
    ORDER BY distance ASC
    FETCH APPROX FIRST 5 ROWS ONLY
      WITH TARGET ACCURACY 90    -- 90% recall, faster than exact search
  ) LOOP
    DBMS_OUTPUT.PUT_LINE(
      ROUND(result.similarity * 100, 1) || '% - ' ||
      SUBSTR(result.chunk_text, 1, 100)
    );
  END LOOP;
END;
/

-- ── Vector Indexes ───────────────────────────────────────
-- HNSW: Hierarchical Navigable Small World (fast, in-memory)
CREATE VECTOR INDEX kb_hnsw_idx ON knowledge_base(embedding)
  ORGANIZATION INMEMORY NEIGHBOR GRAPH
  DISTANCE COSINE
  WITH TARGET ACCURACY 95
  PARAMETERS (TYPE HNSW, NEIGHBORS 32, EFCONSTRUCTION 200);

-- IVF: Inverted File Flat (tiết kiệm memory hơn)
CREATE VECTOR INDEX kb_ivf_idx ON knowledge_base(embedding)
  ORGANIZATION NEIGHBOR PARTITIONS
  DISTANCE COSINE
  WITH TARGET ACCURACY 90
  PARAMETERS (TYPE IVF, NEIGHBOR PARTITIONS 128);

-- ── Similarity Search trong SQL ──────────────────────────
-- Top-K nearest neighbors
SELECT doc_id, chunk_seq, chunk_text,
       VECTOR_DISTANCE(embedding,
         VECTOR_EMBEDDING(MINILM_MODEL USING 'backup strategies' AS DATA),
         COSINE) AS distance
FROM knowledge_base
ORDER BY distance
FETCH APPROX FIRST 10 ROWS ONLY WITH TARGET ACCURACY 90;

-- Similarity search với filter (Hybrid Search)
SELECT doc_id, chunk_text, distance
FROM (
  SELECT doc_id, chunk_text,
         VECTOR_DISTANCE(embedding, :query_vector, COSINE) AS distance
  FROM knowledge_base
  WHERE source_url LIKE '%oracle.com%'  -- Metadata filter
    AND created_at > SYSDATE - 30       -- Recency filter
  ORDER BY distance
  FETCH APPROX FIRST 20 ROWS ONLY
)
WHERE distance < 0.3;  -- Similarity threshold

-- ── RAG Pattern (Retrieval-Augmented Generation) ──────────
-- Step 1: Retrieve relevant context
CREATE OR REPLACE FUNCTION get_rag_context(
  p_query   IN VARCHAR2,
  p_top_k   IN NUMBER DEFAULT 5
) RETURN CLOB AS
  v_query_vec VECTOR;
  v_context   CLOB := '';
BEGIN
  -- Generate query embedding
  SELECT VECTOR_EMBEDDING(MINILM_MODEL USING p_query AS DATA)
  INTO v_query_vec FROM dual;

  -- Retrieve top-K similar chunks
  FOR ctx IN (
    SELECT chunk_text,
           ROUND((1 - VECTOR_DISTANCE(embedding, v_query_vec, COSINE))*100,1) similarity
    FROM knowledge_base
    ORDER BY VECTOR_DISTANCE(embedding, v_query_vec, COSINE)
    FETCH APPROX FIRST p_top_k ROWS ONLY WITH TARGET ACCURACY 90
  ) LOOP
    v_context := v_context || '[' || ctx.similarity || '%] ' ||
                 ctx.chunk_text || CHR(10) || '---' || CHR(10);
  END LOOP;

  RETURN v_context;
END;
/

-- Step 2: Use context with LLM (via UTL_HTTP to external API or DBMS_VECTOR_CHAIN)
-- Oracle 23ai có DBMS_VECTOR_CHAIN để chain embedding + LLM calls

-- ── VECTOR_CHUNKS (split text) ────────────────────────────
SELECT * FROM VECTOR_CHUNKS(
  'Long document text here...'
  BY words
  MAX 100
  OVERLAP 20
  SPLIT BY [newline, space]
);

-- ── Inspect vectors ──────────────────────────────────────
SELECT id, doc_id,
  VECTOR_DIMS(embedding)  num_dimensions,  -- 1536
  VECTOR_NORM(embedding)  vector_norm,
  FROM_VECTOR(embedding)  vec_as_string    -- Convert to readable string
FROM knowledge_base
FETCH FIRST 5 ROWS ONLY;

-- Vector operations
SELECT
  VECTOR_DISTANCE(
    TO_VECTOR('[1,0,0]'),
    TO_VECTOR('[0,1,0]'),
    COSINE
  ) cosine_dist,         -- 1.0 = orthogonal
  VECTOR_DISTANCE(
    TO_VECTOR('[1,0,0]'),
    TO_VECTOR('[1,0,0]'),
    COSINE
  ) identical_dist       -- 0.0 = identical
FROM dual;
```

---

**Tài liệu tham khảo:**
- Oracle Database PL/SQL Language Reference 19c
- Oracle Database PL/SQL Packages and Types Reference 19c
- Oracle AI Vector Search User's Guide 23ai
- Oracle Database JSON Developer's Guide 19c
- docs.oracle.com/en/database/oracle/oracle-database/23/vecse/
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
