SELECT * FROM hr.employees;

/***** Chính sách VPD mức cột  *****/
--Chính sách VPD được áp dụng cho toàn bộ row. Theo mặc định, Chính sách VPD ở mức cột cho phép bạn hạn chế các row được hiển thị chỉ khi các cột được chỉ định được truy cập.

--CONN sys/password@db10g AS SYSDBA
GRANT EXECUTE ON dbms_rls TO hr;

CONN hr/oracle

-- Tạo hàm với các polcy để hạn chế quyền truy cập vào các cột SAL và COMM
-- nếu nhân viên không thuộc deptno=20.
CREATE OR REPLACE FUNCTION pf_job (oowner IN VARCHAR2, ojname IN VARCHAR2)
RETURN VARCHAR2 AS
  con VARCHAR2 (200);
BEGIN
  con := 'department_id = 20';
  RETURN (con);
END pf_job;
/

-- Áp các policy cho bảng.
BEGIN
  DBMS_RLS.ADD_POLICY (object_schema     => 'hr',
                       object_name       => 'employees',
                       policy_name       => 'sp_job',
                       function_schema   => 'hr',
                       policy_function   => 'pf_job',
                       sec_relevant_cols => 'salary,commission_pct');
END;
/

-- Chúng ta sẽ xem được tất cả các bản ghi nếu deptno khác 20, nhưng SAL, COMM không hiển thị

SELECT employee_id, first_name, job_id,department_id FROM employees;

100	Steven	AD_PRES	90
101	Neena	AD_VP	90
102	Lex	AD_VP	90
103	Alexander	IT_PROG	60
...


107 rows selected.

-- Các row hiển thị thêm thông tin SAL, COMM nếu deptno = 20

SELECT employee_id, first_name, job_id, salary, commission_pct FROM employees;

201	Michael	MK_MAN	13000	
202	Pat	MK_REP	6000	

2 row selected

5 rows selected.

-- Bỏ policy ra khỏi bảng.
BEGIN
  DBMS_RLS.DROP_POLICY (object_schema     => 'hr',
                        object_name       => 'employees',
                        policy_name       => 'sp_job');
END;
/

/***** Column Masking *****/

-- Tạo policy
BEGIN
  DBMS_RLS.ADD_POLICY (object_schema         => 'hr',
                       object_name           => 'employees',
                       policy_name           => 'sp_job',
                       function_schema       => 'hr',
                       policy_function       => 'pf_job',
                       sec_relevant_cols     => 'salary,commission_pct',
                       sec_relevant_cols_opt => DBMS_RLS.ALL_ROWS);
END;
/

-- Tất cả các row được trả về với SAL và COMM là NULL nhưng nếu deptno=20 sẽ hiển thị giá trị SAL và COMM
SELECT employee_id, first_name, job_id, salary, commission_pct FROM employees;

--SELECT empno, ename, job, sal, comm FROM emp;

     EMPNO ENAME      JOB              SAL       COMM
---------- ---------- --------- ---------- ----------
      7369 SMITH      CLERK          10000
      7499 ALLEN      SALESMAN
      7521 WARD       SALESMAN
      7566 JONES      MANAGER         2975
      7654 MARTIN     SALESMAN
      7698 BLAKE      MANAGER
      7782 CLARK      MANAGER
      7788 SCOTT      ANALYST         3000
      7839 KING       PRESIDENT
      7844 TURNER     SALESMAN
      7876 ADAMS      CLERK           1100

     EMPNO ENAME      JOB              SAL       COMM
---------- ---------- --------- ---------- ----------
      7900 JAMES      CLERK
      7902 FORD       ANALYST         3000
      7934 MILLER     CLERK

14 rows selected.

-- Xóa policy
BEGIN
  DBMS_RLS.DROP_POLICY (object_schema     => 'hr',
                        object_name       => 'employees',
                        policy_name       => 'sp_job');
END;
/


/**** DUNG VIEW ***/
select * from hr.employees;

create view hr.v_employees as select * from hr.employees where department_id=20;

select * from  hr.v_employees;