---
name: sysadmin-troubleshoot-hardware-os-infra-k8s-weblogic
description: >
  Case study khắc phục lỗi thường gặp trong vận hành hạ tầng System Admin:
  phần cứng server (HP ProLiant, Dell PowerEdge, Fujitsu PRIMERGY, Oracle
  SPARC/Exadata, IBM Power), hệ điều hành (Linux RHEL/OL, Solaris, AIX),
  dịch vụ hạ tầng (HAProxy, Pacemaker/Corosync, Nginx), container
  orchestration (Kubernetes, Docker), và middleware Oracle WebLogic Server.
  Mỗi case trình bày đầy đủ: Vấn đề/Mức độ ảnh hưởng, Nguyên nhân,
  Thủ tục xử lý, Bài học kinh nghiệm, Biện pháp phòng ngừa từ sớm/từ xa.
  Kích hoạt khi hỏi về: lỗi phần cứng server thực chiến, sự cố Linux Solaris
  AIX, troubleshoot HAProxy Pacemaker Nginx, sự cố Kubernetes Docker,
  postmortem WebLogic, iLO predictive failure, RAID controller lỗi,
  kernel panic OOM killer, split-brain Pacemaker STONITH,
  Pod CrashLoopBackOff, etcd quorum lost, JDBC connection pool exhausted,
  bài học kinh nghiệm vận hành hạ tầng system admin.
---

# SK09-CASE · Case Study: Sự cố thường gặp trong System Admin (Hardware, OS, Hạ tầng, K8s/Docker, WebLogic)

**Phạm vi:** HP ProLiant/Dell PowerEdge/Fujitsu PRIMERGY/Oracle SPARC/IBM Power | RHEL/OL, Solaris 11, AIX 7 | HAProxy, Pacemaker/Corosync, Nginx | Kubernetes, Docker | Oracle WebLogic Server 12c/14c
**Tác giả:** Trần Văn Bình — VietDBA (Hotline/Zalo: 0902 912 888 — www.tranvanbinh.vn)
**Số lượng case:** 20 case thực chiến, chia 5 nhóm

---

## KIẾN TRÚC TỔNG QUAN SYSTEM ADMIN TROUBLESHOOTING

```
System Admin — Infrastructure Failure Domain Map
══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────┐  |
│  PHYSICAL HARDWARE LAYER (Server/Storage/Firmware)            │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ HP/Dell    │  │ RAID/Disk  │  │ Memory/CPU │  Group A      │  |
│  │ iLO/iDRAC  │  │ Controller │  │ ECC/Guard  │  (1-4)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  OPERATING SYSTEM LAYER (Linux / Solaris / AIX)                │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Kernel/OOM │  │ Filesystem │  │ Zone/LPAR  │  Group B      │  |
│  │ Killer     │  │ Corruption │  │ Resource   │  (5-8)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  LOAD BALANCER & HA CLUSTER LAYER (HAProxy/Pacemaker/Nginx)   │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Health     │  │ Split-Brain│  │ Resource   │  Group C      │  |
│  │ Check      │  │ / STONITH  │  │ Failover   │  (9-12)       │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  CONTAINER ORCHESTRATION LAYER (Kubernetes / Docker)           │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Pod/Probe  │  │ Node/etcd  │  │ Storage/   │  Group D      │  |
│  │ Lifecycle  │  │ Control    │  │ Log Growth │  (13-16)      │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  MIDDLEWARE LAYER (Oracle WebLogic Server)                     │  |
│  ┌────────────┐  ┌────────────┐                              │  |
│  │ Server     │  │ JDBC Pool  │  Group E                      │  |
│  │ State/JVM  │  │ / Deploy   │  (17-20)                      │  |
│  └────────────┘  └────────────┘                              │  |
└────────────────────────────────────────────────────────────┘  |

Severity: 🔴 CRITICAL (ngừng dịch vụ/mất dữ liệu) | 🟡 DEGRADED (suy giảm/rủi ro) | 🟢 MINOR (cảnh báo)
══════════════════════════════════════════════════════════════════
```

---

## MỤC LỤC CHI TIẾT THEO NHÓM

**NHÓM A: Phần cứng Server — HP/Dell/Fujitsu/Oracle/IBM (Case 1-4)**
- Case 1: 🟡 HP ProLiant iLO báo Predictive Failure bị bỏ qua dẫn đến hỏng đĩa thật
- Case 2: 🔴 Dell PowerEdge — RAID Controller Battery (BBU) lỗi gây cache ghi tắt, hiệu năng sụt giảm nghiêm trọng
- Case 3: 🟡 Fujitsu PRIMERGY — lỗi ECC memory tích lũy gây corruption âm thầm
- Case 4: 🔴 IBM Power/AIX — Service Processor mất kết nối, không thể quản lý LPAR từ xa

**NHÓM B: Hệ điều hành — Linux/Solaris/AIX (Case 5-8)**
- Case 5: 🔴 Linux OOM Killer giết nhầm tiến trình quan trọng (database/middleware)
- Case 6: 🔴 Filesystem corruption (XFS/ext4) sau unclean shutdown
- Case 7: 🟡 Solaris Zone — tranh chấp tài nguyên giữa non-global zone không giới hạn
- Case 8: 🟡 AIX LPAR — thiếu paging space gây hang toàn hệ thống

**NHÓM C: Load Balancer & HA Cluster — HAProxy/Pacemaker/Nginx (Case 9-12)**
- Case 9: 🟡 HAProxy — backend server flapping do health check cấu hình sai
- Case 10: 🔴 Pacemaker/Corosync — Split-brain do STONITH không được cấu hình
- Case 11: 🟡 Pacemaker — resource kẹt ở trạng thái Started trên node sai sau failover
- Case 12: 🟡 Nginx — lỗi 502/504 hàng loạt do vượt giới hạn worker_connections

**NHÓM D: Container Orchestration — Kubernetes/Docker (Case 13-16)**
- Case 13: 🔴 Kubernetes — Pod CrashLoopBackOff do liveness probe cấu hình sai
- Case 14: 🔴 Kubernetes — Node chuyển NotReady do Disk Pressure
- Case 15: 🔴 Kubernetes — etcd cluster mất quorum, control plane ngừng phản hồi
- Case 16: 🟡 Docker — dung lượng disk phình to không kiểm soát do log container

**NHÓM E: Middleware — Oracle WebLogic Server (Case 17-20)**
- Case 17: 🔴 WebLogic Managed Server kẹt ở trạng thái ADMIN sau crash
- Case 18: 🔴 WebLogic — JDBC Connection Pool cạn kiệt do connection leak
- Case 19: 🟡 WebLogic — Node Manager mất kết nối, không thể failover cluster
- Case 20: 🟡 WebLogic — Heap Out of Memory gây GC pause storm định kỳ

---

## NHÓM A: PHẦN CỨNG SERVER — HP/DELL/FUJITSU/ORACLE/IBM (Case 1-4)

### Case 1: HP ProLiant iLO báo Predictive Failure bị bỏ qua dẫn đến hỏng đĩa thật

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED → 🔴 nếu leo thang thành mất đĩa thật trong RAID chưa kịp rebuild. iLO (Integrated Lights-Out) gửi cảnh báo "Drive predictive failure" nhiều ngày trước khi đĩa thực sự hỏng, nhưng không ai xử lý kịp thời — đến khi đĩa hỏng thật, RAID phải chạy ở chế độ degraded, tăng rủi ro mất dữ liệu nếu có đĩa thứ hai hỏng trong lúc rebuild.

**2. Nguyên nhân**
Cảnh báo SNMP trap/email từ iLO không được tích hợp vào hệ thống monitoring trung tâm (chỉ gửi email riêng lẻ, dễ bị bỏ sót trong hộp thư chung), không có quy trình rõ ràng ai chịu trách nhiệm theo dõi và phản hồi cảnh báo phần cứng.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái sức khỏe hệ thống qua iLO CLI/hpasmcli
hpasmcli -s "show server"
ssacli ctrl slot=0 pd all show status

# Bước 2: Xác định đĩa cảnh báo cụ thể
ssacli ctrl slot=0 pd all show detail | grep -A5 "predictive"

# Bước 3: Đặt lịch thay đĩa trong bảo trì gần nhất, đảm bảo RAID có đủ redundancy
# trong lúc chờ thay (kiểm tra không có đĩa nào khác đang degraded đồng thời)
ssacli ctrl slot=0 ld all show status

# Bước 4: Sau khi thay đĩa, xác nhận rebuild hoàn tất
ssacli ctrl slot=0 ld all show status
# Theo dõi % rebuild tới 100%
```

**4. Bài học kinh nghiệm**
Cảnh báo phần cứng "predictive failure" là một trong những tín hiệu đáng tin cậy nhất về sự cố sắp xảy ra (khác với phần mềm, phần cứng thường có dấu hiệu suy giảm dần trước khi hỏng hẳn) — bỏ qua loại cảnh báo này là lãng phí "cửa sổ thời gian vàng" để xử lý có kế hoạch thay vì xử lý khẩn cấp.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tích hợp SNMP trap từ iLO/iDRAC/iRMC vào hệ thống monitoring trung tâm (Zabbix/Nagios/Prometheus), không để cảnh báo phần cứng nằm rải rác qua email riêng lẻ
- Quy định rõ SLA phản hồi cho từng mức độ cảnh báo phần cứng (predictive failure = xử lý trong X ngày làm việc, không phải "khi nào rảnh")
- Duy trì kho phụ tùng thay thế (đĩa, RAM) tối thiểu tại chỗ cho hệ thống production quan trọng, giảm thời gian chờ đặt hàng khi cần thay khẩn cấp

---

### Case 2: Dell PowerEdge — RAID Controller Battery (BBU) lỗi gây cache ghi tắt, hiệu năng sụt giảm nghiêm trọng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL về mặt hiệu năng (không mất dữ liệu ngay nhưng ảnh hưởng nghiêm trọng đến khả năng phục vụ). Toàn bộ I/O ghi trên server đột ngột chậm hẳn (có thể chậm 10-50 lần so với bình thường) mà không có thay đổi nào về khối lượng công việc.

**2. Nguyên nhân**
RAID Controller tự động chuyển chế độ cache từ "Write-Back" (ghi vào cache trước, flush xuống đĩa sau — nhanh) sang "Write-Through" (ghi trực tiếp xuống đĩa, chờ xác nhận — chậm) khi phát hiện pin cache (BBU/Supercap) bị lỗi hoặc đang sạc lại, vì không còn đảm bảo dữ liệu trong cache an toàn nếu mất điện đột ngột.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái RAID controller và battery
racadm raid get controllers -o -p State,CacheSizeInMB
omreport storage battery controller=0

# Bước 2: Xác nhận cache policy hiện tại đã chuyển sang Write-Through
omreport storage vdisk controller=0 | grep "Cache Policy"

# Bước 3: Nếu battery hỏng hoàn toàn — đặt hàng thay thế khẩn cấp
# Trong lúc chờ, đánh giá impact và cân nhắc maintenance window để giảm tải

# Bước 4: Sau khi thay battery và battery đã sạc đầy/tự kiểm tra xong,
# xác nhận cache policy tự động chuyển lại Write-Back
omreport storage vdisk controller=0 | grep "Cache Policy"
```

**4. Bài học kinh nghiệm**
Cơ chế tự bảo vệ của RAID controller (chuyển Write-Through khi BBU lỗi) là hành vi ĐÚNG và AN TOÀN — vấn đề không nằm ở việc controller "làm gì" mà ở việc không ai giám sát trạng thái BBU nên sự cố chỉ được phát hiện qua triệu chứng gián tiếp (server chậm) thay vì cảnh báo trực tiếp.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát trạng thái battery/supercap của RAID controller như một chỉ số sức khỏe hạ tầng riêng biệt, không chỉ dựa vào việc phát hiện qua hiệu năng ứng dụng suy giảm
- Với server production quan trọng, ưu tiên dùng công nghệ Supercap + Flash-backed cache (không cần pin hóa học, tuổi thọ cao hơn, ít lỗi hơn BBU truyền thống) khi có lựa chọn từ nhà sản xuất
- Đưa việc kiểm tra tình trạng BBU vào checklist bảo trì phần cứng định kỳ hàng quý, không đợi hệ thống tự cảnh báo

---

### Case 3: Fujitsu PRIMERGY — lỗi ECC memory tích lũy gây corruption âm thầm

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED → 🔴 nếu dẫn đến corruption dữ liệu ứng dụng. Server thỉnh thoảng gặp lỗi ứng dụng bất thường, khó tái hiện (segfault ngẫu nhiên, tính toán sai kết quả không nhất quán) mà không tìm được nguyên nhân ở tầng phần mềm.

**2. Nguyên nhân**
Memory ECC (Error-Correcting Code) tự động sửa lỗi bit đơn (single-bit error) mà không báo cho hệ điều hành biết trừ khi được giám sát chủ động qua BMC/iRMC — khi số lỗi ECC tích lũy trên một module RAM tăng dần, đây là dấu hiệu sớm của thanh RAM sắp hỏng hoàn toàn (lỗi đa bit không sửa được, gây corruption thực sự hoặc crash).

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra log lỗi ECC qua iRMC/BMC
ipmitool sel list | grep -i "memory\|ecc\|correctable"

# Bước 2: Trên Linux, kiểm tra qua EDAC (Error Detection and Correction) subsystem
edac-util -v
cat /sys/devices/system/edac/mc/mc0/csrow*/ce_count

# Bước 3: Xác định module RAM cụ thể có tỷ lệ lỗi tăng dần theo thời gian
# (so sánh ce_count giữa các lần kiểm tra để thấy xu hướng, không chỉ giá trị tức thời)

# Bước 4: Lên kế hoạch thay module RAM có xu hướng lỗi tăng, ưu tiên trong
# maintenance window gần nhất trước khi chuyển thành lỗi không sửa được
```

**4. Bài học kinh nghiệm**
ECC memory là lớp bảo vệ tuyệt vời nhưng cũng là "con dao hai lưỡi về nhận thức" — vì nó âm thầm sửa lỗi nên đội vận hành dễ tưởng hệ thống hoàn toàn khỏe mạnh trong khi thực chất phần cứng đang suy giảm dần, chỉ đến khi ECC không còn sửa được nữa mới biểu hiện thành sự cố rõ ràng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát chủ động số lượng correctable ECC error theo xu hướng thời gian (qua EDAC trên Linux hoặc công cụ tương đương), coi đây là chỉ số sức khỏe phần cứng bắt buộc phải theo dõi, không chỉ dựa vào việc hệ thống "không crash"
- Alert khi tỷ lệ ECC error trên một module tăng bất thường so với baseline, thay vì chỉ alert khi vượt ngưỡng tuyệt đối cố định
- Định kỳ chạy memtest hoặc công cụ chẩn đoán phần cứng của hãng (Fujitsu ServerView Diagnostic Tool) trong kỳ bảo trì để phát hiện sớm module RAM có nguy cơ

---

### Case 4: IBM Power/AIX — Service Processor mất kết nối, không thể quản lý LPAR từ xa

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL về khả năng vận hành (không nhất thiết ảnh hưởng ứng dụng đang chạy ngay lập tức, nhưng mất hoàn toàn khả năng quản lý từ xa). HMC (Hardware Management Console) không thể kết nối tới Service Processor của server, không thể thực hiện các thao tác LPAR (dynamic LPAR, restart, power management) từ xa.

**2. Nguyên nhân**
Thường do lỗi mạng quản lý riêng (dành cho HMC-to-FSP communication) bị gián đoạn, hoặc Flexible Service Processor (FSP) bị treo do lỗi firmware, cần được phân biệt rõ với sự cố ở tầng LPAR/AIX (vốn vẫn có thể đang hoạt động bình thường).

**3. Thủ tục xử lý**
```bash
# Bước 1: Từ HMC, kiểm tra trạng thái kết nối tới managed system
lssyscfg -r sys -F name,state

# Bước 2: Kiểm tra kết nối mạng vật lý tới cổng quản lý FSP (thường là cổng riêng, không chung LAN production)
ping <fsp_ip_address>

# Bước 3: Nếu network OK nhưng vẫn không kết nối được — FSP có thể bị treo,
# cần reset FSP (đây là thao tác an toàn, KHÔNG ảnh hưởng đến LPAR đang chạy)
# Thực hiện qua nút vật lý trên server hoặc qua ASMI nếu còn truy cập được console local

# Bước 4: Sau khi FSP khởi động lại, xác nhận HMC kết nối lại và đồng bộ trạng thái
chsysstate -r sys -m <managed_system> -o rebuildsp
```

**4. Bài học kinh nghiệm**
Kiến trúc Power Systems tách biệt rõ ràng giữa tầng quản lý phần cứng (Service Processor) và tầng hệ điều hành (LPAR/AIX) — đây là điểm mạnh giúp reset FSP không ảnh hưởng ứng dụng đang chạy, nhưng cũng dễ gây hoảng loạn không cần thiết nếu đội vận hành không hiểu rõ sự tách biệt này khi thấy "mất kết nối quản lý".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đảm bảo mạng quản lý (HMC network) tách biệt vật lý hoặc VLAN riêng khỏi mạng production, có redundancy riêng, không phụ thuộc vào cùng switch/uplink với traffic ứng dụng
- Đào tạo đội vận hành phân biệt rõ sự cố "mất kết nối quản lý" (không ảnh hưởng ứng dụng) với sự cố "LPAR/ứng dụng ngừng hoạt động" (ảnh hưởng thực sự), tránh phản ứng thái quá hoặc thao tác nhầm khi hoảng loạn
- Giám sát riêng kết nối HMC-to-FSP như một hạng mục hạ tầng độc lập, alert sớm khi mất kết nối kéo dài dù ứng dụng vẫn hoạt động bình thường

---

## NHÓM B: HỆ ĐIỀU HÀNH — LINUX/SOLARIS/AIX (Case 5-8)

### Case 5: Linux OOM Killer giết nhầm tiến trình quan trọng (database/middleware)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Tiến trình Oracle/WebLogic/ứng dụng quan trọng đột ngột bị kill không rõ nguyên nhân từ góc nhìn ứng dụng — log ứng dụng chỉ thấy tiến trình "biến mất", trong khi thực chất là hành động chủ động của kernel Linux.

**2. Nguyên nhân**
Hệ thống cạn kiệt bộ nhớ khả dụng (RAM + swap) do một tiến trình khác (thường là batch job, cache ứng dụng không giới hạn, hoặc memory leak) tiêu thụ vượt mức, buộc kernel Linux kích hoạt OOM Killer để chọn và kill tiến trình theo thuật toán "oom_score" — thuật toán này không phải lúc nào cũng chọn đúng "thủ phạm" mà có thể chọn nhầm tiến trình quan trọng có mức sử dụng RAM cao (như database) làm nạn nhân.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận đây đúng là OOM Killer (không phải crash ứng dụng thông thường)
dmesg -T | grep -i "out of memory\|oom-killer\|killed process"
grep -i "oom" /var/log/messages

# Bước 2: Xác định tiến trình nào đã gây cạn bộ nhớ (không phải tiến trình bị kill)
# Xem trong log dmesg phần liệt kê toàn bộ tiến trình và oom_score tại thời điểm đó
dmesg -T | grep -A50 "invoked oom-killer" | grep -i "total-vm\|oom_score"

# Bước 3: Khởi động lại tiến trình bị kill (database/middleware) sau khi xác nhận
# nguyên nhân gốc đã được kiểm soát tạm thời (ví dụ kill tiến trình thủ phạm)

# Bước 4: Điều chỉnh oom_score_adj cho tiến trình quan trọng để giảm khả năng
# bị chọn làm nạn nhân trong tương lai (giải pháp tạm thời, không thay thế fix gốc)
echo -800 > /proc/<pid_database>/oom_score_adj
```

**4. Bài học kinh nghiệm**
OOM Killer là cơ chế tự bảo vệ cuối cùng của kernel khi hệ thống thực sự cạn kiệt bộ nhớ — sự xuất hiện của nó luôn là dấu hiệu của một vấn đề capacity/memory leak thực sự cần điều tra, không phải "sự cố ngẫu nhiên" có thể bỏ qua sau khi khởi động lại tiến trình.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình memory limit rõ ràng cho từng loại tiến trình (cgroups, systemd MemoryMax) để cô lập rủi ro, tránh một tiến trình "tệ" ảnh hưởng đến toàn hệ thống
- Với tiến trình cực kỳ quan trọng (database instance chính), cấu hình `oom_score_adj` bảo vệ chủ động ngay từ đầu, không đợi sự cố xảy ra mới điều chỉnh
- Giám sát xu hướng sử dụng bộ nhớ hệ thống (không chỉ per-process) và alert sớm khi tiệm cận ngưỡng nguy hiểm, kèm capacity planning định kỳ theo tăng trưởng workload

---

### Case 6: Filesystem corruption (XFS/ext4) sau unclean shutdown

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Sau khi server khởi động lại từ sự cố mất điện/crash đột ngột, filesystem không mount được tự động, hệ thống dừng ở chế độ emergency/rescue shell, toàn bộ dịch vụ trên server ngừng hoạt động.

**2. Nguyên nhân**
Journal của filesystem (XFS log hoặc ext4 journal) chưa kịp ghi hoàn chỉnh tại thời điểm mất điện, gây tình trạng không nhất quán giữa metadata và dữ liệu thực tế trên đĩa — mức độ nghiêm trọng tùy thuộc vào việc storage bên dưới có đảm bảo write barrier/cache flush đúng cách hay không.

**3. Thủ tục xử lý**
```bash
# Bước 1: Boot vào rescue mode, xác định filesystem bị lỗi
journalctl -xb | grep -i "fail\|error" | grep -i "mount\|xfs\|ext4"

# Bước 2a: Với XFS — chạy xfs_repair (KHÔNG mount trước khi repair)
xfs_repair -v /dev/mapper/vg_data-lv_oracle

# Bước 2b: Với ext4 — chạy fsck
fsck.ext4 -y /dev/mapper/vg_data-lv_oracle

# Bước 3: Sau khi repair, mount thử ở chế độ read-only trước để kiểm tra
mount -o ro /dev/mapper/vg_data-lv_oracle /mnt/check
ls -la /mnt/check   # Kiểm tra dữ liệu có còn nguyên vẹn không

# Bước 4: Nếu ổn, mount lại bình thường (read-write) và khởi động lại dịch vụ
mount /dev/mapper/vg_data-lv_oracle /u01
systemctl start <application_service>

# Bước 5: Nếu repair phát hiện mất dữ liệu (file trong lost+found) — đối chiếu
# với backup gần nhất để khôi phục phần bị mất
```

**4. Bài học kinh nghiệm**
`xfs_repair`/`fsck` có thể khôi phục filesystem "mountable" trở lại nhưng không đảm bảo dữ liệu ứng dụng (đặc biệt database) hoàn toàn nhất quán về mặt logic — đối với datafile database, luôn cần kiểm tra thêm ở tầng ứng dụng (ví dụ Oracle DBVERIFY/RMAN validate) sau khi filesystem đã repair xong.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đảm bảo UPS và cơ chế graceful shutdown cho mọi server production, đây là biện pháp phòng ngừa hiệu quả nhất vì loại bỏ tận gốc nguyên nhân unclean shutdown
- Với storage ảo hóa/SAN, xác nhận write barrier hoặc cache flush được cấu hình đúng theo khuyến nghị của cả hypervisor và storage vendor, tránh mất dữ liệu "trong bay" khi mất điện
- Với dữ liệu database, luôn có RMAN backup/validate định kỳ độc lập với backup filesystem, vì đây là lớp bảo vệ đáng tin cậy nhất khi filesystem-level corruption xảy ra

---

### Case 7: Solaris Zone — tranh chấp tài nguyên giữa non-global zone không giới hạn

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Nhiều non-global zone chạy trên cùng global zone, một zone đột ngột tiêu thụ CPU/memory cao bất thường (do batch job hoặc bug ứng dụng) làm ảnh hưởng hiệu năng của toàn bộ các zone khác trên cùng server vật lý.

**2. Nguyên nhân**
Zone được tạo mà không cấu hình resource controls (CPU cap, memory cap) rõ ràng — mặc định Solaris Zone chia sẻ tài nguyên "best-effort" giữa các zone, nên một zone "tham lam" hoàn toàn có thể chiếm dụng phần lớn tài nguyên hệ thống nếu không bị giới hạn.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác định zone nào đang tiêu thụ tài nguyên bất thường
prstat -Z
zonestat 5 1

# Bước 2: Kiểm tra cấu hình resource control hiện tại của zone thủ phạm
zonecfg -z <zone_name> info

# Bước 3: Áp dụng giới hạn CPU cap khẩn cấp để bảo vệ các zone khác
zonecfg -z <zone_name>
> add capped-cpu
> set ncpus=2
> end
> exit
zoneadm -z <zone_name> reboot   # hoặc apply động nếu hỗ trợ

# Bước 4: Cấu hình memory cap tương tự nếu nguyên nhân là bộ nhớ
zonecfg -z <zone_name>
> add capped-memory
> set physical=4G
> end
> exit
```

**4. Bài học kinh nghiệm**
Solaris Zone là công nghệ ảo hóa nhẹ (lightweight virtualization) chia sẻ chung kernel — điều này mang lại hiệu năng tốt nhưng đồng nghĩa việc thiếu resource control là rủi ro "hàng xóm ồn ào" (noisy neighbor) rất thực tế, khác với ảo hóa đầy đủ (như VMware/KVM) vốn có cô lập tài nguyên mạnh hơn theo mặc định.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc cấu hình resource control (capped-cpu, capped-memory) cho MỌI zone ngay từ khi tạo mới, không để mặc định "unlimited" cho môi trường production nhiều tenant
- Giám sát tài nguyên ở cấp global zone (tổng hợp toàn server) song song với giám sát từng non-global zone riêng lẻ, để phát hiện sớm xu hướng một zone đang "phình to" bất thường
- Với ứng dụng có khối lượng công việc dao động lớn (batch job định kỳ), cân nhắc dùng Fair Share Scheduler (FSS) kết hợp resource pools để đảm bảo phân bổ công bằng theo priority đã định trước

---

### Case 8: AIX LPAR — thiếu paging space gây hang toàn hệ thống

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. LPAR AIX đột ngột không phản hồi (hang), console hiển thị lỗi liên quan paging space, các tiến trình mới không thể khởi tạo, hệ thống có thể cần restart cứng để khôi phục.

**2. Nguyên nhân**
Paging space (swap) được cấu hình quá nhỏ so với nhu cầu thực tế của workload, hoặc `Real Memory Manager` không kịp giải phóng trang nhớ khi có đợt tăng đột biến nhu cầu bộ nhớ (ví dụ batch job lớn chạy song song ngoài dự kiến), dẫn đến tình trạng "thrashing" nghiêm trọng trước khi hang hoàn toàn.

**3. Thủ tục xử lý**
```bash
# Bước 1: Nếu còn truy cập được console — kiểm tra paging space usage
lsps -a
vmstat 1 5    # Xem cột "pi/po" (page in/out) tăng bất thường -> dấu hiệu thrashing

# Bước 2: Nếu hệ thống hoàn toàn không phản hồi — cần restart LPAR qua HMC
# (ghi nhận đầy đủ trạng thái trước khi restart để phân tích sau)

# Bước 3: Sau khi khởi động lại, tăng dung lượng paging space ngay
chps -s <số_LP_thêm> paging00
# Hoặc tạo thêm paging space mới trên LUN khác
mkps -a -n -s <size> rootvg hdisk1

# Bước 4: Xác định tiến trình/batch job đã gây tăng đột biến nhu cầu bộ nhớ
# qua log ứng dụng và lịch chạy job tại thời điểm sự cố
```

**4. Bài học kinh nghiệm**
Paging space trên AIX không chỉ là "bộ nhớ ảo dự phòng" mà còn đóng vai trò như một bộ đệm an toàn giúp hệ thống có thời gian phản ứng khi nhu cầu bộ nhớ tăng đột biến — cấu hình quá tiết kiệm paging space (để "tiết kiệm" dung lượng đĩa) là đánh đổi rủi ro ổn định hệ thống lấy một khoản dung lượng đĩa thường không đáng kể.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tuân theo khuyến nghị sizing paging space của IBM (thường tối thiểu bằng RAM, điều chỉnh theo workload thực tế), review định kỳ theo tăng trưởng khối lượng công việc
- Giám sát chỉ số `pi/po` (page in/out) và tỷ lệ sử dụng paging space liên tục, alert sớm khi có xu hướng tăng bất thường trước khi xảy ra thrashing nghiêm trọng
- Với batch job lớn định kỳ, có quy trình đăng ký lịch chạy rõ ràng để đội vận hành nắm được và tính toán capacity phù hợp, tránh nhiều job nặng chạy chồng chéo ngoài dự kiến

---

## NHÓM C: LOAD BALANCER & HA CLUSTER — HAPROXY/PACEMAKER/NGINX (Case 9-12)

### Case 9: HAProxy — backend server flapping do health check cấu hình sai

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Backend server liên tục bị đánh dấu DOWN rồi lại UP (flapping) dù ứng dụng phía sau vẫn hoạt động bình thường, gây gián đoạn traffic không cần thiết và log alert dồn dập gây "alert fatigue".

**2. Nguyên nhân**
Health check endpoint (`option httpchk`) trỏ tới một API/trang có thời gian phản hồi không ổn định (ví dụ endpoint truy vấn database nặng) thay vì một health check endpoint nhẹ chuyên dụng, hoặc timeout health check đặt quá ngắn so với thời gian phản hồi thực tế trong lúc tải cao.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra log HAProxy để xác nhận pattern flapping và nguyên nhân
tail -f /var/log/haproxy.log | grep -i "server.*down\|server.*up"

# Bước 2: Kiểm tra cấu hình health check hiện tại
grep -A5 "backend" /etc/haproxy/haproxy.cfg

# Bước 3: Test trực tiếp thời gian phản hồi của health check endpoint dưới tải
time curl -s http://backend-server/health

# Bước 4: Điều chỉnh cấu hình health check — dùng endpoint nhẹ chuyên dụng,
# tăng timeout/interval hợp lý, thêm "rise"/"fall" để tránh flapping do dao động ngắn hạn
```
```
backend web_servers
  option httpchk GET /healthz
  http-check expect status 200
  default-server inter 3s fall 3 rise 2 timeout check 5s
```

**4. Bài học kinh nghiệm**
Health check endpoint không nên phản ánh "toàn bộ sức khỏe ứng dụng" (bao gồm cả dependency như database) trừ khi đó là chủ đích thiết kế rõ ràng — một health check quá "nghiêm khắc" có thể gây flapping không cần thiết ngay cả khi phần lớn chức năng ứng dụng vẫn hoạt động tốt.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thiết kế endpoint health check chuyên dụng, nhẹ, phản hồi nhanh (không truy vấn dependency nặng), tách biệt rõ với endpoint kiểm tra "readiness" đầy đủ nếu cần
- Cấu hình `rise`/`fall` (số lần check liên tiếp trước khi đổi trạng thái) đủ lớn để tránh phản ứng thái quá với dao động tạm thời, cân bằng giữa phát hiện sự cố nhanh và tránh flapping
- Giám sát riêng tần suất flapping của từng backend server như một chỉ số cấu hình cần review, không chỉ xem health check là nhị phân "up/down" đơn thuần

---

### Case 10: Pacemaker/Corosync — Split-brain do STONITH không được cấu hình

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL — tương tự split-brain trong Data Guard nhưng ở tầng cluster hạ tầng. Cả hai node trong cluster HA cùng cho rằng mình là node active, cùng cố gắng mount cùng một shared storage hoặc cùng bind cùng một Virtual IP, gây corruption dữ liệu hoặc xung đột network nghiêm trọng.

**2. Nguyên nhân**
STONITH (Shoot The Other Node In The Head — cơ chế fencing của Pacemaker) không được cấu hình hoặc bị tắt (`stonith-enabled=false`, thường do đội triển khai ban đầu tắt để "đơn giản hóa" test mà quên bật lại cho production), khiến khi mất kết nối heartbeat giữa hai node (nhưng cả hai vẫn đang chạy), không có cơ chế nào "buộc tắt" node còn lại để tránh xung đột.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận tình trạng split-brain đang xảy ra
pcs status
# Kiểm tra cả hai node cùng báo "resource started" cho cùng một resource

# Bước 2: Xử lý khẩn cấp — cô lập một trong hai node ngay lập tức (thủ công)
# Chọn node "sai" (không nên giữ vai trò active) để tắt network/shutdown
ssh node2 "systemctl stop corosync pacemaker"

# Bước 3: Sau khi chỉ còn 1 node active — kiểm tra và cấu hình đúng STONITH
pcs stonith create fence_node1 fence_ipmilan pcmk_host_list="node1" \
  ipaddr="10.0.0.10" login="admin" passwd="xxx" op monitor interval="60s"
pcs property set stonith-enabled=true

# Bước 4: Khởi động lại node còn lại sau khi xác nhận cấu hình STONITH đã đúng,
# để nó tham gia lại cluster một cách an toàn
```

**4. Bài học kinh nghiệm**
Tắt STONITH để "dễ test" trong môi trường lab là thói quen nguy hiểm nếu không có quy trình kiểm soát bắt buộc bật lại trước khi go-live — đây là lỗi cấu hình tưởng như nhỏ nhưng hậu quả split-brain trong production có thể nghiêm trọng ngang một sự cố mất dữ liệu thực sự.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Coi `stonith-enabled=true` với fencing device hoạt động thực sự là điều kiện BẮT BUỘC trước khi bất kỳ cluster Pacemaker nào được đưa vào production, đưa vào checklist go-live không thể bỏ qua
- Test fencing device định kỳ (không chỉ cấu hình một lần rồi thôi) để đảm bảo nó thực sự hoạt động khi cần — fencing device "cấu hình sai âm thầm" cũng nguy hiểm không kém việc không cấu hình
- Giám sát property `stonith-enabled` và trạng thái fencing device như một phần của health check cluster định kỳ, alert ngay nếu phát hiện bị tắt ngoài kế hoạch

---

### Case 11: Pacemaker — resource kẹt ở trạng thái Started trên node sai sau failover

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Sau khi failover cluster, Pacemaker báo resource "Started" trên node mới nhưng ứng dụng thực tế không hoạt động (ví dụ Virtual IP không ping được, dịch vụ không lắng nghe) — cluster "nghĩ" mọi thứ ổn nhưng thực tế dịch vụ đã gián đoạn.

**2. Nguyên nhân**
Resource Agent (RA) script không kiểm tra đúng cách trạng thái thực tế của dịch vụ trong hàm `monitor`, hoặc có "resource stickiness"/constraint cấu hình sai khiến Pacemaker không tự động di chuyển resource sang node thực sự khỏe mạnh sau khi phát hiện lỗi.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái resource và lịch sử failure
pcs status --full
pcs resource failcount show <resource_name>

# Bước 2: Xác nhận thực tế dịch vụ có hoạt động đúng trên node hiện tại không
# (kiểm tra trực tiếp, không chỉ tin vào Pacemaker status)
ssh <current_node> "systemctl status <service>"

# Bước 3: Nếu resource agent không phản ánh đúng — buộc cleanup và di chuyển thủ công
pcs resource cleanup <resource_name>
pcs resource move <resource_name> <target_node>

# Bước 4: Điều tra và sửa resource agent script để hàm monitor kiểm tra
# chính xác trạng thái thực tế (không chỉ kiểm tra process đang chạy mà còn
# phải kiểm tra dịch vụ thực sự phản hồi đúng)
```

**4. Bài học kinh nghiệm**
Pacemaker chỉ "biết" những gì Resource Agent báo cáo qua hàm `monitor` — nếu RA viết không đủ chặt chẽ (chỉ kiểm tra process tồn tại thay vì kiểm tra dịch vụ thực sự phản hồi đúng), cluster có thể báo cáo trạng thái sai lệch hoàn toàn so với thực tế, khiến toàn bộ giá trị của HA bị vô hiệu hóa một cách âm thầm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Kiểm thử kỹ Resource Agent trong nhiều kịch bản lỗi khác nhau (process chết, dịch vụ treo nhưng process vẫn còn, network lỗi) trước khi đưa vào production, không chỉ test happy-path
- Với resource agent tùy chỉnh, đảm bảo hàm `monitor` kiểm tra chức năng thực sự của dịch vụ (ví dụ curl vào health endpoint) thay vì chỉ kiểm tra `pgrep` process tồn tại
- Diễn tập failover định kỳ có kiểm tra đối chiếu giữa trạng thái Pacemaker báo cáo và trạng thái thực tế của ứng dụng, không chỉ tin tưởng dashboard cluster

---

### Case 12: Nginx — lỗi 502/504 hàng loạt do vượt giới hạn worker_connections

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, xuất hiện tập trung ở giờ cao điểm. Client nhận lỗi 502 Bad Gateway hoặc 504 Gateway Timeout hàng loạt dù backend server vẫn hoạt động bình thường và không quá tải.

**2. Nguyên nhân**
`worker_connections` (số kết nối tối đa mỗi worker process xử lý đồng thời) được cấu hình thấp hơn nhu cầu thực tế khi traffic tăng trưởng theo thời gian, kết hợp với `worker_processes` không được đặt phù hợp với số CPU core thực tế của server, khiến Nginx từ chối kết nối mới dù tài nguyên hệ thống (CPU/RAM) còn dư thừa nhiều.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra log lỗi Nginx tìm nguyên nhân cụ thể
tail -f /var/log/nginx/error.log | grep -i "worker_connections\|accept4\|too many open files"

# Bước 2: Kiểm tra cấu hình hiện tại và tài nguyên hệ thống thực tế
nginx -T | grep -E "worker_connections|worker_processes"
nproc
ulimit -n

# Bước 3: Điều chỉnh cấu hình phù hợp với tài nguyên và traffic thực tế
```
```nginx
worker_processes auto;
events {
  worker_connections 4096;
  use epoll;
}
```
```bash
# Bước 4: Đồng thời tăng file descriptor limit ở cấp OS (thường bị bỏ sót)
# /etc/security/limits.conf: nginx soft/hard nofile 65536
nginx -s reload
```

**4. Bài học kinh nghiệm**
`worker_connections` là một giới hạn "mềm" dễ bị quên khi traffic tăng trưởng dần theo thời gian — vì hệ thống vẫn hoạt động bình thường ở mức tải thấp/trung bình, vấn đề chỉ lộ ra đúng lúc traffic đạt đỉnh (thường là giờ cao điểm kinh doanh, thời điểm tệ nhất để phát hiện sự cố).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Load test định kỳ với traffic mô phỏng mức đỉnh dự kiến (và cao hơn 20-30% để có buffer), không chỉ dựa vào traffic trung bình hàng ngày để sizing cấu hình
- Giám sát số connection hiện tại so với `worker_connections` cấu hình như một chỉ số capacity, alert sớm khi tiệm cận ngưỡng thay vì đợi lỗi 502/504 xuất hiện
- Review lại cấu hình Nginx (worker_processes, worker_connections, file descriptor limit) định kỳ theo tăng trưởng traffic thực tế, coi đây là một phần của capacity planning tổng thể chứ không phải cấu hình "một lần rồi thôi"

---

## NHÓM D: CONTAINER ORCHESTRATION — KUBERNETES/DOCKER (Case 13-16)

### Case 13: Kubernetes — Pod CrashLoopBackOff do liveness probe cấu hình sai

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Pod liên tục bị Kubernetes restart (CrashLoopBackOff), ứng dụng không bao giờ đạt trạng thái ổn định đủ lâu để phục vụ traffic, gây gián đoạn dịch vụ hoàn toàn dù ứng dụng bên trong container thực chất hoạt động bình thường.

**2. Nguyên nhân**
Liveness probe được cấu hình với `initialDelaySeconds` quá ngắn so với thời gian khởi động thực tế của ứng dụng (đặc biệt ứng dụng Java/WebLogic cần vài chục giây đến vài phút để khởi động JVM và load ứng dụng) — Kubernetes coi ứng dụng "chết" vì chưa kịp phản hồi trong probe đầu tiên và kill container ngay khi nó đang trong quá trình khởi động bình thường.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận nguyên nhân qua describe pod
kubectl describe pod <pod_name> -n <namespace>
# Tìm phần "Events" - thường thấy "Liveness probe failed" lặp lại

# Bước 2: Kiểm tra thời gian khởi động thực tế của ứng dụng qua log
kubectl logs <pod_name> -n <namespace> --previous
# Xác định thời điểm ứng dụng thực sự sẵn sàng (ví dụ "Server started" trong log)

# Bước 3: Điều chỉnh cấu hình probe phù hợp với thời gian khởi động thực tế
```
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 90
  periodSeconds: 15
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
```
```bash
# Bước 4: Apply lại và giám sát pod ổn định
kubectl apply -f deployment.yaml
kubectl get pods -w
```

**4. Bài học kinh nghiệm**
Liveness probe và Readiness probe phục vụ hai mục đích khác nhau nhưng thường bị nhầm lẫn cấu hình giống nhau — liveness quá "nhạy" (fail sớm) là nguyên nhân phổ biến nhất gây CrashLoopBackOff cho các ứng dụng có thời gian khởi động dài như WebLogic/JVM-based application.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đo đạc thời gian khởi động thực tế của ứng dụng trong môi trường staging/production-like trước khi cấu hình probe, không dùng giá trị mặc định/đoán chừng
- Cân nhắc dùng `startupProbe` (Kubernetes 1.16+) riêng cho ứng dụng khởi động chậm — cho phép thời gian khởi động dài hơn nhiều mà không ảnh hưởng đến độ nhạy của liveness probe sau khi đã chạy ổn định
- Review cấu hình probe như một phần bắt buộc của quy trình review trước khi deploy ứng dụng mới lên Kubernetes, không để mặc định generic cho mọi loại ứng dụng

---

### Case 14: Kubernetes — Node chuyển NotReady do Disk Pressure

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Node chuyển sang trạng thái `NotReady` với điều kiện `DiskPressure=True`, Kubernetes bắt đầu evict pod khỏi node này hàng loạt, gây gián đoạn dịch vụ trên toàn bộ pod đang chạy tại node đó.

**2. Nguyên nhân**
Disk trên node (thường là phân vùng chứa container image, log, hoặc ephemeral storage) đầy do image không được dọn dẹp (garbage collection không theo kịp tốc độ pull image mới), hoặc container ghi log không giới hạn dung lượng vào ephemeral storage của pod.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận điều kiện node và dung lượng disk thực tế
kubectl describe node <node_name> | grep -A5 "Conditions"
ssh <node> "df -h /var/lib/containerd /var/lib/kubelet"

# Bước 2: Kiểm tra image/container nào chiếm dụng nhiều dung lượng nhất
ssh <node> "crictl images | sort -k4 -h -r | head -20"
ssh <node> "du -sh /var/log/pods/* | sort -h -r | head -20"

# Bước 3: Xử lý khẩn cấp — dọn image không dùng thủ công
ssh <node> "crictl rmi --prune"

# Bước 4: Kiểm tra và điều chỉnh kubelet garbage collection threshold
# (trong kubelet config: imageGCHighThresholdPercent, imageGCLowThresholdPercent)
# đảm bảo GC kích hoạt sớm hơn trước khi đạt ngưỡng DiskPressure của node
```

**4. Bài học kinh nghiệm**
Disk Pressure là một trong những nguyên nhân "node eviction hàng loạt" gây bất ngờ nhất vì không liên quan trực tiếp đến CPU/Memory của ứng dụng — nhiều đội vận hành chỉ giám sát CPU/Memory của node mà bỏ qua giám sát disk usage, dẫn đến sự cố xuất hiện đột ngột không có cảnh báo sớm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát disk usage của node (đặc biệt phân vùng container runtime và kubelet) như một chỉ số sức khỏe node bắt buộc, ngang hàng với CPU/Memory, không chỉ dựa vào Kubernetes tự báo NotReady
- Cấu hình giới hạn log container (`--log-opt max-size`, `max-file` cho Docker, hoặc tương đương cho containerd) để tránh một container "nói nhiều" làm đầy disk node dùng chung
- Thiết lập resource quota/limit ephemeral-storage ở cấp namespace/pod để ngăn một pod chiếm dụng disk vượt mức cho phép, cô lập rủi ro giữa các team/ứng dụng khác nhau trên cùng cluster

---

### Case 15: Kubernetes — etcd cluster mất quorum, control plane ngừng phản hồi

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL nghiêm trọng nhất trong nhóm Container. `kubectl` không phản hồi, không thể tạo/sửa/xóa bất kỳ resource nào trong cluster (dù pod đang chạy vẫn tiếp tục hoạt động cho đến khi cần restart), về bản chất cluster mất khả năng tự quản lý.

**2. Nguyên nhân**
etcd là hệ cơ sở dữ liệu key-value dùng thuật toán đồng thuận Raft, cần đa số (quorum) thành viên hoạt động để chấp nhận ghi — khi mất quá nửa số node etcd (ví dụ 2/3 node etcd cùng gặp sự cố mạng/hardware đồng thời, hoặc disk I/O quá chậm khiến etcd tự đánh giá là "unhealthy"), cluster mất quorum và toàn bộ control plane ngừng hoạt động.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận trạng thái etcd cluster
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health --cluster

# Bước 2: Xác định số node etcd còn sống và có đạt quorum không (cần >50%)
ETCDCTL_API=3 etcdctl member list

# Bước 3a: Nếu chỉ tạm thời mất kết nối — khôi phục kết nối/khởi động lại node etcd bị lỗi
systemctl restart etcd

# Bước 3b: Nếu mất vĩnh viễn một node — remove member cũ và add node mới
ETCDCTL_API=3 etcdctl member remove <member_id_cu>
ETCDCTL_API=3 etcdctl member add <new_node_name> --peer-urls=https://<new_ip>:2380

# Bước 4: Nếu mất quorum hoàn toàn không thể khôi phục — restore từ etcd snapshot backup
# (kịch bản xấu nhất, cần backup định kỳ được chuẩn bị từ trước)
etcdctl snapshot restore /backup/etcd-snapshot.db --data-dir /var/lib/etcd-restored
```

**4. Bài học kinh nghiệm**
etcd là "trái tim" của mọi Kubernetes cluster nhưng thường bị đối xử như một thành phần "cài rồi quên" — số lượng node etcd (thường 3 hoặc 5, luôn là số lẻ) và việc phân tán chúng ra các failure domain khác nhau (rack, AZ) quan trọng ngang với việc thiết kế HA cho chính ứng dụng chạy trên cluster.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Luôn triển khai etcd với số lượng node lẻ (3 hoặc 5) phân tán trên các failure domain độc lập (rack/AZ khác nhau), tránh đặt đa số node etcd cùng một điểm lỗi vật lý
- Backup etcd snapshot định kỳ (tối thiểu hàng ngày cho cluster quan trọng) và test restore trong môi trường riêng biệt, đây là "van an toàn" cuối cùng khi mất quorum không thể khôi phục
- Giám sát riêng sức khỏe etcd (latency, số node healthy, disk I/O) như một hạng mục ưu tiên cao nhất trong toàn bộ hệ thống giám sát Kubernetes, vì sự cố etcd ảnh hưởng đến toàn bộ khả năng quản lý cluster

---

### Case 16: Docker — dung lượng disk phình to không kiểm soát do log container

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, có thể leo thang thành ngừng dịch vụ nếu disk đầy hoàn toàn. Server chạy Docker (không dùng Kubernetes) đột ngột cảnh báo disk đầy dù không có thay đổi rõ ràng về số lượng container hay dữ liệu ứng dụng.

**2. Nguyên nhân**
Docker mặc định dùng `json-file` log driver không giới hạn kích thước — một container ghi log liên tục với tốc độ cao (đặc biệt log ở mức DEBUG hoặc có bug ghi log lặp vô hạn) có thể tạo file log khổng lồ tại `/var/lib/docker/containers/<id>/<id>-json.log` mà không ai để ý vì nó nằm sâu trong thư mục hệ thống, không phải đường dẫn log ứng dụng thông thường.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác định container/log file nào chiếm dụng nhiều dung lượng nhất
du -sh /var/lib/docker/containers/*/*-json.log | sort -h -r | head -10

# Bước 2: Xử lý khẩn cấp — truncate log file đang quá lớn (an toàn, không cần
# restart container, Docker vẫn tiếp tục ghi vào cùng file handle)
truncate -s 0 /var/lib/docker/containers/<container_id>/<container_id>-json.log

# Bước 3: Cấu hình giới hạn log cho container liên quan (cần restart để áp dụng)
docker update --log-opt max-size=100m --log-opt max-file=3 <container_name>

# Bước 4: Cấu hình mặc định cho toàn bộ Docker daemon (áp dụng cho container mới)
# /etc/docker/daemon.json:
```
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```
```bash
systemctl restart docker
```

**4. Bài học kinh nghiệm**
Log container là một trong những nguyên nhân "âm thầm" phổ biến nhất gây đầy disk trên host chạy Docker — vì log nằm trong thư mục quản lý nội bộ của Docker (không phải đường dẫn log ứng dụng quen thuộc), đội vận hành thường không nghĩ đến việc kiểm tra ở đây đầu tiên khi điều tra sự cố đầy disk.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình `max-size`/`max-file` mặc định cho Docker daemon ngay từ khi cài đặt (`/etc/docker/daemon.json`), không để mặc định "không giới hạn" cho bất kỳ môi trường production nào
- Giám sát dung lượng thư mục `/var/lib/docker` như một hạng mục riêng biệt trong disk monitoring, không chỉ giám sát disk usage tổng quát của filesystem gốc
- Khuyến khích ứng dụng xuất log ra stdout/stderr theo chuẩn (để Docker log driver quản lý tập trung, có thể tích hợp thêm log aggregator như Fluentd/Loki) thay vì tự ghi file log riêng bên trong container không được quản lý

---

## NHÓM E: MIDDLEWARE — ORACLE WEBLOGIC SERVER (Case 17-20)

### Case 17: WebLogic Managed Server kẹt ở trạng thái ADMIN sau crash

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Sau khi Managed Server crash và được khởi động lại (tự động hoặc thủ công), server chuyển vào trạng thái `ADMIN` thay vì `RUNNING` — server không phục vụ traffic ứng dụng dù tiến trình JVM đang chạy và "trông" như đang hoạt động.

**2. Nguyên nhân**
WebLogic tự động chuyển Managed Server sang trạng thái ADMIN khi phát hiện có vấn đề trong quá trình khởi động (thường do một hoặc nhiều resource — JDBC DataSource, JMS, Deployment — không khởi tạo thành công), đây là cơ chế "an toàn" ngăn server phục vụ traffic khi chưa sẵn sàng hoàn toàn thay vì để nó chạy ở trạng thái nửa vời.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra log server để xác định resource nào khởi tạo thất bại
tail -200 $DOMAIN_HOME/servers/<managed_server>/logs/<managed_server>.log | grep -i "error\|failed"

# Bước 2: Kiểm tra trạng thái các resource qua WLST
java weblogic.WLST
connect('weblogic','password','t3://adminserver:7001')
domainRuntime()
cd('ServerRuntimes/<managed_server>')
cmo.getState()

# Bước 3: Xác định và khắc phục resource lỗi (ví dụ JDBC DataSource không kết nối
# được database — kiểm tra connectivity, credential trước)

# Bước 4: Sau khi khắc phục nguyên nhân gốc, chuyển server sang RUNNING qua WLST
cd('/')
serverRuntime = getMBean('/ServerRuntimes/<managed_server>')
serverLifeCycleRuntime = serverRuntime.getServerLifeCycleRuntime()
serverLifeCycleRuntime.resume()
```

**4. Bài học kinh nghiệm**
Trạng thái ADMIN không phải là "lỗi" theo nghĩa thông thường mà là một cơ chế bảo vệ hợp lý của WebLogic — vấn đề thực sự luôn nằm ở resource/dependency thất bại phía sau, cần điều tra đúng nguyên nhân gốc thay vì chỉ cố "ép" server chuyển sang RUNNING mà chưa giải quyết vấn đề nền tảng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đảm bảo mọi JDBC DataSource cấu hình với `Test Connections on Reserve` và connection retry hợp lý, giảm khả năng khởi động server thất bại do vấn đề kết nối database tạm thời
- Giám sát trạng thái server (`RUNNING`/`ADMIN`/`FAILED`) qua Node Manager hoặc monitoring tool tích hợp, alert ngay khi phát hiện server ở trạng thái khác RUNNING sau một khoảng thời gian hợp lý kể từ lúc khởi động
- Review log khởi động của mọi Managed Server sau mỗi lần restart theo kế hoạch (patching, bảo trì), xác nhận đạt RUNNING hoàn toàn trước khi coi bảo trì hoàn tất

---

### Case 18: WebLogic — JDBC Connection Pool cạn kiệt do connection leak

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Ứng dụng báo lỗi `weblogic.common.resourcepool.ResourceLimitException: No resources currently available` — không còn connection database nào khả dụng trong pool, mọi request mới cần truy cập database đều thất bại.

**2. Nguyên nhân**
Code ứng dụng không đóng (`close()`) connection JDBC đúng cách trong mọi nhánh xử lý (đặc biệt thiếu try-finally hoặc try-with-resources khi có exception xảy ra giữa chừng), khiến connection bị "rò rỉ" dần khỏi pool theo thời gian cho đến khi cạn kiệt hoàn toàn.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận pool đã cạn kiệt qua WLST hoặc Console
# Console: Services > JDBC > Data Sources > <pool_name> > Monitoring
# Kiểm tra "Active Connections Current Count" so với "Maximum Capacity"

# Bước 2: Bật tính năng "Leak Profiling" tạm thời để xác định vị trí code gây leak
# (Console: Data Source > Configuration > Connection Pool > Inactive Connection Timeout,
# và bật "Profile Connection Leak Timeout Seconds")

# Bước 3: Xử lý khẩn cấp — tăng tạm Maximum Capacity của pool để giảm áp lực ngay
# (đây CHỈ là biện pháp câu giờ, không phải fix triệt để)

# Bước 4: Với connection bị leak xác định được qua stack trace, phối hợp
# team phát triển fix code (đảm bảo đóng connection trong finally block)
# và deploy bản vá, sau đó theo dõi lại pool để xác nhận không còn leak
```

**4. Bài học kinh nghiệm**
Connection pool cạn kiệt gần như luôn là triệu chứng của bug ở tầng code ứng dụng (thiếu quản lý resource đúng cách), không phải vấn đề cấu hình WebLogic — tăng kích thước pool là biện pháp tạm thời hợp lý để duy trì dịch vụ trong lúc điều tra, nhưng không giải quyết nguyên nhân gốc và pool sẽ cạn kiệt trở lại nếu leak vẫn tồn tại.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Bắt buộc chuẩn coding sử dụng try-with-resources (Java 7+) cho mọi thao tác JDBC trong review code, đảm bảo connection luôn được đóng dù có exception xảy ra
- Cấu hình `Inactive Connection Timeout` hợp lý ở tầng pool như một lớp bảo vệ bổ sung, tự động thu hồi connection bị giữ quá lâu bất thường mà không cần đợi ứng dụng tự giải phóng
- Giám sát liên tục tỷ lệ Active Connections/Maximum Capacity theo xu hướng thời gian, phát hiện sớm xu hướng tăng dần đều (dấu hiệu leak) trước khi pool cạn kiệt hoàn toàn và ảnh hưởng người dùng cuối

---

### Case 19: WebLogic — Node Manager mất kết nối, không thể failover cluster

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED về khả năng vận hành (ứng dụng đang chạy có thể vẫn hoạt động bình thường, nhưng mất khả năng quản lý/failover tự động). Admin Console không thể start/stop/restart Managed Server từ xa qua Node Manager, hiển thị trạng thái "Node Manager Not Reachable".

**2. Nguyên nhân**
Node Manager service trên máy chủ vật lý/VM bị crash hoặc SSL handshake giữa Admin Server và Node Manager thất bại (thường do certificate hết hạn hoặc `nodemanager.properties` cấu hình sai sau khi có thay đổi bảo mật hạ tầng), khiến kênh giao tiếp quản lý bị cắt đứt dù chính Managed Server vẫn đang chạy độc lập.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái Node Manager trên máy chủ liên quan
ps -ef | grep NodeManager
tail -100 $WL_HOME/common/nodemanager/nodemanager.log

# Bước 2: Nếu process đã chết — khởi động lại Node Manager
cd $WL_HOME/server/bin
nohup ./startNodeManager.sh > nodemanager_startup.log 2>&1 &

# Bước 3: Nếu process vẫn chạy nhưng SSL handshake lỗi — kiểm tra certificate
keytool -list -v -keystore $DOMAIN_HOME/security/DemoIdentity.jks | grep "Valid"

# Bước 4: Nếu certificate hết hạn — tạo lại và cập nhật cấu hình cho cả
# Admin Server và Node Manager, đồng bộ trên tất cả các máy chủ trong domain
```

**4. Bài học kinh nghiệm**
Node Manager là "kênh điều khiển" (control plane) riêng biệt với chính ứng dụng đang chạy trên Managed Server — tương tự bài học từ Case 4 (FSP trên IBM Power), cần phân biệt rõ "mất khả năng quản lý từ xa" với "ứng dụng thực sự ngừng hoạt động" để tránh phản ứng thái quá không cần thiết.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát riêng trạng thái Node Manager (process alive, SSL handshake thành công) như một thành phần hạ tầng độc lập, không gộp chung với giám sát sức khỏe ứng dụng trên Managed Server
- Quản lý vòng đời certificate SSL của Node Manager một cách chủ động (theo dõi ngày hết hạn, gia hạn trước thời hạn), tránh để hết hạn bất ngờ gây gián đoạn kênh quản lý
- Cấu hình Node Manager chạy như một service hệ điều hành (systemd/init script) có auto-restart, giảm rủi ro process chết mà không được phát hiện và khởi động lại kịp thời

---

### Case 20: WebLogic — Heap Out of Memory gây GC pause storm định kỳ

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, ảnh hưởng theo chu kỳ dễ nhận diện (thường lặp lại vài giờ một lần). Ứng dụng định kỳ "đứng hình" vài giây đến vài chục giây (thời gian phản hồi tăng vọt đồng loạt), sau đó tự phục hồi bình thường — pattern lặp lại đều đặn theo thời gian.

**2. Nguyên nhân**
Heap size JVM không đủ cho khối lượng object được tạo ra liên tục (do memory leak trong code ứng dụng, cache không giới hạn, hoặc đơn giản là heap size được cấu hình quá nhỏ so với tải thực tế), khiến Garbage Collector phải chạy Full GC (stop-the-world) thường xuyên để giải phóng đủ bộ nhớ, mỗi lần Full GC làm "đóng băng" toàn bộ ứng dụng trong khoảng thời gian đó.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra GC log để xác nhận pattern Full GC lặp lại
tail -f $DOMAIN_HOME/servers/<managed_server>/logs/gc.log | grep "Full GC"

# Bước 2: Chụp heap dump tại thời điểm heap usage cao để phân tích
jmap -dump:live,format=b,file=/tmp/heap_dump.hprof <pid>

# Bước 3: Phân tích heap dump (dùng Eclipse MAT hoặc công cụ tương đương)
# xác định object nào chiếm dụng bộ nhớ nhiều bất thường (dấu hiệu memory leak)

# Bước 4a: Xử lý tạm thời — tăng heap size nếu server còn tài nguyên vật lý
# (chỉ giảm tần suất Full GC, không giải quyết leak nếu có)
# JAVA_OPTIONS="-Xms4g -Xmx4g -XX:+UseG1GC"

# Bước 4b: Xử lý triệt để — phối hợp team phát triển fix memory leak dựa trên
# kết quả phân tích heap dump, hoặc giới hạn cache size nếu nguyên nhân là cache
```

**4. Bài học kinh nghiệm**
Tăng heap size là phản xạ phổ biến nhất khi gặp GC pause nhưng thường chỉ "kéo dài thời gian sống" trước khi vấn đề tái diễn nếu nguyên nhân là memory leak thực sự — heap lớn hơn đồng nghĩa Full GC (khi xảy ra) sẽ mất nhiều thời gian hơn để hoàn tất, có thể khiến tình huống tệ hơn về mặt trải nghiệm người dùng dù tần suất giảm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát GC log liên tục (tần suất, thời lượng Full GC) như một chỉ số sức khỏe ứng dụng bắt buộc, không đợi người dùng phàn nàn về độ trễ mới điều tra
- Cân nhắc chuyển sang GC algorithm hiện đại (G1GC, ZGC cho JDK mới hơn) có đặc tính pause time thấp hơn đáng kể so với GC truyền thống, phù hợp cho ứng dụng cần độ trễ ổn định
- Load test định kỳ với khối lượng dữ liệu và thời gian chạy đủ dài (không chỉ test ngắn hạn) để phát hiện memory leak tiềm ẩn trước khi đưa ứng dụng vào production, vì nhiều leak chỉ biểu hiện rõ sau nhiều giờ/ngày vận hành liên tục

---

## TỔNG KẾT — KẾT LUẬN

```
Phân tích xu hướng qua 20 case (5 nhóm hạ tầng khác nhau):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Thiếu giám sát chủ động các chỉ số "âm thầm tích lũy"
   (ECC error, dead connection leak, log/disk growth, GC pause)  → 8/20 case
2. Cấu hình mặc định/tối giản không phù hợp production
   (STONITH tắt, probe timeout, log không giới hạn, health check)→ 6/20 case
3. Nhầm lẫn giữa "mất kết nối quản lý" và "mất dịch vụ thực sự"
   (FSP, Node Manager, iLO)                                     → 3/20 case
4. Thiếu resource isolation/capacity planning giữa các tenant
   (Zone, container, connection pool)                           → 2/20 case
5. Thiếu quy trình bắt buộc trước khi go-live (fencing, checklist)→ 1/20 case
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nguyên tắc phòng ngừa cốt lõi rút ra (áp dụng chung toàn bộ lớp hạ tầng):
- Cảnh báo phần cứng/hệ thống "âm thầm" (predictive failure, ECC error,
  connection leak, log growth) luôn đáng tin cậy hơn triệu chứng gián tiếp
  (ứng dụng chậm) — cần tích hợp và giám sát trực tiếp thay vì chờ hệ quả
- Mọi cơ chế bảo vệ tự động (RAID Write-Through khi BBU lỗi, WebLogic
  chuyển ADMIN state, K8s DiskPressure eviction) đều là hành vi ĐÚNG —
  vấn đề luôn nằm ở việc thiếu giám sát để phát hiện nguyên nhân gốc sớm,
  không phải ở bản thân cơ chế bảo vệ
- Cấu hình "mặc định để đơn giản hóa test" (STONITH tắt, log không giới
  hạn, health check sơ sài) là nợ kỹ thuật nguy hiểm nếu không có quy
  trình bắt buộc rà soát lại trước khi go-live production
- Tầng quản lý hạ tầng (iLO/FSP/Node Manager/HMC) luôn tách biệt với tầng
  dịch vụ thực tế — hiểu đúng ranh giới này giúp tránh phản ứng sai/thái
  quá khi chỉ mất kết nối quản lý mà dịch vụ vẫn đang chạy bình thường
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

So sánh nhanh trọng tâm giám sát theo từng lớp hạ tầng:
┌──────────────────┬────────────────────────────────────────┐
│ Phần cứng Server  │ iLO/iDRAC/iRMC alert, BBU/RAID, ECC     │
│ Hệ điều hành      │ OOM/kernel log, filesystem, paging/zone │
│ LB & HA Cluster   │ Health check flapping, STONITH, resource│
│ Container (K8s)   │ Probe config, disk pressure, etcd quorum│
│ WebLogic          │ Server state, connection pool, GC log   │
└──────────────────┴────────────────────────────────────────┘
```

---

## Tài liệu tham khảo
- HPE iLO 5 User Guide, Dell iDRAC9 Reference Guide, Fujitsu iRMC S6 Manual
- IBM Power Systems HMC and Service Processor Guide
- Red Hat Enterprise Linux Kernel Tuning Guide, Oracle Solaris Zones Administration Guide, IBM AIX System Management Guide
- HAProxy Configuration Manual, ClusterLabs Pacemaker Documentation, Nginx Admin Guide
- Kubernetes Documentation — Node Conditions, etcd Operations Guide
- Docker Documentation — Logging Drivers, Daemon Configuration
- Oracle Fusion Middleware WebLogic Server Administration Guide 14c
- www.tranvanbinh.vn — Khóa học Oracle & System Admin DBA A-Z Enterprise
