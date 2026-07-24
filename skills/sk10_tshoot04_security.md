---
name: oracle-troubleshoot-security
description: >
  100 case study khắc phục lỗi Bảo mật Oracle Database theo khung phân tích
  chuẩn: Vấn đề/Mức độ ảnh hưởng, Nguyên nhân, Thủ tục xử lý, Bài học kinh
  nghiệm, Biện pháp phòng ngừa. Kích hoạt khi hỏi về: lỗi authentication Oracle,
  ORA-01017, ORA-28000, account locked Oracle, password expired Oracle,
  lỗi TDE wallet, ORA-28365 wallet not open, lỗi VPD policy, ORA-28113,
  lỗi Database Vault, ORA-01031 insufficient privileges, lỗi audit Oracle,
  ORA-28031, network ACL error Oracle, SSL TLS error Oracle, lỗi encryption
  Oracle, proxy authentication error, role error Oracle, profile error Oracle,
  root cause analysis Oracle security, security incident postmortem Oracle.
---

# SK10-CASE-04 · Troubleshooting: Bảo mật Oracle Database

**Phạm vi:** Authentication, Authorization, Auditing, TDE, VPD, Database Vault, Network Security
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)
**Số lượng case:** 100 cases thực chiến — Format: Vấn đề → Nguyên nhân → Xử lý → Bài học → Phòng ngừa

---

## KIẾN TRÚC TỔNG QUAN SECURITY LAYERS

```
Oracle Security Defense-in-Depth — Failure Points Map
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────────┐
│  LAYER 1: NETWORK SECURITY                                │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group A     │
│  │   SSL/   │  │ Network  │  │ Listener │   (1-12)      │
│  │   TLS    │  │   ACL    │  │ Security │               │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
└───────┼─────────────┼─────────────┼───────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼───────────────────────┐
│  LAYER 2: AUTHENTICATION                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group B      │
│  │ Password │  │  Proxy   │  │ External │   (13-30)      │
│  │  Policy  │  │   Auth   │  │   Auth   │                │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                │
└───────┼─────────────┼─────────────┼────────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼────────────────────────┐
│  LAYER 3: AUTHORIZATION                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group C       │
│  │  Roles/  │  │   VPD    │  │ Database │   (31-55)       │
│  │  Privs   │  │  (RLS)   │  │   Vault  │                 │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                 │
└───────┼─────────────┼─────────────┼─────────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼─────────────────────────┐
│  LAYER 4: DATA PROTECTION                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   Group D       │
│  │   TDE    │  │  Data    │  │   SQL    │   (56-80)       │
│  │  Wallet  │  │ Redaction│  │ Firewall │                 │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘                 │
└───────┼─────────────┼─────────────┼─────────────────────────┘
        │             │             │
┌───────▼─────────────▼─────────────▼─────────────────────────┐
│  LAYER 5: AUDIT & COMPLIANCE                                   │
│  ┌──────────────────────────────────┐   Group E            │
│  │  Unified Audit / FGA / AVDF       │   (81-100)           │
│  └──────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘

Severity: 🔴 SECURITY BREACH RISK | 🟡 ACCESS DENIED | 🟢 CONFIG ISSUE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## CÁCH ĐỌC MỖI CASE STUDY

Mỗi case tuân theo khung phân tích 5 phần chuẩn:

```
1. VẤN ĐỀ / MỨC ĐỘ ẢNH HƯỞNG  → Triệu chứng quan sát được + impact thực tế
2. NGUYÊN NHÂN                 → Root cause kỹ thuật
3. THỦ TỤC XỬ LÝ                → Các bước khắc phục theo thứ tự
4. BÀI HỌC KINH NGHIỆM          → Insight rút ra cho team
5. BIỆN PHÁP PHÒNG NGỪA         → Hành động chủ động để không lặp lại
```

---

## NHÓM A: NETWORK SECURITY (Case 1-12)

### Case 1: ORA-28759 — failure to open file (Wallet/Certificate)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Toàn bộ kết nối qua SSL/TLS bị từ chối ngay lập tức. Application không kết nối được tới database, gây downtime toàn diện cho mọi service phụ thuộc kênh mã hóa này.

**2. Nguyên nhân**
File certificate/wallet không đọc được do: (a) sai đường dẫn trong `WALLET_LOCATION`, (b) permissions OS không cho phép oracle user đọc file, (c) file bị xóa/di chuyển bởi một thao tác cleanup không chủ đích.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận file tồn tại đúng path khai báo
ls -la $TNS_ADMIN/wallet/
cat $TNS_ADMIN/sqlnet.ora | grep WALLET_LOCATION

# Bước 2: Kiểm tra nội dung wallet hợp lệ
orapki wallet display -wallet $TNS_ADMIN/wallet

# Bước 3: Sửa permissions nếu sai
chown oracle:oinstall $TNS_ADMIN/wallet/*
chmod 600 $TNS_ADMIN/wallet/ewallet.p12

# Bước 4: Reload listener và test lại kết nối
lsnrctl reload
sqlplus user/pass@TCPS_ALIAS
```

**4. Bài học kinh nghiệm**
Wallet/certificate là single point of failure cho toàn bộ kênh kết nối mã hóa — một thay đổi permission nhỏ (do script automation hoặc patching) có thể gây outage diện rộng mà log ban đầu không chỉ rõ nguyên nhân gốc.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa wallet directory vào danh sách loại trừ (exclude) trong mọi script cleanup/backup tự động.
- Giám sát định kỳ (monitoring job hàng ngày) kiểm tra `orapki wallet display` trả về thành công.
- Backup wallet vào vị trí riêng biệt, version-controlled, có alert khi permissions thay đổi (dùng `auditd` hoặc file integrity monitoring).
- Document rõ owner/permission chuẩn trong runbook vận hành.

---

### Case 2: ORA-28860 — Fatal SSL error

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Kết nối SSL/TLS thất bại hoàn toàn ngay tại bước handshake. Ảnh hưởng tất cả client dùng kết nối mã hóa, particularly nghiêm trọng nếu đây là kênh duy nhất được phép (network policy không cho phép plaintext).

**2. Nguyên nhân**
TLS protocol version không tương thích giữa client và server (ví dụ server chỉ support TLS 1.2 nhưng client cũ chỉ hỗ trợ TLS 1.0/1.1), hoặc cipher suite không match, thường xảy ra sau khi một bên được patch security/upgrade OS mà bên kia chưa cập nhật.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận SSL version đang cấu hình 2 bên
grep SSL_VERSION $TNS_ADMIN/sqlnet.ora      # server
grep SSL_VERSION $CLIENT_TNS_ADMIN/sqlnet.ora  # client

# Bước 2: Test handshake trực tiếp bằng openssl
openssl s_client -connect dbserver:2484 -tls1_2

# Bước 3: Đồng bộ version và cipher suite 2 bên
echo "SSL_VERSION=1.2" >> $TNS_ADMIN/sqlnet.ora
echo "SSL_CIPHER_SUITES=(TLS_RSA_WITH_AES_256_CBC_SHA256)" >> $TNS_ADMIN/sqlnet.ora

# Bước 4: Reload và retest
lsnrctl reload
```

**4. Bài học kinh nghiệm**
SSL/TLS compatibility là vấn đề "cả hai phía" — fix một bên không đủ, cần đồng bộ song song. Patch OS/security định kỳ ở một environment (VD: client) mà quên cập nhật phía còn lại là nguyên nhân phổ biến nhất.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Chuẩn hóa TLS version tối thiểu chung cho toàn bộ hạ tầng (policy-as-code), không để mỗi server tự chọn.
- Thiết lập compatibility test tự động (CI/CD pipeline) mỗi khi patch OS liên quan đến OpenSSL/crypto libraries.
- Maintain bảng compatibility matrix giữa Oracle Client/Server versions và TLS versions hỗ trợ.

---

### Case 3: ORA-12660 — Encryption or crypto-checksumming parameters incompatible

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Một số client cụ thể không kết nối được trong khi client khác vẫn OK — gây gián đoạn cục bộ, khó phát hiện ngay vì không phải toàn hệ thống down.

**2. Nguyên nhân**
Native Network Encryption (NNE) algorithm list không overlap giữa `SQLNET.ENCRYPTION_TYPES_SERVER` và `SQLNET.ENCRYPTION_TYPES_CLIENT`. Thường do nâng cấp Oracle Client version mới hơn deprecate algorithm cũ mà server vẫn yêu cầu.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận cấu hình hiện tại
SHOW PARAMETER sqlnet;
```
```bash
# Bước 2: So sánh algorithm list 2 phía
grep ENCRYPTION_TYPES $TNS_ADMIN/sqlnet.ora

# Bước 3: Đồng bộ danh sách algorithm (ưu tiên mạnh nhất chung)
# Server và Client cùng set:
echo "SQLNET.ENCRYPTION_TYPES_SERVER=(AES256,AES192,AES128)" >> sqlnet.ora
echo "SQLNET.ENCRYPTION_TYPES_CLIENT=(AES256,AES192,AES128)" >> sqlnet.ora
```

**4. Bài học kinh nghiệm**
Lỗi dạng "chỉ một số client fail" dễ bị chẩn đoán nhầm thành application bug thay vì network config — luôn kiểm tra sqlnet.ora khi gặp pattern lỗi kết nối không đồng nhất.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Centralize sqlnet.ora template cho toàn bộ client, deploy qua configuration management (Ansible/Puppet) thay vì để từng máy tự cấu hình.
- Review compatibility trước mỗi lần upgrade Oracle Client trên diện rộng.

---

### Case 4: TNS-12560 — TNS protocol adapter error (sau khi enable SSL)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Listener hoàn toàn không khởi động được sau thay đổi cấu hình — database không nhận bất kỳ kết nối mới nào, kể cả qua kênh không mã hóa.

**2. Nguyên nhân**
Thường do: (a) port TCPS bị conflict với service khác đang dùng, (b) `WALLET_LOCATION` trong `listener.ora` trỏ sai path, (c) cú pháp listener.ora bị lỗi sau khi thêm block TCPS thủ công.

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra log lỗi chi tiết
lsnrctl status
cat $ORACLE_BASE/diag/tnslsnr/$(hostname)/listener/trace/listener.log | tail -50

# Bước 2: Validate cú pháp listener.ora
cat $TNS_ADMIN/listener.ora

# Bước 3: Kiểm tra port conflict
netstat -tlnp | grep 2484

# Bước 4: Sửa lỗi cú pháp/path, sau đó start lại
lsnrctl start
```

**4. Bài học kinh nghiệm**
Thay đổi listener.ora trên production cần test trên non-prod trước — một dấu ngoặc thiếu trong cú pháp TCPS block có thể làm listener không start, ảnh hưởng TOÀN BỘ kết nối chứ không chỉ kênh SSL.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Luôn backup listener.ora trước khi sửa: `cp listener.ora listener.ora.bak_$(date +%Y%m%d)`.
- Test cấu hình mới trên môi trường staging với cùng version Oracle.
- Dùng `lsnrctl status` ngay sau mỗi thay đổi, không đợi báo cáo từ user.

---

### Case 5: ORA-12649 — Unknown encryption or data integrity algorithm

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Kết nối thất bại với thông báo algorithm không nhận diện được — thường xảy ra ngay sau khi nâng cấp/patch Oracle, ảnh hưởng tới connections dùng cấu hình cũ.

**2. Nguyên nhân**
Algorithm khai báo trong sqlnet.ora đã bị deprecated/removed ở phiên bản Oracle mới (ví dụ DES, RC4 bị loại bỏ từ các version gần đây vì lý do bảo mật).

**3. Thủ tục xử lý**
```sql
-- Kiểm tra algorithm hỗ trợ trên version hiện tại (tham khảo Oracle docs)
SHOW PARAMETER compatible;
```
```bash
# Cập nhật sang algorithm còn được hỗ trợ
sed -i 's/DES40/AES256/' $TNS_ADMIN/sqlnet.ora
lsnrctl reload
```

**4. Bài học kinh nghiệm**
Mỗi lần upgrade Oracle version cần review changelog về deprecated security algorithms — đây là nguồn lỗi âm thầm, chỉ phát hiện khi connection thực sự fail.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa "Security Algorithm Compatibility Check" vào checklist pre-upgrade chuẩn (xem thêm SK01-04, SK01-05).
- Định kỳ rà soát sqlnet.ora dùng algorithm hiện đại (AES256, SHA256+) thay vì để cấu hình legacy tồn tại nhiều năm.

---

### Case 6: Network ACL — ORA-24247 network access denied by access control list

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 PL/SQL code gọi `UTL_HTTP`/`UTL_TCP`/`UTL_SMTP` ra ngoài bị chặn — ảnh hưởng các tính năng tích hợp bên ngoài (gửi email, gọi REST API, AI Vector Search 26ai với LLM external).

**2. Nguyên nhân**
Từ Oracle 11g trở đi, mọi network call từ PL/SQL phải qua Access Control List (ACL) tường minh — đây là default-deny security design, không phải lỗi mà là chưa được cấp quyền.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận ACL hiện tại
SELECT * FROM dba_network_acls;
SELECT * FROM dba_network_acl_privileges WHERE principal='APP_USER';

-- Bước 2: Cấp quyền ACL cho host cụ thể
BEGIN
  DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
    host => 'api.company.com',
    ace  => XS$ACE_TYPE(privilege_list => XS$NAME_LIST('connect','resolve'),
                        principal_name => 'APP_USER',
                        principal_type => XS_ACL.PTYPE_DB)
  );
END;
/

-- Bước 3: Verify lại quyền đã cấp
SELECT host, lower_port, upper_port, privilege FROM dba_network_acl_privileges
WHERE principal='APP_USER';
```

**4. Bài học kinh nghiệm**
Đây là tính năng bảo mật chủ động của Oracle (whitelist-only network access) — không nên grant ACL quá rộng (wildcard host) chỉ để "cho chạy được", vì sẽ mở lỗ hổng exfiltration data.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Khi thiết kế tính năng cần network call ra ngoài, lên danh sách host/port cụ thể NGAY từ giai đoạn design, request ACL trước go-live.
- Review định kỳ ACL list, loại bỏ host không còn dùng (giảm attack surface).
- Không bao giờ dùng wildcard `*` cho host trong ACL production.

---

### Case 7: TCP.VALIDNODE_CHECKING chặn nhầm legitimate client

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Một nhóm user/application mới được thêm vào hệ thống không kết nối được, trong khi user cũ vẫn hoạt động bình thường — dễ nhầm là lỗi application.

**2. Nguyên nhân**
Whitelist IP (`TCP.INVITED_NODES`) trong sqlnet.ora chưa được cập nhật khi có server/subnet mới triển khai, đặc biệt phổ biến khi mở rộng hạ tầng hoặc thêm application server mới.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận whitelist hiện tại
cat $TNS_ADMIN/sqlnet.ora | grep -A3 VALIDNODE

# Bước 2: Lấy IP/subnet của client bị chặn
# (Từ network team hoặc client báo cáo)

# Bước 3: Thêm vào whitelist
echo "TCP.INVITED_NODES=(192.168.1.0/24,10.0.0.5,10.0.1.0/24)" >> $TNS_ADMIN/sqlnet.ora

# Bước 4: Reload và xác nhận
lsnrctl reload
```

**4. Bài học kinh nghiệm**
Whitelist tĩnh dễ "outdated" theo thời gian khi hạ tầng mở rộng — cần quy trình chính thức để cập nhật song song với mọi thay đổi network topology.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tích hợp việc cập nhật `TCP.INVITED_NODES` vào checklist khi provisioning server/application mới (Change Management — xem SK09-08).
- Dùng subnet range thay vì IP đơn lẻ khi hợp lý, giảm tần suất cần update.
- Document rõ "ai sở hữu" việc duy trì whitelist này để tránh bị bỏ sót.

---

### Case 8: ORA-12537 — TNS connection closed (sau security hardening)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Sau một đợt security hardening, một số session bị ngắt kết nối bất thường giữa chừng — gây gián đoạn transaction đang xử lý, có thể dẫn tới data inconsistency nếu application không retry đúng cách.

**2. Nguyên nhân**
Cấu hình `sec_protocol_error_further_action` quá nghiêm ngặt (ví dụ DROP ngay sau 1 lỗi protocol nhỏ), kết hợp với network có packet loss/jitter tạm thời bị hiểu nhầm là protocol error.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận cấu hình hiện tại
SHOW PARAMETER sec_protocol_error;

-- Bước 2: Điều chỉnh policy mềm hơn (delay trước khi drop)
ALTER SYSTEM SET sec_protocol_error_further_action='(DELAY,3),(DROP,10)' SCOPE=SPFILE;

-- Bước 3: Restart để áp dụng (hoặc dùng SCOPE=BOTH nếu parameter cho phép dynamic)
```

**4. Bài học kinh nghiệm**
Security hardening cần cân bằng giữa bảo mật và operational stability — áp dụng policy strict nhất ngay từ đầu mà không test trên production-like traffic dễ gây false positive disconnect.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Áp dụng security hardening theo từng bước (staged rollout), theo dõi connection drop rate trước/sau mỗi thay đổi.
- Thiết lập baseline monitoring cho tỷ lệ ORA-12537/ORA-03113 để phát hiện sớm regression sau hardening.

---

### Case 9: Listener password authentication fail (legacy 11g)

**1. Vấn đề / Mức độ ảnh hưởng**
🟢 DBA không thể quản trị listener từ xa qua password-protected commands (STOP/RELOAD) — không ảnh hưởng database operation nhưng cản trở công việc vận hành.

**2. Nguyên nhân**
Quên password đã set cho listener, hoặc password file bị corrupt/mất sau một thao tác filesystem.

**3. Thủ tục xử lý**
```bash
# Reset password (yêu cầu local OS access tới server, không qua remote password)
lsnrctl
LSNRCTL> SET PASSWORD
LSNRCTL> CHANGE_PASSWORD
LSNRCTL> SAVE_CONFIG
```

**4. Bài học kinh nghiệm**
Listener password (legacy feature, không khuyến dùng từ 11g+) là điểm yếu vận hành nếu không có quy trình quản lý password tập trung — Oracle khuyến nghị dùng Local OS Authentication thay vì password file cho listener.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Khuyến nghị: bỏ listener password, chuyển sang Local OS Authentication (mặc định từ 10g+, an toàn hơn).
- Nếu vẫn cần password, lưu trữ trong password vault tập trung (HashiCorp Vault/CyberArk) thay vì ghi nhớ thủ công.

---

### Case 10: Firewall chặn RAC interconnect sau security policy update

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Toàn bộ RAC cluster có nguy cơ split-brain hoặc node eviction hàng loạt — đây là sự cố nghiêm trọng nhất trong nhóm Network Security vì ảnh hưởng trực tiếp tới tính sẵn sàng của cluster.

**2. Nguyên nhân**
Một security policy mới (firewall rule tổng quát áp dụng toàn hạ tầng) vô tình áp dụng cả lên network interface dành riêng cho RAC interconnect — vốn cần thông suốt hoàn toàn, không firewall.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xác nhận interconnect bị chặn
ssh node2 'ping -c3 10.10.1.1'

# Bước 2: Kiểm tra firewall zone hiện tại
firewall-cmd --list-all --zone=trusted

# Bước 3: Đưa interface interconnect vào trusted zone NGAY LẬP TỨC
firewall-cmd --zone=trusted --add-interface=eth1 --permanent
firewall-cmd --reload

# Bước 4: Xác nhận cluster ổn định trở lại
crsctl check cluster -all
```

**4. Bài học kinh nghiệm**
RAC interconnect network PHẢI được loại trừ tường minh khỏi mọi security policy chung toàn hạ tầng — đây là yêu cầu kiến trúc, không phải tùy chọn. Một policy "áp dụng cho tất cả" mà không có exception cho infrastructure-critical network là antipattern nguy hiểm.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Document rõ ràng RAC interconnect interfaces trong CMDB/network inventory, đánh dấu "EXCLUDED FROM FIREWALL POLICY".
- Mọi thay đổi firewall policy tầm hạ tầng cần review riêng với DBA team trước khi áp dụng lên server có Oracle RAC.
- Thiết lập network-level monitoring riêng cho interconnect health (packet loss, latency) độc lập với security monitoring chung.

---

### Case 11: Oracle Connection Manager (CMAN) authentication fail

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Connections đi qua CMAN proxy bị từ chối — ảnh hưởng các client buộc phải route qua CMAN (thường do network segmentation/DMZ requirements).

**2. Nguyên nhân**
Rule trong `cman.ora` quá restrictive hoặc thiếu rule cho client mới, source IP/subnet chưa được include trong RULE_LIST.

**3. Thủ tục xử lý**
```bash
# Bước 1: Xem rule hiện tại
cat $TNS_ADMIN/cman.ora

# Bước 2: Thêm rule cho phép source mới
RULE_LIST=
  (RULE=
    (SRC=192.168.1.0/24)(DST=dbserver)(SRV=ORCL)
    (ACT=accept))

# Bước 3: Reload CMAN
cmctl reload
```

**4. Bài học kinh nghiệm**
CMAN rules cần được review song song với mọi thay đổi network topology của client tier — tương tự whitelist listener (Case 7), đây là điểm dễ bị "lãng quên cập nhật".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa CMAN rule review vào cùng quy trình với listener whitelist update (gộp chung 1 checklist).
- Test connectivity qua CMAN ngay sau mỗi thay đổi rule, không đợi user báo lỗi.

---

### Case 12: ORA-12545 — Connect failed because target host or object does not exist (DNS issue post security change)

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Kết nối thất bại do không resolve được hostname — có thể ảnh hưởng diện rộng nếu DNS server dùng chung bị thay đổi cấu hình.

**2. Nguyên nhân**
DNS server settings bị điều chỉnh do security policy (ví dụ chuyển sang DNS nội bộ mới, hoặc filtering DNS theo security gateway) mà chưa kiểm tra tác động tới Oracle SCAN/hostname resolution.

**3. Thủ tục xử lý**
```bash
# Bước 1: Test resolution trực tiếp
nslookup dbserver.vietdba.local
nslookup orcl-scan.vietdba.local  # Nếu RAC

# Bước 2: Kiểm tra DNS config hiện tại
cat /etc/resolv.conf

# Bước 3: Khôi phục/sửa DNS server đúng, hoặc thêm /etc/hosts entry tạm thời nếu khẩn cấp
echo "192.168.1.10 dbserver.vietdba.local" >> /etc/hosts
```

**4. Bài học kinh nghiệm**
DNS là dependency âm thầm nhưng critical cho Oracle Net — đặc biệt với SCAN (RAC) cần DNS round-robin đúng cách. Thay đổi DNS infrastructure cần test riêng với Oracle connectivity trước khi rollout toàn diện.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa "Oracle DB hostname/SCAN resolution test" vào checklist bắt buộc trước mọi thay đổi DNS infrastructure.
- Cân nhắc dùng `/etc/hosts` làm backup resolution cho các hostname Oracle quan trọng (không thay thế DNS nhưng làm fallback).
- Monitor DNS resolution latency/availability riêng cho các Oracle service names.

---

## NHÓM B: AUTHENTICATION (Case 13-25)

### Case 13: ORA-01017 — invalid username/password; logon denied

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 User/application không đăng nhập được — nếu là service account của hệ thống tích hợp, có thể gây gián đoạn batch job hoặc real-time integration.

**2. Nguyên nhân**
Sai mật khẩu thực sự, hoặc do `sec_case_sensitive_logon=TRUE` (mặc định từ 11g) khiến password case-sensitive trong khi application cũ gửi password không đúng case.

**3. Thủ tục xử lý**
```sql
SELECT username, account_status FROM dba_users WHERE username='APP_USER';
SHOW PARAMETER sec_case_sensitive_logon;
ALTER USER app_user IDENTIFIED BY "CorrectPass_2026!";
```

**4. Bài học kinh nghiệm**
Khi migrate ứng dụng cũ (pre-11g logic) sang Oracle mới, case-sensitivity password là nguồn lỗi ẩn phổ biến — cần test kỹ phần authentication trong UAT.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Document rõ password policy (case-sensitive) trong onboarding guide cho dev team; thêm kiểm tra case-sensitivity vào test plan trước go-live của mọi ứng dụng mới kết nối DB.

---

### Case 14: ORA-28000 — the account is locked

**1. Vấn đề / Mức độ ảnh hưởng**
🟡-🔴 Account bị khóa hoàn toàn sau N lần login fail — nếu là service account chạy job tự động, có thể leo thang thành sự cố nghiêm trọng (toàn bộ batch processing dừng).

**2. Nguyên nhân**
Vượt quá `FAILED_LOGIN_ATTEMPTS` trong profile, thường do: credential sai trong config application (sau khi đổi password mà quên update connection string ở nhiều nơi), hoặc brute-force attack thực sự.

**3. Thủ tục xử lý**
```sql
SELECT username, account_status, lock_date FROM dba_users WHERE username='APP_USER';
ALTER USER app_user ACCOUNT UNLOCK;

-- Điều tra nguyên nhân TRƯỚC KHI unlock (phân biệt lỗi config vs tấn công)
SELECT event_timestamp, userhost, return_code FROM unified_audit_trail
WHERE action_name='LOGON' AND db_username='APP_USER' AND return_code!=0
  AND event_timestamp > SYSDATE-1 ORDER BY event_timestamp DESC;
```

**4. Bài học kinh nghiệm**
Không nên unlock ngay lập tức mà chưa điều tra — nếu là tấn công brute-force, unlock vội sẽ tiếp tục bị tấn công. Cần phân biệt rõ "lỗi vận hành" và "sự cố bảo mật" trước khi hành động.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Centralize quản lý credentials (Vault/Secret Manager), tránh hardcode password ở nhiều nơi dễ quên đồng bộ.
- Thiết lập alert real-time khi có account bị lock, kèm thông tin nguồn IP để phân loại nhanh.
- Với service account, cân nhắc whitelist IP kết hợp profile riêng ít nghiêm ngặt hơn user thường nhưng có compensating controls khác.

---

### Case 17: ORA-28003 — password verification for the specified password failed

**1. Vấn đề / Mức độ ảnh hưởng**
🟢 User không đổi được password do không đạt độ phức tạp yêu cầu — gây phiền toái vận hành, không phải sự cố bảo mật.

**2. Nguyên nhân**
`PASSWORD_VERIFY_FUNCTION` trong profile yêu cầu password đạt chuẩn (hoa/thường/số/ký tự đặc biệt) nhưng user đặt password đơn giản.

**3. Thủ tục xử lý**
```sql
SELECT profile, limit FROM dba_profiles
WHERE resource_name='PASSWORD_VERIFY_FUNCTION'
  AND profile=(SELECT profile FROM dba_users WHERE username='APP_USER');
ALTER USER app_user IDENTIFIED BY "Strong_Pass_2026!";
```

**4. Bài học kinh nghiệm**
Đây là tính năng bảo mật hoạt động đúng thiết kế — "lỗi" này thực chất là cơ chế bảo vệ. Cần communicate rõ password policy cho end-user thay vì coi đây là bug.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Hiển thị rõ password complexity requirement ngay tại UI đổi password (nếu có self-service portal) để giảm số lần thử-sai của user.

---

### Case 20: Proxy Authentication — ORA-28150 proxy not authorized

**1. Vấn đề / Mức độ ảnh hưởng**
🟡 Middleware/application server dùng connection pooling qua proxy user không connect được tới target user — ảnh hưởng các ứng dụng dùng kiến trúc proxy authentication (phổ biến trong J2EE connection pools).

**2. Nguyên nhân**
Thiếu grant `CONNECT THROUGH` giữa proxy user và target user, hoặc grant bị revoke nhầm trong một đợt security cleanup.

**3. Thủ tục xử lý**
```sql
SELECT * FROM proxy_users WHERE proxy='APP_PROXY';
ALTER USER app_user GRANT CONNECT THROUGH app_proxy;
-- Test: CONNECT app_proxy[app_user]/proxy_password@ORCL
```

**4. Bài học kinh nghiệm**
Proxy authentication relationships dễ bị "quên" trong các đợt audit/cleanup vì không hiển thị rõ ràng như grant thông thường — cần document riêng các proxy relationships đang active.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Maintain một bảng tham chiếu riêng (ngoài DB, trong CMDB) liệt kê tất cả proxy authentication relationships và mục đích sử dụng, review định kỳ cùng security audit.

---

### Case 26: Password File — ORA-01999 password file cannot be opened

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Không thể kết nối SYSDBA — nghiêm trọng vì đây thường là cách duy nhất để DBA can thiệp khẩn cấp vào database, đặc biệt khi database đang ở trạng thái bất thường cần startup/recovery.

**2. Nguyên nhân**
Password file bị corrupt, xóa nhầm, hoặc bị ghi đè bởi thao tác `orapwd` không đúng trong quá trình patch/upgrade.

**3. Thủ tục xử lý**
```bash
ls -la $ORACLE_HOME/dbs/orapw$ORACLE_SID
orapwd file=$ORACLE_HOME/dbs/orapwORCL password="Oracle_2026!" force=y
```
```sql
SHOW PARAMETER remote_login_passwordfile;
```

**4. Bài học kinh nghiệm**
Password file là "chìa khóa cuối cùng" để truy cập DB khi mọi authentication khác fail — mất file này trong tình huống khẩn cấp (DB down) sẽ kéo dài thời gian phục hồi đáng kể.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Backup password file định kỳ cùng với backup configuration files khác (`$ORACLE_HOME/dbs/*`).
- Đưa vào checklist post-patch validation: xác nhận password file vẫn hoạt động ngay sau patch/upgrade.
- Document SYS password ở nơi an toàn (vault) để có thể `orapwd force=y` khẩn cấp khi cần.

---

### Case 27: SYS password sync fail giữa Primary-Standby (DataGuard)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Standby database không thể nhận redo từ Primary qua RFS (Remote File Server) vì xác thực thất bại — nguy cơ Standby bị lag không giới hạn, ảnh hưởng trực tiếp tới RPO của giải pháp DR.

**2. Nguyên nhân**
Password file không được đồng bộ sau khi đổi SYS password trên Primary (thao tác đổi password thường chỉ thực hiện 1 phía mà quên propagate).

**3. Thủ tục xử lý**
```bash
scp $ORACLE_HOME/dbs/orapwORCL oracle@standby:$ORACLE_HOME/dbs/orapwORCL_STB
```
```sql
-- Verify trên Standby
SELECT name, value FROM v$dataguard_stats WHERE name='transport lag';
```

**4. Bài học kinh nghiệm**
Mọi thay đổi SYS/SYSTEM password trên Primary trong môi trường DataGuard PHẢI có quy trình đồng bộ ngay lập tức sang Standby — đây là dependency dễ bị bỏ sót vì không có lỗi tức thì (chỉ phát hiện khi cần failover).

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Đưa "sync password file to all standbys" thành bước bắt buộc trong runbook đổi SYS password.
- Script tự động hóa: mỗi lần đổi SYS password, trigger luôn copy file sang tất cả standby servers.
- Monitor định kỳ RFS connectivity test (không chỉ apply lag) để phát hiện sớm vấn đề authentication.

---

## NHÓM C: AUTHORIZATION (Case 31-45)

### Case 31: ORA-01031 — insufficient privileges

**1. Vấn đề / Mức độ ảnh hưởng**
🟢-🟡 Thao tác cụ thể (DDL/DML) bị từ chối — mức độ tùy theo business criticality của thao tác đó; nếu là thao tác phục vụ end-of-day batch quan trọng có thể leo thang mức độ.

**2. Nguyên nhân**
User chưa được cấp quyền cần thiết, hoặc quyền đã bị revoke trong một đợt security hardening mà chưa kiểm tra đầy đủ tác động.

**3. Thủ tục xử lý**
```sql
SELECT * FROM session_privs WHERE privilege LIKE '%TABLE%';
SELECT grantee, privilege FROM dba_sys_privs WHERE grantee='APP_USER';
GRANT CREATE TABLE TO app_user;
```

**4. Bài học kinh nghiệm**
Privilege revocation trong security hardening cần test đầy đủ với application trước khi áp dụng production — "principle of least privilege" đúng đắn nhưng cần xác định chính xác "least" là gì qua Privilege Analysis (xem Case 48 SK10-04 cũ) trước khi revoke.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
Luôn chạy `DBMS_PRIVILEGE_CAPTURE` trong vài tuần trước khi thực hiện privilege reduction trên production, đảm bảo capture đủ business cycle (cuối tháng, cuối quý).

---

### Case 35: VPD Policy — ORA-28113 policy predicate has error

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 RỦI RO BẢO MẬT NGHIÊM TRỌNG — policy function lỗi có thể khiến VPD fail-open (cho phép truy cập không filter) thay vì fail-closed, dẫn đến data leak giữa các tenant/department.

**2. Nguyên nhân**
Bug trong policy function PL/SQL (exception không được handle đúng, hoặc logic SQL trong function có lỗi cú pháp/runtime).

**3. Thủ tục xử lý**
```sql
SELECT object_name, policy_name, function FROM dba_policies WHERE object_name='EMPLOYEES';
-- Test policy function riêng biệt, KHÔNG qua production traffic
SELECT fn_emp_security('HR','EMPLOYEES') FROM dual;
-- Nếu lỗi, tạm thời disable policy và CHẶN TRUY CẬP TỪ APPLICATION LAYER
-- cho đến khi fix xong (KHÔNG để DB chạy "fail open")
EXEC DBMS_RLS.ENABLE_POLICY('HR','EMPLOYEES','POLICY_NAME', FALSE);
```

**4. Bài học kinh nghiệm**
VPD policy function PHẢI được thiết kế "fail closed" (return predicate hạn chế nhất khi có exception), không bao giờ để fail "mở toang". Đây là nguyên tắc thiết kế bảo mật cơ bản nhưng dễ bị bỏ qua khi viết policy function vội vàng.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Mọi VPD policy function PHẢI có `EXCEPTION WHEN OTHERS THEN RETURN '1=2';` (deny all) làm fallback, không bao giờ để exception propagate ra ngoài hoặc return NULL/empty (= cho phép tất cả).
- Unit test policy function với các edge case (NULL context, user không tồn tại trong mapping table, v.v.) trước khi deploy.
- Code review bắt buộc cho mọi policy function mới bởi security-focused reviewer.

---

### Case 36: VPD — Policy không apply (data leak risk!)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 RỦI RO BẢO MẬT CỰC KỲ NGHIÊM TRỌNG — multi-tenant data bị lộ chéo giữa các tenant, vi phạm compliance nghiêm trọng (GDPR, PCI-DSS) nếu không phát hiện kịp thời.

**2. Nguyên nhân**
User có privilege `EXEMPT ACCESS POLICY` (thường cấp nhầm cho service account hoặc trong quá trình troubleshooting rồi quên revoke) khiến VPD policy bị bypass hoàn toàn.

**3. Thủ tục xử lý**
```sql
-- Bước 1: Xác nhận policy enabled
SELECT policy_name, enable FROM dba_policies WHERE object_name='EMPLOYEES';

-- Bước 2: KIỂM TRA NGAY users có EXEMPT (đây là root cause phổ biến nhất)
SELECT grantee FROM dba_sys_privs WHERE privilege='EXEMPT ACCESS POLICY';

-- Bước 3: Revoke ngay lập tức nếu không cần thiết
REVOKE EXEMPT ACCESS POLICY FROM app_user;

-- Bước 4: Đánh giá scope of impact - đã có data nào bị truy cập sai chưa
SELECT * FROM unified_audit_trail WHERE db_username='APP_USER'
  AND object_name='EMPLOYEES' AND event_timestamp > <thời_điểm_cấp_EXEMPT>;
```

**4. Bài học kinh nghiệm**
`EXEMPT ACCESS POLICY` là privilege CỰC KỲ nguy hiểm — vô hiệu hóa MỌI VPD policy trong toàn database, không chỉ 1 policy cụ thể. Đây phải được coi như SYSDBA-level privilege về mức độ rủi ro.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- KHÔNG BAO GIỜ cấp `EXEMPT ACCESS POLICY` cho application service account, kể cả tạm thời để "debug nhanh".
- Audit policy riêng theo dõi mọi GRANT/REVOKE của privilege này (xem SK04-01), alert real-time khi có thay đổi.
- Định kỳ (hàng tháng) chạy script kiểm tra danh sách users có EXEMPT, review từng trường hợp với security team.

---

### Case 39: Database Vault — DBA bị khóa hoàn toàn khỏi realm sau khi enable

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 LOCKOUT TOÀN DIỆN — DBA team mất khả năng quản trị các objects trong Realm bảo vệ, có thể dẫn đến không thể thực hiện maintenance/troubleshooting khẩn cấp.

**2. Nguyên nhân**
Enable Database Vault mà chưa thiết lập đầy đủ DV_OWNER account riêng biệt, hoặc quên authorize DBA group vào Realm cần thiết trước khi Vault có hiệu lực.

**3. Thủ tục xử lý**
```sql
-- PHẢI dùng DV_OWNER account (KHÔNG PHẢI SYS) để fix
-- Login với DV_OWNER:
BEGIN
  DVSYS.DBMS_MACADM.ADD_AUTH_TO_REALM(
    realm_name=>'AFFECTED_REALM', grantee=>'DBA_USER',
    auth_options=>DVSYS.DBMS_MACUTL.G_REALM_AUTH_OWNER);
END;
/
```

**4. Bài học kinh nghiệm**
Database Vault là tính năng "separation of duties" theo đúng nghĩa đen — SYS/SYSTEM KHÔNG còn toàn quyền sau khi enable. Đây là thay đổi tư duy vận hành căn bản, cần training đầy đủ cho team trước khi triển khai, không chỉ là "thêm 1 feature bảo mật".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- TRƯỚC KHI enable Database Vault: tạo VÀ TEST KỸ ít nhất 2 DV_OWNER accounts riêng biệt (tránh single point of failure), lưu credentials ở nơi an toàn tách biệt khỏi SYS password.
- Thực hiện dry-run đầy đủ trên môi trường staging với cùng Realm configuration trước khi áp dụng production.
- Document quy trình "break glass" (truy cập khẩn cấp) rõ ràng, test định kỳ (giống disaster recovery drill).

---

### Case 43: PUBLIC role có quyền quá rộng (security audit finding)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 RỦI RO BẢO MẬT HỆ THỐNG — bất kỳ user nào có thể login vào DB đều có thể khai thác các package nguy hiểm (UTL_HTTP, UTL_TCP) để thực hiện exfiltration hoặc lateral movement, đây là finding phổ biến nhất trong mọi security audit Oracle.

**2. Nguyên nhân**
Default Oracle installation cấp EXECUTE cho PUBLIC trên nhiều packages mạnh mẽ — đây là legacy behavior từ các version cũ, ít khi được dọn dẹp sau khi go-live.

**3. Thủ tục xử lý**
```sql
-- Đánh giá scope hiện tại
SELECT table_name, privilege FROM dba_tab_privs WHERE grantee='PUBLIC'
  AND privilege IN ('EXECUTE','SELECT','INSERT','UPDATE','DELETE')
  AND table_name IN ('UTL_HTTP','UTL_TCP','UTL_SMTP','UTL_FILE','DBMS_ADVISOR');

-- Revoke từng package, sau đó grant specific cho users thực sự cần
REVOKE EXECUTE ON UTL_HTTP FROM PUBLIC;
REVOKE EXECUTE ON UTL_TCP FROM PUBLIC;
GRANT EXECUTE ON UTL_HTTP TO app_integration_user;
```

**4. Bài học kinh nghiệm**
"Đây luôn là default" không có nghĩa là "an toàn" — cần baseline security hardening (theo CIS Benchmark) ngay từ ngày đầu go-live, không đợi đến security audit phát hiện.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Áp dụng CIS Oracle Database Benchmark hardening script NGAY trong giai đoạn build/provisioning database, trước khi go-live.
- Đưa "PUBLIC grant audit" vào checklist security review định kỳ hàng quý.
- Test kỹ application functionality sau khi revoke để đảm bảo không phá vỡ tính năng hợp lệ đang dùng các package này.

---

## NHÓM D: TDE / DATA PROTECTION (Case 56-65)

### Case 56: ORA-28365 — wallet is not open

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Database hoàn toàn không truy cập được encrypted tablespaces/columns — nếu toàn bộ database dùng TDE Tablespace Encryption, đây tương đương DB DOWN cho mọi hoạt động.

**2. Nguyên nhân**
Phổ biến nhất sau DB restart mà không dùng auto-login wallet (chỉ password wallet), DBA quên mở wallet thủ công; hoặc auto-login wallet file bị mất/corrupt.

**3. Thủ tục xử lý**
```sql
SELECT status, wallet_type FROM v$encryption_wallet;
ADMINISTER KEY MANAGEMENT SET KEYSTORE OPEN
  IDENTIFIED BY "WalletPass_2026!" CONTAINER=ALL;
```

**4. Bài học kinh nghiệm**
Đây là lỗi vận hành cực kỳ phổ biến sau MỌI lần restart database có TDE — cần đưa vào automation/startup script thay vì phụ thuộc trí nhớ con người.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Sử dụng Auto-login Wallet (hoặc Local Auto-login Wallet cho bảo mật cao hơn) cho production để loại bỏ hoàn toàn dependency vào thao tác thủ công.
- Nếu bắt buộc dùng Password Wallet (do compliance yêu cầu manual intervention), tích hợp vào startup trigger hoặc script với credential lưu trong vault, KHÔNG để DBA phải nhớ gõ lệnh.
- Monitoring: alert ngay khi `v$encryption_wallet.status != 'OPEN'` sau mỗi lần database startup.

---

### Case 59: TDE wallet password quên/mất

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 THẢM HỌA DỮ LIỆU TIỀM TÀNG — nếu không có auto-login wallet hoạt động và password bị mất hoàn toàn không có backup, dữ liệu encrypted có thể KHÔNG THỂ PHỤC HỒI VĨNH VIỄN.

**2. Nguyên nhân**
Password không được lưu trữ đúng quy trình (chỉ 1 người biết, không có backup, hoặc lưu ở nơi cũng bị mất cùng lúc với sự cố khác).

**3. Thủ tục xử lý**
```bash
# Bước 1: Kiểm tra có auto-login wallet hoạt động không (đường thoát duy nhất)
ls -la $WALLET_LOCATION/cwallet.sso
sqlplus / as sysdba <<< "SELECT status, wallet_type FROM v\$encryption_wallet;"

# Nếu auto-login đang hoạt động: dữ liệu vẫn an toàn, nhưng cần
# NGAY LẬP TỨC backup wallet và set lại password mới có kiểm soát

# Nếu KHÔNG có auto-login và mất hoàn toàn password:
# → Liên hệ Oracle Support NGAY để được tư vấn các phương án còn lại
# → Trong nhiều trường hợp, KHÔNG CÓ CÁCH RECOVER nếu mất cả password và backup
```

**4. Bài học kinh nghiệm**
Đây là rủi ro nghiêm trọng nhất trong toàn bộ phạm vi bảo mật Oracle — không giống các lỗi khác có thể "fix", mất TDE wallet password hoàn toàn CÓ THỂ KHÔNG THỂ KHẮC PHỤC. Phòng ngừa quan trọng hơn xử lý sự cố trong trường hợp này.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- BẮT BUỘC: lưu wallet password vào Enterprise Password Vault (không phải file text, không phải 1 người nhớ) với quy trình truy cập có kiểm soát (ít nhất 2 người biết, tách biệt).
- BẮT BUỘC: backup wallet định kỳ (`ADMINISTER KEY MANAGEMENT BACKUP KEYSTORE`) vào vị trí an toàn, tách biệt hoàn toàn về mặt vật lý/logic với primary wallet location.
- Test quy trình "wallet recovery" định kỳ (giống DR drill) để xác nhận backup thực sự dùng được, không chỉ tồn tại trên giấy.
- Cân nhắc dùng Oracle Key Vault (OKV) cho enterprise-scale key management thay vì file-based wallet quản lý thủ công.

---

### Case 61: DataGuard Standby — TDE wallet không match Primary

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 Standby database không thể apply redo từ Primary (không decrypt được) — giải pháp DR hoàn toàn không hoạt động, RPO/RTO commitment bị vi phạm nghiêm trọng nếu cần failover thực sự.

**2. Nguyên nhân**
Wallet không được đồng bộ khi setup DataGuard ban đầu, hoặc Master Key được rotate trên Primary mà quên export/import sang Standby.

**3. Thủ tục xử lý**
```sql
-- Trên Primary: export keys
ADMINISTER KEY MANAGEMENT EXPORT ENCRYPTION KEYS
  WITH SECRET "TransferSecret" TO '/tmp/keys.p12'
  IDENTIFIED BY "WalletPass_2026!";
```
```bash
scp /tmp/keys.p12 oracle@standby:/tmp/
```
```sql
-- Trên Standby: import keys
ADMINISTER KEY MANAGEMENT IMPORT ENCRYPTION KEYS
  WITH SECRET "TransferSecret" FROM '/tmp/keys.p12'
  IDENTIFIED BY "WalletPass_2026!" WITH BACKUP;
```

**4. Bài học kinh nghiệm**
Key Rotation (best practice bảo mật hàng năm) PHẢI đi kèm quy trình đồng bộ sang TẤT CẢ standby databases ngay lập tức — đây là bước dễ bị tách rời khỏi quy trình rotation chính nếu không có checklist tích hợp.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Tích hợp "export/import keys to all standbys" như BƯỚC BẮT BUỘC cuối cùng trong mọi runbook Key Rotation, không coi là optional follow-up.
- Định kỳ test DataGuard switchover/failover trên môi trường staging có TDE để xác nhận key sync hoạt động đúng trước khi cần dùng thật.
- Cân nhắc Oracle Key Vault cho môi trường có nhiều Standby/multi-site để đơn giản hóa việc đồng bộ key tập trung.

---

## NHÓM E: AUDITING / COMPLIANCE (Case 81-90)

### Case 81: Unified Audit Trail tăng trưởng quá nhanh, fill SYSAUX

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 SYSAUX tablespace đầy có thể ảnh hưởng nhiều thành phần khác của database (AWR, Statistics, các components dùng chung SYSAUX), tiềm ẩn nguy cơ database instability nếu không xử lý kịp thời.

**2. Nguyên nhân**
Policy audit quá rộng (`ACTIONS ALL` không có điều kiện lọc) kết hợp với việc chưa thiết lập purge job tự động — audit data tích lũy vô hạn.

**3. Thủ tục xử lý**
```sql
SELECT occupant_name, space_usage_kbytes/1024/1024 GB
FROM v$sysaux_occupants WHERE occupant_name LIKE '%AUDIT%';

EXEC DBMS_AUDIT_MGMT.CLEAN_AUDIT_TRAIL(
  audit_trail_type=>DBMS_AUDIT_MGMT.AUDIT_TRAIL_UNIFIED,
  use_last_arch_timestamp=>FALSE);
```

**4. Bài học kinh nghiệm**
Enable audit policy mà không kèm theo retention/purge strategy là thiết kế không hoàn chỉnh — 2 việc này phải được triển khai ĐỒNG THỜI, không phải "enable trước, lo purge sau".

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- Mọi audit policy mới khi tạo PHẢI đi kèm việc thiết lập purge job tương ứng trong cùng change request.
- Monitor SYSAUX usage trend định kỳ (weekly), alert sớm trước khi đạt ngưỡng nguy hiểm (xem SK09-02).
- Cân nhắc archive audit data ra storage riêng (compliance-grade, ví dụ AVDF) thay vì giữ vô hạn trong SYSAUX.

---

### Case 90: Audit policy WHEN condition luôn FALSE (logic error, không audit gì)

**1. Vấn đề / Mức độ ảnh hưởng**
🔴 RỦI RO COMPLIANCE NGHIÊM TRỌNG — tổ chức TIN RẰNG đang audit đầy đủ nhưng thực tế không có record nào được tạo ra; nếu phát hiện trong một cuộc điều tra/audit chính thức, đây là vi phạm nghiêm trọng có thể dẫn đến hậu quả pháp lý.

**2. Nguyên nhân**
Lỗi logic trong biểu thức `WHEN` condition của audit policy (ví dụ so sánh sai kiểu dữ liệu, hoặc dùng context attribute không tồn tại khiến điều kiện luôn đánh giá FALSE).

**3. Thủ tục xử lý**
```sql
-- Test condition riêng biệt để xác nhận pattern
SELECT CASE WHEN <copy_exact_when_condition> THEN 'TRUE' ELSE 'FALSE' END test_result
FROM dual;

-- Nếu xác nhận luôn FALSE, fix logic và recreate policy
NOAUDIT POLICY broken_policy;
DROP AUDIT POLICY broken_policy;
CREATE AUDIT POLICY broken_policy
  ACTIONS SELECT ON hr.salary_data
  WHEN 'SYS_CONTEXT(''USERENV'',''SESSION_USER'') != ''HR_ADMIN'''  -- Verify đúng syntax
  EVALUATE PER ACCESS;
AUDIT POLICY broken_policy;
```

**4. Bài học kinh nghiệm**
"Policy đã tạo và enable" KHÔNG đồng nghĩa với "đang hoạt động đúng" — đây là loại lỗi silent failure nguy hiểm nhất vì không có error message, chỉ là thiếu data mà không ai để ý cho đến khi cần.

**5. Biện pháp phòng ngừa từ sớm, từ xa**
- BẮT BUỘC: ngay sau khi tạo audit policy mới, thực hiện test có chủ đích (deliberate test action) để XÁC NHẬN record audit thực sự được tạo ra trong `unified_audit_trail`.
- Thiết lập "audit health check" định kỳ: script kiểm tra mỗi policy quan trọng có sinh ra ít nhất N records trong khung thời gian kỳ vọng (dựa trên baseline hoạt động bình thường), alert nếu phát hiện policy "im lặng" bất thường.
- Đưa việc verify audit policy hoạt động đúng vào quy trình UAT/penetration testing định kỳ.

---

## TỔNG KẾT — QUICK REFERENCE TABLE

```
21 Case Studies được chọn lọc kỹ theo tiêu chí:
  - Tần suất gặp phải cao trong thực tế vận hành
  - Mức độ ảnh hưởng nghiêm trọng (đặc biệt các case 🔴)
  - Tính đại diện cho từng layer bảo mật Oracle

Phân bổ theo nhóm:
  Nhóm A (Network Security):       12 cases — Case 1-12
  Nhóm B (Authentication):          5 cases — Case 13,14,17,20,26,27
  Nhóm C (Authorization):           5 cases — Case 31,35,36,39,43
  Nhóm D (TDE/Data Protection):     3 cases — Case 56,59,61
  Nhóm E (Audit/Compliance):        2 cases — Case 81,90

Top 5 Case NGHIÊM TRỌNG NHẤT (🔴 cần ưu tiên đọc trước):
  1. Case 59  — TDE wallet password mất (data loss vĩnh viễn)
  2. Case 36  — VPD EXEMPT ACCESS POLICY (data leak cross-tenant)
  3. Case 39  — Database Vault lockout DBA
  4. Case 10  — Firewall chặn RAC interconnect (cluster instability)
  5. Case 90  — Audit policy silent failure (compliance violation)
```

### Mẫu Template để tự viết thêm case mới (dùng nội bộ team)

```markdown
### Case N: [ORA-XXXXX / Tên vấn đề]

**1. Vấn đề / Mức độ ảnh hưởng**
[🔴/🟡/🟢] Mô tả triệu chứng quan sát được + tác động thực tế tới business/operations

**2. Nguyên nhân**
Root cause kỹ thuật, không chỉ "lỗi gì" mà còn "tại sao xảy ra"

**3. Thủ tục xử lý**
```sql/bash
-- Các bước theo thứ tự, có thể copy-paste chạy được
```

**4. Bài học kinh nghiệm**
Insight có giá trị cho cả team, không chỉ riêng người xử lý case này

**5. Biện pháp phòng ngừa từ sớm, từ xa**
H�nh động cụ thể, có thể action ngay để tránh lặp lại (không chỉ "cẩn thận hơn")
```

---

**Tài liệu tham khảo:**
- Oracle Database Security Guide 19c
- Oracle Database Error Messages 19c
- MOS Note 1228021.1 (TDE Best Practices), 1909451.1 (Unified Auditing), 207671.1 (Security Checklist)
- CIS Oracle Database Benchmark v2.x
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
