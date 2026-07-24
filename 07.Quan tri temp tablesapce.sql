--Quản trị Temp files trong Oracle Database
--Keyword: Recreate temp tablespace Oracle Database 10g, 11g, 12c, 19c
-- Temporary Tablespace Usage 
select * from v$tempfile;

select * from dba_temp_files;

-- Xac dinh session dang dung TEMP
SELECT A.inst_id,b.tablespace, 'ALTER SYSTEM KILL SESSION '''||a.sid||','||a.serial#||',@'||a.inst_id||''' IMMEDIATE;',ROUND(((b.blocks*p.value)/1024/1024),2)||'M' "SIZE",
a.sid||','||a.serial# SID_SERIAL,a.username,a.program
FROM sys.Gv_$session a,sys.Gv_$sort_usage b,sys.v_$parameter p
WHERE p.name = 'db_block_size' and a.inst_id=b.inst_id AND a.saddr = b.session_addr and b.tablespace like 'TEMP'
--AND A.USERNAME IS NOT NULL AND A.USERNAME not like 'SYS%'
ORDER BY b.tablespace, b.blocks;

select b.Total_MB,
       b.Total_MB - round(a.used_blocks*8/1024) Current_Free_MB,
       round(used_blocks*8/1024)                Current_Used_MB,
      round(max_used_blocks*8/1024)             Max_used_MB
from v$sort_segment a,
 (select round(sum(bytes)/1024/1024) Total_MB from dba_temp_files ) b;


col hash_value for a40
col tablespace for a10
col username for a15
set linesize 132 pagesize 1000
 
SELECT s.sid, s.username, u.tablespace, s.sql_hash_value||'/'||u.sqlhash hash_value, u.segtype, u.contents, u.blocks
FROM v$session s, v$tempseg_usage u
WHERE s.saddr=u.session_addr
order by u.blocks;

select s.inst_id,
   s.sid , s.serial# serial, 
   s.username, 
   s.osuser, 
   p.spid, 
   s.module,
   p.program, 
   sum (t.blocks) * tbs.block_size / 1024 / 1024 mb_used, 
   t.tablespace,
   count(*) nbr_statements
from 
   gv$sort_usage t, 
   gv$session s, 
   dba_tablespaces tbs, 
   gv$process p
where 
   t.session_addr = s.saddr
and 
   s.paddr = p.addr
and 
   t.tablespace = tbs.tablespace_name
group by 
    s.inst_id,
    s.sid, 
   s.serial#, 
   s.username, 
   s.osuser, 
   p.spid, 
   s.module,
   p.program, 
   tbs.block_size, 
   t.tablespace
order by MB_used desc;

--Tìm các object đang sử dụng temp

select tu.tablespace,tu.username,s.sid,s.serial#,s.inst_id from gv$tempseg_usage tu, gv$session s
where tu.session_addr=s.saddr;


--Tạo script kill các session đó:

select 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||',@'||s.inst_id||''' immediate;' from gv$tempseg_usage tu, gv$session s
where tu.session_addr=s.saddr and tu.tablespace='TEMP';

-- Create tempprary tablespace
CREATE SMALLFILE TEMPORARY TABLESPACE TEMP2      
TEMPFILE       '/u04/oracle/DBAViet/temp00.dbf'      SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
                 '/u04/oracle/DBAViet/temp01.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
                '/u04/oracle/DBAViet/temp02.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
              '/u04/oracle/DBAViet/temp03.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
            '/u04/oracle/DBAViet/temp04.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
             '/u04/oracle/DBAViet/temp05.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
             '/u04/oracle/DBAViet/temp06.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
                '/u04/oracle/DBAViet/temp07.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
               '/u04/oracle/DBAViet/temp08.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
              '/u04/oracle/DBAViet/temp09.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
               '/u04/oracle/DBAViet/temp10.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
                 '/u04/oracle/DBAViet/temp11.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
               '/u04/oracle/DBAViet/temp12.dbf'    SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
            '/u04/oracle/DBAViet/temp13.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
              '/u04/oracle/DBAViet/temp14.dbf'     SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M,
             '/u04/oracle/DBAViet/temp15 .dbf'    SIZE 512M AUTOEXTEND ON NEXT 150M MAXSIZE 1024M;

CREATE SMALLFILE TEMPORARY TABLESPACE TEMP2      
TEMPFILE       '+DATA'      SIZE 1G AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED;

alter database default temporary tablespace temp2;

drop tablespace temp including contents and datafiles;

select * from dba_temp_files order by file_name desc

-- Chuyển tablespaces sang temporary tablespace
ALTER TABLESPACE temp2 TEMPORARY;

-- Add tempfile file system
ALTER TABLESPACE temp_demo ADD TEMPFILE 'temp05.dbf' size 20480m autoextend on next 100M max size 10G;

ALTER TABLESPACE TEMP ADD TEMPFILE '+DATA' SIZE 1G AUTOEXTEND ON NEXT 100M
 MAXSIZE UNLIMITED;

-- Add tempfile trong ASM
-- Check đường dẫn lưu temp file
select * from dba_temp_files where tablespace_name='TEMP';

--Check dung luong diskgroup:Giả từ DATA còn dư
select * from v$asm_diskgroup;

-- Add tempfile: Tùy 1 hoặc 5 hoặc 10 file
alter tablespace TEMP1 add tempfile '+DATA' size 1G autoextend on next 100m;
alter tablespace TEMP1 add tempfile '+DATA' size 1G autoextend on next 100m;
alter tablespace TEMP1 add tempfile '+DATA' size 1G autoextend on next 100m;
alter tablespace TEMP1 add tempfile '+DATA' size 1G autoextend on next 100m;
alter tablespace TEMP1 add tempfile '+DATA' size 1G autoextend on next 100m;

alter tablespace TEMP add tempfile '/SID/oradata/data02/temp05.dbf' size 1800m reuse;

--RESIZE  TEMPFILE 
select * from dba_temp_files;

alter database tempfile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_temp_jngplfvb_.dbf' resize 10M

alter database tempfile '/SID/oradata/data02/temp12.dbf' autoextend on maxsize 1800M;

alter database tempfile '/u02/oracle/oradata/DBAViet/temp_02.dbf' resize 10240m

--+ Script resize mọi tempfile cả tablespace TEMP về 10MB
select 'alter database tempfile ''' || file_name || ''' resize 10M;' from dba_temp_files where tablespace_name='TEMP';

-- Drop tempfile
ALTER TABLESPACE temp_demo DROP TEMPFILE 'temp05.dbf';

-- Drop tablespace TEMP
drop tablespace temp including contents and datafiles;