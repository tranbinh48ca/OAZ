--drop table bang_to purge;
---oaz25

CREATE TABLE OAZ29.bang_to (
    bang_toID int,
    LastName varchar(255),
    FirstName varchar(255),
    Address varchar(255),
    City varchar(255),
    create_date date
)
TABLESPACE DATA
PARTITION BY RANGE (create_date)
( 
 PARTITION DATA20260101 VALUES LESS THAN (TO_DATE('2025-01-02 00:00:00', 'YYYY-MM-DD HH24:MI:SS', 'NLS_CALENDAR=GREGORIAN'))
 TABLESPACE DATA2026);

-- Add partition het nam 2026, boi den xong an F5
DECLARE
   v_nam          NUMBER (4) := 2026;
   v_owner        varchar2 (50) := 'OAZ29';
   v_tablename    VARCHAR2 (50) := 'bang_to';
   v_date_from   date    := to_date('02/01/2026','dd/mm/yyyy');
   v_date_to     date    := to_date('31/12/2026','dd/mm/yyyy');
   v_numday     number(5);
   v_tablespace varchar2(50):='DATA';
BEGIN
   v_numday:=v_date_to-v_date_from; 
   FOR i IN 0 .. v_numday
   LOOP
      DBMS_OUTPUT.put_line ('alter table '||v_owner||'.'|| v_tablename || ' add PARTITION DATA' ||to_char(v_date_from+i,'YYYYMMDD')||' VALUES LESS THAN (TO_DATE('''|| to_char(v_date_from+i+1,'YYYY-MM-DD')||' 00:00:00'',''SYYYY-MM-DD HH24:MI:SS'', ''NLS_CALENDAR=GREGORIAN'')) LOGGING TABLESPACE DATA'|| to_char(v_date_from+i,'YYYY')||';');
   END LOOP;
END;

-- Them du lieu deu co cac partition theo ngay
declare
    v_commit number :=0;
    v_reset_date number;
    v_start date := to_date('01/01/2026','dd/mm/yyyy');
BEGIN
FOR v_LoopCounter IN 1..100000 LOOP
    if v_start = to_date('31/12/2026','dd/mm/yyyy') then
        v_start := to_date('01/01/2026','dd/mm/yyyy');
    end if;
    INSERT INTO OAZ29.bang_to (bang_toID, LastName, FirstName, Address, City,create_date) 
    VALUES (TO_CHAR(v_LoopCounter),'Name'||v_LoopCounter,'FirstName'||v_LoopCounter,'HANOI','HANOI',v_start);
    v_start := v_start+1;
    v_commit := v_commit + 1;
    if v_commit=1000 then
        commit;
        v_commit :=1;
    end if;
END LOOP;
END;

-- Them du lieu deu co cac partition theo ngay:100 row
declare
    v_commit number :=0;
    v_reset_date number;
    v_start date := to_date('01/01/2025','dd/mm/yyyy');
BEGIN
    FOR v_LoopCounter IN 1..100 LOOP
        if v_start = to_date('31/12/2025','dd/mm/yyyy') then
            v_start := to_date('01/01/2025','dd/mm/yyyy');
        end if;
        INSERT INTO OAZ29.bang_to (bang_toID, LastName, FirstName, Address, City,create_date) 
        VALUES (TO_CHAR(v_LoopCounter),'Name'||v_LoopCounter,'FirstName'||v_LoopCounter,'HANOI','HANOI',v_start);
        v_start := v_start+1;
        v_commit := v_commit + 1;
        if v_commit=10 then
            commit;
            v_commit :=1;
        end if;
    END LOOP;
END;

select count(*) from OAZ29.bang_to ;


--Them 100.000 ro cho ngay hien tai (vd 20/06/2025)
BEGIN
    FOR v_LoopCounter IN 1..100000 LOOP
    INSERT INTO OAZ29.bang_to (bang_toID, LastName, FirstName, Address, City, create_date) 
    VALUES (TO_CHAR(v_LoopCounter),'Name'||v_LoopCounter,'FirstName'||v_LoopCounter,'HANOI','HANOI', sysdate);
    END LOOP;
    COMMIT;
END;

--Them 10.000 ro cho ngay hien tai (vd 20/06/2025)
BEGIN
    FOR v_LoopCounter IN 1..1000 LOOP
    INSERT INTO bang_to (bang_toID, LastName, FirstName, Address, City, create_date) 
    VALUES (TO_CHAR(v_LoopCounter),'Name'||v_LoopCounter,'FirstName'||v_LoopCounter,'HANOI','HANOI', sysdate);
    END LOOP;
    COMMIT;
END;

-- Ctrl+E lay Plan
Plan: Truoc gather
SELECT STATEMENT  ALL_ROWSCost: 99,537  Bytes: 538  Cardinality: 1  		
	2 PARTITION RANGE ALL  Cost: 99,537  Bytes: 538  Cardinality: 1  Partition #: 1  Partitions accessed #1 - #365	
		1 TABLE ACCESS FULL TABLE OAZ29.BANG_TO Cost: 99,537  Bytes: 538  Cardinality: 1  Partition #: 1  Partitions accessed #1 - #365

Plan: Sau gather
SELECT STATEMENT  ALL_ROWSCost: 99,266  Bytes: 10,005,000  Cardinality: 200,100  		
	2 PARTITION RANGE ALL  Cost: 99,266  Bytes: 10,005,000  Cardinality: 200,100  Partition #: 1  Partitions accessed #1 - #365	
		1 TABLE ACCESS FULL TABLE OAZ29.BANG_TO Cost: 99,266  Bytes: 10,005,000  Cardinality: 200,100  Partition #: 1  Partitions accessed #1 - #365

		
select * from OAZ29.bang_to;


Plan
SELECT STATEMENT  ALL_ROWSCost: 99,265  Bytes: 100  Cardinality: 2  		
	2 PARTITION RANGE ALL  Cost: 99,265  Bytes: 100  Cardinality: 2  Partition #: 1  Partitions accessed #1 - #365	
		1 TABLE ACCESS FULL TABLE OAZ29.BANG_TO Cost: 99,265  Bytes: 100  Cardinality: 2  Partition #: 1  Partitions accessed #1 - #365

select * from OAZ29.bang_to where bang_toID=1234;

-- TAO GLOBAL INDEX
create index OAZ29.bang_to_ind1 on OAZ29.bang_to(bang_toID) tablespace INDX;

Plan
SELECT STATEMENT  ALL_ROWSCost: 3  Bytes: 100  Cardinality: 2  		
	2 TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED TABLE OAZ29.BANG_TO Cost: 3  Bytes: 100  Cardinality: 2  Partition #: 1  Partition access computed by row location	
		1 INDEX RANGE SCAN INDEX OAZ29.BANG_TO_IND1 Cost: 1  Cardinality: 2  
select * from OAZ29.bang_to where bang_toID=1234;


alter table OAZ29.bang_to truncate partition DATA20260101;
		
--Sau do index oaz25.bang_to_ind1 unusable do la global index 

Plan
SELECT STATEMENT  ALL_ROWSCost: 98,993  Bytes: 100  Cardinality: 2  		
	2 PARTITION RANGE ALL  Cost: 98,993  Bytes: 100  Cardinality: 2  Partition #: 1  Partitions accessed #1 - #365	
		1 TABLE ACCESS FULL TABLE OAZ29.BANG_TO Cost: 98,993  Bytes: 100  Cardinality: 2  Partition #: 1  Partitions accessed #1 - #365
		
select * from OAZ29.bang_to where bang_toID=1234;
		
-- Xu ly
alter index OAZ29.bang_to_ind1 rebuild online;

--+ Lay Plan
Plan
SELECT STATEMENT  ALL_ROWSCost: 3  Bytes: 100  Cardinality: 2  		
	2 TABLE ACCESS BY GLOBAL INDEX ROWID BATCHED TABLE OAZ29.BANG_TO Cost: 3  Bytes: 100  Cardinality: 2  Partition #: 1  Partition access computed by row location	
		1 INDEX RANGE SCAN INDEX OAZ29.BANG_TO_IND1 Cost: 1  Cardinality: 2  
select * from OAZ29.bang_to where bang_toID=1234;


-- Muon khong bi unusable phai update global index
alter table OAZ29.bang_to truncate partition DATA20260102 update global indexes;

-- TAO LOCAL INDEX
create index OAZ29.bang_to_ind2 on OAZ29.bang_to(bang_toID) tablespace INDX local parallel 8 online ;

--Rebuild partition index ve tablespace tuong ung
DECLARE
   v_date_from   date    := to_date('01/01/2025','dd/mm/yyyy');
   v_date_to     date    := to_date('31/12/2025','dd/mm/yyyy');
   v_numday     number;
   v_tablespace varchar2(50):='INDX';
   cursor c1 is
     select a.* from DBA_PART_INDEXES a, DBA_TAB_PARTITIONS b where a.owner=B.TABLE_OWNER  and a.table_name=B.TABLE_NAME  and b.table_owner='OAZ29' and b.table_name='BANG_TO'  and a.index_name not like '%$%' and b.partition_name like '%20251231'  order by a.owner,a.index_name;
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

select * from OAZ29.bang_to where bang_toID=1234 and create_date>=to_date('21/06/2025','dd/mm/yyyy') and create_date<to_date('22/06/2025','dd/mm/yyyy');

--Plan
SELECT STATEMENT  ALL_ROWSCost: 2  			
	3 PARTITION RANGE SINGLE  Cost: 2  Bytes: 50  Cardinality: 1  Partition #: 1  Partitions accessed #172		
		2 TABLE ACCESS BY LOCAL INDEX ROWID BATCHED TABLE OAZ29.BANG_TO Cost: 2  Bytes: 50  Cardinality: 1  Partition #: 2  Partitions accessed #172	
			1 INDEX RANGE SCAN INDEX OAZ29.BANG_TO_IND2 Cost: 1  Cardinality: 1  Partition #: 3  Partitions accessed #172



select * from OAZ29.bang_to where lastname like 'Binh%' and create_date>=to_date('21/06/2025','dd/mm/yyyy') and create_date<to_date('22/06/2025','dd/mm/yyyy');

--Plan: Full partition #172
SELECT STATEMENT  ALL_ROWSCost: 274  Bytes: 50  Cardinality: 1  		
	2 PARTITION RANGE SINGLE  Cost: 274  Bytes: 50  Cardinality: 1  Partition #: 1  Partitions accessed #172	
		1 TABLE ACCESS FULL TABLE OAZ29.BANG_TO Cost: 274  Bytes: 50  Cardinality: 1  Partition #: 2  Partitions accessed #172


--Giai phap: Dung SQL Tunning Advisor
create index OAZ29.IDX$$_00220001 on OAZ29.BANG_TO("LASTNAME") tablespace INDX local parallel 8 online;

alter index OAZ29.IDX$$_00220001 noparallel ;

-- Cau lenh quet ko co partiiton_key
select * from OAZ29.bang_to where lastname like 'Binh%' and create_date>=to_date('21/06/2025','dd/mm/yyyy') and create_date<to_date('22/06/2025','dd/mm/yyyy');

--Plan: Quet 1 partion va theo index
SELECT STATEMENT  ALL_ROWSCost: 2  Bytes: 50  Cardinality: 1  			
	3 PARTITION RANGE SINGLE  Cost: 2  Bytes: 50  Cardinality: 1  Partition #: 1  Partitions accessed #172		
		2 TABLE ACCESS BY LOCAL INDEX ROWID BATCHED TABLE OAZ29.BANG_TO Cost: 2  Bytes: 50  Cardinality: 1  Partition #: 2  Partitions accessed #172	
			1 INDEX RANGE SCAN INDEX OAZ29.IDX$$_00220001 Cost: 1  Cardinality: 1  Partition #: 3  Partitions accessed #172




