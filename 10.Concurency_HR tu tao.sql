-- User1
-- 
create user user1 identified by oracle;
grant connect, resource, dba to user1;

create user user2 identified by oracle;
grant connect, resource, dba to user2;

select * from hr.employees;

-- Cau 1: Bảng 100 triệu row
alter table  hr.emp add salary number default 1000;

--> 
alter table  hr.emp add salary number;
alter table  hr.emp modify salary default 1000; --New

update hr.emp  set salary=2000;

rollback;

commit;

-- Cau 2:
alter table  hr.emp add salary_max number;

--alter table  hr.employees modify salary default 1000;
--

select * from hr.emp where name='Dean Bollich';

UPDATE hr.emp
    SET salary=salary+101
    WHERE name='Dean Bollich';
    
    rollback;

UPDATE hr.emp
    SET salary=salary+102
    WHERE name='Dean Bollich';
 
select * from  hr.employees order by 1;

UPDATE hr.emp
    SET salary=salary+102
    WHERE name='Milo Manoni';
      
-- User2 
UPDATE emp
    SET salary=salary*1.1
    WHERE name='Dean Bollich';
    
    commit;
    
--    rollback;

-- Giai quyet lock
--+Cach 1
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
   
--+Cach 2
SELECT sid, serial#, username
  FROM v$session WHERE sid IN
  (SELECT blocking_session FROM v$session);
  
ALTER SYSTEM KILL SESSION '257,48772' immediate;


    