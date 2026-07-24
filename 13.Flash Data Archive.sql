--Flashback Data Archive (FDA) trong Oracle Database 11g
--Flashback Data Archive (FDA) , còn được gọi là Flashback Archive (FBA), được giới thiệu từ Oracle 11g để cung cấp khả năng lưu trữ lâu dài dữ liệu undo, cho phép thực hiện các hoạt động flashback dựa trên undo trong một khoảng thời gian dài.
--Tạo tablespace để FDA lưu 1 năm, tablespace khác lưu 2 năm, user test cần quyền flashback archive

CREATE TABLESPACE fda_ts  DATAFILE 
  SIZE 1M AUTOEXTEND ON NEXT 1M;
  
CREATE TABLESPACE fda_ts2  DATAFILE 
  SIZE 1M AUTOEXTEND ON NEXT 1M;  

CREATE FLASHBACK ARCHIVE DEFAULT fda_1year TABLESPACE fda_ts
  QUOTA 5G RETENTION 1 YEAR;

CREATE FLASHBACK ARCHIVE fda_2year TABLESPACE fda_ts
  RETENTION 2 YEAR;
  
--Có 3 kiểu cần quản lý:

--Quản lý Tablespace .

ALTER FLASHBACK ARCHIVE fda_1year SET DEFAULT;

ALTER FLASHBACK ARCHIVE fda_1year ADD TABLESPACE fda_ts2 QUOTA 5G;

ALTER FLASHBACK ARCHIVE fda_1year ADD TABLESPACE fda_ts2;

ALTER FLASHBACK ARCHIVE fda_1year REMOVE TABLESPACE fda_ts2;

ALTER FLASHBACK ARCHIVE fda_1year MODIFY TABLESPACE fda_ts2 QUOTA 6G;

ALTER FLASHBACK ARCHIVE fda_2year MODIFY TABLESPACE fda_ts2;

ALTER FLASHBACK ARCHIVE fda_1year REMOVE TABLESPACE fda_ts2;

--Chỉnh sửa thành 3 năm

ALTER FLASHBACK ARCHIVE fda_1year MODIFY RETENTION 3 YEAR;

--Xóa data.

-- Xóa toàn bộ dữ liệu lịch sử 
ALTER FLASHBACK ARCHIVE fda_1year PURGE ALL;

-- Xóa mọi dữ liệu theo thời gian nhất định
ALTER FLASHBACK ARCHIVE fda_1year PURGE BEFORE TIMESTAMP (SYSTIMESTAMP - INTERVAL '1' DAY);

-- Xóa mọi dữ liệu trước SCN.
ALTER FLASHBACK ARCHIVE fba_name PURGE BEFORE SCN 728969;

--Drop tablespace lưu flashback:

DROP FLASHBACK ARCHIVE fba_name;

--Tạo user:

CONN sys/password AS SYSDBA

CREATE USER fda_test_user IDENTIFIED BY oracle
  QUOTA UNLIMITED ON users
  QUOTA UNLIMITED ON fda_ts;

GRANT CONNECT, CREATE TABLE TO fda_test_user;

GRANT FLASHBACK ARCHIVE ON fda_1year TO fda_test_user;

GRANT FLASHBACK ARCHIVE ON fda_2year TO fda_test_user;

--Tạo bảng:

alter user fda_test_user identified by oracle;

CONN fda_test_user/oracle

CREATE TABLE fda_test_user.test_tab_1 (
  id          NUMBER,
  desription  VARCHAR2(50),
  CONSTRAINT test_tab_1_pk PRIMARY KEY (id)
)
FLASHBACK ARCHIVE;

--Nếu tạo bảng thiếu quyền FLASHBACK ARCHIVE sẽ hiển thị lỗi:

CONN fda_test_user/oracle

CREATE TABLE test_tab_2 (
  id          NUMBER,
  desription  VARCHAR2(50),
  CONSTRAINT test_tab_2_pk PRIMARY KEY (id)
)
FLASHBACK ARCHIVE fda_2year;
CREATE TABLE test_tab_2 (
*
ERROR at line 1:
ORA-55620: No privilege to use Flashback Archive


SQL>

--Thiết lập flashback cho bảng:

-- Kích hoạt sử dụng FBDA mặc định.

ALTER TABLE fda_test_user.test_tab_1 FLASHBACK ARCHIVE;

-- Cho phép sử dụng FBDA cụ thể.

ALTER TABLE fda_test_user.test_tab_1 FLASHBACK ARCHIVE fda_2year;

-- Tắt FBDA
ALTER TABLE fda_test_user.test_tab_1 NO FLASHBACK ARCHIVE;

--Nếu alter thiếu quyền FLASHBACK ARCHIVE ADMINISTER thì báo lỗi:

SQL> ALTER TABLE test_tab_1 NO FLASHBACK ARCHIVE;
ALTER TABLE test_tab_1 NO FLASHBACK ARCHIVE
*
ERROR at line 1:
ORA-55620: No privilege to use Flashback Archive

SQL>

--Kiểm tra lại từ view %_FLASHBACK_ARCHIVE:

CONN sys/password AS SYSDBA

COLUMN flashback_archive_name FORMAT A20

SELECT flashback_archive_name, retention_in_days, status
FROM   dba_flashback_archive;

FLASHBACK_ARCHIVE_NA RETENTION_IN_DAYS STATUS
-------------------- ----------------- -------
FDA_2YEAR                          730
FDA_1YEAR                          365 DEFAULT

2 rows selected.

SQL>

--View %_FLASHBACK_ARCHIVE_TS hiển thị thông tin tablespaces và quotas của flashback archive

COLUMN flashback_archive_name FORMAT A20
COLUMN quota_in_mb FORMAT A10

SELECT flashback_archive_name, tablespace_name, quota_in_mb
FROM   dba_flashback_archive_ts;

FLASHBACK_ARCHIVE_NA TABLESPACE_NAME                QUOTA_IN_M
-------------------- ------------------------------ ----------
FDA_2YEAR            FDA_TS
FDA_1YEAR            FDA_TS                         10240

2 rows selected.

SQL>

--View %_FLASHBACK_ARCHIVE_TABLES hiển thị flashback archive, tên bảng table lưu dữ liệu lịch sử:

COLUMN table_name FORMAT A15
COLUMN owner_name FORMAT A15
COLUMN flashback_archive_name FORMAT A20
COLUMN archive_table_name FORMAT A20

SELECT table_name, owner_name, flashback_archive_name, archive_table_name
FROM   dba_flashback_archive_tables;

TABLE_NAME      OWNER_NAME      FLASHBACK_ARCHIVE_NA ARCHIVE_TABLE_NAME
--------------- --------------- -------------------- --------------------
TEST_TAB_1      FDA_TEST_USER   FDA_1YEAR            SYS_FBA_HIST_72023

1 row selected.

SQL>

select rowid, a.* from fda_test_user.test_tab_1 a; 