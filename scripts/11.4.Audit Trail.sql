-- Cấu hình extended auditing.
CONN sys/password AS SYSDBA
--CDB
ALTER SYSTEM SET audit_trail=DB,EXTENDED SCOPE=SPFILE;
SHUTDOWN IMMEDIATE
STARTUP
TRUNCATE TABLE aud$;
TRUNCATE TABLE fga_log$;

select * from aud$;

select * from fga_log$;

create table oaz18.BANG_NHO as select * from oaz18.bang_to where rownum < 10;

-- All la DDL
AUDIT ALL BY user1 BY ACCESS;

--All la DDL
grant all on OAZ18.BANG_TO to user1;
grant all on OAZ18.BANG_NHO to user1;

-- Audit DML
AUDIT insert,update,delete on oaz18.BANG_TO BY ACCESS;
AUDIT insert,update,delete on oaz18.BANG_NHO BY ACCESS;

CREATE AUDIT POLICY sl_BANG_NHO_pol ACTIONS select on OAZ18.BANG_NHO;

CREATE AUDIT POLICY audit_objpriv_pol6 ACTIONS ALL;

ALTER AUDIT POLICY audit_objpriv_pol6
	ADD ACTIONS    CREATE TABLE, DROP TABLE, TRUNCATE TABLE;
	

ALTER AUDIT POLICY audit_objpriv_pol6
	ADD ACTIONS    SELECT, UPDATE, DELETE, INSERT ON oaz18.bangnho;	

ALTER AUDIT POLICY audit_objpriv_pol6
	ADD ACTIONS    SELECT, UPDATE, DELETE, INSERT ON user1.xxx1;	
	
audit policy sl_BANG_NHO_pol;
audit policy audit_objpriv_pol6;
noaudit policy audit_objpriv_pol6;

SELECT policy_name, audit_option, condition_eval_opt
  FROM   audit_unified_policies where policy_name in ('AUDIT_OBJPRIV_POL6','SL_BANG_NHO_POL');
  
SELECT *
  FROM   audit_unified_enabled_policies;
  
SELECT *
FROM dba_stmt_audit_opts;

grant dba to user1;

-- Thực hiện audit 
CONN user1/oracle@pdb1;

select * from oaz18.BANG_NHO;

UPDATE oaz18.BANG_NHO SET address = address||'_NEW';
commit;

a


-- Kiểm tra dữ liệu audit trail
SELECT * FROM dba_common_audit_trail order by extended_timestamp desc;

select * from aud$ order by ntimestamp# desc;

SQL_TEXT
----------------------------
UPDATE oaz18.BANG_TO SET col2 = cold2||'_NEW'

UPDATE oaz18.BANG_TO SET cold2 = cold2||'_NEW'


