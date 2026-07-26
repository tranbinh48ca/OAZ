CREATE OR REPLACE PACKAGE SYS.dba_rp
IS
    
    PROCEDURE hc_all;
    PROCEDURE hc_sms;
    PROCEDURE session_sms;
    PROCEDURE hc_storage;
    PROCEDURE hc_backup;
    PROCEDURE hc_du;
    PROCEDURE hc_os;
    --PROCEDURE hc_ddl;
    procedure hc_ddl_log;
    procedure hc_fga_log;
END; -- Package spec
/

CREATE OR REPLACE PACKAGE BODY SYS.dba_rp
IS
    
    -- Ngay chay 2 lan 8h, 16h cac thong tin: 1.Tai DB, 2.Backup, 3.Storage, 3.1.User su dung, 4.Object invalid, 5.Index Non-partition, parttion Unuable, 6.Archive log: Hoi it
    --
    procedure hc_all
    is
        tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';

        --1.Tai DB
        nActiveSession number;
        nTotalActiveSession number; -- Ca background
        nTotalInactiveSession number;
        nTotalSession number;
        nLock number;
        nLockDBLink number;

        CURSOR cTotalUserSession
        IS
           select /* count , status*/ username,status, count(*) num from gv$session group by username,status
           having (count(*)>400 and status='INACTIVE') or (count(*)>20 and status='ACTIVE')
           order by status,count(*) desc,username;

        tTotalUserSession varchar2(30000):='';


        cursor c_cpu_ram
        is
             select event_date, duration, server_name, cpu_idle, round(ram_free_k/1024/1024,0) "GB"
            from BINHTV.dbamf_ct_vmstat
            where event_date > sysdate-1/24
            and (cpu_idle <= 20 or round(ram_free_k/1024/1024,0) <=70)
            order by event_date desc;
        v_cpu_ram varchar2(30000):='';
        --2.Backup
        CURSOR cBackup
        IS
           select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,0) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
            from v$rman_backup_job_details
            where trunc(end_time)>=trunc(sysdate-7)
            order by end_time desc;
        tBackup varchar2(30000):='';

         --3.Storage
         cursor cASM is
             select name, state, type,  round(total_mb/1024) total_gb,  round(usable_file_mb/1024) usable_file_gb from v$asm_diskgroup;
         tASM varchar2(30000) := '';

         cursor cTBS is
            SELECT  a.tablespace_name,100 - ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) pct_usage,   ROUND(a.bytes_alloc / 1024 / 1024/1024) size_gb,   ROUND (NVL (b.bytes_free, 0) / 1024 / 1024/1024) free_gb,
                  (ROUND (a.bytes_alloc / 1024 / 1024/1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024/1024)) used_gb, ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) pct_free, ROUND (maxbytes / 1048576/1024)  max_gb,
                   ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100) as pct_used_max
              FROM (  SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
                        FROM dba_data_files f
                    GROUP BY tablespace_name) a,
                   (  SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
             WHERE a.tablespace_name = b.tablespace_name(+)
             --and a.tablespace_name in ('DATA','INDX')
             and ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100)  > 90
             order by pct_used_max desc;
         tTBS varchar2(30000) := '';

         cursor c_user_usage is
             select owner,round(sum(bytes)/1024/1024/1024,0) "GB" from dba_segments
             group by owner
              having round(sum(bytes)/1024/1024/1024,0)  > 50
             order by "GB" desc;
         v_user_usage varchar2(30000) := '';


        cursor c_object_usage is
             select owner,segment_name,round(sum(bytes)/1024/1024/1024,0) "GB" from dba_segments
             group by owner, segment_name
             having round(sum(bytes)/1024/1024/1024,0)  > 200
             order by "GB" desc;
         v_object_usage varchar2(3000) := '';

          -- Cac tablespace Read Only:Chay lau
    /*      cursor cTBS_RO is
              select tablespace_name, round(sum(bytes)/1024/1024/1024,0) "GB"
                from dba_segments
                where tablespace_name in (select name from v$tablespace where ts# in (select ts# from v$datafile where enabled='READ ONLY'))
                group by tablespace_name
                order by tablespace_name ;
        tStorage varchar2(4000):='';*/

        cursor c_du
        is
             select * from binhtv.dbamf_ct_disk_usage
                where event_date>sysdate-1
                and nvl(substr(disk_percen,-3,2),0)>70
                order by disk_percen desc;
        v_du varchar2(30000):='';

        --4.Object invalid
        nInvalidObject number;

        --5.Index Non-partition, parttion Unuable
        nUnuableIndNonPar number;
        nUnuableIndPar number;


         --6.Archive log
         -- Theo doi archived log sinh ra
        cursor cTotalArchivedLog is
            select trunc(completion_time), round(sum(blocks*block_size)/1024/1024/1024,0) "Archived Log GB" from V$ARCHIVED_LOG
            where trunc(completion_time) >= trunc(sysdate-1)
            --and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
            and dest_id=1
            group by trunc(completion_time)
            order by trunc(completion_time) desc;

        -- Archived log sinh ra theo gio
        cursor cHourArchivedLog is
        select to_char(next_time,'YYYY-MM-DD hh24') Hour, round(sum(size_in_byte)/1024/1024,0) as size_in_mb, count(*) log_switch from (
        select thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE as size_in_byte, next_time
        from v$archived_log where name is not null and completion_time>sysdate-1 group by thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE, next_time)
        group by to_char(next_time,'YYYY-MM-DD hh24') order by 1 desc;

        tArchivedLog varchar2(30000):='';

        --7.Gather
        tGather varchar2(4000):='';
        tGatherTabPar varchar2(100) :='';
        tGatherIndPar varchar2(100) :='';
        tGatherTabNonPar varchar2(100) :='';
        tGatherIndNonPar varchar2(100) :='';
    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_all',1,sysdate,'sys.dba_rp.hc_all');
         commit;

     --dbms_output.put_line('Before if');
        --if (to_char(sysdate,'hh24') in ('00','08','13')) then
            --dbms_output.put_line('After if');
            select name into tDBName from v$database;
            tAll := tAll ||'<h2>BAO CAO CSDL ' || tDBName ||' NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss') ||'</h2>';

            --1.TAI DB
            select count(*) into nActiveSession from gv$session where username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','DBAVIETENGATE') and status='ACTIVE';

            select count(*) into nTotalActiveSession from gv$session where  status='ACTIVE';

            select count(*) into nTotalInactiveSession from gv$session where  status='INACTIVE';

            select count(*) into nTotalSession from gv$session;

            SELECT COUNT(*) INTO nLock FROM   gv$session  WHERE   blocking_session IS NOT NULL;

            sELECT   COUNT ( * ) INTO nLockDBLink FROM dba_2pc_pending where (retry_time-fail_time)*24*60>2;


            tAll := tAll|| '<br><b>SUMMARY SESSION:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1"><tr bgcolor="#FFF1D9" style="font-weight:bold"><td>nActiveSession</td><td>nTotalActiveSession</td><td>nTotalInactiveSession</td><td>nTotalSession</td><td>nLock</td><td>nLockDBLink</td></tr>';
            if nActiveSession > 200 then
                tAll := tAll||'<tr>
                                <td><font color="red"><b>'||nActiveSession||'</b></font></td>
                                <td>'||nTotalActiveSession||'</td>
                                <td>'||nTotalInactiveSession||'</td>
                                <td>'||nTotalSession||'</td>
                                <td>'||nLock||'</td>
                                <td>'||nLockDBLink||'</td>
                               </tr>'||'</table>';
            else
               tAll := tAll||'<tr>
                                <td>'||nActiveSession||'</td>
                                <td>'||nTotalActiveSession||'</td>
                                <td>'||nTotalInactiveSession||'</td>
                                <td>'||nTotalSession||'</td>
                                <td>'||nLock||'</td>
                                <td>'||nLockDBLink||'</td>
                               </tr>'||'</table>';
            end if;

            --1.3.Total session theo tung user
            tTotalUserSession :=tTotalUserSession||'
                                                    <br><b>USER SESSIONS DETAIL</b>:
                                                    <table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td>UserName</td>
                                                            <td>Status</td>
                                                            <td>Total Sesion</td>
                                                        </tr>';
            FOR r1 IN cTotalUserSession
            LOOP
                tTotalUserSession:=tTotalUserSession||'<tr>
                                                            <td>'||r1.username||'</td>
                                                            <td>'||r1.status||' </td>
                                                            <td>'||r1.num||'</td>
                                                        </tr>';

            END LOOP;
            tTotalUserSession:=tTotalUserSession||'</table>';

            tAll :=tAll || tTotalUserSession;

            --cdr_monitor.send_email_html_m('binhtv@mobifone.vn;tranbinh48ca@gmail.com','DBA_BILL_DBA MONITOR_' || sysdate, tAll);
            dbms_output.put_line('1');

            --CPU,RAM
            v_cpu_ram:=v_cpu_ram||'<br><b>CPU, RAM USAGE:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td> event_date</td>
                                                            <td> duration</td>
                                                            <td> server_name</td>
                                                            <td> cpu_idle</td>
                                                            <td> GB</td>
                                                        </tr>';
            for r11 in c_cpu_ram loop
                v_cpu_ram:=v_cpu_ram||'<tr>
                                        <td>'||to_char(r11.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r11.duration||'</td>
                                        <td>'||r11.server_name||'</td>
                                        <td>'||r11.cpu_idle||'</td>
                                        <td>'||r11.GB||'</td>
                                    </tr>' ;
            end loop;
            v_cpu_ram := v_cpu_ram || '</table>';
            tAll := tAll || v_cpu_ram;
            --dbms_output.put_line('2');

            --2.BACKUP: Lay 1 tuan
            tBackup:=tBackup||'<br><b>SUMMARY BACKUP:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td>command_id</td>
                                                            <td>start_time</td>
                                                            <td>end_time</td>
                                                            <td>status</td>
                                                            <td>INPUT_TYPE</td>
                                                            <td>input_bytes_display</td>
                                                            <td>output_bytes_display</td>
                                                            <td>time_taken_display</td>
                                                            <td>RATIO</td>
                                                            <td>input_bytes_per_sec_display</td>
                                                            <td>output_bytes_per_sec_display</td>
                                                        </tr>';
            for r1 in cBackup loop
                tBackup:=tBackup||'<tr>
                                        <td>'||r1.command_id||'</td>
                                        <td>'||to_char(r1.start_time,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||to_char(r1.end_time,'dd/mm/yyyy hh24:mm:ss')||' </td>
                                        <td>'||r1.status||' </td>
                                        <td>'||r1.INPUT_TYPE||'</td>
                                        <td>'||r1.input_bytes_display||'</td>
                                        <td>'||r1.output_bytes_display||'</td>
                                        <td>'||r1.time_taken_display||'</td>
                                        <td>'||r1.RATIO||'</td>
                                        <td>'||r1.input_bytes_per_sec_display||'</td>
                                        <td>'||r1.output_bytes_per_sec_display||'</td>
                                    </tr>' ;
            end loop;
            tBackup := tBackup || '</table>';
            tAll := tAll || tBackup;
            --dbms_output.put_line('2');

           --3.STORAGE
            tASM :='<br><b>ASM DISKGROUP:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td>name</td>
                    <td>state</td>
                    <td>type</td>
                    <td>total_gb</td>
                    <td>usable_file_gb</td>
                </tr>';

            for r2 in cASM loop
                tASM:=tASM||'<tr>
                                <td>'||r2.name||'</td>
                                <td>'||r2.state||'</td>
                                <td>'||r2.type||'</td>
                                <td>'||r2.total_gb||'</td>
                                <td>'||r2.usable_file_gb||'</td>
                             </tr>' ;
            end loop;
            tASM := tASM || '</table><br>';
            tAll := tAll || tASM;
            --dbms_output.put_line('3.tASM');

            tTBS :='<br><b>DUNG LUONG TABLESPACE:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Tablespace Name </td>
                    <td> %Usage </td>
                    <td> Size GB </td>
                    <td> Free GB </td>
                    <td> Used GB </td>
                    <td> %Free </td>
                    <td> Max GB </td>
                    <td> %Used Max </td>
                </tr>';
           --dbms_output.put_line('0');
           for r3 in cTBS loop
             if r3.pct_used_max > 90 then
                               tTBS:=tTBS||'<tr>
                                <td><font color="red"><b>'||r3.tablespace_name||'</b></font></td>
                                <td>'||r3.pct_usage||'</td>
                                <td>'||r3.size_gb||'</td>
                                <td>'||r3.free_gb||'</td>
                                <td>'||r3.used_gb||'</td>
                                <td>'||r3.pct_free||'</td>
                                <td>'||r3.max_gb||'</td>
                                <td><font color="red"><b>'||r3.pct_used_max||'</b></font></td>
                             </tr>' ;
            else
                tTBS:=tTBS||'<tr>
                                <td>'||r3.tablespace_name||'</td>
                                <td>'||r3.pct_usage||'</td>
                                <td>'||r3.size_gb||'</td>
                                <td>'||r3.free_gb||'</td>
                                <td>'||r3.used_gb||'</td>
                                <td>'||r3.pct_free||'</td>
                                <td>'||r3.max_gb||'</td>
                                <td>'||r3.pct_used_max||'</td>
                             </tr>' ;
            end if;
           end loop;
           --dbms_output.put_line('1:' || length(tTBS));
           tTBS := tTBS || '</table><br>';
           tAll := tAll || tTBS;
           --dbms_output.put_line('3.TBS');

           v_user_usage :='<br><b>DUNG LUONG THEO USER:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> User </td>
                    <td> GB </td>
                </tr>';
           --dbms_output.put_line('for r31 in c_user_usage loop');
           for r31 in c_user_usage loop
                if r31."GB" > 100 then
                    v_user_usage:=v_user_usage||'<tr>
                                                    <td><font color="red"><b>'||r31.owner||'</b></font></td>
                                                    <td><font color="red"><b>'||r31."GB"||'</b></font></td>
                                                 </tr>' ;
                else
                    v_user_usage:=v_user_usage||'<tr>
                                                    <td>'||r31.owner||'</td>
                                                    <td>'||r31."GB"||'</td>
                                                 </tr>' ;
                end if;
           end loop;
           --dbms_output.put_line('end loop;');
           v_user_usage := v_user_usage || '</table>';
           tAll := tAll || v_user_usage;
           --dbms_output.put_line('3.DUNG LUONG THEO USER');

           v_object_usage :='<br><b>DUNG LUONG THEO OBJECT:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> User</td>
                    <td> Segment_name/td>
                    <td> GB </td>
                </tr>';

           for r32 in c_object_usage loop
            if r32."GB" > 1000 then
                v_object_usage:=v_object_usage||'<tr>
                                <td><font color="red"><b>'||r32.owner||'</b></font></td>
                                 <td><font color="red"><b>'||r32.segment_name||'</b></font></td>
                                <td><font color="red"><b>'||r32."GB"||'</b></font></td>
                             </tr>' ;
            else
               v_object_usage:=v_object_usage||'<tr>
                                <td>'||r32.owner||'</td>
                                 <td>'||r32.segment_name||'</td>
                                <td>'||r32."GB"||'</td>
                             </tr>';
            end if;
           end loop;

           v_object_usage := v_object_usage || '</table>';
           tAll := tAll || v_object_usage;

           /*dbms_output.put_line('3.DUNG LUONG THEO OBJECT');
           --dbms_output.put_line('3');


           v_du :='<br><b>DUNG LUONG CAC PHAN VUNG OS:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Host_Name</td>
                    <td> Name</td>
                    <td> Size </td>
                    <td> Free </td>
                    <td> Percent </td>
                    <td> Mount Point </td>
                    <td> Event_Date </td>
                    <td> IP </td>
                </tr>';
           --dbms_output.put_line('v_object_usage');
           for r33 in c_du loop
            if(substr(r33.Disk_percen,-3,0) > 80) then
                v_du:=v_du||'<tr>
                                <td><font color="red"><b>'||r33.host_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.disk_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_size||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_free||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_percen||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_mount||'</b></font></td>
                                <td><font color="red"><b>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</b></font></td>
                                <td><font color="red"><b>'||r33.db_ip||'</b></font></td>
                             </tr>' ;
            else
               v_du:=v_du||'<tr>
                                <td>'||r33.host_name||'</td>
                                 <td>'||r33.disk_name||'</td>
                                <td>'||r33.Disk_size||'</td>
                                <td>'||r33.Disk_free||'</td>
                                <td>'||r33.Disk_percen||'</td>
                                <td>'||r33.Disk_mount||'</td>
                                <td>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                <td>'||r33.db_ip||'</td>
                             </tr>' ;
            end if;
           end loop;

           v_du := v_du || '</table>';
           tAll := tAll || v_du; */
           --dbms_output.put_line('3.DUNG LUONG THEO OS');
            --dbms_output.put_line('3.Completed');

           --4.Object invalid
           select count(*) into nInvalidObject from  (select 'ALTER '||OBJECT_TYPE||' '||OWNER||'.'||OBJECT_NAME||' COMPILE;'  from dba_objects
                        where object_type in ('PROCEDURE','FUNCTION','TRIGGER','PACKAGE') and status like 'INVALID'and OWNER in ('CDR_OWNER','CUS_OWNER','MC_OWNER')
                        UNION ALL
                        select 'ALTER PACKAGE '||OWNER||'.'||OBJECT_NAME||' COMPILE BODY;'  from dba_objects
                        where object_type in ('PACKAGE BODY') and status like 'INVALID' and OWNER like 'CDR_OWNER');

           tAll := tAll||'<br><b>OBJECT INVALID:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> So luong Object Invalid </td>
                    <td> So luong Index Partition UNUSABLE </td>
                    <td> So luong Index Non-Partition UNUSABLE </td>
                </tr>';

           --dbms_output.put_line('tAll: ' || length(tAll));
           tAll := tAll||'<tr>
                                <td>'||nInvalidObject||'</td>' ;
           --dbms_output.put_line('tAll: ' || length(tAll));

           --Index invalid: Partition, non-partition
           select count(*) into nUnuableIndNonPar from  dba_indexes where status='UNUSABLE';

           select count(*) into nUnuableIndPar  from dba_ind_partitions where status='UNUSABLE';

           tAll := tAll||'
                                <td>'||nUnuableIndPar||'</td>
                                <td>'||nUnuableIndNonPar||'</td>
                           </tr>' ;
           tAll := tAll || '</table>';

           --dbms_output.put_line('4');

           --5.Archive log trong 1 ngay hien tai
           tAll := tAll||'<br><b>ARCHIVE LOG TRONG 7 NGAY:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
            <tr bgcolor="#FFF1D9" style="font-weight:bold">
                <td> Completion_time </td>
                <td> Archived_Log_GB </td>
            </tr>';
           for r1 in (select trunc(completion_time) completion_time, round(sum(blocks*block_size)/1024/1024/1024,0) as archived_log_gb from V$ARCHIVED_LOG
                        where trunc(completion_time) >= trunc(sysdate-3)
                        --and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
                        and dest_id=1
                        group by trunc(completion_time)
                        order by trunc(completion_time) desc) loop
               if r1.archived_log_gb > 1000 then
                tAll:=tAll||'<tr>
                            <td><font color="red"><b>'||r1.completion_time||'</b></font></td>
                            <td><font color="red"><b>'||r1.archived_log_gb||'</b></font></td>
                         </tr>' ;

               else
                tAll:=tAll||'<tr>
                            <td>'||r1.completion_time||'</td>
                            <td>'||r1.archived_log_gb||'</td>
                         </tr>' ;
               end if;
           end loop;
           tAll:=tAll||'</table>';
           --dbms_output.put_line('5');

           --6.Gather
           tAll := tAll||'<br><b>GATHER:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
            <tr bgcolor="#FFF1D9" style="font-weight:bold">
                <td> tGatherTabPar </td>
                <td> tGatherIndPar </td>
                <td> tGatherTabNonPar </td>
                <td> tGatherIndNonPar </td>
            </tr>';
           select to_date(max(last_analyzed),'dd/mm/yyyy') into tGatherTabPar from dba_tab_partitions
            where table_owner in ('CDR_OWNER','CUS_OWNER','MC_OWNER') and last_analyzed<sysdate and last_analyzed>sysdate-7;

            select to_date(max(last_analyzed),'dd/mm/yyyy')  into tGatherIndPar from dba_ind_partitions
            where  index_owner in ('CDR_OWNER','CUS_OWNER','MC_OWNER') and last_analyzed<sysdate and last_analyzed>sysdate-7;

            -- Non-partition
            select to_date(max(last_analyzed),'dd/mm/yyyy')  into  tGatherTabNonPar from dba_tables
            where owner in ('CDR_OWNER','CUS_OWNER','MC_OWNER') and last_analyzed<sysdate and last_analyzed>sysdate-7  ;

            select to_date(max(last_analyzed),'dd/mm/yyyy')  into  tGatherIndNonPar from dba_indexes
            where owner in ('CDR_OWNER','CUS_OWNER','MC_OWNER') and last_analyzed<sysdate and last_analyzed>sysdate-7;

            tAll:=tAll||'<tr>
                        <td>'||tGatherTabPar||'</td>
                        <td>'||tGatherIndPar||'</td>
                        <td>'||tGatherTabNonPar||'</td>
                        <td>'||tGatherIndNonPar||'</td>
                     </tr>' ;

           tAll := tAll || '</table>';
           --dbms_output.put_line('6');
           --dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
            IF  nActiveSession >= 250 then
                cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','HIGH - HC_' || tDBName ||'_ALL NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
            ELSIF  nActiveSession > 200 and nActiveSession < 250 then
                cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','MID - HC_' || tDBName ||'_ALL NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
            ELSE
                cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','LOW - HC_' || tDBName ||'_ALL NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
            END IF;

           --send_sms_binhtv('sys.dba_rp.hc');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_all',1,sysdate,'sys.dba_rp.hc_all');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc: ' || SQLERRM);
             v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_all',-1,sysdate,'Error sys.dba_rp.hc_all, '||v_err);
            commit;
   END;

    PROCEDURE hc_backup
    is
        tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';

        --1.Tai DB
        nActiveSession number;
        nTotalActiveSession number; -- Ca background
        nTotalInactiveSession number;
        nTotalSession number;
        nLock number;
        nLockDBLink number;


        --2.Backup
        CURSOR cBackup
        IS
           select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,0) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
            from v$rman_backup_job_details
            where trunc(end_time)>=trunc(sysdate-30)
            order by end_time desc;
        tBackup varchar2(30000):='';


    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_backup',1,sysdate,'sys.dba_rp.hc_backup');
         commit;

     --dbms_output.put_line('Before if');
        --if (to_char(sysdate,'hh24') in ('00','08','13')) then
            --dbms_output.put_line('After if');
            select name into tDBName from v$database;
            tAll := tAll ||'<h2>BAO CAO BACKUP CSDL ' || tDBName ||' NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss') ||'</h2>';


            --2.BACKUP: Lay 30 ngay
            tBackup:=tBackup||'<br><b>SUMMARY BACKUP:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td>command_id</td>
                                                            <td>start_time</td>
                                                            <td>end_time</td>
                                                            <td>status</td>
                                                            <td>INPUT_TYPE</td>
                                                            <td>input_bytes_display</td>
                                                            <td>output_bytes_display</td>
                                                            <td>time_taken_display</td>
                                                            <td>RATIO</td>
                                                            <td>input_bytes_per_sec_display</td>
                                                            <td>output_bytes_per_sec_display</td>
                                                        </tr>';
            for r1 in cBackup loop
                tBackup:=tBackup||'<tr>
                                        <td>'||r1.command_id||'</td>
                                        <td>'||to_char(r1.start_time,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||to_char(r1.end_time,'dd/mm/yyyy hh24:mm:ss')||' </td>
                                        <td>'||r1.status||' </td>
                                        <td>'||r1.INPUT_TYPE||'</td>
                                        <td>'||r1.input_bytes_display||'</td>
                                        <td>'||r1.output_bytes_display||'</td>
                                        <td>'||r1.time_taken_display||'</td>
                                        <td>'||r1.RATIO||'</td>
                                        <td>'||r1.input_bytes_per_sec_display||'</td>
                                        <td>'||r1.output_bytes_per_sec_display||'</td>
                                    </tr>' ;
            end loop;
            tBackup := tBackup || '</table>';
            tAll := tAll || tBackup;
            --dbms_output.put_line('2');


           --dbms_output.put_line('6');
           dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
           cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','RP_' || tDBName ||'_BACKUP NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
           --send_sms_binhtv('sys.dba_rp.hc_backup');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_backup',1,sysdate,'sys.dba_rp.hc_backup');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_backup: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_backup',-1,sysdate,'Error sys.dba_rp.hc_backup, ' ||v_err);
            commit;
    end;

    --PROCEDURE hc_ddl;
    procedure hc_os
    is
        tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';


        cursor c_cpu_ram
        is
             select event_date, duration, server_name, cpu_idle, round(ram_free_k/1024/1024,0) "GB"
            from BINHTV.dbamf_ct_vmstat
            where event_date > sysdate-1/24
            and (cpu_idle <= 20 or round(ram_free_k/1024/1024,0) <=70)
            order by event_date desc;
        v_cpu_ram varchar2(30000):='';


        cursor c_du
        is
             select * from binhtv.dbamf_ct_disk_usage
                where event_date>sysdate-1
                and substr(disk_percen,-3,0)>'50'
                order by disk_percen desc;
        v_du varchar2(30000):='';

    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_os',1,sysdate,'sys.dba_rp.hc_os');
         commit;

            --CPU,RAM
            v_cpu_ram:=v_cpu_ram||'<br><b>CPU, RAM USAGE:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td> event_date</td>
                                                            <td> duration</td>
                                                            <td> server_name</td>
                                                            <td> cpu_idle</td>
                                                            <td> GB</td>
                                                        </tr>';
            for r11 in c_cpu_ram loop
                v_cpu_ram:=v_cpu_ram||'<tr>
                                        <td>'||to_char(r11.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r11.duration||'</td>
                                        <td>'||r11.server_name||'</td>
                                        <td>'||r11.cpu_idle||'</td>
                                        <td>'||r11.GB||'</td>
                                    </tr>' ;
            end loop;
            v_cpu_ram := v_cpu_ram || '</table>';
            tAll := tAll || v_cpu_ram;

           v_du :='<br><b>DUNG LUONG CAC PHAN VUNG OS:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Host_Name</td>
                    <td> Name</td>
                    <td> Size </td>
                    <td> Free </td>
                    <td> Percent </td>
                    <td> Mount Point </td>
                    <td> Event_Date </td>
                    <td> IP </td>
                </tr>';
           --dbms_output.put_line('v_object_usage');
           for r33 in c_du loop
            if(substr(r33.Disk_percen,-3,0) > 80) then
                v_du:=v_du||'<tr>
                                <td><font color="red"><b>'||r33.host_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.disk_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_size||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_free||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_percen||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_mount||'</b></font></td>
                                <td><font color="red"><b>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</b></font></td>
                                <td><font color="red"><b>'||r33.db_ip||'</b></font></td>
                             </tr>' ;
            else
               v_du:=v_du||'<tr>
                                <td>'||r33.host_name||'</td>
                                 <td>'||r33.disk_name||'</td>
                                <td>'||r33.Disk_size||'</td>
                                <td>'||r33.Disk_free||'</td>
                                <td>'||r33.Disk_percen||'</td>
                                <td>'||r33.Disk_mount||'</td>
                                <td>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                <td>'||r33.db_ip||'</td>
                             </tr>' ;
            end if;
           end loop;

           v_du := v_du || '</table>';
           tAll := tAll || v_du;


           --dbms_output.put_line('6');
           dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
           cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','RP' || tDBName ||'_OS NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
           --send_sms_binhtv('sys.dba_rp.hc_os');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_os',1,sysdate,'sys.dba_rp.hc_os');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_os',-1,sysdate,'Error sys.dba_rp.hc_os, '||v_err);
            commit;
   END;

    PROCEDURE hc_du
    is
        tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';

        cursor c_du
        is
             select * from binhtv.dbamf_ct_disk_usage
                where event_date>sysdate-1
                --and substr(disk_percen,-3,0)>'50'
                order by host_name asc,disk_percen desc;
        v_du varchar2(30000):='';


    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_du',1,sysdate,'sys.dba_rp.hc_du');
         commit;

     --dbms_output.put_line('Before if');
        --if (to_char(sysdate,'hh24') in ('00','08','13')) then
            --dbms_output.put_line('After if');
            select name into tDBName from v$database;
            tAll := tAll ||'<h2>BAO CAO CSDL ' || tDBName ||'_DU NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss') ||'</h2>';


           v_du :='<br><b>DUNG LUONG CAC PHAN VUNG OS:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Host_Name</td>
                    <td> Name</td>
                    <td> Size </td>
                    <td> Free </td>
                    <td> Percent </td>
                    <td> Mount Point </td>
                    <td> Event_Date </td>
                    <td> IP </td>
                </tr>';
           --dbms_output.put_line('v_object_usage');
           for r33 in c_du loop
            if(substr(r33.Disk_percen,-3,0) > 80) then
                v_du:=v_du||'<tr>
                                <td><font color="red"><b>'||r33.host_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.disk_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_size||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_free||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_percen||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_mount||'</b></font></td>
                                <td><font color="red"><b>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</b></font></td>
                                <td><font color="red"><b>'||r33.db_ip||'</b></font></td>
                             </tr>' ;
            else
               v_du:=v_du||'<tr>
                                <td>'||r33.host_name||'</td>
                                 <td>'||r33.disk_name||'</td>
                                <td>'||r33.Disk_size||'</td>
                                <td>'||r33.Disk_free||'</td>
                                <td>'||r33.Disk_percen||'</td>
                                <td>'||r33.Disk_mount||'</td>
                                <td>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                <td>'||r33.db_ip||'</td>
                             </tr>' ;
            end if;
           end loop;

           v_du := v_du || '</table>';
           tAll := tAll || v_du;

           --dbms_output.put_line('6');
           --dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
           cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','HC_' || tDBName ||'_DU NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
           --send_sms_binhtv('sys.dba_rp.hc_du');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_du',1,sysdate,'sys.dba_rp.hc_du');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_du: ' || SQLERRM);
            --v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_du',-1,sysdate,'Error sys.dba_rp.hc_du, '||v_err);
            commit;
    end;

    PROCEDURE hc_storage
    is
       tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';


        --2.Backup
        CURSOR cBackup
        IS
           select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,0) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
            from v$rman_backup_job_details
            where trunc(end_time)>=trunc(sysdate-3)
            order by end_time desc;
        tBackup varchar2(30000):='';

         --3.Storage
         cursor cASM is
             select name, state, type, total_mb, usable_file_mb from v$asm_diskgroup;
         tASM varchar2(30000) := '';

         cursor cTBS is
            SELECT  a.tablespace_name,100 - ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) pct_usage,   ROUND(a.bytes_alloc / 1024 / 1024) size_mb,   ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) free_mb,
                  (ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024)) used_mb, ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) pct_free, ROUND (maxbytes / 1048576)  max_mb,
                   ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100) as pct_used_max
              FROM (  SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
                        FROM dba_data_files f
                    GROUP BY tablespace_name) a,
                   (  SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
             WHERE a.tablespace_name = b.tablespace_name(+)
             --and a.tablespace_name in ('DATA','INDX')
             and ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100)  > 85
             order by pct_used_max desc;
         tTBS varchar2(30000) := '';

         cursor c_user_usage is
             select owner,round(sum(bytes)/1024/1024/1024,0) "GB" from dba_segments
             group by owner
              having round(sum(bytes)/1024/1024/1024,0)  > 50
             order by "GB" desc;
         v_user_usage varchar2(30000) := '';


        cursor c_object_usage is
             select owner,segment_name,round(sum(bytes)/1024/1024/1024,0) "GB" from dba_segments
             group by owner, segment_name
             having round(sum(bytes)/1024/1024/1024,0)  > 100
             order by "GB" desc;
         v_object_usage varchar2(3000) := '';

          -- Cac tablespace Read Only:Chay lau
    /*      cursor cTBS_RO is
              select tablespace_name, round(sum(bytes)/1024/1024/1024,0) "GB"
                from dba_segments
                where tablespace_name in (select name from v$tablespace where ts# in (select ts# from v$datafile where enabled='READ ONLY'))
                group by tablespace_name
                order by tablespace_name ;
        tStorage varchar2(4000):='';*/

        cursor c_du
        is
             select * from binhtv.dbamf_ct_disk_usage
                where event_date>sysdate-1
                and substr(disk_percen,-3,0)>'50'
                order by disk_percen desc;
        v_du varchar2(30000):='';


         --6.Archive log
         -- Theo doi archived log sinh ra
        cursor cTotalArchivedLog is
            select trunc(completion_time), round(sum(blocks*block_size)/1024/1024/1024,0) "Archived Log GB" from V$ARCHIVED_LOG
            where trunc(completion_time) >= trunc(sysdate-1)
            --and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
            and dest_id=1
            group by trunc(completion_time)
            order by trunc(completion_time) desc;

        -- Archived log sinh ra theo gio
        cursor cHourArchivedLog is
        select to_char(next_time,'YYYY-MM-DD hh24') Hour, round(sum(size_in_byte)/1024/1024,0) as size_in_mb, count(*) log_switch from (
        select thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE as size_in_byte, next_time
        from v$archived_log where name is not null and completion_time>sysdate-1 group by thread# ,sequence#, FIRST_CHANGE#,blocks*BLOCK_SIZE, next_time)
        group by to_char(next_time,'YYYY-MM-DD hh24') order by 1 desc;

        tArchivedLog varchar2(30000):='';



    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_storage',1,sysdate,'sys.dba_rp.hc_storage');
         commit;

     --dbms_output.put_line('Before if');
        --if (to_char(sysdate,'hh24') in ('00','08','13')) then
            --dbms_output.put_line('After if');
            select name into tDBName from v$database;
            tAll := tAll ||'<h2>BAO CAO STORAGE CSDL ' || tDBName ||' NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss') ||'</h2>';

            --2.BACKUP: Lay 1 tuan
            tBackup:=tBackup||'<br><b>SUMMARY BACKUP:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td>command_id</td>
                                                            <td>start_time</td>
                                                            <td>end_time</td>
                                                            <td>status</td>
                                                            <td>INPUT_TYPE</td>
                                                            <td>input_bytes_display</td>
                                                            <td>output_bytes_display</td>
                                                            <td>time_taken_display</td>
                                                            <td>RATIO</td>
                                                            <td>input_bytes_per_sec_display</td>
                                                            <td>output_bytes_per_sec_display</td>
                                                        </tr>';
            for r1 in cBackup loop
                tBackup:=tBackup||'<tr>
                                        <td>'||r1.command_id||'</td>
                                        <td>'||to_char(r1.start_time,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||to_char(r1.end_time,'dd/mm/yyyy hh24:mm:ss')||' </td>
                                        <td>'||r1.status||' </td>
                                        <td>'||r1.INPUT_TYPE||'</td>
                                        <td>'||r1.input_bytes_display||'</td>
                                        <td>'||r1.output_bytes_display||'</td>
                                        <td>'||r1.time_taken_display||'</td>
                                        <td>'||r1.RATIO||'</td>
                                        <td>'||r1.input_bytes_per_sec_display||'</td>
                                        <td>'||r1.output_bytes_per_sec_display||'</td>
                                    </tr>' ;
            end loop;
            tBackup := tBackup || '</table>';
            tAll := tAll || tBackup;
            --dbms_output.put_line('2');

           --3.STORAGE
            tASM :='<br><b>ASM DISKGROUP:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td>name</td>
                    <td>state</td>
                    <td>type</td>
                    <td>total_mb</td>
                    <td>usable_file_mb</td>
                </tr>';

            for r2 in cASM loop
                tASM:=tASM||'<tr>
                                <td>'||r2.name||'</td>
                                <td>'||r2.state||'</td>
                                <td>'||r2.type||'</td>
                                <td>'||r2.total_mb||'</td>
                                <td>'||r2.usable_file_mb||'</td>
                             </tr>' ;
            end loop;
            tASM := tASM || '</table><br>';
            tAll := tAll || tASM;
            --dbms_output.put_line('3.tASM');

            tTBS :='<br><b>TABLESPACE:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Tablespace Name </td>
                    <td> %Usage </td>
                    <td> Size MB </td>
                    <td> Free MB </td>
                    <td> Used MB </td>
                    <td> %Free </td>
                    <td> Max MB </td>
                    <td> %Used Max </td>
                </tr>';
           --dbms_output.put_line('0');
           for r3 in cTBS loop
                tTBS:=tTBS||'<tr>
                                <td>'||r3.tablespace_name||'</td>
                                <td>'||r3.pct_usage||'</td>
                                <td>'||r3.size_mb||'</td>
                                <td>'||r3.free_mb||'</td>
                                <td>'||r3.used_mb||'</td>
                                <td>'||r3.pct_free||'</td>
                                <td>'||r3.max_mb||'</td>
                                <td>'||r3.pct_used_max||'</td>
                             </tr>' ;
           end loop;
           --dbms_output.put_line('1:' || length(tTBS));
           tTBS := tTBS || '</table><br>';
           tAll := tAll || tTBS;
           --dbms_output.put_line('3.TBS');

           v_user_usage :='<br><b>DUNG LUONG THEO USER:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> User </td>
                    <td> GB </td>
                </tr>';
           --dbms_output.put_line('for r31 in c_user_usage loop');
           for r31 in c_user_usage loop
                if r31."GB" > 100 then
                    v_user_usage:=v_user_usage||'<tr>
                                                    <td><font color="red"><b>'||r31.owner||'</b></font></td>
                                                    <td><font color="red"><b>'||r31."GB"||'</b></font></td>
                                                 </tr>' ;
                else
                    v_user_usage:=v_user_usage||'<tr>
                                                    <td>'||r31.owner||'</td>
                                                    <td>'||r31."GB"||'</td>
                                                 </tr>' ;
                end if;
           end loop;
           --dbms_output.put_line('end loop;');
           v_user_usage := v_user_usage || '</table>';
           tAll := tAll || v_user_usage;

           v_object_usage :='<br><b>DUNG LUONG THEO OBJECT:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> User</td>
                    <td> Segment_name/td>
                    <td> GB </td>
                </tr>';
           --dbms_output.put_line('v_object_usage');
           for r32 in c_object_usage loop
            if r32."GB" > 1000 then
                v_object_usage:=v_object_usage||'<tr>
                                <td><font color="red"><b>'||r32.owner||'</b></font></td>
                                 <td><font color="red"><b>'||r32.segment_name||'</b></font></td>
                                <td><font color="red"><b>'||r32."GB"||'</b></font></td>
                             </tr>' ;
            else
               v_object_usage:=v_object_usage||'<tr>
                                <td>'||r32.owner||'</td>
                                 <td>'||r32.segment_name||'</td>
                                <td>'||r32."GB"||'</td>
                             </tr>';
            end if;
           end loop;

           v_object_usage := v_object_usage || '</table>';
           tAll := tAll || v_object_usage;

           --dbms_output.put_line('1:' || length(v_user_usage));
           --dbms_output.put_line('3');


           v_du :='<br><b>DUNG LUONG CAC PHAN VUNG OS:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                <tr bgcolor="#FFF1D9" style="font-weight:bold">
                    <td> Host_Name</td>
                    <td> Name</td>
                    <td> Size </td>
                    <td> Free </td>
                    <td> Percent </td>
                    <td> Mount Point </td>
                    <td> Event_Date </td>
                    <td> IP </td>
                </tr>';
           --dbms_output.put_line('v_object_usage');
           for r33 in c_du loop
            if(substr(r33.Disk_percen,-3,0) > 80) then
                v_du:=v_du||'<tr>
                                <td><font color="red"><b>'||r33.host_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.disk_name||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_size||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_free||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_percen||'</b></font></td>
                                <td><font color="red"><b>'||r33.Disk_mount||'</b></font></td>
                                <td><font color="red"><b>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</b></font></td>
                                <td><font color="red"><b>'||r33.db_ip||'</b></font></td>
                             </tr>' ;
            else
               v_du:=v_du||'<tr>
                                <td>'||r33.host_name||'</td>
                                 <td>'||r33.disk_name||'</td>
                                <td>'||r33.Disk_size||'</td>
                                <td>'||r33.Disk_free||'</td>
                                <td>'||r33.Disk_percen||'</td>
                                <td>'||r33.Disk_mount||'</td>
                                <td>'||to_char(r33.event_date,'dd/mm/yyyy hh24:mm:ss')||'</td>
                                <td>'||r33.db_ip||'</td>
                             </tr>' ;
            end if;
           end loop;

           v_du := v_du || '</table>';
           tAll := tAll || v_du;



           --5.Archive log trong 1 ngay hien tai
           tAll := tAll||'<br><b>ARCHIVE LOG TRONG 7 NGAY:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
            <tr bgcolor="#FFF1D9" style="font-weight:bold">
                <td> Completion_time </td>
                <td> Archived_Log_GB </td>
            </tr>';
           for r1 in (select trunc(completion_time) completion_time, round(sum(blocks*block_size)/1024/1024/1024,0) as archived_log_gb from V$ARCHIVED_LOG
                        where trunc(completion_time) >= trunc(sysdate-7)
                        --and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
                        and dest_id=1
                        group by trunc(completion_time)
                        order by trunc(completion_time) desc) loop
               if r1.archived_log_gb > 1000 then
                tAll:=tAll||'<tr>
                            <td><font color="red"><b>'||r1.completion_time||'</b></font></td>
                            <td><font color="red"><b>'||r1.archived_log_gb||'</b></font></td>
                         </tr>' ;

               else
                tAll:=tAll||'<tr>
                            <td>'||r1.completion_time||'</td>
                            <td>'||r1.archived_log_gb||'</td>
                         </tr>' ;
               end if;
           end loop;
           tAll:=tAll||'</table>';
           --dbms_output.put_line('5');


           --dbms_output.put_line('6');
           dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
           cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','HC_' || tDBName ||'_STORAGE NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
           send_sms_binhtv('sys.dba_rp.hc_storage');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_storage',1,sysdate,'sys.dba_rp.hc_storage');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_storage: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_storage',-1,sysdate,'Error sys.dba_rp.hc_storage, '||v_err);
            commit;
    end;

   PROCEDURE hc_sms
    is
         v_active_session number :=0;
        v_total_active_session number := 0;
        v_total_session number := 0;
        v_lock number := 0;
        v_backup_status varchar2(100) := 'Fail' ;
        v_count_backup number;
        v_tbl_par_date1  varchar2(100) :='';
        v_tbl_non_par_date1   varchar2(100) :='';
        v_all varchar2(1000) := '';
        v_tbs varchar2(20) := '';
        v_used_max number := 0;
        V_TBL_NON_PAR_DATE varchar2(50) :='';
        V_TBL_PAR_DATE varchar2(50) := '';
        V_INVALID_OBJ number := 0;
        v_err varchar2(1000):='';

        cursor c_tbs is
            SELECT  a.tablespace_name,ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100)  as pct_used_max
            FROM (  SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
                    FROM dba_data_files f
                GROUP BY tablespace_name) a,
               (  SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
            WHERE a.tablespace_name = b.tablespace_name(+)
            and ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100)>96;

        cursor c_archived_log is
            select trunc(completion_time) as completion_time, round(sum(blocks*block_size)/1024/1024/1024,0) as archived_log from V$ARCHIVED_LOG
            where trunc(completion_time) >= trunc(sysdate-1)
            --and trunc(completion_time)>= to_date(trunc(sysdate),'dd/mm/yyyy')
            and dest_id=1
            group by trunc(completion_time)
            order by trunc(completion_time) desc;
    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_sms',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;
        --select to_char(sysdate,'hh')  from dual;

        --if (to_char(sysdate,'hh24') in ('08','17')) then
            select count(*) into v_active_session from gv$session where  status='ACTIVE' and username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','DBAVIETENGATE') and type != 'BACKGROUND' AND TYPE = 'USER' ;

            select count(*) into v_total_active_session from gv$session where  status='ACTIVE';

            select count(*) into v_total_session from gv$session;

            Select count(*) into v_lock  From gv$session where blocking_session is not NULL and type not like 'BACKGROUND';
            v_all := v_all || 'DBAVIET_HC_' || to_char(sysdate,'dd/mm hh24:mi')||':Active ('||v_active_session || '),TAS('||v_total_active_session||'),TS('||v_total_session||'),Lock('||v_lock||')';
            --dbms_output.put_line('1.'||v_all);

            --2.BACKUP
        --    select command_id, start_time, end_time, status,INPUT_TYPE, input_bytes_display, output_bytes_display, time_taken_display, round(compression_ratio,0) RATIO , input_bytes_per_sec_display, output_bytes_per_sec_display
        --    from v$rman_backup_job_details
        --    where trunc(end_time)>=trunc(sysdate)
        --    order by end_time desc;

        --    select  substr(output_bytes_display,1,8) from v$rman_backup_job_details
        --    where trunc(end_time)>=trunc(sysdate)
        --    order by end_time desc;

            select count(1) into v_count_backup
            from v$rman_backup_job_details
            where trunc(end_time)>=trunc(sysdate)
            and to_number(trunc(substr(output_bytes_display,1,8)),'999')>0
            order by end_time desc;

            if v_count_backup > 0  then
                v_backup_status := substr(v_backup_status,1,3);
            end if;

            v_all := v_all ||',Backup('|| v_backup_status ||')';
            --dbms_output.put_line('2.'||v_all);

           --3.STORAGE      --19s
            for r_tbs in c_tbs loop
                v_all := v_all || ',Storage('||r_tbs.tablespace_name || ':'||r_tbs.pct_used_max ||'%';
            end loop;
            v_all := v_all || '),';
            --dbms_output.put_line('3.'||v_all);

            --4.ARCHIVE_LOG
             v_all := v_all || 'ARC(';
            for r_archived_log in c_archived_log loop
                v_all := v_all ||to_char(r_archived_log.completion_time,'dd/mm')||':'||r_archived_log.archived_log ||',';
            end loop;
            v_all := v_all || '),';
            --dbms_output.put_line('4.'||v_all);

            --5.ANALYZE
            select last_analyzed into v_tbl_par_date1 from dba_tab_partitions
            where table_owner='CUS_OWNER' and last_analyzed>sysdate-1
            and rownum=1
            order by last_analyzed desc;
            --dbms_output.put_line('5.1_Pre'||v_all);
            v_all := v_all || 'Table par:' ||v_tbl_par_date1 || ',';
            --dbms_output.put_line('5.1_Post'||v_all);

            select last_analyzed into v_tbl_non_par_date1  from dba_tables
            where owner='CUS_OWNER' and last_analyzed>sysdate-1
            and rownum=1
            order by last_analyzed desc;

            v_all := v_all || 'Table non_par:' ||v_tbl_non_par_date1 ||',';
            --dbms_output.put_line('5.2'||v_all);

            --6.INVALID OBJ
            select count(*) into v_invalid_obj from (select 'ALTER '||OBJECT_TYPE||' '||OWNER||'.'||OBJECT_NAME||' COMPILE;' from dba_objects
            where object_type in ('PROCEDURE','FUNCTION','TRIGGER','PACKAGE') and status like 'INVALID'and OWNER like 'CUS_OWNER'
            UNION ALL
            select 'ALTER PACKAGE '||OWNER||'.'||OBJECT_NAME||' COMPILE BODY;' from dba_objects
            where object_type in ('PACKAGE BODY') and status like 'INVALID' and OWNER like 'CUS_OWNER');
            v_all := v_all || 'Invalid Obj:'|| v_invalid_obj;
            --dbms_output.put_line('6.'||v_all);
            send_sms_binhtv(v_all);
            --send_sms_binhtv('sys.dba_rp.hc_sms');

         --end if;

         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_sms',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_sms: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_sms',-1,sysdate,'Error sys.dba_rp.hc_sms, '||v_err);
            commit;
   END;

    PROCEDURE session_sms
    is
        nActiveSession number;
        nTotalActiveSession number; -- Ca background
        nTotalInactiveSession number;
        nTotalSession number;
        nLock number;
        v_err varchar2(1000);
       --strBackup varchar2(50);
    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.session_sms',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;

          --1.SESSION
        /*SELECT distinct s.inst_id i#, s.username, s.SID SID, s.osuser, s.machine,DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') ACTION,
        s.sql_id, SUBSTR(DECODE(SS.SQL_TEXT, NULL, AA.NAME, SS.SQL_TEXT), 1, 1000) SQLTEXT,s.logon_time,s.p1text, S.P1, s.p2text, S.P2, s.p3text, S.P3
        FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
        WHERE  S.STATUS = 'ACTIVE' AND S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND and s.type != 'BACKGROUND' AND S.TYPE = 'USER'
        and s.username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','DBAVIETENGATE')
        --AND username in 'SYS'
        --and DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') like '%cell single block physical read%'
        --and lower(ss.sql_text) like lower('%parallel%')
        --and s.sid=1234
        --and s.machine like '%BINHTV%'
        --and s.sql_id ='ccwg0nqr1zbu7'
        ORDER BY username,sql_id; */

        if (to_char(sysdate,'hh24') in ('07','08','09','10','11','14','15''16','17','18','19','20','21')) then
          select count(*) into nActiveSession from gv$session where  status='ACTIVE' and username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','DBAVIETENGATE') and type != 'BACKGROUND' AND TYPE = 'USER' ;

          select count(*) into nTotalActiveSession from gv$session where  status='ACTIVE';

          select count(*) into nTotalSession from gv$session;

          Select count(*) into nLock  From gv$session where blocking_session is not NULL and type not like 'BACKGROUND';

          send_sms_all('DBA_DBAVIET','DBAVIET_HeathCheck: ActiveSession ('||nActiveSession || '),TotalActiveSession('||nTotalActiveSession||'),TotalSession('||nTotalSession||'),Lock('||nLock||'),' ||to_char(sysdate,'dd/mm/yyyy hh24:mi:ss'));
          --sys.send_sms_ht('DBA_DBAVIET','DBAVIET_HeathCheck:' || chr(10) || 'ActiveSession: ('||nActiveSession || ');' || chr(10) ||'TotalActiveSession:('||nTotalActiveSession||');' || chr(10) ||'TotalSession:('||nTotalSession||');' || chr(10) ||'Lock:('||nLock||');' || chr(10) || 'Report time:' ||to_char(sysdate,'dd/mm/yyyy hh24:mi:ss'));
          --send_sms_binhtv('DBAVIET_HeathCheck:' || chr(10) || 'ActiveSession: ('||nActiveSession || ');' || chr(10) ||'TotalActiveSession:('||nTotalActiveSession||');' || chr(10) ||'TotalSession:('||nTotalSession||');' || chr(10) ||'Lock:('||nLock||');' || chr(10) || 'Report time:' ||to_char(sysdate,'dd/mm/yyyy hh24:mi:ss'));
          --dbms_output.put_line('DBAVIET_HeathCheck:' || chr(10) || 'ActiveSession: ('||nActiveSession || ');' || chr(10) ||'TotalActiveSession:('||nTotalActiveSession||');' || chr(10) ||'TotalSession:('||nTotalSession||');' || chr(10) ||'Lock:('||nLock||');' || chr(10) || 'Report time:' ||to_char(sysdate,'dd/mm/yyyy hh24:mi:ss'));
      end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.session_sms',1,sysdate,'binhtv.dbamf_log_jobs');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.session_sms: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.session_sms',-1,sysdate,'Error sys.dba_rp.session_sms, '||v_err);
            commit;
   END;

    -- Chay cuoi ngay, Bao cao object sai quy dinh, quyen tac dong, ddl
    procedure hc_ddl_log
    is
       v_all varchar2(30000):='';
        v_db_name varchar2(20):='';
        v_err varchar2(1000):='';

        --1.Thong ke all theo user_name
        cursor c_all
        is
           select trunc(ddl_date) "event_date",count(*) num from ddl_log
           where ddl_date >= sysdate-7
           --and object_name not in ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
           --and owner='CUS_OWNER'
           group by  trunc(ddl_date)
           order by trunc(ddl_date)  desc;

        --2.Th?ng k?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Âª theo user_name theo ng?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Â y CUS_OWNER
        cursor c_cus_user
        is
           select trunc(ddl_date) "event_date",user_name,count(*) num from ddl_log
           where ddl_date >= sysdate-1
           --and object_name not in ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
           and owner='CUS_OWNER'
           group by  trunc(ddl_date),user_name
           order by trunc(ddl_date) desc, num desc;

        --3.Th?ng k?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Âª theo user_name theo ng?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Â y CUS_OWNER tr? ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
        cursor c_cus_user_min
        is
           select trunc(ddl_date) "event_date",user_name,count(*) num from ddl_log
           where ddl_date >= trunc(sysdate-1)
           and object_name not in ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
           and owner='CUS_OWNER'
           group by trunc(ddl_date),user_name
           order by trunc(ddl_date), num desc;

        --4.Thong ke theo object_type tr? ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
        -- Chi CUS_OWNER
        cursor c_cus_obj_type
        is
           select trunc(ddl_date) "event_date",object_type,count(*) num from ddl_log
           where ddl_date >= trunc(sysdate-1)
           and object_name not in ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
           and owner='CUS_OWNER'
           group by trunc(ddl_date),object_type
           order by trunc(ddl_date), num desc;

        --5..Thong ke theo object_type tr? ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
        -- Chi CUS_OWNER
        -- NOT: ('CALLCENTER_BEA','PAYMENT_GATEWAY','PAYMENT')
        cursor c_cus_obj_type_min
        is
           select trunc(ddl_date) "event_date",object_type,count(*) num from ddl_log
           where ddl_date >= trunc(sysdate-1)
           and object_name not in ('GLOBAL_B4_SUB_USAGE_ITEM','RP_VERIFY_NEW_SUBS','RP_CUSTS_NOT_PAID_ACT')
           and owner='CUS_OWNER'
           and user_name not in ('CALLCENTER_BEA','PAYMENT_GATEWAY','PAYMENT')
           group by trunc(ddl_date),object_type
           order by trunc(ddl_date), num desc;
    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_ddl_log',1,sysdate,'sys.dba_rp.hc_ddl_log');
         commit;
    --dbms_output.put_line('length:'||length(v_all));
        --if (to_char(sysdate,'hh24') in ('08','17')) then
            select name into v_db_name from v$database;
            v_all := v_all ||'<h2>BAO CAO DDL_LOG ' || v_db_name ||' NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss') ||'</h2>';

            --1.ALL
            v_all:=v_all||'<br><b>1.DDL LOG TRONG 7 NGAY GAN NHAT:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                   <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                       <td>Ngay thong ke</td>
                                                       <td>So luong</td>
                                                   </tr>';
            for r1 in c_all loop
                v_all:=v_all||'<tr>
                                        <td>'||to_char(r1."event_date",'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r1.num||'</td>
                               </tr>' ;
            end loop;
            v_all := v_all || '</table>';
            --dbms_output.put_line('1.length:'||length(v_all));

            --2.c_cus_user
            v_all:=v_all||'<br><b>2.DDL LOG theo ngay, user_name theo ng?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Â y cua CUS_OWNER:</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                   <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                       <td>Ngay thong ke</td>
                                                       <td>User_name</td>
                                                       <td>So luong</td>
                                                   </tr>';
            for r2 in c_cus_user loop
                v_all:=v_all||'<tr>
                                        <td>'||to_char(r2."event_date",'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r2.user_name||'</td>
                                        <td>'||r2.num||'</td>
                               </tr>' ;
            end loop;
            v_all := v_all || '</table>';
           --dbms_output.put_line('2.length:'||length(v_all));

            --3.c_cus_user_min
            v_all:=v_all||'<br><b>3.DDL LOG theo user_name theo ng?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?¢â‚¬Â ?ƒÂ¢?¢â€?Â¬?¢â€?Â¢?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?‚Â ?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒÂ¢?¢â‚¬Å¾?‚Â¢?ƒÆ’?†â€™?ƒâ€ ?¢â‚¬â„¢?ƒÆ’?‚Â¢?ƒÂ¢?¢â‚¬Å¡?‚Â¬?ƒâ€¦?‚Â¡?ƒÆ’?†â€™?ƒÂ¢?¢â€?Â¬?…Â¡?ƒÆ’?¢â‚¬Å¡?ƒâ€??‚Â y cua CUS_OWNER, Tru (GLOBAL_B4_SUB_USAGE_ITEM,RP_VERIFY_NEW_SUBS,RP_CUSTS_NOT_PAID_ACT):</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                   <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                       <td>Ngay thong ke</td>
                                                       <td>User_name</td>
                                                       <td>So luong</td>
                                                   </tr>';
            for r3 in c_cus_user_min loop
                v_all:=v_all||'<tr>
                                        <td>'||to_char(r3."event_date",'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r3.user_name||'</td>
                                        <td>'||r3.num||'</td>
                               </tr>' ;
            end loop;
            v_all := v_all || '</table>';
           --dbms_output.put_line('3.length:'||length(v_all));

            --4.c_cus_obj_type
            v_all:=v_all||'<br><b>4.DDL LOG theo object_type cua CUS_OWNER, Tru (GLOBAL_B4_SUB_USAGE_ITEM,RP_VERIFY_NEW_SUBS,RP_CUSTS_NOT_PAID_ACT):</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                   <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                       <td>Ngay thong ke</td>
                                                       <td>Object_type</td>
                                                       <td>So luong</td>
                                                   </tr>';
            for r4 in c_cus_obj_type loop
                v_all:=v_all||'<tr>
                                        <td>'||to_char(r4."event_date",'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r4.object_type||'</td>
                                        <td>'||r4.num||'</td>
                               </tr>' ;
            end loop;
            v_all := v_all || '</table>';
            --dbms_output.put_line('4.length:'||length(v_all));

            --5.c_cus_obj_type_min
            v_all:=v_all||'<br><b>4.DDL LOG theo object_type cua CUS_OWNER, Tru (GLOBAL_B4_SUB_USAGE_ITEM,RP_VERIFY_NEW_SUBS,RP_CUSTS_NOT_PAID_ACT), Tru user_name tac dong (CALLCENTER_BEA,PAYMENT_GATEWAY,PAYMENT):</b><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                   <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                       <td>Ngay thong ke</td>
                                                       <td>Object_type</td>
                                                       <td>So luong</td>
                                                   </tr>';
            for r5 in c_cus_obj_type_min loop
                v_all:=v_all||'<tr>
                                        <td>'||to_char(r5."event_date",'dd/mm/yyyy hh24:mm:ss')||'</td>
                                        <td>'||r5.object_type||'</td>
                                        <td>'||r5.num||'</td>
                               </tr>' ;
            end loop;
            v_all := v_all || '</table>';

           --dbms_output.put_line('5.length:'||length(v_all));
           cdr_monitor.send_email_html_m('tranbinh48ca@gmail.com','HC_' || v_db_name ||'_DDL_LOG NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), v_all);
           --sys.dba_rp.send_sms_binhtv('sys.dba_rp.rpt_ddl_log');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_ddl_log',1,sysdate,'sys.dba_rp.hc_ddl_log');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_ddl_log: ' || SQLERRM);
            v_err := substr(SQLERRM,1,200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_ddl_log',-1,sysdate,'Error sys.dba_rp.hc_ddl_log, '||v_err);
            commit;
   END;


   PROCEDURE hc_fga_log
    is
        tAll varchar2(32700):='';
        tAll_New varchar2(10000):='';
        tDBName varchar2(20):='';
        v_err varchar2(1000):='';

        --1.Tai DB
        ndb_user varchar2(500);
        nstatement_type  varchar2(500);
        nCount number;

        --2.Backup
        CURSOR cFGA
        IS
           select db_user, statement_type,count(*)  "Count" from DBA_FGA_AUDIT_TRAIL
            where  timestamp >= sysdate-1
            group by db_user, statement_type
            order by  "Count"  desc,statement_type, db_user;

        tFGA varchar2(30000):='';

    BEGIN
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Starting sys.dba_rp.hc_fga',1,sysdate,'sys.dba_rp.hc_fga');
         commit;
        select name into tDBName from v$database;
     --dbms_output.put_line('Before if');
        --if (to_char(sysdate,'hh24') in ('00','08','13')) then
            --dbms_output.put_line('After if');
            select name into tDBName from v$database;
            tAll := tAll || '<h2>BAO CAO TRUY CAP CSDL ' || tDBName || ' NGAY ' || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss')  || '</h2>';


            --2.BACKUP: Lay 30 ngay
            tFGA:=tFGA||'<br><table width="600"  border ="1" cellspacing="1" cellpadding="1">
                                                        <tr bgcolor="#FFF1D9" style="font-weight:bold">
                                                            <td>User_name</td>
                                                            <td>Cau lenh</td>
                                                            <td>So luong</td>
                                                        </tr>';
            for r1 in cFGA loop
                tFGA:=tFGA||'<tr>
                                        <td>'||r1.db_user||'</td>
                                        <td>'||r1.statement_type||'</td>
                                        <td>'||r1."Count"||' </td>
                                    ' ;
            end loop;
            --tFGA := tFGA ||  '</table>';
            tAll := tAll || tFGA;
            --dbms_output.put_line('2');


           --dbms_output.put_line('6');
           dbms_output.put_line('tAll: '||length(tAll));
           --execute immediate 'truncate table tc_monior_lob';
           --insert into tc_monior_lob(text) values(tAll);
           --commit;
           --select text into tAll_New from tc_monior_lob;
           CUS_OWNER.send_email_html_clob('tranbinh48ca@gmail.com', 'BAO CAO TRUY CAP CSDL ' ||tDBName ||' '  || to_char(sysdate,'dd/mm/yyyy hh24:mm:ss'), tAll);
           
        --send_sms_binhtv('sys.dba_rp.hc_backup');
        --end if;
         insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
            values(binhtv.dbamf_log_jobs_seq.nextval,'Completed sys.dba_rp.hc_fga',1,sysdate,'sys.dba_rp.hc_fga');
         commit;

   EXCEPTION
        WHEN others THEN
            send_sms_binhtv('Error sys.dba_rp.hc_fga: ' || SQLERRM);
            v_err := SUBSTR(SQLERRM, 1, 200);
            insert into binhtv.dbamf_log_jobs (id,name,status,event_date, note)
                values(binhtv.dbamf_log_jobs_seq.nextval,'Error sys.dba_rp.hc_fga',-1,sysdate,'Error sys.dba_rp.hc_fga, ' ||v_err);
            commit;
    end;


end;
/
