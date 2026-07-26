--0.View
--Nhuoc diem
--1.Role DBA thi khong bat duoc
--2.User khong khai bao IP thi khong duoc
--Sys.logon_trig

select * from DBA_TRIGGERS where trigger_name like '%LOGON_TRIG%';

drop trigger SYS.LOGON_TRIG;

drop table sys.table_ip purge;

select * from SYS.TABLE_IP_LOG ;

drop table SYS.TABLE_IP_LOG purge;

select rowid,a.* from sys.table_ip a;

commit;

revoke dba from user2;

revoke dba from user1;
 
--1.Thu thập IP kết nối vào DB
CREATE TABLE SYS.TABLE_IP_LOG
(
  USERNAME     VARCHAR2(50 BYTE),
  IP_ADDRESS   VARCHAR2(500 BYTE),
  DESCRIPTION  VARCHAR2(200 BYTE)
);

-- Tao trigger ghi log IP, tuong ung voi user
CREATE OR REPLACE TRIGGER SYS.LOGON_TRIG
 AFTER
 LOGON
 ON DATABASE
DECLARE
    v_ip   VARCHAR2 (1000);
BEGIN

    /* comment doan chan ket noi
SELECT   ip_address
      INTO   v_ip
      FROM   sys.table_ip
     WHERE   username = SYS_CONTEXT ('USERENV', 'SESSION_USER');

    IF sys.pck_admin.checkip (SYS_CONTEXT ('USERENV', 'IP_ADDRESS'),
                                    v_ip) or SYS_CONTEXT ('USERENV', 'HOST') in ('ORAAZ-HOST')

    THEN
        NULL;
    ELSE
        raise_application_error (
            -20001,
            'You are not allowed to connect to the database!');
    END IF;
*/
    insert into sys.table_ip_log (username,ip_address) values (SYS_CONTEXT ('USERENV', 'SESSION_USER'),SYS_CONTEXT ('USERENV', 'IP_ADDRESS'));
    commit;
EXCEPTION
    -- Nhung account ko duoc khai bao trong bang table_ip
    WHEN NO_DATA_FOUND THEN NULL;
END;


select * from SYS.TABLE_IP_LOG;

-- User1, user2 login test

-- Sys kiem tra IP da thu thap
select * from SYS.TABLE_IP_LOG;

create table SYS.TABLE_IP as select * from SYS.TABLE_IP_LOG;

select * from SYS.TABLE_IP;

--insert into  SYS.TABLE_IP select * from SYS.TABLE_IP_LOG;
--commit;

--select * from SYS.TABLE_IP;

--2.Cài đặt
--Thay đổi lại trigger LOGON_TRIG:
--CREATE TABLE SYS.TABLE_IP
--(
--  USERNAME     VARCHAR2(50 BYTE),
--  IP_ADDRESS   VARCHAR2(500 BYTE),
--  DESCRIPTION  VARCHAR2(200 BYTE)
--)

select rowid,a.* from SYS.TABLE_IP a;

commit;

create user oaz29 identified by oracle;
grant connect, resource to oaz29;

revoke dba from oaz28;

-- Tao trigger bat user truy cap dung IP da khi bao trong sys.table_Ip
CREATE OR REPLACE TRIGGER SYS.LOGON_TRIG
 AFTER
 LOGON
 ON DATABASE
DECLARE
    v_ip   VARCHAR2 (1000);
BEGIN

    
    SELECT   ip_address
      INTO   v_ip
      FROM   sys.table_ip
     WHERE   username = SYS_CONTEXT ('USERENV', 'SESSION_USER');

    IF sys.pck_admin.checkip (SYS_CONTEXT ('USERENV', 'IP_ADDRESS'),
                                    v_ip) or SYS_CONTEXT ('USERENV', 'HOST') in ('ORAAZ-HOST')

    THEN
        NULL;
    ELSE
        raise_application_error (
            -20001,
            'You are not allowed to connect to the database!');
    END IF;

    --insert into sys.table_ip_log (username,ip_address) values (SYS_CONTEXT ('USERENV', 'SESSION_USER'),SYS_CONTEXT ('USERENV', 'IP_ADDRESS'));
    commit;
EXCEPTION
    -- Nhung account ko duoc khai bao trong bang table_ip
    WHEN NO_DATA_FOUND THEN NULL;
END;
/

-- Doi ip 192.168.11.1 thanh 192.168.11.10
select rowid,a.* from SYS.TABLE_IP a;

--oaz2

revoke dba from user1;

revoke dba from user2;

-- Gan quyen DBA cho user1 user2
grant dba to user1; --Nhung USER1	192.168.182.77, ko duoc truy cap

-- Thuc te duoc truy cap do user1 co quyen DBA nen bypasss

revoke dba from user1;

-- Thu hoi quyen DBA tu c##oaz18
revoke dba from c##oaz29;

--CASE STUDY: USER2 KHONG KHAI BAO IP
select rowid,a.* from SYS.TABLE_IP a;

-- Xu ly
select username from dba_users where account_status='OPEN'
minus
select username from sys.table_ip
order by 1;

-- Tao trigger chi cho phep dang nhap tu TOAD
CREATE OR REPLACE TRIGGER SYS.LOGON_TRIG
 AFTER
 LOGON
 ON DATABASE
DECLARE
    v_ip   VARCHAR2 (1000);
    v_action varchar2(50);
BEGIN

--    SELECT   ip_address
--      INTO   v_ip
--      FROM   sys.table_ip
--     WHERE   username = SYS_CONTEXT ('USERENV', 'SESSION_USER');
     
     --select sys_context('USERENV','ACTION') into v_action from dual;
     
    insert into sys.xxx_client_info values(sys_context('USERENV','MODULE'));
    commit;
    
    if sys_context('USERENV','MODULE') in ('Toad.exe') then
        NULL;
    else raise_application_error (
            -20001,
            'Bạn phải dùng chương trình TOAD để kết nối vào Database');
    END IF; 
    


--    IF sys.pck_admin.checkip (SYS_CONTEXT ('USERENV', 'IP_ADDRESS'),
--                                    v_ip) or SYS_CONTEXT ('USERENV', 'HOST') in ('HOST-ORAAZ')
--
--    THEN
--        NULL;
--    ELSE
--        raise_application_error (
--            -20001,
--            'You are not allowed to connect to the database!');
--    END IF;

    --insert into table_ip_log (username,ip_address) values (SYS_CONTEXT ('USERENV', 'SESSION_USER'),SYS_CONTEXT ('USERENV', 'IP_ADDRESS'));
    --commit;
EXCEPTION
    -- Nhung account ko duoc khai bao trong bang table_ip
    WHEN NO_DATA_FOUND THEN NULL;
END;
/

select * from sys.xxx_cli ent_info;


-- Sua IP USER1 thanh 192.168.182.2
select rowid, a.* from sys.table_ip a;

-- User1 login lai bao loi: 
revoke dba from user1;

revoke dba from user2;

--User1, user2 la DBA thi bypass

revoke dba from user1;

revoke dba from user2;

--Login lai bao loi

-- Sua IP user1 thanh 192.168.182.1
select rowid, a.* from sys.table_ip a;

--3.Khắc phục sự cố
-- Trong trường hợp cần thiết có thể xoá trigger đi:
DROP TRIGGER SYS.LOGON_TRIG;

--Package SYS.pck_admin

CREATE OR REPLACE PACKAGE SYS.pck_admin
  IS
Function ConvertIP(p_IP varchar2)
    Return Varchar2;

  FUNCTION checkIP (p_ip VARCHAR2, p_Grant_IP Varchar2)
      RETURN BOOLEAN;
END;
/
CREATE OR REPLACE PACKAGE BODY SYS.pck_admin
IS
   FUNCTION convertip (p_ip VARCHAR2)
      RETURN VARCHAR2
   AS
      v_resuilt   VARCHAR2 (12);
      v_temp      VARCHAR2 (4);
      v_i         NUMBER;
      v_ip        VARCHAR2 (15);
   BEGIN
      v_ip := p_ip;
      v_resuilt := NULL;

      IF LENGTH (v_ip) = 15
      THEN
         v_resuilt := REPLACE (v_ip, '.', NULL);
      ELSE
         v_i := 1;

         WHILE v_ip IS NOT NULL
         LOOP
            v_i := INSTR (v_ip, '.', 1);

            IF v_i > 0
            THEN
               v_temp := SUBSTR (v_ip, 1, v_i - 1);
               v_ip := TRIM (SUBSTR (v_ip, v_i + 1));
            ELSE
               v_temp := SUBSTR (v_ip, 1);
               v_ip := NULL;
            END IF;

            IF LENGTH (v_temp) < 3
            THEN
               SELECT LPAD (v_temp, 3, '0')
                 INTO v_temp
                 FROM DUAL;
            END IF;

            v_resuilt := v_resuilt || TRIM (v_temp);
         END LOOP;
      END IF;

      RETURN v_resuilt;
   EXCEPTION
      WHEN OTHERS
      THEN
         RETURN NULL;
   END;

   FUNCTION checkip (p_ip VARCHAR2, p_grant_ip VARCHAR2)
      RETURN BOOLEAN
   AS
      v_ip         VARCHAR2 (20);
      v_grant_ip   VARCHAR2 (1500);
      v_grantip    VARCHAR2 (50);
      v_startip    VARCHAR2 (50);
      v_endip      VARCHAR2 (50);
      v_start      NUMBER;
      v_fix        NUMBER;
   BEGIN
      v_ip := convertip (p_ip);
      v_start := 1;
      v_grant_ip := p_grant_ip || ';';

      FOR i IN 1 .. LENGTH (v_grant_ip)
      LOOP
         IF SUBSTR (v_grant_ip, i, 1) = ',' OR SUBSTR (v_grant_ip, i, 1) =
                                                                          ';'
         THEN
            v_grantip := SUBSTR (v_grant_ip, v_start, i - v_start);
            v_fix := INSTR (v_grantip, '-');

            IF v_fix > 1
            THEN                                                     --dai ip
               v_startip := SUBSTR (v_grantip, 1, v_fix - 1);
               v_endip := SUBSTR (v_grantip, v_fix + 1);

               IF     v_ip >= convertip (v_startip)
                  AND v_ip <= convertip (v_endip)
               THEN
                  RETURN TRUE;
               END IF;
            ELSE                                               --1 ip xac dinh
               IF v_ip = convertip (v_grantip)
               THEN
                  RETURN TRUE;
               END IF;
            END IF;

            v_start := i + 1;
         END IF;
      END LOOP;

      RETURN FALSE;
   END;
END;
/