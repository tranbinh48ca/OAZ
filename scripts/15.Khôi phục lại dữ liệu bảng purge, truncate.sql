select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,2) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
from v$rman_backup_job_details 
where trunc(end_time)>=trunc(sysdate-120)
order by end_time desc; 

select * from OAZ27.TAB2;

drop table OAZ27.TAB2;

FLASHBACK TABLE OAZ27.TAB2 TO BEFORE DROP;

select * from dba_segments where owner='OAZ27';

select * from OAZ27."BIN$DAKli/9pLATgY4C2qMCcig==$0";

--OAZ27	BIN$DAKli/9pLATgY4C2qMCcig==$0	TAB20	DROP	TABLE	USERS	2023-12-08:21:31:46	2023-12-08:22:58:20	9520547		YES	YES	83331	83331	83331	16
select * from dba_recyclebin
where owner='OAZ27'
order by droptime desc;

purge table OAZ27.TAB2; -- Xoa thung rac

--[Error] Execution (23: 21): ORA-00942: table or view does not exist
select * from OAZ27."BIN$DAKli/9pLATgY4C2qMCcig==$0";

select * from OAZ27.TAB2;

$rman target /

RMAN> RECOVER TABLE 'OAZ27'.'TAB2' OF PLUGGABLE DATABASE pdb1
  UNTIL TIME "TO_DATE('10-12-2025 22:38', 'DD-MM-YYYY HH24:MI')"
  AUXILIARY DESTINATION '/u01/aux' ;
  
  --4.7GB, trong khi do / free 9GB
  select sum(bytes)/1024/1024/1024 from dba_data_files;
  
--10,000  
select * from OAZ27.TAB2;