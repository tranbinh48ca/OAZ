Quản lý database link trong Oracle Database
--1. CHECK
select * from dba_db_links;

--Check dblink
SQL> select * from dual@db1   // db1 là tên DBLink

--2. CREATE
--Public dblink trong RAC
CREATE PUBLIC DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION =
       (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.66)(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.88)(PORT = 1521))
  
      (LOAD_BALANCE = yes)
      (FAILOVER = yes)
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = BINHDB)
    )
  )';
  
  --Private dblink trong RAC
  CREATE  DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION =
       (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.66)(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.88)(PORT = 1521))
      (LOAD_BALANCE = yes)
      (FAILOVER = yes)
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = BINHDB)
    )
  )';

--Public dblink trong Single
CREATE PUBLIC DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION=
    (ADDRESS=
      (PROTOCOL=TCP)
      (HOST=10.38.31.187)
      (PORT=1521)
    )
    (CONNECT_DATA=
      (SERVICE_NAME=BINHDB)
    )
  )';

CREATE PUBLIC DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION=
    (ADDRESS=
      (PROTOCOL=TCP)
      (HOST=10.38.31.187)
      (PORT=1521)
    )
    (CONNECT_DATA=
      (SID=BINHDB1)
    )
  )';

--Private dblink trong Single
CREATE DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION=
    (ADDRESS=
      (PROTOCOL=TCP)
      (HOST=10.38.31.187)
      (PORT=1521)
    )
    (CONNECT_DATA=
      (SERVICE_NAME=BINHDB)
    )
  )';

CREATE DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY pwd1
 USING '(DESCRIPTION=
    (ADDRESS=
      (PROTOCOL=TCP)
      (HOST=10.38.31.187)
      (PORT=1521)
    )
    (CONNECT_DATA=
      (SID=BINHDB1)
    )
  )';


  --3.ALTER
  	• ALTER DATABASE LINK private_link 
  CONNECT TO hr IDENTIFIED BY hr_new_password;
	• ALTER PUBLIC DATABASE LINK public_link
  CONNECT TO scott IDENTIFIED BY scott_new_password;
  
  --4.Drop
  DROP [PUBLIC] DATABASE LINK dblink_name
  
  CREATE OR REPLACE PROCEDURE user1.cre_dbl
IS
    v_sql   LONG;
BEGIN
  EXECUTE IMMEDIATE 'drop DATABASE LINK link2';
    v_sql :=
        'CREATE DATABASE LINK link2
CONNECT TO user1
IDENTIFIED BY pwd1
USING '
        || ''''
        || '(DESCRIPTION=
    (FAILOVER=yes)
    (LOAD_BALANCE=yes)
    (ADDRESS_LIST=
      (ADDRESS= (PROTOCOL=TCP) (HOST=192.168.1.145) (PORT=1521))
   (ADDRESS= (PROTOCOL=TCP) (HOST=192.168.1.146) (PORT=1521))
    )
    (CONNECT_DATA=
      (SERVER=dedicated)
      (SERVICE_NAME=db2)
    )
  )'
        || '''';

    EXECUTE IMMEDIATE v_sql;
END;
/

--5.KILL LOCK DBLINK
 declare
 CURSOR c1
        IS
            SELECT   local_tran_id, state
              FROM   DBA_2PC_PENDING
              where (retry_time-fail_time)*24*60>1.5; --waiting for longer 4 min
    BEGIN
        /*FOR r1 IN c1
        LOOP

            dbms_output.put_line('1');
            EXECUTE IMMEDIATE 'rollback force '''
                     || r1.local_tran_id
                     || '''';
            commit;
        end loop;*/

        FOR r2 IN c1
        LOOP
            if r2.state in ('committed') then
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;
             elsif r2.state='prepared' then
                EXECUTE IMMEDIATE 'rollback force '''
                     || r2.local_tran_id
                     || '''';
                commit;
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;
             else
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;

             end if;
        end loop;
    END;

	
--Thủ tục tạo dblink bằng user khác
CREATE OR REPLACE PROCEDURE user1.cre_dbl
IS
    v_sql   LONG;
BEGIN
    v_sql :=
        'CREATE DATABASE LINK dblink1
 CONNECT TO user1
 IDENTIFIED BY paswd
 USING '
        || ''''
        || '(DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.1)(PORT = 1521))
    (ADDRESS = (PROTOCOL = TCP)(HOST = 192.168.1.2)(PORT = 1521))
      (LOAD_BALANCE = yes)
      (FAILOVER = yes)
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = db1)
    )
  )'
        || '''';

    EXECUTE IMMEDIATE v_sql;
END;
/

begin
user1.cre_dbl;
end;

drop procedure user1.cre_dbl;

---------

CREATE OR REPLACE PROCEDURE user1.drop_dbl
IS
BEGIN
    EXECUTE IMMEDIATE 'drop DATABASE LINK dblink1';
END;
/
begin
user1.drop_dbl;
end;

drop procedure user1.drop_dbl;