--Quản trị Online Redo Log Files trong Oracle Database

--1. Check
SELECT * FROM V$LOG
--where status  in ('INACTIVE','ACTIVE','CURRENT')
order by group#;

SELECT thread#, count(*) FROM V$LOG group by thread#;

SELECT * FROM V$LOGFILE order by group#;

SQL> COL DAY FORMAT a15;
SQL> COL HOUR FORMAT a4;
SQL> COL TOTAL FORMAT 999;

SELECT TO_CHAR(FIRST_TIME,'YYYY-MM-DD') DAY,
    TO_CHAR(FIRST_TIME,'HH24') HOUR,
    COUNT(*) TOTAL
    FROM V$LOG_HISTORY
    WHERE first_time >= sysdate - 1
    GROUP BY TO_CHAR(FIRST_TIME,'YYYY-MM-DD'),TO_CHAR(FIRST_TIME,'HH24')
    ORDER BY TO_CHAR(FIRST_TIME,'YYYY-MM-DD'),TO_CHAR(FIRST_TIME,'HH24')
    desc;

Các view khác:
v$thread
V$ARCHIVE_DEST 
V$LOG_HISTORY
V$DATABASE

--2. Add log file to group
--File system
alter database add logfile   thread 1 group 1 ('/u01/app/oracle/oradata/db12c/redo01.log','/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo01b.log','/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo01c.log') size 200M;

alter database add logfile   thread 1 group 2 ('/u09/oracle/data/DBAViet/redo02a.log','/u10/oracle/data/DBAViet/redo02b.log') size 1G;
alter database add logfile   thread 1 group 3 ('/u09/oracle/data/DBAViet/redo03a.log','/u10/oracle/data/DBAViet/redo03b.log')  size 1G;


alter database add logfile   thread 2 group 11 ('/u09/oracle/data/DBAViet/redo11a.log','/u10/oracle/data/DBAViet/redo12b.log')  size 1G;
alter database add logfile   thread 2 group 12 ('/u09/oracle/data/DBAViet/redo12a.log','/u10/oracle/data/DBAViet/redo12b.log') ' size 1G;
alter database add logfile   thread 2 group 13 ('/u09/oracle/data/DBAViet/redo13a.log','/u10/oracle/data/DBAViet/redo13b.log') size 1G;

(có thể dung lượng nhỏ hơn, tùy DB:
alter database add logfile   thread 2 group 13 ('/u09/oracle/data/DBAViet/redo13a.log','/u10/oracle/data/DBAViet/redo13b.log') size 100M;)

-- Add Log member
ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo01b.log'   TO GROUP 1

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo01c.log'   TO GROUP 1;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo02c.log'   TO GROUP 2;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog/redo03c.log'   TO GROUP 3;


ALTER DATABASE ADD LOGFILE MEMBER '/oracle/dbs/log2c.rdo'
    TO ('/oracle/dbs/log2a.rdo', '/oracle/dbs/log2b.rdo'); 

-- ASM
alter database add logfile   thread 1 group 1 ('+DATA','+RECO') size 1G;
alter database add logfile  thread 2 group 11  ('+DATA','+RECO') size 1G;

alter database add logfile   thread 1 group 2 ('+DATA','+RECO') size 1G;
alter database add logfile   thread 2 group 12  ('+DATA','+RECO')  size 1G;

alter database add logfile   thread 1 group 3 '+DATA' size 1G;
alter database add logfile   thread 2 group 13 '+DATA' size 1G;

--3. Xóa log file từ group
--Xóa log file, group
Alter database drop logfile group 1;
Alter database drop logfile member '/u10/oracle/data/DBAViet/redo01b.log';

--. Xóa trắng Redo Log File

ALTER DATABASE CLEAR LOGFILE GROUP 3;
ALTER DATABASE CLEAR UNARCHIVED LOGFILE GROUP 3;
 
Các câu lệnh khác:

--Bắt Log Switches để chuyển sang log file tiếp theo

ALTER SYSTEM SWITCH LOGFILE;