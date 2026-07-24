create user app_owner identified by oracle;
grant connect, resource, dba to app_owner;

--alter user app_owner identified by app_owner;

create user binhtv identified by oracle;
grant connect, resource, select any table to binhtv;

create user user1 identified by oracle;
grant connect, resource, select any table to user1;

create user user2 identified by oracle;
grant connect, resource, select any table to user2;

--SYS
--Buoc 1 – Tao bang và d lieu mau
CREATE TABLE app_owner.customers (
  id   NUMBER,
  name VARCHAR2(100),
  ssn  VARCHAR2(11)
);

INSERT INTO customers VALUES (1, 'Nguyen Van A', '123-45-6789');
INSERT INTO customers VALUES (2, 'Tran Thi B',  '234-56-7890');
COMMIT;

-- Buoc 2 – Cap quyen can thiet
GRANT EXECUTE ON DBMS_REDACT TO app_owner;

-- Buoc 3 – Tao chính sách redaction
BEGIN
  DBMS_REDACT.ADD_POLICY(
    object_schema   => 'APP_OWNER',
    object_name     => 'CUSTOMERS',
    column_name     => 'SSN',
    policy_name     => 'REDACT_SSN',
    function_type   => DBMS_REDACT.FULL,
    expression      => 'SYS_CONTEXT(''USERENV'', ''SESSION_USER'') <> ''APP_OWNER'''
  );
END;
/

-- Buoc 4 – Kiem tra ket qua dau ra
--Khi dang nhap bang APP_OWNER:
SELECT name, ssn FROM customers;

-- Ketqua:
-- Nguyen Van A | 123-45-6789
-- Tran Thi B   | 234-56-7890

-- Khi dang nhap bang user khac APP_OWNER:
SELECT name, ssn FROM customers;

-- Ket qua: Bi trong o ket qua
--Nguyen Van A |	 
--Tran Thi B   | 

-- Ðúng nhu mong doi: Chi ADMIN thay rõ du lieu thet, còn lai bi che, khong hien thi

-- Buoc 5 – Xoá hoac sua chính sách neu can
-- Xoá:
BEGIN
  DBMS_REDACT.DROP_POLICY(
    object_schema => 'HR',
    object_name   => 'CUSTOMERS',
    policy_name   => 'REDACT_SSN'
  );
END;
/
