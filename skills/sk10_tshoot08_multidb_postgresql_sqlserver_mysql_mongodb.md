---
name: multidb-troubleshoot-postgresql-sqlserver-mysql-mongodb
description: >
  Case study khắc phục lỗi thường gặp trên các hệ quản trị cơ sở dữ liệu
  ngoài Oracle: PostgreSQL (streaming replication, VACUUM, connection pool),
  SQL Server (AlwaysOn AG, TempDB, suspect mode, blocking), MySQL/MariaDB
  (replication, InnoDB corruption, binlog), MongoDB (replica set, WiredTiger,
  sharding, oplog). Mỗi case trình bày đầy đủ: Vấn đề/Mức độ ảnh hưởng,
  Nguyên nhân, Thủ tục xử lý, Bài học kinh nghiệm, Biện pháp phòng ngừa
  từ sớm/từ xa.
  Kích hoạt khi hỏi về: lỗi PostgreSQL thực chiến, sự cố SQL Server,
  troubleshoot MySQL MariaDB, sự cố MongoDB, postmortem multi-database,
  too many connections, replication broken, database suspect mode,
  AlwaysOn not synchronizing, InnoDB corruption, replica set election,
  WiredTiger cache, sharding balancer stuck, transaction ID wraparound,
  bài học kinh nghiệm vận hành database ngoài Oracle.
---

# SK08-CASE · Case Study: Sự cố thường gặp trên Database khác (PostgreSQL, SQL Server, MySQL/MariaDB, MongoDB)

**Phạm vi:** PostgreSQL 14-16, SQL Server 2019-2022, MySQL 8.0/MariaDB 10.x, MongoDB 6.0-7.0
**Tác giả:** Trần Văn Bình — VietDBA (Hotline/Zalo: 0902 912 888 — www.tranvanbinh.vn)
**Số lượng case:** 20 case thực chiến, chia 4 nhóm

---

## KIẾN TRÚC TỔNG QUAN MULTI-DATABASE TROUBLESHOOTING

```
Multi-Database Engine — Failure Domain Map
══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────┐  |
│  POSTGRESQL LAYER (Connection / Replication / MVCC)           │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Connection │  │ Streaming  │  │ VACUUM /   │  Group A      │  |
│  │ Pool       │  │ Replication│  │ XID Wrap   │  (1-5)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  SQL SERVER LAYER (Integrity / AlwaysOn / Concurrency)        │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ DB Suspect │  │ AlwaysOn   │  │ TempDB /   │  Group B      │  |
│  │ / CHECKDB  │  │ AG Sync    │  │ Log / Block│  (6-10)       │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  MYSQL / MARIADB LAYER (Replication / Storage Engine)         │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Replication│  │ InnoDB     │  │ Connection │  Group C      │  |
│  │ (Slave)    │  │ Corruption │  │ / Binlog   │  (11-15)      │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  MONGODB LAYER (Replica Set / Sharding / Storage Engine)      │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Replica Set│  │ WiredTiger │  │ Sharding / │  Group D      │  |
│  │ Election   │  │ / Oplog    │  │ Connection │  (16-20)      │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────────────────────────────────────────────────────────┘  |

Severity: 🔴 CRITICAL (mất dữ liệu/ngừng dịch vụ) | 🟡 DEGRADED (suy giảm hiệu năng/rủi ro) | 🟢 MINOR (cảnh báo)
══════════════════════════════════════════════════════════════════
```

---

## MỤC LỤC CHI TIẾT THEO NHÓM

**NHÓM A: PostgreSQL — Connection / Replication / MVCC (Case 1-5)**
- Case 1: 🟡 "too many connections" — cạn kiệt connection pool
- Case 2: 🔴 Streaming Replication broken — replication slot bị stuck gây phình WAL
- Case 3: 🟡 Table/Index bloat nghiêm trọng do thiếu VACUUM định kỳ
- Case 4: 🔴 Transaction ID Wraparound — nguy cơ database tự shutdown
- Case 5: 🟡 Autovacuum không theo kịp do long-running transaction giữ lock

**NHÓM B: SQL Server — Integrity / AlwaysOn / Concurrency (Case 6-10)**
- Case 6: 🔴 Database ở trạng thái SUSPECT sau sự cố storage
- Case 7: 🟡 TempDB đầy / contention gây treo toàn hệ thống
- Case 8: 🔴 AlwaysOn Availability Group ngừng đồng bộ (NOT SYNCHRONIZING)
- Case 9: 🟡 Blocking chain kéo dài gây timeout hàng loạt ứng dụng
- Case 10: 🔴 Transaction Log đầy (Error 9002) do log không được backup

**NHÓM C: MySQL/MariaDB — Replication / Storage Engine (Case 11-15)**
- Case 11: 🔴 Replication (Slave) dừng do lỗi trùng khóa chính
- Case 12: 🔴 InnoDB corruption sau crash không sạch (unclean shutdown)
- Case 13: 🟡 "Too many connections" do connection leak từ ứng dụng
- Case 14: 🟡 Disk đầy do binlog tăng trưởng không kiểm soát
- Case 15: 🟡 Deadlock / Lock wait timeout tăng đột biến giờ cao điểm

**NHÓM D: MongoDB — Replica Set / Sharding / Storage Engine (Case 16-20)**
- Case 16: 🔴 Replica Set liên tục bầu lại Primary (election storm)
- Case 17: 🟡 WiredTiger cache pressure gây chậm toàn cluster
- Case 18: 🔴 Secondary rớt khỏi Oplog (oplog window quá ngắn)
- Case 19: 🟡 Sharding Balancer bị kẹt, chunk phân bố lệch nghiêm trọng
- Case 20: 🟡 Connection pool từ driver ứng dụng gây quá tải mongos/mongod

---

## NHÓM A: POSTGRESQL — CONNECTION / REPLICATION / MVCC (Case 1-5)

### Case 1: "too many connections" — cạn kiệt connection pool

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, có thể leo thang thành ngừng dịch vụ hoàn toàn. Ứng dụng nhận lỗi `FATAL: too many connections for role` hoặc `sorry, too many clients already`, các request mới không kết nối được vào database dù server vẫn hoạt động bình thường.

**2. Nguyên nhân**
Ứng dụng không dùng connection pooler (kết nối trực tiếp 1-1 giữa mỗi worker/thread và PostgreSQL), hoặc có connection leak (kết nối không được đóng đúng cách sau khi dùng xong), khiến số kết nối tích lũy vượt `max_connections` theo thời gian, đặc biệt rõ sau khi scale số lượng pod/worker ứng dụng mà không tính lại tổng connection cần thiết.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận số connection hiện tại và giới hạn cấu hình
psql -c "SHOW max_connections;"
psql -c "SELECT count(*) FROM pg_stat_activity;"

# Bước 2: Xác định nguồn gây leak (theo application_name, client_addr)
psql -c "SELECT application_name, client_addr, count(*) 
          FROM pg_stat_activity GROUP BY 1,2 ORDER BY 3 DESC;"

# Bước 3: Giải phóng khẩn cấp các connection idle lâu (idle in transaction là nguy hiểm nhất)
psql -c "SELECT pid, state, now()-state_change AS idle_time
          FROM pg_stat_activity WHERE state='idle in transaction'
          ORDER BY idle_time DESC;"
psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity
          WHERE state='idle in transaction' AND now()-state_change > interval '30 minutes';"

# Bước 4: Giải pháp lâu dài — triển khai PgBouncer (transaction pooling mode)
```

**4. Bài học kinh nghiệm**
PostgreSQL dùng mô hình process-per-connection (không như thread-based của một số RDBMS khác), nên mỗi connection tốn tài nguyên OS đáng kể — việc tăng `max_connections` một cách đơn giản để "chữa cháy" thường phản tác dụng vì gây quá tải CPU/RAM khi số connection thực sự active tăng theo.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc dùng connection pooler (PgBouncer/Pgpool-II) ở tầng giữa ứng dụng và PostgreSQL ngay từ khi thiết kế kiến trúc, không đợi đến khi gặp sự cố
- Giám sát liên tục tỷ lệ `pg_stat_activity` theo state (active/idle/idle in transaction), alert sớm khi "idle in transaction" tồn tại quá lâu — đây là dấu hiệu ứng dụng có bug quản lý transaction
- Capacity planning connection: `max_connections` phải được tính dựa trên (số pool connection thực tế + buffer cho admin/maintenance), không phải theo số lượng worker ứng dụng

---

### Case 2: Streaming Replication broken — replication slot bị stuck gây phình WAL

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Standby ngừng nhận WAL, đồng thời disk trên Primary tăng nhanh bất thường do WAL không được recycle — nếu không phát hiện kịp, Primary có thể đầy disk và ngừng hoạt động hoàn toàn (ảnh hưởng cả hệ thống chính, không chỉ standby).

**2. Nguyên nhân**
Replication slot được tạo cho standby nhưng standby đã ngừng kết nối (crash, network cắt, hoặc bị xóa mà quên drop slot tương ứng) — PostgreSQL giữ lại toàn bộ WAL kể từ vị trí slot đó vì thiết kế "physical replication slot" đảm bảo không mất dữ liệu cho standby, nhưng đồng thời không có cơ chế tự động timeout.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác định slot không hoạt động (active=false) và mức độ WAL bị giữ lại
psql -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
          FROM pg_replication_slots;"

# Bước 2: Xác nhận standby tương ứng có còn cần thiết không (đã bị decommission hay chỉ mất kết nối tạm thời)

# Bước 3a: Nếu standby không còn dùng — drop slot ngay
psql -c "SELECT pg_drop_replication_slot('slot_name');"

# Bước 3b: Nếu standby vẫn cần — khôi phục kết nối standby càng sớm càng tốt để slot resume
# Kiểm tra log trên standby:
tail -100 /var/log/postgresql/postgresql.log | grep -i "streaming\|fatal"
```

**4. Bài học kinh nghiệm**
Physical replication slot là con dao hai lưỡi: nó đảm bảo standby không bao giờ bị "gap" (mất WAL cần thiết) nhưng đổi lại có thể gây sự cố nghiêm trọng hơn nhiều lần cho Primary nếu standby biến mất mà không dọn slot — ưu tiên bảo vệ standby vô tình trở thành rủi ro cho chính Primary.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Alert riêng và có mức độ nghiêm trọng cao cho `pg_replication_slots.active=false` kéo dài quá X phút, độc lập với alert disk usage chung
- Đưa "drop replication slot" thành bước bắt buộc trong quy trình decommission một standby, không được bỏ qua
- Cân nhắc dùng `max_slot_wal_keep_size` (PostgreSQL 13+) để giới hạn tối đa WAL giữ lại cho mỗi slot, chấp nhận đánh đổi standby có thể cần rebuild thay vì để Primary gặp rủi ro hết disk

---

### Case 3: Table/Index bloat nghiêm trọng do thiếu VACUUM định kỳ

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Query trên bảng lớn ngày càng chậm dần theo thời gian dù dữ liệu logic (số row thực tế) không tăng tương ứng — kích thước vật lý bảng/index phình to bất thường so với dữ liệu thực.

**2. Nguyên nhân**
Do đặc tính MVCC của PostgreSQL, mỗi UPDATE/DELETE tạo ra dead tuple thay vì ghi đè trực tiếp — autovacuum không dọn kịp do cấu hình mặc định (`autovacuum_vacuum_scale_factor`) không phù hợp với bảng có tốc độ ghi rất cao, hoặc do có transaction dài giữ lock cản trở autovacuum hoạt động hiệu quả.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác định các bảng có dead tuple cao nhất
SELECT relname, n_dead_tup, n_live_tup,
       ROUND(n_dead_tup::numeric/NULLIF(n_live_tup,0)*100,1) AS dead_pct
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 10;

-- Bước 2: Kiểm tra autovacuum có đang chạy/bị chặn không
SELECT pid, query, state FROM pg_stat_activity WHERE query LIKE '%autovacuum%';

-- Bước 3: VACUUM thủ công cho bảng bị ảnh hưởng nặng (ngoài giờ cao điểm)
VACUUM (VERBOSE, ANALYZE) schema.large_table;

-- Bước 4: Với bảng ghi rất nhiều, điều chỉnh riêng ngưỡng autovacuum cho bảng đó
ALTER TABLE schema.large_table SET (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_vacuum_cost_delay = 0
);
```

**4. Bài học kinh nghiệm**
Cấu hình autovacuum mặc định của PostgreSQL được thiết kế cho khối lượng công việc trung bình — với bảng có write pattern cao (queue, log, session table), cần override riêng theo bảng thay vì kỳ vọng cấu hình mặc định cấp database đủ dùng cho mọi bảng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Xác định trước các bảng "hot" (ghi/xóa nhiều) ngay từ giai đoạn thiết kế và cấu hình autovacuum riêng cho từng bảng đó
- Giám sát tỷ lệ dead tuple/live tuple định kỳ như một chỉ số sức khỏe database, không đợi query chậm mới điều tra
- Với bảng dạng queue (insert rồi xóa liên tục), cân nhắc kiến trúc thay thế (partition theo thời gian, TRUNCATE thay vì DELETE hàng loạt) để giảm áp lực lên VACUUM

---

### Case 4: Transaction ID Wraparound — nguy cơ database tự shutdown

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL nghiêm trọng nhất trong PostgreSQL. Nếu không xử lý kịp, PostgreSQL sẽ tự chuyển sang chế độ chỉ cho phép superuser kết nối để chạy VACUUM (single-user mode), toàn bộ ứng dụng ngừng hoạt động để bảo vệ tính toàn vẹn dữ liệu.

**2. Nguyên nhân**
PostgreSQL dùng transaction ID 32-bit hữu hạn — nếu `age(datfrozenxid)` của một database tiệm cận giới hạn (~2 tỷ) mà không được VACUUM FREEZE kịp thời, hệ thống buộc phải tự bảo vệ. Nguyên nhân gốc thường là autovacuum bị vô hiệu hóa nhầm, hoặc có transaction/prepared transaction bị "treo" (orphaned) giữ nguyên age không tăng.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra ngay age của tất cả database, ưu tiên xử lý database cao nhất
SELECT datname, age(datfrozenxid) AS xid_age
FROM pg_database ORDER BY xid_age DESC;

-- Bước 2: Kiểm tra có transaction/prepared transaction nào đang "treo" gây cản trở
SELECT gid, prepared, owner FROM pg_prepared_xacts;
SELECT pid, state, age(backend_xid) FROM pg_stat_activity WHERE backend_xid IS NOT NULL
ORDER BY age(backend_xid) DESC;

-- Bước 3: Xử lý transaction treo trước (rollback prepared transaction nếu an toàn)
ROLLBACK PREPARED 'gid_value';

-- Bước 4: Chạy VACUUM FREEZE khẩn cấp cho database có age cao nhất
VACUUM FREEZE;  -- Chạy trên toàn database, ưu tiên bảng lớn nhất trước nếu cần
```

**4. Bài học kinh nghiệm**
Wraparound là loại sự cố "âm thầm tích lũy trong nhiều tháng/năm" rồi bùng phát đột ngột thành ngừng dịch vụ hoàn toàn — khác hẳn các lỗi PostgreSQL khác thường có dấu hiệu cảnh báo rõ ràng trước đó, đây là lý do nó thường bị đánh giá thấp mức độ ưu tiên cho đến khi quá muộn.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát `age(datfrozenxid)` cho MỌI database định kỳ (hàng ngày), alert nghiêm trọng khi vượt 1 tỷ (khoảng 50% giới hạn), không đợi đến ngưỡng khẩn cấp của PostgreSQL
- Không bao giờ tắt autovacuum ở cấp toàn database (`autovacuum=off`) trừ trường hợp bảo trì có kiểm soát, và phải bật lại ngay sau đó
- Kiểm tra và dọn định kỳ prepared transaction/replication slot mồ côi — đây là nguyên nhân phổ biến khiến VACUUM không thể tiến triển dù được kích hoạt đúng

---

### Case 5: Autovacuum không theo kịp do long-running transaction giữ lock

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, tiền đề trực tiếp dẫn tới Case 3 và Case 4 nếu không xử lý sớm. Autovacuum khởi động nhưng không thể dọn dead tuple hiệu quả, `age(datfrozenxid)` tiếp tục tăng dù autovacuum vẫn "đang chạy".

**2. Nguyên nhân**
Một transaction dài (báo cáo, batch job, hoặc session ứng dụng quên COMMIT) giữ snapshot cũ, khiến PostgreSQL không thể xác định dead tuple nào thực sự an toàn để dọn — về bản chất autovacuum bị "khóa tay" bởi transaction đang mở dù không có lock tường minh trên bảng.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Tìm transaction dài nhất đang mở
SELECT pid, usename, state, now()-xact_start AS duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY duration DESC LIMIT 10;

-- Bước 2: Xác định đây có phải nguyên nhân chặn vacuum không
SELECT datname, age(backend_xmin) FROM pg_stat_activity WHERE backend_xmin IS NOT NULL
ORDER BY age(backend_xmin) DESC;

-- Bước 3: Với transaction xác nhận là "mồ côi" hoặc không còn cần thiết
SELECT pg_terminate_backend(pid);

-- Bước 4: Sau khi giải phóng, VACUUM sẽ tự động tiến triển ở lần chạy autovacuum tiếp theo,
-- hoặc kích hoạt thủ công để xác nhận ngay
VACUUM (VERBOSE) schema.affected_table;
```

**4. Bài học kinh nghiệm**
Long-running transaction là nguyên nhân gốc ẩn sau rất nhiều vấn đề PostgreSQL tưởng chừng không liên quan (bloat, wraparound, replication lag) — cần được xem như một chỉ số sức khỏe hệ thống độc lập, được giám sát chủ động thay vì chỉ điều tra khi có triệu chứng khác xuất hiện.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đặt `statement_timeout` và `idle_in_transaction_session_timeout` hợp lý ở cấp database/role để tự động cắt transaction/session treo quá lâu
- Yêu cầu team ứng dụng/BI tách riêng connection cho báo cáo dài (dùng replica/standby cho query nặng) thay vì chạy trực tiếp trên Primary cùng với OLTP traffic
- Giám sát liên tục transaction có `age(backend_xmin)` hoặc thời lượng vượt ngưỡng, alert sớm trước khi ảnh hưởng tới VACUUM

---

## NHÓM B: SQL SERVER — INTEGRITY / ALWAYSON / CONCURRENCY (Case 6-10)

### Case 6: Database ở trạng thái SUSPECT sau sự cố storage

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Database chuyển sang trạng thái `SUSPECT`, hoàn toàn không thể truy cập, toàn bộ ứng dụng liên quan ngừng hoạt động ngay lập tức.

**2. Nguyên nhân**
Thường do lỗi I/O đột ngột trên storage (mất điện không sạch, SAN timeout, corrupt sector) trong lúc SQL Server đang ghi vào transaction log hoặc data file, khiến SQL Server không thể hoàn tất recovery khi khởi động lại và đánh dấu database không đáng tin cậy để bảo vệ dữ liệu.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận trạng thái và nguyên nhân qua error log
EXEC sp_readerrorlog 0, 1, 'suspect';

-- Bước 2: Chuyển database sang EMERGENCY để có thể truy cập read-only, đánh giá thiệt hại
ALTER DATABASE mydb SET EMERGENCY;

-- Bước 3: Chạy CHECKDB để xác định phạm vi corruption trước khi quyết định phương án
DBCC CHECKDB(mydb) WITH NO_INFOMSGS, ALL_ERRORMSGS;

-- Bước 4a: Nếu có backup gần nhất còn tốt — ƯU TIÊN restore từ backup thay vì repair
-- (REPAIR_ALLOW_DATA_LOSS có thể làm mất dữ liệu không thể khôi phục)
RESTORE DATABASE mydb FROM DISK='/backup/mydb_full.bak' WITH NORECOVERY;
RESTORE LOG mydb FROM DISK='/backup/mydb_log.trn' WITH RECOVERY;

-- Bước 4b: Chỉ dùng REPAIR khi không còn lựa chọn nào khác và đã chấp nhận rủi ro mất dữ liệu
ALTER DATABASE mydb SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DBCC CHECKDB(mydb, REPAIR_ALLOW_DATA_LOSS);
ALTER DATABASE mydb SET MULTI_USER;
```

**4. Bài học kinh nghiệm**
`REPAIR_ALLOW_DATA_LOSS` là phương án cuối cùng, không phải phản xạ đầu tiên — nhiều DBA vội chạy lệnh này ngay khi thấy SUSPECT mà không kiểm tra backup trước, dẫn đến mất dữ liệu đáng lẽ có thể khôi phục đầy đủ nếu restore từ backup hợp lệ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đảm bảo backup full + transaction log backup chạy đúng lịch và được test restore định kỳ — đây là "van an toàn" thực sự cho tình huống SUSPECT, không phải DBCC REPAIR
- Bật `PAGE_VERIFY CHECKSUM` cho mọi database để SQL Server phát hiện corruption sớm nhất có thể, trước khi nó lan rộng
- Giám sát I/O latency của storage layer chủ động (không đợi SQL Server báo lỗi), vì corruption gần như luôn bắt nguồn từ vấn đề storage bên dưới

---

### Case 7: TempDB đầy / contention gây treo toàn hệ thống

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, có thể lan rộng thành ngừng dịch vụ toàn instance vì TempDB dùng chung cho mọi database. Query báo lỗi hết dung lượng TempDB, hoặc hệ thống chậm nghiêm trọng do tranh chấp (contention) trên các trang hệ thống (PFS/GAM/SGAM) của TempDB.

**2. Nguyên nhân**
Query có thao tác sort/hash lớn (ORDER BY, GROUP BY, DISTINCT trên tập dữ liệu khổng lồ) hoặc sử dụng nhiều temp table/table variable không tối ưu; đồng thời TempDB chỉ có 1 file dữ liệu (cấu hình mặc định) gây tranh chấp allocation page khi có nhiều session cùng dùng TempDB đồng thời.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra dung lượng TempDB đang dùng
DBCC SQLPERF(LOGSPACE);
SELECT SUM(unallocated_extent_page_count)*8/1024 AS free_MB FROM sys.dm_db_file_space_usage;

-- Bước 2: Xác định query/session đang chiếm dụng TempDB nhiều nhất
SELECT r.session_id, t.text, du.user_objects_alloc_page_count*8/1024 AS mb_used
FROM sys.dm_db_task_space_usage du
JOIN sys.dm_exec_requests r ON du.session_id = r.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
ORDER BY mb_used DESC;

-- Bước 3: Xử lý ngay — kill session gây tràn nếu là query lỗi/ngoài kế hoạch
KILL <session_id>;

-- Bước 4: Giải pháp cấu hình lâu dài — nhiều file TempDB (bằng số core, tối đa 8) kích thước bằng nhau
ALTER DATABASE tempdb MODIFY FILE (NAME=tempdev, SIZE=10GB);
ALTER DATABASE tempdb ADD FILE (NAME=tempdev2, FILENAME='D:\tempdb2.ndf', SIZE=10GB);
```

**4. Bài học kinh nghiệm**
TempDB thường bị "quên" trong quá trình sizing ban đầu vì không chứa dữ liệu nghiệp vụ, nhưng nó là tài nguyên dùng chung toàn instance — một query tệ trên một database bất kỳ có thể làm chậm mọi database khác thông qua TempDB.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình chuẩn TempDB ngay khi cài đặt: nhiều file kích thước bằng nhau (số lượng tùy theo số core, khuyến nghị Microsoft), đặt trên storage nhanh riêng biệt (SSD/NVMe) nếu có thể
- Giám sát dung lượng và contention TempDB như một chỉ số sức khỏe instance-level, không chỉ theo dõi từng database riêng lẻ
- Review và tối ưu các query có pattern sort/hash lớn định kỳ, đặc biệt các báo cáo BI chạy trực tiếp trên OLTP instance

---

### Case 8: AlwaysOn Availability Group ngừng đồng bộ (NOT SYNCHRONIZING)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Secondary replica báo trạng thái `NOT SYNCHRONIZING`, mất khả năng failover, đồng thời nếu ứng dụng đang dùng Readable Secondary cho báo cáo, dữ liệu trên đó bắt đầu lỗi thời.

**2. Nguyên nhân**
Thường do network gián đoạn giữa các replica, hoặc disk trên Secondary đầy khiến redo log không thể apply, hoặc data movement bị tạm dừng thủ công (do bảo trì) nhưng quên resume sau đó.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra trạng thái đồng bộ chi tiết từng database trong AG
SELECT ag.name, drs.database_id, drs.synchronization_state_desc,
       drs.is_suspended, drs.suspend_reason_desc
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_groups ag ON drs.group_id = ag.group_id;

-- Bước 2: Nếu bị suspend thủ công (is_suspended=1) — resume lại
ALTER DATABASE mydb SET HADR RESUME;

-- Bước 3: Nếu do disk đầy trên Secondary — giải phóng dung lượng trước khi resume
-- Kiểm tra dung lượng redo log path

-- Bước 4: Nếu lỗi kéo dài không tự phục hồi — kiểm tra Extended Events/Error log AG
SELECT * FROM sys.dm_hadr_availability_replica_states;
```

**4. Bài học kinh nghiệm**
`RESUME` sau bảo trì là bước rất dễ bị quên trong quy trình vận hành thủ công — AG có thể "trông như hoạt động" (Primary vẫn phục vụ ứng dụng bình thường) trong khi Secondary đã âm thầm mất đồng bộ suốt nhiều ngày nếu không có giám sát chủ động.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Mọi thao tác `SUSPEND` trên AG phải được ghi vào change log kèm thời gian dự kiến `RESUME`, và có alert nếu quá thời gian đó mà chưa resume
- Giám sát `synchronization_state_desc` liên tục cho tất cả database trong AG, alert ngay khi khác `SYNCHRONIZED`/`SYNCHRONIZING` bình thường
- Đảm bảo dung lượng disk trên mọi Secondary luôn được provisioning tương đương Primary, tránh chênh lệch capacity gây nghẽn redo log

---

### Case 9: Blocking chain kéo dài gây timeout hàng loạt ứng dụng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED nhưng ảnh hưởng diện rộng — hàng loạt request ứng dụng timeout đồng thời dù CPU/Memory server vẫn ở mức bình thường, dễ gây hiểu nhầm là "database quá tải" trong khi thực chất là vấn đề khóa (locking).

**2. Nguyên nhân**
Một transaction "đầu chuỗi" (head blocker) giữ lock lâu bất thường (do thiếu index gây table scan trong lúc UPDATE, hoặc quên COMMIT/ROLLBACK) khiến hàng loạt session khác xếp hàng chờ theo chuỗi (blocking chain), tạo hiệu ứng domino lan rộng nhanh chóng.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác định session đầu chuỗi (head blocker) — session có blocking_session_id nhưng
-- bản thân KHÔNG bị block bởi ai khác
SELECT session_id, blocking_session_id, wait_type, wait_time, wait_resource
FROM sys.dm_exec_requests WHERE blocking_session_id != 0;

-- Bước 2: Xem chi tiết query của head blocker
SELECT t.text FROM sys.dm_exec_connections c
CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) t
WHERE c.session_id = <head_blocker_id>;

-- Bước 3: Xử lý khẩn cấp — kill head blocker nếu xác nhận là transaction lỗi/treo
KILL <head_blocker_id>;

-- Bước 4: Điều tra nguyên nhân gốc (thiếu index, transaction thiết kế sai) để fix triệt để
```

**4. Bài học kinh nghiệm**
Trong sự cố blocking chain, việc kill nhầm session bị block (thay vì head blocker thực sự) không giải quyết được vấn đề — kỹ năng xác định chính xác đầu chuỗi block là yếu tố quyết định tốc độ xử lý sự cố.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Review và bổ sung index cho các câu UPDATE/DELETE thường xuyên trên bảng lớn, tránh table scan giữ lock diện rộng không cần thiết
- Thiết lập alert tự động khi phát hiện blocking chain vượt ngưỡng thời gian (ví dụ >30 giây) hoặc số lượng session bị block vượt ngưỡng, kèm tự động capture thông tin head blocker
- Đào tạo team phát triển về quản lý transaction đúng cách (transaction ngắn, commit sớm, tránh gọi external service trong transaction đang mở)

---

### Case 10: Transaction Log đầy (Error 9002) do log không được backup

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Database chuyển sang chế độ read-only hoặc từ chối mọi ghi mới, ứng dụng báo lỗi `The transaction log for database is full`.

**2. Nguyên nhân**
Database ở chế độ FULL recovery model nhưng job backup transaction log bị lỗi/ngừng chạy trong thời gian dài mà không ai phát hiện — transaction log chỉ được giải phóng (truncate) sau khi backup log thành công, nên log file tăng trưởng không giới hạn cho đến khi hết disk.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận nguyên nhân — kiểm tra log_reuse_wait_desc
SELECT name, log_reuse_wait_desc FROM sys.databases WHERE name='mydb';
-- Nếu là 'LOG_BACKUP' -> xác nhận đúng nguyên nhân

-- Bước 2: Backup log ngay lập tức để giải phóng không gian
BACKUP LOG mydb TO DISK='/backup/mydb_log_emergency.trn';

-- Bước 3: Nếu disk đã đầy hoàn toàn, không backup được — thêm file log tạm trên ổ khác
ALTER DATABASE mydb ADD LOG FILE (NAME=mydb_log2, FILENAME='E:\temp\mydb_log2.ldf', SIZE=5GB);
-- Sau khi backup log thành công và ổn định, xóa file tạm này

-- Bước 4: Xác nhận job backup log đã chạy lại đúng lịch
```

**4. Bài học kinh nghiệm**
`SHRINKFILE` transaction log ngay sau sự cố (một phản xạ phổ biến) chỉ giải quyết triệu chứng tạm thời — nếu không khắc phục nguyên nhân gốc (job backup log bị lỗi), log sẽ phình to trở lại ngay sau đó với cùng tốc độ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát job backup log như một thành phần hạ tầng nghiêm trọng (critical infrastructure job), alert ngay khi job thất bại hoặc bị bỏ lỡ lịch, không chỉ alert khi log đã đầy
- Với database FULL recovery model, đảm bảo tần suất backup log phù hợp với tốc độ sinh log thực tế (không mặc định "1 giờ/lần" cho mọi hệ thống)
- Định kỳ review kích thước log file so với kích thước data file — tỷ lệ bất thường là dấu hiệu sớm của vấn đề backup log

---

## NHÓM C: MYSQL/MARIADB — REPLICATION / STORAGE ENGINE (Case 11-15)

### Case 11: Replication (Slave) dừng do lỗi trùng khóa chính

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. `SHOW SLAVE STATUS` báo `Slave_SQL_Running: No`, replica ngừng nhận cập nhật mới, dữ liệu trên slave "đóng băng" tại thời điểm lỗi trong khi Master vẫn tiếp tục hoạt động bình thường.

**2. Nguyên nhân**
Thường do có thao tác ghi trực tiếp vào slave (vi phạm nguyên tắc read-only replica, có thể do nhầm connection string trong một script bảo trì), gây trùng dữ liệu khi binlog từ Master áp dụng lại INSERT với cùng primary key.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận lỗi cụ thể
mysql -e "SHOW SLAVE STATUS\G" | grep -E "Last_SQL_Error|Last_Errno"

# Bước 2: Xác định mức độ nghiêm trọng — dữ liệu trùng có phải cùng nội dung với Master không
# (nếu đúng là duplicate hợp lệ, có thể skip an toàn; nếu KHÔNG khớp, cần điều tra kỹ hơn)

# Bước 3a: Nếu xác nhận an toàn để skip (dữ liệu Master mới hơn/đúng hơn)
mysql -e "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1; START SLAVE;"

# Bước 3b: Nếu nghi ngờ dữ liệu đã lệch nhiều — không skip mù quáng, cần đối chiếu
# bằng pt-table-checksum (Percona Toolkit) trước khi quyết định

# Bước 4: Xác nhận replication chạy lại bình thường
mysql -e "SHOW SLAVE STATUS\G" | grep -E "Running|Seconds_Behind"
```

**4. Bài học kinh nghiệm**
`SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1` là công cụ "chữa cháy nhanh" nhưng nguy hiểm nếu dùng theo phản xạ mà không hiểu rõ nguyên nhân — bỏ qua một transaction sai cách có thể khiến slave lệch dữ liệu vĩnh viễn so với Master mà không có cảnh báo nào tiếp theo.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc `read_only=ON` (và `super_read_only=ON` cho MySQL 8.0+) trên mọi replica ở cấp cấu hình server, không chỉ dựa vào quy ước connection string của ứng dụng
- Tách biệt hoàn toàn credential/connection string giữa Master và Replica ngay từ khi thiết kế, giảm nguy cơ nhầm lẫn trong script vận hành
- Chạy `pt-table-checksum` định kỳ để phát hiện sớm lệch dữ liệu giữa Master-Replica, không đợi đến khi replication ABEND mới biết

---

### Case 12: InnoDB corruption sau crash không sạch (unclean shutdown)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Sau khi MySQL restart sau sự cố mất điện/kill -9, log báo lỗi corruption trong tablespace InnoDB, một số bảng không truy cập được hoặc server từ chối khởi động hoàn toàn.

**2. Nguyên nhân**
`innodb_flush_log_at_trx_commit` không được đặt ở giá trị an toàn (=1) kết hợp với việc tắt máy đột ngột (không qua `SHUTDOWN` chuẩn), khiến InnoDB không hoàn tất crash recovery đúng cách khi khởi động lại.

**3. Thủ tục xử lý**
```bash
# Bước 1: Thử khởi động với innodb_force_recovery tăng dần (bắt đầu từ mức thấp nhất)
# Thêm vào my.cnf: innodb_force_recovery = 1
systemctl start mysql
# Nếu vẫn lỗi, tăng dần lên 2, 3... (mức 6 chỉ dùng để dump dữ liệu, KHÔNG dùng lâu dài)

# Bước 2: Ngay khi khởi động được (dù ở chế độ force recovery) — export dữ liệu ra ngay
mysqldump --all-databases --single-transaction > emergency_backup.sql

# Bước 3: Dừng server, xóa sạch ibdata/ib_logfile, khởi động lại như một instance mới
# rồi import lại dữ liệu đã export (KHÔNG cố sửa trực tiếp file corrupt)

# Bước 4: Kiểm tra toàn bộ bảng sau khi restore
mysqlcheck --all-databases --check
```

**4. Bài học kinh nghiệm**
`innodb_force_recovery` chỉ nên dùng để "cứu dữ liệu ra ngoài" chứ không phải giải pháp vận hành lâu dài — server chạy ở các mức force_recovery cao có thể trả về dữ liệu không nhất quán mà không báo lỗi rõ ràng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đảm bảo `innodb_flush_log_at_trx_commit=1` và `sync_binlog=1` cho mọi hệ thống production coi trọng tính toàn vẹn dữ liệu, chấp nhận đánh đổi hiệu năng ghi để đổi lấy an toàn dữ liệu
- Có UPS/cơ chế shutdown graceful cho hạ tầng vật lý/ảo hóa, tránh unclean shutdown ngay từ tầng hạ tầng thay vì chỉ dựa vào cấu hình database
- Backup định kỳ (mysqldump/Percona XtraBackup) với tần suất phù hợp RPO yêu cầu, vì đây luôn là phương án phục hồi đáng tin cậy nhất khi corruption xảy ra

---

### Case 13: "Too many connections" do connection leak từ ứng dụng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Ứng dụng nhận lỗi `ERROR 1040: Too many connections`, tương tự Case 1 của PostgreSQL nhưng với đặc thù riêng của MySQL connection pool ở tầng driver/ORM.

**2. Nguyên nhân**
Connection pool ở tầng ứng dụng (HikariCP, mysql2 pool...) cấu hình sai (pool size quá lớn so với `max_connections` của MySQL, hoặc không release connection về pool đúng cách sau khi dùng), đặc biệt phổ biến trong kiến trúc microservices có nhiều service cùng kết nối vào một MySQL instance.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra số connection hiện tại và giới hạn
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -e "SHOW STATUS LIKE 'Threads_connected';"

# Bước 2: Xác định service/user nào chiếm nhiều connection nhất
mysql -e "SELECT user, host, count(*) FROM information_schema.processlist GROUP BY user, host ORDER BY count(*) DESC;"

# Bước 3: Xử lý khẩn cấp — tăng tạm max_connections nếu server còn tài nguyên
mysql -e "SET GLOBAL max_connections = 500;"

# Bước 4: Xác định và fix service có connection leak (review pool config, đảm bảo
# đóng connection/transaction đúng cách trong code, đặc biệt trong exception handling)
```

**4. Bài học kinh nghiệm**
Trong kiến trúc microservices, tổng connection pool của TẤT CẢ service cộng lại thường vượt xa `max_connections` mà không ai tính tổng — mỗi team chỉ nhìn vào cấu hình pool của riêng service mình mà không có cái nhìn tổng thể.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết lập ProxySQL hoặc MySQL Router làm tầng trung gian quản lý connection tập trung cho kiến trúc microservices, thay vì để từng service tự quản lý pool riêng lẻ
- Yêu cầu mọi service đăng ký pool size dự kiến với DBA trước khi go-live, để tính tổng và đảm bảo không vượt giới hạn instance
- Giám sát `Threads_connected` theo xu hướng thời gian, alert sớm khi tiệm cận `max_connections` thay vì đợi lỗi thực sự xảy ra

---

### Case 14: Disk đầy do binlog tăng trưởng không kiểm soát

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Disk chứa binary log đầy hoàn toàn, MySQL không thể ghi thêm dữ liệu, server có thể crash hoặc từ chối mọi write mới.

**2. Nguyên nhân**
`expire_logs_days` (hoặc `binlog_expire_logs_seconds` ở MySQL 8.0+) không được cấu hình hoặc đặt giá trị quá lớn, kết hợp với có replica/consumer (như Debezium CDC) đọc binlog chậm hoặc đã ngừng đọc từ lâu khiến MySQL không dám xóa binlog cũ vì sợ replica cần đến.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra dung lượng binlog hiện tại
du -sh /var/lib/mysql/binlog.*

# Bước 2: Kiểm tra vị trí đọc binlog của các replica/consumer đang active
mysql -e "SHOW BINARY LOGS;"
mysql -e "SHOW SLAVE HOSTS;"  -- hoặc SHOW REPLICAS trên MySQL 8.0+

# Bước 3: Xóa an toàn các binlog đã được TẤT CẢ replica/consumer đọc qua
mysql -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;"
# Chỉ dùng ngày gần hơn nếu đã xác nhận chắc chắn không còn consumer nào cần binlog cũ hơn

# Bước 4: Cấu hình lại expire tự động cho lâu dài
mysql -e "SET GLOBAL binlog_expire_logs_seconds = 604800;"  -- 7 ngày
```

**4. Bài học kinh nghiệm**
Xóa binlog thủ công bằng lệnh `rm` trực tiếp trên filesystem (thay vì `PURGE BINARY LOGS`) là sai lầm nghiêm trọng — MySQL vẫn giữ tham chiếu đến các file đã bị xóa trong index, gây lỗi khi replica cố gắng đọc lại binlog đã "biến mất" một cách không nhất quán.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Luôn cấu hình `binlog_expire_logs_seconds` tường minh phù hợp với capacity disk thực tế, không để giá trị mặc định/vô hạn
- Giám sát vị trí đọc binlog của mọi consumer (replica, CDC tool) và cảnh báo sớm khi có consumer bị "bỏ lại" quá xa so với vị trí ghi hiện tại của Master
- Capacity planning riêng cho volume chứa binlog, tách biệt khỏi volume chứa data file để tránh binlog đầy ảnh hưởng trực tiếp tới khả năng ghi dữ liệu nghiệp vụ

---

### Case 15: Deadlock / Lock wait timeout tăng đột biến giờ cao điểm

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, tập trung vào khung giờ cao điểm gây trải nghiệm người dùng kém đồng loạt. Ứng dụng nhận lỗi `Deadlock found when trying to get lock` hoặc `Lock wait timeout exceeded` tăng vọt trong giờ traffic cao.

**2. Nguyên nhân**
Nhiều transaction truy cập cùng tập bảng theo thứ tự khác nhau (ví dụ transaction A: update bảng Orders rồi Inventory; transaction B: update Inventory rồi Orders) tạo vòng lặp chờ lẫn nhau kinh điển, hoặc thiếu index khiến InnoDB phải khóa nhiều row hơn cần thiết (gap lock) khi thực hiện UPDATE/DELETE có điều kiện WHERE không dùng index hiệu quả.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xem chi tiết deadlock gần nhất từ InnoDB status
SHOW ENGINE INNODB STATUS\G
-- Tìm phần "LATEST DETECTED DEADLOCK", xác định 2 transaction và thứ tự lock

-- Bước 2: Xác định query nào thiếu index gây lock diện rộng
EXPLAIN SELECT ... FROM table WHERE condition;
-- Nếu type=ALL hoặc dùng nhiều row hơn cần thiết -> cần thêm index

-- Bước 3: Sửa thứ tự truy cập bảng trong code ứng dụng để nhất quán giữa các transaction
-- (Đây là fix quan trọng nhất, không chỉ dựa vào retry logic)

-- Bước 4: Bổ sung retry logic hợp lý ở tầng ứng dụng cho lỗi deadlock
-- (Deadlock là cơ chế tự bảo vệ bình thường của InnoDB, cần retry thay vì coi là lỗi nghiêm trọng)
```

**4. Bài học kinh nghiệm**
Deadlock không phải lúc nào cũng là "lỗi cấu hình database" — phần lớn là hệ quả của thiết kế transaction ở tầng ứng dụng không nhất quán về thứ tự truy cập tài nguyên, cần được xử lý từ gốc ở code chứ không chỉ tối ưu database.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Chuẩn hóa quy tắc thứ tự truy cập bảng trong mọi transaction đa bảng ngay từ giai đoạn thiết kế (ví dụ luôn theo thứ tự alphabet tên bảng), giảm thiểu deadlock kinh điển
- Review và bổ sung index cho các câu UPDATE/DELETE có điều kiện phức tạp, giảm phạm vi lock không cần thiết
- Bắt buộc mọi client code có retry logic chuẩn cho lỗi deadlock (với backoff hợp lý), coi đây là một phần thiết kế bình thường chứ không phải xử lý ngoại lệ

---

## NHÓM D: MONGODB — REPLICA SET / SHARDING / STORAGE ENGINE (Case 16-20)

### Case 16: Replica Set liên tục bầu lại Primary (election storm)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Cluster liên tục chuyển vai trò Primary trong thời gian ngắn (vài phút một lần), ứng dụng nhận lỗi kết nối gián đoạn liên tục vì driver phải reconnect mỗi lần có election mới.

**2. Nguyên nhân**
Network không ổn định giữa các member replica set (đặc biệt phổ biến khi các node đặt ở nhiều datacenter/AZ khác nhau với latency dao động), khiến heartbeat giữa các node bị miss vượt ngưỡng `electionTimeoutMillis`, kích hoạt election mới dù Primary cũ thực chất vẫn hoạt động bình thường.

**3. Thủ tục xử lý**
```javascript
// Bước 1: Kiểm tra lịch sử election và trạng thái replica set
rs.status()
db.getSiblingDB("local").oplog.rs.find().sort({$natural:-1}).limit(1)

// Bước 2: Kiểm tra log tìm nguyên nhân election
// grep "election" trong mongod.log của mọi node
// tìm "heartbeat" timeout hoặc network error

// Bước 3: Kiểm tra độ trễ mạng thực tế giữa các node
// ping/mtr giữa các server, đặc biệt nếu cross-region

// Bước 4: Điều chỉnh electionTimeoutMillis phù hợp với đặc tính mạng thực tế
// (chỉ tăng sau khi đã xác nhận không thể cải thiện network)
cfg = rs.conf()
cfg.settings.electionTimeoutMillis = 12000
rs.reconfig(cfg)
```

**4. Bài học kinh nghiệm**
Election storm gần như luôn là triệu chứng của vấn đề hạ tầng mạng bên dưới, không phải lỗi logic của MongoDB — cố gắng "vá" bằng cách tăng timeout mà không điều tra nguyên nhân mạng chỉ trì hoãn vấn đề, không giải quyết triệt để.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết kế replica set với các node trong cùng region/AZ có kết nối ổn định làm ưu tiên, chỉ đặt node cross-region cho mục đích DR với hiểu biết rõ về trade-off latency
- Giám sát network latency/packet loss giữa các member replica set như một chỉ số sức khỏe cluster độc lập, không chỉ dựa vào `rs.status()` khi có sự cố
- Set `priority` và `votes` hợp lý cho các node theo vai trò (node DR cross-region nên có priority thấp hơn để tránh trở thành Primary không mong muốn khi network dao động)

---

### Case 17: WiredTiger cache pressure gây chậm toàn cluster

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Toàn bộ query trên cluster chậm đột ngột dù không có thay đổi về khối lượng dữ liệu hay traffic rõ ràng, thường đi kèm CPU tăng cao bất thường.

**2. Nguyên nhân**
WiredTiger cache (mặc định 50% RAM trừ 1GB) không đủ chứa working set dữ liệu đang hoạt động (do dữ liệu tăng trưởng vượt dự kiến ban đầu, hoặc có query pattern mới quét nhiều dữ liệu "lạnh" ngoài working set thông thường), khiến engine phải liên tục evict page ra khỏi cache và đọc lại từ disk.

**3. Thủ tục xử lý**
```javascript
// Bước 1: Kiểm tra chỉ số cache pressure
db.serverStatus().wiredTiger.cache

// Các chỉ số quan trọng cần xem:
// "bytes currently in the cache" so với "maximum bytes configured"
// "tracked dirty bytes in the cache" - nếu cao, cache đang bị áp lực ghi

// Bước 2: Xác định query đang gây quét dữ liệu lớn bất thường
db.currentOp({"secs_running": {$gt: 3}})

// Bước 3: Xử lý khẩn cấp — kill operation gây quét lớn ngoài kế hoạch nếu có
db.killOp(<opid>)

// Bước 4: Giải pháp lâu dài — tăng RAM/cacheSizeGB nếu working set thực sự lớn hơn dự kiến
// mongod.conf:
// storage.wiredTiger.engineConfig.cacheSizeGB: 16
```

**4. Bài học kinh nghiệm**
Cache sizing cho MongoDB cần dựa trên "working set" thực tế (tập dữ liệu được truy cập thường xuyên), không phải tổng kích thước database — một cluster có database rất lớn nhưng working set nhỏ vẫn có thể hoạt động tốt với cache khiêm tốn, và ngược lại.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát chỉ số cache eviction rate và cache pressure định kỳ, thiết lập alert khi eviction tăng cao bất thường thay vì chỉ phát hiện qua triệu chứng chậm chung chung
- Review pattern truy vấn định kỳ, đảm bảo có index phù hợp để tránh collection scan không cần thiết làm "ô nhiễm" cache với dữ liệu ít dùng
- Capacity planning RAM dựa trên phân tích working set thực tế (qua công cụ như MongoDB Atlas Performance Advisor hoặc phân tích log), review lại định kỳ theo tăng trưởng dữ liệu

---

### Case 18: Secondary rớt khỏi Oplog (oplog window quá ngắn)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Secondary không thể tiếp tục đồng bộ bình thường (resync) mà chuyển sang trạng thái cần initial sync lại toàn bộ từ đầu — trong thời gian đó, cluster mất một node dự phòng, giảm khả năng chịu lỗi.

**2. Nguyên nhân**
Secondary bị offline/chậm trong thời gian dài hơn kích thước "oplog window" (khoảng thời gian oplog trên Primary còn giữ lại) — khi Secondary quay lại, vị trí nó cần tiếp tục đã bị ghi đè (oplog là capped collection, tự động xoay vòng).

**3. Thủ tục xử lý**
```javascript
// Bước 1: Xác nhận tình trạng — kiểm tra log Secondary
// tìm dòng "our last op time fetched" và "RS102 too stale to catch up"

// Bước 2: Kiểm tra kích thước oplog window hiện tại trên Primary
db.getReplicationInfo()
// Xem "timeDiff" (giờ) - đây là thời gian tối đa Secondary có thể offline mà vẫn resync được

// Bước 3: Nếu đã quá stale — bắt buộc initial sync lại từ đầu
// (Xóa dữ liệu trên Secondary và để MongoDB tự đồng bộ lại, hoặc dùng
// Percona-style physical backup restore để tăng tốc)
rs.stepDown()  -- nếu node này vô tình là Primary
// Trên Secondary cần resync:
// Dừng mongod, xóa dbpath, khởi động lại - MongoDB tự động initial sync

// Bước 4: Giám sát tiến trình initial sync
db.adminCommand({replSetGetStatus: 1}).members
```

**4. Bài học kinh nghiệm**
Kích thước oplog cần được tính toán dựa trên write throughput thực tế và thời gian bảo trì/downtime dự kiến dài nhất có thể xảy ra cho một Secondary (ví dụ patching OS, thay hardware) — cấu hình mặc định thường không đủ cho môi trường production có write rate cao.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tính toán và cấu hình `oplogSizeMB` đủ lớn để bao phủ tối thiểu 72 giờ dữ liệu ở write rate đỉnh, thay vì dùng giá trị mặc định
- Giám sát oplog window (`timeDiff`) như một chỉ số sức khỏe cluster liên tục, alert sớm khi window bị thu hẹp bất thường (dấu hiệu write rate tăng đột biến)
- Với bảo trì có kế hoạch trên một Secondary dự kiến kéo dài, cân nhắc tạm thời loại node đó khỏi replica set (thay vì để nó "treo" offline) để tránh rủi ro rớt khỏi oplog window

---

### Case 19: Sharding Balancer bị kẹt, chunk phân bố lệch nghiêm trọng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Một hoặc vài shard nhận tải không cân xứng (hotspot), gây chậm cục bộ dù tổng tài nguyên cluster vẫn còn dư thừa ở các shard khác.

**2. Nguyên nhân**
Shard key được chọn không tối ưu (ví dụ dùng timestamp tăng dần làm shard key, khiến toàn bộ write mới luôn đổ vào cùng một chunk/shard "nóng nhất"), hoặc balancer bị chặn do có thao tác bảo trì trước đó quên bật lại.

**3. Thủ tục xử lý**
```javascript
// Bước 1: Kiểm tra trạng thái balancer và phân bố chunk
sh.getBalancerState()
db.getSiblingDB("config").chunks.aggregate([
  {$group: {_id: "$shard", count: {$sum: 1}}}
])

// Bước 2: Nếu balancer đang tắt — bật lại
sh.startBalancer()

// Bước 3: Nếu balancer đang chạy nhưng vẫn lệch do shard key kém — đây là vấn đề
// thiết kế, không thể fix chỉ bằng balancer; cần đánh giá lại shard key
sh.status()  -- xem chi tiết phân bố theo range

// Bước 4: Với shard key monotonic gây hotspot, cân nhắc dùng hashed shard key
// cho collection mới, hoặc resharding (MongoDB 5.0+) cho collection hiện tại
sh.reshardCollection("db.collection", {newShardKey: "hashed"})
```

**4. Bài học kinh nghiệm**
Chọn shard key là một trong những quyết định kiến trúc khó thay đổi nhất trong MongoDB — một shard key kém (monotonic, cardinality thấp) không thể khắc phục hoàn toàn chỉ bằng cấu hình balancer, đòi hỏi phải resharding hoặc redesign, vốn là thao tác tốn kém trên dữ liệu lớn.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đầu tư thời gian phân tích kỹ pattern truy vấn và ghi dữ liệu TRƯỚC khi chọn shard key, ưu tiên key có cardinality cao và phân bố write đều (tránh monotonic key như timestamp/auto-increment thuần túy)
- Giám sát phân bố chunk/dung lượng theo shard định kỳ, phát hiện sớm xu hướng lệch trước khi trở thành vấn đề hiệu năng nghiêm trọng
- Tận dụng tính năng resharding của MongoDB 5.0+ như một công cụ khắc phục có kế hoạch, thay vì chờ đến khi hotspot ảnh hưởng nghiêm trọng mới xử lý

---

### Case 20: Connection pool từ driver ứng dụng gây quá tải mongos/mongod

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Tương tự Case 1 (PostgreSQL) và Case 13 (MySQL) nhưng đặc thù MongoDB — số connection tới `mongos` (sharded cluster router) hoặc `mongod` tăng vọt, gây cạn kiệt file descriptor hoặc chậm response.

**2. Nguyên nhân**
Driver MongoDB (Node.js, Java, Python...) mặc định có connection pool size khá lớn (thường 100 theo mặc định driver) nhân với số instance ứng dụng chạy song song trong kiến trúc container/Kubernetes có auto-scaling, khiến tổng connection thực tế vượt xa dự kiến ban đầu khi scale ngang.

**3. Thủ tục xử lý**
```javascript
// Bước 1: Kiểm tra số connection hiện tại
db.serverStatus().connections

// Bước 2: Xác định nguồn kết nối nhiều nhất
db.currentOp(true).inprog.length
// Hoặc dùng $currentOp aggregation để group theo client

// Bước 3: Tăng giới hạn connection tạm thời nếu server còn tài nguyên (mongod.conf)
// net.maxIncomingConnections: 51200

// Bước 4: Điều chỉnh pool size ở tầng driver ứng dụng cho hợp lý với số lượng
// instance thực tế (ví dụ nếu có 20 pod, mỗi pod chỉ nên dùng pool size 10-20,
// không phải mặc định 100)
```

**4. Bài học kinh nghiệm**
Trong kiến trúc container hóa với auto-scaling, cấu hình connection pool mặc định của driver database gần như luôn cần được điều chỉnh giảm — mặc định của driver được thiết kế cho mô hình triển khai truyền thống (số lượng instance ứng dụng cố định, ít), không phù hợp với auto-scaling hiện đại.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tính toán pool size theo công thức (tổng connection tối đa cho phép ÷ số instance ứng dụng tối đa khi scale hết cỡ), cấu hình tường minh thay vì dùng mặc định driver
- Với sharded cluster, cân nhắc dùng connection pooling tập trung ở tầng `mongos` một cách hợp lý, tránh để mỗi ứng dụng tự mở quá nhiều kết nối trực tiếp
- Giám sát số connection theo xu hướng khi auto-scaling kích hoạt, đảm bảo capacity database luôn được tính đến trong kế hoạch scale ứng dụng, không chỉ scale riêng tầng ứng dụng

---

## TỔNG KẾT — KẾT LUẬN

```
Phân tích xu hướng qua 20 case (4 engine khác nhau):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Cạn kiệt tài nguyên dùng chung (connection, TempDB, cache,
   disk cho log/binlog/oplog) do thiếu capacity planning     → 7/20 case
2. Cấu hình mặc định không phù hợp với production thực tế
   (autovacuum, oplog size, connection pool driver)          → 5/20 case
3. Thiếu giám sát chủ động các chỉ số "âm thầm tích lũy"
   (XID age, dead tuple, oplog window, cache pressure)       → 4/20 case
4. Vấn đề quy trình vận hành (quên resume, quên drop slot,
   thao tác trực tiếp trên replica/secondary)                → 3/20 case
5. Quyết định thiết kế khó đảo ngược (shard key, thứ tự
   truy cập bảng trong transaction)                          → 1/20 case
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nguyên tắc phòng ngừa cốt lõi rút ra (áp dụng chung cho cả 4 engine):
- Mọi tài nguyên "dùng chung" (connection pool, TempDB, WAL/binlog/oplog,
  cache) đều cần capacity planning riêng biệt và giám sát chủ động —
  đây là nguyên nhân gốc phổ biến nhất, vượt xa lỗi logic phần mềm
- Cấu hình mặc định của mọi engine đều được thiết kế cho khối lượng
  công việc "trung bình" — production thực tế luôn cần tinh chỉnh
  theo đặc thù workload cụ thể, không nên giữ nguyên mặc định
- Các chỉ số "tích lũy âm thầm" (transaction ID age, dead tuple,
  oplog window, replication slot lag) cần alert chủ động ở ngưỡng sớm
  (50-70%), không đợi đến ngưỡng khẩn cấp của chính engine mới phát hiện
- Ranh giới Primary/Secondary (Replica) phải được bảo vệ bằng cấu hình
  cứng (read_only, super_read_only) chứ không chỉ dựa vào quy ước
  vận hành hay connection string của ứng dụng
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

So sánh nhanh trọng tâm giám sát theo từng engine:
┌──────────────┬────────────────────────────────────────────┐
│ PostgreSQL   │ Connection pool, XID age, dead tuple, slot  │
│ SQL Server   │ TempDB, AlwaysOn sync state, blocking chain │
│ MySQL/MariaDB│ Replication lag/error, binlog size, deadlock│
│ MongoDB      │ Election/heartbeat, oplog window, cache     │
└──────────────┴────────────────────────────────────────────┘
```

---

## Tài liệu tham khảo
- PostgreSQL Official Documentation — Routine Vacuuming, Streaming Replication
- Microsoft SQL Server Documentation — AlwaysOn Availability Groups, TempDB
- MySQL 8.0 Reference Manual — Replication, InnoDB Recovery
- MongoDB Manual — Replication, Sharding, WiredTiger Storage Engine
- Percona Toolkit Documentation (pt-table-checksum, XtraBackup)
- www.tranvanbinh.vn — Khóa học Oracle & Multi-Database DBA A-Z Enterprise
