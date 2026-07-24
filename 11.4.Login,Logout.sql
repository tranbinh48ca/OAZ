--Audit th?i di?m logon, logofff c?a user vào Oracle Database
--M?c dích: Luu th?i di?m logon, logofff c?a user vào Oracle Database

drop table sys.log_on_off ;

--1.T?o trigger
create  table sys.log_on_off (USERNAME  varchar2(30),IP_ADDRESS   VARCHAR2(500 BYTE),host   VARCHAR2(500 BYTE) , time date, action varchar2(10));

create or replace trigger trg_logon
after logon on database
begin
    insert into sys.log_on_off values (user, SYS_CONTEXT ('USERENV', 'IP_ADDRESS'),SYS_CONTEXT ('USERENV', 'HOST'), sysdate, 'LOGON');
    commit;
end trg_logon;

create or replace trigger trg_logoff
before logoff on database
begin
    insert into sys.log_on_off values (user, SYS_CONTEXT ('USERENV', 'IP_ADDRESS'),SYS_CONTEXT ('USERENV', 'HOST'), sysdate, 'LOGOFF');
    commit;
end trg_logon;

select * from sys.log_on_off ;

--2.Test
 --Login user1, user2, sys
 --Logout user1, user2, sys
--3.Check log
select * from sys.log_on_off ;

--ROLLBACK:
alter trigger trg_logon disable;

alter trigger trg_logon enable;

select rowid, a.* from sys.table_ip a;