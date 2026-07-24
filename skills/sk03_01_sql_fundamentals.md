---
name: oracle-sql-fundamentals
description: >
  SQL Fundamentals Oracle: DML, DDL, DCL, TCL và SQL cơ bản đến trung cấp.
  Kích hoạt khi hỏi về: SQL Oracle cơ bản, SELECT Oracle, WHERE clause,
  GROUP BY HAVING Oracle, ORDER BY Oracle, JOIN Oracle,
  INNER JOIN OUTER JOIN CROSS JOIN, LEFT JOIN RIGHT JOIN FULL OUTER JOIN,
  self join Oracle, subquery Oracle, correlated subquery, EXISTS NOT EXISTS,
  IN NOT IN Oracle, UNION UNION ALL INTERSECT MINUS Oracle,
  INSERT UPDATE DELETE MERGE Oracle, DML Oracle, DDL Oracle,
  CREATE TABLE ALTER TABLE DROP TABLE TRUNCATE Oracle,
  primary key foreign key constraint Oracle, sequence Oracle,
  view Oracle, synonym Oracle, DCL GRANT REVOKE Oracle,
  TCL COMMIT ROLLBACK SAVEPOINT Oracle, NVL DECODE CASE Oracle,
  date functions Oracle, string functions Oracle, aggregate functions Oracle.
---

# SK03-01 · SQL Fundamentals: DML, DDL, DCL & Cơ bản

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. SELECT CƠ BẢN

```sql
-- ── Basic SELECT ─────────────────────────────────────────
SELECT employee_id, first_name, last_name, salary,
       department_id
FROM employees
WHERE salary > 5000
  AND department_id IN (10, 20, 30)
  AND hire_date >= DATE '2020-01-01'
ORDER BY salary DESC, last_name ASC;

-- ── DISTINCT ─────────────────────────────────────────────
SELECT DISTINCT department_id FROM employees;
SELECT DISTINCT department_id, job_id FROM employees;

-- ── Alias ─────────────────────────────────────────────────
SELECT e.employee_id                          emp_id,
       e.first_name || ' ' || e.last_name     full_name,
       ROUND(e.salary * 12, 2)               annual_salary,
       CASE WHEN e.salary > 10000 THEN 'High'
            WHEN e.salary >  5000 THEN 'Medium'
            ELSE 'Low' END                    salary_grade
FROM employees e;

-- ── ROWNUM và FETCH (pagination) ─────────────────────────
-- Oracle 12c+ (khuyến dùng)
SELECT employee_id, first_name, salary
FROM employees
ORDER BY salary DESC
FETCH FIRST 10 ROWS ONLY;               -- Top 10

FETCH FIRST 20 PERCENT ROWS ONLY;       -- Top 20%
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY; -- Trang 2 (row 11-20)

-- Oracle 11g và cũ hơn
SELECT * FROM (
  SELECT employee_id, first_name, salary,
         ROWNUM rn
  FROM (SELECT employee_id, first_name, salary
        FROM employees ORDER BY salary DESC)
  WHERE ROWNUM <= 20
)
WHERE rn >= 11;
```

---

## 2. WHERE CLAUSE & OPERATORS

```sql
-- ── Comparison ───────────────────────────────────────────
WHERE salary  = 5000
WHERE salary != 5000     -- Hoặc: salary <> 5000
WHERE salary  > 5000
WHERE salary >= 5000
WHERE salary BETWEEN 3000 AND 8000

-- ── LIKE / Pattern matching ───────────────────────────────
WHERE last_name LIKE 'N%'       -- Bắt đầu bằng N
WHERE last_name LIKE '%en%'     -- Chứa 'en'
WHERE last_name LIKE '_ith'     -- 4 ký tự, kết thúc bằng 'ith'
WHERE email     NOT LIKE '%@gmail%'

-- ── IN / NOT IN ───────────────────────────────────────────
WHERE department_id IN (10, 20, 30, 40)
WHERE job_id NOT IN ('IT_PROG', 'FI_ACCOUNT')
-- Cẩn thận: NOT IN với NULL → returns nothing!
WHERE department_id NOT IN (10, 20, NULL)  -- Luôn trả về 0 rows!

-- ── IS NULL / IS NOT NULL ─────────────────────────────────
WHERE commission_pct IS NULL
WHERE manager_id IS NOT NULL

-- ── Logic operators ───────────────────────────────────────
WHERE (salary > 8000 OR commission_pct IS NOT NULL)
  AND department_id = 80
  AND hire_date BETWEEN DATE '2020-01-01' AND SYSDATE

-- ── EXISTS / NOT EXISTS ───────────────────────────────────
-- Kiểm tra department có employee không
SELECT department_id, department_name
FROM departments d
WHERE EXISTS (
  SELECT 1 FROM employees e
  WHERE e.department_id = d.department_id
);
-- NOT EXISTS: departments KHÔNG có employee
WHERE NOT EXISTS (
  SELECT 1 FROM employees e
  WHERE e.department_id = d.department_id
);

-- ── ANY / ALL ────────────────────────────────────────────
-- salary > ít nhất 1 manager's salary
WHERE salary > ANY (SELECT salary FROM employees WHERE job_id LIKE '%MAN%')
-- salary > tất cả manager's salaries
WHERE salary > ALL (SELECT salary FROM employees WHERE job_id LIKE '%MAN%')
```

---

## 3. GROUP BY & AGGREGATE FUNCTIONS

```sql
-- ── Basic aggregate functions ─────────────────────────────
SELECT COUNT(*)                          total_rows,
       COUNT(commission_pct)             non_null_commissions,
       SUM(salary)                       total_salary,
       AVG(salary)                       avg_salary,
       MIN(salary)                       min_salary,
       MAX(salary)                       max_salary,
       MEDIAN(salary)                    median_salary,
       STATS_MODE(department_id)         most_common_dept,
       STDDEV(salary)                    salary_stddev,
       VARIANCE(salary)                  salary_variance,
       LISTAGG(last_name, ', ')
         WITHIN GROUP (ORDER BY last_name) all_names  -- 12c+
FROM employees;

-- ── GROUP BY ─────────────────────────────────────────────
SELECT department_id,
       COUNT(*)           headcount,
       ROUND(AVG(salary), 2) avg_sal,
       SUM(salary)           total_sal,
       MIN(salary)           min_sal,
       MAX(salary)           max_sal
FROM employees
WHERE hire_date > DATE '2018-01-01'
GROUP BY department_id
HAVING AVG(salary) > 5000   -- Filter AFTER grouping
   AND COUNT(*) >= 3
ORDER BY avg_sal DESC;

-- ── ROLLUP (subtotals) ────────────────────────────────────
SELECT department_id, job_id, SUM(salary)
FROM employees
GROUP BY ROLLUP(department_id, job_id)
ORDER BY department_id NULLS LAST, job_id NULLS LAST;
-- Tạo: subtotals per dept, grand total (NULLS = subtotal row)

-- ── CUBE (all combinations) ───────────────────────────────
SELECT department_id, job_id, SUM(salary)
FROM employees
GROUP BY CUBE(department_id, job_id);
-- Tạo: subtotals per dept, per job, cross combinations, grand total

-- ── GROUPING SETS (custom groups) ────────────────────────
SELECT department_id, job_id, SUM(salary)
FROM employees
GROUP BY GROUPING SETS(
  (department_id, job_id),   -- Group 1
  (department_id),            -- Group 2
  ()                          -- Grand total
);

-- GROUPING() function: xác định row là subtotal hay không
SELECT GROUPING(department_id) is_dept_subtotal,
       GROUPING(job_id)         is_job_subtotal,
       department_id, job_id,
       SUM(salary)
FROM employees
GROUP BY ROLLUP(department_id, job_id);
-- 1 = subtotal row, 0 = regular data row
```

---

## 4. JOINS

```sql
-- ── INNER JOIN ───────────────────────────────────────────
SELECT e.employee_id, e.first_name, e.last_name,
       d.department_name, l.city
FROM employees e
JOIN departments d ON e.department_id = d.department_id
JOIN locations   l ON d.location_id   = l.location_id
WHERE e.salary > 5000;

-- ── LEFT / RIGHT / FULL OUTER JOIN ───────────────────────
-- Left: tất cả employees, kể cả không có department
SELECT e.first_name, d.department_name
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id;

-- Full: tất cả employees VÀ tất cả departments
SELECT e.first_name, d.department_name
FROM employees e
FULL OUTER JOIN departments d ON e.department_id = d.department_id;

-- ── SELF JOIN ────────────────────────────────────────────
SELECT e.employee_id, e.first_name employee_name,
       m.first_name manager_name,
       m.salary     manager_salary
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.employee_id
ORDER BY m.employee_id;

-- ── CROSS JOIN ───────────────────────────────────────────
-- Tất cả combinations (dùng cẩn thận)
SELECT c.region, p.category_name
FROM regions c CROSS JOIN product_categories p
ORDER BY c.region, p.category_name;

-- ── NATURAL JOIN (không khuyến dùng) ─────────────────────
-- Tự động join trên tất cả columns cùng tên
SELECT employee_id, department_name
FROM employees NATURAL JOIN departments;

-- ── Oracle (+) syntax (legacy, 11g trở về) ───────────────
-- Tương đương LEFT JOIN:
SELECT e.first_name, d.department_name
FROM employees e, departments d
WHERE e.department_id = d.department_id(+);

-- ── Multi-table subquery join ─────────────────────────────
SELECT e.first_name, e.salary,
       dept_avg.avg_sal dept_average,
       ROUND(e.salary - dept_avg.avg_sal, 2) vs_average
FROM employees e
JOIN (
  SELECT department_id, AVG(salary) avg_sal
  FROM employees
  GROUP BY department_id
) dept_avg ON e.department_id = dept_avg.department_id
ORDER BY vs_average DESC;
```

---

## 5. SUBQUERIES

```sql
-- ── Single-row subquery ───────────────────────────────────
-- Tìm employee có salary cao nhất
SELECT first_name, last_name, salary
FROM employees
WHERE salary = (SELECT MAX(salary) FROM employees);

-- ── Multi-row subquery ────────────────────────────────────
-- Employee thuộc departments ở Seattle
SELECT first_name, last_name, department_id
FROM employees
WHERE department_id IN (
  SELECT department_id
  FROM departments d
  JOIN locations l ON d.location_id = l.location_id
  WHERE l.city = 'Seattle'
);

-- ── Correlated subquery ───────────────────────────────────
-- Employee có salary > average của department họ
SELECT e.first_name, e.last_name, e.salary, e.department_id
FROM employees e
WHERE e.salary > (
  SELECT AVG(e2.salary)
  FROM employees e2
  WHERE e2.department_id = e.department_id  -- Correlated!
);

-- ── Scalar subquery (single value) ───────────────────────
SELECT e.first_name, e.salary,
       (SELECT AVG(e2.salary)
        FROM employees e2
        WHERE e2.department_id = e.department_id) dept_avg_sal
FROM employees e
ORDER BY e.department_id;

-- ── Inline view (subquery in FROM) ───────────────────────
SELECT dept, avg_sal, headcount
FROM (
  SELECT department_id dept,
         AVG(salary)   avg_sal,
         COUNT(*)      headcount
  FROM employees
  GROUP BY department_id
)
WHERE avg_sal > 6000
ORDER BY avg_sal DESC;
```

---

## 6. SET OPERATORS

```sql
-- ── UNION (loại trùng lặp) ────────────────────────────────
SELECT employee_id, first_name FROM employees
UNION
SELECT manager_id, 'MANAGER' FROM employees
WHERE manager_id IS NOT NULL;

-- ── UNION ALL (giữ trùng lặp, nhanh hơn UNION) ───────────
SELECT 'EMPLOYEE' type, employee_id id, first_name name FROM employees
UNION ALL
SELECT 'CONTACT' type, contact_id, first_name FROM contacts
ORDER BY type, id;

-- ── INTERSECT (rows có trong cả hai) ─────────────────────
-- Departments có cả employee lẫn project
SELECT department_id FROM employees
INTERSECT
SELECT department_id FROM project_assignments;

-- ── MINUS (rows trong query 1 nhưng không có trong query 2) ─
-- Employees không có trong any project
SELECT employee_id FROM employees
MINUS
SELECT employee_id FROM project_assignments;

-- ── Rules cho set operators ─────────────────────────────
-- 1. Số columns phải bằng nhau
-- 2. Data types phải compatible
-- 3. ORDER BY chỉ được ở cuối cùng, sau set operator
-- 4. Column aliases từ query đầu tiên được dùng
```

---

## 7. DML — DATA MANIPULATION LANGUAGE

```sql
-- ── INSERT ───────────────────────────────────────────────
-- Single row
INSERT INTO employees (employee_id, first_name, last_name,
                       email, hire_date, job_id, salary, department_id)
VALUES (999, 'Binh', 'Tran', 'btran@vietdba.vn',
        DATE '2026-01-15', 'IT_DBA', 15000, 60);

-- Insert from SELECT
INSERT INTO emp_archive
SELECT * FROM employees WHERE hire_date < DATE '2020-01-01';

-- Multi-table INSERT (Oracle specific)
INSERT ALL
  WHEN salary > 10000 THEN INTO high_salary_emp VALUES(employee_id, salary)
  WHEN salary BETWEEN 5000 AND 10000 THEN INTO mid_salary_emp VALUES(employee_id, salary)
  ELSE INTO low_salary_emp VALUES(employee_id, salary)
SELECT employee_id, salary FROM employees;

-- ── UPDATE ────────────────────────────────────────────────
-- Single column
UPDATE employees SET salary = salary * 1.10
WHERE department_id = 60;

-- Multiple columns với subquery
UPDATE employees e
SET (salary, commission_pct) = (
  SELECT s.new_salary, s.new_commission
  FROM salary_adjustments s
  WHERE s.employee_id = e.employee_id
)
WHERE EXISTS (
  SELECT 1 FROM salary_adjustments s
  WHERE s.employee_id = e.employee_id
);

-- UPDATE với RETURNING (lấy giá trị sau update)
DECLARE
  v_new_salary NUMBER;
BEGIN
  UPDATE employees SET salary = salary * 1.1
  WHERE employee_id = 100
  RETURNING salary INTO v_new_salary;
  DBMS_OUTPUT.PUT_LINE('New salary: ' || v_new_salary);
  COMMIT;
END;
/

-- ── DELETE ───────────────────────────────────────────────
DELETE FROM employees WHERE hire_date < DATE '2000-01-01';

-- Delete với subquery
DELETE FROM order_items oi
WHERE NOT EXISTS (
  SELECT 1 FROM orders o
  WHERE o.order_id = oi.order_id
);

-- ── MERGE (Upsert) ────────────────────────────────────────
MERGE INTO employees_target t
USING (SELECT employee_id, first_name, last_name, salary
       FROM employees_source) s
ON (t.employee_id = s.employee_id)
WHEN MATCHED THEN
  UPDATE SET t.salary     = s.salary,
             t.first_name = s.first_name
  WHERE t.salary != s.salary        -- Chỉ update nếu có thay đổi
WHEN NOT MATCHED THEN
  INSERT (employee_id, first_name, last_name, salary)
  VALUES (s.employee_id, s.first_name, s.last_name, s.salary)
WHEN NOT MATCHED BY SOURCE THEN      -- Oracle 19c+
  DELETE;                            -- Delete rows trong target không có trong source
```

---

## 8. DDL — DATA DEFINITION LANGUAGE

```sql
-- ── CREATE TABLE ─────────────────────────────────────────
CREATE TABLE orders (
  order_id     NUMBER         GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id  NUMBER         NOT NULL,
  order_date   DATE           DEFAULT SYSDATE NOT NULL,
  status       VARCHAR2(20)   DEFAULT 'PENDING' NOT NULL
                              CONSTRAINT chk_order_status
                              CHECK (status IN ('PENDING','ACTIVE','COMPLETED','CANCELLED')),
  amount       NUMBER(12,2)   CHECK (amount > 0),
  discount_pct NUMBER(5,2)    DEFAULT 0,
  notes        CLOB,
  created_at   TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
  -- Constraints
  CONSTRAINT fk_orders_cust FOREIGN KEY (customer_id)
    REFERENCES customers(customer_id)
    ON DELETE CASCADE,
  CONSTRAINT uq_order_ref UNIQUE (customer_id, order_date)
) TABLESPACE APP_DATA
  STORAGE (INITIAL 64M NEXT 64M PCTINCREASE 0)
  PCTFREE 10;

-- ── ALTER TABLE ───────────────────────────────────────────
-- Add column
ALTER TABLE orders ADD (
  discount_amount NUMBER(12,2),
  approved_by     VARCHAR2(50)
);

-- Modify column
ALTER TABLE orders MODIFY status VARCHAR2(30);
ALTER TABLE orders MODIFY amount NUMBER(15,2) DEFAULT 0;

-- Rename column (12c+)
ALTER TABLE orders RENAME COLUMN notes TO order_notes;

-- Drop column
ALTER TABLE orders DROP COLUMN approved_by;
ALTER TABLE orders SET UNUSED COLUMN discount_amount;  -- Mark unused first
ALTER TABLE orders DROP UNUSED COLUMNS;               -- Then drop

-- Add constraint
ALTER TABLE orders ADD CONSTRAINT chk_discount
  CHECK (discount_pct BETWEEN 0 AND 100) ENABLE NOVALIDATE;

-- Disable/Enable constraint
ALTER TABLE orders DISABLE CONSTRAINT chk_order_status;
ALTER TABLE orders ENABLE  CONSTRAINT chk_order_status;

-- ── SEQUENCES ─────────────────────────────────────────────
CREATE SEQUENCE order_seq
  START WITH 1000
  INCREMENT BY 1
  NOCYCLE
  CACHE 100    -- 100 values in cache (important for RAC performance)
  ORDER;       -- Guarantee sequence ordering (RAC)

SELECT order_seq.NEXTVAL FROM dual;  -- Lấy giá trị tiếp theo
SELECT order_seq.CURRVAL FROM dual;  -- Giá trị hiện tại (trong session)

ALTER SEQUENCE order_seq INCREMENT BY 10;
ALTER SEQUENCE order_seq CACHE 500;

-- ── VIEWS ────────────────────────────────────────────────
CREATE OR REPLACE VIEW employee_dept_v AS
SELECT e.employee_id, e.first_name, e.last_name,
       e.salary, e.email,
       d.department_name, l.city
FROM employees e
JOIN departments d ON e.department_id = d.department_id
JOIN locations   l ON d.location_id   = l.location_id;

-- Updatable view (chỉ update base table)
UPDATE employee_dept_v
SET salary = salary * 1.05
WHERE city = 'Seattle';

-- Materialized View (precomputed)
CREATE MATERIALIZED VIEW mv_dept_salary
REFRESH COMPLETE ON DEMAND
AS
SELECT department_id, AVG(salary) avg_sal, COUNT(*) headcount
FROM employees GROUP BY department_id;

-- Force refresh
EXEC DBMS_MVIEW.REFRESH('MV_DEPT_SALARY', 'C');
```

---

## 9. TCL — TRANSACTION CONTROL

```sql
-- ── COMMIT / ROLLBACK / SAVEPOINT ─────────────────────────
BEGIN
  -- DML 1
  UPDATE accounts SET balance = balance - 1000 WHERE account_id = 101;

  SAVEPOINT after_debit;  -- Đánh dấu savepoint

  -- DML 2
  UPDATE accounts SET balance = balance + 1000 WHERE account_id = 202;

  -- Nếu có lỗi tại DML 2, rollback về savepoint:
  -- ROLLBACK TO SAVEPOINT after_debit;
  -- Còn DML 1 vẫn còn trong transaction

  COMMIT;  -- Hoàn thành transaction
END;

-- ── AUTONOMOUS TRANSACTION ────────────────────────────────
-- Sub-transaction độc lập, commit/rollback riêng
CREATE OR REPLACE PROCEDURE log_audit(p_msg VARCHAR2) AS
  PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
  INSERT INTO audit_log(log_date, message)
  VALUES (SYSDATE, p_msg);
  COMMIT;  -- Commit chỉ autonomous transaction
END;
-- Audit log được ghi ngay cả khi calling transaction rollback
```

---

## 10. FUNCTIONS

### 10.1 String Functions

```sql
SELECT
  UPPER('hello')                     upper_val,     -- HELLO
  LOWER('WORLD')                     lower_val,     -- world
  INITCAP('oracle dba')              initcap_val,   -- Oracle Dba
  LENGTH('Hello')                    len_val,       -- 5
  SUBSTR('Hello World', 1, 5)        substr_val,    -- Hello
  SUBSTR('Hello World', -5)          substr_end,    -- World (from end)
  INSTR('Hello World', 'o')          instr_val,     -- 5 (first occurrence)
  INSTR('Hello World', 'o', 6)       instr_2nd,     -- 8 (from pos 6)
  REPLACE('Hello', 'l', 'L')        replace_val,   -- HeLLo
  TRANSLATE('hello', 'helo', 'HELO') trans_val,     -- HELLO
  LPAD('5', 3, '0')                  lpad_val,      -- 005
  RPAD('abc', 5, '-')                rpad_val,      -- abc--
  LTRIM('  hello  ')                 ltrim_val,     -- 'hello  '
  RTRIM('  hello  ')                 rtrim_val,     -- '  hello'
  TRIM('  hello  ')                  trim_val,      -- 'hello'
  TRIM(LEADING  '0' FROM '00123')    ltrim_char,    -- 123
  TRIM(TRAILING '0' FROM '12300')    rtrim_char,    -- 123
  CONCAT('Hello', ' World')          concat_val,    -- Hello World
  'Hello' || ' ' || 'World'         concat_op,     -- Hello World
  REVERSE('Hello')                   reverse_val,   -- olleH
  REGEXP_REPLACE('ph#one:123', '[^0-9]', '') digits_only, -- 123
  REGEXP_SUBSTR('user@email.com', '[^@]+$') domain  -- email.com
FROM dual;
```

### 10.2 Date Functions

```sql
SELECT
  SYSDATE                            now_date,
  SYSTIMESTAMP                       now_timestamp,
  CURRENT_DATE                       session_date,      -- Session timezone
  CURRENT_TIMESTAMP                  session_ts,
  TRUNC(SYSDATE)                     today_midnight,
  TRUNC(SYSDATE, 'MM')               first_of_month,
  TRUNC(SYSDATE, 'YYYY')             first_of_year,
  LAST_DAY(SYSDATE)                  last_day_month,
  ADD_MONTHS(SYSDATE, 3)             plus_3_months,
  ADD_MONTHS(SYSDATE, -6)            minus_6_months,
  MONTHS_BETWEEN(DATE '2026-12-31', DATE '2026-01-01') months_diff,
  NEXT_DAY(SYSDATE, 'MONDAY')        next_monday,
  ROUND(SYSDATE, 'MM')               round_month,
  TO_DATE('2026-01-15', 'YYYY-MM-DD') converted_date,
  TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') formatted_date,
  TO_CHAR(SYSDATE, 'Day, DD Month YYYY')    formatted_long,
  EXTRACT(YEAR  FROM SYSDATE)        year_part,
  EXTRACT(MONTH FROM SYSDATE)        month_part,
  EXTRACT(DAY   FROM SYSDATE)        day_part,
  EXTRACT(HOUR  FROM SYSTIMESTAMP)   hour_part,
  SYSDATE - DATE '2020-01-01'        days_since,       -- Số ngày
  INTERVAL '30' DAY                  thirty_days,
  SYSDATE + NUMTODSINTERVAL(6, 'HOUR')   plus_6hrs
FROM dual;
```

### 10.3 Conversion & NULL Functions

```sql
SELECT
  NVL(commission_pct, 0)                  nvl_val,        -- Replace NULL
  NVL2(commission_pct, 'Has Comm', 'No Comm') nvl2_val,   -- If/else NULL
  NULLIF(10, 10)                          nullif_val,     -- NULL if equal
  NULLIF(10, 20)                          nullif_diff,    -- 10 (not equal)
  COALESCE(NULL, NULL, 3, 4)              coalesce_val,   -- 3 (first non-null)
  DECODE(department_id,
         10, 'Administration',
         20, 'Marketing',
         'Other')                         decode_val,
  CASE department_id
    WHEN 10 THEN 'Administration'
    WHEN 20 THEN 'Marketing'
    ELSE 'Other'
  END                                     case_simple,
  CASE
    WHEN salary > 10000 THEN 'High'
    WHEN salary >  5000 THEN 'Medium'
    ELSE 'Low'
  END                                     case_searched,
  TO_NUMBER('1,234.56', '9,999.99')       to_num,
  TO_CHAR(12345.67, '$999,999.99')        formatted_num,
  CAST('2026-01-15' AS DATE)              cast_date,
  CAST(123.45 AS VARCHAR2(10))            cast_str,
  CONVERT('Tiếng Việt', 'AL32UTF8', 'US7ASCII') convert_charset
FROM employees;
```

---

**Tài liệu tham khảo:**
- Oracle Database SQL Language Reference 19c
- Oracle Database SQL Reference (docs.oracle.com)
- www.tranvanbinh.vn
