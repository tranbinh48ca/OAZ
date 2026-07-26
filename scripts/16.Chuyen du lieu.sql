--0. Check
 --OS:      
    ps -ef |grep expdp
    
    ps -ef |grep impdp
        
--DB    
    -- job data pump: SYS	SYS_EXPORT_FULL_01	EXPORT	FULL	EXECUTING	8	1	10
    select * from DBA_DATAPUMP_JOBS;
    
    -- session
    select * from dba_datapump_sessions;
        
    -- longops
    col table_name format a30
        
    select substr(sql_text, instr(sql_text,'"')+1, 
                   instr(sql_text,'"', 1, 2)-instr(sql_text,'"')-1) 
              table_name, 
           rows_processed, 
           round((sysdate
                  - to_date(first_load_time,'yyyy-mm-dd hh24:mi:ss'))
                 *24*60, 1) minutes, 
           trunc(rows_processed / 
                    ((sysdate-to_date(first_load_time,'yyyy-mm-dd hh24:mi:ss'))
                 *24*60)) rows_per_min 
    from 
       v$sqlarea 
    where 
      --upper(sql_text) like 'INSERT % INTO "%'       and 
      command_type = 2 
      and 
      open_versions > 0;
      
    select 
       sid, 
       serial#
    from 
       v$session s, 
       dba_datapump_sessions d
    where 
       s.saddr = d.saddr;
       
    select 
       sid, 
       serial#, 
       sofar, 
       totalwork 
    from    v$session_longops;
    
--1. Tao thu muc
--Tren OS tao:
$ mkdir /home/oracle/oaz

--PDB
sqlplus / as sysdba
alter session set container=pdb1;

select * from dba_directories;
cd 
desc dba_directories;
col DIRECTORY_NAME format a30;
col directory_path format a70;
set linesize 200;

select DIRECTORY_NAME, directory_path from dba_directories;

 -- drop directory oaz;
 
create directory oaz as '/home/oracle/oaz';

select DIRECTORY_NAME, directory_path from dba_directories where directory_name='OAZ';

--2.Export

-- 2.1.Export 1 schema (tab18) cua pdb1
alter session set container=pdb1;
create directory oaz as '/home/oracle/oaz';

create user ora29 identified by oracle;
grant connect, resource, dba to ora29;

create table ora29.tab_objects as select * from dba_objects ;

--73,721
select * from ora29.tab_objects;
 

--expdp \"sys/oracle@service as sysdba\"

expdp "' sys/oracle@pdb1 as sysdba'" DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=oaz29.log SCHEMAS=ora29 COMPRESSION=ALL CONTENT=ALL  PARALLEL=4;

-- 2.2.Export full DB
sqlplus / as sysdba
create directory oaz as '/home/oracle/oaz';
expdp "' / as sysdba'" DIRECTORY=oaz DUMPFILE=orcl%U.dmp logfile=orcl.log COMPRESSION=ALL CONTENT=ALL FULL=y  PARALLEL=8;

-- Go mat khau: oracle

--1.8GB
select sum(bytes)/1024/1024/1024 "GB" from dba_data_files;

. . exported "ora29"."TAB_OBJECTS"                   6.679 KB       9 rows


--3.Xoa bang tab_objects di
--3.1.Truong hop drop KHONG PURGE
--oaz23	BIN$BliaFOlBUzTgY4C2qMDthQ==$0	TAB_OBJECTS	DROP	TABLE	USERS	2023-09-27:20:56:44	2023-09-27:20:59:37	7364590		YES	YES	80995	80995	80995	1536
--Check tu tablespace: oaz23	BIN$/7+dIk6yGvXgU4C2qMBFow==$0	TABLE	12582912	65536	1048576	27	2147483645

--73,721
select * from ora29.TAB_OBJECTS;

drop table ora29.TAB_OBJECTS purge;

select * from ora29.TAB_OBJECTS;

select * from dba_recyclebin order by droptime desc;

select * from "OAZ29"."BIN$VHUXSwTEF8fgY4C2qMDUMQ==$0";

--[Error] Execution (119: 1): ORA-38305: object not in RECYCLE BIN
flashback table ora29.TAB_OBJECTS   to  before drop;

select * from ora29.TAB_OBJECTS;

-- 3.2.Truong hop drop PURGE
drop table ora29.TAB_OBJECTS purge;

select * from ora29.TAB_OBJECTS;

--Kiem tra tablespace: ko co

select * from dba_recyclebin order by droptime desc;

--[Error] Execution (3: 1): ORA-38305: object not in RECYCLE BIN
flashback table ora29.TAB_OBJECTS   to  before drop;

--4.Import lai
--impdp "' / as sysdba'"  DIRECTORY=binhdir DUMPFILE=orcl%U.dmp TABLES=C##BINHTV.TAB_OBJECTS;
--ORA-39002: invalid operation
--ORA-39070: Unable to open the log file.
--ORA-39087: directory name OAZ is invalid
impdp  ora29/oracle@pdb1   DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=impdp.TAB_OBJECTS.log TABLES=ora29.TAB_OBJECTS  parallel=4;

impdp  "' sys/oracle@pdb1 as sysdba '"   DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=impdp.TAB_OBJECTS.log TABLES=oaz29.TAB_OBJECTS  parallel=4;

--73,721
select * from  ora29.TAB_OBJECTS;

impdp  ora29/oracle@pdb1   DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=impdp.TAB_OBJECTS.log TABLES=oaz29.bang_to REMAP_TABLE=ora29.bang_to:tab_objects_new parallel=4;

impdp "' sys/oracle@pdb1 as sysdba '" directory=oaz dumpfile=ora29%u.dmp logfile=impdp.tabl_objects.log tables=ora29.tab_objects parallel=4; 

 impdp "' sys/oracle@pdb1 as sysdba '" directory=oaz dumpfile=ora29%u.dmp logfile=impdp.tabl_objects.log tables=ora29.tab_objects  REMAP_TABLE=oaz23.tab_objects:tab_objects_new parallel=4;

select * from  ora29.tab_objects_new;

--select * from oaz23.tab_objects;

-- Test them
expdp "'/ as sysdba'" DIRECTORY=oaz   ESTIMATE_ONLY=y full=y COMPRESSION=ALL


--Truncate va import lai
--+ 73,721
select * from  ora29.TAB_OBJECTS;

--+ Truncate:
truncate table   ora29.TAB_OBJECTS

--+ 0 row
select * from  ora29.TAB_OBJECTS;

--+Import
impdp  ora29/oracle@pdb1   DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=impdp.TAB_OBJECTS.log TABLES=ora29.TAB_OBJECTS  parallel=4 TABLE_EXISTS_ACTION=TRUNCATE;

--+Check lai: 73,721
select * from  ora29.TAB_OBJECTS;

--5.Drop bang PURGE dung recover table
drop table ora29.tab_objects purge; -- hoac truncate table oaz23.tab_objects

recover table ora29.tab_objects;

rman TARGET SYS/oracle@pdb1


--Khong chay duoc
MAN> recover table ora29.tab_objects until time 'sysdate - 5/24*60' auxiliary destination '/data/dump/aux';

Starting recover at 13-JUL-26
using target database control file instead of recovery catalog
RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of recover command at 07/13/2026 21:59:15
RMAN-20207: UNTIL TIME or RECOVERY WINDOW is before RESETLOGS time

RMAN> recover table ora29.tab_objects until time 'sysdate - 1/24' auxiliary destination '/data/dump/aux';

Starting recover at 13-JUL-26
RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of recover command at 07/13/2026 21:59:46
RMAN-06617: UNTIL TIME (13-JUL-26) is ahead of last NEXT TIME in archived logs (08-JUL-26)


RMAN> recover table oaz29.tab_objects until time "to_date('13/07/2026 20:01:00','dd/mm/yyyy hh24:mi:ss')" auxiliary destination '/data/dump/aux';

Starting recover at 13-JUL-26
RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of recover command at 07/13/2026 22:05:47
RMAN-06617: UNTIL TIME (13-JUL-26) is ahead of last NEXT TIME in archived logs (08-JUL-26)
RMAN> recover table ora29.tab_objects until time 'sysdate - 1/24' auxiliary destination '/data/dump/aux';

recover table ora29.tab_objects until time 'sysdate - 2/24' auxiliary destination '/data/dump/aux';

 recover table ora29.tab_objects until time 'sysdate - 7' auxiliary destination '/data/dump/aux';

 recover table ora29.tab_objects until time 'sysdate - 1' auxiliary destination '/data/dump/aux';
 
 --Import lai
  impdp  ora29/oracle@pdb1   DIRECTORY=oaz DUMPFILE=oaz29%U.dmp logfile=impdp.TAB_OBJECTS.log TABLES=ora29.TAB_OBJECTS  parallel=4 TABLE_EXISTS_ACTION=TRUNCATE;
  
  --73,721
  select * from ora29.TAB_OBJECTS;
