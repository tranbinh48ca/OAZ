--Quản trị tablespace Oracle Database
--Các câu lệnh thường sử dụng để quản trị tablespace:

--1. CHECK
--Hiển thị dung lượng trống của tablespace
SELECT  a.tablespace_name,100 - ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Usage",
    ROUND (a.bytes_alloc / 1024 / 1024) "Size MB",
    ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) "Used MB",
    ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) "Free MB",
    --ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Free",
    ROUND (maxbytes / 1048576)  "Max MB",
    round(maxbytes/1048576-(ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024)),0) "Free_MB_Max",
    ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100) "%Used of Max"
    FROM (SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
            FROM dba_data_files f
            GROUP BY tablespace_name) a,
        (SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
 WHERE a.tablespace_name = b.tablespace_name(+)  
 --and  (a.tablespace_name in ('TEMP1','DATA201511','DATA2016','INDX','INDX2016'))
 --order by "%Used of Max" desc;
order by tablespace_name;


 --Dung luong của từng data files
SELECT  FILE_NAME, BLOCKS, round(bytes/1024/1024,2) "MB", TABLESPACE_NAME
FROM DBA_DATA_FILES
WHERE file_name like '%data2026%'
order by tablespace_name;

--Dung lượng DB
SELECT ROUND(SUM(BYTES)/1024/1024,2) "MB" FROM DBA_DATA_FILES;

--Dung lượng schema
select owner,round(sum(bytes/1024/1024),2) "MB" from dba_segments
group by owner order by MB desc;

--Dung lượng schema.segment
select owner, segment_name,round(sum(bytes/1024/1024),2) "MB" from dba_segments
group by owner, segment_name
order by "MB" desc;

-- Dung luong tablespace READ ONLY: 7,15GB
select sum(bytes)/1024/1024/1024 "GB" from dba_data_files;

--2,92TB
select sum(bytes)/1024/1024/1024 "GB" from dba_data_files where tablespace_name in
(select tablespace_name from dba_tablespaces where 
status='READ ONLY');

-- Check duong dan cua datafile trong tablesapce
select * from dba_data_files where tablespace_name='USERS';

--Check trạng thái của datafile, tablespace
--Offline
select file_name,tablespace_name,online_status from dba_data_files where tablespace_name='DATA201008'

-- Read Only (co the online hoac offline), Online
select tablespace_name, status from dba_tablespaces where
--tablespace_name like '%201208%' and
status='OFFLINE'
order by tablespace_name;

-- Thống kê dung lượng tăng theo tháng
select to_char(creation_time,'yyyy/mm'), round(sum(bytes)/1024/1024/1024) "GB" from v$datafile 
group by to_char(creation_time,'yyyy/mm')
order by 1;

(tháng 2021/07 tạo 16.3TB, tháng 08/2021 tạo 10.2TB, tháng 09/2021 dến hôm  nay là 09/09/2021 tạo 3.6TB, cần tạo khoảng > 7TB nữa để duy trì hết tháng)

--2. CREATE TABLESPACE

CREATE TABLESPACE data201102 DATAFILE '/u02/oradata/ORCL/datafile/DATA201102_01.DBF' SIZE 6G;
CREATE TABLESPACE data201102 DATAFILE '/u02/oradata/ORCL/datafile/DATA201102_01.DBF' SIZE 100M;
'/u02/oradata/ORCL/datafile/DATA201103_01.DBF' SIZE 50M AUTOEXTEND ON NEXT 100M MAXSIZE 2048M,
'/u02/oradata/ORCL/datafile/DATA201103_02.DBF' SIZE 50M AUTOEXTEND ON NEXT 100M MAXSIZE 2048M,
'/u02/oradata/ORCL/datafile/DATA201103_03.DBF' SIZE 50M AUTOEXTEND ON NEXT 100M MAXSIZE 2048M;

CREATE TABLESPACE data201103 DATAFILE

CREATE TABLESPACE /*FileSystem*/ DATA202304 datafile  size 10M autoextend on next 10M ;

CREATE TABLESPACE app_ts;

CREATE TABLESPACE app_ts2 DATAFILE SIZE 150M;

CREATE TABLESPACE /*ASM*/ DATA202304   datafile '+DATA' size 1G autoextend on next 100M ;
   
--3.ALTER TABLESPACE

--ADD DATAIFILE ASM
--+ Check dung luong diskgroup trong
select * from gv$asm_diskgroup;

--+ Check duong dan chua datafile
 
select * from dba_data_files where tablespace_name='DUMP_DATA';

--+ Add datafile trong ASM:
    alter tablespace DATA_ add datafile '+DATA' size 1G autoextend on next 200M maxsize 10G;
    ALTER TABLESPACE DATA201206 ADD datafile size 512M autoextend on next 200M maxsize 8g

--ADD DATAIFILE FILESYSTEM
    select * from dba_data_files where tablespace_name='DATA2022';
    
    
    alter tablespace app_ts add datafile size 1G autoextend on next 100m;

alter tablespace app_ts add datafile size 10m autoextend on next 10m;

alter tablespace app_ts add datafile size 8G autoextend off;

--+ Add datafile với file system
ALTER TABLESPACE DATA2022 ADD DATAFILE SIZE 1M AUTOEXTEND ON NEXT 10M; 

select * from dba_data_files where tablespace_name='DATA2022';

select * from v$datafile where ts# in (select ts# from v$tablespace where name='DATA2022');

select * from v$tablespace;

select * from dba_tablespaces;

ALTER TABLESPACE DUMP_DATA ADD DATAFILE '/u02/oracle/oradata/datafile/DUMP_DATA_04.dbf' SIZE 2G AUTOEXTEND ON NEXT 200M MAXSIZE 10G;

ALTER TABLESPACE DUMP_DATA ADD DATAFILE '/u02/oracle/oradata/datafile/DUMP_DATA_04.dbf' SIZE 2G AUTOEXTEND ON NEXT 200M; --unlimited 

ALTER TABLESPACE lmtemp ADD TEMPFILE '/u02/oracle/data/lmtemp02.dbf' SIZE 18M REUSE;  
   
-- Drop datafile
ALTER TABLESPACE DATA201302 DROP DATAFILE '/u03/oradata/ORCL/DATA201302_0004.dbf';
   
--  Rename datafile
ALTER TABLESPACE users
RENAME DATAFILE '/u02/oracle/ORCL/user1.dbf',
                '/u02/oracle/ORCL/user2.dbf'
             TO '/u02/oracle/ORCL/users01.dbf',
                '/u02/oracle/ORCL/users02.dbf';
   
-- ONLINE, OFFLINE
ALTER TABLESPACE APP_TS ONLINE;

ALTER TABLESPACE APP_TS OFFLINE [force | normal];
   
-- Read write, read only:
ALTER TABLESPACE DATA201101 READ WRITE;
ALTER TABLESPACE DATA201101 READ ONLY;

-- Renaming Tablespaces
ALTER TABLESPACE my_space RENAME TO your_space; 

--4.DROP TABLESPACE
DROP TABLESPACE APP_TS INCLUDING CONTENTS AND DATAFILES;