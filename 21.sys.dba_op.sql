CREATE OR REPLACE PACKAGE SYS.dba_op
IS
 
    PROCEDURE auto_drop_partitions(v_date date);

    PROCEDURE fix_lock_dblinks;
    PROCEDURE fix_lock_dblinks1;

    PROCEDURE auto_extend_space;
    procedure auto_kill_direct;
    procedure auto_kill_sql_id;
    procedure auto_kill_lock_mem;
    procedure auto_kill_all;

   PROCEDURE auto_gather_tables ;
   PROCEDURE gather_partitioned_tables (p_month DATE);
   PROCEDURE gather_unpartitioned_tables ;
END; -- Package spec
/


CREATE OR REPLACE PACKAGE BODY SYS.dba_op
IS
    free_space_low_level   NUMBER := 50000;  --1000MB
    p_error         VARCHAR2 (1000);
    p_gather_date   DATE := SYSDATE ;

   
    procedure auto_drop_partitions(v_date date)
    is
        CURSOR c_partition
        IS   --
             SELECT   table_owner,table_name, partition_name
                      FROM   dba_tab_partitions
                     WHERE   (table_owner='TEST_OWNER')
                            and (sysdate - to_date(SUBSTR(partition_name,length(partition_name)-7,8),'yyyy/mm/dd') > 365 AND table_name IN ('MC_IN_LOG_VIEW','MC_HLR_LOG_VIEW'))
                    order by 1,2;
        v_sql_command   VARCHAR2 (2400);
        --date_num12t        INT := 365;                         -- Chi luu giu 40 ngay, PROM_CHARGE_DAILY_HIS,..
        v_err varchar2(1000):='';
        --v_date date := sysdate;
    BEGIN
        -- add partitions
        --dbms_output.put_line('0');
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_drop_partitions',1,sysdate,'binhtv.dbamf_log_jobs');
        commit;
        --dbms_output.put_line('1');
        FOR v_data IN c_partition
        LOOP
            --dbms_output.put_line('1.loop');
            v_sql_command :=    'alter table '
                                 || v_data.table_owner ||'.'
                                 || v_data.table_name
                                 || ' drop partition '
                                 || v_data.partition_name;
            --dbms_output.put_line(v_sql_command);
            EXECUTE IMMEDIATE   v_sql_command;
            --dbms_output.put_line('1.loop.IMMEDIATE');
            --dbms_output.put_line(v_sql_command);
        END LOOP;
        --dbms_output.put_line('2');
        --sys.send_sms_binhtv('Completed c_partition at: ' || sysdate);
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_drop_partitions',1,sysdate,'binhtv.dbamf_log_jobs');
        commit;
        --dbms_output.put_line('3');
        send_sms_binhtv('Completed sys.dba_op.auto_drop_partitions');
   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_op.auto_drop_partitions: ' || SQLERRM);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_drop_partitions',-1,sysdate,'Error sys.dba_op.auto_drop_partitions');
            commit;
   END;

    PROCEDURE fix_lock_dblinks
    IS
        CURSOR c1
        IS
            SELECT   local_tran_id
              FROM   DBA_2PC_PENDING
              where (retry_time-fail_time)*24*60>1.5
              AND STATE='committed'
              and (db_user not in ('BINHTV')
              or (db_user is null and host like '%KMTD%')); --waiting for longer 4 min
    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.fix_lock_dblinks',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;

        FOR r1 IN c1
        LOOP
            EXECUTE IMMEDIATE 'begin
            dbms_transaction.purge_lost_db_entry('''
                     || r1.local_tran_id
                     || ''');
            commit;
            end;';

            COMMIT;
        END LOOP;
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.fix_lock_dblinks',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
    EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_op.fix_lock_dblinks: ' || SQLERRM);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.fix_lock_dblinks',-1,sysdate,'Error sys.dba_op.fix_lock_dblinks');
            commit;
    END;
    PROCEDURE fix_lock_dblinks1
    IS
        v_err varchar2(1000);
        CURSOR c1
        IS
            SELECT   local_tran_id, state
              FROM   DBA_2PC_PENDING
              where (retry_time-fail_time)*24*60>1.5; --waiting for longer 4 min
    BEGIN
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.fix_lock_dblinks1',1,sysdate,'binhtv.dbamf_log_jobs');
        /*FOR r1 IN c1
        LOOP

            dbms_output.put_line('1');
            EXECUTE IMMEDIATE 'rollback force '''
                     || r1.local_tran_id
                     || '''';
            commit;
        end loop;*/

        FOR r2 IN c1
        LOOP
            if r2.state in ('committed') then
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;
             elsif r2.state='prepared' then
                EXECUTE IMMEDIATE 'rollback force '''
                     || r2.local_tran_id
                     || '''';
                commit;
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;
             else
                EXECUTE IMMEDIATE 'begin
                dbms_transaction.purge_lost_db_entry('''
                         || r2.local_tran_id
                         || ''');
                commit;
                end;';
                commit;

             end if;
        end loop;
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.fix_lock_dblinks1',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
   EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.fix_lock_dblinks1',-1,sysdate,'Error sys.dba_op.fix_lock_dblinks1, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.fix_lock_dblinks1, ' ||v_err);
   END;

   PROCEDURE auto_extend_space
   IS
      CURSOR c_free_space -- get tablespace free left 200MB.
      IS
/*      SELECT   tablespace_name, SUM (BYTES) / 1024 / 1024
             FROM SYS.dba_free_space
            WHERE (lower(tablespace_name) in ('regb_req_data01','regb_req_data06','data','indx','users','indx' || to_char(sysdate,'YYYY'),'indx' || to_char(sysdate,'YYYYMM'),'data' || to_char(sysdate,'YYYY'),'data' || to_char(sysdate,'YYYYMM'),'mclo' || to_char(sysdate,'YYYYMM')))
            --WHERE tablespace_name='INDX2014'
         GROUP BY tablespace_name
           HAVING SUM (BYTES) / 1024 / 1024 < free_space_low_level;*/
             SELECT
              a.tablespace_name,
               ROUND (a.bytes_alloc / 1024 / 1024) megs_alloc,
               ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) megs_free,
               ROUND (maxbytes / 1048576) MAX,
               ROUND (maxbytes / 1048576)-ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024) free_tbs
            FROM (  SELECT f.tablespace_name,
                         SUM (f.bytes) bytes_alloc,
                         SUM (
                            DECODE (f.autoextensible,
                                    'YES', f.maxbytes,
                                    'NO', f.bytes))
                            maxbytes
                    FROM dba_data_files f
                GROUP BY tablespace_name) a,
               (  SELECT f.tablespace_name, SUM (f.bytes) bytes_free
                    FROM dba_free_space f
                GROUP BY tablespace_name) b
            WHERE a.tablespace_name = b.tablespace_name(+)
            AND (lower(a.tablespace_name) in ('regb_req_data01','regb_req_data06','data','indx','users','indx' || to_char(sysdate,'YYYY'),'indx' || to_char(sysdate,'YYYYMM'),'data' || to_char(sysdate,'YYYY'),'data' || to_char(sysdate,'YYYYMM'),'data' || to_char(sysdate,'YYYY')||'_rw','indx' || to_char(sysdate,'YYYY')||'_rw','mclo' || to_char(sysdate,'YYYYMM')))
            AND ROUND (maxbytes / 1048576)-ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024) < free_space_low_level
            order by ROUND (maxbytes / 1048576)-ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024) desc;

        v_sql   varchar2(1000);
        msg varchar2(1000);
        v_err varchar2(1000);
   BEGIN
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_extend_space',1,sysdate,'binhtv.dbamf_log_jobs');
        commit;
        for v_free_space in c_free_space
        loop
            begin
                v_sql:='ALTER TABLESPACE '
                    || v_free_space.tablespace_name
                    || ' ADD DATAFILE size 8G autoextend OFF';
                EXECUTE IMMEDIATE v_sql;
                --dbms_output.put_line('sql: ' || v_sql);
                send_sms_binhtv('Card: v_sql ' || v_sql);
            end;
        end loop;
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_extend_space',1,sysdate,'binhtv.dbamf_log_jobs');
        commit;
        --send_sms_binhtv('Completed sys.dba_op.auto_extend_space');
   EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_extend_space',-1,sysdate,'Error sys.dba_op.auto_extend_space, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.auto_extend_space, ' ||v_err);
   END;

    -- Job kill tien trinh quet full chiem nhieu IO
   procedure auto_kill_direct
   is
    v_err varchar2(1000);
     cursor c1 is SELECT 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||',@'||s.inst_id||''' immediate'sqltext
    FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
    WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND     AND S.TYPE = 'USER'
    AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1)) and username NOT in ('SYS','BINHVT')
    and DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') IN ('direct path read','db file scattered read','PX Deq Credit: send blkd') ;
    nsession number;

   begin
      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_kill_direct',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
      SELECT count(*) into nsession
      FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
      WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND AND S.TYPE = 'USER'
      AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1)) and username not in ('SYS','SYSMAN');
      --IF nsession>150 THEN
      IF nsession>300 THEN
        for r1 in c1 loop
          begin
            execute immediate r1.sqltext;
          exception
            when others then null;
          end;
        end loop;
      end if;

      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_kill_direct',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
   EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_kill_direct',-1,sysdate,'Error sys.dba_op.auto_kill_direct, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.auto_kill_direct, ' ||v_err);
   END;

    -- Job kill cac cau lenh bat thuong gay tang tai
   procedure auto_kill_sql_id
   is
        cursor c2 is SELECT 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||',@'||s.inst_id||''' immediate'sqltext
        FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
        WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND     AND S.TYPE = 'USER'
        AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1))
        and s.sql_id in ('dqb9hg546pk2c','8yun477ph5333','9m4fha58ngchf','77v3nwwph3pdv','2x2qbhtvr6yu2','gydasbrnsyxa1','ckj83ua4gk847','b49mktdg1ddsg','azxdzad5pku35','b49mktdg1ddsg','1xxb5zghqfnnd','dqb9hg546pk2c','azxdzad5pku35','bm72hcznbd433','6z9rabgwm8v70','562xv25t83b2u','drgbfu8y0fs3v','4c24awr2jkv1p','guz6xw11t4f6s','6z9rabgwm8v70','147z1raw5hsfq','6nxb8p7s91gs9','592x919qtvz06','bt05z7yfpyxk6','bgp6ja1spjrh3','g2c9zn8rqwwcf','bt05z7yfpyxk6','dqb9hg546pk2c','2f6jtz620h7m4','1fkjrpkyp5cgw','7470q698pzjs9','9k7fx6x81qvsb','gf5tujm2aa9dh','1uu005ppxhsqw','2kxybw5awdvfn','cgzc3ut2nrhff','gbmyfjjdcyk75','2541vzdnptncb')
        and s.username NOT in ('SYS') ;
        nsession number;
        v_err varchar2(1000);
       


    begin
      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_kill_sql_id',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
      SELECT count(*) into nsession
      FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
      WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND and s.type != 'BACKGROUND' AND S.TYPE = 'USER'
      AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1)) and username NOT in ('SYS','SYSMAN','DBSNMP','GGATE','GOLDENGATE');
      --IF nsession>300 THEN: cu
      -- Cap nhat ngay 27/08/2020
      --IF nsession>40 THEN
        for r2 in c2 loop
            begin
              execute immediate r2.sqltext;
            exception
              when others then null;
            end;
          end loop;
      --end if;
      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_kill_sql_id',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
   EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_kill_sql_id',-1,sysdate,'Error sys.dba_op.auto_kill_sql_id, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.auto_kill_sql_id, ' ||v_err);
   END;

    -- Job kill cac cau lenh gay lock
   procedure auto_kill_lock_mem
   is
    v_err varchar2(1000);
    cursor c1 is SELECT 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||',@'||s.inst_id||''' immediate;' sqltext
        FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
        WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND AND S.TYPE = 'USER' and s.username  not in ('SYS','SYSMAN','BINHVT')
        and s.event in ('library cache lock','gc buffer busy acquire')
        and s.username NOT in ('SYS');
        nsession number;
    begin
      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_kill_lock_mem',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
      SELECT count(*) into nsession
      FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
      WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND AND S.TYPE = 'USER'
      AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1)) and username not in ('SYS','SYSMAN');
      IF nsession>300 THEN
        for r1 in c1 loop
            begin
              execute immediate r1.sqltext;
            exception
              when others then null;
            end;
        end loop;
      end if;
      insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_kill_lock_mem',1,sysdate,'binhtv.dbamf_log_jobs');
      commit;
   EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_extend_space',-1,sysdate,'Error sys.dba_op.auto_extend_space, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.auto_extend_space, ' ||v_err);
   END;

    procedure auto_kill_all
    is
        v_err VARCHAR2(1000);
        cursor c1 is SELECT 'ALTER SYSTEM KILL SESSION '''||s.sid||','||s.serial#||',@'||s.inst_id||''' immediate' sqltext
            FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
            WHERE s.type != 'BACKGROUND' AND S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND     AND S.TYPE = 'USER'
            AND s.sql_id <> (select sql_id from v$session where sid=(select sid from v$mystat where rownum=1)) and s.USERNAME not  in ('SYS','SYSTEM','GGATE','GOLDENGATE','BINHVT');
        nsession number;
    begin
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_kill_all',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
         select count(*) into nsession from gv$session s  where s.status='ACTIVE' group by status ;
          IF nsession > 600 THEN
            for r1 in c1 loop
              begin
                execute immediate r1.sqltext;
              exception
                when others then null;
              end;
            end loop;
          end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_kill_all',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
    EXCEPTION
        WHEN others THEN
             v_err := substr(SQLERRM,1,200);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.auto_extend_space',-1,sysdate,'Error sys.dba_op.auto_extend_space, ' ||v_err);
             commit;
             send_sms_binhtv('Error sys.dba_op.auto_extend_space, ' ||v_err);
   END;

    PROCEDURE auto_gather_tables
    IS
    BEGIN
        send_sms_binhtv('TEST_OWNER: Gather Starting at ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'));
       insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.auto_gather_tables',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
        gather_partitioned_tables (TRUNC (SYSDATE));
        cdr_monitor.send_email_html@vms2('tranbinh48ca@gmail.vn','TEST_OWNER Completed gathering partitioned_tables', 'TEST_OWNER Completed gathering partitioned_tables at ' || to_char(sysdate,'dd/mm/yyy hh24:mm:ss'));
        IF (TO_NUMBER (TO_CHAR (SYSDATE, 'dd')) IN (8, 18, 28) and (TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) < 8 or TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) > 21 ))
        THEN
            gather_unpartitioned_tables;
            binhtv.send_email_html('tranbinh48ca@gmail.vn','TEST_OWNER Completed gathering unpartitioned_tables', 'TEST_OWNER Completed gathering unpartitioned_tables at ' || to_char(sysdate,'dd/mm/yyy hh24:mm:ss'));
        END IF;
        send_sms_binhtv('TEST_OWNER: Gather success at ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'));

         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.auto_gather_tables',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
        --null;
    EXCEPTION
         WHEN others THEN
             send_sms_binhtv('Error sys.dba_op.auto_gather_tables: ' || SQLERRM);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.exec_gather_tables_cus',-1,sysdate,'Error sys.dba_op.auto_gather_tables');
             commit;
    END;

    PROCEDURE gather_partitioned_tables (p_month DATE)
    IS
        CURSOR c_partitioned_tables
        IS
              SELECT   table_name, partition_name, last_analyzed,
                          'ANALYZE TABLE '
                       || table_owner
                       || '.'
                       || table_name
                       || ' partition ('
                       || partition_name
                       || ') ESTIMATE STATISTICS SAMPLE 10 PERCENT'
                           script
                FROM   dba_tab_partitions
               WHERE   (( (partition_name LIKE
                                'DATA' || TO_CHAR (p_month, 'YYYYMM') ||'%'
                              AND LENGTH(partition_name)>10
                              AND TO_DATE(SUBSTR(partition_name,5,8),'YYYYMMDD')>=SYSDATE-7
                              AND TO_DATE(SUBSTR(partition_name,5,8),'YYYYMMDD')<SYSDATE+3
                          )
                          OR partition_name =
                                'DATA' || TO_CHAR (p_month, 'YYYY')
                       ) or table_name in ('MC_SUBSCRIBER'))
                       AND table_name NOT LIKE '%$%'
                       AND table_owner IN ('TEST_OWNER')
                       AND (NVL (last_analyzed, SYSDATE - 15) < p_gather_date OR num_rows=0)
            ORDER BY   table_name, last_analyzed, partition_name;
/*
            SELECT   table_name, partition_name, last_analyzed,
                          'begin
                                dbms_stats.gather_table_stats
                                (ownname=>''' || TABLE_OWNER || ''',
                                tabname=>''' || table_name || ''',
                                partname=>''' || partition_name || ''',
                                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                method_opt => ''FOR ALL COLUMNS SIZE AUTO'',
                                cascade=>true,
                                degree=>10);
                                end;
                            '  script
                FROM   all_tab_partitions
               WHERE   ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<sysdate
                       AND to_date(substr(partition_name,5,8),'YYYYMMDD')>sysdate-5)
                       or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<sysdate
                       AND to_date(substr(partition_name,5,6),'YYYYMM')>=add_months(trunc(sysdate,'month'),-1))
                       or (length(partition_name) =8 AND to_date(substr(partition_name,5,4),'YYYY')<sysdate
                       AND to_date(substr(partition_name,5,4),'YYYY')>=trunc(sysdate,'year'))
                       )
                       AND table_name NOT LIKE '%$%'
                       AND table_owner IN ('TEST_OWNER')
                       AND (NVL (last_analyzed, SYSDATE - 15) < p_gather_date OR num_rows=0)
            ORDER BY   table_name, last_analyzed, partition_name;
*/
        v_table_name   VARCHAR2 (100);
        v_par_name     VARCHAR2 (100);
    BEGIN
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.gather_partitioned_tables',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
        
        FOR v_partitioned_tables IN c_partitioned_tables
        LOOP
            v_table_name := v_partitioned_tables.table_name;
            v_par_name := v_partitioned_tables.partition_name;
            if (TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) < 8 or TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) > 21 )
            then
                EXECUTE IMMEDIATE v_partitioned_tables.script;
            end if;
        END LOOP;
        --EXECUTE IMMEDIATE 'analyze table mc_subscriber estimate statistics sample 10 percent';
        

        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.gather_partitioned_tables',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;

        --null;
    EXCEPTION
         WHEN others THEN
             send_sms_binhtv('Error sys.dba_op.auto_gather_tables: ' || SQLERRM);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.gather_partitioned_tables',-1,sysdate,'Error sys.dba_op.gather_partitioned_tables');
             commit;
    END;

    -- Gather stats for unpartitioned tables
    -- Input:
    -- p_Owner: Owner of tables
    -- p_Ignored_Tables_List: List of Tables that will not be gathered
    -- Output
    -- p_Gathered_Tables: Tables already gathered
    -- p_Error: Errors descriptions(if any), NULL value means no error occurred
    PROCEDURE gather_unpartitioned_tables
    IS
        CURSOR c_tables
        IS
              SELECT   owner, table_name, last_analyzed,
                       'begin
        dbms_stats.gather_table_stats
        (ownname => '''
                       || owner
                       || ''',
        tabname => '''
                       || table_name
                       || ''',
        cascade => true,
        estimate_percent => 10,
        degree => 10);
        end;
        '
/*        'begin
                                dbms_stats.gather_table_stats
                                (ownname=>''' || OWNER || ''',
                                tabname=>''' || table_name || ''',
                                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                method_opt => ''FOR ALL COLUMNS SIZE AUTO'',
                                cascade=>true,
                                degree=>10);
                                end;
                            '
*/                           script
                FROM   dba_tables
               WHERE       partitioned = 'NO'
                       AND owner IN ('TEST_OWNER')
                       and table_name not like 'XX%'
                       AND tablespace_name IS NOT NULL
                       AND table_name NOT LIKE '%$%'
                       AND NVL (last_analyzed, SYSDATE - 15) < p_gather_date
            ORDER BY   last_analyzed;

        v_table_name   VARCHAR2 (100);
    BEGIN
        insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_op.gather_unpartitioned_tables',1,sysdate,'binhtv.dbamf_log_jobs');
        commit;
        --TEST_OWNER.send_sms ('902912888',  'TEST_OWNER: Gather unpartitioned_tables started at ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'));
        FOR v_tables IN c_tables
        LOOP
            v_table_name := v_tables.table_name;
            if (TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) < 8 or TO_NUMBER (TO_CHAR (SYSDATE, 'hh24')) > 21 )
            then
                EXECUTE IMMEDIATE v_tables.script;
            end if;
        END LOOP;
        --TEST_OWNER.send_sms ('902912888',  'TEST_OWNER: Gather unpartitioned_tables successed at ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'));
       insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_op.gather_unpartitioned_tables',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
        --null;
    EXCEPTION
         WHEN others THEN
             send_sms_binhtv('Error sys.dba_op.gather_unpartitioned_tables: ' || SQLERRM);
             insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                 values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_op.gather_unpartitioned_tables',-1,sysdate,'Error sys.dba_op.gather_unpartitioned_tables');
             commit;
    END;
END;
/
