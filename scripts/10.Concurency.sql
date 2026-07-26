-- User1
create user user1 identified by oracle;
grant connect, resource, dba to user1;

create user user2 identified by oracle;
grant connect, resource, dba to user2;

create user user3 identified by oracle;
grant connect, resource, dba to user3;

select * from hr.employees;

-- Cau 1: Bảng 100 triệu row???
alter table  hr.employees add salary number default 1000; --lock toan bo bang, co the treo DB neu HT online

--> 
alter table  hr.employees add salary number;
alter table  hr.employees modify salary default 1000; --New

update hr.EMPlOYEES  set salary=3000;

rollback;

commit;

-- Cau 2:
--User1/sys
create table user1.test(id number); --> DDL la implicit commit;

alter table  hr.employees add salary_max29 number;

--alter table  hr.employees modify salary default 1000;
--

UPDATE hr.employees
    SET salary=salary+101
    WHERE first_name='John';
    
    rollback;

select * from hr.employees;

UPDATE hr.employees
    SET salary=salary+102
    WHERE first_name='John';
 
select * from  hr.employees WHERE first_name='John' order by 1;

UPDATE hr.employees
    SET salary=salary+102
    WHERE first_name='Kevin';
      
-- User2 
UPDATE hr.employees
    SET salary=salary*1.1
    WHERE first_name='John';

--user1/sys    
    commit;
    
--    rollback;

-- Giai quyet lock
SELECT sid, serial#, username
  FROM v$session WHERE sid IN
  (SELECT blocking_session FROM v$session);
  
ALTER SYSTEM KILL SESSION '409,54148' immediate;

SELECT /*SID*/  'kill -9 ' || spid a, a.INST_ID,A.SQL_ID,A.SID, A.SERIAL#, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,a.prev_exec_start,BACKGROUND
FROM gv$session a, gv$process b 
WHERE b.addr = a.paddr   
AND a.inst_id=b.inst_id 
--and b.inst_id=2
AND a.sid in (
257
)
and type='USER'
order by inst_id;


--DEADLOCK
SELECT * FROM hr.employees;

--t1 User1
update hr.EMPlOYEES  set salary=3000 where  employee_id= 200;

--t1 User2
update hr.EMPlOYEES  set salary=2500 where  employee_id= 201;

--t2 User1
update hr.EMPlOYEES  set salary=3000 where  employee_id= 201;

--t2 User2
update hr.EMPlOYEES  set salary=3000 where  employee_id= 200;

rollback;
 
