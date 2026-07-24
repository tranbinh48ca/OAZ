--Cấu hình Audit DDL Log Oracle Database
--Mục đích: Lưu log các thao tác DDL (drop table, create table, drop procedure, drop package,...) để truy vết các thao tác của DBA hay quản trị ứng dụng (có dùng user DB) làm sai, nhầm.
create tablespace data_log  datafile size 1M autoextend on next 10m;

create tablespace indx_log  datafile size 1M autoextend on next 10m;
 
--1. Tạo bản lưu log

--drop table SYS.DDL_LOG purge;
--alter table SYS.DDL_LOG modify SQL_TEXT     VARCHAR2(4000 BYTE);

CREATE TABLE SYS.DDL_LOG
(
  USER_NAME    VARCHAR2(30 BYTE),
  IP_ADDRESS   VARCHAR2(30 BYTE),
  HOSTNAME     VARCHAR2(30 BYTE),
  DDL_DATE     DATE,
  DDL_TYPE     VARCHAR2(30 BYTE),
  OBJECT_TYPE  VARCHAR2(18 BYTE),
  OWNER        VARCHAR2(30 BYTE),
  OBJECT_NAME  VARCHAR2(128 BYTE),
  SQL_TEXT     VARCHAR2(2000 BYTE)
)
TABLESPACE DATA_LOG
PCTUSED    0
PCTFREE    10
INITRANS   1
MAXTRANS   255
STORAGE    (
            INITIAL          64K
            NEXT             1M
            MINEXTENTS       1
            MAXEXTENTS       UNLIMITED
            PCTINCREASE      0
            BUFFER_POOL      DEFAULT
           )
LOGGING 
NOCOMPRESS 
NOCACHE
MONITORING; 

CREATE INDEX SYS.DDL_LOG_I1 ON SYS.DDL_LOG
(DDL_DATE)
LOGGING
TABLESPACE INDX_LOG
PCTFREE    10
INITRANS   2
MAXTRANS   255
STORAGE    (
            INITIAL          64K
            NEXT             1M
            MINEXTENTS       1
            MAXEXTENTS       UNLIMITED
            PCTINCREASE      0
            BUFFER_POOL      DEFAULT
           );

--2. Tạo trigger bắt log DDL

CREATE OR REPLACE TRIGGER SYS.ddl_trig
    AFTER DDL
    ON DATABASE
--ON binhtv.tab1 -- Chỉ giám sát 1 bảng
DECLARE
    ip_addr      VARCHAR2 (30);
    hostname     VARCHAR2 (30);
    l_count      NUMBER;
    l_sql_text   ora_name_list_t;
    l_sql        VARCHAR2 (4000);
BEGIN
    l_count := ora_sql_txt (l_sql_text);

    IF l_count > 1
    THEN
        l_sql := l_sql_text (1) || l_sql_text (2);
    ELSE
        l_sql := l_sql_text (1);
    END IF;

    SELECT   SYS_CONTEXT ('USERENV', 'IP_ADDRESS') INTO ip_addr FROM DUAL;

    SELECT   SYS_CONTEXT ('USERENV', 'HOST') INTO hostname FROM DUAL;

    --IF (ip_addr NOT LIKE '192.168.1.%')
    --THEN
        INSERT INTO ddl_log (user_name,ip_address,hostname,ddl_date,ddl_type,object_type,
                             owner,object_name,sql_text)
          VALUES   (ora_login_user,ip_addr,hostname,SYSDATE,ora_sysevent,ora_dict_obj_type,
                    ora_dict_obj_owner,ora_dict_obj_name,l_sql);
    --END IF;

END ddl_trig;
/

--3. Test
--SYS
CREATE TABLE oaz29.tab11 (col1 DATE);

DROP TABLE oaz29.tab11;

--oaz29
CREATE TABLE oaz29.tab11 (col1 DATE);

truncate table oaz29.tab11;

DROP TABLE oaz29.tab11;

CREATE OR REPLACE FUNCTION oaz29.check_ip_machine
return number
is
begin
--    if (SYS_CONTEXT('USERENV', 'SESSION_USER') <> 'BINHTV'
--         and (SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  like '192.168.1%' or SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  like '1192.168.2%'
--        )) then
    if (SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.1.%' and
        SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.2.%' and
        SYS_CONTEXT ('USERENV', 'IP_ADDRESS')  not like '192.168.3.%')  then
        return 1;
    else
        return 0;
    end if;
end;

--4. Kiểm tra log

SELECT * FROM sys.DDL_LOG order by ddl_date desc;

SQL> colum owner format A10;
SQL> column object_name format A30;
SQL> column original_name format A30;

select * from dba_recyclebin;

ALTER TABLE "oaz29"."TAB11" RENAME TO "BIN$TMKTore2F4TgY4C2qMAKWg==$00" 

SELECT * FROM oaz29."BIN$VHUY6rfhF97gY4C2qMBAaA==$0";


select * from oaz29.tab11 ;

select * from dba_recyclebin;

purge dba_recyclebin;

select * from dba_segments where tablespace_name='USERS'
and  segment_name like '%TAB11%';

-- Flashback before drop

flashback table oaz29.tab11 to before drop;

select * from oaz29.tab11 ;



