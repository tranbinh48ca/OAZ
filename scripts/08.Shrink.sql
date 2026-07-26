--3.045.064.1704 bytes ~3G
select sum(bytes) from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

--100000
select count(*) from oaz29.bang_to;

delete oaz29.bang_to;
commit;

--0
select count(*) from oaz29.bang_to;

--3.045.064.704 bytes ~3G
select sum(bytes) from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

-- Cho phép row movement.
ALTER TABLE oaz29.bang_to ENABLE ROW MOVEMENT;

-- Khôi ph?c không gian luu tr? và s?a d?i high water mark (HWM): 2s
ALTER TABLE oaz29.bang_to SHRINK SPACE;

-- Khôi ph?c không gian luu tr? nhung không s?a d?i the high water mark (HWM).
--ALTER TABLE oaz29.bang_to SHRINK SPACE COMPACT;

-- Recover không gian luu tr? cho d?i tu?ng và m?i d?i tu?ng ph? thu?c
--ALTER TABLE oaz29.bang_to SHRINK SPACE CASCADE;

--71.368.704 --> 71M
select sum(bytes) from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

--Moi Parttition la 196K
select * from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

truncate table oaz29.bang_to ;

--71.368.704 --> 71M
select sum(bytes) from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

--Moi Parttition la 196K
select * from dba_segments where owner='OAZ29' and segment_name='BANG_TO';

-- shrink m?t do?n LOB (t?p co b?n ch? cho d?n 21c).
ALTER TABLE table_name MODIFY LOB(lob_column) (SHRINK SPACE);
ALTER TABLE table_name MODIFY LOB(lob_column) (SHRINK SPACE CASCADE);

-- shrink phân do?n tràn IOT.
ALTER TABLE iot_name OVERFLOW SHRINK SPACE;

--20 object lon nhat
SET LINESIZE 200
COLUMN owner FORMAT A30
COLUMN segment_name FORMAT A30
COLUMN tablespace_name FORMAT A30
COLUMN size_mb FORMAT 99999999.00

SELECT *
FROM   (SELECT owner,
               segment_name,
               segment_type,
               tablespace_name,
               ROUND(bytes/1024/1024,2) size_mb
        FROM   dba_segments
        ORDER BY 5 DESC)
WHERE  ROWNUM <= 20;

--B?n có th? th?y nhi?u segment l?n hon là phân khúc LOB. B?n có th? nh?n thêm thông tin c? th? v? các phân do?n LOB b?ng cách s? d?ng truy v?n top-n sau dây.

SET LINESIZE 200
COLUMN owner FORMAT A30
COLUMN table_name FORMAT A30
COLUMN column_name FORMAT A30
COLUMN segment_name FORMAT A30
COLUMN tablespace_name FORMAT A30
COLUMN size_mb FORMAT 99999999.00

SELECT *
FROM   (SELECT l.owner,
               l.table_name,
               l.column_name,
               l.segment_name,
               l.tablespace_name,
               ROUND(s.bytes/1024/1024,2) size_mb
        FROM   dba_lobs l
               JOIN dba_segments s ON s.owner = l.owner AND s.segment_name = l.segment_name
        ORDER BY 6 DESC)
WHERE  ROWNUM <= 20;


--large_segments.sql: Hi?n th? size segment l?n nh?t
SET LINESIZE 500 VERIFY OFF
COLUMN owner FORMAT A30
COLUMN segment_name FORMAT A30
COLUMN tablespace_name FORMAT A30
COLUMN size_mb FORMAT 99999999.00

SELECT *
FROM   (SELECT owner,
               segment_name,
               segment_type,
               tablespace_name,
               ROUND(bytes/1024/1024,2) size_mb
        FROM   dba_segments
        ORDER BY 5 DESC)
WHERE  ROWNUM <= &1;

SET VERIFY ON
--large_lob_segments.sql: Hi?n th? size segment LOB l?n nh?t
SET LINESIZE 500 VERIFY OFF
COLUMN owner FORMAT A30
COLUMN table_name FORMAT A30
COLUMN column_name FORMAT A30
COLUMN segment_name FORMAT A30
COLUMN tablespace_name FORMAT A30
COLUMN size_mb FORMAT 99999999.00

SELECT *
FROM   (SELECT l.owner,
               l.table_name,
               l.column_name,
               l.segment_name,
               l.tablespace_name,
               ROUND(s.bytes/1024/1024,2) size_mb
        FROM   dba_lobs l
               JOIN dba_segments s ON s.owner = l.owner AND s.segment_name = l.segment_name
        ORDER BY 6 DESC)
WHERE  ROWNUM <= &1;

--Check Row Movement
SELECT row_movement
FROM   dba_tables
WHERE  table_name = 'BANG_TO';

ROW_MOVE
--------
DISABLED

SQL>

Row movement du?c b?t b?ng l?nh sau.

ALTER TABLE emp ENABLE ROW MOVEMENT;

