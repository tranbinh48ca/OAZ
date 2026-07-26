--Thủ tục add datafile TỰ ĐỘNG trên Oracle Database File system
--Mục đích: add partition tự động của DB lớn (không phải mọi tablespace đều add partition) trên Oracle Database

--BƯỚC 1: TẠO CÁC BẢNG LƯU LOG:
CREATE TABLE oaz29.dbamf_log_op
    (id                             NUMBER,
    name                            VARCHAR2(1000 BYTE),
    event_date               TIMESTAMP (6) DEFAULT sysdate,
    type                           VARCHAR2(1000 BYTE),
    note                           VARCHAR2(1000 BYTE))
  PCTFREE     10
  INITRANS    1
  MAXTRANS    255
  TABLESPACE  users
  STORAGE   (
    INITIAL     65536
    NEXT        1048576
    MINEXTENTS  1
    MAXEXTENTS  2147483645
  )
  NOCACHE
  MONITORING
  NOPARALLEL
  LOGGING
/

CREATE SEQUENCE oaz29.dbamf_log_op_SEQ
  START WITH 1
  MAXVALUE 9999999999999999999999999999
  MINVALUE 1
  NOCYCLE
  CACHE 20
  NOORDER;

CREATE TABLE oaz29.DBAMF_LOG_JOBS
(
  ID          NUMBER,
  NAME        VARCHAR2(4000 BYTE),
  STATUS      VARCHAR2(50 BYTE),
  EVENT_DATE  DATE                              DEFAULT sysdate,
  NOTE        VARCHAR2(2000 BYTE)
)
TABLESPACE USERS
PCTUSED    0
PCTFREE    10
INITRANS   1
MAXTRANS   255
LOGGING 
NOCOMPRESS 
NOCACHE
NOPARALLEL
MONITORING; 

--DROP SEQUENCE oaz29.DBAMF_LOG_JOBS_SEQ; 

CREATE SEQUENCE oaz29.DBAMF_LOG_JOBS_SEQ
  START WITH 1
  MAXVALUE 9999999999999999999999999999
  MINVALUE 1
  NOCYCLE
  CACHE 20
  NOORDER;
  
select oaz29.DBAMF_LOG_OP_SEQ.nextval from dual;

select * from oaz29.DBAMF_LOG_OP;

select * From oaz29.DBAMF_LOG_JOBS;

--BƯỚC 2: TẠO THỦ TỤC TRÊN SYS
create   or replace PROCEDURE sys.auto_extend_space
    IS
        v_err varchar2(1000):='';
       free_space_low_level   NUMBER := 50000; 
        CURSOR c_free_space                 -- get tablespace free left 200MB.
        IS
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
         --and  ( a.tablespace_name not in ('DUMP'))
        -- and "Free_MB_Max" < 50000
        and round(maxbytes/1048576-(ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024)),0) <= 32768
         order by "%Used of Max" desc;

        v_sql           VARCHAR2 (200);
        msg             VARCHAR2 (1000);
        next_datafile   VARCHAR2 (1000);
    BEGIN
        insert into oaz29.dbamf_log_jobs (id,name,status,event_date, note)
            values(oaz29.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.extend_space',1,sysdate,'oaz29.dbamf_log_jobs, oaz29.dbamf_log_op');
        commit;
        FOR v_free_space IN c_free_space                 -- tablespace < 200MB
        LOOP
            BEGIN
                v_sql :=
                       'ALTER TABLESPACE '
                    || v_free_space.tablespace_name
                    || ' ADD DATAFILE  size 10m autoextend on next 1m'; --- 1G, autoextend 100m;
                --DBMS_OUTPUT.put_line (v_sql);
                EXECUTE IMMEDIATE v_sql;               
                insert into oaz29.dbamf_log_op (name, type, note) values (v_sql, 'df','Add a new datafile');
                commit;
            EXCEPTION
                WHEN OTHERS
                THEN
                   v_err := substr(SQLERRM,1,200);        
                    insert into oaz29.dbamf_log_jobs (id,name,status,event_date, note)
                        values(oaz29.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.extend_space',-1,sysdate,'Error sys.dba_op.extend_spac, '||v_err);
                commit;
            END;
        END LOOP;

        insert into oaz29.dbamf_log_jobs (id,name,status,event_date, note)
            values(oaz29.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.extend_space',1,sysdate,'oaz29.dbamf_log_jobs');
        commit;
   EXCEPTION
        WHEN others THEN
            v_err := substr(SQLERRM,1,200);        
            insert into oaz29.dbamf_log_jobs (id,name,status,event_date, note)
                values(oaz29.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.extend_space',-1,sysdate,'Error sys.dba_op.extend_spac, '||v_err);
            commit;
   END;

--BƯỚC 3: Tạo job từ sched.Jobs: 10 phút chạy 1 lần

--Vào giao diện hoặc chạy câu lệnh
--BEGIN
--  SYS.DBMS_SCHEDULER.DROP_JOB
--    (job_name  => 'SYS.AUTO_ADD_DATAFILE');
--END;
--/
BEGIN
  SYS.DBMS_SCHEDULER.DROP_JOB
    (job_name  => 'SYS.AUTO_ADD_DATAFILE');
END;
/
BEGIN
  SYS.DBMS_SCHEDULER.CREATE_JOB
    (
       job_name        => 'SYS.AUTO_ADD_DATAFILE'
      ,start_date      => TO_TIMESTAMP_TZ('2023/07/21 20:53:02.109327 +07:00','yyyy/mm/dd hh24:mi:ss.ff tzh:tzm')
      ,repeat_interval => 'FREQ=HOURLY;INTERVAL=1;BYMINUTE=0;BYSECOND=0'
      ,end_date        => NULL
      ,job_class       => 'DEFAULT_JOB_CLASS'
      ,job_type        => 'STORED_PROCEDURE'
      ,job_action      => 'SYS.AUTO_EXTEND_SPACE'
      ,comments        => 'AUTO_ADD_DATAFILE'
    );
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'RESTARTABLE'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'MAX_FAILURES');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'MAX_RUNS');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'STOP_ON_WINDOW_CLOSE'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'JOB_PRIORITY'
     ,value     => 3);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE_NULL
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'SCHEDULE_LIMIT');
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'AUTO_DROP'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'RESTART_ON_RECOVERY'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'RESTART_ON_FAILURE'
     ,value     => FALSE);
  SYS.DBMS_SCHEDULER.SET_ATTRIBUTE
    ( name      => 'SYS.AUTO_ADD_DATAFILE'
     ,attribute => 'STORE_OUTPUT'
     ,value     => TRUE);

  SYS.DBMS_SCHEDULER.ENABLE
    (name                  => 'SYS.AUTO_ADD_DATAFILE');
END;
/

select * from oaz29.dbamf_log_jobs order by id;

--BƯỚC 4: MONITOR JOBS:
-- Check job chạy lâu nhất, job chạy gần nhất cách đây 60 ngày
select owner,job_name,job_creator,state,job_type,last_run_duration,job_action,schedule_type,start_date,repeat_interval,last_start_date,next_run_date 
from dba_scheduler_jobs
where    --owner not  like 'SYS'
--and 
state!='DISABLED'
--and last_start_date > sysdate-60
order by last_run_duration desc;

SELECT * FROM dba_scheduler_running_jobs WHERE job_name = 'AUTO_ADD_DATAFILE';

SELECT * FROM dba_scheduler_jobs WHERE job_name = 'AUTO_ADD_DATAFILE';

SELECT * FROM dba_scheduler_job_log WHERE job_name = 'AUTO_ADD_DATAFILE';

--Hoặc kiểm tra JOB của schema khác

 SELECT * FROM user_scheduler_jobs WHERE job_name = 'AUTO_ADD_DATAFILE';

 SELECT * FROM user_scheduler_job_log WHERE job_name = 'AUTO_ADD_DATAFILE';


--Hoặc 
select * from oaz29.dbamf_log_op;

select * from oaz29.dbamf_log_jobs ;

