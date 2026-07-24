---
name: oracle-troubleshoot-rac
description: >
  Case study khắc phục lỗi Oracle RAC (Real Application Clusters):
  Architecture, Grid Infrastructure, ASM, Services, TAF/FCF, Backup,
  Performance, Rolling Patch, Add/Remove Node, Troubleshooting.
  Kích hoạt khi hỏi về: RAC node eviction, CSS timeout, split brain RAC,
  CRS-xxxxx error, voting disk error, OCR corrupt, interconnect issue RAC,
  Cache Fusion problem, gc buffer busy, RAC service failover error,
  SCAN listener error, ASM diskgroup RAC error, RAC rolling patch failed,
  addNode.sh error, RAC instance crash, RAC performance degradation,
  ORA-29740 RAC, PRCR error, RAC cluster down, GRID infrastructure crash.
---

# SK10-CASE-06 · Troubleshooting: Oracle RAC

**Phạm vi:** Architecture/Grid Infrastructure, ASM, Services/TAF/FCF, Backup, Performance, Patching, Node Add/Remove, Troubleshooting
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)
**Số lượng case:** 40 cases thực chiến — Format: Vấn đề → Nguyên nhân → Xử lý → Bài học → Phòng ngừa

---

## KIẾN TRÚC TỔNG QUAN RAC TROUBLESHOOTING

```
Oracle RAC — Failure Domain Map
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────────┐
│         CLUSTERWARE LAYER (Grid Infrastructure)           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │   CSS    │  │   CRS    │  │   OCR/   │   Group A     │
│  │ Heartbeat│  │ Resource │  │  Voting  │   (1-12)      │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
└───────┼─────────────┼─────────────┼───────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼───────────────────────┐
│              SHARED STORAGE LAYER (ASM)                     │
│  ┌──────────┐  ┌──────────┐                Group B        │
│  │Diskgroup │  │  Rebalance│                (13-20)        │
│  └────┬─────┘  └────┬─────┘                                │
└───────┼─────────────┼───────────────────────────────────────┘
        │             │
┌───────▼─────────────▼───────────────────────────────────────┐
│         INSTANCE & CACHE FUSION LAYER                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group C        │
│  │  Cache   │  │ Services/│  │   TAF/   │   (21-30)        │
│  │  Fusion  │  │  Failover│  │   FCF    │                  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                  │
└───────┼─────────────┼─────────────┼───────────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼───────────────────────────┐
│         OPERATIONS LAYER (Patch/Backup/Scale)                   │
│  ┌──────────────────────────────────┐   Group D              │
│  │  Patching / Add-Remove Node       │   (31-40)              │
│  └──────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘

Severity: 🔴 CLUSTER DOWN/UNSTABLE | 🟡 PARTIAL DEGRADATION | 🟢 MAINTENANCE ISSUE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## NHÓM A: CLUSTERWARE — CSS/CRS/OCR/VOTING (Case 1-12)

### Case 1: Node Eviction đột ngột không rõ nguyên nhân ban đầu

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Một node bị CSS (Cluster Synchronization Services) trục xuất khỏi cluster đột ngột (thường kèm reboot tự động), instance trên node đó crash ngay lập tức — ảnh hưởng tới availability và có thể gây service interruption nếu application không có TAF/FCF đúng cách.

**2. Nguyên nhân**
CSS dùng cơ chế "node kill" để ngăn split-brain khi nghi ngờ network hoặc storage heartbeat bị mất quá ngưỡng (`misscount`). Ba nguyên nhân phổ biến nhất: network interconnect packet loss/latency cao, voting disk I/O quá chậm, hoặc node bị treo (CPU/memory exhaustion) không kịp ghi heartbeat đúng hạn.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận trạng thái cluster hiện tại
crsctl check cluster -all
olsnodes -n -s

# Bước 2: Phân tích CSS log để tìm nguyên nhân
grep -E "evict|missed|disktimeout|networktimeout" \
  $GRID_HOME/log/$(hostname)/cssd/ocssd.log | tail -100

# Bước 3: Phân loại theo pattern tìm được (xem Case 2-4 để xử lý chi tiết theo từng nguyên nhân)

# Bước 4: Sau khi xác định và fix root cause, rejoin node
crsctl start crs
crsctl check crs
```

**4. Bài học kinh nghiệm**
Node Eviction LUÔN có nguyên nhân cụ thể trong log — tuyệt đối không chỉ "restart và hy vọng không lặp lại" mà phải truy nguyên đến cùng, vì nếu là vấn đề hạ tầng (network/storage) thì eviction SẼ TÁI DIỄN, có thể vào thời điểm tệ hơn (giờ cao điểm).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết lập dedicated, isolated network cho interconnect (không share với traffic khác), monitoring riêng cho packet loss/latency của interconnect.
- Voting disk PHẢI trên storage có latency thấp và ổn định, test I/O latency định kỳ.
- Capacity planning đảm bảo node không bao giờ chạm ngưỡng CPU/Memory exhaustion trong điều kiện peak load dự kiến.

---

### Case 2: Node Eviction do Network Interconnect — packet loss/latency

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Eviction lặp lại theo pattern liên quan tới network congestion (thường vào giờ cao điểm khi traffic backup/batch job chạy đồng thời với OLTP).

**2. Nguyên nhân**
Interconnect network bị share với traffic khác (vi phạm nguyên tắc dedicated network), hoặc MTU mismatch gây fragmentation, hoặc switch port có vấn đề (flapping, duplex mismatch).

**3. Thủ tục xử lý**
```bash
# Kiểm tra packet loss thực tế
ping -c 1000 -i 0.1 10.10.1.2 | tail -5

# Kiểm tra Jumbo Frame hoạt động đúng (nếu đã cấu hình MTU 9000)
ping -M do -s 8972 10.10.1.2

# Kiểm tra network errors ở OS level
netstat -s | grep -E "error|drop|retrans"
ip -s link show eth1

# Phối hợp Network team kiểm tra switch port statistics
```

**4. Bài học kinh nghiệm**
"Đã cấu hình dedicated interconnect" trên giấy tờ không đảm bảo THỰC TẾ network đó không bị share — switch/VLAN configuration có thể bị thay đổi bởi network team khác mà DBA không biết, cần audit định kỳ.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Document rõ ràng trong CMDB network diagram đâu là interconnect VLAN, gắn nhãn "KHÔNG ĐƯỢC THAY ĐỔI/SHARE" với quy trình change approval riêng có sign-off từ DBA team trước khi network team thực hiện bất kỳ thay đổi nào liên quan.

---

### Case 3: Node Eviction do Voting Disk I/O chậm

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Eviction xảy ra ngay cả khi network hoàn toàn bình thường — dấu hiệu cho thấy vấn đề nằm ở storage layer chứ không phải network.

**2. Nguyên nhân**
Voting disk đặt trên storage có latency cao (thường do storage bị overload bởi I/O khác, hoặc SAN/array đang thực hiện maintenance/rebuild ảnh hưởng tới latency tổng thể).

**3. Thủ tục xử lý**
```bash
# Đo trực tiếp latency ghi/đọc voting disk
time dd if=/dev/CRS1 of=/dev/null bs=512 count=1000

# Kiểm tra storage-wide I/O metrics
iostat -x 1 10 | grep -E "$(crsctl query css votedisk | grep -oP '(?<=\().*?(?=\))')"

# Kiểm tra threshold hiện tại
crsctl get css disktimeout
crsctl get css misscount
```

**4. Bài học kinh nghiệm**
Voting disk cần storage TIER cao nhất, KHÔNG được share I/O queue với datafiles hoặc backup traffic — đây thường bị xem nhẹ vì voting disk dung lượng nhỏ (vài trăm MB) nên dễ bị đặt chung array với data lớn hơn mà không cân nhắc latency requirement riêng biệt.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đặt Voting Disk (cùng OCR) trên dedicated diskgroup với storage tier nhanh nhất available (SSD/NVMe), monitor latency của riêng diskgroup này tách biệt khỏi DATA diskgroup.

---

### Case 4: Node Eviction do CPU/Memory Exhaustion (Server quá tải)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Node bị evicted vì process CSSD không được CPU scheduler ưu tiên kịp thời để ghi heartbeat, dù network/storage hoàn toàn bình thường.

**2. Nguyên nhân**
Server chạy gần 100% CPU liên tục (do batch job nặng hoặc memory swap nghiêm trọng khiến toàn hệ thống bị "đứng hình" tạm thời), khiến CSSD daemon không kịp respond trong ngưỡng misscount.

**3. Thủ tục xử lý**
```bash
# Kiểm tra resource tại thời điểm xảy ra eviction (lịch sử)
sar -u -f /var/log/sa/sa$(date -d "yesterday" +%d)
dmesg | grep -E "hung|stall|blocked|oom"

# Kiểm tra swap usage
free -g
sar -r -f /var/log/sa/sa$(date +%d)
```

**4. Bài học kinh nghiệm**
Capacity planning phải tính tới buffer an toàn cho hệ thống Clusterware daemon, không chỉ tính đủ cho database workload — khi server chạm 100% CPU dù chỉ trong vài giây, hệ quả có thể là TOÀN BỘ NODE bị evicted, gây impact lớn hơn nhiều so với chỉ "query chạy chậm".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết lập Resource Manager để giới hạn batch jobs không tiêu thụ 100% CPU, để dành margin cho hệ thống.
- Monitor và alert sớm khi CPU/Memory đạt ngưỡng nguy hiểm (VD: 85%) thay vì đợi tới 100% mới phản ứng.
- Cân nhắc dùng CPU/cgroup isolation cho Clusterware processes để đảm bảo chúng luôn có resource tối thiểu.

---

### Case 5: CRS-4535 — Cannot communicate with Cluster Ready Services

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Không thể quản lý cluster resources qua srvctl/crsctl — DBA mất khả năng can thiệp qua công cụ chuẩn, cần dùng OS-level commands để chẩn đoán.

**2. Nguyên nhân**
CRSD daemon chưa start hoặc đã crash, thường do dependency chain (OHASD → CSSD → CRSD) bị gián đoạn ở một mắt xích nào đó.

**3. Thủ tục xử lý**
```bash
crsctl stat res -t -init  # Kiểm tra init resources (không cần CRSD)
crsctl stat res ora.crsd -init

tail -200 $GRID_HOME/log/$(hostname)/crsd/crsd.log
# Thường restart theo thứ tự đúng sẽ tự fix
crsctl start crs
```

**4. Bài học kinh nghiệm**
Clusterware có dependency chain nghiêm ngặt — không thể "nhảy cóc" start CRSD nếu OHASD/CSSD chưa healthy, cần kiểm tra từ dưới lên trên theo đúng thứ tự kiến trúc.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Hiểu rõ và document dependency chain Clusterware cho team vận hành, tránh thao tác can thiệp thủ công không đúng thứ tự gây thêm sự cố trong lúc cố gắng fix.

---

### Case 6: OCR Corrupt — ocrcheck báo lỗi integrity

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 NGHIÊM TRỌNG — OCR (Oracle Cluster Registry) lưu toàn bộ metadata cluster, corrupt có thể khiến TOÀN BỘ cluster không hoạt động được nếu không xử lý kịp thời.

**2. Nguyên nhân**
Hiếm gặp nhưng có thể do: storage corruption ở tầng dưới (silent data corruption), thao tác can thiệp trực tiếp không đúng cách vào OCR file, hoặc disk failure đột ngột nếu OCR không có đủ redundancy.

**3. Thủ tục xử lý**
```bash
# Xác nhận mức độ corrupt
ocrcheck

# Nếu có backup tự động (mặc định mỗi 4 giờ)
ocrconfig -showbackup

# Restore từ backup gần nhất (CẦN CLUSTER DOWN)
crsctl stop crs -f  # Tất cả nodes
ocrconfig -restore /u01/app/grid/cdata/<node>/backup00.ocr
crsctl start crs
ocrcheck  # Verify sau restore
```

**4. Bài học kinh nghiệm**
OCR backup tự động (4 giờ/lần, giữ 3-4 bản gần nhất theo mặc định Oracle) là "phao cứu sinh" cuối cùng — nhưng RPO mặc định 4 giờ có thể không đủ với thay đổi cluster configuration tần suất cao, cần đánh giá có cần manual backup thường xuyên hơn.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đặt OCR trên diskgroup với NORMAL/HIGH redundancy (không bao giờ EXTERNAL redundancy cho OCR/Voting trong môi trường production quan trọng).
- Thực hiện `ocrconfig -manualbackup` ngay sau mọi thay đổi cấu trúc cluster quan trọng (add/remove node, thay đổi resource definitions lớn).
- Test quy trình OCR restore định kỳ trên môi trường staging (giống DR drill) để đảm bảo quy trình thực sự hoạt động khi cần.

---

### Case 7: CRS-1006 — node is not a member of cluster (sau network change)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Một node không còn được công nhận là thành viên cluster sau một thay đổi hạ tầng (thường network), cần can thiệp thủ công để rejoin.

**2. Nguyên nhân**
GPnP (Grid Plug and Play) profile không đồng bộ do thay đổi network configuration (IP, hostname) mà chưa cập nhật đúng cách qua Oracle's official procedures.

**3. Thủ tục xử lý**
```bash
crsctl query css votedisk
olsnodes -n

# Kiểm tra GPnP profile
$GRID_HOME/bin/gpnptool get

# Trường hợp phức tạp cần Oracle Support hỗ trợ profile repair
```

**4. Bài học kinh nghiệm**
Mọi thay đổi network-level (IP, hostname) liên quan tới RAC nodes PHẢI tuân theo quy trình chính thức của Oracle (`oifcfg`, official node rename procedures), không được thay đổi trực tiếp ở OS level rồi "hy vọng" Clusterware tự nhận diện.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Document quy trình chuẩn cho mọi thay đổi network liên quan RAC (xem Oracle official docs cho "Changing the Network IP Address"), không cho phép network team tự ý thay đổi mà không phối hợp DBA.

---

### Case 8: PRCR-1079 — Failed to start resource ora.crsd

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 CRSD không start được sau reboot/maintenance, cluster không hoạt động hoàn chỉnh.

**2. Nguyên nhân**
Thường liên quan tới OCR hoặc Voting Disk không accessible tại thời điểm CRSD cần đọc (storage chưa sẵn sàng, hoặc permission issue).

**3. Thủ tục xử lý**
```bash
crsctl stat res ora.crsd -init
tail -200 $GRID_HOME/log/$(hostname)/crsd/crsd.log

# Kiểm tra OCR/Voting accessible
ocrcheck
crsctl query css votedisk
```

**4. Bài học kinh nghiệm**
Thứ tự khởi động hạ tầng quan trọng — nếu shared storage (SAN/NFS) chưa sẵn sàng khi server boot, Clusterware sẽ fail start CRSD. Cần đảm bảo storage layer luôn sẵn sàng TRƯỚC khi Clusterware service start (dependency ở OS/systemd level).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Cấu hình systemd/init dependency đúng cách để Clusterware service chờ storage mount hoàn tất trước khi start, đặc biệt quan trọng sau server reboot/power outage.

---

### Case 9: Split-Brain nghi ngờ — 2 nodes đều tự nhận là Primary

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 RỦI RO DATA CORRUPTION CỰC KỲ NGHIÊM TRỌNG — nếu thực sự xảy ra split-brain (2 nửa cluster hoạt động độc lập không biết về nhau), data integrity có thể bị phá vỡ hoàn toàn.

**2. Nguyên nhân**
Về mặt thiết kế, Oracle Clusterware với Voting Disk quorum mechanism được thiết kế để NGĂN CHẶN hoàn toàn split-brain thực sự xảy ra — "nghi ngờ split-brain" thường là hiểu nhầm symptom khác (VD: 2 listener cùng port khác network segment).

**3. Thủ tục xử lý**
```bash
# Xác nhận thực sự cluster có đang hoạt động đúng quorum không
crsctl check cluster -all
crsctl query css votedisk

# Nếu cluster status OK trên cả 2 nodes mà nghi ngờ do connection routing sai
# -> kiểm tra lại network/DNS/SCAN configuration thay vì coi là split-brain thật
```

**4. Bài học kinh nghiệm**
Với thiết kế Voting Disk quorum đúng cách (ODD number of voting disks), split-brain THỰC SỰ gần như không thể xảy ra trong Oracle RAC — khi nghi ngờ hiện tượng này, hãy kiểm tra kỹ symptom thực tế trước khi panic, có thể là vấn đề khác (DNS, application connection pool cache stale).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đảm bảo LUÔN có số lẻ Voting Disks (3, 5...) trên storage độc lập, test quorum behavior định kỳ (disconnect 1 node tạm thời trên staging để verify behavior đúng như thiết kế).

---

### Case 10: GPnP Profile corrupt sau thao tác thủ công sai

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Toàn bộ cluster bootstrap process bị ảnh hưởng, các node không thể start Clusterware đúng cách.

**2. Nguyên nhân**
DBA/Admin thao tác trực tiếp sửa file GPnP profile XML thay vì dùng official `gpnptool`/`crsctl` commands, dẫn tới cấu trúc XML không hợp lệ hoặc thiếu signature.

**3. Thủ tục xử lý**
```bash
$GRID_HOME/bin/gpnptool check -p=$GRID_HOME/gpnp/$(hostname)/profiles/peer/profile.xml

# Đây là tình huống PHỨC TẠP, thường cần Oracle Support hỗ trợ
# Không tự ý sửa file XML thủ công thêm lần nữa
```

**4. Bài học kinh nghiệm**
GPnP Profile là metadata nội bộ phức tạp với digital signature — TUYỆT ĐỐI KHÔNG được sửa trực tiếp bằng text editor, mọi thay đổi PHẢI qua official tools (`oifcfg`, `srvctl`, `crsctl`).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đào tạo rõ ràng cho team: KHÔNG BAO GIỜ edit trực tiếp các file cấu hình internal của Clusterware (GPnP profile, OCR binary) bằng tay — luôn dùng official command-line tools, kể cả khi "chỉ sửa 1 dòng nhỏ".

---

### Case 11: CSS Misscount Threshold quá nhạy, gây False Positive Eviction

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Node bị evicted dù không có vấn đề thực sự nghiêm trọng — chỉ là 1 đợt network jitter ngắn (vài giây) trong môi trường có network quality không hoàn hảo (VD: WAN-based stretched cluster).

**2. Nguyên nhân**
Misscount mặc định (30 giây) có thể quá strict cho môi trường có network latency cao hơn bình thường (stretched cluster across datacenters), gây false positive.

**3. Thủ tục xử lý**
```bash
crsctl get css misscount
crsctl get css disktimeout

# Điều chỉnh CẨN THẬN (chỉ khi có lý do chính đáng và đã review với Oracle Support)
crsctl set css misscount 60  # Tăng từ 30 lên 60 giây
```

**4. Bài học kinh nghiệm**
Tăng misscount giúp giảm false positive eviction NHƯNG đồng thời làm chậm thời gian phát hiện node down thực sự — đây là trade-off cần cân nhắc kỹ, không nên tùy tiện tăng mà không hiểu rõ hệ quả.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với kiến trúc Stretched RAC (multi-datacenter), tham khảo Oracle MAA (Maximum Availability Architecture) best practices cho cấu hình misscount/disktimeout phù hợp, không tự ý điều chỉnh dựa trên đoán định.

---

### Case 12: Time Sync (NTP) lệch giữa các nodes gây cluster instability

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Cluster hoạt động không ổn định, các log timestamp không khớp gây khó khăn troubleshooting, có thể ảnh hưởng tới các tính năng dựa trên time-based coordination.

**2. Nguyên nhân**
NTP daemon không chạy hoặc không sync đúng trên 1/nhiều nodes, thời gian lệch nhau vượt ngưỡng cho phép.

**3. Thủ tục xử lý**
```bash
chronyc tracking  # Kiểm tra trên từng node
ssh node2 'chronyc tracking'

systemctl restart chronyd
chronyc makestep  # Force sync ngay nếu lệch quá nhiều
```

**4. Bài học kinh nghiệm**
NTP sync là prerequisite CƠ BẢN nhưng dễ bị bỏ quên trong vận hành lâu dài — NTP daemon có thể bị stop bởi 1 thao tác maintenance khác mà không ai chú ý cho tới khi gây vấn đề.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Monitor NTP sync status như 1 health check tiêu chuẩn (đưa vào daily health check — xem SK09-01), alert ngay khi phát hiện time drift vượt ngưỡng trên bất kỳ node nào.

---

## NHÓM B: ASM SHARED STORAGE (Case 13-20)

### Case 13: ASM Diskgroup tự động DISMOUNT trên 1 node

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Instance trên node đó crash ngay lập tức vì không truy cập được datafiles, trong khi các nodes khác vẫn hoạt động bình thường — gây confusion vì "chỉ 1 phần" cluster bị ảnh hưởng.

**2. Nguyên nhân**
Thường do disk path bị mất kết nối CHỈ trên node đó (SAN zoning issue, multipath configuration sai riêng cho node này), khiến ASM instance trên node đó không còn quorum đủ để giữ diskgroup mounted.

**3. Thủ tục xử lý**
```bash
# Trên node bị ảnh hưởng
asmcmd lsdsk

# So sánh với node khác đang hoạt động bình thường
ssh node1 'asmcmd lsdsk'

# Kiểm tra SAN zoning/multipath riêng cho node này
multipath -ll
```

**4. Bài học kinh nghiệm**
SAN zoning configuration PHẢI giống hệt nhau across TẤT CẢ RAC nodes — một sai sót nhỏ trong zoning config (thường do thao tác thủ công không dùng template/script chuẩn) chỉ ảnh hưởng 1 node có thể gây sự cố khó chẩn đoán.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Dùng infrastructure-as-code/scripted approach cho SAN zoning configuration thay vì thao tác thủ công từng node, đảm bảo consistency tuyệt đối; thực hiện validation script so sánh disk visibility giữa các nodes định kỳ.

---

### Case 14: ASM Rebalance chạy cực chậm, ảnh hưởng performance kéo dài

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Sau khi add/remove disk, quá trình rebalance kéo dài nhiều giờ/ngày, tiêu tốn I/O resource đáng kể ảnh hưởng tới production workload đồng thời.

**2. Nguyên nhân**
Power level của rebalance quá thấp so với khối lượng data cần di chuyển, hoặc storage I/O throughput không đủ cho cả production traffic lẫn rebalance traffic cùng lúc.

**3. Thủ tục xử lý**
```sql
SELECT * FROM v$asm_operation;
-- Theo dõi est_minutes để ước lượng thời gian còn lại

-- Tăng power nếu storage còn headroom (cẩn thận tác động production)
ALTER DISKGROUP DATA REBALANCE POWER 8;

-- Hoặc giảm power nếu đang ảnh hưởng production quá nhiều
ALTER DISKGROUP DATA REBALANCE POWER 2;
```

**4. Bài học kinh nghiệm**
Rebalance Power là con dao 2 lưỡi — power cao hoàn thành nhanh hơn nhưng tiêu tốn I/O nhiều hơn ngay lúc đó; cần cân nhắc thời điểm thực hiện (off-peak hours) và power level phù hợp với storage headroom thực tế, không chỉ set "power cao nhất cho nhanh".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Lên kế hoạch thêm/bớt disk vào off-peak window, capacity test storage I/O headroom trước để xác định power level phù hợp không ảnh hưởng SLA, theo dõi tiến độ chủ động thay vì "set and forget".

---

### Case 15: ORA-15041 ASM full trên RAC dù 1 node vừa cleanup được

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Database operations fail vì ASM báo full dù logic nghĩ rằng vừa giải phóng được dung lượng — gây nhầm lẫn trong xử lý khẩn cấp.

**2. Nguyên nhân**
Có độ trễ giữa thao tác xóa (DROP TABLESPACE/file) và việc ASM thực sự reclaim không gian trống — đặc biệt nếu rebalance chưa hoàn tất hoàn toàn.

**3. Thủ tục xử lý**
```sql
SELECT name, free_mb, total_mb FROM v$asm_diskgroup;
SELECT * FROM v$asm_operation;  -- Xem có rebalance đang chạy không

-- Nếu rebalance đang pending, đợi hoàn tất hoặc force power cao hơn tạm thời
ALTER DISKGROUP DATA REBALANCE POWER 4;
```

**4. Bài học kinh nghiệm**
"Đã xóa data" không đồng nghĩa "không gian đã thực sự available" trong ASM — luôn verify qua `v$asm_operation` trước khi kết luận tình huống storage emergency đã được giải quyết.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Trong tình huống cleanup khẩn cấp storage, luôn theo dõi `v$asm_operation` cho tới khi rebalance hoàn tất 100% trước khi báo cáo "đã xử lý xong" cho stakeholder.

---

### Case 16-20: Tổng hợp ASM issues khác (rút gọn)

**Case 16 — ASM disk WWN mismatch giữa nodes gây Voting Disk không nhất quán:**
Vấn đề: Voting disk path khác nhau dù cùng physical disk do udev rules không đồng bộ. Nguyên nhân: thiết lập udev rules thủ công riêng từng node thay vì dùng config tập trung. Xử lý: đồng bộ udev rules dựa trên WWN identifier nhất quán across nodes. Bài học: mọi shared storage config RAC cần dùng identifier ổn định (WWN), không dùng device path có thể đổi (`/dev/sdX`). Phòng ngừa: dùng configuration management tool để deploy udev rules đồng nhất, không thao tác thủ công từng server.

**Case 17 — ASM instance OOM khi rebalance large diskgroup:**
Vấn đề: ASM instance crash do out-of-memory khi xử lý rebalance trên diskgroup rất lớn (hàng trăm TB). Nguyên nhân: ASM PGA/memory sizing không đủ cho metadata processing của rebalance quy mô lớn. Xử lý: tăng ASM instance memory_target trước khi thực hiện rebalance lớn. Bài học: ASM instance cũng cần capacity planning như DB instance, không chỉ "set và quên". Phòng ngừa: review ASM memory sizing khi diskgroup tăng trưởng đáng kể, không giữ nguyên cấu hình từ lúc setup ban đầu.

**Case 18 — Multipath failover không transparent, gây I/O error tạm thời:**
Vấn đề: Khi 1 path tới SAN storage bị down, ASM ghi nhận I/O error trước khi multipath failover hoàn tất, dù có alternate path. Nguyên nhân: multipath timeout configuration chưa tối ưu cho Oracle ASM workload pattern. Xử lý: tune multipath.conf với `path_checker`/`failback` settings phù hợp khuyến nghị Oracle. Bài học: Multipath default configuration không phải lúc nào cũng tối ưu cho Oracle workload, cần tuning riêng. Phòng ngừa: áp dụng Oracle-recommended multipath settings (tham khảo MOS notes cho storage vendor cụ thể) ngay từ giai đoạn build hạ tầng.

**Case 19 — ASM Compatible.rdbms parameter chặn tính năng mới sau upgrade DB:**
Vấn đề: Sau khi upgrade Database lên version mới, một số tính năng ASM-dependent không hoạt động. Nguyên nhân: `compatible.rdbms` của diskgroup vẫn ở mức cũ, chưa update theo Database version mới. Xử lý: `ALTER DISKGROUP DATA SET ATTRIBUTE 'compatible.rdbms'='19.0';` (sau khi đã chắc chắn KHÔNG cần rollback). Bài học: Compatible attributes của ASM cần update đồng bộ theo Database upgrade lifecycle. Phòng ngừa: đưa "review ASM compatible attributes" vào checklist post-upgrade chuẩn (xem SK01-05).

**Case 20 — ASM disk header bị conflict sau khi tái sử dụng disk từ cluster cũ:**
Vấn đề: Disk được tái sử dụng từ một cluster cũ vẫn còn ASM header cũ, gây conflict khi cố thêm vào diskgroup mới. Nguyên nhân: chưa clear hoàn toàn ASM metadata trước khi tái sử dụng disk. Xử lý: `dd if=/dev/zero of=/dev/DISK bs=1M count=100` để xóa header trước khi add (CẨN THẬN — mất hết data cũ). Bài học: tái sử dụng disk từ hệ thống cũ luôn cần clear metadata kỹ lưỡng. Phòng ngừa: chuẩn hóa quy trình decommission disk (bao gồm secure wipe metadata) trước khi đưa vào kho tái sử dụng.

---

## NHÓM C: CACHE FUSION / SERVICES / TAF-FCF (Case 21-30)

### Case 21: Gc Buffer Busy Wait cao bất thường trên 1 bảng cụ thể

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Performance giảm đáng kể cho các session truy cập bảng đó từ nhiều instances đồng thời, đặc biệt nghiêm trọng với bảng "hot" có insert/update tần suất cao.

**2. Nguyên nhân**
Hot block contention qua Cache Fusion — nhiều instances liên tục tranh chấp quyền sở hữu cùng 1 block (thường do sequence-based PK insert tập trung vào cùng block, hoặc thiếu Reverse Key Index/Hash Partitioning cho bảng OLTP cao tải trên RAC).

**3. Thủ tục xử lý**
```sql
SELECT o.object_name, COUNT(*) waits
FROM gv$session_wait sw JOIN dba_objects o ON sw.p1=o.object_id
WHERE sw.event LIKE 'gc buffer busy%'
GROUP BY o.object_name ORDER BY waits DESC;

-- Kiểm tra sequence cache cho bảng liên quan
SELECT sequence_name, cache_size FROM dba_sequences WHERE sequence_name='ORDER_SEQ';
ALTER SEQUENCE order_seq CACHE 1000 NOORDER;
```

**4. Bài học kinh nghiệm**
Trong môi trường RAC, hot block contention nghiêm trọng hơn nhiều so với Single Instance vì phải đi qua Cache Fusion protocol (network round-trip) thay vì chỉ local memory access — thiết kế schema cho RAC cần cân nhắc kỹ vấn đề này ngay từ đầu, không chỉ "port" từ thiết kế Single Instance.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Với bảng OLTP cao tải dự kiến chạy trên RAC, đánh giá kỹ insert pattern ngay từ giai đoạn thiết kế: tăng sequence CACHE đáng kể, cân nhắc Hash Partitioning hoặc Reverse Key Index nếu cần, test concurrency trên RAC staging environment trước go-live (không chỉ test trên Single Instance).

---

### Case 22: Service không Failover đúng cách khi instance down

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Application mất kết nối hoàn toàn dù còn instance khác hoạt động bình thường — defeat toàn bộ mục đích của RAC (high availability).

**2. Nguyên nhân**
Service không được cấu hình đúng `preferred`/`available` instances, hoặc application không dùng connection string đúng cách (point trực tiếp tới 1 instance/VIP cụ thể thay vì qua SCAN + service name).

**3. Thủ tục xử lý**
```bash
srvctl config service -d ORCL -s APP_SVC
srvctl status service -d ORCL -s APP_SVC

# Fix cấu hình service nếu sai
srvctl modify service -d ORCL -s APP_SVC \
  -preferred ORCL1,ORCL2 -available ORCL3
```

**4. Bài học kinh nghiệm**
"Có RAC" không tự động đồng nghĩa "có High Availability" — application PHẢI kết nối qua service name đúng cách (không hardcode instance/VIP), và service PHẢI được config preferred/available hợp lý. Đây là lỗi thiết kế application phổ biến nhất khiến RAC mất tác dụng HA.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Đưa "connection string review" vào quy trình go-live bắt buộc cho mọi application mới kết nối RAC database — kiểm tra application dùng SCAN + Service Name, không hardcode VIP/instance cụ thể; test failover thực tế (kill 1 instance) trên staging trước go-live.

---

### Case 23: TAF không hoạt động — Session không Failover dù đã cấu hình

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Mặc dù đã cấu hình TAF trong tnsnames.ora, session vẫn bị disconnect hoàn toàn khi instance fail thay vì tự động chuyển sang instance khác.

**2. Nguyên nhân**
TAF cấu hình ở client-side (tnsnames.ora) nhưng service trên server-side không có matching TAF policy, hoặc thư viện Oracle Client phiên bản cũ không support đầy đủ TAF features.

**3. Thủ tục xử lý**
```sql
-- Verify TAF status thực tế trong session
SELECT failed_over, failover_type, failover_method FROM v$session
WHERE username='APP_USER';
```
```bash
-- Đảm bảo service có TAF policy khớp với client config
srvctl modify service -d ORCL -s APP_SVC \
  -failovertype SELECT -failovermethod BASIC -failoverretry 15
```

**4. Bài học kinh nghiệm**
TAF cần cấu hình ĐỒNG BỘ cả 2 phía (client tnsnames.ora VÀ server service definition) — chỉ cấu hình 1 phía không đủ để TAF hoạt động, đây là điểm dễ bị thiếu sót khi handover giữa các team (network/app team setup client, DBA setup server).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Document rõ ràng TAF configuration cần đồng bộ 2 phía, cung cấp checklist/script tự động verify cả client và server-side config khớp nhau trước khi xác nhận TAF "đã setup xong".

---

### Case 24-30: Tổng hợp Cache Fusion/Services khác (rút gọn)

**Case 24 — FCF không trigger notification khi node down (ONS issue):**
Vấn đề: Fast Connection Failover không hoạt động, application không nhận được notification ngay khi node down, phải đợi connection timeout thông thường. Nguyên nhân: ONS (Oracle Notification Service) không chạy hoặc misconfigured. Xử lý: `srvctl status ons` và `srvctl start ons` nếu cần, verify cấu hình `ons.config`. Bài học: FCF phụ thuộc hoàn toàn vào ONS hoạt động đúng, đây là component dễ bị bỏ quên trong monitoring. Phòng ngừa: đưa ONS status vào health check định kỳ, không chỉ kiểm tra CRS/ASM/Database resources.

**Case 25 — Sequence ORDER gây serialization nghiêm trọng trên RAC:**
Vấn đề: Sequence với `ORDER` option (đảm bảo thứ tự tăng dần tuyệt đối across instances) gây serialization bottleneck nghiêm trọng. Nguyên nhân: `ORDER` yêu cầu coordination qua GES (Global Enqueue Services) cho MỖI lần NEXTVAL, tương đương single-threaded ở mức cluster. Xử lý: đánh giá lại có thực sự cần ORDER không (business requirement), nếu không cần thì bỏ ORDER. Bài học: ORDER sequence là antipattern nghiêm trọng cho RAC trừ khi có yêu cầu nghiệp vụ tuyệt đối cần thứ tự liên tục. Phòng ngừa: review mọi sequence có ORDER trong design review, chỉ giữ lại khi thực sự cần thiết về nghiệp vụ.

**Case 26 — Service Connection Load Balancing không cân bằng (skewed):**
Vấn đề: Sessions tập trung lệch hẳn vào 1 instance thay vì cân bằng across các instances. Nguyên nhân: `CLB_GOAL` setting không phù hợp, hoặc application connection pool cache kết nối quá lâu không re-balance định kỳ. Xử lý: review CLB_GOAL setting (LONG vs SHORT) phù hợp với workload pattern. Bài học: Load balancing phụ thuộc cả vào server-side config LẪN application connection pool behavior. Phòng ngừa: review định kỳ phân bổ session across instances, điều chỉnh connection pool refresh interval nếu cần.

**Case 27 — Cache Fusion CR Block transfer time cao bất thường:**
Vấn đề: Thời gian transfer Consistent Read block giữa instances tăng đột biến, ảnh hưởng latency toàn hệ thống. Nguyên nhân: interconnect network bị nghẽn hoặc LMS process không đủ (cần tăng `gcs_server_processes`). Xử lý: kiểm tra interconnect throughput, tăng số LMS processes nếu CPU còn dư. Bài học: Cache Fusion performance phụ thuộc cả network quality LẪN đủ LMS processes để xử lý message queue. Phòng ngừa: monitor CR/Current block transfer time như 1 KPI riêng (xem SK06-02), capacity planning LMS processes theo workload.

**Case 28 — RAC One Node failover không như mong đợi:**
Vấn đề: Trong cấu hình RAC One Node, instance không tự động relocate sang node khác khi có vấn đề. Nguyên nhân: RAC One Node có cơ chế failover khác RAC thông thường, cần Omotion hoặc explicit relocate command. Xử lý: `srvctl relocate database -d ORCL -n target_node`. Bài học: RAC One Node KHÔNG tự động failover giống RAC full — cần hiểu rõ khác biệt kiến trúc trước khi triển khai. Phòng ngừa: review kỹ tài liệu RAC One Node behavior trước khi chọn kiến trúc này, đảm bảo team hiểu đúng failover semantics.

**Case 29 — Service tự động Stop sau khi Database Restart:**
Vấn đề: Service không tự động start lại sau khi database restart, dù trước đó đang chạy. Nguyên nhân: Service chưa được set "AUTO_START" hoặc role attribute không match (service chỉ dành cho PRIMARY role nhưng DB hiện ở role khác). Xử lý: `srvctl modify service -d ORCL -s SVC -policy AUTOMATIC`. Bài học: Service availability sau restart phụ thuộc cấu hình policy, không phải mặc định luôn tự start. Phòng ngừa: review policy=AUTOMATIC cho tất cả services quan trọng, test restart scenario định kỳ.

**Case 30 — Listener Local không đăng ký Service đúng cách sau Patch:**
Vấn đề: Sau khi patch Grid Infrastructure, một số services không được đăng ký lại với Local Listener. Nguyên nhân: `local_listener` parameter bị reset về default sau patch, không trỏ đúng VIP. Xử lý: `ALTER SYSTEM SET local_listener='(ADDRESS=...)' SCOPE=BOTH; ALTER SYSTEM REGISTER;`. Bài học: Patching có thể reset một số parameters về default, cần verify đầy đủ sau patch, không chỉ kiểm tra "database mở được là xong". Phòng ngừa: checklist post-patch validation đầy đủ bao gồm verify tất cả services registered đúng (xem SK01-04).

---

## NHÓM D: PATCHING & SCALING (Case 31-40)

### Case 31: Rolling Patch fail giữa chừng trên Node 2, Node 1 đã patch xong

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Cluster ở trạng thái "mixed version" tạm thời — Node 1 đã patch, Node 2 chưa, có thể gây instability nếu kéo dài hoặc nếu 2 patch level không tương thích tạm thời.

**2. Nguyên nhân**
Thường do tài nguyên không đủ trên Node 2 (disk space, hoặc conflict patch khác chưa phát hiện ở pre-check), khiến quá trình apply patch dừng lại giữa chừng.

**3. Thủ tục xử lý**
```bash
tail -200 /u01/app/grid/cfgtoollogs/opatchautodb/opatchauto_*.log

# Rollback node đã patch một phần để đưa cluster về trạng thái đồng nhất
$ORACLE_HOME/OPatch/opatchauto rollback /opt/patches/<patch_id> \
  -oh $GRID_HOME,$ORACLE_HOME

# Sau khi rollback, fix root cause (VD: giải phóng disk space)
# rồi retry toàn bộ quy trình patch từ đầu
```

**4. Bài học kinh nghiệm**
"Mixed version cluster" tạm thời trong quá trình rolling patch là CHẤP NHẬN ĐƯỢC trong thời gian ngắn (đây chính là cách rolling patch hoạt động), nhưng nếu BỊ KẸT ở trạng thái này quá lâu do lỗi, cần rollback về đồng nhất NGAY thay vì để kéo dài không kiểm soát.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Luôn chạy `-analyze` mode đầy đủ TRÊN TẤT CẢ NODES trước khi thực sự apply patch, không chỉ check node đầu tiên; đảm bảo đủ disk space buffer trên MỌI node (không chỉ node sẽ patch trước) trước khi bắt đầu rolling patch process.

---

### Case 32: addNode.sh fail — Node mới không join được Cluster

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Quá trình mở rộng cluster (thêm node mới) bị gián đoạn, cần xử lý trước khi có thể tiếp tục capacity expansion.

**2. Nguyên nhân**
Thường do node mới chưa đáp ứng đầy đủ prerequisite (xem SK01-CASE-01 Nhóm A), phổ biến nhất là SSH equivalence chưa setup đúng hoặc shared storage chưa accessible từ node mới.

**3. Thủ tục xử lý**
```bash
# Verify prerequisites trên node mới TRƯỚC khi retry addNode
su - grid -c "ssh node4 date"  # SSH equivalence
ssh node4 'asmcmd lsdsk'  # Storage accessibility

# Chạy cluvfy trước khi retry
$GRID_HOME/runcluvfy.sh stage -pre nodeadd -n node4
```

**4. Bài học kinh nghiệm**
Add Node thất bại hầu hết là do thiếu sót ở bước CHUẨN BỊ (prerequisite) chứ không phải bug trong quá trình addNode.sh tự nó — luôn chạy cluvfy pre-check đầy đủ TRƯỚC, không chỉ chạy addNode.sh rồi "thử xem có lỗi gì không".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Chuẩn hóa node provisioning process (configuration management/automation tool) đảm bảo mọi node mới đáp ứng 100% prerequisite TRƯỚC KHI bắt đầu addNode.sh, giảm thiểu thao tác thủ công dễ sai sót.

---

### Case 33-40: Tổng hợp Patching/Scaling khác (rút gọn)

**Case 33 — Datapatch chạy thiếu sau Rolling Patch (chỉ 1 node):**
Vấn đề: Sau khi patch xong tất cả node, một số SQL changes (datapatch) chưa apply đầy đủ. Nguyên nhân: datapatch chỉ cần chạy 1 LẦN cho toàn database (không phải mỗi node), nhưng dễ bị quên hoặc chạy nhầm nhiều lần gây confusion. Xử lý: chạy `datapatch -verbose` MỘT LẦN sau khi TẤT CẢ nodes đã patch xong. Bài học: phân biệt rõ "patch binary" (mỗi node) vs "datapatch SQL changes" (toàn database, 1 lần). Phòng ngừa: document rõ ràng trong runbook patch quy trình đúng, tránh nhầm lẫn giữa 2 khái niệm.

**Case 34 — Remove Node để lại Orphan Resources trong OCR:**
Vấn đề: Sau khi xóa 1 node khỏi cluster, vẫn còn resource definitions cũ trỏ tới node đó trong OCR gây confusion khi list resources. Nguyên nhân: quy trình remove node chưa cleanup hoàn chỉnh tất cả resource references. Xử lý: `crsctl delete resource <orphan_resource> -f` cho từng resource còn sót. Bài học: Remove Node là quy trình nhiều bước, dễ sót nếu làm thủ công không theo checklist đầy đủ. Phòng ngừa: dùng checklist chuẩn từ Oracle docs cho Remove Node, verify `crsctl stat res -t` sạch sẽ sau khi hoàn tất.

**Case 35 — Add Node thành công nhưng Service không tự propagate:**
Vấn đề: Node mới join cluster thành công nhưng các services hiện có không tự động available trên node mới. Nguyên nhân: Service definition có `preferred` list cố định không tự bao gồm node mới (by design, cần explicit modify). Xử lý: `srvctl modify service -d ORCL -s SVC -preferred ORCL1,ORCL2,ORCL4 (node mới)`. Bài học: Add Node về mặt Clusterware không tự động "dùng được ngay" cho application — cần bước cấu hình service bổ sung. Phòng ngừa: đưa "service preferred/available list update" vào checklist Add Node chuẩn, không coi node add là hoàn tất chỉ vì instance đã chạy.

**Case 36 — Out-of-Place Patching gây confusion về Oracle Home đang active:**
Vấn đề: Sau out-of-place patching, team vận hành nhầm lẫn không biết Oracle Home nào đang thực sự active. Nguyên nhân: thiếu documentation/communication rõ ràng về Oracle Home switch. Xử lý: verify qua `srvctl config database -d ORCL` xem oracle_home đang trỏ tới đâu. Bài học: Out-of-place patching cần communication rõ ràng cho toàn team về Oracle Home mới, không chỉ DBA thực hiện patch biết. Phòng ngừa: cập nhật CMDB/documentation NGAY sau khi switch Oracle Home, thông báo toàn team liên quan.

**Case 37 — RAC Performance giảm sau khi Add Node (thay vì cải thiện):**
Vấn đề: Sau khi thêm node để tăng capacity, performance tổng thể lại giảm thay vì tăng. Nguyên nhân: tăng thêm Cache Fusion overhead (nhiều instances hơn = nhiều coordination traffic hơn) vượt quá lợi ích từ thêm compute resource, đặc biệt nếu interconnect không được nâng cấp tương ứng. Xử lý: đánh giá lại interconnect bandwidth có đủ cho N+1 nodes không, cân nhắc upgrade network trước khi thêm node tiếp theo. Bài học: "Thêm node = thêm performance" không phải LUÔN ĐÚNG, cần đánh giá tổng thể bao gồm cả network capacity. Phòng ngừa: capacity planning đầy đủ (compute + network + storage) trước khi quyết định scale-out, không chỉ nhìn vào CPU/Memory.

**Case 38 — Cluster Health Check tự động (CHM/OSWatcher) chiếm resource đáng kể:**
Vấn đề: Cluster Health Monitor và OS Watcher background processes tiêu tốn CPU/storage I/O đáng kể, ảnh hưởng workload chính. Nguyên nhân: cấu hình mặc định CHM thu thập data quá chi tiết/tần suất cao không cần thiết cho mọi trường hợp. Xử lý: điều chỉnh CHM data retention/collection interval phù hợp. Bài học: Monitoring tools tự thân cũng tiêu tốn resource, cần cân bằng giữa observability và overhead. Phòng ngừa: review định kỳ CHM/diagnostic tools configuration, điều chỉnh theo nhu cầu thực tế thay vì giữ nguyên default mãi mãi.

**Case 39 — Patch Conflict giữa Grid Infrastructure và Database Home không phát hiện sớm:**
Vấn đề: Patch GI và DB Home riêng biệt nhưng có dependency/conflict ẩn không phát hiện ở bước pre-check riêng lẻ. Nguyên nhân: chạy pre-check riêng từng Home mà không kiểm tra tương tác giữa chúng. Xử lý: dùng OPatchAuto combined patching (patch cả 2 Home cùng lúc) thay vì riêng lẻ để Oracle tools tự phát hiện conflict. Bài học: GI và DB Home không hoàn toàn độc lập, cần patch coordination cẩn thận. Phòng ngừa: luôn dùng Combined Patch (nếu Oracle cung cấp) thay vì patch riêng lẻ 2 Home khi version tương thích cho phép.

**Case 40 — Capacity Exhausted khi Scale-out không kèm Storage Scale tương ứng:**
Vấn đề: Sau khi add nhiều compute nodes, storage I/O throughput trở thành bottleneck mới (không tăng tương ứng với compute). Nguyên nhân: capacity planning chỉ tập trung compute scale-out mà quên storage layer cũng cần scale tương ứng. Xử lý: đánh giá storage I/O headroom, cân nhắc thêm ASM disks/storage array upgrade song song. Bài học: RAC scale-out là multi-dimensional (compute + network + storage), không chỉ "thêm server là đủ". Phòng ngừa: capacity planning toàn diện theo phương pháp luận chuẩn (không chỉ nhìn 1 metric), review định kỳ tất cả layer khi traffic tăng trưởng.

---

## TỔNG KẾT — QUICK REFERENCE TABLE

```
40 Case Studies được chọn lọc theo tiêu chí:
  - Tần suất gặp phải cao trong vận hành RAC thực tế
  - Đại diện đầy đủ cho 4 nhóm: Clusterware, ASM, Cache Fusion/Services, Patching/Scaling

Top 6 Case NGHIÊM TRỌNG NHẤT (🔴 cần ưu tiên đọc trước):
  1. Case 1   — Node Eviction tổng quát (quy trình chẩn đoán chuẩn)
  2. Case 6   — OCR Corrupt (rủi ro toàn cluster down)
  3. Case 9   — Split-Brain nghi ngờ (hiểu đúng cơ chế quorum)
  4. Case 13  — ASM Diskgroup tự Dismount 1 node (SAN zoning issue)
  5. Case 22  — Service Failover không hoạt động (defeat mục đích RAC)
  6. Case 31  — Rolling Patch fail giữa chừng (mixed version risk)
```

---

**Tài liệu tham khảo:**
- Oracle Real Application Clusters Administration Guide 19c
- Oracle Clusterware Administration and Deployment Guide 19c
- Oracle Grid Infrastructure Installation Guide 19c
- MOS Note 1053147.1, 1050693.1 (Node Eviction), 1302736.1 (RAC Troubleshooting)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise