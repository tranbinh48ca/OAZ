---
name: middleware-deep-dive-troubleshoot-common-errors
description: >
  Case study đi sâu 20 lỗi thường gặp chuyên biệt trên Middleware/Hạ tầng:
  Load Balancer & VIP (HAProxy, Nginx, Keepalived VRRP), Cluster Resource
  Manager (Pacemaker/Corosync nâng cao: stickiness, token timeout,
  constraint, quorum policy), Container Orchestration (Kubernetes HPA,
  PodDisruptionBudget, Docker overlay network MTU, ImagePullBackOff),
  Message Queue (Kafka consumer rebalance storm, under-replicated
  partition, RabbitMQ queue unbounded growth, network partition), Redis
  (blocking command, Sentinel failover, maxmemory eviction, Cluster
  resharding stuck). Mỗi case trình bày đầy đủ: Vấn đề/Mức độ ảnh hưởng,
  Nguyên nhân, Thủ tục xử lý, Bài học kinh nghiệm, Biện pháp phòng ngừa
  từ sớm/từ xa.
  Kích hoạt khi hỏi về: lỗi HAProxy Nginx Keepalived chuyên sâu, VRRP
  split-brain, Pacemaker resource-stickiness, Corosync token timeout,
  Kubernetes HPA không scale, PodDisruptionBudget chặn drain, Docker
  overlay MTU, ImagePullBackOff, Kafka consumer rebalancing storm,
  Kafka under-replicated partition, RabbitMQ queue phình to, RabbitMQ
  network partition, Redis blocking command latency, Redis Sentinel
  failover, Redis maxmemory eviction, Redis Cluster CLUSTERDOWN,
  postmortem middleware production.
---

# SK09-CASE-MW · Đi sâu Case Study: Lỗi thường gặp chuyên biệt trên Middleware/Hạ tầng

**Phạm vi:** HAProxy 2.x, Nginx 1.24+, Keepalived, Pacemaker/Corosync, Kubernetes 1.28+, Docker, Apache Kafka 3.x, RabbitMQ 3.12+, Redis 7.x/Redis Cluster
**Tác giả:** Trần Văn Bình — VietDBA (Hotline/Zalo: 0902 912 888 — www.tranvanbinh.vn)
**Số lượng case:** 20 case thực chiến chuyên sâu Middleware, chia 5 nhóm

---

## KIẾN TRÚC TỔNG QUAN MIDDLEWARE TROUBLESHOOTING

```
Middleware & Infrastructure Services — Failure Domain Map (Deep Dive)
══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────┐  |
│  LOAD BALANCER & VIP LAYER (HAProxy/Nginx/Keepalived)          │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ VRRP Split-│  │ Session    │  │ SSL Cache/ │  Group A      │  |
│  │ Brain      │  │ Persistence│  │ Client IP  │  (1-4)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  CLUSTER RESOURCE MANAGER LAYER (Pacemaker/Corosync nâng cao)  │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Stickiness/│  │ Token      │  │ Constraint/│  Group B      │  |
│  │ Flapping   │  │ Timeout    │  │ Quorum     │  (5-8)        │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  CONTAINER ORCHESTRATION LAYER (K8s/Docker nâng cao)            │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ HPA/PDB    │  │ Overlay    │  │ Image Pull │  Group C      │  |
│  │ Scheduling │  │ Network MTU│  │ / Registry │  (9-12)       │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  MESSAGE QUEUE LAYER (Kafka/RabbitMQ)                           │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Consumer   │  │ Under-Rep. │  │ Queue      │  Group D      │  |
│  │ Rebalance  │  │ Partition  │  │ Growth/Split│ (13-16)      │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────┬───────────────┬───────────────┬─────────────────────┘  |
         │                │               │
         ▼                ▼               ▼
┌────────────────────────────────────────────────────────────┐  |
│  IN-MEMORY CACHE LAYER (Redis/Redis Cluster)                    │  |
│  ┌────────────┐  ┌────────────┐  ┌────────────┐              │  |
│  │ Blocking   │  │ Sentinel   │  │ Eviction/  │  Group E      │  |
│  │ Command    │  │ Failover   │  │ Resharding │  (17-20)      │  |
│  └────────────┘  └────────────┘  └────────────┘              │  |
└────────────────────────────────────────────────────────────┘  |

Severity: 🔴 CRITICAL (ngừng dịch vụ/mất dữ liệu) | 🟡 DEGRADED (suy giảm/rủi ro) | 🟢 MINOR (cảnh báo)
══════════════════════════════════════════════════════════════════
```

---

## MỤC LỤC CHI TIẾT THEO NHÓM

**NHÓM A: Load Balancer & VIP — HAProxy/Nginx/Keepalived (Case 1-4)**
- Case 1: 🔴 Keepalived VRRP split-brain — cả hai node cùng nhận MASTER và giữ VIP
- Case 2: 🟡 HAProxy mất session persistence (stick-table) sau khi reload cấu hình
- Case 3: 🟡 Nginx SSL session cache cạn kiệt gây chậm handshake dưới tải cao
- Case 4: 🟡 X-Forwarded-For không được bảo toàn đúng qua nhiều lớp proxy, sai client IP ở tầng ứng dụng

**NHÓM B: Cluster Resource Manager — Pacemaker/Corosync nâng cao (Case 5-8)**
- Case 5: 🟡 resource-stickiness cấu hình sai gây flapping failback qua lại giữa các node
- Case 6: 🔴 Corosync token timeout quá thấp gây fencing nhầm (false-positive)
- Case 7: 🟡 Colocation/Order constraint xung đột khiến resource không thể start
- Case 8: 🔴 no-quorum-policy cấu hình sai trên cluster 2 node gây đóng băng toàn cluster

**NHÓM C: Container Orchestration — K8s/Docker nâng cao (Case 9-12)**
- Case 9: 🟡 Horizontal Pod Autoscaler (HPA) không scale do thiếu metrics-server
- Case 10: 🔴 PodDisruptionBudget chặn hoàn toàn node drain trong bảo trì
- Case 11: 🟡 Docker overlay network MTU không khớp gây rớt gói tin ngắt quãng
- Case 12: 🔴 ImagePullBackOff hàng loạt do rate limit/token registry hết hạn

**NHÓM D: Message Queue — Kafka/RabbitMQ (Case 13-16)**
- Case 13: 🔴 Kafka consumer group rơi vào vòng lặp rebalancing storm liên tục
- Case 14: 🔴 Kafka under-replicated partition do broker disk chậm/ISR bị thu hẹp
- Case 15: 🔴 RabbitMQ queue phình to không giới hạn do không có consumer, kích hoạt Flow Control
- Case 16: 🔴 RabbitMQ cluster network partition (split-brain) do thiếu cấu hình pause_minority

**NHÓM E: In-Memory Cache — Redis/Redis Cluster (Case 17-20)**
- Case 17: 🔴 Lệnh blocking (KEYS/FLUSHALL) trên Redis đơn luồng gây đơ toàn bộ client
- Case 18: 🔴 Redis Sentinel không kích hoạt failover do quorum/down-after-milliseconds sai
- Case 19: 🟡 maxmemory-policy cấu hình sai gây evict nhầm key quan trọng
- Case 20: 🔴 Redis Cluster CLUSTERDOWN do quá trình resharding bị gián đoạn giữa chừng

---

## NHÓM A: LOAD BALANCER & VIP — HAPROXY/NGINX/KEEPALIVED (Case 1-4)

### Case 1: Keepalived VRRP split-brain — cả hai node cùng nhận MASTER và giữ VIP

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL, tương tự split-brain của Pacemaker (case09) nhưng ở tầng VRRP riêng biệt. Cả hai node Keepalived cùng chuyển sang trạng thái MASTER và cùng cố gắng ARP-announce cùng một Virtual IP, gây xung đột địa chỉ IP trên mạng — client kết nối chập chờn tùy vào node nào "thắng" ARP tại từng thời điểm.

**2. Nguyên nhân**
Multicast VRRP advertisement giữa hai node bị chặn hoặc gián đoạn (do firewall giữa hai node, hoặc switch không cho phép multicast traffic đi qua đúng cách), khiến mỗi node không còn "thấy" advertisement từ node kia và tự cho rằng mình là node duy nhất còn sống, tự động chuyển sang MASTER độc lập.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận cả hai node cùng đang ở trạng thái MASTER
journalctl -u keepalived | grep -i "state\|master\|backup"
ip addr show | grep <VIP>   # kiểm tra trên cả hai node xem VIP đang gán ở đâu

# Bước 2: Xác nhận multicast traffic giữa hai node có thông suốt không
tcpdump -i eth0 vrrp -n
# Nếu KHÔNG thấy advertisement từ node kia -> xác nhận nguyên nhân network

# Bước 3: Xử lý khẩn cấp — buộc một node về BACKUP thủ công để loại bỏ xung đột ngay
systemctl stop keepalived   # trên node cần loại bỏ khỏi MASTER tạm thời

# Bước 4: Khắc phục nguyên nhân gốc — mở multicast giữa hai node qua firewall,
# hoặc chuyển sang unicast VRRP (ổn định hơn qua nhiều loại hạ tầng mạng)
```
```
# keepalived.conf - chuyển sang unicast thay vì multicast
vrrp_instance VI_1 {
    unicast_src_ip 10.0.0.1
    unicast_peer {
        10.0.0.2
    }
}
```

**4. Bài học kinh nghiệm**
VRRP multicast dựa vào giả định hạ tầng mạng cho phép multicast traffic đi qua thông suốt giữa hai node — giả định này thường KHÔNG đúng trong môi trường cloud/ảo hóa hiện đại (nhiều nhà cung cấp cloud chặn multicast theo mặc định), khiến split-brain trở thành rủi ro thực tế cao hơn nhiều so với triển khai trên hạ tầng vật lý truyền thống.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Với môi trường cloud/ảo hóa, ưu tiên cấu hình VRRP ở chế độ `unicast` thay vì multicast ngay từ đầu, tránh hoàn toàn phụ thuộc vào khả năng hỗ trợ multicast của hạ tầng mạng bên dưới
- Kết hợp thêm cơ chế `track_script` kiểm tra tình trạng thực sự của ứng dụng/service phía sau (không chỉ dựa vào VRRP advertisement) để quyết định chuyển trạng thái MASTER/BACKUP chính xác hơn
- Test split-brain thực tế (chặn tạm network giữa hai node) trong môi trường staging để xác nhận hành vi thực sự của cấu hình Keepalived trước khi tin tưởng đưa vào production

---

### Case 2: HAProxy mất session persistence (stick-table) sau khi reload cấu hình

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Sau khi reload HAProxy để áp dụng thay đổi cấu hình (thêm backend, sửa rule), người dùng đang có session hoạt động đột nhiên bị route sang một backend server khác, gây mất trạng thái đăng nhập/giỏ hàng dù về lý thuyết reload không nên ảnh hưởng đến session đang chạy.

**2. Nguyên nhân**
`stick-table` (bảng lưu ánh xạ client → backend server để đảm bảo session persistence) mặc định được lưu TRONG BỘ NHỚ của tiến trình HAProxy — một lần `reload` thông thường (không phải `restart`) tạo tiến trình worker mới và tiến trình cũ dần thoát, nhưng nếu không cấu hình đúng cơ chế chia sẻ stick-table giữa các lần reload, bảng ánh xạ persistence bị mất hoàn toàn khi worker cũ kết thúc.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận HAProxy đang dùng stick-table cho session persistence
grep -A5 "stick-table\|stick match" /etc/haproxy/haproxy.cfg

# Bước 2: Kiểm tra cơ chế reload hiện tại (systemd reload vs hard restart)
systemctl status haproxy
cat /usr/lib/systemd/system/haproxy.service | grep -i reload

# Bước 3: Đảm bảo dùng cơ chế reload đúng chuẩn hỗ trợ seamless reload
# (HAProxy 2.0+ hỗ trợ tốt qua master-worker mode với socket chia sẻ)
haproxy -f /etc/haproxy/haproxy.cfg -c   # validate config trước
systemctl reload haproxy   # dùng reload (không phải restart) để giảm gián đoạn

# Bước 4: Với yêu cầu session persistence tuyệt đối không được mất qua reload,
# cân nhắc chuyển session state ra ngoài HAProxy (session lưu ở tầng ứng dụng/Redis)
# thay vì phụ thuộc hoàn toàn vào stick-table nội bộ của HAProxy
```

**4. Bài học kinh nghiệm**
`reload` của HAProxy giảm thiểu downtime đáng kể so với `restart` (không đóng hẳn kết nối đang có) nhưng KHÔNG đảm bảo bảo toàn 100% trạng thái nội bộ như stick-table trừ khi cấu hình đúng chuẩn — nhiều đội vận hành tin tưởng "reload luôn an toàn tuyệt đối" mà không kiểm chứng riêng cho từng loại state cụ thể đang dùng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Với ứng dụng có yêu cầu session persistence nghiêm ngặt, ưu tiên thiết kế kiến trúc "stateless" ở tầng backend (session lưu trong Redis/database dùng chung) thay vì phụ thuộc vào stick-table của load balancer, giảm rủi ro mất trạng thái qua mọi thao tác bảo trì
- Test thực tế hành vi reload với session đang hoạt động trong môi trường staging trước khi tin tưởng áp dụng quy trình tương tự trên production
- Lên lịch reload cấu hình HAProxy vào khung giờ thấp điểm nếu vẫn phụ thuộc vào stick-table nội bộ, giảm thiểu số lượng session bị ảnh hưởng

---

### Case 3: Nginx SSL session cache cạn kiệt gây chậm handshake dưới tải cao

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Dưới tải kết nối HTTPS cao, độ trễ thiết lập kết nối mới (đặc biệt TLS handshake) tăng đáng kể dù CPU server không quá tải hoàn toàn — client trải nghiệm độ trễ ban đầu cao hơn bình thường khi có nhiều kết nối mới đồng thời.

**2. Nguyên nhân**
`ssl_session_cache` (bộ nhớ đệm lưu TLS session để tái sử dụng, tránh phải thực hiện full handshake tốn kém cho mỗi kết nối) được cấu hình với kích thước quá nhỏ so với lưu lượng thực tế — khi cache đầy, session mới liên tục ghi đè session cũ (dù vẫn còn hiệu lực), buộc nhiều client phải thực hiện full handshake (tốn CPU/thời gian hơn đáng kể so với session resumption) thay vì tái sử dụng session đã có.

**3. Thủ tục xử lý**
```nginx
# Bước 1: Kiểm tra cấu hình ssl_session_cache hiện tại
grep "ssl_session" /etc/nginx/nginx.conf

# Bước 2: Ước tính kích thước cache cần thiết
# (mỗi 1MB cache lưu được khoảng 4000 session; tính theo số session đồng thời dự kiến)
ssl_session_cache shared:SSL:50m;   # ~200,000 session
ssl_session_timeout 10m;

# Bước 3: Với kiến trúc nhiều Nginx worker/nhiều server, cân nhắc dùng
# ssl_session_cache "shared" (đã có ở trên) để mọi worker process cùng truy cập
# chung một cache thay vì mỗi worker có cache riêng biệt

# Bước 4: Với kiến trúc nhiều server Nginx phía sau load balancer khác,
# cân nhắc thêm TLS session ticket (không cần lưu trạng thái phía server)
ssl_session_tickets on;
ssl_session_ticket_key /etc/nginx/ticket.key;
```
```bash
# Bước 5: Reload và giám sát lại tỷ lệ session resumption
nginx -s reload
# Theo dõi qua log hoặc công cụ giám sát TLS handshake ratio
```

**4. Bài học kinh nghiệm**
`ssl_session_cache` mặc định (thường khá nhỏ, chỉ vài MB) được thiết kế cho website lưu lượng thấp — với hệ thống production có lưu lượng HTTPS cao, đây là một tham số tuning dễ bị bỏ sót vì "trông có vẻ hoạt động bình thường" (không có lỗi rõ ràng) mà chỉ biểu hiện qua độ trễ tăng dần không dễ nhận thấy nếu không đo lường cụ thể.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Sizing `ssl_session_cache` dựa trên số lượng kết nối HTTPS đồng thời dự kiến thực tế, không dùng giá trị mặc định cho hệ thống production có lưu lượng đáng kể
- Kết hợp cả `ssl_session_cache` (server-side) và `ssl_session_tickets` (client-side, không cần trạng thái phía server) để tối đa hóa khả năng tái sử dụng session qua nhiều kiến trúc triển khai khác nhau
- Giám sát tỷ lệ TLS session resumption (qua log hoặc công cụ phân tích) như một chỉ số hiệu năng riêng biệt, không chỉ dựa vào độ trễ tổng thể chung chung để phát hiện vấn đề này

---

### Case 4: X-Forwarded-For không được bảo toàn đúng qua nhiều lớp proxy, sai client IP ở tầng ứng dụng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, ảnh hưởng đến logic nghiệp vụ phụ thuộc địa chỉ IP (rate limiting, phân tích địa lý, chặn IP độc hại). Ứng dụng ghi nhận SAI địa chỉ IP thực của client cuối — thường là IP của load balancer/proxy gần nhất thay vì IP client thật, khiến các tính năng dựa vào IP hoạt động không chính xác.

**2. Nguyên nhân**
Trong kiến trúc nhiều lớp proxy (Nginx → HAProxy → Application), mỗi lớp cần được cấu hình ĐÚNG để nối tiếp header `X-Forwarded-For` (thêm IP của chính nó vào cuối chuỗi, giữ nguyên các IP trước đó) thay vì GHI ĐÈ header — nếu một lớp bất kỳ trong chuỗi cấu hình sai (ghi đè thay vì append, hoặc không forward header này), thông tin IP client gốc bị mất hoàn toàn hoặc bị thay thế.

**3. Thủ tục xử lý**
```nginx
# Bước 1: Kiểm tra cấu hình từng lớp proxy trong chuỗi
# Nginx (lớp ngoài cùng, tiếp xúc trực tiếp client) — PHẢI set đúng
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Real-IP $remote_addr;
```
```
# HAProxy (lớp giữa) — dùng option forwardfor để APPEND, không GHI ĐÈ
backend app_servers
    option forwardfor
```
```bash
# Bước 2: Test qua toàn bộ chuỗi để xác nhận IP client được bảo toàn đúng
curl -H "X-Forwarded-For: 1.2.3.4" http://nginx-frontend/debug-headers
# Kiểm tra header nhận được ở tầng ứng dụng cuối cùng

# Bước 3: Ở tầng ứng dụng, đảm bảo LUÔN lấy IP đầu tiên trong chuỗi
# X-Forwarded-For (client gốc), không lấy IP cuối cùng (proxy gần nhất)
# và chỉ tin tưởng header này nếu request đến từ proxy nội bộ đáng tin cậy

# Bước 4: Với ứng dụng nhạy cảm bảo mật (rate limiting, chống DDoS), luôn
# validate rằng request chỉ có thể đến qua đúng chuỗi proxy đã định, không
# cho phép client bên ngoài tự set X-Forwarded-For giả mạo trực tiếp
```

**4. Bài học kinh nghiệm**
Header `X-Forwarded-For` không tự động "đúng" chỉ vì có mặt trong request — nó cần được TOÀN BỘ chuỗi proxy xử lý nhất quán, và nếu không kiểm soát chặt, client độc hại hoàn toàn có thể tự gửi header giả mạo để "spoofing" địa chỉ IP nếu ứng dụng tin tưởng mù quáng vào giá trị này mà không xác thực nguồn gốc request.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Kiểm kê và xác nhận cấu hình `X-Forwarded-For`/`X-Real-IP` nhất quán qua TOÀN BỘ chuỗi proxy (không chỉ lớp ngoài cùng), đưa vào checklist khi thêm bất kỳ lớp proxy mới nào vào kiến trúc
- Ở tầng ứng dụng, chỉ tin tưởng `X-Forwarded-For` nếu request đến từ dải IP nội bộ đáng tin cậy (proxy đã biết trước), tránh nguy cơ client bên ngoài giả mạo header để spoof IP hoặc bypass rate limiting
- Test end-to-end định kỳ (không chỉ khi setup lần đầu) để xác nhận IP client được truyền tải chính xác qua toàn bộ pipeline, đặc biệt sau mỗi lần thêm/thay đổi thành phần trong chuỗi proxy

---

## NHÓM B: CLUSTER RESOURCE MANAGER — PACEMAKER/COROSYNC NÂNG CAO (Case 5-8)

### Case 5: resource-stickiness cấu hình sai gây flapping failback qua lại giữa các node

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Sau khi node bị lỗi (đã failover đúng) phục hồi trở lại, resource TỰ ĐỘNG chuyển ngược (failback) về node cũ ngay lập tức — nếu node đó chưa thực sự ổn định hoàn toàn (ví dụ vừa reboot, dịch vụ phụ thuộc chưa sẵn sàng đầy đủ), gây gián đoạn dịch vụ thêm một lần nữa không cần thiết.

**2. Nguyên nhân**
`resource-stickiness` (giá trị quyết định mức độ "ưu tiên giữ nguyên vị trí hiện tại" của resource so với việc di chuyển về node có priority cao hơn) không được cấu hình hoặc đặt giá trị quá thấp — Pacemaker mặc định có xu hướng đặt resource về node có điểm ưu tiên (score) cao nhất ngay khi có thể, dẫn đến failback tự động ngay khi node cũ trở lại "khỏe mạnh" theo Pacemaker, dù chưa chắc đã sẵn sàng phục vụ traffic thực sự.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận resource-stickiness hiện tại
pcs resource defaults
pcs constraint

# Bước 2: Đặt resource-stickiness đủ cao để ưu tiên giữ nguyên vị trí hiện tại,
# tránh failback tự động không kiểm soát
pcs resource defaults resource-stickiness=200

# Bước 3: Nếu cần failback CÓ KIỂM SOÁT (không phải tự động ngay lập tức),
# thực hiện thủ công sau khi xác nhận node cũ đã thực sự sẵn sàng hoàn toàn
pcs resource move <resource_name> <node_cu>
pcs resource clear <resource_name>   # xóa constraint tạm thời sau khi ổn định

# Bước 4: Với hệ thống cần failback tự động nhưng có kiểm soát thời gian trễ,
# cân nhắc kết hợp thêm health check script xác nhận đầy đủ trước khi cho phép
```

**4. Bài học kinh nghiệm**
Failback tự động ngay lập tức không phải lúc nào cũng là hành vi mong muốn — một node vừa phục hồi từ sự cố có thể "khỏe mạnh" theo góc nhìn của Pacemaker (service đã start) nhưng chưa chắc đã sẵn sàng thực sự về mặt vận hành (cache chưa warm-up, kết nối downstream chưa ổn định), khiến failback vội vàng tạo ra gián đoạn dịch vụ lần thứ hai ngay sau khi vừa khôi phục từ lần đầu.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình `resource-stickiness` đủ cao (thường cao hơn giá trị chênh lệch priority giữa các node) làm tiêu chuẩn mặc định cho mọi cluster Pacemaker, tránh hành vi failback tự động không kiểm soát ngay khi node cũ vừa phục hồi
- Xây dựng quy trình thủ công có kiểm tra (checklist xác nhận node thực sự sẵn sàng) trước khi thực hiện failback có chủ đích, thay vì để hoàn toàn tự động
- Diễn tập kịch bản node lỗi rồi phục hồi (không chỉ diễn tập failover một chiều) để quan sát và xác nhận hành vi failback thực tế phù hợp với kỳ vọng vận hành

---

### Case 6: Corosync token timeout quá thấp gây fencing nhầm (false-positive)

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Node hoàn toàn khỏe mạnh (CPU/RAM/network đều bình thường) bị fence (tắt cưỡng bức) một cách "vô cớ" trong lúc có một đợt tải cao tạm thời (ví dụ backup job, patching) khiến nó phản hồi heartbeat chậm hơn bình thường trong thời gian ngắn.

**2. Nguyên nhân**
`token` timeout của Corosync (thời gian tối đa chờ phản hồi heartbeat từ một node trước khi coi là "mất kết nối") được đặt quá thấp so với đặc tính tải thực tế của hệ thống — trong các thời điểm tải CPU cao đột biến (không phải sự cố thực sự, chỉ là công việc nền hợp lệ), tiến trình Corosync có thể tạm thời không được lập lịch CPU kịp thời để gửi heartbeat đúng hạn, dẫn đến fencing nhầm.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận token timeout hiện tại
cat /etc/corosync/corosync.conf | grep -A3 "totem"

# Bước 2: Điều tra log tại thời điểm fencing xảy ra để xác nhận đây là
# false-positive (không có sự cố network/hardware thực sự)
journalctl -u corosync --since "<thời điểm sự cố>"
journalctl -u pacemaker --since "<thời điểm sự cố>" | grep -i fence

# Bước 3: Tăng token timeout hợp lý hơn (mặc định 1000ms thường quá thấp
# cho môi trường có tải CPU dao động, khuyến nghị 3000-5000ms tùy đặc thù)
```
```
# corosync.conf
totem {
    token: 5000
    token_retransmits_before_loss_const: 10
}
```
```bash
# Bước 4: Reload cấu hình Corosync trên toàn bộ node trong cluster (cần đồng bộ)
pcs cluster reload corosync
```

**4. Bài học kinh nghiệm**
Fencing (STONITH) là cơ chế bảo vệ CẦN THIẾT chống split-brain (như đã nhấn mạnh ở Case 10 của tài liệu case07 HA) — nhưng ngưỡng kích hoạt quá nhạy (token timeout thấp) biến chính cơ chế bảo vệ này thành nguồn gây gián đoạn dịch vụ không cần thiết, một dạng "false positive" tương tự các case giám sát quá nhạy đã gặp ở health check HAProxy (case09).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình `token` timeout dựa trên đặc tính tải THỰC TẾ của hệ thống (không dùng giá trị mặc định cho môi trường có tải CPU dao động lớn), cân bằng giữa phát hiện sự cố nhanh và tránh false-positive
- Với server chạy đồng thời batch job/backup nặng, đánh giá riêng tác động của các job này lên độ trễ heartbeat Corosync, điều chỉnh lịch chạy hoặc token timeout tương ứng
- Giám sát riêng tần suất fencing xảy ra theo thời gian, nếu có pattern lặp lại trùng với các sự kiện tải cao đã biết (backup, patching), đây là dấu hiệu rõ ràng cần điều chỉnh ngưỡng thay vì coi là sự cố hardware thực sự

---

### Case 7: Colocation/Order constraint xung đột khiến resource không thể start

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. Sau khi thêm một resource/constraint mới vào cluster Pacemaker, một resource khác (đã hoạt động ổn định từ trước) đột nhiên không thể start được ở bất kỳ node nào, dù bản thân service/resource đó hoàn toàn không có vấn đề kỹ thuật.

**2. Nguyên nhân**
Constraint mới thêm vào (colocation — yêu cầu 2 resource phải/không được cùng node, hoặc order — yêu cầu resource A phải start trước/sau resource B) tạo ra xung đột logic với các constraint đã tồn tại từ trước — Pacemaker không thể tìm ra một cấu hình vị trí thỏa mãn ĐỒNG THỜI tất cả các ràng buộc, dẫn đến việc "an toàn" nhất là không start resource đó ở đâu cả.

**3. Thủ tục xử lý**
```bash
# Bước 1: Liệt kê toàn bộ constraint hiện có để tìm xung đột logic
pcs constraint --full

# Bước 2: Kiểm tra lý do cụ thể resource không thể start
pcs status --full
crm_simulate -sL   # mô phỏng và giải thích quyết định placement của Pacemaker

# Bước 3: Xác định constraint mới thêm gây xung đột, xóa hoặc điều chỉnh lại
pcs constraint remove <constraint_id>

# Bước 4: Thêm lại constraint với logic đúng, kiểm tra kỹ tương tác với
# các constraint hiện có trước khi áp dụng vào production
pcs constraint colocation add <resource_A> with <resource_B> score=INFINITY
pcs constraint order start <resource_B> then start <resource_A>

# Bước 5: Xác nhận resource khởi động thành công sau khi sửa constraint
pcs resource cleanup <resource_name>
pcs status
```

**4. Bài học kinh nghiệm**
Constraint trong Pacemaker không hoạt động độc lập từng cái — chúng tương tác với NHAU theo một hệ thống điểm số (score) phức tạp, và một constraint "trông đúng riêng lẻ" hoàn toàn có thể tạo ra xung đột không lường trước khi kết hợp với các constraint đã tồn tại, đặc biệt trong cluster đã vận hành lâu năm với nhiều constraint tích lũy theo thời gian.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Dùng `crm_simulate` để mô phỏng tác động của constraint mới TRƯỚC khi áp dụng thực tế vào cluster production, phát hiện xung đột tiềm ẩn ngay trong giai đoạn lập kế hoạch
- Duy trì tài liệu rõ ràng giải thích MỤC ĐÍCH của từng constraint đang tồn tại trong cluster, giúp việc thêm constraint mới sau này có đủ ngữ cảnh để tránh xung đột không lường trước
- Review và dọn dẹp định kỳ các constraint không còn cần thiết (do resource đã bị gỡ bỏ hoặc thay đổi kiến trúc), giữ cho tập hợp constraint luôn gọn gàng và dễ suy luận logic

---

### Case 8: no-quorum-policy cấu hình sai trên cluster 2 node gây đóng băng toàn cluster

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Trong cluster chỉ có 2 node (kiến trúc phổ biến cho HA đơn giản), khi MỘT node bị mất kết nối (dù chỉ là sự cố network tạm thời), TOÀN BỘ cluster (bao gồm cả node còn lại vẫn hoàn toàn khỏe mạnh) ngừng phục vụ mọi resource — một dạng "tự sát" không cần thiết của cluster.

**2. Nguyên nhân**
Với cluster 2 node, khái niệm "quorum" (đa số) theo định nghĩa toán học thông thường không thể áp dụng trực tiếp (2 node, mất 1 node nghĩa là chỉ còn 50%, không phải đa số) — nếu `no-quorum-policy` giữ giá trị mặc định `stop` (dừng mọi resource khi mất quorum) mà không có cơ chế đặc biệt cho cluster 2 node (`two_node: 1` trong Corosync, hoặc quorum device), cluster sẽ tự dừng hoàn toàn ngay khi một node biến mất, kể cả khi node còn lại hoàn toàn có khả năng tiếp tục phục vụ.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận cấu hình quorum hiện tại
pcs quorum status
cat /etc/corosync/corosync.conf | grep -A5 "quorum"

# Bước 2: Với cluster 2 node, xác nhận đã bật chế độ two_node đúng cách
```
```
# corosync.conf
quorum {
    provider: corosync_votequorum
    two_node: 1
}
```
```bash
# Bước 3: Nếu chưa cấu hình đúng — sửa và reload
pcs cluster reload corosync

# Bước 4: Với yêu cầu độ tin cậy cao hơn, cân nhắc thêm Quorum Device (qdevice)
# — một "node ảo" thứ ba chỉ tham gia bỏ phiếu quorum, không chạy resource thực,
# giúp cluster 2 node có cơ chế quorum rõ ràng hơn (2/3 thay vì 1/2 mơ hồ)
pcs quorum device add model net host=<qdevice_host> algorithm=ffsplit
```

**4. Bài học kinh nghiệm**
Cluster 2 node là kiến trúc phổ biến vì đơn giản/tiết kiệm chi phí, nhưng bản chất toán học của "quorum" (cần đa số tuyệt đối) không phù hợp tự nhiên với số node chẵn nhỏ nhất này — đây là lý do vì sao Corosync cần một chế độ đặc biệt (`two_node`) để xử lý đúng, và bỏ qua bước cấu hình này là một trong những lỗi thiết lập ban đầu nghiêm trọng nhất cho cluster 2 node.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Với MỌI cluster 2 node, xác nhận `two_node: 1` đã được cấu hình đúng trong `corosync.conf` như một bước bắt buộc trong checklist triển khai, không bỏ sót
- Cân nhắc nghiêm túc việc thêm Quorum Device (một node/service nhẹ thứ ba chỉ tham gia quorum) cho cluster 2 node quan trọng, giúp loại bỏ hoàn toàn sự mơ hồ của quorum trên số node chẵn
- Diễn tập kịch bản mất một node trong cluster 2 node ngay sau khi triển khai, xác nhận node còn lại tiếp tục phục vụ đúng như kỳ vọng thay vì cluster tự dừng hoàn toàn ngoài ý muốn

---

## NHÓM C: CONTAINER ORCHESTRATION — K8S/DOCKER NÂNG CAO (Case 9-12)

### Case 9: Horizontal Pod Autoscaler (HPA) không scale do thiếu metrics-server

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED. HPA đã được cấu hình đúng (target CPU/memory utilization hợp lý) nhưng không bao giờ tự động tăng số lượng Pod dù ứng dụng đang chịu tải cao rõ ràng, khiến ứng dụng phải gánh toàn bộ tải với số Pod cố định ban đầu.

**2. Nguyên nhân**
HPA phụ thuộc hoàn toàn vào `metrics-server` (hoặc Prometheus Adapter cho custom metrics) để lấy dữ liệu CPU/memory usage thực tế của Pod — nếu `metrics-server` chưa được cài đặt, đang lỗi, hoặc không thể giao tiếp đúng với kubelet trên các node (thường do certificate hoặc network policy chặn), HPA hoàn toàn "mù" không có dữ liệu để đưa ra quyết định scale, dù chính đối tượng HPA vẫn tồn tại và "trông như đã cấu hình đúng".

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận metrics-server đang chạy và hoạt động đúng
kubectl get deployment metrics-server -n kube-system
kubectl top nodes
kubectl top pods -n <namespace>
# Nếu lệnh "top" báo lỗi hoặc không trả về dữ liệu -> xác nhận nguyên nhân

# Bước 2: Kiểm tra trạng thái HPA và lý do cụ thể không scale
kubectl describe hpa <hpa_name> -n <namespace>
# Tìm phần "Conditions" - thường thấy "FailedGetResourceMetric" nếu đây đúng nguyên nhân

# Bước 3: Kiểm tra log metrics-server để xác định lỗi cụ thể (thường TLS/certificate)
kubectl logs -n kube-system deployment/metrics-server

# Bước 4: Khắc phục (ví dụ thiếu --kubelet-insecure-tls cho môi trường self-signed cert,
# hoặc network policy chặn giao tiếp metrics-server -> kubelet)
kubectl edit deployment metrics-server -n kube-system
# Thêm args: --kubelet-insecure-tls (chỉ dùng khi hiểu rõ đánh đổi bảo mật)
```

**4. Bài học kinh nghiệm**
HPA là một tính năng "im lặng khi thất bại" — nó không báo lỗi ồn ào khi thiếu metrics, chỉ đơn giản không làm gì cả (giữ nguyên số Pod), khiến vấn đề dễ bị nhầm là "ứng dụng chưa cần scale" thay vì nhận ra đây là lỗi hạ tầng giám sát đang chặn hoàn toàn khả năng autoscaling.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Xác nhận `metrics-server` hoạt động đúng (qua `kubectl top`) như một phần của health check cluster định kỳ, không chỉ tin tưởng HPA object tồn tại là đủ
- Giám sát riêng các `Conditions` của mọi HPA quan trọng, alert khi có `FailedGetResourceMetric` hoặc điều kiện lỗi tương tự kéo dài, thay vì chỉ phát hiện qua triệu chứng gián tiếp (ứng dụng quá tải)
- Test khả năng scale thực tế của HPA (tạo tải giả lập) ngay sau khi triển khai ứng dụng mới lên cluster, xác nhận toàn bộ chuỗi metrics-server → HPA → scale hoạt động đúng trước khi tin tưởng cho production

---

### Case 10: PodDisruptionBudget chặn hoàn toàn node drain trong bảo trì

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL cho tiến độ bảo trì (không ảnh hưởng ứng dụng đang chạy). Lệnh `kubectl drain` (chuẩn bị đưa node vào bảo trì, di chuyển toàn bộ Pod sang node khác) bị TREO VÔ THỜI HẠN, không bao giờ hoàn tất, chặn toàn bộ kế hoạch bảo trì đã lên lịch.

**2. Nguyên nhân**
PodDisruptionBudget (PDB) — cấu hình giới hạn số lượng Pod tối đa được phép "gián đoạn" đồng thời cho một ứng dụng — được đặt quá chặt (ví dụ `minAvailable` bằng đúng số replica hiện có, không chừa margin nào), kết hợp với việc tất cả các Pod của ứng dụng đó đang tập trung trên CÙNG node cần drain, khiến Kubernetes không thể di chuyển bất kỳ Pod nào mà vẫn tuân thủ PDB.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận PDB nào đang chặn quá trình drain
kubectl get pdb -n <namespace>
kubectl describe pdb <pdb_name> -n <namespace>
# Xem "Allowed disruptions: 0" -> xác nhận đây là nguyên nhân

# Bước 2: Kiểm tra phân bố Pod hiện tại của ứng dụng bị ảnh hưởng
kubectl get pods -n <namespace> -o wide | grep <app_label>
# Nếu tất cả Pod đang trên cùng 1-2 node -> vấn đề phân bố kém càng làm PDB chặt hơn

# Bước 3a: Xử lý khẩn cấp — tăng tạm số replica để có buffer cho phép drain
kubectl scale deployment <app_name> -n <namespace> --replicas=<số_lớn_hơn>
# Sau khi Pod mới đã Running và phân bố đều, drain sẽ có thể tiến hành

# Bước 3b: Nếu không thể tăng replica ngay — cân nhắc tạm thời nới lỏng PDB
# (CHỈ trong maintenance window đã được phê duyệt, khôi phục lại ngay sau đó)
kubectl patch pdb <pdb_name> -n <namespace> -p '{"spec":{"minAvailable":1}}'

# Bước 4: Sau khi drain hoàn tất, khôi phục lại PDB về cấu hình an toàn ban đầu
```

**4. Bài học kinh nghiệm**
PodDisruptionBudget là một cơ chế bảo vệ ĐÚNG ĐẮN (ngăn quá nhiều Pod bị gián đoạn đồng thời gây downtime ứng dụng) nhưng cấu hình quá chặt kết hợp với thiết kế phân bố Pod kém (thiếu `podAntiAffinity` để trải đều Pod ra nhiều node) tạo ra tình huống tự mâu thuẫn — chính cơ chế bảo vệ ứng dụng lại ngăn cản hoạt động bảo trì hạ tầng cần thiết.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình PDB với biên độ hợp lý (`minAvailable` thấp hơn tổng số replica, hoặc dùng `maxUnavailable` thay vì `minAvailable` tùy ngữ cảnh), không đặt giá trị khiến "Allowed disruptions" luôn bằng 0 trong điều kiện vận hành bình thường
- Kết hợp `podAntiAffinity`/topology spread constraints để đảm bảo Pod của cùng một ứng dụng được phân bố đều ra nhiều node khác nhau, giảm khả năng toàn bộ replica bị dồn vào một node duy nhất cần bảo trì
- Test `kubectl drain` trong môi trường staging với PDB tương tự production trước khi lên lịch bảo trì thật, phát hiện sớm xung đột cấu hình trước khi ảnh hưởng đến maintenance window đã cam kết

---

### Case 11: Docker overlay network MTU không khớp gây rớt gói tin ngắt quãng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, đặc biệt khó chẩn đoán vì chỉ ảnh hưởng đến MỘT PHẦN traffic (gói tin lớn), traffic nhỏ vẫn hoạt động bình thường. Kết nối giữa các container trên overlay network (Docker Swarm hoặc CNI plugin tương tự trong Kubernetes) thỉnh thoảng bị timeout/rớt kết nối, đặc biệt với request/response có payload lớn.

**2. Nguyên nhân**
Overlay network (VXLAN hoặc công nghệ tunnel tương tự) đóng gói (encapsulate) gói tin gốc bên trong một lớp header bổ sung, làm giảm MTU khả dụng thực tế cho payload gốc — nếu MTU của overlay network interface không được điều chỉnh thấp hơn MTU vật lý tương ứng (thường cần trừ đi 50 byte cho VXLAN overhead), các gói tin lớn bị phân mảnh không đúng cách hoặc bị drop hoàn toàn bởi thiết bị mạng trung gian không hỗ trợ fragmentation.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận MTU hiện tại của overlay network interface
ip link show | grep -A2 "vxlan\|overlay"
docker network inspect <overlay_network_name> | grep -i mtu

# Bước 2: Test với gói tin kích thước khác nhau để xác nhận ngưỡng gây lỗi
ping -M do -s 1472 <target_container_ip>   # test với MTU 1500 chuẩn (1472+28 header)
ping -M do -s 1400 <target_container_ip>   # test với kích thước nhỏ hơn

# Bước 3: Điều chỉnh MTU của overlay network thấp hơn MTU vật lý phù hợp
# (VXLAN overhead thường 50 byte, nên overlay MTU = physical MTU - 50)
docker network create --opt com.docker.network.driver.mtu=1450 --driver overlay my_overlay_net

# Bước 4: Với Kubernetes CNI (Calico, Flannel...), cấu hình MTU tương ứng
# trong CNI config, đảm bảo nhất quán trên toàn bộ node trong cluster
```

**4. Bài học kinh nghiệm**
Vấn đề MTU mismatch là một trong những lỗi network "khó tái hiện nhất" vì nó chỉ biểu hiện với gói tin đủ lớn — nhiều test kết nối cơ bản (ping đơn giản, curl với response nhỏ) hoàn toàn không phát hiện ra vấn đề, khiến nó thường bị bỏ sót qua các bước kiểm thử thông thường và chỉ lộ ra khi có traffic thực tế với payload lớn hơn (upload file, response API lớn).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Luôn tính toán và cấu hình MTU của overlay network thấp hơn MTU vật lý một khoảng phù hợp với overhead encapsulation cụ thể (VXLAN, IPIP...) đang dùng, không giữ nguyên giá trị mặc định mà không xác nhận tương thích
- Test kết nối với gói tin kích thước lớn (không chỉ ping cơ bản) như một phần bắt buộc của quy trình kiểm thử network sau khi triển khai overlay network mới
- Đảm bảo MTU nhất quán trên toàn bộ node trong cluster (physical NIC, overlay interface, và mọi thiết bị mạng trung gian như switch/firewall), một node cấu hình lệch có thể gây lỗi ngắt quãng khó tái hiện tùy vào Pod được schedule ở đâu

---

### Case 12: ImagePullBackOff hàng loạt do rate limit/token registry hết hạn

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Nhiều Pod trên khắp cluster đồng loạt không thể khởi động, ở trạng thái `ImagePullBackOff`/`ErrImagePull`, đặc biệt nghiêm trọng nếu đang trong lúc scale-out hoặc rolling update cần pull nhiều image mới cùng lúc.

**2. Nguyên nhân**
Hai nguyên nhân phổ biến: (1) Docker Hub (hoặc registry công khai khác) áp dụng rate limit cho pull request theo IP/account, và cluster có nhiều node cùng pull image đồng thời vượt quá giới hạn cho phép; (2) `imagePullSecret` (credential xác thực registry riêng tư) hết hạn hoặc bị thu hồi mà không ai cập nhật kịp thời trong Kubernetes Secret tương ứng.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận nguyên nhân cụ thể qua describe pod
kubectl describe pod <pod_name> -n <namespace>
# Tìm dòng lỗi cụ thể: "429 Too Many Requests" (rate limit) hoặc
# "unauthorized: authentication required" (credential hết hạn)

# Bước 2a: Nếu là rate limit từ registry công khai — xác nhận và chờ reset
# (thường theo giờ), đồng thời đánh giá giải pháp lâu dài bên dưới

# Bước 2b: Nếu là credential hết hạn — cập nhật lại Secret ngay
kubectl create secret docker-registry regcred \
  --docker-server=<registry_url> \
  --docker-username=<user> --docker-password=<new_token> \
  -n <namespace> --dry-run=client -o yaml | kubectl apply -f -

# Bước 3: Với rate limit, triển khai Pull-Through Cache Registry (registry
# mirror nội bộ) để giảm số lượng pull request trực tiếp ra registry công khai
# từ mỗi node, tất cả node chỉ cần pull từ mirror nội bộ

# Bước 4: Xác nhận Pod tự động retry và khởi động thành công sau khi khắc phục
kubectl get pods -n <namespace> -w
```

**4. Bài học kinh nghiệm**
Registry (Docker Hub hay bất kỳ registry riêng tư nào) là một external dependency thường bị đối xử như "luôn sẵn sàng, không cần dự phòng" — nhưng thực tế nó có giới hạn (rate limit) và vòng đời credential (token hết hạn) riêng, cần được quản lý chủ động tương tự như bất kỳ dependency quan trọng nào khác của hệ thống.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Triển khai Pull-Through Cache Registry hoặc registry nội bộ (Harbor, Nexus) làm lớp trung gian cho mọi image pull trong cluster, giảm phụ thuộc trực tiếp vào rate limit của registry công khai bên ngoài
- Quản lý vòng đời `imagePullSecret` chủ động (theo dõi ngày hết hạn, gia hạn trước thời hạn, tương tự quản lý chứng chỉ SSL đã đề cập ở tài liệu case08b), không để credential hết hạn bất ngờ ảnh hưởng khả năng pull image
- Cấu hình `imagePullPolicy: IfNotPresent` cho image ổn định ít thay đổi (giảm số lần cần pull mới thực sự), chỉ dùng `Always` khi thực sự cần thiết cho image thay đổi thường xuyên (như tag `latest` trong môi trường CI/CD)

---

## NHÓM D: MESSAGE QUEUE — KAFKA/RABBITMQ (Case 13-16)

### Case 13: Kafka consumer group rơi vào vòng lặp rebalancing storm liên tục

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Consumer group liên tục thực hiện rebalancing (phân bổ lại partition cho các consumer), khiến throughput xử lý message giảm gần như về 0 — trong lúc rebalancing, toàn bộ consumer trong group tạm dừng xử lý, và nếu rebalancing xảy ra liên tục, hệ thống gần như không bao giờ thực sự xử lý được message.

**2. Nguyên nhân**
`session.timeout.ms` (thời gian tối đa broker chờ heartbeat từ consumer trước khi coi là "chết" và loại khỏi group) được đặt quá thấp so với thời gian xử lý thực tế mỗi message/batch của consumer, hoặc `max.poll.interval.ms` không đủ lớn cho logic xử lý phức tạp — consumer bị coi là "chết" giữa lúc đang xử lý bình thường (chỉ là chậm), bị loại khỏi group, kích hoạt rebalancing, sau đó consumer đó lại join lại group ngay sau khi hoàn tất xử lý, kích hoạt rebalancing LẦN NỮA, tạo vòng lặp.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận đang có rebalancing storm qua log broker/consumer
grep -i "rebalance\|Group.*generation" /var/log/kafka/server.log | tail -50

# Bước 2: Kiểm tra cấu hình hiện tại của consumer group
kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --describe --group <consumer_group_id>

# Bước 3: Điều chỉnh session.timeout.ms và max.poll.interval.ms phù hợp
# với thời gian xử lý thực tế của consumer (đo đạc trước khi điều chỉnh)
```
```properties
# consumer.properties
session.timeout.ms=45000
max.poll.interval.ms=300000
max.poll.records=100
```
```bash
# Bước 4: Restart consumer với cấu hình mới, giám sát lại tần suất rebalancing
# sau điều chỉnh để xác nhận đã ổn định
```

**4. Bài học kinh nghiệm**
Rebalancing storm là một vòng lặp tự củng cố (self-reinforcing) nguy hiểm — mỗi lần rebalance làm chậm thêm việc xử lý (do gián đoạn), khiến consumer càng dễ vượt timeout ở lần tiếp theo, tạo ra một vòng xoáy suy giảm hiệu năng ngày càng tệ hơn nếu không can thiệp kịp thời vào đúng nguyên nhân gốc (cấu hình timeout không phù hợp với đặc tính xử lý thực tế).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đo đạc thời gian xử lý thực tế (bao gồm cả trường hợp xấu nhất — batch lớn, downstream dependency chậm) của consumer TRƯỚC khi cấu hình `session.timeout.ms`/`max.poll.interval.ms`, không dùng giá trị mặc định cho mọi loại workload
- Với logic xử lý message có thời gian không ổn định (phụ thuộc external service), cân nhắc tách xử lý nặng ra một tiến trình/thread riêng, để consumer poll loop vẫn có thể gửi heartbeat đều đặn độc lập với tốc độ xử lý thực tế
- Giám sát tần suất rebalancing của mọi consumer group quan trọng như một chỉ số sức khỏe, alert khi có xu hướng rebalancing lặp lại bất thường thay vì chỉ phát hiện qua triệu chứng throughput giảm

---

### Case 14: Kafka under-replicated partition do broker disk chậm/ISR bị thu hẹp

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Một hoặc nhiều partition có số lượng replica đồng bộ (In-Sync Replica - ISR) giảm xuống dưới số replication factor cấu hình, giảm khả năng chịu lỗi của dữ liệu — nếu broker chứa replica còn lại trong ISR gặp sự cố tiếp theo, có nguy cơ mất dữ liệu hoặc gián đoạn dịch vụ cho partition đó.

**2. Nguyên nhân**
Một broker cụ thể có hiệu năng disk I/O suy giảm (do disk sắp hỏng, hoặc tranh chấp I/O với workload khác trên cùng server) khiến nó không thể fetch/ghi dữ liệu kịp tốc độ với leader của partition — khi độ trễ vượt quá `replica.lag.time.max.ms`, leader tự động loại broker đó khỏi ISR để bảo vệ tính nhất quán, làm giảm số lượng replica đồng bộ thực tế của partition đó.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác định các partition đang under-replicated
kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions

# Bước 2: Xác định broker nào đang bị loại khỏi ISR thường xuyên nhất
kafka-topics.sh --bootstrap-server localhost:9092 --describe | grep -B2 "Isr:"

# Bước 3: Kiểm tra sức khỏe I/O của broker nghi ngờ
iostat -x 5 3   # trên server broker cụ thể, xem %util và await có bất thường

# Bước 4: Nếu xác nhận broker có vấn đề I/O — xử lý theo nguyên nhân cụ thể
# (thay disk nếu sắp hỏng, giảm tải I/O khác cạnh tranh trên cùng server)

# Bước 5: Sau khi khắc phục, theo dõi broker tự động rejoin ISR
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic <affected_topic>
# Xác nhận Isr đã bao gồm đầy đủ lại tất cả replica
```

**4. Bài học kinh nghiệm**
Under-replicated partition là chỉ số sức khỏe QUAN TRỌNG NHẤT của một Kafka cluster nhưng thường không gây lỗi/downtime NGAY LẬP TỨC (dữ liệu vẫn được ghi/đọc bình thường qua leader) — điều này khiến nó dễ bị bỏ qua trong giám sát hàng ngày cho đến khi kết hợp với một sự cố thứ hai (leader cũng gặp vấn đề) mới bộc lộ hậu quả nghiêm trọng của việc thiếu redundancy đã tồn tại từ trước.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Giám sát chỉ số `UnderReplicatedPartitions` liên tục qua JMX metrics như một chỉ số CRITICAL bắt buộc của cluster, alert ngay khi giá trị khác 0 kéo dài (không đợi có sự cố thứ hai mới phát hiện)
- Đảm bảo mọi broker trong cluster có cấu hình I/O tương đương nhau, tránh tình trạng "broker yếu" trở thành điểm nghẽn thường xuyên bị loại khỏi ISR
- Giám sát riêng sức khỏe disk I/O của từng broker (không chỉ dung lượng, mà cả latency/throughput thực tế) như một phần của health check hạ tầng Kafka định kỳ, phát hiện sớm broker có dấu hiệu suy giảm trước khi ảnh hưởng đến ISR

---

### Case 15: RabbitMQ queue phình to không giới hạn do không có consumer, kích hoạt Flow Control

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Một queue không có consumer (do consumer application bị lỗi/dừng mà không ai phát hiện) tích lũy message không giới hạn, dẫn đến RAM của RabbitMQ node tăng cao và kích hoạt cơ chế "Flow Control" — làm chậm TOÀN BỘ publisher trên node đó (không chỉ riêng queue có vấn đề), lan rộng ảnh hưởng ra ngoài phạm vi ban đầu.

**2. Nguyên nhân**
Không có giới hạn `max-length`/TTL cho queue, kết hợp với việc consumer application dừng hoạt động (crash, deploy lỗi) mà không có giám sát/alert riêng cho tình trạng "queue không có consumer" — message publisher vẫn tiếp tục gửi bình thường (publisher không biết/không quan tâm consumer có đang hoạt động hay không), khiến queue phình to không kiểm soát.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác định queue nào đang phình to và có bao nhiêu consumer
rabbitmqctl list_queues name messages consumers memory

# Bước 2: Xác nhận Flow Control đã kích hoạt (ảnh hưởng publisher)
rabbitmqctl list_connections name recv_oct send_oct state
# Trạng thái "blocking"/"blocked" là dấu hiệu Flow Control đang hoạt động

# Bước 3: Xử lý khẩn cấp — khôi phục consumer application ngay lập tức
# (đây là hành động quan trọng nhất, giải quyết đúng nguyên nhân gốc)

# Bước 4: Nếu queue đã phình quá lớn và cần giảm tải ngay trong lúc chờ
# consumer bắt kịp, cân nhắc purge các message không còn giá trị nghiệp vụ
# (CHỈ khi xác nhận an toàn, mất dữ liệu message đã purge)
rabbitmqctl purge_queue <queue_name>

# Bước 5: Thiết lập giới hạn cho tương lai để tránh tái diễn
rabbitmqctl set_policy queue-limit "^my_queue$" \
  '{"max-length":100000,"overflow":"reject-publish"}' --apply-to queues
```

**4. Bài học kinh nghiệm**
RabbitMQ Flow Control là cơ chế bảo vệ đúng đắn (ngăn RAM của node bị cạn kiệt hoàn toàn) nhưng tác động của nó lan RỘNG RA TOÀN NODE thay vì chỉ giới hạn ở queue có vấn đề — một consumer application lỗi ở MỘT service có thể gián tiếp làm chậm publisher của TẤT CẢ service khác đang dùng chung RabbitMQ node đó, đây là hiệu ứng "hàng xóm ồn ào" tương tự đã gặp trong nhiều case khác của tài liệu này.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấu hình `max-length` hoặc TTL hợp lý cho MỌI queue production, không để queue có khả năng phình to vô hạn — quyết định rõ ràng chính sách khi đầy (reject publish mới, hay drop message cũ nhất) phù hợp với đặc thù nghiệp vụ
- Giám sát riêng số lượng consumer đang active trên mỗi queue quan trọng, alert NGAY khi một queue có consumer giảm về 0 trong khi vẫn đang nhận message mới, không đợi đến khi queue đã phình to mới phát hiện
- Với kiến trúc multi-tenant dùng chung RabbitMQ cluster cho nhiều service, cân nhắc dùng cơ chế cô lập tài nguyên (virtual host riêng, hoặc cluster riêng cho service quan trọng) để tránh một service lỗi ảnh hưởng dây chuyền tới các service khác

---

### Case 16: RabbitMQ cluster network partition (split-brain) do thiếu cấu hình pause_minority

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL, tương tự các case split-brain đã gặp ở Data Guard/Pacemaker/Keepalived nhưng ở tầng message queue. Khi network giữa các node RabbitMQ cluster bị gián đoạn tạm thời, cả hai phía của cluster (sau khi bị chia cắt) tiếp tục hoạt động ĐỘC LẬP, nhận publish/consume riêng biệt — khi network phục hồi, dữ liệu giữa hai phía đã phân kỳ không thể tự động hợp nhất.

**2. Nguyên nhân**
`cluster_partition_handling` không được cấu hình (giữ giá trị mặc định `ignore` — cluster không có hành động chủ động khi phát hiện partition) — khác với các hệ thống HA khác có cơ chế fencing/STONITH rõ ràng, RabbitMQ mặc định "phớt lờ" network partition và để cả hai phía tiếp tục hoạt động, tạo ra chính xác kịch bản split-brain nguy hiểm.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận đã/đang xảy ra network partition
rabbitmqctl cluster_status
# Tìm phần "partitions" - nếu không rỗng, xác nhận cluster đã/đang bị chia cắt

# Bước 2: Xác định phía nào của cluster đã tiếp tục hoạt động độc lập,
# đánh giá phạm vi dữ liệu bị phân kỳ giữa hai phía

# Bước 3: Xử lý khẩn cấp — theo nguyên tắc tương tự split-brain database,
# XÁC ĐỊNH một phía là "đúng" (thường phía có nhiều dữ liệu/traffic quan trọng
# hơn), phía còn lại cần đánh giá dữ liệu bị mất và chấp nhận rebuild

# Bước 4: Cấu hình cluster_partition_handling phù hợp cho tương lai
```
```
# rabbitmq.conf
cluster_partition_handling = pause_minority
```
```bash
# pause_minority: node ở phía thiểu số (ít node hơn) tự động dừng phục vụ,
# tránh cả hai phía cùng hoạt động độc lập — đây là lựa chọn an toàn phổ biến
# cho cluster có số node lẻ (3, 5...)
```

**4. Bài học kinh nghiệm**
Cấu hình mặc định `ignore` của RabbitMQ cho `cluster_partition_handling` là một trong những cạm bẫy nguy hiểm nhất dễ bị bỏ sót khi triển khai cluster — khác với Pacemaker (yêu cầu cấu hình STONITH tường minh mới hoạt động), RabbitMQ "hoạt động được" ngay cả khi không cấu hình gì, khiến rủi ro split-brain ẩn mình cho đến khi network thực sự gặp sự cố.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Luôn cấu hình `cluster_partition_handling` tường minh (khuyến nghị `pause_minority` cho cluster số node lẻ) ngay khi triển khai RabbitMQ cluster, coi đây là bước bắt buộc tương đương với việc cấu hình STONITH cho Pacemaker
- Thiết kế cluster RabbitMQ với số lượng node LẺ (3, 5...) để `pause_minority` có thể xác định rõ ràng phía nào là thiểu số, tránh tình huống chia đôi 50-50 không thể phân định
- Diễn tập network partition thực tế (chặn tạm network giữa các node cluster) trong môi trường staging, xác nhận hành vi `pause_minority` hoạt động đúng như kỳ vọng trước khi tin tưởng cấu hình này bảo vệ production

---

## NHÓM E: IN-MEMORY CACHE — REDIS/REDIS CLUSTER (Case 17-20)

### Case 17: Lệnh blocking (KEYS/FLUSHALL) trên Redis đơn luồng gây đơ toàn bộ client

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL nhưng hoàn toàn "tự gây ra" (self-inflicted), không phải lỗi phần mềm Redis. Một lệnh `KEYS *` hoặc thao tác nặng khác được một developer/script chạy trên Redis production khiến TOÀN BỘ client khác bị treo hoàn toàn trong suốt thời gian lệnh đó thực thi, có thể từ vài giây đến hàng chục giây tùy kích thước dataset.

**2. Nguyên nhân**
Redis xử lý lệnh theo mô hình đơn luồng (single-threaded) cho phần lớn command — điều này mang lại tính nhất quán và hiệu năng cao cho các thao tác đơn giản (O(1)), nhưng đồng nghĩa MỌI lệnh có độ phức tạp cao (như `KEYS *` quét toàn bộ keyspace, độ phức tạp O(N)) sẽ CHIẾM DỤNG hoàn toàn luồng xử lý duy nhất, chặn tất cả client khác phải xếp hàng chờ đến khi lệnh đó hoàn tất.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận lệnh nào đang chạy gây block (nếu vẫn đang trong lúc xảy ra)
redis-cli -a <password> CLIENT LIST
redis-cli -a <password> SLOWLOG GET 10

# Bước 2: Nếu lệnh đang chạy và cần dừng ngay (chấp nhận rủi ro với phiên bản cũ)
# Redis 6.2+ hỗ trợ CLIENT KILL/CLIENT UNPAUSE, hoặc dùng lệnh sau (thận trọng)
redis-cli -a <password> CLIENT LIST | grep <client_gây_block>

# Bước 3: Thay thế lệnh nguy hiểm bằng phiên bản an toàn có phân trang (cursor-based)
# KEYS * -> dùng SCAN thay thế, không block toàn bộ server
redis-cli -a <password> --scan --pattern '*' | head -100
# Trong code ứng dụng, dùng SCAN với COUNT hợp lý thay vì KEYS

# Bước 4: Bật cảnh báo cho các lệnh chậm để phát hiện sớm trong tương lai
redis-cli -a <password> CONFIG SET slowlog-log-slower-than 10000  # 10ms
redis-cli -a <password> CONFIG SET slowlog-max-len 1000
```

**4. Bài học kinh nghiệm**
Đặc tính "cực nhanh" nổi tiếng của Redis chính là con dao hai lưỡi khi có ai đó vô tình chạy một lệnh không phù hợp — vì không có cơ chế song song hóa để cô lập tác động, MỘT lệnh sai lầm duy nhất có khả năng ảnh hưởng đến TOÀN BỘ hệ thống đang dùng chung Redis instance đó, một hậu quả nghiêm trọng hơn nhiều so với một câu query chậm trong RDBMS có nhiều connection song song.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Cấm tuyệt đối sử dụng `KEYS *`, `FLUSHALL`/`FLUSHDB` không có xác nhận, và các lệnh O(N) nguy hiểm khác trên Redis production trong mọi script/công cụ vận hành, thay thế bằng `SCAN` có cursor cho mọi nhu cầu duyệt keyspace
- Cấu hình `rename-command` trong `redis.conf` để vô hiệu hóa hoặc đổi tên các lệnh nguy hiểm nhất trên instance production, giảm rủi ro chạy nhầm ngay cả khi có người không nắm rõ quy tắc
- Giám sát Slowlog liên tục như một chỉ số sức khỏe bắt buộc, đưa vào alert khi có lệnh vượt ngưỡng thời gian thực thi, giúp phát hiện và ngăn chặn thói quen dùng lệnh nguy hiểm trước khi gây sự cố nghiêm trọng

---

### Case 18: Redis Sentinel không kích hoạt failover do quorum/down-after-milliseconds sai

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Redis Master gặp sự cố thực sự (crash/network down) nhưng Sentinel KHÔNG tự động thực hiện failover sang Replica như thiết kế, khiến ứng dụng mất khả năng ghi dữ liệu vào Redis trong thời gian dài hơn nhiều so với kỳ vọng.

**2. Nguyên nhân**
`quorum` (số lượng Sentinel tối thiểu cần đồng thuận trước khi coi Master là "khách quan đã chết" - ODOWN) được cấu hình quá cao so với số lượng Sentinel instance thực tế đang chạy (ví dụ quorum=3 nhưng chỉ có 3 Sentinel và một trong số đó cũng bị ảnh hưởng bởi cùng sự cố network khiến nó không thể "biểu quyết"), hoặc `down-after-milliseconds` quá cao khiến thời gian phát hiện sự cố kéo dài không cần thiết.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra trạng thái Sentinel và quorum hiện tại
redis-cli -p 26379 SENTINEL master mymaster
redis-cli -p 26379 SENTINEL sentinels mymaster

# Bước 2: Xác nhận số lượng Sentinel đang thực sự "nhìn thấy" nhau và Master
redis-cli -p 26379 INFO sentinel

# Bước 3: Nếu quorum không thể đạt được do thiếu Sentinel khả dụng — 
# xử lý khẩn cấp bằng failover thủ công
redis-cli -p 26379 SENTINEL failover mymaster

# Bước 4: Sau sự cố, điều chỉnh lại quorum phù hợp với số lượng Sentinel
# thực tế (khuyến nghị tối thiểu 3 Sentinel, quorum = majority, ví dụ 2/3)
# sentinel.conf:
# sentinel monitor mymaster 10.0.0.1 6379 2
# sentinel down-after-milliseconds mymaster 5000
```

**4. Bài học kinh nghiệm**
Sentinel quorum có cùng bản chất toán học với quorum của Pacemaker/Corosync (Case 8) — cần đủ số lượng "cử tri" độc lập để đưa ra quyết định đáng tin cậy, và triển khai Sentinel với số lượng instance không đủ hoặc không phân tán đúng cách (nhiều Sentinel cùng nằm sau một điểm lỗi mạng chung) là nguyên nhân gốc phổ biến khiến failover tự động không hoạt động đúng lúc cần thiết nhất.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Triển khai tối thiểu 3 Sentinel instance (số lẻ) phân tán trên các failure domain độc lập (không cùng rack/AZ với nhau và với Master), đảm bảo một sự cố cục bộ không đồng thời ảnh hưởng đến đa số Sentinel
- Cấu hình `quorum` bằng majority thực sự (ví dụ 2 trong 3, không phải toàn bộ 3/3) để failover vẫn có thể xảy ra ngay cả khi một Sentinel gặp sự cố cùng lúc với Master
- Diễn tập failover Sentinel định kỳ (kill Master thủ công trong môi trường staging) để xác nhận thời gian phát hiện và failover thực tế phù hợp với RTO yêu cầu, không chỉ tin tưởng vào cấu hình trên giấy

---

### Case 19: maxmemory-policy cấu hình sai gây evict nhầm key quan trọng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🟡 DEGRADED, đặc biệt nguy hiểm nếu Redis đang được dùng cho mục đích ngoài cache thuần túy (ví dụ lưu session, hàng đợi tạm). Khi Redis đạt giới hạn `maxmemory`, các key QUAN TRỌNG (session đang hoạt động, dữ liệu nghiệp vụ tạm thời) bị tự động xóa (evict) để nhường chỗ cho key mới, gây mất dữ liệu ngoài dự kiến.

**2. Nguyên nhân**
`maxmemory-policy` được đặt là `allkeys-lru`/`allkeys-random` (evict bất kỳ key nào, không phân biệt có TTL hay không) trong khi ứng dụng thực tế có LƯU TRỮ một số key quan trọng KHÔNG có TTL (dùng Redis như một phần lưu trữ bán-persistent, không chỉ cache thuần túy) — chính sách evict "allkeys" áp dụng đồng đều cho mọi key, kể cả những key mà ứng dụng kỳ vọng sẽ tồn tại vĩnh viễn cho đến khi bị xóa chủ động.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận chính sách eviction hiện tại và tình trạng memory
redis-cli -a <password> CONFIG GET maxmemory-policy
redis-cli -a <password> INFO memory | grep -E "used_memory_human|maxmemory_human|evicted_keys"

# Bước 2: Xác định các key quan trọng có đang thiếu TTL không (dấu hiệu
# "key cache" bị nhầm dùng làm "key lưu trữ")
redis-cli -a <password> --scan --pattern 'session:*' | head -5 | \
  xargs -I{} redis-cli -a <password> TTL {}
# TTL trả về -1 nghĩa là key không có thời hạn, có nguy cơ bị evict nếu policy allkeys

# Bước 3: Chuyển sang chính sách phù hợp — chỉ evict key CÓ TTL (đúng là cache),
# bảo vệ hoàn toàn key không có TTL (được xem là dữ liệu quan trọng)
redis-cli -a <password> CONFIG SET maxmemory-policy volatile-lru

# Bước 4: Đồng thời tăng maxmemory nếu dung lượng hiện tại không đủ đáp ứng
# nhu cầu thực tế, tránh áp lực eviction liên tục
redis-cli -a <password> CONFIG SET maxmemory 4gb
```

**4. Bài học kinh nghiệm**
Redis được thiết kế linh hoạt để dùng cho cả mục đích cache THUẦN TÚY (mọi key có thể mất mà không ảnh hưởng nghiêm trọng) và lưu trữ bán-persistent (một số key cần tồn tại đáng tin cậy) — nhưng CÙNG một `maxmemory-policy` không thể phù hợp cho cả hai mục đích cùng lúc nếu không phân biệt rõ qua việc có/không đặt TTL, và nhầm lẫn giữa hai vai trò này là nguồn gốc phổ biến của mất dữ liệu "bất ngờ".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Xác định rõ ràng vai trò của Redis instance (cache thuần túy hay lưu trữ bán-persistent) ngay từ khi thiết kế, và chọn `maxmemory-policy` phù hợp tương ứng (`volatile-*` để chỉ evict key có TTL, bảo vệ key không TTL)
- Yêu cầu team phát triển LUÔN đặt TTL rõ ràng cho mọi key thực sự chỉ mang tính chất cache tạm thời, giúp phân biệt rõ với key cần được bảo vệ khỏi eviction
- Giám sát `evicted_keys` metric liên tục, alert khi có eviction xảy ra bất thường (đặc biệt nếu instance được kỳ vọng không nên có eviction), giúp phát hiện sớm áp lực memory trước khi ảnh hưởng đến dữ liệu quan trọng

---

### Case 20: Redis Cluster CLUSTERDOWN do quá trình resharding bị gián đoạn giữa chừng

**1. Vấn đề/lỗi, Mức độ ảnh hưởng**
🔴 CRITICAL. Trong lúc thực hiện resharding (di chuyển slot dữ liệu giữa các node để cân bằng lại tải), quá trình bị gián đoạn giữa chừng (network lỗi, tiến trình di chuyển bị kill) khiến một số slot rơi vào trạng thái "MIGRATING"/"IMPORTING" treo lửng lơ — toàn bộ cluster báo lỗi `CLUSTERDOWN` và từ chối phục vụ TOÀN BỘ request, không chỉ riêng phần dữ liệu thuộc slot bị ảnh hưởng.

**2. Nguyên nhân**
Redis Cluster yêu cầu TẤT CẢ 16384 slot phải được gán một cách rõ ràng và nhất quán cho việc cluster được coi là "healthy" — nếu một slot đang ở trạng thái chuyển tiếp (migrating từ node A sang node B) mà quá trình bị gián đoạn không hoàn tất, cluster không thể xác định chắc chắn slot đó thuộc về node nào, dẫn đến trạng thái không nhất quán và cluster tự bảo vệ bằng cách từ chối phục vụ hoàn toàn.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận trạng thái cluster và xác định slot đang bị treo
redis-cli -a <password> CLUSTER INFO
redis-cli -a <password> CLUSTER NODES | grep -E "migrating|importing"

# Bước 2: Xác định chính xác node nguồn và đích của slot đang treo
redis-cli -c -a <password> -h <node_migrating> CLUSTER GETKEYSINSLOT <slot_number> 10

# Bước 3: Hoàn tất thủ công quá trình di chuyển slot bị treo (đưa slot về
# trạng thái ổn định, gán rõ ràng cho MỘT node duy nhất)
redis-cli -a <password> -h <node_dich> CLUSTER SETSLOT <slot_number> NODE <node_dich_id>
redis-cli -a <password> -h <node_nguon> CLUSTER SETSLOT <slot_number> NODE <node_dich_id>

# Bước 4: Xác nhận toàn bộ 16384 slot đã được gán đầy đủ và nhất quán
redis-cli -a <password> CLUSTER SLOTS
redis-cli -a <password> CLUSTER INFO | grep cluster_state
# Xác nhận "cluster_state:ok" trước khi coi sự cố đã được khắc phục hoàn toàn
```

**4. Bài học kinh nghiệm**
Redis Cluster resharding không phải là một thao tác "atomic" hoàn toàn — nó là một quá trình nhiều bước có thể bị gián đoạn giữa chừng, và khác với nhiều thao tác bảo trì khác chỉ ảnh hưởng cục bộ, một slot bị treo có thể kéo theo trạng thái `CLUSTERDOWN` ảnh hưởng TOÀN BỘ cluster — mức độ nghiêm trọng của hậu quả không tương xứng với phạm vi nhỏ của vấn đề gốc (chỉ 1 trong 16384 slot).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Thực hiện resharding trong khung giờ có giám sát trực tiếp, tránh chạy resharding lớn tự động hoàn toàn không người theo dõi, đặc biệt qua kết nối mạng không ổn định (VPN, kết nối từ xa dễ bị gián đoạn)
- Dùng công cụ resharding chính thức (`redis-cli --cluster reshard` hoặc Redis Enterprise/managed service) có cơ chế resume/rollback tốt hơn thao tác thủ công từng lệnh `CLUSTER SETSLOT`, giảm rủi ro gián đoạn giữa chừng
- Giám sát trạng thái `cluster_state` liên tục như một chỉ số CRITICAL, alert ngay khi khác `ok`, kết hợp kiểm tra định kỳ không có slot nào ở trạng thái `migrating`/`importing` treo lâu bất thường ngoài các cửa sổ bảo trì đã lên kế hoạch

---

## TỔNG KẾT — KẾT LUẬN

```
Phân tích xu hướng qua 20 case chuyên sâu Middleware:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Split-brain/network partition xuất hiện lặp lại xuyên suốt MỌI công
   nghệ HA (Keepalived VRRP, Pacemaker quorum, RabbitMQ cluster,
   Redis Sentinel) — cùng một nguyên lý toán học quorum, khác cách
   triển khai                                                        → 5/20 case
2. Cấu hình mặc định "im lặng, không cảnh báo" khi thiếu (RabbitMQ
   ignore partition, HPA thiếu metrics-server) khiến vấn đề chỉ lộ ra
   qua triệu chứng gián tiếp, không có lỗi rõ ràng                   → 4/20 case
3. Đặc tính kiến trúc cốt lõi tạo rủi ro tập trung (Redis đơn luồng,
   RabbitMQ Flow Control lan toàn node) — một vấn đề cục bộ ảnh hưởng
   diện rộng hơn phạm vi ban đầu                                     → 4/20 case
4. Thiếu cấu hình bảo vệ tường minh, phụ thuộc hành vi mặc định không
   phù hợp production (PDB quá chặt, maxmemory-policy sai, timeout
   không khớp workload thực tế)                                      → 5/20 case
5. Thao tác bảo trì có nhiều bước bị gián đoạn giữa chừng (resharding
   Redis Cluster) gây hậu quả không tương xứng phạm vi ban đầu         → 2/20 case
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nguyên tắc phòng ngừa cốt lõi rút ra (chuyên sâu Middleware):
- Nguyên lý QUORUM (cần đa số rõ ràng để đưa ra quyết định đáng tin
  cậy trong hệ phân tán) là chủ đề xuyên suốt mọi công nghệ HA hiện
  đại — hiểu sâu nguyên lý này một lần áp dụng được cho mọi công nghệ
  cụ thể (Keepalived, Pacemaker, RabbitMQ, Sentinel, Kafka ISR),
  hiệu quả hơn nhiều so với học thuộc lòng cấu hình riêng lẻ từng hệ
- Với hệ thống phân tán, LUÔN kiểm tra xem cơ chế bảo vệ khi mất kết
  nối/network partition là "an toàn mặc định" (fail-safe, như Pacemaker
  STONITH bắt buộc cấu hình) hay "nguy hiểm mặc định" (fail-open, như
  RabbitMQ ignore partition) — với loại thứ hai, cấu hình tường minh
  ngay từ đầu là bắt buộc, không thể để mặc định
- Nhiều thành phần middleware có đặc tính kiến trúc khiến một vấn đề
  cục bộ nhỏ (một lệnh chậm, một consumer chết) lan tỏa ảnh hưởng diện
  rộng hơn nhiều phạm vi ban đầu — nhận diện đúng các "điểm khuếch đại"
  này (Redis đơn luồng, RabbitMQ Flow Control) giúp ưu tiên đúng biện
  pháp phòng ngừa có đòn bẩy cao nhất
- Tính năng "im lặng khi thất bại" (HPA không scale mà không báo lỗi
  ồn ào, quorum không đạt mà không có thông báo rõ ràng) là dạng lỗi
  nguy hiểm nhất vì không có tín hiệu chủ động — giám sát các Condition/
  State nội bộ của từng thành phần, không chỉ dựa vào triệu chứng bên
  ngoài, là chìa khóa phát hiện sớm
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Tài liệu tham khảo
- HAProxy Documentation — Configuration Manual, Stick Tables
- Nginx Documentation — SSL/TLS Module, Reverse Proxy Guide
- Keepalived Documentation — VRRP Configuration
- ClusterLabs Pacemaker/Corosync Documentation — Quorum, Constraints
- Kubernetes Documentation — HPA, PodDisruptionBudget, CNI Networking
- Apache Kafka Documentation — Consumer Configuration, Replication
- RabbitMQ Documentation — Cluster Partition Handling, Flow Control, Policies
- Redis Documentation — Sentinel, Cluster Specification, Eviction Policies
- www.tranvanbinh.vn — Khóa học Oracle & System Admin DBA A-Z Enterprise
