--[VIP] Gather, Analyze Cơ sở dữ liệu Oracle từ A-Z
--I. Tầm quan trọng của Optimizer Statistics
--Nếu thông tin gather không đầy đủ thì Plan câu lệnh SQL sai --> Hiệu năng DB kém
--Sau khi có thông tin gather thì cơ bản Oracle sẽ xác định Plan chuẩn -->  Tăng hiệu năng của cơ sở dữ liệu
--Các thông tin sau khi gather:
--• Cỡ của bảng và index trong
--• Số row
--• Cỡ trung bình của row và các chain
--• Số row đã bị xóa trong lá của index
--Khi dữ liệu được insert, delete hay chỉnh sửa thì thông tin thực tế đã thay đổi so với lần gather gần nhất.
--
--Để không bị ghi đè thông tin statistic thì lock statistics của object lại.
--
--  II.  Lưu ý khi gather
-- Check stale
select * from dba_tab_statistics where owner='OAZ17' --and table_name='TAB1'
and stale_stats='YES';

----Estimate_Percent
----AUTO_SAMPLE_SIZE
----DBMS_STATS.AUTO_SAMPLE_SIZE
----10: Thay đổi 10% mới gather
----method_opt
----FOR ALL COLUMNS SIZE AUTO: Tất cả các cột
----FOR ALL COLUMNS SIZE AUTO FOR COLUMNS SIZE 1 IMAGE_COLUM: Bỏ qua cột IMAGE_COLUM
----Degree           
----4
----INCREMENTAL
----= true (nếu false mà bảng lớn sẽ tốn tài nguyên
----PUBLISH
----= true (if partitioned table)
----GRANULARITY
----AUTO
----PARTITION
----granularity=>'APPROX_GLOBAL AND PARTITION'
----+gather 1 part nó nội suy cả bảng
----+nhưng  không hay lắm nếu minh đang ngồi trên DB Core
--
--Cascade          
--FALSE   --> Khong gather index

BEGIN
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
      OwnName        => 'TEST_OWNER'
     ,TabName        => 'SUBS'
    ,Estimate_Percent  => AUTO_SAMPLE_SIZE
    ,Method_Opt        => 'FOR ALL COLUMNS SIZE 1'
    ,Degree            => 4
    ,Cascade           => FALSE   --> Khong gather index
    ,No_Invalidate     => FALSE);
END;
/

BEGIN
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
      OwnName        => 'TEST_OWNER'
     ,TabName        => 'SUBS'
    ,Estimate_Percent  => 10
    ,Method_Opt        => 'FOR ALL COLUMNS SIZE 1'
    ,Degree            => 4
    ,Cascade           => TRUE   --> Treo do gather cả index
    ,No_Invalidate     => FALSE);
END;
/ 

--III.            Check last gathered
·         DBA_TABLES
·         DBA_TAB_STATISTICS
·         DBA_TAB_PARTITIONS
·         DBA_TAB_SUB_PARTITIONS
·         DBA_TAB_COLUMNS
·         DBA_TAB_COL_STATISTICS
·         DBA_PART_COL_STATISTICS
·         DBA_SUBPART_COL_STATISTICS
·         DBA_INDEXES
·         DBA_IND_STATISTICS
·         DBA_IND_PARTITIONS
·         DBA_IND_SUBPARTIONS
·         DBA_TAB_HISTOGRAMS
·         DBA_PART_HISTOGRAMS
·         DBA_SUBPART_HISTOGRAMS

--a.      Khi nào cần gather lại:
        select owner, table_name ,partition_name, subpartition_name, object_type, num_rows, sample_size, last_analyzed, global_stats, stale_stats
        from dba_tab_statistics
        where owner = 'SCOTT' 
       and table_name = 'DEPT' 
      and (stale_stats='YES'  or    stale_stats is null) ;  

--Note: Nếu stale_stats=YES (thông tin cũ) hoặc trống (chưa có thông tin): Cần gather lại (còn No thì không cần)
--b.      Table
--·         Bảng partition: (trong TOAD dùng F4 --> partition để check)
select table_name, partition_name, last_analyzed from DBA_TAB_PARTITIONS where table_owner='OAZ17' and table_name like upper('TABLE1')
--and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;

select owner, table_name, partition_name,last_analyzed  from DBA_TAB_STATISTICS where  table_owner='OAZ17' and table_name like upper('TABLE1')
and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;

--·         Bảng ko partition:
select owner, table_name,last_analyzed  from dba_tables where  owner='OAZ17' 
--and table_name like upper('TEST_TAB1')
--and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;

select owner, table_name, partition_name,last_analyzed  from DBA_TAB_STATISTICS where  table_owner='OAZ17' and table_name like upper('TABLE1')
and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;

--c.       Index
--·         Index partition
select index_owner, index_name, partition_name, last_analyzed from dba_ind_partitions
where index_owner=‘TEST_OWNER’
and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;
·         Index ko partition
select owner,table_name,index_name,num_rows,last_analyzed from dba_indexes
where owner=‘TEST_OWNER’
and trunc(last_analyzed) > sysdate-7
order by last_analyzed desc;

--II.   Gather
--Các tham số:
--INCREMENTAL = true
--PUBLISH = true (if partitioned table)
--ESTIMATE_PERCENT=AUTO_SAMPLE_SIZE
--GRANULARITY=AUTO
--1.      Gather
--a.      Database
-- Recommend: estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, method_opt => 'FOR ALL COLUMNS SIZE AUTO'
EXEC DBMS_STATS.gather_database_stats(estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,Method_Opt        => 'FOR ALL COLUMNS SIZE AUTO',degree=>8, cascade => TRUE);

BEGIN
  SYS.DBMS_STATS.gather_database_stats (
    Estimate_Percent  => DBMS_STATS.AUTO_SAMPLE_SIZE
    ,Method_Opt        => 'FOR ALL COLUMNS SIZE AUTO'
    ,Degree            => 16
    ,Cascade           => FALSE
    ,No_Invalidate     => FALSE);
END;
/

-- Thủ tục gather cả Db
CREATE OR REPLACE PACKAGE BODY TEST_OWNER.pck_gather_table_stats
IS
    p_error         VARCHAR2 (1000);
    p_gather_date_par   DATE := SYSDATE;
    p_gather_date   DATE := SYSDATE;

    PROCEDURE exec_gather_tables
    IS
    BEGIN
        -- Bảng unpartitioned dữ 
        IF (TO_NUMBER(TO_CHAR (SYSDATE, 'dd')) IN (1,5,11,15,21,25) and (to_number(to_char(sysdate,'hh24')) < 7 or to_number(to_char(sysdate,'hh24')) > 22))
        THEN
            pck_gather_table_stats.gather_unpartitioned_tables;
        END IF;
         pck_gather_table_stats.gather_partitioned_tables();
        
    END;

    PROCEDURE gather_partitioned_tables
    IS
        CURSOR c_partitioned_tables
        IS
            SELECT   table_owner, table_name, partition_name, last_analyzed,
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
                            '
                         script
                FROM   all_tab_partitions
               WHERE   
   table_owner='TEST_OWNER'
   and table_name not like '%XXX%' and table_name not like '%TMP%' and table_name not like '%TEMP%' and table_name not like '%TEST%' and table_name not like '%$%'             
   AND  (last_analyzed is null or num_rows is null)
   and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<trunc(sysdate)
              AND to_date(substr(partition_name,5,8),'YYYYMMDD')>trunc(sysdate)-60
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<trunc(sysdate)
            AND to_date(substr(partition_name,5,6),'YYYYMM')>=add_months(trunc(sysdate,'month'),-2)
            )
        )
and partition_name like '%2021%'
ORDER BY   table_name, partition_name;

        v_table_name   VARCHAR2 (100);
        v_par_name     VARCHAR2 (100);
    BEGIN
        FOR v_partitioned_tables IN c_partitioned_tables
        LOOP
            IF (TO_NUMBER (TO_CHAR (SYSDATE, 'dd')) NOT IN(0)) and (to_number(to_char(sysdate,'hh24')) < 7 or to_number(to_char(sysdate,'hh24')) > 22)
            THEN
            v_table_name := v_partitioned_tables.table_name;
            v_par_name := v_partitioned_tables.partition_name;

            EXECUTE IMMEDIATE v_partitioned_tables.script;
--            pr_insert_log_gather(v_partitioned_tables.table_owner, v_partitioned_tables.table_name, v_partitioned_tables.partition_name,v_partitioned_tables.script);
            end if;
        END LOOP;
    EXCEPTION
        WHEN OTHERS
        THEN
            null;
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
                                (ownname=>''' || OWNER || ''',
                                tabname=>''' || table_name || ''',
                                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                method_opt => ''FOR ALL COLUMNS SIZE AUTO'',
                                cascade=>true,
                                degree=>10);
                                end;
                            '
                           script
                FROM   dba_tables
               WHERE       partitioned = 'NO'               
                       AND tablespace_name IS NOT NULL
                       AND table_name NOT LIKE '%$%'
                       AND table_name not  like '%XX%'
                       and table_name not  like '%BK%'
                       and owner in ('TEST_OWNER')
                      --AND NVL (last_analyzed, SYSDATE - 15) < p_gather_date
                       AND  (last_analyzed is null or num_rows is null)
            ORDER BY   last_analyzed;

        v_table_name   VARCHAR2 (100);
    BEGIN

        FOR v_tables IN c_tables
        LOOP
            v_table_name := v_tables.table_name;

            EXECUTE IMMEDIATE v_tables.script;
--            pr_insert_log_gather(v_tables.owner, v_tables.table_name, null,v_tables.script);
        END LOOP;
  EXCEPTION
        WHEN OTHERS
        THEN
            null;
    END;

--------------------------------------------------------------------------------
END;
/

b.      Schema
EXEC DBMS_STATS.gather_schema_stats('TEST_OWNER', estimate_percent => 10,degree=>8, cascade => TRUE);

-- All partition của SCHEMA
-- Dùng incremetal=true để không quét cả bảng
SELECT   table_owner,table_name, partition_name, last_analyzed,
             'exec dbms_stats.gather_table_stats(''' || table_owner||''',''' || table_name ||''',partname=>'''
             || PARTITION_NAME || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE,'
             || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8);'     script
              FROM   dba_tab_partitions
             WHERE  table_owner in ('USER1')
                    and ( (partition_name LIKE
                                 'DATA'
                              || TO_CHAR (trunc(sysdate) + 30, 'YYYYMM')
                              || '%')
                      OR (partition_name LIKE
                                 'DATA'
                              || TO_CHAR (trunc(sysdate) + 60, 'YYYYMM')
                              || '%'))        
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )             
            --AND (last_analyzed is null or nvl(last_analyzed,sysdate- 15) < trunc(sysdate))
     AND  (last_analyzed is null or num_rows is null)
            ORDER BY   table_owner, table_name, partition_name;
-- Bảng non-partition
declare
    --p_gather_date DATE := sysdate;
    CURSOR c_tables
    IS
          SELECT   table_name, last_analyzed,
                   'begin
                dbms_stats.gather_table_stats
                (ownname => '''
                               || 'TEST_OWNER'
                               || ''',
                tabname => '''
                               || table_name
                               || ''',
                cascade => true,
                estimate_percent => 10,
                degree => 10);
                end;
                '
                       script
            FROM   dba_tables
           WHERE       partitioned = 'NO' and
                owner='TEST_OWNER'
                   AND tablespace_name IS NOT NULL
                   AND table_name NOT LIKE '%$%'
                   --AND NVL (last_analyzed, SYSDATE - 15) < trunc(sysdate)
       AND  (last_analyzed is null or num_rows is null)
        ORDER BY   last_analyzed;

    v_table_name   VARCHAR2 (100);
BEGIN
        --send_sms('TEST_OWNER Started gathering unpartitioned_tables  at ' || to_char(sysdate,'dd/mm/yyy hh24:mm:ss'));
        FOR v_tables IN c_tables
        LOOP
            v_table_name := v_tables.table_name;
            EXECUTE IMMEDIATE v_tables.script;
            dbms_output.put_line(v_tables.script);
        END LOOP;
  EXCEPTION
        WHEN OTHERS
        THEN
            null;
END;

c.       Table

Cả table (non-partition || partition): Bang partition nen theo từng partition, không nguy cơ sẽ treo
execute dbms_stats.gather_table_stats(ownname => 'SCOTT', tabname =>
            'DEPT', estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
            method_opt => 'FOR ALL COLUMNS SIZE AUTO',cascade => true,degree => 10);

exec dbms_stats.gather_table_stats (ownname => 'TEST_OWNER',tabname => 'STOCK_ISDN',cascade => true,estimate_percent => 10,degree => 10);

BEGIN
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
      OwnName        => 'TEST_OWNER
     ,TabName        => ‘TAB1'
    ,Estimate_Percent  => 10
    ,Method_Opt        => 'FOR ALL COLUMNS SIZE 1'
    ,Degree            => 4
    ,Cascade           => TRUE
    ,No_Invalidate     => FALSE);
END;

BEGIN
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
      OwnName        => 'TEST_OWNER
     ,TabName        => ‘TAB1'
    ,Estimate_Percent  => 10
    ,Method_Opt        => 'DBMS_STATS.AUTO_SAMPLE_SIZE'
    ,Degree            => 4
    ,Cascade           => TRUE
    ,No_Invalidate     => FALSE);
END;
-- Script All Partition 1 bang partition
SELECT   table_name, partition_name, last_analyzed,
           'exec dbms_stats.gather_table_stats(ownname =>'''||table_owner||''',tabname =>'''||table_name||''',partname'||'=>'''
         || PARTITION_NAME
         || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>10,'
         || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8);'
                         script
                FROM   dba_tab_partitions
               WHERE   table_name  in ('TAB1,'TAB2')
                       and table_owner in ('TEST_OWNER')         
                       AND  (last_analyzed is null or num_rows is null)    
                       and partition_name like '%2018%'
                        --AND  and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )                         
            ORDER BY   table_name, partition_name;
Exec sys.send_sms_binhtv
Thủ tục
declare
    --p_gather_date DATE := sysdate;
    CURSOR c_partitions
    IS         
SELECT   table_name, partition_name, last_analyzed,
           'exec dbms_stats.gather_table_stats(ownname =>'''||table_owner||''',tabname =>'''||table_name||''',partname'||'=>'''
         || PARTITION_NAME
         || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>10,'
         || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8);'
                         script
                FROM   all_tab_partitions
               WHERE   table_name NOT LIKE '%$%'
                       and table_owner in (‘TEST_OWNER’)
                       AND  (last_analyzed is null or num_rows is null)
 --AND NVL (last_analyzed, SYSDATE - 15) < trunc(sysdate)
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
            ORDER BY   last_analyzed;
          
    v_table_name   VARCHAR2 (100);
BEGIN
        --send_sms('TEST_OWNER Started gathering unpartitioned_tables  at ' || to_char(sysdate,'dd/mm/yyy hh24:mm:ss'));
        FOR v_partitions IN c_partitions
        LOOP
            v_partition_name := v_partitions.table_name;
            EXECUTE IMMEDIATE v_partitions.script;
            dbms_output.put_line(v_partitions.script);
        END LOOP;
  EXCEPTION
        WHEN OTHERS
        THEN
            null;
END;

Script gather bảng non-partition STALE

SELECT /* GATHER TABLE NON-PARTITION STALE  */    table_name, partition_name, last_analyzed,
                        'begin
                                dbms_stats.gather_table_stats
                                (ownname=>''' || OWNER || ''',
                                tabname=>''' || table_name || ''',
                                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                method_opt => ''FOR ALL COLUMNS SIZE AUTO'',
                                cascade=>true,
                                degree=>10);
                                end;' script
from dba_tab_statistics a
where owner = 'BINHTV' 
and table_name not like 'XXX%' and table_name not like 'TMP%' and (stale_stats is null or stale_stats = 'YES') and object_type = 'TABLE'
--and table_name in ('TAB1','TAB2') 
and not exists (select 1 from  dba_tab_statistics where owner = a.owner and table_name = a.table_name and object_type = 'PARTITION' and rownum < 2)
order by 1,2 desc; 

Script gather bảng partition STALE 2021
SELECT   table_name, partition_name, last_analyzed,num_rows,
   'begin dbms_stats.gather_table_stats(ownname =>'''||owner||''',tabname =>'''||table_name||''',partname'||'=>'''
 || PARTITION_NAME
 || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>10,'
 || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8); end;'
 script
FROM   dba_tab_statistics
where  
owner='USER1'
--and table_name in ('TAB1')      
--and num_rows<10000000
and partition_name is not null
and partition_name like '%2021%'
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
and (stale_stats='YES' or stale_stats is null);


SELECT /* GATHER TABLE PARTITION STABLE */  table_name, partition_name, last_analyzed,num_rows,
   'begin dbms_stats.gather_table_stats(ownname =>'''||owner||''',tabname =>'''||table_name||''',partname'||'=>'''
 || PARTITION_NAME
 || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>10,'
 || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8); end;'
 script
FROM   dba_tab_statistics
where  
((owner='USER2' and table_name in ('TAB5'))
or
owner='USER1' and table_name in  ('TAB1','TAB2','TAB3','TAB4')
)
and table_name not like '%XXX%' and table_name not like '%TMP%' and table_name not like '%TEMP%' and table_name not like '%TEST%' and table_name not like '%$%' 
--and table_name in ('TAB1','','TAB2','TAB3')      
-- and table_name='TAB5' 
--and num_rows<10000000
and partition_name is not null
and partition_name like '%2021%'
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
and to_date(substr(partition_name,5,8),'yyyymmdd')> sysdate-30
and to_date(substr(partition_name,5,8),'yyyymmdd') < sysdate
and (stale_stats='YES' or stale_stats is null); 

Tips: Gather tự động cho các partition:
 begin    
dbms_stats.gather_table_stats(ownname=>'BINH_OWNER', 
                                  tabname=> 'TRÁN',
                                  partname=>'DATA20210304',
                                  degree=>dbms_stats.auto_degree,
                                  granularity=>'APPROX_GLOBAL AND PARTITION') ;    
end;

d.      Partition

-- 1 partition
begin
	dbms_stats.gather_table_stats(ownname =>'BINHTV',
							tabname =>'TAB1',
							partname=>'DATA20161130',
							granularity=>'partition',
							cascade=> FALSE,
							force=>TRUE,
							estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE,
							method_opt=>'FOR ALL COLUMNS SIZE AUTO',
							degree => 4);
end;

-- Cả bảng
SELECT   table_name, partition_name, last_analyzed,
           'exec dbms_stats.gather_table_stats(ownname =>'''||table_owner||''',tabname =>'''||table_name||''',partname'||'=>'''
         || PARTITION_NAME
         || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE,'
         || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8);'
                         script
                FROM   dba_tab_partitions
               WHERE   table_name  in ('TAB1')
                       and table_owner in ('BINHTV')          
                       --AND  (last_analyzed is null or num_rows is null)
                       and num_rows is null
                       --and partition_name like '%2018%'
                        --AND to_date(substr(partition_name,5,8),'YYYYMMDD')>sysdate                            and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
            ORDER BY   table_name, partition_name desc;


SELECT   table_name, partition_name, last_analyzed,
           'exec dbms_stats.gather_table_stats(ownname =>'''||table_owner||''',tabname =>'''||table_name||''',partname'||'=>'''
         || PARTITION_NAME
         || ''',granularity=>''partition'',cascade=> TRUE,force=>TRUE,estimate_percent=>DBMS_STATS.AUTO_SAMPLE_SIZE,'
         || 'method_opt=>''FOR ALL COLUMNS SIZE AUTO'',degree => 8);'
                         script
                FROM   dba_tab_partitions
               WHERE   table_name  in ('TAB1','TAB2')
                       and table_owner in ('BINHTV')          
                       AND  (last_analyzed is null or num_rows is null)   
                       and partition_name like '%2018%'
                        --AND to_date(substr(partition_name,5,8),'YYYYMMDD')>sysdate                            and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
            ORDER BY   table_name, partition_name;

-- Tự động tạo thông tin gather cho các partition
begin    
dbms_stats.gather_table_stats(ownname=>'BINHTV', 
                                  tabname=> 'TAB1',
                                  partname=>'DATA202011',
                                  degree=>dbms_stats.auto_degree,
                                  granularity=>'APPROX_GLOBAL AND PARTITION') ;    
end;

e.       Gather Index: Không lock index --> Ít dùng vì gather partition || table thì index đi kèm sẽ được gather theo
-- Index non-partition
EXEC DBMS_STATS.gather_index_stats('SCOTT', 'EMPLOYEES_PK', estimate_percent => 15,degree => 8);
-- Index partition
EXEC DBMS_STATS.gather_index_stats('SCOTT', 'EMPLOYEES_I1', estimate_percent => 15,degree => 8);
--+ Tuong minh
BEGIN
  SYS.DBMS_STATS.GATHER_INDEX_STATS (
      OwnName        => ‘TEST_OWNER’
     ,IndName        => 'TABLE1_I1'
    ,Estimate_Percent  => 10
    ,Degree            => 4
    ,No_Invalidate     => FALSE);
END;
/

f. Gather dictionary statistic

Non-CDB: SQL> EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;

CDB:

+ All PDB:

$ORACLE_HOME/perl/bin/perl $ORACLE_HOME/rdbms/admin/catcon.pl -l /tmp -b gatherstats -- --x"exec dbms_stats.gather_dictionary_stats"

+ PDB cụ thể: 
$ORACLE_HOME/perl/bin/perl $ORACLE_HOME/rdbms/admin/catcon.pl -l /tmp -c
'SALES1' -b gatherstats -- --x"exec dbms_stats.gather_dictionary_stats"

f. Gather fixed object statistic
SQL> execute dbms_stats.gather_fixed_objects_stats;

2.    Set Gather
exec DBMS_STATS.SET_TABLE_STATS (   ownname=>'TEST_OWNER’,tabname=> 'TAB1’, partname=>'DATA20110524', numrows=>56000000, numblks=>1000000); 
exec DBMS_STATS.SET_INDEX_STATS (   ownname=>'TEST_OWNER’,indname=> 'TAB1_I1', partname=>'DATA20121124', numrows=>37037005, indlevel=>3,numdist=>2337312);

exec DBMS_STATS.SET_TABLE_STATS (   ownname=>'TEST_OWNER',tabname=> 'TAB1', numrows=>5600000, numblks=>100000);
3.    Delete gather
EXEC DBMS_STATS.delete_database_stats;
EXEC DBMS_STATS.delete_schema_stats('SCOTT');
EXEC DBMS_STATS.delete_table_stats('SCOTT', 'EMP');
EXEC DBMS_STATS.delete_column_stats('SCOTT', 'EMP', 'EMPNO');
EXEC DBMS_STATS.delete_index_stats('SCOTT', 'EMP_PK');
EXEC DBMS_STATS.delete_dictionary_stats;

III.   ANALYZE

1.  Analyze database: Không hỗ trợ


2. ANALYZE SCHEMA
·         Cả schema bang partition
SELECT   table_name, partition_name, last_analyzed, 'ANALYZE TABLE ' ||table_owner|| '.'|| table_name|| ' partition ('|| partition_name                     || ') ESTIMATE STATISTICS SAMPLE 10 PERCENT' script
                FROM   all_tab_partitions
               WHERE   partition_name LIKE
                              'DATA' || TO_CHAR (sysdate, 'YYYYMM') || '%'
                       AND table_name NOT LIKE '%$%'
                       and table_owner in ('TEST_OWNER', 'TEST2_OWNER')
                       AND NVL (last_analyzed, SYSDATE - 15) < sysdate
                       AND NVL (last_analyzed, SYSDATE - 15) < sysdate
                       AND to_date(substr(partition_name,5,8),'YYYYMMDD')<sysdate
                       AND to_date(substr(partition_name,5,8),'YYYYMMDD')>sysdate-4
                     AND  (last_analyzed is null or num_rows is null)
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
            ORDER BY   table_name, partition_name;
declare
        CURSOR c_partitioned_tables
        IS
           SELECT   table_name, partition_name, last_analyzed,
                        'ANALYZE TABLE ' ||table_owner|| '.'
                     || table_name
                     || ' partition ('
                     || partition_name
                     || ') ESTIMATE STATISTICS SAMPLE 10 PERCENT'
                         script
                FROM   dba_tab_partitions
               WHERE   table_name NOT LIKE '%$%'
                       and table_owner in ('TEST_OWNER')
                       AND  (last_analyzed is null or num_rows is null)
                        and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        )
            ORDER BY   table_name, partition_name;

        v_table_name   VARCHAR2 (100);
        v_par_name     VARCHAR2 (100);
    BEGIN
        FOR v_partitioned_tables IN c_partitioned_tables
        LOOP
            v_table_name := v_partitioned_tables.table_name;
            v_par_name := v_partitioned_tables.partition_name;

            EXECUTE IMMEDIATE v_partitioned_tables.script;
            --dbms_output.put_line(v_partitioned_tables.script);

        END LOOP;
    EXCEPTION
        WHEN OTHERS
        THEN
            null;
    END;

·         Cả schema bang non-partition
3. ANALYZE TABLE
·         Table non-partition
analyze table mc_subscriber estimate statistics sample 10 percent
·         Table partition
ANALYZE TABLE TAB1 partition (DATA20120701) ESTIMATE STATISTICS SAMPLE 10 PERCENT
+ All partition của 1 bảng:
select 'analyze table ' || table_owner ||'.' || table_name || ' partition(' || partition_name || ') estimate statistics sample 10 percent;'  from DBA_TAB_PARTITIONS where table_owner=’TEST_OWNER’ and table_name='TAB1’ and last_analyzed is null
 and ((length(partition_name) = 12 AND to_date(substr(partition_name,5,8),'YYYYMMDD')<= trunc(sysdate)            
         )
        or (length(partition_name) =10 AND to_date(substr(partition_name,5,6),'YYYYMM')<=trunc(sysdate)
            )
        );
+ 1 partition:
ANALYZE TABLE TEST_OWNER.TAB1 partition (DATA20160809) ESTIMATE STATISTICS SAMPLE 10 PERCENT
Ghi chú:
ANALYZE TABLE test VALIDATE STRUCTURE CASCADE ONLINE;
4. Analyze Index:
-- Index non-partition
-- Tương đương câu GATHER ở trên
ANALYZE INDEX index_name COMPUTE STATISTICS;

-- VALIDATE cấu trúc  -->  THẬN TRỌNG KHI CHẠY!!!
--+ Gây LOCK index IDX2 do đó các thao tác DML vào bảng bị wait, sau khi validate xong mới được thực hiện --> Gây lock, active session tăng cao
ANALYZE INDEX TEST_OWNER.IDX2 VALIDATE STRUCTURE;

--+ Index partition
ANALYZE INDEX TEST_OWNER.TAB1 _IDX1 partition(DATA20141224) VALIDATE STRUCTURE;
--+ Sau khi chạy được validate check xem độ phân mảnh của index (nếu del_lf_row/lf_rows > 30%)
SELECT blocks, pct_used, distinct_keys
lf_rows, del_lf_rows
FROM index_stats;
5. SET ANALYZE
Đang cập nhật.....
6. DELETE ANALYZE
ANALYZE TABLE TAB1 DELETE STATISTICS;
7. MONITOR KHI GATHER HOẶC ANALYZE
Nếu trong giờ hành chính có thể gây treo DB Core khi analyze bảng core 1 partition hoăc 1 bảng lớn (>50GB), cần kill ngay:

SELECT /*1.ActiveSession*/ distinct s.inst_id i#, s.username, s.SID SID, s.osuser, s.machine,DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') ACTION,
    s.sql_id, SUBSTR(DECODE(SS.SQL_TEXT, NULL, AA.NAME, SS.SQL_TEXT), 1, 1000) SQLTEXT,s.logon_time,s.p1text, S.P1, s.p2text, S.P2, s.p3text, S.P3
    FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
    WHERE  S.STATUS = 'ACTIVE' AND  S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND and s.type != 'BACKGROUND' AND S.TYPE = 'USER' 
    --and s.username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','GOLDENGATE')
    AND username like 'SYS%'
    --and DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') like '%cell single block physical read%'
    and (lower(ss.sql_text) like lower('%alter table%') or lower(ss.sql_text) like lower('%analyz%') )
    and lower(ss.sql_text) not like lower('%ACTIVE, LOCK%')
    --and s.sid=4588 
    --and s.machine like '%BINHTV%'
    --and s.sql_id ='ccwg0nqr1zbu7'
    
SELECT /*5.SID*/  'kill -9 ' || spid a, a.INST_ID,A.SQL_ID,A.SID, A.SERIAL#, a.USERNAME, a.STATUS,A.SCHEMANAME,a.OSUSER,A.MACHINE,A.PROGRAM,A.TYPE,A.LOGON_TIME,a.prev_exec_start,BACKGROUND
FROM gv$session a, gv$process b 
WHERE b.addr = a.paddr   
AND a.inst_id=b.inst_id 
--and b.inst_id=2
AND a.sid in (
    select sid from (SELECT /*1.ActiveSession*/ distinct s.inst_id i#, s.username, s.SID SID, s.osuser, s.machine,DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') ACTION,
    s.sql_id, SUBSTR(DECODE(SS.SQL_TEXT, NULL, AA.NAME, SS.SQL_TEXT), 1, 1000) SQLTEXT,s.logon_time,s.p1text, S.P1, s.p2text, S.P2, s.p3text, S.P3
    FROM GV$SESSION S, GV$SQLSTATS SS, AUDIT_ACTIONS AA
    WHERE  S.STATUS = 'ACTIVE' AND  S.SQL_ID = SS.SQL_ID (+) AND AA.ACTION = S.COMMAND and s.type != 'BACKGROUND' AND S.TYPE = 'USER' 
    --and s.username  NOT in ('SYS','SYSMAN','DBSNMP','GGATE','GOLDENGATE')
    AND username like 'SYS%'
    --and DECODE(S.WAIT_TIME, 0, S.EVENT, 'CPU') like '%cell single block physical read%'
    and (lower(ss.sql_text) like lower('%alter table%') or lower(ss.sql_text) like lower('%analyz%') )
    and lower(ss.sql_text) not like lower('%ACTIVE, LOCK%'))
    --and s.sid=4588 
    --and s.machine like '%BINHTV%'
    --and s.sql_id ='ccwg0nqr1zbu7'
)
and type='USER'
order by A.LOGON_TIME;

MỘT SỐ LỖI HAY GẶP:

Lỗi 1: Gather dữ liệu offline
begin
                                dbms_stats.gather_table_stats
                                (ownname=>'USER1',
                                tabname=>'TAB1',
                                partname=>'DATA20210609',                                
                                estimate_percent => 10,
                                method_opt => 'FOR ALL COLUMNS SIZE AUTO',
                                cascade=>true,
                                degree=>10);
                                end;
                                
                                
-- Cần datafile từ rất lâu rồi (other201812)
ORA-00376: file 13836 cannot be read at this time
ORA-01110: data file 13836: '+DATA/dbaviet/datafile/other201812.724.995998009'
ORA-06512: at "SYS.DBMS_STATS", line 24281
ORA-06512: at "SYS.DBMS_STATS", line 24332
ORA-06512: at line 2

Giải pháp:

ANALYZE TABLE USER1.TAB1 partition (DATA20210622) ESTIMATE STATISTICS SAMPLE 10 PERCENT;

BEGIN
  SYS.DBMS_STATS.GATHER_TABLE_STATS (
     OwnName           => 'USER1'
    ,TabName           => 'TAB1'
    ,PartName          => 'DATA20210609'
    ,Granularity       => 'PARTITION'
    ,Estimate_Percent  => 10
    ,Method_Opt        => 'FOR ALL COLUMNS SIZE AUTO'
    ,Degree            => 4
    ,Cascade           => TRUE
    ,No_Invalidate  => FALSE);
END;

Lỗi 2: Nghiệp vụ đang chạy DML nhiều thì không gather đựợc

[1]: ORA-04021: timeout occurred while waiting to lock object 
[1]: ORA-06512: at "SYS.DBMS_STATS", line 24281
[1]: ORA-06512: at "SYS.DBMS_STATS", line 24332
[1]: ORA-06512: at line 2

--> Giải pháp: Dừng nghiệp vụ mới gather được hoặc set tĩnh