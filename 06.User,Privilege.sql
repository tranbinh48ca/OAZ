-- 1.TAO USER COMMON c##oaz29
create user c##oaz29 identified by oracle container=all;

-- Tạo xong ấn F4 kiểm tra lại
grant connect, RESOURCE , dba to c##oaz29 container=all;

-- GRANT
-- System Privilege
select * from dba_sys_privs where grantee ='C##OAZ29';

-- Object privilege
select * from dba_tab_privs where grantee='C##OAZ29';

-- Role:DBA, CONNECT, RESOURCE
select * from dba_role_privs where grantee='C##OAZ29';

-- Vao CDB bang c##oaz29: Session
select * from session_privs;

select * from session_roles;

-- Gan quyen
grant select on SYS.FGA_LOG$ to c##oaz29  WITH ADMIN OPTION;

grant select on SYS.FGA_LOG$ to c##oaz29  WITH GRANT OPTION;

grant alter any procedure to c##oaz29 container=all;


-- Quyen view moi package:
        
grant SELECT ANY DICTIONARY to c##oaz29;

grant debug any procedure to c##oaz29;

--REVOKE
revoke debug any procedure from c##oaz29;

-- Vao PDB1 bang c##oaz29


-- 2.TAO USER LOCAL TRONG PDB1
-- Vao c##az22 TNS db19c_pdb1 de tao:
create user oaz29 identified by oracle;

grant connect, resource, dba to oaz29;

-- Tuong tu

-- PROFILE
create PROFILE "PROFILE_USER_oaz29" LIMIT
  SESSIONS_PER_USER 3
  CPU_PER_SESSION UNLIMITED
  CPU_PER_CALL UNLIMITED
  CONNECT_TIME UNLIMITED
  IDLE_TIME UNLIMITED
  LOGICAL_READS_PER_SESSION UNLIMITED
  LOGICAL_READS_PER_CALL UNLIMITED
  COMPOSITE_LIMIT UNLIMITED
  PRIVATE_SGA UNLIMITED
  FAILED_LOGIN_ATTEMPTS UNLIMITED
  INACTIVE_ACCOUNT_TIME UNLIMITED
  PASSWORD_LIFE_TIME 45
  PASSWORD_REUSE_TIME UNLIMITED
  PASSWORD_REUSE_MAX UNLIMITED
  PASSWORD_LOCK_TIME UNLIMITED
  PASSWORD_GRACE_TIME UNLIMITED
  PASSWORD_VERIFY_FUNCTION Default;
  
create PROFILE "PROFILE_APP_oaz29" LIMIT
  SESSIONS_PER_USER UNLIMITED
  CPU_PER_SESSION UNLIMITED
  CPU_PER_CALL UNLIMITED
  CONNECT_TIME UNLIMITED
  IDLE_TIME UNLIMITED
  LOGICAL_READS_PER_SESSION UNLIMITED
  LOGICAL_READS_PER_CALL UNLIMITED
  COMPOSITE_LIMIT UNLIMITED
  PRIVATE_SGA UNLIMITED
  FAILED_LOGIN_ATTEMPTS UNLIMITED
  INACTIVE_ACCOUNT_TIME UNLIMITED
  PASSWORD_LIFE_TIME UNLIMITED
  PASSWORD_REUSE_TIME UNLIMITED
  PASSWORD_REUSE_MAX UNLIMITED
  PASSWORD_LOCK_TIME UNLIMITED
  PASSWORD_GRACE_TIME UNLIMITED
  PASSWORD_VERIFY_FUNCTION Default;
  
ALTER USER oaz29  PROFILE "PROFILE_USER_oaz29";
 
--Gan quyen tu user oaz29 sang user TEST
select 'grant ' || privilege || ' to TEST;' from dba_sys_privs
where grantee='OAZ29';

grant UNLIMITED TABLESPACE to TEST;

create user test identified by oracle;

grant UNLIMITED TABLESPACE to TEST;

grant ALTER on HR.EMPLOYEES to oaz29;
grant DELETE on HR.EMPLOYEES to oaz29;
grant INDEX on HR.EMPLOYEES to oaz29;
grant INSERT on HR.EMPLOYEES to oaz29;
grant SELECT on HR.EMPLOYEES to oaz29;
grant UPDATE on HR.EMPLOYEES to oaz29;
grant REFERENCES on HR.EMPLOYEES to oaz29;
grant READ on HR.EMPLOYEES to oaz29;
grant ON COMMIT REFRESH on HR.EMPLOYEES to oaz29;
grant QUERY REWRITE on HR.EMPLOYEES to oaz29;
grant DEBUG on HR.EMPLOYEES to oaz29;
grant FLASHBACK on HR.EMPLOYEES to oaz29;

-- Gan moi quyen object cua oaz29 cho user test
select 'grant ' || privilege || ' on ' || owner||'.' || table_name ||' to test;' from dba_tab_privs
where grantee='OAZ29';

--
grant ALTER on HR.EMPLOYEES to test;
grant DELETE on HR.EMPLOYEES to test;
grant INDEX on HR.EMPLOYEES to test;
grant INSERT on HR.EMPLOYEES to test;
grant SELECT on HR.EMPLOYEES to test;
grant UPDATE on HR.EMPLOYEES to test;
grant REFERENCES on HR.EMPLOYEES to test;
grant READ on HR.EMPLOYEES to test;
grant ON COMMIT REFRESH on HR.EMPLOYEES to test;
grant QUERY REWRITE on HR.EMPLOYEES to test;
grant DEBUG on HR.EMPLOYEES to test;
grant FLASHBACK on HR.EMPLOYEES to test;

grant UNLIMITED TABLESPACE to test;

--oaz29	UNLIMITED TABLESPACE	NO	NO	NO
select * from dba_sys_privs where grantee='OAZ29';

--oaz29	DBA	NO	NO	YES	NO	NO
--oaz29	CONNECT	NO	NO	YES	NO	NO
--oaz29	RESOURCE	NO	NO	YES	NO	NO
select * from dba_role_privs where grantee='OAZ29';
 
select * from dba_role_privs where grantee='DBA'; EXP_FULL_DATABASE

select * from dba_sys_privs where grantee in ('oaz29','DBA','RESOURCE','CONNECT');

grant select on sys.fga_log$ to oaz29;

select * from  dba_tab_privs
where grantee='OAZ29';

---ROLE PDB----

CREATE ROLE ROLE_oaz29 NOT IDENTIFIED;

alter role ROLE_oaz29 identified by oracle;

grant select any table, drop any table, insert any table, delete any table to role_oaz29;

grant all on sys.fga_log$ to role_oaz29;

grant role_oaz29 to oaz29;

grant role_oaz29 to c##oaz29;

---ROLE CDB----

CREATE ROLE c##ROLE_oaz29 NOT IDENTIFIED;

alter role c##ROLE_oaz29 identified by oracle;

grant select any table, drop any table, insert any table, delete any table to c##role_oaz29;

grant all on sys.fga_log$ to c##role_oaz29;


grant c##role_oaz29 to c##oaz29;

-- Vao PDB
grant c##role_oaz29 to oaz29;


 


