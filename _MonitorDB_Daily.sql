/************************************************** ACTIVE, LOCK *******************************************************************/
SELECT /*1.Active session */ distinct s.inst_id i#, s.username, s.SID SID, s.osuser, s.machine,DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') ACTION,
s.sql_id, SUBSTR(DECODE(SS.SQL_TEXT, NULL, AA.NAME, SS.SQL_TEXT), 1, 1000) SQLTEXT,s.logon_time,s.p1text, S.P1, s.p2text, S.P2, s.p3text, S.P3
FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
WHERE  S.STATUS = 'ACTIVE' AND  S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND and s.type != 'BACKGROUND' AND S.TYPE = 'USER' 
--and s.username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','GOLDENGATE')
--AND username in 'CENTER2'
--and DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') like '%cell single block physical read%'
--and lower(ss.sql_text) like lower('%parallel%')
--and s.sid=4588 
--and s.machine like '%BINHTV%'
--and s.sql_id ='ccwg0nqr1zbu7'
ORDER BY username,sql_id;

select /* 2.Active theo user*/ USERNAME,count(*) from gv$session where  status='ACTIVE' group by USERNAME order by count(*) desc;

select /* 3.count , status*/ username,status, count(*) from gv$session group by username,status order by count(*) desc;

Select /*4.blocking_session*/ inst_id,blocking_session, sid, serial#, sql_id, wait_class, seconds_in_wait, username,STATUS,SCHEMANAME,OSUSER,MACHINE,PROGRAM,TYPE,LOGON_TIME  
From gv$session where blocking_session is not NULL and type not like 'BACKGROUND' order by inst_id;

select sql_id,sql_fulltext,loaded_versions,executions,loads,invalidations,parse_calls from gv$sql  where inst_id=4 and sql_id='cn7m7t6y5h77g';

/************************************************** SUM *********************************************************/
select /* count , status*/ username,status, count(*) from gv$session group by username,status order by count(*) desc;

select /* Active theo user*/ USERNAME,count(*) from gv$session where  status='ACTIVE' group by USERNAME order by count(*) desc;

select status, count(*) from gv$session  group by status order by status;

select count(*) from gv$session ;

select USERNAME,count(*) from gv$session group by USERNAME order by count(*) desc;

select machine,count(*) from v$session group by machine order by count(*) desc;

select inst_id, count(*) from gv$session group by inst_id;

select /*Thong ke theo status*/  username,status,count(*) from gv$session where username like 'USER1%' group by username,status order by count(*) desc;

select /*Thong ke theo inst_id*/ inst_id,count(*), username from gv$session where username like 'USER1%' group by inst_id, username order by username; 

select /* user theo machine */ machine,count(*), username from gv$session where username like 'USER1%' group by machine, username order by username;

/************************************************** KILL *********************************************************/
-- Xac dinh process tu inst_id, status, username, sql_id, machine, event,
SELECT /*username*/  'kill -9 ' || SPID A ,a.INST_ID,A.SID,A.SQL_ID, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,BACKGROUND, A.EVENT
FROM gv$session a, gv$process b  
WHERE b.ADDR = a.paddr 
AND a.inst_id=b.inst_id   
--AND B.inst_id = 4
--and a.status='INACTIVE'
--and A.USERNAME LIKE 'BINHTV_OWNER'
--AND A.USERNAME not  in ('SYS','GGATE','GOLDENGATE',''ORA_RECO_070361')
--AND a.program LIKE '%rman%'
--AND sql_id in ('gbmyfjjdcyk75')
--and machine  like '%HCM%'
--and a.event in  ('library cache lock','brary cache load lock','cursor: pin S wait on X','library cache pin','gc buffer busy acquire','enq: TS - contention','enq: TX - row lock contention','enq: TM - contention','db file parallel read','row cache lock','enq: DX - contention','enq: US - contention')
--and  round(to_number(sysdate-a.prev_exec_start)*1440) >30   
and type='USER' 
order by a.inst_id;

SELECT /*SID*/  'kill -9 ' || spid a, a.INST_ID,A.SQL_ID,A.SID, A.SERIAL#, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,a.prev_exec_start,BACKGROUND
FROM gv$session a, gv$process b 
WHERE b.addr = a.paddr   
AND a.inst_id=b.inst_id 
--and b.inst_id=2
AND a.sid in (
257
)
and type='USER'
order by inst_id;
  
SELECT /*call package*/  'kill -9 ' || spid a, a.INST_ID,A.SQL_ID,A.SID, A.SERIAL#, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,a.prev_exec_start,BACKGROUND
FROM gv$session a, gv$process b 
WHERE b.addr = a.paddr   
AND a.inst_id=b.inst_id 
--and b.inst_id=4
AND (b.inst_id, a.sid) in (
(select /*+ parallel(8) */  inst_id, sid from gv$access where object like '%proc_test%')
)
and type='USER'
and a.machine not like '%BINHTV%' ;

SELECT /*lock table*/  'kill -9 ' || spid a, a.INST_ID,A.SQL_ID,A.SID, A.SERIAL#, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,BACKGROUND
FROM gv$session a, gv$process b 
WHERE b.addr = a.paddr   
AND a.inst_id=b.inst_id 
--and b.inst_id=3
AND (b.inst_id, a.sid) in
(SELECT /*+ parallel(8)*/ s.inst_id,s.sid
FROM gv$locked_object v, dba_objects d,
gv$lock l, gv$session s
WHERE v.object_id = d.object_id
AND (v.object_id = l.id1)
AND v.session_id = s.sid
and object_name=upper('TAB1'))
--and type='USER'
--ORDER BY username, session_id;

-- Xac dinh user dang chay cau lenh SQL nao
select  p.INST_ID, 'kill -9 '||P.SPID SPID, s.SID, s.username su, substr(sa.sql_text,1,540) SQL_TEXT 
from gv$process p,gv$session s,gv$sqlarea sa
where p.addr=s.paddr and p.INST_ID=s.INST_ID and s.username is not null and s.sql_address=sa.address(+) and s.sql_hash_value=sa.hash_value(+) 
and s.username=upper('USER1') 
and type='USER'
order by INST_ID, SID;

--alter system kill session '1066,21548,@1' immediate; /*SID, Serial#*/
--alter system kill session '1921,46696' immediate;

select *--'alter system kill session ' || '''' || sid || ',' || SERIAL# || '''' || ' immediate;'
from gv$session 
where event = 'enq: TX - row lock contention'
or event like '%lock contention%';

select 'alter system kill session ' || '''' || sid || ',' || SERIAL# || '''' || ';',TIME_REMAINING+ELAPSED_SECONDS,TIME_REMAINING,TARGET 
from v$session_longops a where TIME_REMAINING>0
order by TIME_REMAINING+ELAPSED_SECONDS;
 
/***************************************************** SQL DETAIL *******************************************************************/
select sql_id,sql_fulltext from gv$sql where  sql_id in ('67bm8d2ah3xhk');

SELECT /* Tim cau lenh sql */ b.inst_id,b.sid, a.SQL_TEXT, b.username, b.machine, b.blocking_session, B.TYPE    
FROM gV$SQLAREA a,gV$SESSION b
WHERE a.ADDRESS = b.SQL_ADDRESS 
AND upper(SQL_TEXT) LIKE '%SHOP%'; 

select machine,username,count(*) from gv$session where sql_id='48hfqhs6n2gak' 
group by machine,username order by count(*) desc;

declare
begin 
    --SQLs with elapsed time more then 1 hour
    SELECT *
    FROM dba_hist_snapshot where end_interval_time>=to_date('03/08/2017 00:00:00','dd/mm/yyyy hh24:mi:ss')
    and end_interval_time <=to_date('04/08/2017 01:00:00','dd/mm/yyyy hh24:mi:ss')
    order by end_interval_time;
    
    SELECT min(snap_id), max(snap_id)
    FROM dba_hist_snapshot where end_interval_time>=to_date('03/08/2017 01:00:00','dd/mm/yyyy hh24:mi:ss')
    and end_interval_time <=to_date('04/08/2017 01:00:00','dd/mm/yyyy hh24:mi:ss')
    order by end_interval_time;

    SELECT sql_id,
    text,
    elapsed_time,
    CPU_TIME,
    EXECUTIONS,
    PX_SERVERS,
    DISK_READ_BYTES,
    DISK_WRITE_BYTES,
    IO_INTERCONNECT_BYTES,
    OFFLOAD_ELIGIBLE_BYTES,
    CELL_SMART_SCAN_ONLY_BYTES,
    FLASH_CACHE_READS,
    ROWS_PROCESSED
    --AVG_PX_SERVER
    FROM (SELECT x.sql_id,
    SUBSTR ( dhst.sql_text, 1, 4000) text,
    ROUND ( x.elapsed_time / 1000000,0)  elapsed_time,
    ROUND ( x.cpu_time / 1000000,0)  CPU_TIME,
    --ROUND ( x.elapsed_time / 1000000, 3) elapsed_time,
    --ROUND ( x.cpu_time / 1000000, 3) cpu_time_sec,
    x.executions_delta       EXECUTIONS,
    ROUND (X.DISK_READ_BYTES/1048576,0)        DISK_READ_BYTES,
    ROUND (X.DISK_WRITE_BYTES/1048576,0)       DISK_WRITE_BYTES,
    ROUND (X.IO_INTERCONNECT_BYTES/1048576,0)  IO_INTERCONNECT_BYTES,
    ROUND (X.OFFLOAD_ELIGIBLE_BYTES/1048576,0) OFFLOAD_ELIGIBLE_BYTES,
    X.FLASH_CACHE_READS                        FLASH_CACHE_READS,
    ROUND (X.cell_smart_scan_only_BYTES/1048576,0)  CELL_SMART_SCAN_ONLY_BYTES,
    (x.ROWS_PROCESSED) ROWS_PROCESSED,
    (X.PX_SERVERS) PX_SERVERS,
    --ROUND(X.PX_SERVERS/X.executions_delta,0) AVG_PX_SERVER,
    row_number () OVER (PARTITION BY x.sql_id ORDER BY 0) rn
    FROM dba_hist_sqltext dhst,
    (SELECT dhss.sql_id                       sql_id,
    SUM (dhss.cpu_time_delta)                 cpu_time,
    SUM (dhss.elapsed_time_delta)             elapsed_time,
    SUM (dhss.executions_delta)               executions_delta,
    SUM (dhss.PHYSICAL_READ_BYTES_DELTA)      DISK_READ_BYTES,
    SUM (dhss.PHYSICAL_WRITE_BYTES_DELTA)     DISK_WRITE_BYTES,
    SUM (dhss.IO_INTERCONNECT_BYTES_DELTA)    IO_INTERCONNECT_BYTES,
    SUM (dhss.IO_OFFLOAD_ELIG_BYTES_DELTA)    OFFLOAD_ELIGIBLE_BYTES,
    SUM (dhss.OPTIMIZED_PHYSICAL_READS_DELTA) FLASH_CACHE_READS,
    SUM (dhss.IO_OFFLOAD_RETURN_BYTES_DELTA)  cell_smart_scan_only_BYTES,
    SUM (dhss.ROWS_PROCESSED_DELTA)      ROWS_PROCESSED,
    SUM (dhss.PX_SERVERS_EXECS_DELTA) PX_SERVERS
    FROM dba_hist_sqlstat dhss
    WHERE dhss.snap_id IN
                        (SELECT distinct snap_id
                        FROM dba_hist_snapshot    
                        WHERE SNAP_ID > 90796 AND SNAP_ID<= 90820)
    --comment BELOW line if want to include current executions.
    --AND dhss.executions_delta > 0    
    and dhss.instance_number=1
    GROUP BY dhss.sql_id) x
    WHERE x.sql_id = dhst.sql_id
    AND ROUND ( x.elapsed_time / 1000000, 3) > 3600    
    )    
    WHERE rn = 1 ORDER BY ELAPSED_TIME DESC;
    
    --WAIT_CLASS AND COUNTS / NOTE " NULL VALUE IS CPU"
    select wait_class, count(*) cnt from dba_hist_active_sess_history
    WHERE SNAP_ID > 90796 AND SNAP_ID<= 90820 and instance_number=1
    group by wait_class_id, wait_class
    order by 2 desc;

    -- Top 40 Objects by Physical Read
    SELECT * FROM (
        SELECT do.OWNER||'.'||do.OBJECT_NAME||'..['||do.OBJECT_TYPE||']' AS OBJECTS,
        DHSS.INSTANCE_NUMBER AS INST,
        SUM(DHSS.LOGICAL_READS_DELTA) LOGICAL_READ,
        SUM(DHSS.PHYSICAL_READS_DELTA) PHY_READ,
        SUM(DHSS.PHYSICAL_WRITES_DELTA) PHY_WRIT,
        SUM(DHSS.ITL_WAITS_DELTA) ITL_WT,
        SUM(DHSS.ROW_LOCK_WAITS_DELTA) ROW_LCK_WT
        from dba_hist_seg_stat DHSS, DBA_OBJECTS DO    
        WHERE DHSS.SNAP_ID > 90797 AND DHSS.SNAP_ID<= 90820
        AND DHSS.OBJ#=DO.OBJECT_ID
        and DHSS.INSTANCE_NUMBER=1
        group by do.OWNER||'.'||do.OBJECT_NAME||'..['||do.OBJECT_TYPE||']',DHSS.INSTANCE_NUMBER
        order BY PHY_READ DESC
    ) WHERE ROWNUM <=40;
    
end; 
   
/***************************************************** LOCK BANG, PKG ****************************************************************/
--Table
SELECT c.owner, c.object_name, c.object_type, b.SID,b.SQL_ID, b.serial#, b.status,b.osuser, b.machine 
FROM v$locked_object a, v$session b, dba_objects c
WHERE b.SID = a.session_id 
AND a.object_id = c.object_id 
and lower(object_name) like lower('%tab1%');

SELECT s.inst_id,s.sid, s.serial#,s.sql_id,username U_NAME, owner OBJ_OWNER,
object_name, object_type, s.osuser, s.machine,
DECODE(l.block,
  0, 'Not Blocking',
  1, 'Blocking',
  2, 'Global') STATUS,
  DECODE(v.locked_mode,
    0, 'None',
    1, 'Null',
    2, 'Row-S (SS)',
    3, 'Row-X (SX)',
    4, 'Share',
    5, 'S/Row-X (SSX)',
    6, 'Exclusive', TO_CHAR(lmode)
  ) MODE_HELD,
  decode(l.TYPE,
'MR', 'Media Recovery',
'RT', 'Redo Thread',
'UN', 'User Name',
'TX', 'Transaction',
'TM', 'DML',
'UL', 'PL/SQL User Lock',
'DX', 'Distributed Xaction',
'CF', 'Control File',
'IS', 'Instance State',
'FS', 'File Set',
'IR', 'Instance Recovery',
'ST', 'Disk Space Transaction',
'TS', 'Temp Segment',
'IV', 'Library Cache Invalidation',
'LS', 'Log Start or Switch',
'RW', 'Row Wait',
'SQ', 'Sequence Number',
'TE', 'Extend Table',
'TT', 'Temp Table',l.type) lock_type
FROM gv$locked_object v, dba_objects d,
gv$lock l, gv$session s
WHERE v.object_id = d.object_id
AND (v.object_id = l.id1)
AND v.session_id = s.sid
and object_name like upper('%TAB1')
--and username like upper('trieunv')
ORDER BY username, session_id;

-- Cac session dang truy cap vao object theo owner --> De kill
select /*+ parallel(8) */ distinct owner from gv$access where lower(object) like lower('%TAB1%');

/*************************************************** BACKUP ***********************************************************************/
select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,2) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
from v$rman_backup_job_details 
where trunc(end_time)>=trunc(sysdate-120)
order by end_time desc; 

SELECT SID, SERIAL#, CONTEXT, SOFAR, TOTALWORK, ROUND(SOFAR/TOTALWORK*100,2) "%_COMPLETE"  
FROM V$SESSION_LONGOPS  
WHERE OPNAME LIKE 'RMAN%'  
  AND OPNAME NOT LIKE '%aggregate%'  
  AND TOTALWORK != 0  
  AND SOFAR  != TOTALWORK ;

/************************************************** STORAGE *********************************************************/
-- Size theo DF
select  round(sum(bytes)/1024/1024/1024,2) "DB_DF_GB" from dba_data_files
order by "DB_DF_GB" desc;

-- Size theo segments
select  round(sum(bytes)/1024/1024/1024,2) "DB_SEGMENTS_GB" from dba_segments 
order by "DB_SEGMENTS_GB" desc;

-- Tim Owner lon
select  owner,round(sum(bytes)/1024/1024/1024,2) "DB_SEGMENTS_GB" from dba_segments 
--where owner='USER1'
group by owner
order by "DB_SEGMENTS_GB" desc;

--Tim segment_name lon
select  owner,segment_name,round(sum(bytes)/1024/1024/1024,2) "DB_SEGMENTS_GB" from dba_segments 
--where owner='USER1'
group by owner,segment_name
order by "DB_SEGMENTS_GB" desc;

--Size TBS Read Only
select round(sum(bytes)/1024/1024/1024,2) "TBS_RO_SEGMENTS_GB" from dba_segments where tablespace_name in (select name from v$tablespace 
where ts# in (select ts# from v$datafile where enabled='READ ONLY'));

select * from dba_segments where tablespace_name in (select name from v$tablespace 
where ts# in (select ts# from v$datafile where enabled='READ ONLY'));

-- Tablespace su dung
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
 
 select round(sum(bytes)/1024/1024/1024,2) "GB" from dba_data_files;
               
/**************************************************** ASM ***********************************************************************/
select * from v$asm_diskgroup;

select * from V$ASM_DISKGROUP_STAT;

select name group_number, os_mb, total_mb, free_mb, path,header_status,mount_status,mode_status,state,create_date, mount_date from v$asm_disk order by name, group_number;

select round(sum(bytes)/1024/1024/1024,2) "GB" from dba_data_files;

/************************************************** ARCHIVED LOG *********************************************************/
-- Theo doi archived log sinh ra
select trunc(completion_time), round(sum(blocks*block_size)/1024/1024/1024,2) "Archived Log GB" from V$ARCHIVED_LOG
where trunc(completion_time) >= trunc(sysdate-90)
--and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
and dest_id=1
group by trunc(completion_time)
order by trunc(completion_time) desc;

-- Archived log sinh ra theo gio
select to_char(next_time,'YYYY-MM-DD hh24') Hour, round(sum(size_in_byte)/1024/1024,2) as size_in_mb, count(*) log_switch from (
select thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE as size_in_byte, next_time 
from v$archived_log where name is not null group by thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE, next_time)
group by to_char(next_time,'YYYY-MM-DD hh24') order by 1 desc;

select
to_char(COMPLETION_TIME,'YYYY-MM-DD') day,
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'00',1,0)),'999') "00h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'01',1,0)),'999') "01h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'02',1,0)),'999') "02h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'03',1,0)),'999') "03h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'04',1,0)),'999') "04h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'05',1,0)),'999') "05h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'06',1,0)),'999') "06h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'07',1,0)),'999') "07h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'08',1,0)),'999') "08h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'09',1,0)),'999') "09h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'10',1,0)),'999') "10h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'11',1,0)),'999') "11h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'12',1,0)),'999') "12h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'13',1,0)),'999') "13h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'14',1,0)),'999') "14h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'15',1,0)),'999') "15h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'16',1,0)),'999') "16h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'17',1,0)),'999') "17h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'18',1,0)),'999') "18h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'19',1,0)),'999') "19h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'20',1,0)),'999') "20h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'21',1,0)),'999') "21h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'22',1,0)),'999') "22h",
to_char(sum(decode(substr(to_char(COMPLETION_TIME,'HH24'),1,2),'23',1,0)),'999') "23h",
round(sum(BLOCKS*BLOCK_SIZE)/1024/1024,3)||' MB' "Total MB in a day",COUNT(*) "Total switch log in a day"
from v$archived_log
where to_date(COMPLETION_TIME) > sysdate-31
group by to_char(COMPLETION_TIME,'YYYY-MM-DD') 
order by day;

/************************************************** Analyze, Gather *********************************************************/
-- Index UNUSABLE
select * from dba_indexes where status='UNUSABLE';

select owner,segment_name, round(sum(bytes)/1024/1024,2) "MB" from dba_segments where (owner,segment_name)
in (select owner, index_name from dba_indexes where status='UNUSABLE')
group by owner, segment_name;

select * from dba_ind_partitions where status='UNUSABLE'; 

-- Partition
select table_owner,table_name,partition_name,last_analyzed from dba_tab_partitions
where table_owner='OAZ12' and last_analyzed<sysdate and last_analyzed>sysdate-7 
order by last_analyzed desc;

select index_owner,index_name,partition_name,last_analyzed from dba_ind_partitions
where  index_owner='OAZ12' and last_analyzed<sysdate and last_analyzed>sysdate-7
order by last_analyzed desc;

-- Non-partition
select owner, table_name,last_analyzed  from dba_tables
where owner='OAZ12' and last_analyzed<sysdate and last_analyzed>sysdate-7   
order by last_analyzed desc;

select owner, index_name,last_analyzed  from dba_indexes
where owner='BINHTV_OWNER' and last_analyzed<sysdate and last_analyzed>sysdate-7   
order by last_analyzed desc;

/************************************************** DISTRIBIUTED TRANSACTION *********************************************************/
---///////ORA-01591: lock held by in-doubt distributed transaction 10.1.10741505, xy ly tren sqlplus
select * from sys.pending_trans$;

select * from DBA_2PC_PENDING;

select * from DBA_2PC_NEIGHBORS;

743.30.1421878
1896.9.233248
2780.32.722288
3127.12.110519

commit force '3127.12.110519'
--rollback force '75.1.3697342'
execute dbms_transaction.purge_lost_db_entry('3127.12.110519');
commit;

SELECT   local_tran_id, state
              FROM   DBA_2PC_PENDING
              where (retry_time-fail_time)*24*60>1.5;
       
/************************************************** OBJECT INVALID ***********************************************************/
select 'ALTER '||OBJECT_TYPE||' '||OWNER||'.'||OBJECT_NAME||' COMPILE;' from dba_objects 
where object_type in ('PROCEDURE','FUNCTION','TRIGGER','PACKAGE') and status like 'INVALID'and OWNER like 'BINHTV_OWNER' 
UNION ALL
select 'ALTER PACKAGE '||OWNER||'.'||OBJECT_NAME||' COMPILE BODY;' from dba_objects
where object_type in ('PACKAGE BODY') and status like 'INVALID' and OWNER like 'BINHTV_OWNER';

/************************************************** OTHERS *********************************************************/
--DB, Instance
select * from gv$instance;

select * from gv$database;

--Index
select * from dba_ind_partitions where status='UNUSABLE' and index_owner not in ('SYS','SYSTEM') order by index_owner, index_name;

select * from dba_indexes where status!='VALID' and owner not in ('SYS','SYSTEM') and partitioned!='YES' order by owner, index_name;

-- Index parallel
select * from dba_indexes where    degree>1 order by 2;

-- Table parallel
select * from dba_tables  where  degree > '1' ;

-- Check IO
SELECT host_name,
         db_name,
         instance_name,
         ROUND (SUM (last_15_mins) / 1024 / 1024) IO_MB_LAST_15_MINS,
         SYSDATE
    FROM (  SELECT inst.host_name,
                   db.name AS db_name,
                   inst.instance_name,
                   sm.metric_name,
                   ROUND (AVG (sm.VALUE), 0) last_15_mins
              FROM GV$SYSMETRIC_HISTORY sm,
                   gv$instance inst,
                   (SELECT name FROM v$database) db
             WHERE     sm.inst_id = inst.inst_id
                   AND sm.metric_name IN ('Physical Read Total Bytes Per Sec',
                                          'Physical Write Bytes Per Sec',
                                          'Redo Generated Per Sec')
                   AND sm.begin_time >= SYSDATE - 15 / (24 * 60)
          GROUP BY inst.host_name,
                   db.name,
                   inst.instance_name,
                   sm.inst_id,
                   sm.metric_name)
GROUP BY host_name, db_name, instance_name
ORDER BY 1;
