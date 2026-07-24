---
name: oracle-sql-advanced-analytic
description: >
  SQL Nâng cao Oracle: Analytic Functions, Hierarchical Query, CTE, PIVOT.
  Kích hoạt khi hỏi về: analytic functions Oracle, window functions Oracle,
  ROW_NUMBER Oracle, RANK DENSE_RANK Oracle, LEAD LAG Oracle,
  FIRST_VALUE LAST_VALUE Oracle, NTH_VALUE Oracle, NTILE Oracle,
  SUM OVER Oracle, AVG OVER running total Oracle,
  PARTITION BY ORDER BY OVER Oracle, frame clause ROWS RANGE,
  UNBOUNDED PRECEDING CURRENT ROW FOLLOWING Oracle,
  hierarchical query Oracle, CONNECT BY PRIOR Oracle,
  START WITH Oracle, SYS_CONNECT_BY_PATH Oracle,
  CONNECT_BY_ISLEAF CONNECT_BY_ISCYCLE Oracle, LEVEL Oracle,
  recursive CTE Oracle, WITH clause recursive Oracle,
  PIVOT Oracle, UNPIVOT Oracle, dynamic pivot Oracle,
  LISTAGG Oracle, WM_CONCAT Oracle, string aggregation Oracle.
---

# SK03-02 · Advanced SQL: Analytic Functions, Hierarchical, CTE, PIVOT

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ANALYTIC / WINDOW FUNCTIONS

### 1.1 Ranking Functions

```sql
-- ── ROW_NUMBER, RANK, DENSE_RANK ─────────────────────────
SELECT employee_id, department_id, salary,
  ROW_NUMBER() OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
  )                        row_num,   -- 1,2,3,4... (luôn unique)
  RANK() OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
  )                        rnk,       -- 1,2,2,4... (gaps sau ties)
  DENSE_RANK() OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
  )                        dense_rnk, -- 1,2,2,3... (no gaps)
  PERCENT_RANK() OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
  )                        pct_rank,  -- 0 to 1
  CUME_DIST() OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
  )                        cume_dist  -- Cumulative distribution
FROM employees;

-- ── NTILE (Phân nhóm đều) ────────────────────────────────
SELECT employee_id, salary,
  NTILE(4) OVER (ORDER BY salary DESC) quartile,  -- Q1,Q2,Q3,Q4
  NTILE(10) OVER (ORDER BY salary DESC) decile     -- Top 10%, 20%...
FROM employees;

-- ── Top-N per group (common pattern) ─────────────────────
-- Lấy top 3 salary của mỗi department
SELECT employee_id, department_id, salary, dept_rank
FROM (
  SELECT employee_id, department_id, salary,
         ROW_NUMBER() OVER (
           PARTITION BY department_id
           ORDER BY salary DESC
         ) dept_rank
  FROM employees
)
WHERE dept_rank <= 3
ORDER BY department_id, dept_rank;
```

### 1.2 Lead/Lag và Value Functions

```sql
-- ── LAG / LEAD (so sánh với row trước/sau) ───────────────
SELECT employee_id, department_id, hire_date, salary,
  LAG(salary, 1, 0) OVER (
    PARTITION BY department_id
    ORDER BY hire_date
  )                        prev_salary,    -- Salary của nhân viên trước
  LEAD(salary, 1, NULL) OVER (
    PARTITION BY department_id
    ORDER BY hire_date
  )                        next_salary,    -- Salary của nhân viên sau
  salary - LAG(salary, 1, salary) OVER (
    PARTITION BY department_id
    ORDER BY hire_date
  )                        salary_change,  -- Thay đổi so với trước
  -- LAG với offset = 2 (so sánh với 2 rows trước)
  LAG(salary, 2) OVER (ORDER BY hire_date) two_before
FROM employees
ORDER BY department_id, hire_date;

-- ── FIRST_VALUE / LAST_VALUE ─────────────────────────────
SELECT employee_id, department_id, salary,
  FIRST_VALUE(salary) OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) highest_in_dept,
  LAST_VALUE(salary) OVER (
    PARTITION BY department_id
    ORDER BY salary DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) lowest_in_dept,
  NTH_VALUE(salary, 2) OVER (  -- 2nd highest
    PARTITION BY department_id
    ORDER BY salary DESC
    ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
  ) second_highest
FROM employees;

-- ── FIRST / LAST aggregate ────────────────────────────────
SELECT department_id,
  MAX(salary) KEEP (DENSE_RANK FIRST ORDER BY hire_date) oldest_emp_sal,
  MIN(salary) KEEP (DENSE_RANK LAST  ORDER BY hire_date) newest_emp_sal
FROM employees
GROUP BY department_id;
```

### 1.3 Aggregate Window Functions

```sql
-- ── Running totals và moving averages ────────────────────
SELECT sale_date,
       region,
       daily_amount,
  -- Running total (cumulative)
  SUM(daily_amount) OVER (
    PARTITION BY region
    ORDER BY sale_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  )                               running_total,
  -- Moving average (last 7 days)
  ROUND(AVG(daily_amount) OVER (
    PARTITION BY region
    ORDER BY sale_date
    ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
  ), 2)                           moving_avg_7day,
  -- Compare với previous period %
  ROUND((daily_amount - LAG(daily_amount) OVER (
    PARTITION BY region ORDER BY sale_date
  )) / NULLIF(LAG(daily_amount) OVER (
    PARTITION BY region ORDER BY sale_date
  ), 0) * 100, 1)                 pct_change_vs_prev,
  -- Percent of total per region
  ROUND(daily_amount / SUM(daily_amount) OVER (
    PARTITION BY region
  ) * 100, 2)                     pct_of_region_total,
  -- Percent of grand total
  ROUND(daily_amount / SUM(daily_amount) OVER () * 100, 2) pct_of_grand_total
FROM daily_sales
ORDER BY region, sale_date;

-- ── Frame Clause variants ─────────────────────────────────
-- ROWS (số rows thực tế):
ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW  -- Từ đầu đến row hiện tại
ROWS BETWEEN 3 PRECEDING AND CURRENT ROW          -- 4-row window
ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING          -- 3-row centered window
ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING  -- Từ row này đến cuối

-- RANGE (logical range, dùng với ORDER BY value):
RANGE BETWEEN INTERVAL '7' DAY PRECEDING AND CURRENT ROW  -- 7-day window
RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW          -- Default

-- ── RATIO_TO_REPORT ─────────────────────────────────────
SELECT department_id, employee_id, salary,
  ROUND(RATIO_TO_REPORT(salary) OVER (
    PARTITION BY department_id
  ) * 100, 2) pct_of_dept_total
FROM employees
ORDER BY department_id, salary DESC;
```

---

## 2. HIERARCHICAL QUERIES (CONNECT BY)

```sql
-- ── Basic hierarchy ───────────────────────────────────────
-- Employee reporting structure
SELECT LEVEL,
       LPAD(' ', 2*(LEVEL-1)) || employee_id  emp_id_tree,
       LPAD(' ', 2*(LEVEL-1)) || first_name   name_tree,
       first_name, last_name,
       manager_id,
       employee_id
FROM employees
START WITH manager_id IS NULL          -- Root: CEO (no manager)
CONNECT BY PRIOR employee_id = manager_id  -- Parent-child relationship
ORDER SIBLINGS BY last_name;          -- Sort within same level

-- ── LEVEL, path, leaf, cycle ─────────────────────────────
SELECT LEVEL                                          depth,
       employee_id,
       first_name,
       SYS_CONNECT_BY_PATH(first_name, ' > ')        path_from_root,
       CONNECT_BY_ISLEAF                              is_leaf,        -- 1=leaf
       CONNECT_BY_ISCYCLE                             is_cycle,       -- 1=cycle detected
       CONNECT_BY_ROOT first_name                     root_name,
       CONNECT_BY_ROOT employee_id                    root_id
FROM employees
START WITH manager_id IS NULL
CONNECT BY NOCYCLE PRIOR employee_id = manager_id    -- NOCYCLE: phòng infinite loop
ORDER SIBLINGS BY first_name;

-- ── Query subtree (một nhánh) ─────────────────────────────
-- Tất cả reports của manager_id = 100 (direct và indirect)
SELECT employee_id, first_name, LEVEL
FROM employees
START WITH manager_id = 100
CONNECT BY PRIOR employee_id = manager_id;

-- ── Generate number series ────────────────────────────────
-- Không cần table
SELECT LEVEL AS num FROM dual
CONNECT BY LEVEL <= 10;
-- Result: 1,2,3,4,5,6,7,8,9,10

-- Generate date series
SELECT TRUNC(SYSDATE) - (LEVEL - 1) AS date_val
FROM dual
CONNECT BY LEVEL <= 30
ORDER BY date_val;

-- ── Category tree (bill of materials) ────────────────────
SELECT LEVEL,
       LPAD(' ', 2*(LEVEL-1)) || category_name tree_display,
       category_id, parent_category_id,
       SYS_CONNECT_BY_PATH(category_name, '/') full_path
FROM product_categories
START WITH parent_category_id IS NULL
CONNECT BY PRIOR category_id = parent_category_id
ORDER SIBLINGS BY category_name;
```

---

## 3. CTE — COMMON TABLE EXPRESSIONS (WITH Clause)

```sql
-- ── Simple CTE ────────────────────────────────────────────
WITH dept_stats AS (
  SELECT department_id,
         AVG(salary)   avg_sal,
         MAX(salary)   max_sal,
         COUNT(*)      headcount
  FROM employees
  GROUP BY department_id
)
SELECT e.employee_id, e.first_name, e.salary,
       d.avg_sal department_avg,
       ROUND(e.salary - d.avg_sal, 2) vs_avg
FROM employees e
JOIN dept_stats d ON e.department_id = d.department_id
WHERE e.salary > d.avg_sal
ORDER BY vs_avg DESC;

-- ── Multiple CTEs ─────────────────────────────────────────
WITH
  high_salary AS (
    SELECT employee_id, salary FROM employees
    WHERE salary > 10000
  ),
  dept_count AS (
    SELECT department_id, COUNT(*) dept_size
    FROM employees GROUP BY department_id
  ),
  combined AS (
    SELECT hs.employee_id, hs.salary, dc.dept_size
    FROM high_salary hs
    JOIN employees e ON hs.employee_id = e.employee_id
    JOIN dept_count dc ON e.department_id = dc.department_id
  )
SELECT * FROM combined WHERE dept_size >= 5;

-- ── Recursive CTE ─────────────────────────────────────────
-- Employee hierarchy (thay thế CONNECT BY)
WITH emp_hierarchy (employee_id, first_name, manager_id, depth, path) AS (
  -- Anchor: root nodes
  SELECT employee_id, first_name, manager_id,
         0 AS depth,
         CAST(first_name AS VARCHAR2(4000)) AS path
  FROM employees
  WHERE manager_id IS NULL

  UNION ALL

  -- Recursive: add one level
  SELECT e.employee_id, e.first_name, e.manager_id,
         h.depth + 1,
         h.path || ' > ' || e.first_name
  FROM employees e
  JOIN emp_hierarchy h ON e.manager_id = h.employee_id
)
CYCLE employee_id SET is_cycle TO '1' DEFAULT '0'  -- Detect cycles
SELECT depth, LPAD(' ',depth*2) || first_name tree_view,
       path, is_cycle
FROM emp_hierarchy
ORDER BY path;

-- ── CTE for INSERT/UPDATE/DELETE (12c+) ───────────────────
WITH data_to_archive AS (
  SELECT order_id FROM orders
  WHERE order_date < DATE '2020-01-01'
    AND status = 'COMPLETED'
)
INSERT INTO orders_archive
SELECT * FROM orders
WHERE order_id IN (SELECT order_id FROM data_to_archive);

-- Factored subquery eliminates repeated computation
WITH monthly_avg AS (
  SELECT TRUNC(sale_date,'MM') month,
         AVG(amount) avg_amount
  FROM sales GROUP BY TRUNC(sale_date,'MM')
)
SELECT s.sale_date, s.amount,
       m.avg_amount monthly_avg,
       CASE WHEN s.amount > m.avg_amount THEN 'Above'
            ELSE 'Below' END vs_avg
FROM sales s
JOIN monthly_avg m ON TRUNC(s.sale_date,'MM') = m.month;
```

---

## 4. PIVOT VÀ UNPIVOT

```sql
-- ── PIVOT (rows → columns) ────────────────────────────────
-- Dữ liệu gốc: employee_id, quarter, revenue
-- Muốn: employee_id | Q1 | Q2 | Q3 | Q4

SELECT * FROM (
  SELECT employee_id, quarter, revenue
  FROM sales_data
)
PIVOT (
  SUM(revenue)
  FOR quarter IN (
    'Q1' AS Q1_revenue,
    'Q2' AS Q2_revenue,
    'Q3' AS Q3_revenue,
    'Q4' AS Q4_revenue
  )
)
ORDER BY employee_id;

-- Multiple aggregate PIVOT
SELECT * FROM (
  SELECT department_id, job_id, salary, commission_pct
  FROM employees
)
PIVOT (
  AVG(salary)       AS avg_sal,
  COUNT(*)          AS headcount,
  MAX(commission_pct) AS max_comm
  FOR job_id IN (
    'IT_PROG'  AS it_prog,
    'SA_REP'   AS sales_rep,
    'ST_CLERK' AS stock_clerk
  )
);

-- ── Dynamic PIVOT (không biết trước values) ──────────────
-- Cần dùng dynamic SQL
DECLARE
  v_cols  VARCHAR2(4000);
  v_sql   VARCHAR2(32767);
BEGIN
  -- Lấy danh sách values
  SELECT LISTAGG('''' || quarter || ''' AS ' || quarter, ', ')
         WITHIN GROUP (ORDER BY quarter)
  INTO v_cols
  FROM (SELECT DISTINCT quarter FROM sales_data);

  -- Tạo dynamic pivot
  v_sql := '
    SELECT * FROM (
      SELECT employee_id, quarter, revenue FROM sales_data
    )
    PIVOT (
      SUM(revenue)
      FOR quarter IN (' || v_cols || ')
    )
    ORDER BY employee_id';

  EXECUTE IMMEDIATE v_sql;
END;
/

-- ── UNPIVOT (columns → rows) ─────────────────────────────
-- Ngược lại với PIVOT
-- Dữ liệu: employee_id, Q1_revenue, Q2_revenue, Q3_revenue, Q4_revenue
-- Muốn: employee_id | quarter | revenue

SELECT employee_id, quarter, revenue
FROM quarterly_revenue_pivot
UNPIVOT (
  revenue                  -- New value column name
  FOR quarter              -- New key column name
  IN (
    Q1_revenue AS 'Q1',
    Q2_revenue AS 'Q2',
    Q3_revenue AS 'Q3',
    Q4_revenue AS 'Q4'
  )
)
WHERE revenue > 0
ORDER BY employee_id, quarter;

-- UNPIVOT với multiple columns
SELECT product_id, metric_name, year_val, value
FROM product_yearly_stats
UNPIVOT (
  (value, year_val)        -- Multiple value columns
  FOR metric_name
  IN (
    (revenue_2024, 2024) AS 'Revenue',
    (cost_2024, 2024)    AS 'Cost',
    (revenue_2025, 2025) AS 'Revenue',
    (cost_2025, 2025)    AS 'Cost'
  )
);
```

---

## 5. MERGE STATEMENT (UPSERT)

```sql
-- ── Full MERGE với DELETE ─────────────────────────────────
MERGE INTO target_inventory t
USING (
  -- Source có thể là table, view, subquery
  SELECT product_id, quantity, warehouse_id, last_update
  FROM source_inventory
  WHERE last_update > SYSDATE - 1  -- Chỉ lấy changes hôm nay
) s
ON (t.product_id = s.product_id AND t.warehouse_id = s.warehouse_id)
WHEN MATCHED THEN
  UPDATE SET
    t.quantity    = s.quantity,
    t.last_update = s.last_update
  WHERE t.quantity != s.quantity    -- Chỉ update khi thực sự thay đổi
  DELETE WHERE s.quantity = 0       -- Delete nếu qty = 0
WHEN NOT MATCHED THEN
  INSERT (product_id, warehouse_id, quantity, last_update)
  VALUES (s.product_id, s.warehouse_id, s.quantity, s.last_update)
  WHERE s.quantity > 0;             -- Chỉ insert nếu có qty

-- ── MERGE với RETURNING ───────────────────────────────────
DECLARE
  TYPE t_ids IS TABLE OF NUMBER;
  v_ids t_ids;
BEGIN
  MERGE INTO orders t
  USING new_orders s ON (t.order_ref = s.order_ref)
  WHEN NOT MATCHED THEN
    INSERT (order_id, order_ref, amount, status)
    VALUES (order_seq.NEXTVAL, s.order_ref, s.amount, 'PENDING')
  RETURNING order_id BULK COLLECT INTO v_ids;

  DBMS_OUTPUT.PUT_LINE(v_ids.COUNT || ' orders inserted');
END;
/
```

---

## 6. LISTAGG VÀ STRING AGGREGATION

```sql
-- ── LISTAGG (12c, aggregate) ─────────────────────────────
SELECT department_id,
  LISTAGG(last_name, ', ')
    WITHIN GROUP (ORDER BY last_name)  AS employees_list,
  LISTAGG(DISTINCT last_name, ', ')    -- DISTINCT trong 19c+
    WITHIN GROUP (ORDER BY last_name)  AS unique_names,
  COUNT(*)                             headcount
FROM employees
GROUP BY department_id;

-- Với ON OVERFLOW TRUNCATE (19c+, tránh ORA-01489)
SELECT department_id,
  LISTAGG(last_name, ', '
    ON OVERFLOW TRUNCATE '...' WITH COUNT)
  WITHIN GROUP (ORDER BY last_name) employee_names
FROM employees
GROUP BY department_id;

-- ── LISTAGG như analytic function (19c+) ─────────────────
SELECT employee_id, department_id, last_name,
  LISTAGG(last_name, ', ')
    WITHIN GROUP (ORDER BY last_name)
    OVER (PARTITION BY department_id)  dept_colleagues
FROM employees
ORDER BY department_id, last_name;

-- ── JSON_ARRAYAGG (12c+) ─────────────────────────────────
SELECT department_id,
  JSON_ARRAYAGG(
    JSON_OBJECT('id' VALUE employee_id, 'name' VALUE last_name)
    ORDER BY last_name
  ) employees_json
FROM employees
GROUP BY department_id;

-- ── COLLECT và CAST (11g) ────────────────────────────────
-- Legacy approach trước LISTAGG
SELECT department_id,
  CAST(COLLECT(last_name ORDER BY last_name) AS SYS.ODCIVARCHAR2LIST) names_collection
FROM employees GROUP BY department_id;
```

---

**Tài liệu tham khảo:**
- Oracle Database SQL Language Reference 19c — Analytic Functions
- Oracle Database SQL Reference — CONNECT BY, CTE, PIVOT
- docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/
- www.tranvanbinh.vn
