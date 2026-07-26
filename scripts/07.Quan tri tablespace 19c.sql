--Quản lý Tablespaces trong Container Database (CDB) và Pluggable Database (PDB) trong Oracle Database 12c
--Mục đích: Hướng dẫn Quản lý Tablespaces trong Container Database (CDB) và Pluggable Database (PDB) trong Oracle Database 12c
--Quản lý Tablespaces trong CDB
--Quản lý Tablespaces trong PDB
--Undo Tablespaces
--Temporary Tablespaces
--Default Tablespaces
--QUẢN LÝ TABLESPACES TRONG CDB
--Quản lý tablespace trong container database (CDB) không khác gì với cơ sở dữ liệu không phải CDB (non-CDB). Miễn là bạn đã đăng nhập với tư cách là người dùng có đặc quyền và trỏ đến root container, các lệnh thông thường đều dùng được.

CONN / AS SYSDBA

SQL> SHOW CON_NAME

CON_NAME
------------------------------
CDB$ROOT

SQL> 

CREATE TABLESPACE dummy
  DATAFILE '/u01/app/oracle/oradata/cdb1/dummy01.dbf' SIZE 1M
  AUTOEXTEND ON NEXT 1M;
  
Tablespace created.

SQL>

ALTER TABLESPACE dummy ADD
  DATAFILE '/u01/app/oracle/oradata/cdb1/dummy02.dbf' SIZE 1M
  AUTOEXTEND ON NEXT 1M;
 
Tablespace altered.

SQL> 

DROP TABLESPACE dummy INCLUDING CONTENTS AND DATAFILES;

Tablespace dropped.

SQL>

--QUẢN LÝ TABLESPACES TRONG PDB
--Các lệnh quản lý tablespace dùng với mức root container vẫn dùng được với pluggable database (PDB), miễn là bạn trỏ đến đúng container. Bạn có thể kết nối bằng cách sử dụng một người dùng thông thường (common user), sau đó chuyển sang đúng container.

SQL> CONN / AS SYSDBA
Connected.

SQL> ALTER SESSION SET CONTAINER = pdb1;

Session altered.

SQL> SHOW CON_NAME

CON_NAME
------------------------------
PDB1

--Ngoài ra, có thể kết nối trực tiếp với PDB với tư cách là người dùng cục bộ có đủ đặc quyền.

SQL> CONN pdb_admin@pdb1
Enter password: oracle
Connected.

SQL> SHOW CON_NAME

CON_NAME
------------------------------
PDB1
SQL>

--Sau khi được trỏ đến đúng container, tablespace có thể được quản lý bằng cách sử dụng các lệnh tương tự như ở trên. Đảm bảo rằng bạn đặt các datafile ở vị trí thích hợp cho PDB.

SQL> CREATE TABLESPACE dummy
  DATAFILE '/u01/app/oracle/oradata/cdb1/pdb1/dummy01.dbf' SIZE 1M
  AUTOEXTEND ON NEXT 1M;
  
Tablespace created.

SQL> ALTER TABLESPACE dummy ADD
  DATAFILE '/u01/app/oracle/oradata/cdb1/pdb1/dummy02.dbf' SIZE 1M
  AUTOEXTEND ON NEXT 1M;
 
Tablespace altered.

SQL> DROP TABLESPACE dummy INCLUDING CONTENTS AND DATAFILES;

Tablespace dropped.

SQL>

--UNDO TABLESPACES
--Việc quản lý undo tablespace trong CDB không khác so với quản lý của cơ sở dữ liệu không phải CDB.

--Ngược lại, PDB không có undo tablespace. Thay vào đó, nó sử dụng undo tablespace  thuộc CDB. Nếu chúng ta kết nối với một PDB, chúng ta có thể thấy không có undo tablespace nào được hiển thị..

CONN pdb_admin@pdb1

SELECT tablespace_name FROM dba_tablespaces;

TABLESPACE_NAME
------------------------------
SYSTEM
SYSAUX
TEMP
USERS

SQL>

--Nhưng chúng ta có thể thấy datafile được liên kết với CDB undo tablespace.

SQL> SELECT name FROM v$datafile;

NAME
--------------------------------------------------------------------------------
/u01/app/oracle/oradata/cdb1/undotbs01.dbf
/u01/app/oracle/oradata/cdb1/pdb1/system01.dbf
/u01/app/oracle/oradata/cdb1/pdb1/sysaux01.dbf
/u01/app/oracle/oradata/cdb1/pdb1/pdb1_users01.dbf

SQL> SELECT name FROM v$tempfile;

NAME
--------------------------------------------------------------------------------
/u01/app/oracle/oradata/cdb1/pdb1/temp01.dbf

SQL>

--TEMPORARY TABLESPACES
--Việc quản lý Temporary Tablespaces trong CDB không khác so với quản lý của cơ sở dữ liệu không phải CDB.

--Một PDB có thể có Temporary Tablespace riêng, hoặc PDB được tạo mà không có Temporary Tablespace, PDB đó có thể chia sẻ Temporary Tablespace với CDB.

SQL> CONN pdb_admin@pdb1

SQL> CREATE TEMPORARY TABLESPACE temp2
  TEMPFILE '/u01/app/oracle/oradata/cdb1/pdb1/temp02.dbf' SIZE 5M
  AUTOEXTEND ON NEXT 1M;
  
Tablespace created.

SQL> DROP TABLESPACE temp2 INCLUDING CONTENTS AND DATAFILES;

Tablespace dropped.
TABLESPACE MẶC ĐỊNH

--Đặt tablespace mặc định và temporary tablespace mặc định cho CDB khôngkhác so với cơ sở dữ liệu không phải CDB.

--Có hai cách để đặt tablespace mặc định và temporary tablespace mặc định cho PDB. Lệnh ALTER PLUGGABLE DATABASE là cách được khuyến nghị sử dụng.

CONN pdb_admin@pdb1
ALTER PLUGGABLE DATABASE DEFAULT TABLESPACE users;
ALTER PLUGGABLE DATABASE DEFAULT TEMPORARY TABLESPACE temp;
Hoặc lệnh ALTER DATABASE.

CONN pdb_admin@pdb1
ALTER DATABASE DEFAULT TABLESPACE users;
ALTER DATABASE DEFAULT TEMPORARY TABLESPACE temp;
--Với cả hai cách trên, bạn phải trỏ đến container thích hợp để lệnh hoạt động (lệnh CONN pdb_admin@pdb1)