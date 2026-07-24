Quản lý Undo data trong Oracle Database từ A-Z

Mục đích: 

Undo data là bản ghi sinh ra bởi các giao dịch DML
Ghi lại tất cả các giao dịch có thay đổi dữ liệu
Duy trì tối thiểu cho đến khi giao dịch kết thúc (commit, rollback , DDL)

Hỗ trợ: 
- Hoạt động rollback 

- Truy vấn đảm bảo tính nhất quán dữ liệu

- Oracle Flashback Query, Oracle Flashback Transaction và Oracle Flashback Table, chi tiết 

- Khôi phục lại các giao dịch lỗi

--1.Tạo undo tablespace

create undo tablespace UNDOTBS1 datafile '/u02/oradata/dbaviet/undotbs1.dbf' size 1g autoextend on next 100m;

create undo tablespace UNDOTBS2 datafile '/u02/oradata/dbaviet/undotbs2.dbf' size 1g autoextend on next 100m;

--2. BẬT TÍNH NĂNG QUẢN LÝ UNDO TỰ ĐỘNG
UNDO_MANAGEMENT = AUTO           # Mặc định là MANUAL
UNDO_TABLESPACE = UNDOTBS1   # Tên undo tablespace.
UNDO_RETENTION  = 900                     # Thời gian dữ liệu undo còn lưu trong undo trước khi bị ghi đè, mặc định là  900 giây --> Tham số này nên đặt tầm 6h (21600s), 12h (43200s) hoặc 24h (86400) để trong trường hợp cần thiết có thể flashback lại dữ liệu mà nghiệp vụ đã commit nhầm, tuy nhiên sẽ tốn dung lượng tablespace undo một ít.
                          
--3. Quản lý

-- Autoextend datafile:
alter  tablespace UNDOTBS1 datafile '/u02/oradata/dbaviet/undotbs1.dbf' autoextend on next 100m;

-- Thêm datafile:
alter  tablespace UNDOTBS1 add datafile '/u02/oradata/dbaviet/undotbs1_2.dbf' size 1g autoextend on next 100m;

-- Resize datafile:
alter  database datafile '/u02/oradata/dbaviet/undotbs1.dbf' resize 100m;

-- Thực hiện backup:
ALTER TABLESPACE undotbs1 BEGIN BACKUP;
ALTER TABLESPACE undotbs1 END BACKUP;

-- Thay đổi undo tablespace mới do tạo dung lượng undo tablespace lớn quá, cần thu hồi:

select * From gv$instance;

alter system set undo_tablespace=UNDOTBS1_NEW sid='dbaviet1';

alter system set undo_tablespace=UNDOTBS2_NEW sid='dbaviet2';

--+ RESTARTTẠI TỪNG INSTANCE

SQL> shutdown immediate
SQL> startup

-- Check lai
select * from gv$parameter where name like '%undo%'

- Drop undo tablespace

DROP TABLESPACE UNDOTBS1 including contents and datafiles;
DROP TABLESPACE UNDOTBS2 including contents and datafiles;

--4. MONITOR

-- Các view sử dụng:
	• V$UNDOSTAT
	• V$ROLLSTAT
	• V$TRANSACTION
	• DBA_UNDO_EXTENTS

-- Hiển thị các transaction cần rollback và thời gian tương ứng
select usn, state, undoblockstotal "Total", undoblocksdone "Done", undoblockstotal-undoblocksdone "ToDo",decode(cputime,0,'unknown',sysdate+(((undoblockstotal-undoblocksdone) / (undoblocksdone / cputime)) / 86400)) "Estimated time to complete"from v$fast_start_transactions;

--Hiển thị dung lượng trống của tablespace UNDOTBS1 UNDOTBS2
SELECT  a.tablespace_name,100 - ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Usage",
    ROUND (a.bytes_alloc / 1024 / 1024) "Size MB",
    ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) "Used MB",
    ROUND (NVL (b.bytes_free, 0) / 1024 / 1024) "Free MB",
    --ROUND ( (NVL (b.bytes_free, 0) / a.bytes_alloc) * 100) "%Free",
    ROUND (maxbytes / 1048576)  "Max MB",
    round(maxbytes/1048576-(ROUND (a.bytes_alloc / 1024 / 1024)- ROUND (NVL (b.bytes_free, 0) / 1024 / 1024)),0) "Free_MB_Max",
    ROUND (ROUND ( (a.bytes_alloc - NVL (b.bytes_free, 0)) / 1024 / 1024)/  ROUND (maxbytes / 1048576) * 100) "%Used of Max"
    FROM (SELECT f.tablespace_name, SUM (f.bytes) bytes_alloc,  SUM (DECODE (f.autoextensible, 'YES', f.maxbytes, 'NO', f.bytes)) maxbytes
            FROM dba_data_files f
            GROUP BY tablespace_name) a,
        (SELECT f.tablespace_name, SUM (f.bytes) bytes_free  FROM dba_free_space f  GROUP BY tablespace_name) b
 WHERE a.tablespace_name = b.tablespace_name(+)  and  (a.tablespace_name in ('UNDOTBS1','UNDOTBS1'))
 order by "%Used of Max" desc;

--Kiểm tra session nào đang sử dụng:
SELECT s.username,
       s.sid,
       s.serial#,
       t.used_ublk,
       t.used_urec,
       rs.segment_name,
       r.rssize,
       r.status
FROM   v$transaction t,
       v$session s,
       v$rollstat r,
       dba_rollback_segs rs
WHERE  s.saddr = t.ses_addr
AND    t.xidusn = r.usn
AND    rs.segment_id = t.xidusn
ORDER BY t.used_ublk DESC;

select * from dba_data_Files where tablespace_name in ('UNDOTBS1','UNDOTBS21');

--/data/oradata/dbaviet/undotbs01.dbf    2    UNDOTBS1    25674383360 --> Node 1
--/data/oradata/dbaviet/undotbs22_1.dbf    62    UNDOTBS21    6442450944 --> Node 2
--/data/oradata/dbaviet/undotbs22_002.dbf    66    UNDOTBS21    2215641088
--/data/oradata/dbaviet/undotbs22_003.dbf    87    UNDOTBS21    2064646144
--/data/oradata/dbaviet/undotbs22_004.dbf    88    UNDOTBS21    773849088

--5. TỐI ƯU THAM SỐ UNDO RETENTION

Undotablespace đang có dung lượng là 32GB, trong khoảng thời gian phân tích từ 1:42:13 ngày 15/04/2022 - 1:42:13 ngày 22/04/2022 đã bao chùm tất cả các thời điểm cao tải của nghiệp vụ rồi, Oracle khuyến nghị có thể đáp ứng với thời gian cho undo_retention là 168562 (s) tức 46.8 giờ (nếu  muốn tăng thêm thời gian thì phải thêm datafile cho undo tablespace, còn muốn giảm thời gian thì resize datafile undo tablespace hoặc tạo lại undo tablespace với kích thước nhỏ hơn)
