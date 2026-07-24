select * from dba_tablespaces; --Ctrl+Enter

select * from v$datafile;

SELECT  a.tablespace_name,100 - ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Usage",   ROUND 
(a.bytes_alloc / 1024 / 1024) "Size MB",   ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) "Free MB",
      (ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024)) "Used MB", ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Free", ROUND (maxbytes / 1048576)  "Max MB", 
       ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100) "%Used of Max"
  FROM (  SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
            FROM dba_data_files f
        GROUP BY tablespace_name) a,
       (  SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
 WHERE a.tablespace_name = b.tablespace_name(+) --and a.tablespace_name in ('DATA201505','DATA201506','IMPORT_TBS','INDX201505','INDX201506')
 order by "%Used of Max" desc;
 
select * from DBA_DATA_FILES;

-- Cach 1: OMF
SQL> alter session set container=pdb1;

--Session altered.
select * from v$parameter where name in ('db_create_file_dest','db_create_online_log_dest_1');

SQL> show parameter db_create;

--NAME                                 TYPE        VALUE
-------------------------------------- ----------- ------------------------------
--db_create_file_dest                  string      /u01/app/oracle/oradata
--db_create_online_log_dest_1          string      /u01/app/oracle/redolog

alter system set db_create_file_dest='/u01/app/oracle/oradata';

alter system set db_create_online_log_dest_1='/u01/app/oracle/oradata';

-- Boi den doan duoi va an F5
create tablespace DATA datafile size 1m autoextend on next 10m;

alter database datafile 70 autoextend off;

create tablespace DATA datafile size 1G autoextend on next 100m;
create tablespace indx datafile size 1m autoextend on next 10m;
create tablespace data2026 datafile size 1m autoextend on next 10m;
create tablespace indx2026 datafile  size 1m autoextend on next 10m;
create tablespace dump datafile  size 1m autoextend on next 10m;
create tablespace lob datafile  size 1m autoextend on next 10m;
create tablespace data_nghiepvu1 datafile  size 1m autoextend on next 10m;
create tablespace indx_nghiepvu1 datafile  size 1m autoextend on next 10m;
create tablespace data_log datafile  size 1m autoextend on next 10m;
create tablespace indx_log datafile  size 1m autoextend on next 10m;

--ASM
--create tablespace data_omf datafile '+DATA'  size 10m autoextend on next 100m;

-- Cach 2: Duong dan tuong minh (khong dung)

create tablespace data datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data01.dbf' size 10m autoextend on next 100m;
create tablespace indx datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/indx01.dbf' size 10m autoextend on next 100m;
create tablespace data2022 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data2022_01.dbf' size 10m autoextend on next 100m;
create tablespace indx2022 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/indx2022_01.dbf' size 10m autoextend on next 100m;
create tablespace data2023 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data2023_01.dbf' size 10m autoextend on next 100m;
create tablespace indx2023 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/indx2023_01.dbf' size 10m autoextend on next 100m;
create tablespace data2024 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data2024_01.dbf' size 10m autoextend on next 100m;
create tablespace indx2024 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/indx2024_01.dbf' size 10m autoextend on next 100m;
create tablespace dump datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/dump01.dbf' size 10m autoextend on next 100m;
create tablespace lob datafile  '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/lob01.dbf' size 10m autoextend on next 100m;
create tablespace data_nghiepvu1 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data_nghiepvu1_01.dbf' size 10m autoextend on next 100m;
create tablespace indx_nghiepvu1 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/indx_nghiepvu1_01.dbf' size 10m autoextend on next 100m;
create tablespace DATA2 datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data2_01.dbf' size 10m autoextend on next 100m;;

alter tablespace data add datafile '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/data02.dbf' size 10m autoextend on next 100m;

ALTER TABLESPACE data ADD DATAFILE;

drop tablespace data3;

select * from dba_tablespaces;

select * from dba_data_files where file_name like '%data%';

--TEST BIGFILE
create bigfile tablespace big_ts datafile size 10M;

--[Error] Execution (94: 1): ORA-32771: cannot add file to bigfile tablespace
alter tablespace big_ts add datafile;




