---
name: oracle-troubleshoot-performance-tuning
description: >
  Case study khắc phục lỗi Tối ưu Hiệu năng Oracle Database: AWR/ASH analysis,
  execution plan, index design, SQL tuning, memory/IO, wait events, partitioning,
  parallel execution, In-Memory. Kích hoạt khi hỏi về: database slow Oracle,
  query chậm Oracle, execution plan changed, full table scan unexpected,
  high CPU Oracle, buffer cache hit ratio low, wait event analysis,
  SQL tuning advisor failed, index not used Oracle, statistics stale,
  cardinality estimate wrong, parallel query not working, ORA-04031 tuning,
  latch contention Oracle, library cache contention, sequence cache low RAC,
  partition pruning not working, In-Memory not populated.
---

# SK10-CASE-05 · Troubleshooting: Tối ưu Hiệu năng Oracle Database

**Phạm vi:** AWR/ASH Analysis, Execution Plan, Index, SQL Tuning, Memory/IO, Partitioning, Parallel, In-Memory
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)
**Số lượng case:** 40 cases thực chiến — Format: Vấn đề → Nguyên nhân → Xử lý → Bài học → Phòng ngừa

---

## KIẾN TRÚC TỔNG QUAN PERFORMANCE TROUBLESHOOTING

```
Oracle Performance Degradation — Diagnostic Decision Tree
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────────┐
│            "DATABASE CHẬM" — Triệu chứng ban đầu          │
└───────────────────────┬─────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
   System-wide      Specific SQL    Specific Time
   (mọi query)       (1 vài query)   (chỉ lúc nào đó)
         │               │               │
┌────────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
│ Group A:       │ │ Group B:     │ │ Group A:     │
│ AWR/ASH/Memory │ │ Execution    │ │ AWR snapshot │
│ (Case 1-10)    │ │ Plan/Index   │ │ comparison   │
│                │ │ (Case 11-25) │ │              │
└────────┬───────┘ └──────┬───────┘ └──────────────┘
         │                │
         ▼                ▼
┌─────────────────┐ ┌──────────────┐
│ Group C:         │ │ Group D:      │
│ Partitioning/     │ │ Parallel/     │
│ Wait Events        │ │ In-Memory     │
│ (Case 26-33)        │ │ (Case 34-40)  │
└──────────────────┘ └──────────────┘

Severity: 🔴 CRITICAL (business impact cao) | 🟡 DEGRADED | 🟢 OPTIMIZATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## NHÓM A: AWR/ASH ANALYSIS & MEMORY (Case 1-10)

### Case 1: Database chậm đột ngột toàn diện, không rõ nguyên nhân

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Tất cả queries trên toàn hệ thống đều chậm hơn bình thường đáng kể (response time tăng 3-5 lần), ảnh hưởng toàn bộ user, gây bức xúc lan rộng nhưng chưa rõ root cause.

**2. Nguyên nhân**
Có thể là 1 trong nhiều nguyên nhân: CPU saturation, I/O bottleneck, memory pressure, lock contention lan rộng, hoặc 1 SQL "rogue" đột nhiên tiêu tốn resource quá mức ảnh hưởng tới toàn hệ thống.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Snapshot ngay lập tức (5 phút đầu tiên là vàng)
SELECT event, wait_class, COUNT(*) sessions_waiting
FROM v$session WHERE type='USER' AND status='ACTIVE' AND wait_class!='Idle'
GROUP BY event, wait_class ORDER BY sessions_waiting DESC;

-- Bước 2: System metrics tổng quan
SELECT metric_name, value FROM v$sysmetric WHERE group_id=2
  AND metric_name IN ('Host CPU Utilization (%)','Average Active Sessions',
    'Buffer Cache Hit Ratio','Physical Read Total IO Requests Per Sec');

-- Bước 3: Top SQL đang chạy
SELECT s.sid, s.seconds_in_wait, s.event,
       SUBSTR(q.sql_text,1,80) sql_text
FROM v$session s, v$sql q WHERE s.sql_id=q.sql_id
  AND s.type='USER' AND s.status='ACTIVE'
ORDER BY s.seconds_in_wait DESC FETCH FIRST 10 ROWS ONLY;
```

**4. Bài học kinh nghiệm**
"Database chậm" là triệu chứng quá chung chung — quy trình chẩn đoán phải có THỨ TỰ CỐ ĐỊNH (đã chuẩn hóa thành script) để không lãng phí thời gian "đoán mò" trong những phút đầu quan trọng nhất.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Chuẩn bị sẵn script chẩn đoán nhanh (xem SK05-08, SK09-01) chạy được trong < 1 phút, không cần soạn SQL lúc đang khủng hoảng.
- Thiết lập AWR snapshot interval ngắn hơn (15 phút thay vì 60 phút mặc định) trên hệ thống critical để có nhiều data point hơn khi cần phân tích retrospective.
- Baseline performance metrics bình thường (qua AWR Baseline) để so sánh nhanh "chậm so với baseline nào".

---

### Case 2: Buffer Cache Hit Ratio thấp bất thường (< 90%)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 I/O subsystem chịu tải cao hơn cần thiết, physical reads tăng vọt, ảnh hưởng latency toàn hệ thống dù chưa tới mức nghiêm trọng.

**2. Nguyên nhân**
Buffer Cache quá nhỏ so với working set của database, hoặc có 1 batch job/report chạy full table scan trên bảng lớn "đẩy" các blocks hot khác ra khỏi cache (cache flush).

**3. Thủ tục xử lý**
```sql
SELECT ROUND((1 - phys_reads/(db_blk_gets+consist_gets))*100,2) hit_ratio
FROM (SELECT SUM(value) phys_reads FROM v$sysstat WHERE name='physical reads'),
     (SELECT SUM(value) db_blk_gets FROM v$sysstat WHERE name='db block gets'),
     (SELECT SUM(value) consist_gets FROM v$sysstat WHERE name='consistent gets');

-- Xem advice tăng cache có lợi không
SELECT size_for_estimate, ROUND(estd_physical_read_factor,2) io_factor
FROM v$db_cache_advice WHERE name='DEFAULT' ORDER BY size_for_estimate;

-- Nếu io_factor giảm đáng kể khi tăng size -> đáng để tăng
ALTER SYSTEM SET db_cache_size=16G SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
Hit ratio thấp KHÔNG LUÔN đồng nghĩa "cần tăng cache" — cần dùng `v$db_cache_advice` để định lượng lợi ích trước khi tăng (tránh lãng phí RAM cho lợi ích không đáng kể).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tách riêng buffer pool KEEP cho objects hot quan trọng, RECYCLE cho full-scan batch jobs lớn để tránh chúng "đá" lẫn nhau khỏi Default Pool.
- Schedule batch jobs/reports nặng I/O vào giờ thấp điểm, tránh giờ cao điểm OLTP.

---

### Case 3: PGA over-allocation, sort spill ra disk thường xuyên

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Sort/Hash operations chậm đáng kể do phải dùng TEMP tablespace (disk) thay vì hoàn toàn trong memory, ảnh hưởng các báo cáo/query có ORDER BY, GROUP BY, HASH JOIN trên dữ liệu lớn.

**2. Nguyên nhân**
`pga_aggregate_target` quá nhỏ so với workload thực tế (nhiều session chạy sort/hash đồng thời).

**3. Thủ tục xử lý**
```sql
SELECT name, value FROM v$pgastat
WHERE name IN ('over allocation count','extra bytes read/written');

SELECT pga_target_for_estimate, estd_pga_cache_hit_percentage
FROM v$pga_target_advice ORDER BY pga_target_for_estimate;

ALTER SYSTEM SET pga_aggregate_target=8G SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
"extra bytes read/written" > 0 là chỉ báo trực tiếp của sort spill — đây là metric nên đưa vào dashboard giám sát thường xuyên thay vì chỉ phát hiện khi user complain về báo cáo chậm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Sizing PGA dựa trên workload thực tế qua `v$pga_target_advice`, review lại mỗi 6 tháng khi data volume tăng trưởng, không chỉ set 1 lần lúc go-live rồi quên.

---

### Case 4: Library Cache Hit Ratio thấp, hard parse cao

**1. Vấn đề / Mức độ ảnh hưởng**
🟡-🔴 CPU tiêu tốn nhiều cho việc parse SQL lặp lại thay vì execute, có thể dẫn tới ORA-04031 (xem SK10-01 Case 2) nếu nghiêm trọng.

**2. Nguyên nhân**
Application không dùng bind variables (mỗi query là 1 literal SQL khác nhau), khiến Oracle phải hard parse mỗi lần thay vì tái sử dụng cached execution plan.

**3. Thủ tục xử lý**
```sql
SELECT ROUND((1-SUM(getmisses)/SUM(gets))*100,2) hit_pct FROM v$rowcache;
SELECT SUBSTR(sql_text,1,60) pattern, COUNT(*) cnt FROM v$sqlarea
WHERE executions=1 AND last_active_time>SYSDATE-1/24
GROUP BY SUBSTR(sql_text,1,60) HAVING COUNT(*)>10 ORDER BY cnt DESC;

-- Fix tạm thời (workaround, không thay code app)
ALTER SYSTEM SET cursor_sharing='FORCE' SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
`cursor_sharing=FORCE` là band-aid, không phải fix triệt để — đặc biệt nguy hiểm với DSS/reporting workload vì có thể làm sai cardinality estimate (do literal values quan trọng cho optimizer). Fix đúng là sửa application code dùng bind variables.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa "kiểm tra dùng bind variables" vào code review checklist cho mọi feature mới truy cập DB.
- Monitor định kỳ tỷ lệ hard parse, đặt threshold alert sớm trước khi thành vấn đề nghiêm trọng.

---

### Case 5: ORA-04031 trong giờ cao điểm, lặp lại định kỳ

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Database không cấp phát được memory cho cursor mới, một số session bị fail kết nối/query trong giờ cao điểm — ảnh hưởng trực tiếp doanh thu nếu là hệ thống giao dịch.

**2. Nguyên nhân**
Shared Pool fragmentation tích lũy theo thời gian (nhiều cursor nhỏ tạo/hủy liên tục), kết hợp với Shared Pool size không đủ buffer cho peak load.

**3. Thủ tục xử lý**
```sql
SELECT name, ROUND(bytes/1024/1024,2) mb FROM v$sgastat
WHERE pool='shared pool' ORDER BY bytes DESC FETCH FIRST 10 ROWS ONLY;

-- Khẩn cấp (chấp nhận performance hit tạm thời)
ALTER SYSTEM FLUSH SHARED_POOL;

-- Lâu dài
ALTER SYSTEM SET shared_pool_size=6G SCOPE=BOTH;
ALTER SYSTEM SET shared_pool_reserved_size=300M SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
ORA-04031 lặp lại theo PATTERN (cùng giờ trong ngày) là tín hiệu của vấn đề cấu trúc (sizing/fragmentation), không phải sự cố ngẫu nhiên — cần phân tích theo time-series thay vì xử lý từng lần riêng lẻ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Capacity planning định kỳ cho Shared Pool dựa trên xu hướng tăng trưởng số lượng cursor/session, không chỉ sizing tĩnh 1 lần.

---

### Case 6: AWR snapshot bị gap (thiếu data trong khoảng thời gian cần phân tích)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Không thể điều tra root cause của sự cố đã xảy ra vì thiếu historical data, ảnh hưởng khả năng RCA (Root Cause Analysis) đầy đủ.

**2. Nguyên nhân**
AWR snapshot job (`auto optimizer stats collection` liên quan job) bị disable hoặc fail âm thầm, hoặc retention policy quá ngắn khiến data cũ bị purge trước khi điều tra.

**3. Thủ tục xử lý**
```sql
SELECT snap_id, begin_interval_time FROM dba_hist_snapshot
WHERE begin_interval_time > SYSDATE-7 ORDER BY snap_id;
-- Nếu thấy gap trong sequence -> snapshot job có vấn đề

SELECT * FROM dba_hist_wr_control;  -- Xem retention/interval hiện tại
EXEC DBMS_WORKLOAD_REPOSITORY.MODIFY_SNAPSHOT_SETTINGS(
  retention=>43200, interval=>30);  -- 30 ngày, mỗi 30 phút
```

**4. Bài học kinh nghiệm**
AWR retention quá ngắn (mặc định 8 ngày) thường KHÔNG ĐỦ để điều tra sự cố mà business chỉ báo cáo sau vài ngày — nên tăng retention lên ít nhất 30-90 ngày cho hệ thống quan trọng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Set AWR retention tối thiểu 30 ngày ngay từ go-live cho production systems, đưa vào standard configuration checklist.

---

### Case 7: Average Active Sessions (AAS) cao bất thường nhưng CPU không cao

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Database "bận" theo metrics nhưng không phải do CPU-bound, dễ gây nhầm lẫn khi troubleshoot (team tập trung sai hướng vào CPU thay vì wait events).

**2. Nguyên nhân**
Sessions đang ACTIVE nhưng chờ đợi (I/O wait, lock wait, network wait) thay vì thực sự dùng CPU — đây là phân biệt quan trọng giữa "ON CPU" và "WAITING" trong ASH.

**3. Thủ tục xử lý**
```sql
SELECT session_state, COUNT(*) FROM v$active_session_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '10' MINUTE
GROUP BY session_state;
-- Nếu phần lớn là WAITING, tìm event cụ thể
SELECT event, COUNT(*) FROM v$active_session_history
WHERE sample_time > SYSTIMESTAMP - INTERVAL '10' MINUTE
  AND session_state='WAITING' GROUP BY event ORDER BY COUNT(*) DESC;
```

**4. Bài học kinh nghiệm**
AAS cao không tự động nghĩa là "cần thêm CPU" — luôn phân tách ON CPU vs WAITING trước khi đề xuất giải pháp, tránh lãng phí đầu tư hạ tầng sai hướng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Dashboard giám sát nên hiển thị riêng biệt AAS breakdown (ON CPU / User I/O / Concurrency / Other) thay vì chỉ 1 con số tổng, giúp team nhận diện đúng vấn đề ngay từ cái nhìn đầu tiên.

---

### Case 8: Memory leak nghi ngờ — PGA/SGA tăng dần không giảm

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Memory usage tăng dần theo thời gian uptime, có nguy cơ OOM (Out Of Memory) nếu không can thiệp, đặc biệt nguy hiểm trên hệ thống chạy liên tục nhiều tháng không restart.

**2. Nguyên nhân**
Thường KHÔNG phải Oracle bug (rất hiếm) mà do: connection pool application không đóng session đúng cách (session leak tích lũy), hoặc PL/SQL global variables trong package giữ data lớn qua nhiều calls.

**3. Thủ tục xử lý**
```sql
SELECT COUNT(*), program FROM v$session GROUP BY program ORDER BY COUNT(*) DESC;
-- Tìm session count tăng bất thường theo connection pool cụ thể

SELECT username, COUNT(*), MIN(logon_time) oldest_session
FROM v$session WHERE type='USER' GROUP BY username ORDER BY COUNT(*) DESC;
```

**4. Bài học kinh nghiệm**
"Memory leak" trong Oracle hầu hết là session/connection leak từ application layer, không phải lỗi DB engine — cần hợp tác với application team để trace connection pool behavior thay vì chỉ tập trung vào DB-side.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Thiết lập `IDLE_TIME` trong profile để tự động kill session bị treo quá lâu, kết hợp monitoring session count theo program/module để phát hiện sớm xu hướng leak.

---

### Case 9: Redo Generation Rate tăng đột biến không rõ nguyên nhân

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Log switch quá thường xuyên, archiver phải làm việc nhiều hơn, có thể dẫn tới ORA-00257 nếu archive đích không theo kịp (xem SK10-01 Case 3).

**2. Nguyên nhân**
Một batch job mới deploy với khối lượng DML lớn hơn dự kiến, hoặc thiếu `NOLOGGING` cho bulk load operations đáng lẽ nên dùng.

**3. Thủ tục xử lý**
```sql
SELECT TO_CHAR(begin_interval_time,'YYYY-MM-DD HH24') hour,
       ROUND(SUM(value)/1024/1024,0) redo_mb
FROM dba_hist_sysstat s JOIN dba_hist_snapshot sn ON s.snap_id=sn.snap_id
WHERE stat_name='redo size' AND begin_interval_time>SYSDATE-2
GROUP BY TO_CHAR(begin_interval_time,'YYYY-MM-DD HH24') ORDER BY 1 DESC;

-- Tìm SQL nào sinh redo nhiều nhất
SELECT sql_id, SUM(value) FROM v$sql... -- correlate với top SQL
```

**4. Bài học kinh nghiệm**
Mọi deployment mới có DML khối lượng lớn cần đánh giá tác động tới redo generation TRƯỚC khi go-live, không phải phát hiện sau khi archive log đầy.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Capacity test cho mọi batch job mới trên staging với volume tương đương production, đo redo generation rate trước khi go-live; cân nhắc dùng `NOLOGGING` cho bulk operations có thể tái tạo lại data nếu cần (kèm backup ngay sau).

---

### Case 10: ASH sampling không đủ để bắt được spike ngắn (< 10 giây)

**1. Vấn đề / Mức độ ảnh hưởng**
🟢 Một số sự cố ngắn (vài giây) không được capture đầy đủ trong ASH do sampling interval mặc định (1 giây) vẫn có thể miss spike cực ngắn.

**2. Nguyên nhân**
ASH sample mỗi 1 giây — các sự cố diễn ra và kết thúc trong < 1 giây có xác suất không bị sample trúng.

**3. Thủ tục xử lý**
```sql
-- Dùng v$session_wait (real-time) thay vì ASH cho phân tích cực ngắn
-- Hoặc dùng SQL Trace (10046) nếu cần độ chi tiết cao cho 1 session cụ thể
ALTER SESSION SET EVENTS '10046 trace name context forever, level 12';
```

**4. Bài học kinh nghiệm**
ASH là công cụ tuyệt vời cho phân tích trend/pattern nhưng có giới hạn về granularity — với sự cố cực ngắn cần công cụ khác (SQL Trace, real-time v$ views).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với hệ thống có yêu cầu latency cực thấp (sub-second), cân nhắc thiết lập continuous SQL tracing có chọn lọc cho các module quan trọng nhất thay vì chỉ dựa vào ASH.

---

## NHÓM B: EXECUTION PLAN & INDEX (Case 11-25)

### Case 11: Execution Plan đột nhiên thay đổi, query chậm hẳn

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Một query trước đây chạy nhanh (mili giây) đột nhiên chậm hẳn (vài giây tới phút), thường phát hiện qua user complaint vì không có error message rõ ràng.

**2. Nguyên nhân**
Phổ biến nhất: statistics vừa được gather lại (qua maintenance window tự động) làm thay đổi cost-based decision của optimizer, chọn plan tệ hơn dù về lý thuyết "mới hơn".

**3. Thủ tục xử lý**
```sql
-- So sánh plan hiện tại với lịch sử
SELECT DISTINCT sql_id, plan_hash_value,
       TO_CHAR(MIN(timestamp),'YYYY-MM-DD HH24:MI') first_seen
FROM dba_hist_sql_plan WHERE sql_id='&sql_id'
GROUP BY sql_id, plan_hash_value ORDER BY first_seen;

-- Fix nhanh: Force plan tốt qua SQL Plan Baseline
DECLARE l_plans INTEGER;
BEGIN
  l_plans := DBMS_SPM.LOAD_PLANS_FROM_AWR(
    sql_id=>'&sql_id', plan_hash_value=>&good_plan_hash, fixed=>'YES');
END;
/
```

**4. Bài học kinh nghiệm**
"Statistics mới hơn = plan tốt hơn" KHÔNG LUÔN ĐÚNG — đặc biệt với data có distribution skew mà histogram chưa đủ chi tiết. SQL Plan Baseline là công cụ "an toàn" giúp ổn định plan mà không cần lock toàn bộ statistics.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Capture SQL Plan Baseline cho các query critical NGAY KHI chúng đang chạy tốt, không đợi đến khi có vấn đề.
- Với bảng có data distribution không đều, cân nhắc histogram strategy phù hợp (HYBRID/FREQUENCY) thay vì để Oracle tự quyết định AUTO.

---

### Case 12: Full Table Scan bất ngờ trên bảng có index sẵn

**1. Vấn đề / Mức độ ảnh hưởng**
🟡-🔴 Query chậm đáng kể do đọc toàn bộ bảng thay vì dùng index, mức độ nghiêm trọng tỷ lệ thuận với kích thước bảng.

**2. Nguyên nhân**
Thường do: (a) function áp lên indexed column trong WHERE clause (vô hiệu hóa index trừ khi có Function-Based Index tương ứng), (b) implicit datatype conversion, (c) statistics lỗi thời khiến optimizer tin rằng FTS rẻ hơn.

**3. Thủ tục xử lý**
```sql
-- Tìm function trên indexed column (nguyên nhân phổ biến nhất)
EXPLAIN PLAN FOR <query>;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,NULL,'TYPICAL PREDICATE'));
-- Xem "Predicate Information" - nếu thấy TRUNC(), UPPER(), TO_CHAR() trên indexed column

-- Fix: viết lại query tránh function, hoặc tạo FBI
CREATE INDEX idx_orders_trunc_date ON orders(TRUNC(order_date));
```

**4. Bài học kinh nghiệm**
Developer thường vô tình "vô hiệu hóa" index bằng cách áp dụng function trong WHERE clause mà không nhận ra — đây là code smell cần đào tạo cho dev team nhận diện ngay từ lúc viết code.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đưa "kiểm tra function trên indexed columns trong WHERE clause" vào SQL code review checklist; cung cấp training về cách viết SQL tận dụng index hiệu quả cho development team.

---

### Case 13: Cardinality Estimate sai lệch nghiêm trọng (Estimated vs Actual)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Optimizer chọn join method/access path không tối ưu do ước tính số rows sai lệch lớn (ví dụ ước tính 10 rows nhưng thực tế 1 triệu rows).

**2. Nguyên nhân**
Statistics lỗi thời, thiếu histogram cho column có data skew, hoặc multiple predicates trên các cột tương quan (correlated columns) mà Oracle không biết tự động (trừ khi có Extended Statistics).

**3. Thủ tục xử lý**
```sql
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(
  sql_id=>'&sql_id', format=>'ALLSTATS LAST'));
-- So sánh cột E-Rows (estimate) vs A-Rows (actual)

-- Fix: tạo Extended Statistics cho correlated columns
EXEC DBMS_STATS.GATHER_TABLE_STATS('SCOTT','ORDERS',
  method_opt=>'FOR ALL COLUMNS SIZE AUTO FOR COLUMNS (region, city) SIZE AUTO');
```

**4. Bài học kinh nghiệm**
Khi 2 cột có mối tương quan logic (VD: city luôn implies region), Oracle mặc định coi chúng độc lập trừ khi được dạy qua Extended Statistics/Column Groups — đây là nguồn lỗi cardinality phổ biến nhưng ít người biết.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với bảng có nhiều predicate filter cùng lúc trên các cột liên quan logic, chủ động tạo Extended Statistics ngay từ giai đoạn thiết kế schema, không đợi tới khi phát hiện performance issue.

---

### Case 14: Index Unusable sau Partition Maintenance

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Sau thao tác DROP/TRUNCATE/SPLIT partition, các global index liên quan trở thành UNUSABLE, queries dùng index đó bắt đầu fail hoặc full scan.

**2. Nguyên nhân**
Global Index (không phải Local) bị invalidate tự động khi cấu trúc partition thay đổi — đây là behavior by design, không phải bug.

**3. Thủ tục xử lý**
```sql
SELECT index_name, status FROM dba_indexes WHERE table_name='SALES_DATA';
ALTER INDEX idx_global_sales REBUILD ONLINE;

-- Hoặc dùng UPDATE INDEXES trong DDL để tránh vấn đề này từ đầu
ALTER TABLE sales_data DROP PARTITION p_2024 UPDATE INDEXES;
```

**4. Bài học kinh nghiệm**
Với bảng partition lớn cần thao tác maintenance thường xuyên (DROP partition cũ định kỳ), nên ưu tiên dùng Local Indexes thay vì Global Indexes nếu business logic cho phép, để tránh phải rebuild định kỳ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Mọi script partition maintenance định kỳ (archive/purge data cũ) PHẢI bao gồm `UPDATE INDEXES` clause hoặc bước rebuild index riêng biệt ngay sau, đưa vào automation script chuẩn.

---

### Case 15: SQL Tuning Advisor đề xuất SQL Profile nhưng không cải thiện

**1. Vấn đề / Mức độ ảnh hưởng**
🟢 Đã accept SQL Profile theo đề xuất nhưng performance không cải thiện như mong đợi — gây mất niềm tin vào tool, lãng phí effort.

**2. Nguyên nhân**
SQL Profile chỉ điều chỉnh optimizer estimates (qua hints/adjustments), không thể khắc phục vấn đề về thiếu index hoặc data model — Advisor chỉ tối ưu trong giới hạn cấu trúc hiện có.

**3. Thủ tục xử lý**
```sql
-- Xem chi tiết recommendation đầy đủ, không chỉ accept profile mù quáng
SELECT DBMS_SQLTUNE.REPORT_TUNING_TASK('TASK_NAME') FROM dual;
-- Tìm phần "FINDINGS" - có thể đề xuất CẢ index lẫn profile
```

**4. Bài học kinh nghiệm**
SQL Tuning Advisor thường đưa RA NHIỀU recommendations (profile, index, restructure SQL, stats) — chỉ accept SQL Profile mà bỏ qua các đề xuất khác (đặc biệt INDEX recommendation) thường không đạt hiệu quả tối đa.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Luôn đọc đầy đủ report của SQL Tuning Advisor (không chỉ phần SQL Profile), đánh giá TẤT CẢ recommendations và áp dụng theo độ ưu tiên benefit/risk trước khi kết luận "advisor không hiệu quả".

---

### Case 16: Index Skip Scan dùng thay vì Range Scan, performance không như mong đợi

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Query dùng composite index nhưng hiệu năng không tốt như kỳ vọng vì optimizer chọn Skip Scan (kém hiệu quả hơn Range Scan).

**2. Nguyên nhân**
Query không filter trên leading column của composite index, buộc Oracle phải "skip" qua các giá trị distinct của leading column — hiệu quả phụ thuộc vào cardinality của leading column (càng ít distinct values càng "đỡ tệ").

**3. Thủ tục xử lý**
```sql
-- Xác nhận đang dùng Skip Scan
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY_CURSOR(format=>'TYPICAL'));
-- Tìm "INDEX SKIP SCAN" trong Operation

-- Fix: tạo index riêng với leading column đúng theo pattern WHERE thực tế
CREATE INDEX idx_orders_status_only ON orders(status);
```

**4. Bài học kinh nghiệm**
Composite index column order PHẢI khớp với pattern WHERE clause thực tế của application — thiết kế index "đoán trước" mà không dựa trên actual query pattern dễ dẫn tới Skip Scan kém hiệu quả.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Thiết kế index dựa trên phân tích actual SQL workload (từ AWR Top SQL) thay vì đoán trước, review định kỳ index usage qua `v$index_usage_info` để điều chỉnh.

---

### Case 17: Adaptive Plan gây instability, performance không ổn định giữa các lần chạy

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Cùng 1 query có lúc chạy nhanh, có lúc chậm — gây khó khăn trong capacity planning và SLA commitment.

**2. Nguyên nhân**
Adaptive Plan Optimization (12c+) re-evaluate plan giữa chừng execution dựa trên actual rows, có thể dẫn tới các lần chạy khác nhau chọn nhánh thực thi khác nhau tùy data distribution thời điểm đó.

**3. Thủ tục xử lý**
```sql
SELECT is_resolved_adaptive_plan FROM v$sql WHERE sql_id='&sql_id';

-- Nếu gây instability không mong muốn, tắt cho session/system
ALTER SESSION SET optimizer_adaptive_plans=FALSE;
```

**4. Bài học kinh nghiệm**
Adaptive features là con dao 2 lưỡi — tốt cho workload có data distribution thay đổi nhiều, nhưng có thể gây "khó đoán" cho hệ thống cần performance nhất quán cao (như real-time trading systems).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với hệ thống yêu cầu SLA nghiêm ngặt về response time consistency, cân nhắc tắt Adaptive Plans và dùng SQL Plan Baseline để đảm bảo plan ổn định, dự đoán được.

---

### Case 18: Bitmap Index gây deadlock trong OLTP workload

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Deadlock xảy ra thường xuyên trên bảng có Bitmap Index khi nhiều session UPDATE/INSERT đồng thời — gây transaction fail liên tục.

**2. Nguyên nhân**
Bitmap Index có lock granularity ở mức rất thô (1 bitmap segment có thể cover hàng nghìn rows), khiến UPDATE 2 rows khác nhau nhưng cùng segment vẫn gây contention — Bitmap Index về bản chất KHÔNG phù hợp OLTP.

**3. Thủ tục xử lý**
```sql
SELECT index_name, index_type FROM dba_indexes
WHERE table_name='ORDERS' AND index_type='BITMAP';

-- Fix: chuyển sang B-tree nếu bảng có DML tần suất cao
DROP INDEX idx_orders_status_bmp;
CREATE INDEX idx_orders_status ON orders(status);
```

**4. Bài học kinh nghiệm**
Bitmap Index CHỈ phù hợp cho DWH/reporting (read-heavy, low DML), tuyệt đối tránh dùng cho bảng OLTP có DML tần suất cao dù cardinality của cột thấp — đây là sai lầm thiết kế phổ biến của người mới làm Oracle.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đưa "Bitmap Index chỉ cho DWH" vào coding standard/design review checklist; với OLTP bảng có cột low-cardinality cần index, ưu tiên B-tree thông thường dù "lý thuyết" Bitmap hiệu quả hơn cho low cardinality.

---

### Case 19: Histogram gây regression cho bind variable peeking

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Query với bind variable có performance khác nhau tùy giá trị bind đầu tiên được dùng để parse (Bind Peeking), gây inconsistency khó debug.

**2. Nguyên nhân**
Khi cột có Histogram (do data skew) VÀ query dùng bind variable, Oracle "peek" giá trị bind đầu tiên để quyết định plan, plan này được cache và dùng cho TẤT CẢ executions sau dù giá trị bind khác đi.

**3. Thủ tục xử lý**
```sql
-- Xác nhận có Adaptive Cursor Sharing đang hoạt động không
SELECT is_bind_sensitive, is_bind_aware FROM v$sql WHERE sql_id='&sql_id';

-- Nếu chưa, có thể cần force qua việc xóa cursor cache để parse lại
EXEC DBMS_SHARED_POOL.PURGE('&address,&hash_value','C');
```

**4. Bài học kinh nghiệm**
Adaptive Cursor Sharing (11g+) giúp giảm vấn đề này nhưng không hoàn toàn loại bỏ — với cột có skew nghiêm trọng kết hợp bind variable, cần test kỹ với nhiều giá trị bind khác nhau trước khi go-live.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với query quan trọng trên cột có data skew cao, cân nhắc dùng literal values thay vì bind variables (chấp nhận tăng hard parse) nếu plan stability quan trọng hơn parse overhead, hoặc dùng SQL Plan Baseline với multiple plans.

---

### Case 20: Index Rebuild Online gây block tạm thời ngoài dự kiến

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Mặc dù dùng `REBUILD ONLINE`, vẫn có khoảng thời gian ngắn lock exclusive ở bước cuối cùng (DDL lock), gây gián đoạn ngắn cho ứng dụng cao tải.

**2. Nguyên nhân**
`REBUILD ONLINE` không hoàn toàn "zero lock" — vẫn cần một short exclusive lock ở giai đoạn cuối để swap structure, có thể bị kéo dài nếu có long-running transaction đang block.

**3. Thủ tục xử lý**
```sql
-- Set timeout để tránh treo vô hạn chờ lock
ALTER SESSION SET ddl_lock_timeout=30;
ALTER INDEX idx_orders_date REBUILD ONLINE;

-- Nếu vẫn bị block, tìm và xử lý session đang giữ lock dài
SELECT blocking_session FROM v$session WHERE sid=(SELECT sid FROM v$session WHERE...);
```

**4. Bài học kinh nghiệm**
"ONLINE" không có nghĩa là "hoàn toàn zero-impact" — cần schedule rebuild lớn vào maintenance window thấp tải, đồng thời set `ddl_lock_timeout` để tránh treo vô thời hạn nếu có blocker.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Luôn dùng `ddl_lock_timeout` cho mọi DDL online trên production, schedule maintenance window rõ ràng cho các thao tác structural changes dù về lý thuyết "online".

---

### Case 21-25: Tổng hợp các vấn đề Index/Plan khác (rút gọn)

**Case 21 — Invisible Index test không phản ánh đúng production behavior:**
Vấn đề: Test invisible index trên session riêng cho kết quả khả quan nhưng khi visible production lại không cải thiện. Nguyên nhân: bind variable values khác nhau giữa test và production traffic thực tế ảnh hưởng cardinality decision. Xử lý: test với representative sample của actual production bind values, không chỉ test với vài giá trị cố định. Bài học: Invisible Index testing cần đại diện đủ cho production traffic pattern. Phòng ngừa: dùng SQL Performance Analyzer (SPA) với captured SQL Tuning Set từ production thay vì test thủ công.

**Case 22 — Function-Based Index không được dùng dù query khớp pattern:**
Vấn đề: Tạo FBI đúng cú pháp nhưng optimizer vẫn không chọn dùng. Nguyên nhân: thiếu `query_rewrite_enabled=TRUE` hoặc chưa gather statistics cho FBI sau khi tạo. Xử lý: `EXEC DBMS_STATS.GATHER_TABLE_STATS(...)` ngay sau CREATE INDEX. Bài học: FBI cần statistics riêng, không tự động có ngay khi tạo. Phòng ngừa: luôn gather stats ngay sau DDL tạo index mới, đưa vào script chuẩn.

**Case 23 — Partition-wise Join không hoạt động dù cả 2 bảng đã partition:**
Vấn đề: JOIN giữa 2 bảng partition cùng key nhưng plan không show "PARTITION JOIN". Nguyên nhân: partition strategy khác nhau (số lượng partition hoặc partition key transformation không khớp). Xử lý: đảm bảo cùng partition count và cùng partition key type giữa 2 bảng. Bài học: Partition-wise Join yêu cầu "equi-partitioned" tables thực sự khớp nhau. Phòng ngừa: thiết kế partition strategy đồng bộ ngay từ đầu cho các bảng thường JOIN với nhau.

**Case 24 — Reverse Key Index làm mất khả năng Range Scan:**
Vấn đề: Sau khi tạo Reverse Key Index để giảm hot block (RAC), các query dùng range condition (BETWEEN) trở nên chậm hẳn. Nguyên nhân: Reverse Key Index về bản chất phá vỡ thứ tự logic của key, khiến Range Scan không thể dùng được (chỉ Unique/Equality Scan hiệu quả). Xử lý: đánh giá lại trade-off, có thể cần Hash Partitioning thay vì Reverse Key nếu cần cả range query lẫn giảm hot block. Bài học: Reverse Key Index chỉ phù hợp khi 100% truy vấn là equality, không có range query. Phòng ngừa: phân tích kỹ access pattern trước khi áp dụng Reverse Key, ưu tiên Hash Partitioning cho trường hợp cần cả 2.

**Case 25 — SQL Baseline conflict khi nhiều plans cùng accepted:**
Vấn đề: SQL Plan Baseline có nhiều plan accepted, Oracle chọn plan không tối ưu nhất trong số đó. Nguyên nhân: Evolve Baseline tự động accept các plan "tốt hơn cũ" nhưng không nhất thiết là "tốt nhất có thể". Xử lý: review tất cả accepted plans, fix plan tốt nhất tường minh. Bài học: Baseline Evolution cần giám sát định kỳ, không phải "set and forget". Phòng ngừa: review SQL Plan Baselines hàng quý, loại bỏ plan cũ không còn dùng.

---

## NHÓM C: PARTITIONING & WAIT EVENTS (Case 26-33)

### Case 26: Partition Pruning không hoạt động dù WHERE có partition key

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Query scan TẤT CẢ partitions thay vì chỉ partition liên quan, performance giảm tỷ lệ thuận với số lượng partition của bảng (có thể chậm hàng chục/trăm lần với bảng nhiều partition).

**2. Nguyên nhân**
Phổ biến nhất: datatype mismatch giữa bind variable và partition key (implicit conversion vô hiệu hóa pruning), hoặc dùng function lên partition key trong WHERE clause.

**3. Thủ tục xử lý**
```sql
EXPLAIN PLAN FOR SELECT * FROM sales_data WHERE sale_date='2026-01-15';
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,NULL,'PARTITION'));
-- Tìm Pstart/Pstop - nếu là "1 / KEY(num_partitions)" nghĩa là KHÔNG pruning

-- Fix: đảm bảo datatype khớp chính xác
SELECT * FROM sales_data WHERE sale_date = DATE '2026-01-15';  -- Không phải string
```

**4. Bài học kinh nghiệm**
Đây là vấn đề CỰC KỲ phổ biến và dễ bị bỏ qua — application thường gửi date dưới dạng string, Oracle implicit convert nhưng MẤT KHẢ NĂNG PRUNING trong quá trình đó. Luôn verify Pstart/Pstop trong plan, không chỉ tin tưởng partition key có trong WHERE là đủ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đưa "verify partition pruning qua DBMS_XPLAN" vào quy trình test bắt buộc cho mọi query mới trên bảng partition lớn, trước khi go-live production.

---

### Case 27: "db file sequential read" wait cao bất thường

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 I/O latency cao cho single-block reads (thường liên quan Index Range Scan), ảnh hưởng OLTP response time.

**2. Nguyên nhân**
Storage subsystem chậm (disk/SAN latency cao), hoặc index có Clustering Factor cao (data không sắp xếp gần với index order, gây nhiều random I/O).

**3. Thủ tục xử lý**
```sql
SELECT index_name, clustering_factor, num_rows FROM dba_indexes
WHERE table_name='ORDERS' ORDER BY clustering_factor DESC;
-- CF gần num_rows = data scattered, nhiều I/O

-- Storage-level check
SELECT name, ROUND(readtim/NULLIF(phyrds,0),2) avg_read_ms
FROM v$filestat fs JOIN v$datafile df ON fs.file#=df.file#
ORDER BY avg_read_ms DESC;
```

**4. Bài học kinh nghiệm**
Cần phân biệt root cause là storage layer (cần escalate hạ tầng/storage team) hay là data organization issue (table cần reorganize theo index order) — 2 hướng xử lý hoàn toàn khác nhau.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với bảng insert theo pattern không tuần tự (VD: random UUID primary key), cân nhắc thiết kế lại để có locality tốt hơn (sequence-based key hoặc partition theo insert order) nếu Clustering Factor là vấn đề thường xuyên.

---

### Case 28: "log file sync" wait cao, commit chậm

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Mọi transaction COMMIT đều chậm, ảnh hưởng trực tiếp throughput của toàn hệ thống OLTP.

**2. Nguyên nhân**
Redo log đặt trên storage chậm (HDD thay vì SSD/NVMe), hoặc quá nhiều commit nhỏ lẻ tẻ (application thiếu batching).

**3. Thủ tục xử lý**
```sql
SELECT event, total_waits, ROUND(time_waited_micro/1e6,2) sec
FROM v$system_event WHERE event='log file sync';

-- Kiểm tra LGWR write time
SELECT name FROM v$bgprocess WHERE name='LGWR';
```

**4. Bài học kinh nghiệm**
Redo log PHẢI nằm trên storage nhanh nhất có thể (SSD/NVMe dedicated) — đây là một trong những quyết định kiến trúc storage quan trọng nhất ảnh hưởng trực tiếp tới OLTP throughput.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Ngay từ giai đoạn thiết kế hạ tầng, dành riêng disk nhanh nhất cho Redo Logs (tách biệt hoàn toàn khỏi Datafiles), kết hợp giáo dục application team về batching commits hợp lý thay vì commit sau mỗi statement đơn lẻ.

---

### Case 29-33: Tổng hợp Wait Events khác (rút gọn)

**Case 29 — "enq: TX - row lock contention" kéo dài:**
Vấn đề: Nhiều session bị block chờ row lock từ 1 transaction dài. Nguyên nhân: application giữ transaction mở quá lâu (thường do logic nghiệp vụ phức tạp hoặc thiếu commit hợp lý). Xử lý: tìm và xử lý blocking session, đồng thời review application logic. Bài học: Long-running transaction là anti-pattern OLTP. Phòng ngừa: thiết lập alert tự động cho transaction chạy > N phút chưa commit/rollback.

**Case 30 — "buffer busy waits" trên bảng có sequence-based PK:**
Vấn đề: Hot block contention khi nhiều session insert đồng thời vào cùng block (do PK tăng tuần tự). Nguyên nhân: tất cả inserts tập trung vào "right-most" block của index. Xử lý: tăng sequence CACHE, cân nhắc Reverse Key Index hoặc Hash Partitioning. Bài học: Sequence tuần tự + high concurrency insert = hot block by design. Phòng ngừa: đánh giá insert concurrency pattern khi thiết kế PK strategy cho bảng OLTP cao tải.

**Case 31 — "latch: cache buffers chains" cao:**
Vấn đề: Latch contention khi nhiều session cùng truy cập 1 block phổ biến (hot block đọc). Nguyên nhân: thiếu index khiến nhiều session FTS cùng 1 bảng nhỏ liên tục. Xử lý: thêm index phù hợp giảm số lần truy cập trực tiếp vào block đó. Bài học: Latch contention thường là triệu chứng của thiếu index, không phải vấn đề latch tự thân. Phòng ngừa: index coverage review định kỳ cho các bảng lookup/reference được truy cập tần suất cao.

**Case 32 — "SQL*Net message from client" cao bất thường (không phải DB issue):**
Vấn đề: Wait time cao nhưng đây là Idle wait, dễ gây hiểu nhầm là DB chậm. Nguyên nhân: Application xử lý logic phía client lâu trước khi gửi câu lệnh tiếp theo, hoặc network latency cao giữa app và DB. Xử lý: không cần action ở DB-side, cần investigate application/network. Bài học: Không phải mọi wait event đều là DB-side issue. Phòng ngừa: training team phân biệt rõ Idle waits vs DB waits trước khi escalate sai hướng.

**Case 33 — "direct path read" cao cho Parallel Query không như mong đợi:**
Vấn đề: Parallel Query vẫn chậm dù đã dùng PARALLEL hint, direct path reads (bypass buffer cache) chiếm phần lớn thời gian. Nguyên nhân: Storage I/O throughput không đủ đáp ứng nhiều PX slaves đọc đồng thời. Xử lý: kiểm tra storage IOPS/throughput limit, có thể cần giảm DOP nếu storage là bottleneck. Bài học: Tăng Parallel DOP không giúp ích nếu storage đã saturated. Phòng ngừa: capacity test storage I/O throughput trước khi thiết kế DOP cho parallel workload lớn.

---

## NHÓM D: PARALLEL EXECUTION & IN-MEMORY (Case 34-40)

### Case 34: Parallel Query bị downgrade DOP không như cấu hình

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Query chạy với Degree of Parallelism thấp hơn yêu cầu, performance không đạt như kỳ vọng dù đã config DOP cao.

**2. Nguyên nhân**
Không đủ Parallel Execution Servers available tại thời điểm chạy (do `parallel_max_servers` đã bị các session khác chiếm dụng hết), Oracle tự động downgrade thay vì fail.

**3. Thủ tục xử lý**
```sql
SELECT qcsid, server_set, degree, req_degree FROM v$px_session
WHERE req_degree != degree;
-- degree < req_degree = bị downgrade

SHOW PARAMETER parallel_max_servers;
ALTER SYSTEM SET parallel_max_servers=128 SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
DOP downgrade diễn ra ÂM THẦM (không có error/warning rõ ràng) — cần chủ động kiểm tra `v$px_session` định kỳ thay vì chỉ tin tưởng cấu hình DOP đã set là sẽ luôn được đáp ứng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Capacity planning cho `parallel_max_servers` dựa trên concurrent parallel workload thực tế (không chỉ 1 query lớn nhất), monitor PX downgrade rate như 1 KPI riêng biệt.

---

### Case 35: PARALLEL DML không hoạt động dù có hint

**1. Vấn đề / Mức độ ảnh hưởng**
🟢 INSERT/UPDATE/DELETE chạy serial dù có PARALLEL hint, không đạt tốc độ kỳ vọng cho bulk operations lớn.

**2. Nguyên nhân**
Thiếu `ALTER SESSION ENABLE PARALLEL DML` — đây là yêu cầu BẮT BUỘC riêng biệt với hint, khác với Parallel Query (SELECT) chỉ cần hint là đủ.

**3. Thủ tục xử lý**
```sql
ALTER SESSION ENABLE PARALLEL DML;
INSERT /*+ PARALLEL(t,4) */ INTO target_table
SELECT /*+ PARALLEL(s,4) */ * FROM source_table;
COMMIT;
```

**4. Bài học kinh nghiệm**
Đây là điểm khác biệt dễ gây nhầm lẫn giữa Parallel Query và Parallel DML — nhiều developer chỉ nhớ thêm hint mà quên session-level enable, dẫn tới "tưởng đang chạy parallel nhưng thực ra serial".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Tạo template/snippet chuẩn cho Parallel DML bao gồm cả `ENABLE PARALLEL DML` để dev team copy-paste đúng pattern, tránh quên bước quan trọng này.

---

### Case 36: In-Memory Column Store không populate dù đã ALTER TABLE INMEMORY

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Query vẫn dùng traditional row-store scan thay vì tận dụng In-Memory, không đạt được tốc độ tăng tốc kỳ vọng từ tính năng IM.

**2. Nguyên nhân**
Populate là quá trình BACKGROUND, không xảy ra ngay lập tức sau ALTER TABLE; hoặc `inmemory_size` không đủ để chứa hết data được đánh dấu INMEMORY.

**3. Thủ tục xử lý**
```sql
SELECT segment_name, populate_status, ROUND(inmemory_size/1024/1024,0) mb
FROM v$im_segments WHERE segment_name='SALES_DATA';
-- Nếu STARTED/NOT STARTED, cần đợi hoặc force

EXEC DBMS_INMEMORY.POPULATE('SCHEMA','SALES_DATA');

-- Nếu OUT OF MEMORY, tăng inmemory_size hoặc giảm scope (column-level thay vì cả bảng)
```

**4. Bài học kinh nghiệm**
In-Memory population KHÔNG tức thì — cần thời gian (tỷ lệ với data size) và đủ memory allocation; việc đặt ALTER TABLE INMEMORY rồi test ngay lập tức là sai lầm phổ biến của người mới dùng tính năng này.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Sizing `inmemory_size` dựa trên tổng data thực sự cần đưa vào memory (không phải toàn bộ database), monitor `v$im_segments` để xác nhận population hoàn tất trước khi đánh giá hiệu quả tính năng.

---

### Case 37-40: Tổng hợp Parallel/In-Memory khác (rút gọn)

**Case 37 — In-Memory Expression không tự động identify đúng:**
Vấn đề: IM Expressions feature không tối ưu các SQL expression thường dùng như kỳ vọng. Nguyên nhân: cần đủ lịch sử query workload để Oracle "học" pattern, hoặc query chưa chạy đủ số lần để được candidate. Xử lý: chạy `IDENTIFY OBJECTS` lại sau khi đã có đủ workload history. Bài học: IM Expressions cần "warm-up period" với actual traffic. Phòng ngừa: không kỳ vọng tối ưu ngay sau go-live, đánh giá lại sau 1-2 tuần production traffic.

**Case 38 — Parallel Query gây resource contention với OLTP đồng thời:**
Vấn đề: Một báo cáo lớn chạy Parallel Query "cướp" hết CPU/PX servers, ảnh hưởng OLTP response time. Nguyên nhân: thiếu Resource Manager để giới hạn resource cho parallel batch jobs. Xử lý: implement Resource Manager Plan phân tách OLTP và Batch/Reporting consumer groups. Bài học: Parallel Execution mạnh mẽ nhưng cần kiểm soát để không "đè" workload khác. Phòng ngừa: luôn có Resource Manager Plan cho hệ thống mixed OLTP+Reporting, không để chạy tự do.

**Case 39 — In-Memory không hỗ trợ cho LOB columns:**
Vấn đề: Bảng có cột CLOB/BLOB lớn không được tăng tốc bởi In-Memory dù phần còn lại của bảng đã IM. Nguyên nhân: đây là limitation kỹ thuật của In-Memory Column Store (không hỗ trợ LOB). Xử lý: tách riêng LOB ra bảng phụ nếu cần tối ưu phần còn lại bằng IM. Bài học: In-Memory có giới hạn datatype support, cần biết trước khi thiết kế. Phòng ngừa: review IM datatype limitations trong tài liệu Oracle trước khi cam kết về hiệu năng cho stakeholder.

**Case 40 — Database Resource Manager Plan không switch theo Window đúng giờ:**
Vấn đề: Resource Plan dự kiến đổi theo giờ (DAY_PLAN/NIGHT_PLAN) không hoạt động đúng lịch. Nguyên nhân: Scheduler Window chưa được gán đúng resource_plan attribute, hoặc Window bị disable. Xử lý: `EXEC DBMS_SCHEDULER.SET_ATTRIBUTE('WINDOW_NAME','resource_plan','PLAN_NAME')`. Bài học: Resource Manager tích hợp chặt với Scheduler, lỗi cấu hình 1 phần ảnh hưởng cả hệ thống tự động hóa. Phòng ngừa: test đầy đủ chu kỳ 24h của Resource Plan switching trên staging trước khi áp dụng production.

---

## TỔNG KẾT — QUICK REFERENCE TABLE

```
40 Case Studies được chọn lọc theo tiêu chí:
  - Tần suất gặp phải cao trong vận hành thực tế
  - Đại diện đầy đủ cho 4 nhóm: AWR/Memory, Plan/Index, Partition/Wait, Parallel/IM

Top 5 Case NGHIÊM TRỌNG NHẤT (🔴 cần ưu tiên đọc trước):
  1. Case 1   — Database chậm đột ngột toàn diện (quy trình chẩn đoán chuẩn)
  2. Case 5   — ORA-04031 lặp lại định kỳ (Shared Pool sizing)
  3. Case 11  — Execution Plan thay đổi đột ngột (SQL Plan Baseline)
  4. Case 18  — Bitmap Index gây deadlock OLTP (thiết kế sai)
  5. Case 26  — Partition Pruning không hoạt động (datatype mismatch)
  6. Case 28  — "log file sync" cao (storage architecture cho Redo)
```

---

**Tài liệu tham khảo:**
- Oracle Database Performance Tuning Guide 19c
- Oracle Database VLDB and Partitioning Guide 19c
- Oracle Database In-Memory Guide 19c
- MOS Note 1448507.1 (Diagnosing Sudden Performance Degradation)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
