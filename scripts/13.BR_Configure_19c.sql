--1.Kiem tra control file: Dam bao co 2 control file
select * from v$controlfile

--/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl
--/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl

SQL> show parameter control;

--+ Them control file
SQL> alter system set control_files='/u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl','/u01/app/oracle/fast_recovery_area/ORCL/controlfile/o1_mf_jngnomvm_.ctl','/u01/app/oracle/oradata/ORCL/controlfile/control03.ctl','/u01/app/oracle/oradata/ORCL/controlfile/control04.ctl' scope=spfile;
SQL> shutdown immediate;
SQL> exit

$ cp /u01/app/oracle/oradata/ORCL/controlfile/o1_mf_jngnomtw_.ctl /u01/app/oracle/oradata/ORCL/controlfile/control03.ctl

[oracle@linux7 ~]$ sqlplus / as sysdba
SQL> startup

SQL> show parameter control;

--2.Cau hinh phan vung fast recovery area mac danh
select * from v$parameter where name like '%recovery_file%'

SQL> show parameter db_recovery_file_dest;

[root@linux7 ~]# mkdir /fra
[root@linux7 fra]# chown -Rf oracle:oinstall /fra

SQL> alter system set db_recovery_file_dest='/fra';

SQL> show parameter db_recovery_file_dest_size;
SQL> alter system set DB_RECOVERY_FILE_DEST_SIZE=14G;
SQL> show parameter db_recovery_file_dest;

--3.Cau hinh nhieu redo log group
select * from v$log;

--6		ONLINE	/data/onlinelog/redo06.log	NO	0
--7		ONLINE	/data/onlinelog/redo07.log	NO	0
--8		ONLINE	/data/onlinelog/redo08.log	NO	0
select * from v$logfile order by 1;

alter system switch logfile;

-- Kiem tra xem co OMF khong
SQL> show parameter online;

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
db_create_online_log_dest_1          string      /data/onlinelog

-- Add Log member
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo06b.log'   TO GROUP 6;
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo07b.log'   TO GROUP 7;
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo08b.log'   TO GROUP 7;

--6	INVALID	ONLINE	/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo06b.log	NO	0
--6		ONLINE	/data/onlinelog/redo06.log	NO	0
--7	INVALID	ONLINE	/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo08b.log	NO	0
--7		ONLINE	/data/onlinelog/redo07.log	NO	0
--7	INVALID	ONLINE	/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo07b.log	NO	0
--8		ONLINE	/data/onlinelog/redo08.log	NO	0

select * from v$logfile order by 1;

alter system switch logfile;

--OMF
--ALTER DATABASE ADD LOGFILE GROUP 1 size 200m;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01b.log' to group 1;

alter system switch logfile;

-- Xoa 
Alter database drop logfile member '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/o1_mf_1_jngnotg1_.log';
Alter database drop logfile member '/u01/app/oracle/oradata/ORCL/onlinelog/redo01c.log';
Alter database drop logfile member '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/o1_mf_2_jngnotfp_.log';
Alter database drop logfile member '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01b.log';

-- Them member redo log vao redo log group
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01a.log'   TO GROUP 1;
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01bb.log'   TO GROUP 2;
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/redo01c.log'   TO GROUP 3;

Alter database drop logfile group 5;

Alter database drop logfile group 3;

Alter database drop logfile group 4;

--4.Dat CSDL o che do ARCHIVELOG

--select name, OPEN_MODE,Log_mode from v$database;
select * from v$database;

SQL> archive log list;
Database log mode              Archive Mode
Automatic archival             Enabled
Archive destination            USE_DB_RECOVERY_FILE_DEST
Oldest online log sequence     18
Next log sequence to archive   20
Current log sequence           20

SQL> show parameter recovery;

NAME                                 TYPE        VALUE
------------------------------------ ----------- ------------------------------
db_recovery_file_dest                string      /backup
db_recovery_file_dest_size           big integer 15G
recovery_parallelism                 integer     0
remote_recovery_file_dest            string
