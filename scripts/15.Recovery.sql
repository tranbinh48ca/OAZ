--15.1.KHOI PHUC 1 DATAFILE CUA TABLESPACE USERS BI MAT
    --15.1.1 XOA 1 DATAFILE CUA PDB
    --15.1.2.XOA 1 DATAFILE  USERS CUA ORCL (CDB)
--15.2.KHOI PHUC DATAFILE SYSTEM CUA PDB1 

--CHI TIET:
--15.1.KHOI PHUC 1 DATAFILE CUA TABLESPACE USERS BI MAT
--15.1.1 XOA 1 DATAFILE CUA PDB
--/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_nmm4hq74_.dbf	12	USERS
select * from dba_data_files where tablespace_name='USERS' order by tablespace_name;


ls -lt /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_nmm4hq74_.dbf;

-- Doi ten file thanh xxx
rm /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_nmm4hq74_.dbf;
ls -lt /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_n91dqrp0_.dbf;

create table oaz28.tab2(id number, name varchar2(100)) tablespace users;

grant unlimited tablespace to oaz28;

select * from oaz28.tab2;

declare
    n number :=0;
begin
    for n in 1 .. 10000 
    loop
        insert into oaz28.tab2 values(n, 'Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;


ORA-01116: error in opening database file 12
ORA-01110: data file 12: '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_nmm4hq74_.dbf'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
ORA-06512: at line 6

--85,424
select * from oaz28.tab2;

declare
    n number :=0;
begin
    for n in 1 .. 100000 
    loop
        insert into oaz28.tab2 values(n, 'Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;

--Recovery
rman target=sys@pdb1;

RUN {
  SQL 'ALTER DATABASE DATAFILE 12 OFFLINE';
  RESTORE DATAFILE 12;
  RECOVER DATAFILE 12;
  SQL 'ALTER DATABASE DATAFILE 12 ONLINE';
}

declare
    n number :=0;
begin
    for n in 1 .. 10000 
    loop
        insert into oaz28.tab2 values(n, 'Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;

--10,000
select * from oaz28.tab2;

-- 15.1.2.XOA 1 DATAFILE  USERS CUA ORCL (CDB)
select * from dba_data_files order by tablespace_name;

--/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_n91fckvz_.dbf	7	USERS

ls -lt /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_n91fckvz_.dbf;

-- Xoa hoc doi ten file thanh xxx
rm -rf /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_n91fckvz_.dbf;
ls -lt /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_n91fckvz_.dbf;

create user c##oaz28 identified by oracle;

grant connect, resource to c##oaz28 container=all;

grant unlimited tablespace to c##oaz28 container=all;

create table c##oaz28.tab2(id number, name varchar2(100)) tablespace users;

declare
    n number :=0;
begin
    for n in 1 .. 10000 
    loop
        insert into c##oaz28.tab2 values(n, 'CDB_Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;

ORA-01116: error in opening database file 7
ORA-01110: data file 7: '/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_n91fckvz_.dbf'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
ORA-06512: at line 6

--0
select * from c##oaz28.tab2;

--Recovery
rman target /;
RMAN > list backup of datafile 7;

RUN {
  SQL 'ALTER DATABASE DATAFILE 7 OFFLINE';
  RESTORE DATAFILE 7;
  RECOVER DATAFILE 7;
  SQL 'ALTER DATABASE DATAFILE 7 ONLINE';
}

declare
    n number :=0;
begin
    for n in 1 .. 1000 
    loop
        insert into c##oaz28.tab2 values(n, 'CDB_Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;

--1,000
select * from c##oaz28.tab2;

--
--create table oaz28.tab17(id number, name varchar2(100)) tablespace system;
--
--grant unlimited tablespace to oaz28;
--
--
--declare
--    n number :=0;
--begin
--    for n in 1 .. 10000 
--    loop
--        insert into test.tab7 values(n, 'Binh ' || n);
--        commit; 
--        --n := n+1;
--    end loop;
--end;
--

-- Xoa file va restart DB:
select * from dba_data_files order by tablespace_name;

/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf	7	USERS

ls -la /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf;

rm -rf /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf;

ls -la /u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf;

declare
    n number :=0;
begin
    for n in 1 .. 100000 
    loop
        insert into c##oaz28.tab2 values(n, 'CDB_Binh ' || n);
        commit; 
        --n := n+1;
    end loop;
end;

ORA-01565: error in identifying file '/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
ORA-06512: at line 6

--Alert
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_21640.trc:
ORA-01110: data file 7: '/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf'
ORA-01565: error in identifying file '/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_nmlxxpd3_.dbf'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7

SQL> shutdown immediate;

--PDB1(3):ALTER PLUGGABLE DATABASE  OPEN 
--PDB1(3):Autotune of undo retention is turned on. 
--2022-12-16T21:13:23.023153+07:00
--Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_dbw0_13008.trc:
--ORA-01157: cannot identify/lock data file 48 - see DBWR trace file
--ORA-01110: data file 48: '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_koqrktbs_.dbf'
--ORA-27037: unable to obtain file status
--Linux-x86_64 Error: 2: No such file or directory
--Additional information: 7
--2022-12-16T21:13:23.032919+07:00
--Pdb PDB1 hit error 1113 during open read write (1) and will be closed.

SQL> Shutdown abort;

--Database mounted.
--ORA-01157: cannot identify/lock data file 7 - see DBWR trace file
--ORA-01110: data file 7:
--'/u01/app/oracle/oradata/ORCL/datafile/o1_mf_users_lb5r05l2_.dbf'
SQL> startup;
 
SQL> show pdbs;

    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
---------- ------------------------------ ---------- ----------
         2 PDB$SEED                       MOUNTED  NO
         3 PDB1                           MOUNTED --> Binh thuong la READ WRITE


RUN {
  SQL 'ALTER DATABASE DATAFILE 7 OFFLINE';
  RESTORE DATAFILE 7;
  RECOVER DATAFILE 7;
  SQL 'ALTER DATABASE DATAFILE 7 ONLINE';
}
====
--SQL> alter session set container=pdb1;
--
--SQL> startup
--ORA-65368: unable to open the pluggable database due to errors during recovery
--ORA-01110: data file 48:
--'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_us
--ers_koqrktbs_.dbf'
--ORA-01157: cannot identify/lock data file 48 - see DBWR trace file
--ORA-01110: data file 48:
--'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_us
--ers_koqrktbs_.dbf'
--ORA-01113: file 83 needs media recovery
--ORA-01110: data file 83:
--'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_da
--ta_kr9ng663_.dbf'
--
--[oracle@linux7 ~]$ rman target /
--
--RMAN> list backup of datafile 48;
-- 48   0  Incr 3925611    16-DEC-22              NO    /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_koqrktbs_.dbf
--
--
--[oracle@linux7 ~]$ ls -la /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_k2ysofg0_.dbf
--ls: cannot access /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_users_k2ysofg0_.dbf: No such file or directory
--		 
--rman target=sys@pdb1; 
--
---- mat khau oracle
--		 
--RUN {
--  ALTER DATABASE DATAFILE 48,83 OFFLINE;
--  RESTORE DATAFILE 48,83;
--  RECOVER DATAFILE 48,83;
--  ALTER DATABASE DATAFILE 48,83 ONLINE;
--}
--
--RMAN> backup database plus archivelog ;  
--
--SQL> show pdbs;
--
--    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
------------ ------------------------------ ---------- ----------
--         2 PDB$SEED                       READ ONLY  NO
--         3 PDB1                           MOUNTED
--SQL> alter pluggable database pdb1 open;
--
--Pluggable database altered.
--
--SQL> show pdbs;
--
--    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
------------ ------------------------------ ---------- ----------
--         2 PDB$SEED                       READ ONLY  NO
--         3 PDB1                           READ WRITE NO
--
--SQL> alter session set container=pdb1;
--
--Session altered.
--
--SQL> startup;
--ORA-65019: pluggable database PDB1 already open

/**************** 15.2.KHOI PHUC DATAFILE SYSTEM CUA PDB1/CDB1 ****************/
--/u01/app/oracle/oradata/ORCL/datafile/o1_mf_system_jngnlyw0_.dbf	1	SYSTEM

--/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf	9	SYSTEM
--PDB
select * from dba_data_files where tablespace_name='SYSTEM';

select * from v$datafile;

--PDB
mv /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf  /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf.xxx;

ls -la /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf;

(hoac echo 1 >> /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf)

ls -la /u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf

--CDB
--rm -rf /u01/app/oracle/oradata/ORCL/datafile/o1_mf_system_jngnlyw0_.dbf
ls -la /u01/app/oracle/oradata/ORCL/datafile/o1_mf_system_jngnlyw0_.dbf
alter

SQL> show pdbs;

    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
---------- ------------------------------ ---------- ----------
         2 PDB$SEED                       READ ONLY  NO
         3 PDB1                           READ WRITE NO
SQL> alter pluggable database pdb1 close;

Pluggable database altered.

--Alert log bao loi:
2026-03-25T21:26:18.841592+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_5631.trc:
ORA-01110: data file 9: '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf'
ORA-01565: error in identifying file '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_system_nmm4hq60_.dbf'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
Checker run found 1 new persistent data failures

SQL> alter pluggable database pdb1 open;

(Tuong duong: 
SQL> alter session set container=pdb1;
SQL> startup
)

ERROR at line 1:
ORA-65368: unable to open the pluggable database due to errors during recovery
ORA-01110: data file 9:
'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_sy
stem_nmm4hq60_.dbf'
ORA-01157: cannot identify/lock data file 9 - see DBWR trace file
ORA-01110: data file 9:
'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_sy
stem_nmm4hq60_.dbf'
ORA-01113: file 83 needs media recovery
ORA-01110: data file 83:
'/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_bi
g_ts_nr1f227p_.dbf'


SQL > alter system switch logfile;
SQL > alter system checkpoint;


--/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_data_kr9ng663_.dbf	83	DATA

select * from dba_data_files  where file_id=9;


$ rman target=sys@pdb1;

-- Go mat khau oracle
		 
RMAN>  
RUN {
  ALTER DATABASE DATAFILE 9 OFFLINE;
  RESTORE DATAFILE 9;
  RECOVER DATAFILE 9;
  ALTER DATABASE DATAFILE 9 ONLINE;
}

RMAN> startup
--SQL>  alter pluggable database pdb1 open;

SQL> show pdbs;


    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
---------- ------------------------------ ---------- ----------
         2 PDB$SEED                       READ ONLY  NO
         3 PDB1                           READ WRITE NO

select * from v$datafile where file#=9

--RMAN > backup database plus archivelog ; 

--Backup 1 ban full cho an toan:
$ /home/oracle/backup/level0.sh 

--Control autobackup written to DISK device

handle '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-01'
handle '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-02'

/***** 15.3.KHOI PHUC CONTROL FILE TU BACKUP *****/
-- 15.3.1.MAT 2/3 CONTROL FILE
--rman> backup database plus archivelog;

--RMAN> backup current controlfile;

/home/oracle/backup/level0.sh 
--piece handle=/u01/app/oracle/fast_recovery_area/ORCL/backupset/2026_03_25/o1_mf_ncnnf_TAG20260325T213442_nw7wn3n1_.bkp tag=TAG20260325T213442 comment=NONE

--Starting Control File and SPFILE Autobackup at 25-MAR-26
piece handle=/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-03 comment=NONE

SQL> show parameter control;      

/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl, /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl, /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl
                                                 
--cp /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl  /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl;
--Control autobackup written to DISK device
--handle '/home/oracle/backup/level1/auto_dbaviet_ctlc-1611489315-20230522-01'

rm  -rf /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
rm -rf  /u01/app/oracle/fast_recovery_area/ORCL/controlfile/exit.ctl;

ls /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
ls /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl;

[oracle@linux7 logs]$ sqlplus / as sysdba

SQL> alter system checkpoint;

SQL> alter system switch logfile;

-- Neu khong loi ben duoi thi shutdown

SQL> 
SQL> shutdown immediate;

2026-03-25T21:37:25.988384+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_6381.trc:
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
2026-03-25T21:37:26.224772+07:00

ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3


SQL> shutdown abort;
ORACLE instance shut down.

SQL> startup
ORACLE instance started.

Total System Global Area 1.0737E+10 bytes
Fixed Size                 12688456 bytes
Variable Size            1744830464 bytes
Database Buffers         8959033344 bytes
Redo Buffers               20865024 bytes
ORA-00205: error in identifying control file, check alert log for more info 

2025-12-10T21:06:54.100963+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_23846.trc:
ORA-00202: control file: '/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory

-- Con lai:
ls -la /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl

--Bo qua: mv /u01/app/oracle/oradata/ORCL/controlfile/control03.ctl /u01/app/oracle/oradata/ORCL/controlfile/control03.ctl.xxx

cp /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
cp /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl;

[oracle@linux7 ~]$ ls -la /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
-rw-r----- 1 oracle oinstall 18759680 Sep 25 22:03 /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl
[oracle@linux7 ~]$ ls -la /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl;
-rw-r----- 1 oracle oinstall 18759680 Sep 25 22:03 /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl

SQL> alter database mount;

SQL> alter database open;

-- 15.3.2.MAT 3/3 CONTROL FILE
SQL> show parameter control;      
                                                 
--control_files  /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl,/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl,/u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl

handle '/home/oracle/backup/level0//home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20251210-03'

rm  -rf /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
rm -rf  /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl;
rm -rf /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl;

ls -la /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl;
ls -la  /u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl;
ls -la /u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl;


SQL> alter system checkpoint;
SQL> alter system switch logfile;

2026-03-25T21:43:51.949588+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_arc1_6771.trc:
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
2026-03-25T21:43:51.982682+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_7130.trc:
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3
2026-03-25T21:43:52.129884+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_7130.trc:
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3


SQL> shutdown immediate;
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3

SQL> shutdown abort;
ORACLE instance shut down.

SQL> startup

Total System Global Area 1.0737E+10 bytes
Fixed Size                 12688456 bytes
Variable Size            1744830464 bytes
Database Buffers         8959033344 bytes
Redo Buffers               20865024 bytes
ORA-00205: error in identifying control file, check alert log for more info

2025-12-10T21:13:38.742386+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_24595.trc:
ORA-00202: control file: '/u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
ORA-00210: cannot open the specified control file
ORA-00202: control file: '/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory

[oracle@linux7 datafile]$ rman target /

--1/Tim trong ALERT LOG:
--2026-03-25T21:33:02.961404+07:00
--Control autobackup written to DISK device
--
--handle '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-02'
--
--2026-03-25T21:34:44.980270+07:00
--Control autobackup written to DISK device
--
--handle '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-03'

-- 2/Tim trong log backup dinh ky:
--Starting Control File and SPFILE Autobackup at 2025-08-04 20:48:01
--piece handle=/home/oracle/backup/level0//home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20251210-03 comment=N
--ONE
--Finished Control File and SPFILE Autobackup at 2025-08-04 20:48:02
RMAN> restore controlfile from  '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-03';

(hoac restore controlfile from autobackup;

Starting restore at 10-DEC-25
using channel ORA_DISK_1

channel ORA_DISK_1: restoring control file
channel ORA_DISK_1: restore complete, elapsed time: 00:00:01
output file name=/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl
output file name=/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl
output file name=/u01/app/oracle/fast_recovery_area/ORCL/controlfile/control03.ctl
Finished restore at 10-DEC-25


RMAN> alter database mount;

RMAN> alter database open;

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of sql statement command at 12/10/2025 21:16:42
ORA-01589: must use RESETLOGS or NORESETLOGS option for database open


RMAN> alter database open NORESETLOGS;

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of sql statement command at 12/10/2025 21:17:05
ORA-01610: recovery using the BACKUP CONTROLFILE option must be done

RMAN>  alter database open RESETLOGS;

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of sql statement command at 12/10/2025 21:17:10
ORA-01194: file 1 needs more recovery to be consistent
ORA-01110: data file 1: '/u01/app/oracle/oradata/ORCL/datafile/o1_mf_system_n91g74s8_.dbf'

2025-12-10T21:17:18.938694+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_24821.trc:
ORA-01110: data file 66: '/u01/app/oracle/oradata/ORCL/CC5C01A97A924B63E05380BDA8C055CE/datafile/o1_mf_indx_log_nlvcclvx_.dbf'
Checker run found 6 new persistent data failures

--RMAN> restore database;
RMAN> recover database;
RMAN> alter database open  NORESETLOGS;

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of sql statement command at 12/10/2025 21:18:22
ORA-01588: must use RESETLOGS option for database open

SQL> alter database open resetlogs;

--38
select * from v$archived_log
where next_time >= trunc(sysdate) and completion_time >sysdate-1
order by sequence# ;

SQL> show pdbs;

    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
---------- ------------------------------ ---------- ----------
         2 PDB$SEED                       READ ONLY  NO
         3 PDB1                           READ WRITE NO

select * from v$archived_log 
--where name like '%o1_mf_1_1_lk39w1hn_%'
order by resetlogs_time;

select * from v$log;

select * from v$logfile;

-- Backup full
/home/oracle/backup/level0.sh 

--Control autobackup written to DISK device
--handle '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06'

/***************************************** 15.4.MAT REDOLOG *************************************************/
-- 15.4.1.MAT 1 MEMBER cua group INACTIVE hoac ACTIVE (CURRENT khong duoc xoa)
--1	1	1	209715200	512	2	YES	INACTIVE	5604185	3/25/2026 9:50:56 PM	5605957	3/25/2026 9:54:23 PM	0
--2	1	2	209715200	512	2	YES	INACTIVE	5605957	3/25/2026 9:54:23 PM	5605965	3/25/2026 9:54:23 PM	0
--3	1	3	209715200	512	2	NO	CURRENT	5605965	3/25/2026 9:54:23 PM	18446744073709551615		0    0
select * from v$log;

--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm4nrc4_.log	NO	0
--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nmm4nrx0_.log	NO	0
select * from v$logfile order by 1;

alter system switch logfile;

select * from v$log;

-- Doi ten, 1 member group 2 inactive
mv /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log.xxx;

--2 lan
alter system switch logfile;

2026-03-25T22:10:47.238956+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_9144.trc:
ORA-00313: open failed for members of log group 2 of thread 1
ORA-00312: online log 2 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
Checker run found 1 new persistent data failures

select * from v$log;

select * from v$logfile;

alter system switch logfile;

2025-08-04T21:25:13.508507+07:00
2025-12-10T21:28:32.887275+07:00
Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_arc0_24787.trc:
ORA-00313: open failed for members of log group 2 of thread 1
ORA-00312: online log 2 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log'
ORA-27041: unable to open file
Linux-x86_64 Error: 2: No such file or directory
Additional information: 3

$ ls -la /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log

select * from v$logfile order by group#;

alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log';

--	ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log	NO	0
select * from v$logfile order by 1;

--alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_jngnoq26_.log';

--3 lan: ko co loi
alter system switch logfile;

select * from v$logfile order by group#;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log'   TO GROUP 2;

--3 lan: ko co loi
alter system switch logfile;

--Dam bao group 2 co file redo02b.
select * from v$logfile order by group#;

--Backup controlfile written to trace file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_ora_15709.trc

--1		ONLINE	/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/o1_mf_1_jngnotg1_.log
--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_n91m48wo_.log
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_n91m4901_.log
--3		ONLINE	/u01/app/oracle/oradata/1ORCL/onlinelog/redo03b.log
select * from v$logfile order by group#;

select * from v$log;

alter system switch logfile;

--15.4.2.MAT TOAN BO GROUP CURRENT

--1	1	13	209715200	512	2	YES	INACTIVE	5621858	3/25/2026 10:12:57 PM	5621861
--2	1	14	209715200	512	2	YES	INACTIVE	5621861	3/25/2026 10:12:59 PM	5621883
--3	1	15	209715200	512	2	NO	CURRENT	5621883	3/25/2026 10:13:39 PM	18446744073709551615

select * from v$log;

--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nmm4nrx0_.log	NO	0
select * from v$logfile order by 1;

rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log;
rm -rf //u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nmm4nrx0_.log;

select 'rm -rf ' || member ||';' from v$logfile where group#=3 order by group#;


alter system switch logfile;
--
--2026-03-25T22:15:32.252871+07:00
--Errors in file /u01/app/oracle/diag/rdbms/orcl/orcl/trace/orcl_mz00_9432.trc:
--ORA-00313: open failed for members of log group 3 of thread 1
--ORA-00312: online log 3 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nmm4nrx0_.log'
--ORA-27037: unable to obtain file status
--Linux-x86_64 Error: 2: No such file or directory
--Additional information: 7
--ORA-00312: online log 3 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log'
--ORA-27037: unable to obtain file status
--Linux-x86_64 Error: 2: No such file or directory

--FIX 

--cd /u01/app/oracle/fast_recovery_area/ORCL/onlinelog
--ls -lt

--cp redo03b.log o1_mf_1_jngnotg1_.log

cd /u01/app/oracle/oradata/ORCL/onlinelog
ls -lt
cp redo02b.log redo03b.log
cp redo02b.log o1_mf_3_nmm4nrx0_.log


--2026-03-25T22:18:50.480757+07:00
--Completed: ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3;

alter system switch logfile;

select * from v$log;

alter system checkpoint;

select * from v$log;

select * from v$logfile;

SQL> shutdown immediate;
SQL> startup

SQL> show pdbs;

    CON_ID CON_NAME                       OPEN MODE  RESTRICTED
---------- ------------------------------ ---------- ----------
         2 PDB$SEED                       READ ONLY  NO
         3 PDB1                           READ WRITE NO
         
--15.4.3.MAT TOAN BO ONLINE REDO LOG GROUP     
--1	1	19	209715200	512	2	YES	INACTIVE	5623453	3/25/2026 10:19:15 PM	5623456
--2	1	21	209715200	512	2	NO	CURRENT	5623461	3/25/2026 10:19:26 PM	18446744073709551615
--3	1	20	209715200	512	2	YES	INACTIVE	5623456	3/25/2026 10:19:16 PM	5623461
select * from v$log;

--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm4nrc4_.log	NO	0
--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log	NO	0
select * from v$logfile order by 1;

--[Error] Execution (807: 1): ORA-01609: log 1 is the current log for thread 1 - cannot drop members
--ORA-00312: online log 1 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log'
--ORA-00312: online log 1 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm1mcp2_.log'
alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log';

alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log';

alter system switch logfile;

select * from v$log;

select * from v$logfile;

--3 Active xoa duoc
alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log';

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo03b.log'  TO GROUP 3;

select * from v$log;

select * from v$logfile order by group#;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo02b.log'  TO GROUP 2;

alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log';

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01b.log'  TO GROUP 1;

rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm4nrc4_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log;
select 'rm -rf ' || member ||';' from v$logfile order by 1;

--Loi redo log
alter system switch logfile;

2026-03-25T22:23:59.198585+07:00
Instance terminated by PMON, pid = 9773

--SQL> shutdown immediate;

SQL> startup
ORACLE instance started.

Total System Global Area 1073739888 bytes
Fixed Size                  9144432 bytes
Variable Size             666894336 bytes
Database Buffers          390070272 bytes
Redo Buffers                7630848 bytes
Database mounted.
ORA-00313: open failed for members of log group 3 of thread 1
ORA-00312: online log 3 thread 1:
'/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7
ORA-00312: online log 3 thread 1:
'/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log'
ORA-27037: unable to obtain file status
Linux-x86_64 Error: 2: No such file or directory
Additional information: 7

-- Tao lai cac group
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm4nrc4_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log;
rm -rf /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log;

select * from v$logfile order 
by 1;

cd /u01/app/oracle/oradata/ORCL/onlinelog/

--[oracle@linux7 onlinelog]$ ll
--total 1024020
---rw-r----- 1 oracle oinstall 209715712 Dec 10 21:43 ledo02b.log
---rw-r----- 1 oracle oinstall 209715712 Dec 10 21:28 ledo02b.log.xxx
---rw-r----- 1 oracle oinstall 209715712 Aug  4 21:49 o1_mf_3_n91l3jxo_.log
---rw-r----- 1 oracle oinstall 209715712 Dec 10 21:55 redo01b.log
---rw-r----- 1 oracle oinstall 209715712 Dec 10 21:56 redo03b.log
ll

cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nmm4nrc4_.log;
cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log;
cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log;
cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log;
cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/redo02b.log;
cp /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log;

ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 1;

ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 2;

--[Error] Execution (949: 1): ORA-01624: log 3 needed for crash recovery of instance orcl (thread 1)
--ORA-00312: online log 3 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log'
--ORA-00312: online log 3 thread 1: '/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log'

ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3;

alter system switch logfile;

--> 
cp 	 /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log;
cp 	 /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw7z6sxg_.log;

--ORA-00341: log 3 of thread 1, wrong log # 2 in header
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3;

--> CHIU
--Xoa het datafile cua CDB, PDB di:
 1007  cd ORCL/
 1008  ls
 1009  cd datafile/
 1010  ls
 1011  ls -lt
 1012  rm -rf *
 1013  ls
 1014  cd ..
 1015  ls
 1016  cd CC5BC8464FD23FD1E05380BDA8C03B75
 1017  ls
 1018  cd datafile/
 1019  ls
 1020  rm -rf *.dbf
 1021  ls
 1022  cd ..
 1023  ls
 1024  cd ..
 1025  ls
 1026  cd CC5C01A97A924B63E05380BDA8C055CE
 1027  ls
 1028  cd datafile/
 1029  ls
 1030  rm -rf *.dbf
 1031  ls
 1032  history

/*************** Khong fix duoc thi Recovery database ******************/

RESTORE SPFILE FROM '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06' TO '/tmp/spfileTEMP.ora'; 
RESTORE SPFILE TO '/tmp/spfileTEMP.ora' FROM AUTOBACKUP; # if in NOCATALOG mode

RESTORE SPFILE TO '/tmp/spfileTEMP.ora' FROM '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06';

rman target /
RMAN> restore database;
RMAN> recover database noredo;
RMAN> alter database open resetlogs;

RMAN> alter database open resetlogs;

RMAN-00571: ===========================================================
RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
RMAN-00571: ===========================================================
RMAN-03002: failure of sql statement command at 08/04/2025 21:59:10
ORA-01139: RESETLOGS option only valid after an incomplete database recovery

--+Case 2:
--connected to target database: ORCL (DBID=1611489315, not open)
rman target /
RMAN> startup nomount force;
RMAN> /*1*/ RESTORE SPFILE TO '/tmp/spfileTEMP.ora' FROM '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06';
RMAN> shutdown immediate
[oracle@linux7 logs]$ sqlplus / as sysdba

SQL*Plus: Release 19.0.0.0.0 - Production on Wed Mar 25 22:45:09 2026
Version 19.3.0.0.0

Copyright (c) 1982, 2019, Oracle.  All rights reserved.

Connected to an idle instance.

SQL> create pfile='/tmp/1' from spfile='/tmp/spfileTEMP.ora'; 

--Using parameter settings in server-side spfile /u01/app/oracle/product/19.0.0/dbhome_1/dbs/spfileorcl.ora
SQL> startup nomount;
(SQL > startup nomount pfile ='/tmp/1';)

RMAN>/*2*/  restore controlfile from  '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06';
RMAN> alter database mount;
RMAN> /*3*/ restore database; 
RMAN> /*4*/ recover database noredo; -- ko dung, dung case 3
RMAN> /*5*/ alter database open resetlogs;

--+Case 3: Toi da recovery
SQL> startup nomount force;
RMAN> restore controlfile from  '/home/oracle/backup/level0/auto_dbaviet_ctlc-1611489315-20260325-06';
RMAN> alter database mount;
RMAN> restore database;
RMAN> recover database; -- ko dung noredo

--unable to find archived log
--archived log thread=1 sequence=15
--RMAN-00571: ===========================================================
--RMAN-00569: =============== ERROR MESSAGE STACK FOLLOWS ===============
--RMAN-00571: ===========================================================
--RMAN-03002: failure of recover command at 03/25/2026 22:49:40
--RMAN-06054: media recovery requesting unknown archived log for thread 1 with sequence 15 and starting SCN of 5621883

--Check sequence co the recovery
SQL> select sequence#,first_change#, to_char(first_time,'HH24:MI:SS') from v$log;

--206	1228862971	/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log	1	1	14	5604185	3/25/2026 9:50:56 PM	3/25/2026 10:49:31 PM	1228859456	5621861	3/25/2026 10:12:59 PM	5621883	3/25/2026 10:13:39 PM	3	512	RMAN	RMAN	NO	NO	NO	NO	A	NO	NO	NO	0	0	0	NO	NO	NO		NO	0
--199	1228862805	/u01/app/oracle/fast_recovery_area/ORCL/archivelog/2026_03_25/o1_mf_1_14_nw7yx3rt_.arc	1	1	14	5604185	3/25/2026 9:50:56 PM	3/25/2026 10:46:45 PM	1228859456	5621861	3/25/2026 10:12:59 PM	5621883	3/25/2026 10:13:39 PM	3	512	RMAN	RMAN	NO	YES	NO	NO	A	NO	NO	NO	0	0	0	YES	NO	NO		NO	0
--147	1223596843		1	1	16	4517001	12/10/2025 10:32:39 PM	1/27/2026 12:00:43 AM	1219530759	4870894	1/23/2026 12:00:42 AM	4899142	1/27/2026 12:00:43 AM	134108	512	FGRD	FGRD	NO	YES	NO	YES	D	NO	NO	NO	1	1	1747339132	YES	NO	NO		NO	0
--200	1228862805	/u01/app/oracle/fast_recovery_area/ORCL/archivelog/2026_03_25/o1_mf_1_16_nw7z7ffh_.arc	1	1	16	5604185	3/25/2026 9:50:56 PM	3/25/2026 10:46:45 PM	1228859456	5623323	3/25/2026 10:15:31 PM	5623447	3/25/2026 10:19:09 PM	52	512	RMAN	RMAN	NO	YES	NO	NO	A	NO	NO	NO	0	0	0	YES	NO	NO		NO	0
select * from v$archived_log;

 run {
 set until sequence=15; 
 restore database;
 recover database;
 }
 
RMAN>  alter database open resetlogs;

--1	1	1	209715200	512	2	NO	CURRENT	5621884	3/25/2026 10:52:56 PM	18446744073709551615		0
--2	1	0	209715200	512	2	YES	UNUSED	0		0		0
--3	1	0	209715200	512	2	YES	UNUSED	0		0		0

select * from v$log;

--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw816slh_.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log	NO	0
--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nw816s89_.log	NO	0
--1		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log	NO	0
--2		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log	NO	0
--3		ONLINE	/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log	NO	0

select * from v$logfile;
--
--Resetting resetlogs activation ID 1756594810 (0x68b3827a)
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log: Thread 1 Group 1 was previously cleared
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_nw816s89_.log: Thread 1 Group 1 was previously cleared
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log: Thread 1 Group 2 was previously cleared
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_2_nmm4nrqb_.log: Thread 1 Group 2 was previously cleared
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log: Thread 1 Group 3 was previously cleared
--Online log /u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_3_nw816slh_.log: Thread 1 Group 3 was previously cleared
--2026-03-25T22:53:01.271049+07:00
--Setting recovery target incarnation to 8