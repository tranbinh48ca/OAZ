---
name: oracle-troubleshoot-high-availability-dataguard-goldengate
description: >
  Case study khắc phục lỗi thường gặp trong vận hành High Availability:
  Oracle DataGuard (Physical/Logical Standby, Broker, Switchover, Failover,
  Redo Transport, Apply Lag) và Oracle GoldenGate (Extract, Pump, Replicat,
  Trail files, Bidirectional Replication). Mỗi case trình bày đầy đủ:
  Vấn đề/Mức độ ảnh hưởng, Nguyên nhân, Thủ tục xử lý, Bài học kinh nghiệm,
  Biện pháp phòng ngừa từ sớm/từ xa.
  Kích hoạt khi hỏi về: lỗi DataGuard thực chiến, sự cố GoldenGate,
  postmortem DataGuard, root cause analysis GoldenGate, OGG abend case study,
  switchover thất bại, failover mất dữ liệu, split brain DataGuard,
  data divergence GoldenGate, apply lag cao, extract lag cao,
  bài học kinh nghiệm vận hành HA Oracle, phòng ngừa sự cố Data Guard.
---

# SK07-CASE · Case Study: Sự cố thường gặp trong High Availability (DataGuard & GoldenGate)

**Phạm vi:** Oracle 19c/21c — Physical/Logical Standby, DataGuard Broker, Oracle GoldenGate 19c+
**Tác giả:** Trần Văn Bình — VietDBA (Hotline/Zalo: 0902 912 888 — www.tranvanbinh.vn)
**Số lượng case:** 20 case thực chiến, chia 5 nhóm

## KIẾN TRÚC TỔNG QUAN HA TROUBLESHOOTING

```
Oracle High Availability — DataGuard & GoldenGate Failure Domain Map
══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────┐  |
│  REDO TRANSPORT & APPLY LAYER (DataGuard Core)               │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Password/  │  │ FAL / Gap  │  │ MRP Apply  │  Group A      │  |
│  │ Auth Sync  │  │ Resolution │  │ Lag / I-O  │  (1-5)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  ROLE TRANSITION LAYER (Switchover / Failover)                │  |
│  ┌────────────┐  ┌────────────┐                              │  |
│  │ Switchover │  │ Failover / │  Group B                      │  |
│  │ Readiness  │  │ Split-Brain│  (6-9)                        │  |
│  └────────────┘  └────────────┘                              │  |
└────────┬───────────────┬──────────────────────────────────────┘  |
         │                │
         ▼                ▼
┌────────────────────────────────────────────────────────────┐  |
│  GOLDENGATE CAPTURE LAYER (Extract / Trail)                   │  |
│  ┌────────────┐  ┌────────────┐                              │  |
│  │ DDL/Schema │  │ Trail File │  Group C                      │  |
│  │ Metadata   │  │ / Archivelog│  (10-13)                     │  |
│  └────────────┘  └────────────┘                              │  |
└────────┬───────────────┬──────────────────────────────────────┘  |
         │                │
         ▼                ▼
┌────────────────────────────────────────────────────────────┐  |
│  GOLDENGATE APPLY LAYER (Replicat & Data Integrity)            │  |
│  ┌────────────┐  ┌────────────┐                              │  |
│  │ Conflict/  │  │ Throughput │  Group D                      │  |
│  │ Divergence │  │ / Charset  │  (14-17)                      │  |
│  └────────────┘  └────────────┘                              │  |
└────────┬───────────────┬──────────────────────────────────────┘  |
         │                │
         ▼                ▼
┌────────────────────────────────────────────────────────────┐  |
│  COMBINED ARCHITECTURE & OPERATIONS LAYER                     │  |
│  ┌──────────────────────────────┐  Group E                    │  |
│  │ DG+GG Coordination / DR Drill │  (18-20)                   │  |
│  └──────────────────────────────┘                             │  |
└────────────────────────────────────────────────────────────┘  |

Severity: 🔴 CRITICAL (mất dữ liệu/mất DR) | 🟡 DEGRADED (suy giảm) | 🟢 MINOR (cảnh báo)
══════════════════════════════════════════════════════════════════
```

---

## MỤC LỤC CHI TIẾT THEO NHÓM

**NHÓM A: DataGuard — Redo Transport & Apply (Case 1-5)**
- Case 1: 🔴 ORA-16191 — Redo transport client not logged on standby
- Case 2: 🔴 FAL[client] Error fetching gap sequence — không resolve được archive gap
- Case 3: 🟡 MRP0 process không tiến — apply lag tăng vô hạn dù transport bình thường
- Case 4: 🟡 ORA-01547 — datafile cần media recovery sau khi thêm tablespace/datafile
- Case 5: 🔴 ORA-16737 — Redo transport service error do network/firewall

**NHÓM B: DataGuard — Switchover & Failover (Case 6-9)**
- Case 6: 🟡 Switchover treo ở "SESSIONS ACTIVE" — không hoàn tất
- Case 7: 🔴 Failover mất dữ liệu ngoài dự kiến dù cấu hình MAX AVAILABILITY
- Case 8: 🔴 Split-brain sau failover thủ công — cả hai database cùng là Primary
- Case 9: 🟡 Reinstate database thất bại sau failover — Flashback Database chưa bật

**NHÓM C: GoldenGate — Extract (Case 10-13)**
- Case 10: 🔴 OGG-01519 — Error processing record sau khi Primary thay đổi DDL
- Case 11: 🟡 Extract ABEND do thiếu Supplemental Logging cho một bảng cụ thể
- Case 12: 🟡 Trail files đầy ổ đĩa do PURGEOLDEXTRACTS cấu hình sai
- Case 13: 🔴 Extract lag tăng cao do archive log bị xóa sớm hơn Extract cần

**NHÓM D: GoldenGate — Replicat & Data Integrity (Case 14-17)**
- Case 14: 🟡 Replicat ABEND — ORA-00001 duplicate key trong cấu hình bidirectional
- Case 15: 🔴 Data divergence không phát hiện suốt nhiều tuần
- Case 16: 🟡 Replicat đơn luồng không theo kịp throughput — lag tích lũy liên tục
- Case 17: 🔴 Character set mismatch gây lỗi dữ liệu âm thầm trong replication cross-platform

**NHÓM E: Kiến trúc kết hợp & Vận hành thực tế (Case 18-20)**
- Case 18: 🔴 GoldenGate Extract mất đồng bộ sau khi DataGuard Failover
- Case 19: 🟡 Supplemental Logging bị tắt sau switchover Data Guard
- Case 20: 🔴 DR test biến thành failover thật do thiếu guardrail môi trường

---

## NHÓM A: DATAGUARD — REDO TRANSPORT & APPLY (Case 1-5)

### Case 1: ORA-16191 — Redo transport client not logged on standby

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Primary liên tục ghi log `ORA-16191: Primary log shipping client not logged on standby`. Redo transport ngưng hoàn toàn, apply lag tăng dần không giới hạn — nếu Primary gặp sự cố trong lúc này, RPO thực tế = thời gian từ lúc lỗi xuất hiện, không phải 0 như thiết kế MAX AVAILABILITY.

**2. Nguyên nhân**
Password file (`orapwORCL`) trên Standby không đồng bộ với Primary — thường xảy ra sau khi DBA đổi password SYS trên Primary bằng `ALTER USER` thay vì `orapwd`, hoặc sau khi restore/refresh Standby từ backup cũ mà quên copy lại password file. RFS (Remote File Server) trên Standby xác thực bằng password file, không dùng OS authentication.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận nguyên nhân
sqlplus / as sysdba
SELECT status, error FROM v$archive_dest WHERE dest_id=2;

# Bước 2: Copy password file mới nhất từ Primary sang Standby
scp $ORACLE_HOME/dbs/orapwORCL oracle@standby-host:$ORACLE_HOME/dbs/orapwORCL_STB

# Bước 3: Restart MRP trên Standby và kiểm tra redo transport
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;

# Bước 4: Xác nhận archive log tiếp tục ship
SELECT sequence#, applied FROM v$archived_log ORDER BY sequence# DESC FETCH FIRST 5 ROWS ONLY;
```

**4. Bài học kinh nghiệm**
Thay đổi password SYS bằng `ALTER USER` sau đó không đồng bộ password file là một trong những nguyên nhân "ngớ ngẩn" nhưng phổ biến nhất gây gián đoạn DataGuard âm thầm — hệ thống vẫn "trông" bình thường (Primary vẫn chạy tốt) nên dễ bị bỏ sót cho đến khi cần failover thật.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa việc đổi password SYS/SYSTEM vào runbook bắt buộc kèm bước "sync password file to all standby"
- Cron job kiểm tra checksum/timestamp `orapwORCL` giữa Primary và tất cả Standby, alert nếu lệch
- Alert riêng cho `v$archive_dest.status != 'VALID'` chạy mỗi 5 phút, không chỉ dựa vào lag threshold (vì lag có thể tăng chậm và bị bỏ qua ở ngưỡng thấp)

---

### Case 2: FAL[client] Error fetching gap sequence — không resolve được archive gap

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Standby báo gap ở `v$archive_gap` nhưng FAL (Fetch Archive Log) không tự động lấy được archive log còn thiếu từ Primary. Standby ngừng tiến, protection thực tế = 0 cho đến khi gap được resolve thủ công.

**2. Nguyên nhân**
Archive log cần thiết đã bị xóa khỏi Primary trước khi Standby kịp nhận (thường do RMAN retention policy hoặc job dọn archivelog chạy quá sớm, không kiểm tra `applied=YES` trên tất cả standby destination trước khi xóa).

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác định range sequence bị thiếu
SELECT thread#, low_sequence#, high_sequence# FROM v$archive_gap;

-- Bước 2: Kiểm tra archive log còn tồn tại trên Primary không
SELECT sequence#, name FROM v$archived_log
WHERE sequence# BETWEEN &low AND &high AND thread#=&thread;
```
```bash
# Bước 3a: Nếu còn file — copy thủ công sang Standby và register
RMAN> CATALOG START WITH '/backup/arch/';
# Trên Standby:
ALTER DATABASE REGISTER LOGFILE '/standby_arch/arch_seq_xxx.arc';

# Bước 3b: Nếu file đã bị xóa — dùng RMAN incremental backup từ SCN để fill gap
RMAN TARGET / AUXILIARY sys/pass@STANDBY
BACKUP INCREMENTAL FROM SCN &standby_scn DATABASE FORMAT '/tmp/gap_%U';
# Transfer, catalog, và recover standby từ incremental backup này
```

**4. Bài học kinh nghiệm**
Retention policy cho archivelog trên Primary phải luôn kiểm tra điều kiện "đã apply trên TẤT CẢ standby đăng ký", không chỉ dựa vào số ngày giữ log. Trong kiến trúc nhiều standby (DR + reporting), một destination chậm có thể khiến job dọn log xóa nhầm dữ liệu cần cho destination khác.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Dùng RMAN `DELETE ARCHIVELOG ... APPLIED ON ALL STANDBY` thay vì xóa theo tuổi file
- Giám sát `v$archive_gap` chủ động (không đợi báo cáo từ người dùng) với alert ngay khi gap xuất hiện, trước khi nó lớn
- Duy trì FRA đủ lớn (tối thiểu 24-48h archive log) làm lớp đệm an toàn cho mọi standby

---

### Case 3: MRP0 process không tiến (apply lag tăng vô hạn dù transport bình thường)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED (có nguy cơ thành CRITICAL nếu kéo dài). Redo được ship đầy đủ (`transport lag` thấp) nhưng `apply lag` tăng liên tục — MRP0 nhận log nhưng apply rất chậm hoặc treo.

**2. Nguyên nhân**
Thường gặp nhất: storage I/O trên Standby chậm hơn Primary đáng kể (Standby dùng disk rẻ hơn hoặc bị tranh chấp I/O với workload khác), hoặc Standby đang phục vụ Active Data Guard với truy vấn nặng gây block trên buffer cache dùng chung với apply process.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận MRP đang chạy và tốc độ apply
SELECT process, status, sequence#, block#, blocks FROM v$managed_standby;

-- Bước 2: Kiểm tra I/O wait của MRP
SELECT event, total_waits, time_waited FROM v$system_event
WHERE event LIKE '%recovery%' OR event LIKE '%log file%';

-- Bước 3: Kiểm tra query đang chạy trên Active DG gây block
SELECT sid, sql_id, event, blocking_session FROM v$session
WHERE username IS NOT NULL AND wait_class != 'Idle';
```
```bash
# Bước 4: Nếu do I/O — tăng parallel recovery (tạm thời)
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  PARALLEL 8 USING CURRENT LOGFILE DISCONNECT;

# Bước 5: Nếu do storage tier lệch — escalate với storage team, kiểm tra IOPS/latency thực tế
```

**4. Bài học kinh nghiệm**
Nhiều team đầu tư kỹ cho Primary nhưng "tiết kiệm" hạ tầng cho Standby vì nghĩ nó "chỉ để dự phòng" — đây là sai lầm nghiêm trọng vì Standby phải apply redo với tốc độ TƯƠNG ĐƯƠNG hoặc nhanh hơn tốc độ sinh redo của Primary, nếu không lag sẽ tích lũy vô hạn theo thời gian.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Standby phải có cấu hình storage/CPU tối thiểu bằng 80-100% Primary, đặc biệt nếu dùng Active Data Guard cho reporting
- Benchmark redo generation rate của Primary lúc peak, đảm bảo Standby apply rate luôn > peak rate với biên an toàn
- Thiết lập Resource Manager trên Standby để giới hạn tài nguyên cho session Active DG, ưu tiên apply process

---

### Case 4: ORA-01547 — datafile cần media recovery sau khi thêm tablespace/datafile trên Primary

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Standby báo lỗi liên quan đến datafile không tìm thấy hoặc cần recovery sau khi Primary thực hiện `CREATE TABLESPACE` hoặc `ALTER TABLESPACE ADD DATAFILE` với đường dẫn không tồn tại tương ứng trên Standby.

**2. Nguyên nhân**
`DB_FILE_NAME_CONVERT` không được cấu hình hoặc cấu hình sai khi Primary/Standby có cấu trúc thư mục khác nhau (khác OS, khác mount point), khiến Standby không tự tạo được datafile tương ứng qua Standby File Management (`STANDBY_FILE_MANAGEMENT=AUTO`).

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra cấu hình standby file management
SHOW PARAMETER standby_file_management;
SHOW PARAMETER db_file_name_convert;

-- Bước 2: Nếu path khác nhau và convert không đúng — tạo thủ công
ALTER DATABASE CREATE DATAFILE '/u01/oradata/primary/new01.dbf'
  AS '/u02/oradata/standby/new01.dbf';

-- Bước 3: Đảm bảo MRP tiếp tục sau khi tạo datafile
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT;
```

**4. Bài học kinh nghiệm**
`STANDBY_FILE_MANAGEMENT=AUTO` không phải "vô điều kiện an toàn" — nó chỉ hoạt động đúng khi `DB_FILE_NAME_CONVERT` khớp chính xác cấu trúc thư mục thực tế. Trong môi trường Primary/Standby không đồng nhất path (rất phổ biến khi hai datacenter dùng chuẩn đặt tên khác nhau), mọi thay đổi cấu trúc file trên Primary đều là điểm rủi ro.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Chuẩn hóa path đặt datafile giống hệt nhau giữa Primary và Standby ngay từ khi thiết kế, tránh phụ thuộc vào `DB_FILE_NAME_CONVERT`
- Đưa "thêm tablespace/datafile" vào checklist thay đổi có review DBA cấp cao, không để tự động 100%
- Sau mọi thay đổi cấu trúc storage trên Primary, kiểm tra ngay `v$managed_standby` và alert log Standby trong 15 phút đầu

---

### Case 5: ORA-16737 — Redo transport service error do network/firewall

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL (nếu kéo dài) / 🟡 DEGRADED (nếu ngắt quãng). Kết nối redo transport giữa Primary và Standby bị gián đoạn không liên tục, gây gap lặp lại nhiều lần trong ngày.

**2. Nguyên nhân**
Thường do timeout của firewall/load balancer giữa hai datacenter đối với kết nối TCP kéo dài (long-lived connection) mà Data Guard sử dụng, hoặc thay đổi rule firewall không thông báo cho DBA team.

**3. Thủ tục xử lý**
```bash
# Bước 1: Test kết nối cơ bản
tnsping STANDBY_SERVICE

# Bước 2: Kiểm tra listener và lắng nghe log lỗi cụ thể
grep "TNS\|ORA-16737\|RFS" $ORACLE_HOME/network/log/listener.log | tail -50

# Bước 3: Test độ ổn định kết nối kéo dài (giả lập traffic Data Guard)
nc -zv standby-host 1521 && sleep 300 && nc -zv standby-host 1521
```
```sql
-- Bước 4: Tăng NET_TIMEOUT phù hợp với đặc tính mạng WAN
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB ASYNC NET_TIMEOUT=60 REOPEN=15
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)' SCOPE=BOTH;
```

**4. Bài học kinh nghiệm**
Sự cố mạng gây gián đoạn Data Guard hiếm khi được network team ưu tiên xử lý nếu DBA không cung cấp bằng chứng cụ thể (timestamp, port, error code) — cần phối hợp chặt giữa hai team và có SLA rõ ràng cho traffic Data Guard.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Yêu cầu network team loại trừ port Data Guard (1521 hoặc port riêng) khỏi mọi idle-timeout rule của firewall, hoặc cấu hình keepalive phù hợp
- Giám sát network riêng cho đường truyền Data Guard (latency, packet loss) độc lập với giám sát ứng dụng chung
- Review lại rule firewall mỗi khi có thay đổi hạ tầng mạng, đưa Data Guard vào danh sách dependency cần thông báo trước

---

## NHÓM B: DATAGUARD — SWITCHOVER & FAILOVER (Case 6-9)

### Case 6: Switchover treo ở "SESSIONS ACTIVE" — không hoàn tất

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. `SWITCHOVER TO` treo lâu hoặc báo lỗi timeout, Primary không chuyển được sang Standby, gây kéo dài downtime bảo trì đã lên lịch (maintenance window bị vượt).

**2. Nguyên nhân**
Có session đang active với transaction chưa commit, hoặc job/batch đang chạy trên Primary tại thời điểm switchover mà không được dừng trước, khiến Oracle chờ session tự kết thúc thay vì switchover ngay.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra trạng thái sẵn sàng trước khi switchover (luôn làm trước!)
SELECT switchover_status FROM v$database;
-- Nếu là 'SESSIONS ACTIVE' → có session cần xử lý

-- Bước 2: Xác định session đang block
SELECT sid, serial#, username, program, status FROM v$session
WHERE username IS NOT NULL AND status='ACTIVE';

-- Bước 3: Dùng WITH SESSION SHUTDOWN để tự động ngắt (chỉ khi đã thông báo user)
ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
```

**4. Bài học kinh nghiệm**
Switchover thành công về mặt kỹ thuật không có nghĩa là "an toàn cho ứng dụng" — cần luôn có bước dừng ứng dụng/job có kiểm soát trước switchover thay vì dựa vào `WITH SESSION SHUTDOWN` để "ép" hệ thống, vì cách này có thể cắt ngang transaction giữa chừng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Checklist switchover luôn bắt đầu bằng bước dừng application traffic (qua load balancer/service) và tắt scheduler job, không chỉ dựa vào lệnh database
- Test `VALIDATE DATABASE` và kiểm tra `switchover_status` định kỳ (không chỉ lúc cần switchover thật) để phát hiện sớm session/job có thói quen chạy dài
- Diễn tập switchover định kỳ (quarterly) trong maintenance window thực tế để phát hiện các vướng mắc vận hành, không chỉ test trên môi trường lab

---

### Case 7: Failover mất dữ liệu ngoài dự kiến dù cấu hình MAX AVAILABILITY

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Sau khi failover khẩn cấp, phát hiện một số transaction gần nhất bị mất dù protection mode là MAX AVAILABILITY (lẽ ra phải zero data loss khi kết nối SYNC còn hoạt động).

**2. Nguyên nhân**
Protection mode đã tự động "downgrade" từ SYNC sang ASYNC trước đó do redo transport SYNC không đáp ứng kịp (network chậm) mà không ai để ý cảnh báo — MAX AVAILABILITY tự chuyển sang cho phép mất dữ liệu để tránh treo Primary, đúng theo thiết kế, nhưng team vận hành không biết trạng thái đã downgrade tại thời điểm sự cố.

**3. Thủ tục xử lý**
```sql
-- Sau sự cố — xác nhận nguyên nhân qua alert log Primary
-- Tìm dòng: "Primary database is unsynchronized" hoặc chuyển "SYNC" -> "resynchronization"

-- Kiểm tra protection level thực tế tại thời điểm failover (không phải protection MODE cấu hình)
SELECT protection_mode, protection_level FROM v$database;
-- Nếu 2 giá trị khác nhau tại lịch sử → đã có thời điểm downgrade

-- Xác định các transaction bị mất qua LogMiner trên archive log cuối của Primary cũ (nếu còn truy cập được)
```

**4. Bài học kinh nghiệm**
`protection_mode` (cấu hình) và `protection_level` (trạng thái thực tế) là hai khái niệm khác nhau — nhiều DBA chỉ kiểm tra mode lúc setup ban đầu mà không giám sát level liên tục, dẫn đến hiểu nhầm nghiêm trọng về RPO thực tế khi cần nhất.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Alert riêng và có mức độ nghiêm trọng cao khi `protection_level` khác `protection_mode` (báo hiệu đang chạy ở chế độ suy giảm)
- Với hệ thống yêu cầu zero data loss thực sự, cân nhắc MAX PROTECTION (chấp nhận Primary dừng nếu mất kết nối Standby) thay vì MAX AVAILABILITY nếu SLA không chấp nhận mất dữ liệu trong mọi tình huống
- Đưa network SYNC latency vào giám sát liên tục — cảnh báo sớm khi latency tiệm cận ngưỡng gây downgrade tự động

---

### Case 8: Split-brain sau failover thủ công — cả hai database cùng là Primary

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL nghiêm trọng nhất trong nhóm HA. Sau failover thủ công (không dùng Broker), Primary cũ được khởi động lại bởi người khác trong team mà không biết đã có failover, dẫn đến hai database cùng nhận ghi độc lập — dữ liệu phân kỳ (diverge) không thể merge tự động.

**2. Nguyên nhân**
Thiếu quy trình cô lập (fencing) Primary cũ ngay sau failover — không tắt listener/network access, không có cơ chế broadcast trạng thái failover cho toàn team vận hành, dẫn đến thao tác khởi động lại Primary cũ trong lúc đang xử lý sự cố.

**3. Thủ tục xử lý**
```bash
# Bước 1: Ngay khi phát hiện — cô lập một trong hai database ngay lập tức
# Trên database sai (không được chọn làm primary chính thức):
sqlplus / as sysdba
SHUTDOWN ABORT;
# Chặn network access ở tầng firewall/listener để tránh client kết nối nhầm

# Bước 2: Đánh giá phạm vi phân kỳ dữ liệu
# Dùng LogMiner so sánh SCN và transaction giữa hai nhánh kể từ thời điểm failover

# Bước 3: Xác định database "đúng" (thường là database có transaction từ ứng dụng
# chính thức, database kia dùng làm nguồn tham chiếu để trích xuất dữ liệu bị lệch)

# Bước 4: Rebuild database sai thành standby mới hoàn toàn (KHÔNG cố gắng merge)
RMAN> DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE;
```

**4. Bài học kinh nghiệm**
Split-brain gần như luôn là hậu quả của quy trình vận hành (con người, giao tiếp), không phải lỗi kỹ thuật của Oracle — Oracle Data Guard Broker với Fast-Start Failover đã có cơ chế fencing tự động chính xác cho tình huống này, nhưng nhiều tổ chức vẫn thao tác thủ công vì chưa tin tưởng automation.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Ưu tiên dùng DataGuard Broker + Observer thay vì failover thủ công, để Oracle tự động fencing Primary cũ
- Nếu bắt buộc thao tác thủ công: quy trình phải có bước SHUTDOWN/khóa network truy cập Primary cũ NGAY LẬP TỨC là bước đầu tiên, trước khi thực hiện failover trên Standby
- Có kênh thông báo real-time (Slack/PagerDuty) bắt buộc mọi thành viên DBA xác nhận đã đọc trước khi bất kỳ ai thao tác lên hệ thống trong sự cố

---

### Case 9: Reinstate database thất bại sau failover — Flashback Database chưa bật

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Sau khi Primary cũ phục hồi, `DGMGRL> REINSTATE DATABASE` báo lỗi không thể tự động chuyển thành Standby mới, buộc phải rebuild toàn bộ từ đầu — kéo dài thời gian khôi phục redundancy (không có DR trong thời gian này).

**2. Nguyên nhân**
Flashback Database không được bật trên Primary cũ, nên Oracle không thể "quay ngược" các transaction đã xảy ra sau điểm phân kỳ để biến nó thành Standby hợp lệ một cách tự động — đây là điều kiện bắt buộc để REINSTATE hoạt động.

**3. Thủ tục xử lý**
```sql
-- Kiểm tra Flashback status (làm NGAY sau sự cố để biết có REINSTATE được không)
SELECT flashback_on FROM v$database;

-- Nếu flashback_on = NO -> không thể REINSTATE, phải rebuild
RMAN TARGET / AUXILIARY sys/pass@NEW_STANDBY
DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE
  SPFILE
  SET DB_UNIQUE_NAME='ORCL_STB'
  NOFILENAMECHECK;
```

**4. Bài học kinh nghiệm**
Flashback Database thường bị xem là tính năng "tùy chọn" khi setup ban đầu, nhưng thực chất là điều kiện tiên quyết để failover/reinstate nhanh chóng — thiếu nó biến một sự cố "vài chục phút" thành "vài giờ" rebuild toàn bộ standby.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bật `FLASHBACK DATABASE` mặc định trên CẢ Primary và Standby ngay từ khi triển khai Data Guard, không xem là optional
- Đảm bảo FRA đủ lớn để chứa flashback logs với retention tối thiểu bằng thời gian phát hiện + xử lý sự cố dự kiến (thường 24h)
- Đưa `flashback_on` vào checklist health check định kỳ, không chỉ kiểm tra khi có sự cố

---

## NHÓM C: GOLDENGATE — EXTRACT (Case 10-13)

### Case 10: OGG-01519 — Error processing record sau khi Primary thay đổi DDL

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Extract ABEND ngay lập tức, toàn bộ luồng đồng bộ dừng, dữ liệu target bắt đầu lệch so với source kể từ thời điểm này.

**2. Nguyên nhân**
Có `ALTER TABLE` (thêm/xóa/đổi kiểu cột) trên bảng đang được GoldenGate replicate mà không thông báo trước cho team GoldenGate — Extract đọc redo log gặp cấu trúc cột không khớp với metadata đã cache.

**3. Thủ tục xử lý**
```bash
# Bước 1: Dừng Extract, xem report để xác nhận nguyên nhân
GGSCI> STOP EXTRACT ext1
GGSCI> VIEW REPORT ext1

# Bước 2: Cho Extract đọc lại metadata mới từ thời điểm hiện tại
GGSCI> DBLOGIN USERID ggadmin PASSWORD pass
GGSCI> ALTER EXTRACT ext1, TRANLOG, BEGIN NOW
GGSCI> START EXTRACT ext1

# Bước 3: Nếu có dữ liệu giữa thời điểm DDL và lúc restart bị bỏ sót
# -> cần đối chiếu dữ liệu (reconciliation) cho khoảng thời gian đó
```

**4. Bài học kinh nghiệm**
GoldenGate không tự động "học" DDL trừ khi được cấu hình DDL replication rõ ràng — mọi thay đổi schema trên bảng nguồn đều là rủi ro tiềm tàng nếu team ứng dụng/DBA không có quy trình phối hợp với team đồng bộ dữ liệu.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bật DDL replication support trong GoldenGate nếu nghiệp vụ cho phép, hoặc bắt buộc quy trình change management: mọi DDL trên bảng có GoldenGate phải thông báo trước cho DBA GoldenGate
- Với bảng quan trọng, thiết lập trigger/audit cảnh báo khi có DDL xảy ra ngoài kế hoạch
- Định kỳ đối chiếu (reconciliation) tự động số lượng bản ghi/checksum giữa source-target để phát hiện sớm lệch dữ liệu, không đợi ABEND mới biết

---

### Case 11: Extract ABEND do thiếu Supplemental Logging cho một bảng cụ thể

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED → có thể thành 🔴 nếu không phát hiện sớm. Replicat trên target báo lỗi thiếu giá trị key khi update, do trail file không chứa đủ thông tin before-image cần thiết.

**2. Nguyên nhân**
Supplemental logging được bật ở mức database (`ALTER DATABASE ADD SUPPLEMENTAL LOG DATA`) nhưng bảng cụ thể có primary key phức hợp hoặc không có primary key, cần cấu hình supplemental logging riêng theo bảng (`ADD TRANDATA`) mà bước này bị bỏ sót khi thêm bảng mới vào cấu hình replicate.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái supplemental logging của bảng
GGSCI> DBLOGIN USERID ggadmin PASSWORD pass
GGSCI> INFO TRANDATA SCOTT.ORDERS

# Bước 2: Bật lại đầy đủ cho bảng này
GGSCI> ADD TRANDATA SCOTT.ORDERS, COLS (order_id, cust_id)

# Bước 3: Restart Extract từ thời điểm hiện tại (dữ liệu cũ thiếu log cần initial load lại phần này)
GGSCI> ALTER EXTRACT ext1, TRANLOG, BEGIN NOW
GGSCI> START EXTRACT ext1
```

**4. Bài học kinh nghiệm**
Việc thêm một bảng mới vào cấu hình GoldenGate không chỉ là thêm dòng `TABLE` trong parameter file — cần một checklist đầy đủ bao gồm supplemental logging riêng theo bảng, đặc biệt với bảng không có primary key rõ ràng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Chuẩn hóa checklist "thêm bảng vào GoldenGate" thành script/quy trình bắt buộc gồm: kiểm tra PK, ADD TRANDATA, verify bằng INFO TRANDATA trước khi thêm vào MAP
- Ưu tiên yêu cầu mọi bảng nghiệp vụ quan trọng có primary key rõ ràng ngay từ thiết kế database, giảm rủi ro vận hành GoldenGate về sau
- Test bằng DML thực tế (insert/update/delete) trên môi trường staging ngay sau khi thêm bảng, trước khi go-live trên production

---

### Case 12: Trail files đầy ổ đĩa do PURGEOLDEXTRACTS cấu hình sai

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, có thể leo thang 🔴 nếu disk đầy hoàn toàn (Extract/Replicat sẽ dừng khi không còn dung lượng ghi). Trail files tích lũy không được dọn, disk usage tăng liên tục.

**2. Nguyên nhân**
Tham số `PURGEOLDEXTRACTS` trong Manager parameter file cấu hình điều kiện giữ file quá dài (ví dụ `USECHECKPOINTS` kết hợp với Replicat bị lag lâu ngày), hoặc trỏ sai path không khớp với đường dẫn Extract thực tế đang ghi.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra dung lượng và số lượng trail file
df -h /u01/ogg/dirdat
ls -la /u01/ogg/dirdat | wc -l

# Bước 2: Kiểm tra checkpoint hiện tại của Replicat (nguyên nhân giữ file cũ)
GGSCI> INFO REPLICAT rep1, SHOWCH

# Bước 3: Nếu Replicat đang lag rất xa — ưu tiên xử lý lag trước (xem Case 15),
# không xóa trail file thủ công vì có thể làm mất dữ liệu chưa apply

# Bước 4: Sửa cấu hình Manager cho đúng
GGSCI> EDIT PARAMS MGR
```
```
PORT 7809
PURGEOLDEXTRACTS ./dirdat/*, USECHECKPOINTS, MINKEEPHOURS 24
```

**4. Bài học kinh nghiệm**
`PURGEOLDEXTRACTS` với `USECHECKPOINTS` là cơ chế an toàn (không xóa file Replicat chưa đọc tới) nhưng đồng thời là "cảnh báo sớm" bị bỏ lỡ — dung lượng đầy đĩa thường là triệu chứng của Replicat lag nghiêm trọng ở phía sau, không phải vấn đề gốc.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát dung lượng `dirdat` như một chỉ số sức khỏe GoldenGate, không chỉ giám sát disk chung của server
- Alert riêng khi số lượng trail file chưa được Replicat đọc vượt ngưỡng (ví dụ >100 file), độc lập với alert disk usage
- Capacity planning: tính toán dung lượng `dirdat` cần thiết dựa trên throughput đỉnh × thời gian retention mong muốn, không để mặc định

---

### Case 13: Extract lag tăng cao do archive log bị xóa sớm hơn Extract cần

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Extract ABEND với lỗi không tìm thấy archive log cần thiết — đây là lỗi nghiêm trọng vì GoldenGate cần initial load lại hoàn toàn (không như Data Guard có thể fill gap từ incremental backup).

**2. Nguyên nhân**
RMAN retention policy hoặc job dọn archivelog trên Primary chỉ kiểm tra điều kiện "đã ship tới Standby" (Data Guard) mà không kiểm tra điều kiện "Extract GoldenGate đã đọc tới" — khi Extract bị dừng lâu (bảo trì, sự cố) hoặc chạy chậm, archive log cần thiết đã bị xóa trước khi Extract kịp đọc.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận archive log đã bị xóa vĩnh viễn
GGSCI> VIEW REPORT ext1
# Tìm dòng báo thiếu archive log sequence cụ thể

# Bước 2: Nếu archive log không còn (kể cả trong backup) -> phải initial load lại
# Đây là kịch bản tốn thời gian nhất, cần lên kế hoạch downtime/impact rõ ràng

GGSCI> STOP EXTRACT ext1
# Thực hiện Data Pump export/import hoặc RMAN transportable tablespace cho initial load
GGSCI> ALTER EXTRACT ext1, TRANLOG, BEGIN NOW
GGSCI> START EXTRACT ext1
# Đồng thời phải START REPLICAT với vị trí tương ứng sau khi initial load hoàn tất
```

**4. Bài học kinh nghiệm**
Đây là lỗi tốn kém nhất trong toàn bộ case study này vì không có cách "vá" nhanh — bắt buộc phải làm lại initial load. Nguyên nhân gốc luôn là thiếu phối hợp giữa policy quản lý archivelog (thường do team backup/DBA hạ tầng quản lý) và yêu cầu retention thực tế của GoldenGate (do team dữ liệu/tích hợp quản lý).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc mọi script/RMAN policy xóa archivelog phải kiểm tra thêm điều kiện GoldenGate: dùng `GGSCI> SEND EXTRACT ext1, GETLAG` hoặc theo dõi giá trị "Recovery checkpoint" của Extract trước khi cho phép xóa log tương ứng
- Alert riêng cho Extract lag vượt ngưỡng nghiêm trọng (ví dụ > 2 giờ) với mức độ cảnh báo cao nhất, vì lag Extract lớn đồng nghĩa nguy cơ mất archive log cần thiết tăng theo thời gian
- Duy trì FRA/archive log retention tối thiểu đủ lớn để bù đắp cho thời gian downtime bảo trì GoldenGate theo kế hoạch dài nhất có thể xảy ra

---

## NHÓM D: GOLDENGATE — REPLICAT & DATA INTEGRITY (Case 14-17)

### Case 14: Replicat ABEND — ORA-00001 duplicate key trong cấu hình bidirectional

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED (nếu discard đúng) → 🔴 CRITICAL (nếu bị bỏ qua âm thầm, gây mất bản ghi). Replicat dừng lại vì cố insert một bản ghi đã tồn tại ở target.

**2. Nguyên nhân**
Trong cấu hình bidirectional replication (Active-Active), thiếu cơ chế loop prevention khiến một transaction được replicate lại về chính nơi nó xuất phát, hoặc do sự kiện resync/initial load chạy song song với luồng CDC đang hoạt động, gây trùng dữ liệu.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xem report xác định SQL/row cụ thể gây lỗi
GGSCI> VIEW REPORT rep1

# Bước 2: Xác nhận đây là do loop hay do resync trùng lặp
# Kiểm tra cột metadata (nếu có dùng CDR - Conflict Detection and Resolution)

# Bước 3: Với duplicate key hợp lệ (do resync) — xử lý có kiểm soát, KHÔNG dùng
# REPERROR DISCARD vô điều kiện vì có thể che giấu lỗi loop thực sự
GGSCI> EDIT PARAMS rep1
```
```
REPERROR (ORA-00001, EXCEPTION)
-- Route lỗi vào bảng exception để review thủ công, thay vì âm thầm bỏ qua
```

**4. Bài học kinh nghiệm**
`REPERROR (DEFAULT, DISCARD)` là con dao hai lưỡi — dễ dùng để "cho chạy tiếp" nhưng nếu áp dụng cho lỗi duplicate key mà không phân tích nguyên nhân gốc, có thể đang âm thầm bỏ qua vấn đề loop replication nghiêm trọng khiến dữ liệu tại một trong hai site bị sai lệch vĩnh viễn.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Với Active-Active, luôn cấu hình Conflict Detection and Resolution (CDR) đúng chuẩn Oracle thay vì dựa vào DISCARD thô
- Không bao giờ dùng `REPERROR (DEFAULT, DISCARD)` cho môi trường production mà không có bảng exception log kèm quy trình review định kỳ
- Kiểm thử kỹ luồng loop prevention (dùng `EXCLUDETRANSFROMSOURCE` hoặc tương đương) trong môi trường staging trước khi triển khai bidirectional trên production

---

### Case 15: Data divergence không phát hiện suốt nhiều tuần

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. GoldenGate báo trạng thái "chạy bình thường" (không ABEND, lag thấp) nhưng khi audit định kỳ phát hiện hàng nghìn bản ghi bị lệch giữa source và target — do trước đó có một số bản ghi bị DISCARD âm thầm mà không ai theo dõi discard file.

**2. Nguyên nhân**
Không có quy trình đối chiếu (reconciliation) dữ liệu định kỳ; discard file được cấu hình để ghi log lỗi nhưng không có ai giám sát nội dung file này — "không có lỗi ABEND" bị hiểu nhầm là "dữ liệu chính xác 100%".

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra discard file để xác định phạm vi và thời điểm lệch bắt đầu
cat /u01/ogg/dirrpt/rep1.dsc | grep -c "DISCARDED"

# Bước 2: Chạy đối chiếu dữ liệu để xác định chính xác phạm vi ảnh hưởng
# (Sử dụng Oracle GoldenGate Veridata, hoặc script so sánh checksum/count theo từng bảng)

# Bước 3: Với các bản ghi lệch — export dữ liệu đúng từ source, đồng bộ thủ công có kiểm soát
# vào target, kèm log đầy đủ để audit
```

**4. Bài học kinh nghiệm**
"Không có lỗi" trong log GoldenGate không đồng nghĩa "dữ liệu đồng bộ chính xác" — DISCARD là cơ chế "chạy tiếp bằng mọi giá" chứ không phải "báo cáo mọi vấn đề rõ ràng". Đây là bài học đắt giá nhất: cần một tầng giám sát độc lập với chính GoldenGate để xác nhận tính đúng đắn dữ liệu.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết lập job reconciliation tự động (checksum/row count theo bảng, theo khoảng thời gian) chạy định kỳ hàng ngày, độc lập hoàn toàn với trạng thái process GoldenGate
- Alert real-time khi có bản ghi mới xuất hiện trong discard file, không đợi review thủ công định kỳ
- Với dữ liệu tài chính/nghiệp vụ quan trọng, cân nhắc dùng Oracle GoldenGate Veridata hoặc công cụ đối chiếu chuyên dụng thay vì kiểm tra thủ công

---

### Case 16: Replicat đơn luồng không theo kịp throughput — lag tích lũy liên tục

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, ảnh hưởng trực tiếp đến RPO thực tế của kiến trúc dùng GoldenGate cho DR/reporting — dữ liệu trên target luôn "chậm hơn" source một khoảng ngày càng lớn.

**2. Nguyên nhân**
Classic Replicat đơn luồng không đủ throughput khi khối lượng giao dịch nguồn tăng trưởng theo thời gian (do business tăng trưởng) mà cấu hình Replicat chưa được nâng cấp tương ứng — vẫn dùng kiến trúc cũ từ lúc go-live ban đầu.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận lag hiện tại và xu hướng tăng
GGSCI> SEND REPLICAT rep1, GETLAG

# Bước 2: Chuyển sang Coordinated Replicat hoặc Parallel Replicat (19c+, khuyến dùng nhất)
GGSCI> STOP REPLICAT rep1
GGSCI> DELETE REPLICAT rep1

GGSCI> ADD REPLICAT rep1, PARALLEL, EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS rep1
```
```
REPLICAT rep1
USERID ggadmin, PASSWORD pass
MAXTHREADS 8
BATCHSQL BATCHESPERQUEUE 50 BATCHTRANSOPS 1000
MAP SCOTT.*, TARGET SCOTT.*;
```

**4. Bài học kinh nghiệm**
Kiến trúc GoldenGate cần được review định kỳ theo tăng trưởng khối lượng giao dịch của nghiệp vụ, không phải cấu hình "một lần rồi thôi" — throughput đủ dùng lúc go-live không đảm bảo đủ dùng sau 1-2 năm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Theo dõi xu hướng (trend) apply lag theo thời gian, không chỉ giá trị tức thời — lag tăng dần đều là tín hiệu sớm cần nâng cấp kiến trúc trước khi thành vấn đề nghiêm trọng
- Capacity review định kỳ hàng năm cho cấu hình GoldenGate, đối chiếu với tăng trưởng giao dịch thực tế của ứng dụng
- Ưu tiên thiết kế Parallel Replicat ngay từ đầu cho hệ thống có khối lượng giao dịch lớn hoặc dự kiến tăng trưởng nhanh, thay vì đợi có vấn đề mới nâng cấp

---

### Case 17: Character set mismatch gây lỗi dữ liệu âm thầm trong replication cross-platform

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL nhưng khó phát hiện. Dữ liệu tiếng Việt có dấu (hoặc ký tự đặc biệt khác) bị hiển thị sai (lỗi font/mojibake) trên target sau khi replicate từ Oracle (source dùng AL32UTF8) sang một hệ quản trị khác có character set không tương thích hoàn toàn.

**2. Nguyên nhân**
Không kiểm tra kỹ tương thích character set giữa source và target trước khi thiết lập replication cross-platform; GoldenGate không tự động cảnh báo lỗi này vì về mặt kỹ thuật dữ liệu vẫn "được ghi" thành công, chỉ sai về mặt hiển thị/encoding.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận character set thực tế của source và target
SELECT parameter, value FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';

-- Bước 2: Kiểm tra dữ liệu mẫu bị lỗi để xác định phạm vi ảnh hưởng
-- (thường phát hiện qua báo cáo người dùng cuối, không phải qua log kỹ thuật)
```
```
-- Bước 3: Cấu hình lại Replicat với chuyển đổi character set rõ ràng
REPLICAT rep1
SOURCEDB dsn=source_alias
TARGETDB dsn=target_alias
SETENV (NLS_LANG="AMERICAN_AMERICA.AL32UTF8")
```

**4. Bài học kinh nghiệm**
Đây là loại lỗi nguy hiểm nhất — âm thầm, không có error log, chỉ phát hiện qua khiếu nại người dùng cuối, và có thể đã tích lũy hàng tháng dữ liệu sai trước khi được phát hiện, khiến việc khắc phục ngược (backfill) cực kỳ phức tạp.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc kiểm tra và test kỹ character set tương thích với dữ liệu thực tế (bao gồm tiếng Việt có dấu) trong giai đoạn thiết kế/PoC, trước khi go-live bất kỳ replication cross-platform nào
- Test case chuyên biệt với dữ liệu chứa ký tự đặc biệt, ký tự tiếng Việt, emoji nếu có, như một phần bắt buộc của UAT
- Giám sát định kỳ bằng cách lấy mẫu dữ liệu văn bản từ target và so sánh trực quan với source, không chỉ tin vào việc "không có lỗi kỹ thuật"

---

## NHÓM E: KIẾN TRÚC KẾT HỢP & VẬN HÀNH THỰC TẾ (Case 18-20)

### Case 18: GoldenGate Extract mất đồng bộ sau khi DataGuard Failover

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Sau khi Data Guard failover thành công (Standby cũ trở thành Primary mới), GoldenGate Extract vẫn cấu hình trỏ tới Primary cũ (giờ đã down hoặc đã thành standby) — luồng đồng bộ tới hệ thống reporting/downstream ngừng hoàn toàn dù Database chính đã hoạt động bình thường.

**2. Nguyên nhân**
Thiếu quy trình phối hợp giữa runbook Data Guard failover và runbook GoldenGate — hai đội vận hành khác nhau (đội HA database và đội tích hợp dữ liệu) không có bước bàn giao rõ ràng khi failover xảy ra.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận Primary mới
sqlplus / as sysdba
SELECT database_role FROM v$database;

# Bước 2: Restart GoldenGate Extract trỏ tới Primary mới
GGSCI> DBLOGIN USERID ggadmin@NEW_PRIMARY PASSWORD pass
GGSCI> ALTER EXTRACT ext_reporting, ETROLLOVER
GGSCI> START EXTRACT ext_reporting

# Bước 3: Kiểm tra lại toàn bộ chain Extract -> Pump -> Replicat hoạt động bình thường
GGSCI> INFO ALL
```

**4. Bài học kinh nghiệm**
Trong kiến trúc kết hợp Data Guard + GoldenGate, "failover thành công" ở góc độ database không đồng nghĩa "hệ thống HA hoàn chỉnh thành công" — cần xem toàn bộ chuỗi phụ thuộc (downstream systems) như một phần không thể tách rời của quy trình failover.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Runbook failover Data Guard PHẢI bao gồm bước rõ ràng "restart/reconfigure GoldenGate Extract" như một bước bắt buộc, không phải việc riêng của đội khác tự nhớ làm
- Dùng script tự động hóa (như combined_failover.sh) kết hợp cả hai bước DG failover và GG restart trong một quy trình duy nhất, giảm phụ thuộc vào con người nhớ đúng thứ tự
- Diễn tập kết hợp (không chỉ diễn tập riêng Data Guard) để đảm bảo toàn bộ chain HA hoạt động đúng khi test thực tế

---

### Case 19: Supplemental Logging bị tắt sau switchover Data Guard

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED → 🔴 nếu không phát hiện kịp. Sau switchover kế hoạch (Standby trở thành Primary mới), GoldenGate Extract trên Primary mới bắt đầu báo lỗi thiếu before-image dù trước switchover mọi thứ hoạt động bình thường.

**2. Nguyên nhân**
Supplemental logging là thuộc tính ở cấp database nhưng một số cấu hình (đặc biệt khi dùng `ENABLE_GOLDENGATE_REPLICATION` không đồng bộ giữa hai node, hoặc do khác biệt cấu hình `SCOPE=BOTH` vs `SCOPE=SPFILE` khi set tham số) khiến Primary mới sau switchover không kế thừa đúng cấu hình supplemental logging như Primary cũ.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Kiểm tra ngay sau switchover trên Primary mới
SELECT supplemental_log_data_min, supplemental_log_data_all FROM v$database;
SHOW PARAMETER enable_goldengate_replication;

-- Bước 2: Bật lại nếu thiếu
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SET enable_goldengate_replication=TRUE SCOPE=BOTH;

-- Bước 3: Restart Extract để áp dụng
```

**4. Bài học kinh nghiệm**
Mọi tham số quan trọng cho GoldenGate cần được xác minh là "đối xứng" (identical) giữa Primary và Standby, không chỉ dựa vào giả định rằng Data Guard tự động đồng bộ mọi cấu hình mức database.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Checklist switchover Data Guard trong môi trường có GoldenGate phải có bước xác minh riêng: supplemental logging, `enable_goldengate_replication`, và trạng thái Extract ngay sau khi switchover hoàn tất
- Kiểm tra định kỳ (không chỉ lúc switchover) rằng cấu hình liên quan GoldenGate đồng nhất giữa Primary và Standby, phát hiện sớm lệch cấu hình
- Đưa việc verify GoldenGate vào post-switchover validation script tự động, chạy ngay sau mọi switchover kế hoạch

---

### Case 20: DR test biến thành failover thật do thiếu guardrail môi trường

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL — sự cố vận hành nghiêm trọng nhất về mặt quy trình con người. Trong một buổi diễn tập DR (Disaster Recovery test), kỹ sư thực hiện nhầm lệnh `FAILOVER` thay vì lệnh test snapshot standby trên đúng môi trường production, gây gián đoạn dịch vụ thật ngoài kế hoạch.

**2. Nguyên nhân**
Môi trường production và môi trường test/DR-drill không có cơ chế phân biệt rõ ràng ở tầng công cụ (cùng dùng chung DGMGRL session, cùng naming convention dễ nhầm lẫn), kết hợp với áp lực thời gian trong buổi diễn tập khiến thao tác vội vàng, thiếu bước xác nhận (confirmation) trước lệnh nguy hiểm.

**3. Thủ tục xử lý**
```bash
# Xử lý khắc phục ngay sau sự cố — coi như một failover thật đã xảy ra
# Áp dụng lại quy trình Case 8/9: cô lập Primary cũ, đánh giá phân kỳ dữ liệu,
# thực hiện reinstate hoặc rebuild theo tình huống thực tế

# Đồng thời — điều quan trọng nhất là tổ chức Blameless Postmortem ngay sau đó
# để phân tích nguyên nhân quy trình, không quy trách nhiệm cá nhân
```

**4. Bài học kinh nghiệm**
Sự cố HA nghiêm trọng nhất thường không đến từ lỗi kỹ thuật của Oracle mà từ khoảng trống trong quy trình vận hành — thiếu guardrail phân biệt môi trường, thiếu bước xác nhận hai lớp cho lệnh nguy hiểm, và áp lực thời gian trong lúc thao tác. Đây cũng là lý do vì sao mọi case trong tài liệu này đều nhấn mạnh "Biện pháp phòng ngừa" ngang bằng với "Thủ tục xử lý" — phòng ngừa quy trình quan trọng không kém khắc phục kỹ thuật.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tách biệt hoàn toàn công cụ/session/credential giữa môi trường production và môi trường DR-drill, không bao giờ dùng chung một cửa sổ terminal cho cả hai
- Với các lệnh nguy hiểm (FAILOVER, SWITCHOVER, SHUTDOWN ABORT trên production), bắt buộc cơ chế xác nhận hai người (four-eyes principle) hoặc double-confirmation trong script
- Văn hóa Blameless Postmortem sau mọi sự cố vận hành để khuyến khích báo cáo trung thực và cải tiến hệ thống/quy trình thay vì che giấu lỗi vì sợ trách nhiệm cá nhân
- Diễn tập DR định kỳ nên dùng standby riêng (clone/snapshot) tách biệt hoàn toàn khỏi cấu hình production thật, không thao tác trực tiếp trên hệ thống DR đang bảo vệ production

---

## TỔNG KẾT — KẾT LUẬN

```
Phân tích xu hướng qua 20 case:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Lệch cấu hình Primary/Standby (password file, supplemental logging,
   tham số không đồng bộ)                          → 6/20 case
2. Thiếu giám sát chủ động, chỉ phát hiện qua báo cáo
   người dùng hoặc audit định kỳ                    → 5/20 case
3. Thiếu phối hợp quy trình giữa các team
   (network, backup, ứng dụng, GoldenGate, DataGuard) → 5/20 case
4. Capacity/throughput không được review theo tăng trưởng → 2/20 case
5. Lỗi quy trình con người (thao tác nhầm, thiếu guardrail) → 2/20 case
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nguyên tắc phòng ngừa cốt lõi rút ra:
- "Không có lỗi" ≠ "Đang chạy đúng" — cần giám sát chủ động độc lập
  với chính hệ thống đang giám sát (reconciliation, alert riêng)
- Mọi thay đổi hạ tầng (network, storage, DDL, password) đều là
  điểm rủi ro tiềm tàng cho HA — cần checklist bắt buộc, không dựa
  vào trí nhớ cá nhân
- Diễn tập định kỳ (switchover, failover, DR test) trong điều kiện
  gần giống thật nhất có thể là cách phát hiện lỗ hổng quy trình
  hiệu quả nhất, quan trọng không kém việc vá lỗi kỹ thuật
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Tài liệu tham khảo
- Oracle Data Guard Concepts and Administration 19c
- Oracle Data Guard Broker Guide 19c
- Oracle GoldenGate Administration Guide 19c
- Oracle GoldenGate Troubleshooting Guide
- MOS Note 1265700.1 — DataGuard Best Practices
- MOS Note 836986.1 — DataGuard Gap Resolution
- MOS Note 1581345.1 — DataGuard Switchover Best Practices
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
