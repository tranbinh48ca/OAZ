SELECT * FROM V$LOG;

SELECT * FROM V$LOGFILE order by group#;

/u01/app/oracle/fast_recovery_area/db12c/DB12C/onlinelog

--alter database add logfile  thread 1 group 1 ('/u01/app/oracle/oradata/ORCL/onlinelog/o1_mf_1_jngnoq26_.log', '/u01/app/oracle/fast_recovery_area/ORCL/onlinelog/o1_mf_1_jngnotg1_.log','/u01/app/oracle/oradata/ORCL/onlinelog/redo01.log')  size 200m;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/oradata/ORCL/onlinelog/redo01b.log'   TO GROUP 1;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/oradata/ORCL/onlinelog/ledo02b.log'   TO GROUP 2;

ALTER DATABASE ADD LOGFILE MEMBER '/u01/app/oracle/oradata/ORCL/onlinelog/redo03b.log'   TO GROUP 3;

 alter system switch logfile;




