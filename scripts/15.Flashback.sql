    
--FLASHBACK
select * from v$parameter where name like '%undo%';

--107
select * from hr.employees;

--delete   hr.employees where  employee_id > 102;

update hr.employees set  first_name=first_name ||'_New'; 

commit;

select * from hr.employees;

--FLASHBACK QUERY1
create table hr.xxx_employees_20251210_22h38 as select * FROM   hr.employees AS OF TIMESTAMP TO_TIMESTAMP('20251210 22:38:00', 'YYYYMMDD HH24:MI:SS');

select * from hr.xxx_employees_20251210_22h38;

select * from hr.employees;

insert into hr.employees  select * from hr.xxx_employees_20251210_22h38;

commit;

select * from hr.employees;

alter table hr.employees rename to xxx_employees;

alter table hr.xxx_employees_20251210_22h38 rename to employees;

select * from hr.employees;

--Flashback table
alter table hr.employees enable row movement;

FLASHBACK TABLE hr.employees TO TIMESTAMP TO_TIMESTAMP('20251210 22:38:00', 'YYYYMMDD HH24:MI:SS');

select * from hr.employees;

--FLASHBACK DROP
create table hr.objects as select * from dba_objects;

--75,126
select * from hr.objects;

drop table hr.objects;

--[Error] Execution (50: 18): ORA-00942: table or view does not exist
select * from hr.objects;

hr

HR	BIN$RZvs7SJveUvgY4C2qMBmMQ==$0	TABLE	12582912	65536	1048576	27	2147483645

--75,126
select * from HR."BIN$RZvs7SJveUvgY4C2qMBmMQ==$0";

flashback table hr.objects  TO BEFORE DROP;

--75,126
select * from hr.objects;

