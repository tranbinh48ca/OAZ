---
name: oracle-sql-plsql
description: >
  SQL và PL/SQL Oracle từ cơ bản đến nâng cao.
  Kích hoạt khi hỏi về: SQL Oracle, PL/SQL, stored procedure, function,
  package, trigger, cursor, exception handling, dynamic SQL, EXECUTE IMMEDIATE,
  bulk collect, FORALL, analytic functions, window functions, ROW_NUMBER RANK,
  PIVOT UNPIVOT, CONNECT BY hierarchical query, CTE WITH clause, MERGE,
  DBMS packages, UTL_FILE, JSON SQL, XML SQL, vector search 23ai 26ai,
  viết procedure, viết function, debug PL/SQL, SQL tuning rewrite.
---

# SK03 · SQL & PL/SQL Oracle

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. SQL NÂNG CAO

### 1.1 Analytic / Window Functions

```sql
-- ROW_NUMBER, RANK, DENSE_RANK
SELECT employee_id, department_id, salary,
  ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY salary DESC) rn,
  RANK()        OVER (PARTITION BY department_id ORDER BY salary DESC) rnk,
  DENSE_RANK()  OVER (PARTITION BY department_id ORDER BY salary DESC) dense_rnk
FROM employees;

-- LAG / LEAD (so sánh với row trước/sau)
SELECT order_date, amount,
  LAG(amount,1,0)  OVER (ORDER BY order_date) prev_amount,
  LEAD(amount,1,0) OVER (ORDER BY order_date) next_amount,
  amount - LAG(amount,1,0) OVER (ORDER BY order_date) diff
FROM daily_sales;

-- SUM / AVG với OVER (running total)
SELECT order_date, amount,
  SUM(amount) OVER (ORDER BY order_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) running_total,
  AVG(amount) OVER (ORDER BY order_date
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) moving_avg_7days
FROM daily_sales;

-- NTILE (phân nhóm)
SELECT customer_id, total_spent,
  NTILE(4) OVER (ORDER BY total_spent DESC) quartile
FROM customer_summary;

-- FIRST_VALUE / LAST_VALUE
SELECT dept_id, emp_name, salary,
  FIRST_VALUE(emp_name) OVER (
    PARTITION BY dept_id ORDER BY salary DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) top_earner
FROM employees;
```

### 1.2 Hierarchical Query (CONNECT BY)

```sql
-- Tree traversal
SELECT LEVEL, LPAD(' ', 2*(LEVEL-1)) || employee_name tree,
       employee_id, manager_id
FROM employees
START WITH manager_id IS NULL
CONNECT BY PRIOR employee_id = manager_id
ORDER SIBLINGS BY employee_name;

-- Tính depth và path
SELECT employee_id,
       SYS_CONNECT_BY_PATH(employee_name, '/') path,
       CONNECT_BY_ISLEAF is_leaf,
       CONNECT_BY_ISCYCLE is_cycle,
       LEVEL depth
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id;
```

### 1.3 PIVOT / UNPIVOT

```sql
-- PIVOT: Rows → Columns
SELECT * FROM (
  SELECT department_id, job_id, salary FROM employees
)
PIVOT (
  SUM(salary) FOR job_id IN (
    'SA_MAN' AS sales_manager,
    'SA_REP' AS sales_rep,
    'IT_PROG' AS it_programmer
  )
)
ORDER BY department_id;

-- UNPIVOT: Columns → Rows
SELECT product_id, quarter, sales
FROM product_sales
UNPIVOT (
  sales FOR quarter IN (
    q1_sales AS 'Q1', q2_sales AS 'Q2',
    q3_sales AS 'Q3', q4_sales AS 'Q4'
  )
);
```

### 1.4 MERGE (Upsert)

```sql
MERGE INTO target_orders t
USING source_orders s ON (t.order_id = s.order_id)
WHEN MATCHED THEN
  UPDATE SET
    t.status      = s.status,
    t.updated_date = SYSDATE
  WHERE t.status != s.status
WHEN NOT MATCHED THEN
  INSERT (order_id, customer_id, order_date, amount, status)
  VALUES (s.order_id, s.customer_id, s.order_date, s.amount, s.status)
WHEN NOT MATCHED BY SOURCE THEN  -- 19c+
  DELETE;  -- Xóa rows trong target không có trong source
```

### 1.5 CTE (WITH Clause)

```sql
-- Recursive CTE
WITH RECURSIVE dept_tree (dept_id, dept_name, parent_id, level_no, path) AS (
  -- Anchor
  SELECT dept_id, dept_name, parent_dept_id, 1, dept_name
  FROM departments WHERE parent_dept_id IS NULL
  UNION ALL
  -- Recursive
  SELECT d.dept_id, d.dept_name, d.parent_dept_id,
         dt.level_no + 1,
         dt.path || ' > ' || d.dept_name
  FROM departments d
  JOIN dept_tree dt ON d.parent_dept_id = dt.dept_id
)
SELECT * FROM dept_tree ORDER BY path;

-- Multiple CTEs
WITH
  monthly_sales AS (
    SELECT TRUNC(sale_date,'MM') month, SUM(amount) total
    FROM sales GROUP BY TRUNC(sale_date,'MM')
  ),
  ranked AS (
    SELECT month, total,
           RANK() OVER (ORDER BY total DESC) rnk
    FROM monthly_sales
  )
SELECT month, total
FROM ranked WHERE rnk <= 3;
```

---

## 2. PL/SQL NÂNG CAO

### 2.1 Stored Procedure với Error Handling

```sql
CREATE OR REPLACE PROCEDURE transfer_funds(
  p_from_acct   IN  NUMBER,
  p_to_acct     IN  NUMBER,
  p_amount      IN  NUMBER,
  p_status      OUT VARCHAR2
) AS
  v_balance     NUMBER;
  e_insufficient EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_insufficient, -20001);
BEGIN
  -- Kiểm tra balance
  SELECT balance INTO v_balance
  FROM accounts
  WHERE account_id = p_from_acct
  FOR UPDATE NOWAIT;  -- Lock không chờ

  IF v_balance < p_amount THEN
    RAISE_APPLICATION_ERROR(-20001, 'Insufficient balance: ' || v_balance);
  END IF;

  -- Thực hiện transfer
  UPDATE accounts SET balance = balance - p_amount
  WHERE account_id = p_from_acct;

  UPDATE accounts SET balance = balance + p_amount
  WHERE account_id = p_to_acct;

  -- Log transaction
  INSERT INTO transfer_log (from_acct, to_acct, amount, transfer_time)
  VALUES (p_from_acct, p_to_acct, p_amount, SYSTIMESTAMP);

  COMMIT;
  p_status := 'SUCCESS';

EXCEPTION
  WHEN e_insufficient THEN
    ROLLBACK;
    p_status := 'FAILED: ' || SQLERRM;
  WHEN NO_DATA_FOUND THEN
    ROLLBACK;
    p_status := 'FAILED: Account not found';
  WHEN OTHERS THEN
    ROLLBACK;
    p_status := 'FAILED: ' || SQLERRM;
    -- Log lỗi vào error table
    INSERT INTO error_log (proc_name, error_msg, error_date)
    VALUES ('transfer_funds', SQLERRM, SYSDATE);
    COMMIT;  -- Commit error log
END transfer_funds;
/
```

### 2.2 Bulk Operations (tối ưu hiệu năng)

```sql
CREATE OR REPLACE PROCEDURE process_orders_bulk AS
  TYPE t_order_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE t_amounts   IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  v_order_ids  t_order_ids;
  v_amounts    t_amounts;
  v_errors     PLS_INTEGER;

  CURSOR c_orders IS
    SELECT order_id, amount FROM orders
    WHERE status = 'PENDING'
    FOR UPDATE;
BEGIN
  -- Bulk collect (tốt hơn từng row một)
  OPEN c_orders;
  LOOP
    FETCH c_orders
    BULK COLLECT INTO v_order_ids, v_amounts
    LIMIT 1000;  -- Xử lý 1000 rows mỗi lần

    EXIT WHEN v_order_ids.COUNT = 0;

    -- Bulk update với SAVE EXCEPTIONS
    BEGIN
      FORALL i IN 1..v_order_ids.COUNT
        SAVE EXCEPTIONS
        UPDATE orders
        SET    status = 'PROCESSING',
               processed_date = SYSDATE
        WHERE  order_id = v_order_ids(i);
    EXCEPTION
      WHEN OTHERS THEN
        v_errors := SQL%BULK_EXCEPTIONS.COUNT;
        FOR i IN 1..v_errors LOOP
          DBMS_OUTPUT.PUT_LINE(
            'Error on index ' || SQL%BULK_EXCEPTIONS(i).ERROR_INDEX ||
            ': ' || SQLERRM(-SQL%BULK_EXCEPTIONS(i).ERROR_CODE));
        END LOOP;
    END;

    COMMIT;
  END LOOP;
  CLOSE c_orders;
END;
/
```

### 2.3 Dynamic SQL

```sql
CREATE OR REPLACE FUNCTION get_table_count(
  p_owner  IN VARCHAR2,
  p_table  IN VARCHAR2
) RETURN NUMBER AS
  v_count NUMBER;
  v_sql   VARCHAR2(500);
BEGIN
  -- Validate input (tránh SQL injection)
  IF NOT REGEXP_LIKE(p_owner, '^[A-Z][A-Z0-9_$#]{0,29}$') OR
     NOT REGEXP_LIKE(p_table, '^[A-Z][A-Z0-9_$#]{0,29}$') THEN
    RAISE_APPLICATION_ERROR(-20002, 'Invalid identifier');
  END IF;

  v_sql := 'SELECT COUNT(*) FROM ' || p_owner || '.' || p_table;
  EXECUTE IMMEDIATE v_sql INTO v_count;
  RETURN v_count;

EXCEPTION
  WHEN OTHERS THEN
    RETURN -1;
END;
/

-- Dùng với REF CURSOR
CREATE OR REPLACE PROCEDURE get_rows(
  p_table     IN  VARCHAR2,
  p_where     IN  VARCHAR2 DEFAULT NULL,
  p_cursor    OUT SYS_REFCURSOR
) AS
  v_sql VARCHAR2(1000);
BEGIN
  v_sql := 'SELECT * FROM ' || p_table;
  IF p_where IS NOT NULL THEN
    v_sql := v_sql || ' WHERE ' || p_where;
  END IF;
  OPEN p_cursor FOR v_sql;
END;
/
```

### 2.4 Package

```sql
-- Package Spec
CREATE OR REPLACE PACKAGE pkg_order_mgmt AS
  -- Constants
  STATUS_PENDING    CONSTANT VARCHAR2(20) := 'PENDING';
  STATUS_PROCESSING CONSTANT VARCHAR2(20) := 'PROCESSING';
  STATUS_COMPLETED  CONSTANT VARCHAR2(20) := 'COMPLETED';

  -- Types
  TYPE r_order IS RECORD (
    order_id    orders.order_id%TYPE,
    customer_id orders.customer_id%TYPE,
    amount      orders.amount%TYPE
  );
  TYPE t_orders IS TABLE OF r_order;

  -- Functions & Procedures
  FUNCTION  get_order(p_id IN NUMBER) RETURN r_order;
  PROCEDURE process_order(p_id IN NUMBER);
  FUNCTION  get_pending_orders RETURN t_orders PIPELINED;
END pkg_order_mgmt;
/

-- Package Body
CREATE OR REPLACE PACKAGE BODY pkg_order_mgmt AS
  -- Private variable (persists for session)
  g_last_processed_id NUMBER := 0;

  FUNCTION get_order(p_id IN NUMBER) RETURN r_order AS
    v_rec r_order;
  BEGIN
    SELECT order_id, customer_id, amount
    INTO   v_rec
    FROM   orders WHERE order_id = p_id;
    RETURN v_rec;
  END;

  PROCEDURE process_order(p_id IN NUMBER) AS
  BEGIN
    UPDATE orders SET status = STATUS_PROCESSING WHERE order_id = p_id;
    g_last_processed_id := p_id;
    COMMIT;
  END;

  -- Pipelined function (streaming rows, không cần load tất cả vào memory)
  FUNCTION get_pending_orders RETURN t_orders PIPELINED AS
    v_rec r_order;
  BEGIN
    FOR ord IN (SELECT order_id, customer_id, amount FROM orders
                 WHERE status = STATUS_PENDING ORDER BY order_id) LOOP
      v_rec.order_id    := ord.order_id;
      v_rec.customer_id := ord.customer_id;
      v_rec.amount      := ord.amount;
      PIPE ROW(v_rec);
    END LOOP;
  END;
END pkg_order_mgmt;
/

-- Sử dụng
SELECT * FROM TABLE(pkg_order_mgmt.get_pending_orders());
```

---

## 3. JSON & XML (19c/23ai)

```sql
-- JSON_TABLE — parse JSON thành rows
SELECT jt.*
FROM json_log,
     JSON_TABLE(log_data, '$.events[*]'
       COLUMNS (
         event_id   NUMBER        PATH '$.id',
         event_type VARCHAR2(50)  PATH '$.type',
         event_time VARCHAR2(30)  PATH '$.timestamp'
       )) jt;

-- JSON_VALUE / JSON_QUERY
SELECT JSON_VALUE(data, '$.customer.name')   cust_name,
       JSON_VALUE(data, '$.order.total')     total,
       JSON_QUERY(data, '$.items')           items_json
FROM order_json_table;

-- IS JSON constraint
CREATE TABLE orders_json (
  id   NUMBER PRIMARY KEY,
  data CLOB CONSTRAINT chk_json CHECK (data IS JSON)
);

-- JSON Duality View (23ai) — REST API ready
CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW order_dv AS
  SELECT JSON {
    '_id'    : o.order_id,
    'status' : o.status,
    'customer' : (
      SELECT JSON {'name': c.name, 'email': c.email}
      FROM customers c WHERE c.cust_id = o.cust_id
    ),
    'items' : [
      SELECT JSON {'product': i.product_name, 'qty': i.quantity}
      FROM order_items i WHERE i.order_id = o.order_id
    ]
  }
  FROM orders o WITH INSERT UPDATE DELETE;
```

---

## Tài liệu tham khảo
- Oracle SQL Language Reference 19c
- Oracle PL/SQL Language Reference 19c  
- www.tranvanbinh.vn
