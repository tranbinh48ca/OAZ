-- 1.Check Policy da duoc cau hinh
select * from DBA_AUDIT_POLICIES;

-- Drop
BEGIN
  DBMS_FGA.drop_policy(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_EMPLOYEES');
END;

--SQL> show parameter audit; 

--audit_trail                       DB

select * from hr.employees;

/***** 2.ADD *****/
BEGIN
  DBMS_FGA.add_policy(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_EMPLOYEES',
    --AUDIT_CONDITION => 'SYS.check_ip_machine = 1',
    --audit_condition => SYS_CONTEXT('USERENV','SESSION_USER') <> 'BINHTV',
    statement_types => 'SELECT, INSERT,UPDATE,DELETE'
    );
END;

/***** 3.ROLLBACK: DISABLE, DROP*****/
-- Disable
BEGIN
  DBMS_FGA.disable_policy(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_EMPLOYEES');
END;
/

BEGIN
  DBMS_FGA.enable_policy(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_EMPLOYEES');
END;
/

-- Drop
BEGIN
  DBMS_FGA.drop_policy(
    object_schema   => 'HR',
    object_name     => 'EMPLOYEES',
    policy_name     => 'FGA_EMPLOYEES');
END;

--4.TEST
create user oaz29 identified by oracle;

grant connect, resource, select any table to oaz29;

grant all on hr.employees to oaz29;

create user user1 identified by oracle;

grant connect, resource, update any table,dba to user1;

grant all on hr.employees to user1;

create user user2 identified by oracle;

grant connect, resource, select any table,dba to user2;

grant all on hr.employees to user2;

create user test_dba identified by oracle;

grant connect, resource, select any table,dba to test_dba;

-- oaz29
SELECT *
  FROM hr.employees
  WHERE
    department_id = 1;    

SELECT *
  FROM hr.employees;
  
--User1,2 
SELECT *
  FROM hr.employees
  WHERE
    department_id = 1;
    
update hr.employees set email='JWHALEN_NEW' where department_id = 10;

commit;

--USER SYS CO GIAM DUOC KHONG: KHONG
SELECT *
  FROM hr.employees
  WHERE
    department_id = 1;
    
update hr.employees set email='JWHALEN_NEW_SYS' where department_id = 10;
commit;

--USER TEST_DBA CO GIAM DUOC KHONG: CO
create user test_dba identified by oracle;

grant connect, resource, dba to test_dba;

SELECT *
  FROM hr.employees
  WHERE
    department_id = 1;
    
update hr.employees set email='JWHALEN_NEW' where department_id = 10;
commit;

--DBA KHONG TRUNCTE DUOC: truncate table sys.fga_log$;, PHAI QUYEN SYSDBA

-- 5.Check log da audit (bang sys.fga_log$)
select * from dba_fga_audit_trail 
where  timestamp > sysdate-1 order by timestamp desc

select * from sys.fga_log$ where  ntimestamp# > sysdate-1 order by ntimestamp# desc;

select * from DBA_COMMON_AUDIT_TRAIL;

--truncate table fga_log$;

--truncate table hr.employees;  -- Khong bat duoc


--Phụ lục: Hàm check_ip_machine

-- Bỏ các user máy chủ ứng dụng do ứng dụng đã ghi log rồi
CREATE OR REPLACE FUNCTION SYS.check_ip_machine
return number
is
begin
--    if (SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'BINHTV'
--         and (SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  like '192.168.1%' or SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  like '1192.168.2%'
--        )) then
    if (SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.1.%' and
        SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.2.%' and
        SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.3.%')  then
        return 1;
    else
        return 0;
    end if;
end;