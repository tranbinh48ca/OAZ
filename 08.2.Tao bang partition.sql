--Thủ tục tạo bảng partition theo ngày trong Oracle Database
--Thủ tục tạo partition theo ngày trong Oracle Database

--drop table OAZ29.t1;

create user OAZ29 identified by oracle;

grant connect, resource, dba to OAZ29;

-- 07.2.1.Tao bang: Boi den --> An F5
CREATE TABLE OAZ29.t1
    (id                     VARCHAR2(15) NOT NULL,
    create_datetime              DATE NOT NULL,    
    col2                    VARCHAR2(20),
    col3                 NUMBER(10,2)
)
TABLESPACE DATA
PARTITION BY RANGE (create_datetime)
(
  PARTITION DATA20260101 VALUES LESS THAN (TO_DATE('2026-01-02 00:00:00', 'SYYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN'))
  TABLESPACE DATA2026
);

--07.2.2.Add them partition: Bôi đen và ấn F5 --> Vào DBMS Ouput copy nội dung và mở Tab mới để chạy 
--Add them partition 2026
DECLARE
   v_nam          NUMBER (4) := 2026; 
   v_tablename    VARCHAR2 (50) := 't1';
   v_date_from   date    := to_date('02/01/2026','dd/mm/yyyy');
   v_date_to     date    := to_date('31/12/2026','dd/mm/yyyy');
   v_numday     number(5);
   v_tablespace varchar2(50):='DATA2026';
BEGIN
    DBMS_OUTPUT.ENABLE (buffer_size => NULL);
   v_numday:=v_date_to-v_date_from; 
   FOR i IN 0 .. v_numday
   LOOP
      DBMS_OUTPUT.put_line ('alter table OAZ29.'|| v_tablename || ' add PARTITION DATA'||to_char(v_date_from+i,'YYYYMMDD')||' VALUES LESS THAN (TO_DATE('''|| to_char(v_date_from+i+1,'YYYY-MM-DD')||' 00:00:00'', ''SYYYY-MM-DD HH24:MI:SS'', ''NLS_CALENDAR=GREGORIAN'')) LOGGING TABLESPACE '||v_tablespace||';');      
   END LOOP;
END;

-- 07.2.3.Add them partition 2026 (khong can)
DECLARE
   v_nam          NUMBER (4) := 2026; 
   v_tablename    VARCHAR2 (50) := 't1';
   v_date_from   date    := to_date('01/01/2026','dd/mm/yyyy');
   v_date_to     date    := to_date('31/12/2026','dd/mm/yyyy');
   v_numday     number(5);
   v_tablespace varchar2(50):='DATA2025';
BEGIN
    DBMS_OUTPUT.ENABLE (buffer_size => NULL);
   v_numday:=v_date_to-v_date_from; 
   FOR i IN 0 .. v_numday
   LOOP
      DBMS_OUTPUT.put_line ('alter table OAZ29.'|| v_tablename || ' add PARTITION DATA'||to_char(v_date_from+i,'YYYYMMDD')||' VALUES LESS THAN (TO_DATE('''|| to_char(v_date_from+i+1,'YYYY-MM-DD')||' 00:00:00'', ''SYYYY-MM-DD HH24:MI:SS'', ''NLS_CALENDAR=GREGORIAN'')) LOGGING TABLESPACE '||v_tablespace||';');
   END LOOP;
END;

-- Check lai cac partition vua tao
select * from dba_tab_partitions where table_owner ='OAZ29'
and table_name='T1'
order by partition_name;

select * from dba_segments where owner='OAZ29'
and segment_name='T1';

-- Hoac dua chuot vao t1 an nut F4

--3.Tao index, an Ctrl+E tao explan plan
insert into OAZ29.t1(id,create_datetime,col2,col3)  select object_id,created,owner, object_name from dba_objects;
commit;
 
alter table oaz29.t1 modify col3 varchar2(150);

alter table oaz29.t1 modify id number;

select object_id,created,owner, object_name from dba_objects where created >= to_date('01/01/2026','dd/mm/yyyy');

select * from oaz29.t1; 
 
 grant unlimited tablespace to OAZ29;
 
 alter table OAZ29.t1 modify id number;
 
alter table OAZ29.t1 modify col2 varchar2(50);

 alter table OAZ29.t1 modify col3 varchar2(200);
 
  alter table OAZ29.t1 modify id ID
 
 select * from dba_objects where object_id is null
 
 alter table OAZ29.t1 modify col2 varchar2(200);
 
select * from dba_objects;

--Ctrl+E  
select * from  OAZ29.t1 
where id=24;

alter table OAZ29.t1  modify id number;

--Plan: Before Gather
SELECT STATEMENT  ALL_ROWSCost: 366  Bytes: 8,305  Cardinality: 55  		
	2 PARTITION RANGE ITERATOR  Cost: 366  Bytes: 8,305  Cardinality: 55  Partition #: 1  Partitions determined by Key Values	
		1 TABLE ACCESS FULL TABLE OAZ29.T1 Cost: 366  Bytes: 8,305  Cardinality: 55  Partition #: 1  Partitions determined by Key Values


-- Go ctrl+E sẽ là explain plan

-- LOCAL index: index partition
create index  OAZ29.t1_I1 on OAZ29.t1(id) LOCAL parallel 8 nologging online;

alter index OAZ29.t1_I1 noparallel;

-- Ấn Ctrl+E
select * from  OAZ29.t1 where create_datetime>sysdate-2
and id=1;

--Plan: Afterm cost 232
Plan
SELECT STATEMENT  ALL_ROWSCost: 232  Bytes: 51  Cardinality: 1  			
	3 PARTITION RANGE ITERATOR  Cost: 232  Bytes: 51  Cardinality: 1  Partition #: 1  Partitions determined by Key Values		
		2 TABLE ACCESS BY LOCAL INDEX ROWID BATCHED TABLE OAZ29.T1 Cost: 232  Bytes: 51  Cardinality: 1  Partition #: 1  Partitions determined by Key Values	
			1 INDEX RANGE SCAN INDEX OAZ29.T1_I1 Cost: 231  Cardinality: 1  Partition #: 1  Partitions determined by Key Value

-- global index = global non-partition
create index  OAZ29.t1_I2 on OAZ29.t1(col2)  parallel 8 nologging online;

alter index OAZ29.t1_I2 noparallel;

-- Them du lieu 01/01, 02/01/2025
insert into OAZ29.t1 values(500,to_date('01/01/2026','dd/mm/yyyy'),2,3);
commit;

--Plan
Plan
SELECT STATEMENT  ALL_ROWSCost: 2,457  Bytes: 3,742,533  Cardinality: 73,383  		
	2 PARTITION RANGE ALL  Cost: 2,457  Bytes: 3,742,533  Cardinality: 73,383  Partition #: 1  Partitions accessed #1 - #365	
		1 TABLE ACCESS FULL TABLE OAZ29.T1 Cost: 2,457  Bytes: 3,742,533  Cardinality: 73,383  Partition #: 1  Partitions accessed #1 - #365


select * from OAZ29.t1;
   
--72.956
select count(*) from OAZ29.t1;

alter table  OAZ29.t1 truncate partition DATA20260101; -- Khi do index global t1_i2  unusable

insert into OAZ29.t1 values(500,to_date('01/01/2026','dd/mm/yyyy'),2,3);
commit;

insert into OAZ29.t1 values(500,to_date('02/01/2026','dd/mm/yyyy'),2,3);

commit;

insert into OAZ29.t1 values(500,to_date('03/01/2026','dd/mm/yyyy'),2,3);

commit;

select * from OAZ29.t1;

alter table  OAZ29.t1 drop partition DATA20260101;

--Plan: full do I2 unusable
SELECT STATEMENT  ALL_ROWSCost: 2,183  Bytes: 253  Cardinality: 11  		
	2 PARTITION RANGE ALL  Cost: 2,183  Bytes: 253  Cardinality: 11  Partition #: 1  Partitions accessed #1 - #364	
		1 TABLE ACCESS FULL TABLE OAZ29.T1 Cost: 2,183  Bytes: 253  Cardinality: 11  Partition #: 1  Partitions accessed #1 - #364


select * from OAZ29.t1 where col2 = 3;

--Plan: Full do I2 unusable
DELETE STATEMENT  ALL_ROWSCost: 2,183  Bytes: 99  Cardinality: 9  			
	3 DELETE OAZ29.T1 		
		2 PARTITION RANGE ALL  Cost: 2,183  Bytes: 99  Cardinality: 9  Partition #: 2  Partitions accessed #1 - #364	
			1 TABLE ACCESS FULL TABLE OAZ29.T1 Cost: 2,183  Bytes: 99  Cardinality: 9  Partition #: 2  Partitions accessed #1 - #364

delete  OAZ29.t1  where col2='2';

commit;

--OAZ29	T1_I2	UNUSABLE
select owner, index_name, status from dba_indexes where index_name='T1_I2';

--insert into OAZ29.t1 values(5,to_date('01/05/2021','dd/mm/yyyy'),2,3);
--commit;
--
--update OAZ29.t1 set col2='col2';
--commit;

-- Cay index t1_i2 unusable: DML loi

 alter index OAZ29.t1_I2 rebuild online;
 
 --OAZ29	T1_I2	VALID
 select owner, index_name, status from dba_indexes where index_name='T1_I2';

--Plan: Theo index I2
SELECT STATEMENT  ALL_ROWSCost: 2  Bytes: 299  Cardinality: 13  		
	2 TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED TABLE OAZ29.T1 Cost: 2  Bytes: 299  Cardinality: 13  Partition #: 1  Partition access computed by row location	
		1 INDEX RANGE SCAN INDEX OAZ29.T1_I2 Cost: 1  Cardinality: 13  


select * from OAZ29.t1 where col2 = '5';

--Plan: Theo index I2
SELECT STATEMENT  ALL_ROWSCost: 2  Bytes: 23  Cardinality: 1  		
	2 TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED TABLE OAZ29.T1 Cost: 2  Bytes: 23  Cardinality: 1  Partition #: 1  Partition access computed by row location	
		1 INDEX RANGE SCAN INDEX OAZ29.T1_I2 Cost: 1  Cardinality: 13  
  
 
select * from OAZ29.t1 where create_datetime > sysdate-7 and col2 = '5';

select * from dba_indexes where owner='OAZ29'
and table_name='T1';

select * from dba_ind_partitions  where index_owner='OAZ29'
and index_name like 'T1%'
order by 1,2,4;

insert into OAZ29.t1 values(5,to_date('02/01/2025','dd/mm/yyyy'),2,3);
commit;

alter table  OAZ29.t1 truncate partition DATA20260930 update global indexes;

alter table  OAZ29.t1 drop partition DATA20260930 update global indexes;

alter table  OAZ29.t1 truncate partition data20260101; --unusable T1_I2

alter table  OAZ29.t1 truncate partition data20261001; --Index T1_I2 binh thuong do khong co du lieu

select * from dba_ind_partitions 
where index_owner='OAZ29'
and index_name='T1_I1'
--and status!='USABLE';

alter index  OAZ29.t1_I1 nologging noparallel;

--3.Rebuild index ve tablespace INDX2026: Bôi đen đoạn dưới và ấn F5
--2025, 2025
DECLARE
   v_date_from   date    := to_date('01/01/2026','dd/mm/yyyy');
   v_date_to     date    := to_date('31/12/2026','dd/mm/yyyy');
   v_numday     number;
   v_tablespace varchar2(50):='INDX';
   cursor c1 is
     select a.* from DBA_PART_INDEXES a, DBA_TAB_PARTITIONS b where a.owner=B.TABLE_OWNER  and a.table_name=B.TABLE_NAME  and b.table_owner='OAZ29' and b.table_name='T1'  and a.index_name not like '%$%' and b.partition_name like '%20261231'  order by a.owner,a.index_name;
BEGIN
   v_numday:=v_date_to-v_date_from; 
   FOR i1 in c1
   LOOP
       FOR i IN 0 .. v_numday
       LOOP
            DBMS_OUTPUT.put_line ('alter index '||i1.owner||'.'||i1.index_name || ' REBUILD PARTITION DATA'||to_char(v_date_from+i,'YYYYMMDD')||' TABLESPACE '||v_tablespace||to_char(v_date_from+i,'YYYY')||' nologging parallel 8 online;');
       END LOOP;
   END LOOP;
END;

-- Set nologging noparallel
DECLARE
   cursor c1 is
        select distinct a.index_owner, a.index_name from DBA_ind_partitions a where  a.index_owner='OAZ29' and a.index_name not like '%$%' and a.partition_name like '%20261231'  
        order by a.index_owner,a.index_name;
BEGIN
   FOR i1 in c1
   LOOP
            DBMS_OUTPUT.put_line ('alter index '||i1.index_owner||'.'||i1.index_name || ' nologging noparallel;');
   END LOOP;
END;

alter index OAZ29.T1_I1 nologging noparallel;