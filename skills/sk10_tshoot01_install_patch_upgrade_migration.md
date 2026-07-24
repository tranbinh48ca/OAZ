---
name: oracle-troubleshoot-install-patch-upgrade-migration
description: >
  100 case study khắc phục lỗi Cài đặt, Patching, Upgrading, Migration,
  Uninstall Oracle Database (Single Instance, RAC) 11g/12c/19c/21c/23ai/26ai.
  Kích hoạt khi hỏi về: lỗi cài đặt Oracle, install Oracle error,
  INS-xxxxx error Oracle, lỗi patch Oracle, OPatch failed,
  lỗi upgrade Oracle, AutoUpgrade failed, DBUA error,
  lỗi migration Oracle, expdp impdp failed, RMAN duplicate failed,
  lỗi uninstall Oracle, deinstall failed, prerequisite check failed,
  cluvfy failed, runInstaller error, root.sh failed,
  CRS-xxxxx install error, PRVF- error Oracle, gridSetup failed,
  catupgrd failed, preupgrade error, ORA-up-grade error.
---

# SK10-CASE-01 · Troubleshooting: Install, Patch, Upgrade, Migration, Uninstall

**Phạm vi:** Oracle 11g, 12c, 19c, 21c, 23ai, 26ai — Single Instance & RAC  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)  
**Số lượng case:** 100 cases thực chiến

---

## KIẾN TRÚC TỔNG QUAN LIFECYCLE

```
Oracle Database Lifecycle — Điểm các Failure Points
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ PREREQ   │──►│ INSTALL  │──►│  PATCH   │──►│ UPGRADE  │──►│MIGRATION │
│ CHECK    │   │          │   │          │   │          │   │          │
└────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘
     │              │              │              │              │
  Group A        Group B        Group C        Group D        Group E
  (Case 1-15)    (16-35)        (36-55)        (56-75)        (76-90)
     │              │              │              │              │
     ▼              ▼              ▼              ▼              ▼
  cluvfy        runInstaller   opatch apply   AutoUpgrade    expdp/impdp
  OS check      root.sh        datapatch      DBUA           RMAN duplicate
  Kernel        DBCA           OPatchAuto     catupgrd       GoldenGate
  params        Network        Conflict       Timezone       TTS

                                                          ┌──────────┐
                                                          │UNINSTALL │
                                                          │ (91-100) │
                                                          └──────────┘
                                                          deinstall
                                                          Cleanup

Failure Impact Levels:
  🔴 BLOCKING:  Không thể tiếp tục bước tiếp theo
  🟡 DEGRADED:  Tiếp tục được nhưng có vấn đề cần fix sau
  🟢 COSMETIC:  Warning, không ảnh hưởng chức năng
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## NHÓM A: PREREQUISITE CHECK FAILURES (Case 1-15)

### Case 1: PRVF-7530 — Sufficient physical memory

```
🔴 BLOCKING | cluvfy stage -pre crsinst

Triệu chứng: "Check failed on node node1: PRVF-7530: Sufficient
physical memory is not available on node"
```

```bash
# Chẩn đoán
free -g
cat /proc/meminfo | grep MemTotal

# Fix: Oracle yêu cầu tối thiểu 8GB cho RAC GI, 4GB single instance
# Nếu RAM thực sự thiếu → thêm RAM hoặc dùng -ignorePrereqFailure (testing only)
free -m
# Nếu đủ RAM nhưng vẫn fail: kiểm tra /proc/sys/vm/overcommit_memory
cat /proc/sys/vm/overcommit_memory  # Nên = 0 hoặc 1
```

### Case 2: PRVF-5436 — NTP daemon not running

```
🔴 BLOCKING | cluvfy RAC pre-install

Triệu chứng: "NTP Configuration check failed... NTP daemon not running"
```

```bash
# Fix
systemctl status chronyd
systemctl enable --now chronyd
chronyc tracking
# Verify sync trên TẤT CẢ nodes trước khi tiếp tục
ssh node2 'chronyc tracking'
```

### Case 3: PRVF-9802 — Attempt to get udev info failed

```
🟡 DEGRADED | cluvfy ASM disk check

Triệu chứng: "PRVF-9802: Attempt to get udev info from node failed"
```

```bash
# Chẩn đoán
ls -la /dev/oracleasm/disks/  # Nếu dùng oracleasm
udevadm info --query=all --name=/dev/sdb1

# Fix: Permissions sai trên ASM disks
chown grid:asmadmin /dev/CRS1
chmod 660 /dev/CRS1
# Reload udev rules
udevadm control --reload-rules
udevadm trigger
```

### Case 4: INS-13001 — Environment does not meet requirements

```
🔴 BLOCKING | runInstaller (mọi version)

Triệu chứng: Generic environment check fail screen
```

```bash
# Fix: Thường do thiếu package hoặc kernel param
# Xem chi tiết log
cat /tmp/OraInstall*/installActions*.log | grep -A10 "FAILED\|requirement"

# Common missing packages (RHEL 8/9)
dnf install -y oracle-database-preinstall-19c
```

### Case 5: PRVF-5640 — Free disk space not available

```
🔴 BLOCKING | cluvfy/runInstaller — /tmp space check

Triệu chứng: "PRVF-5640: Sufficient disk space not available at location: /tmp"
```

```bash
# Fix: cần tối thiểu 1-10GB tại /tmp tùy version
df -h /tmp
# Workaround: redirect TEMP/TMP environment variables
export TEMP=/u01/temp
export TMPDIR=/u01/temp
mkdir -p /u01/temp
chmod 1777 /u01/temp
```

### Case 6: PRVG-1101 — SCAN name could not be resolved

```
🔴 BLOCKING | cluvfy RAC — Network check

Triệu chứng: "PRVG-1101: SCAN name "orcl-scan" failed to resolve"
```

```bash
# Chẩn đoán
nslookup orcl-scan.vietdba.local
dig orcl-scan.vietdba.local

# Fix 1: DNS chưa cấu hình đúng — phải trả về 3 IPs
# Fix 2: Nếu test/dev không có DNS, dùng /etc/hosts (chỉ 1 IP, không HA thật)
echo "192.168.1.100 orcl-scan.vietdba.local orcl-scan" >> /etc/hosts
# Khuyến cáo: Production PHẢI dùng DNS round-robin, không dùng /etc/hosts
```

### Case 7: PRVF-4007 — User equivalence check failed

```
🔴 BLOCKING | cluvfy — SSH equivalence

Triệu chứng: "User equivalence check failed for user grid"
```

```bash
# Fix: SSH keys chưa setup đúng giữa nodes
su - grid
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
ssh-copy-id grid@node2
ssh-copy-id grid@node1  # Chính nó
# Test:
ssh node2 date  # Không được hỏi password
# Nếu vẫn fail: kiểm tra known_hosts, StrictHostKeyChecking
ssh -o StrictHostKeyChecking=no node2 date
```

### Case 8: PRVF-5449 — Check of Voting Disk location failed

```
🔴 BLOCKING | cluvfy — Voting disk

Triệu chứng: "Disk required for voting disk location not shared"
```

```bash
# Chẩn đoán — disk phải accessible TẤT CẢ nodes giống nhau
ssh node1 'ls -la /dev/CRS1'
ssh node2 'ls -la /dev/CRS1'

# Fix: Disk WWN không match — udev rules sai trên 1 trong các nodes
for dev in /dev/sd{b,c,d}; do
  /usr/lib/udev/scsi_id -g -u -d $dev
done
# Đảm bảo cùng WWN trên tất cả nodes → sửa udev rules cho khớp
```

### Case 9: PRVF-5637 — Check of swap space failed

```
🟡 DEGRADED | cluvfy — Swap check

Triệu chứng: "PRVF-5637: Insufficient swap space"
```

```bash
# Fix: Tạo swap file tạm
dd if=/dev/zero of=/swapfile bs=1G count=16
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
free -g
```

### Case 10: INS-32026 — Patches required to apply

```
🟡 DEGRADED | runInstaller — version compatibility

Triệu chứng: Installer yêu cầu apply patch trước khi install
```

```bash
# Fix: Download và apply prerequisite patches từ MOS
# Thường gặp khi cài 19c trên RHEL 8.4+ (cần patch OPatch trước)
cd $ORACLE_HOME
unzip -o /opt/patches/p6880880_190000_Linux-x86-64.zip
$ORACLE_HOME/OPatch/opatch version  # Verify updated
```

### Case 11: PRVF-0002 — Could not retrieve local nodename

```
🔴 BLOCKING | cluvfy — hostname resolution

Triệu chứng: "Could not retrieve local nodename"
```

```bash
# Fix: hostname không resolve được chính nó
hostname
hostname -f
cat /etc/hosts | grep $(hostname)
# Đảm bảo /etc/hosts có entry cho chính node đó
echo "127.0.0.1 $(hostname) $(hostname -s)" >> /etc/hosts
```

### Case 12: PRVF-7617 — node connectivity failed for interface

```
🔴 BLOCKING | cluvfy — network interface check

Triệu chứng: Interconnect interface không thể ping giữa nodes
```

```bash
# Chẩn đoán
ssh node1 'ping -c3 10.10.1.2'
ssh node2 'ping -c3 10.10.1.1'

# Fix: Firewall chặn interconnect traffic
firewall-cmd --zone=trusted --add-interface=eth1 --permanent
firewall-cmd --reload
# Hoặc tắt firewall hoàn toàn cho interconnect interface (nếu isolated network)
```

### Case 13: INS-08101 — Unexpected error while validating inventory

```
🟡 DEGRADED | runInstaller — Inventory

Triệu chứng: Central Inventory bị corrupt hoặc lock
```

```bash
# Fix
ls -la /u01/app/oraInventory
cat /u01/app/oraInventory/ContentsXML/inventory.xml
# Nếu corrupt, backup và xóa, để installer tạo mới
mv /u01/app/oraInventory /u01/app/oraInventory_bak
mkdir -p /u01/app/oraInventory
chown grid:oinstall /u01/app/oraInventory
```

### Case 14: PRVF-5648 — Check of resolv.conf failed

```
🟡 DEGRADED | cluvfy — DNS config

Triệu chứng: "More than one of the options NAMESERVER, DOMAIN, SEARCH defined"
```

```bash
cat /etc/resolv.conf
# Fix: Đảm bảo chỉ 1 dòng SEARCH hoặc DOMAIN (không cả 2)
# Chỉnh sửa /etc/resolv.conf — giữ 1 trong 2:
# search vietdba.local
# (xóa domain nếu đã có search)
```

### Case 15: CRS-1006 — node is not a member of cluster

```
🔴 BLOCKING | Grid install — Cluster verification

Triệu chứng: Node mới add không nhận diện được cluster hiện tại
```

```bash
# Chẩn đoán
crsctl query css votedisk
olsnodes -n

# Fix: Thường do GPnP profile chưa sync
$GRID_HOME/bin/gpnptool get
# Re-run addNode.sh với đầy đủ thông tin GPnP
```

---

## NHÓM B: INSTALLATION FAILURES (Case 16-35)

### Case 16: INS-20802 — Oracle Net Configuration Assistant failed

```
🟡 DEGRADED | DBCA — Listener setup

Triệu chứng: Listener không tạo được trong quá trình install
```

```bash
# Fix: Tạo listener thủ công sau khi install xong
netca /silent /responseFile /tmp/netca.rsp
# Hoặc đơn giản:
lsnrctl start LISTENER
# Nếu vẫn fail, kiểm tra port 1521 đã bị chiếm chưa
ss -tlnp | grep 1521
```

### Case 17: ORA-12546 — TNS:permission denied (sau install)

```
🟡 DEGRADED | Post-install connectivity

Triệu chứng: Không kết nối được sau khi cài xong
```

```bash
# Fix: File permissions sai trên socket/listener
chmod 755 $ORACLE_HOME/bin/oracle
ls -la $ORACLE_HOME/bin/oracle
# Phải có setuid bit nếu cần:
chmod 6751 $ORACLE_HOME/bin/oracle
```

### Case 18: root.sh failed — "/etc/oratab not found"

```
🔴 BLOCKING | Post-runInstaller — root.sh execution

Triệu chứng: root.sh báo lỗi không tìm thấy oratab
```

```bash
# Fix: Tạo /etc/oratab trống trước
touch /etc/oratab
chmod 664 /etc/oratab
chown oracle:oinstall /etc/oratab
# Re-run root.sh
$ORACLE_HOME/root.sh
```

### Case 19: DBCA fails — ORA-01034: ORACLE not available

```
🔴 BLOCKING | DBCA database creation

Triệu chứng: DBCA fail khi tạo database, ORA-01034
```

```bash
# Chẩn đoán
ps -ef | grep pmon
echo $ORACLE_SID
sqlplus / as sysdba << 'EOF'
STARTUP NOMOUNT;
EOF

# Fix: Thường do environment variables sai hoặc init.ora missing
# Kiểm tra $ORACLE_HOME/dbs/init<SID>.ora tồn tại
ls $ORACLE_HOME/dbs/
# Tạo pfile tối thiểu nếu thiếu
echo "db_name=ORCL" > $ORACLE_HOME/dbs/initORCL.ora
```

### Case 20: CRS-2674 — Start of resource failed (Grid install)

```
🔴 BLOCKING | Grid Infrastructure post-install

Triệu chứng: ASM hoặc CRS resource không start được
```

```bash
crsctl stat res -t -init
crsctl stat res ora.asm -v

# Xem log chi tiết
tail -100 $GRID_HOME/log/$(hostname)/agent/ohasd/oraagent_grid/oraagent_grid.log

# Fix thường gặp: ASM disk permission hoặc disk không accessible
ls -la /dev/CRS*
chown grid:asmadmin /dev/CRS*
chmod 660 /dev/CRS*
crsctl start res ora.asm -init
```

### Case 21: PRCR-1079 — Failed to start resource ora.crsd

```
🔴 BLOCKING | Grid Infrastructure — CRSD startup

Triệu chứng: CRSD daemon không start, cluster không hoạt động
```

```bash
# Chẩn đoán
crsctl stat res ora.crsd -init
tail -200 $GRID_HOME/log/$(hostname)/crsd/crsd.log

# Common cause: OCR corrupt hoặc voting disk issue
ocrcheck
crsctl query css votedisk

# Fix nếu OCR corrupt: restore từ backup
ocrconfig -restore /u01/app/grid/cdata/backup00.ocr
```

### Case 22: DBCA — ORA-19809: limit exceeded for recovery files

```
🟡 DEGRADED | DBCA database creation — FRA sizing

Triệu chứng: FRA quá nhỏ ngay khi tạo DB
```

```bash
# Fix: Tăng FRA size trong response file hoặc sau khi tạo
sqlplus / as sysdba << 'EOF'
ALTER SYSTEM SET db_recovery_file_dest_size = 50G SCOPE=BOTH;
EOF
```

### Case 23: INS-30131 — Initial setup required for the execution failed

```
🟡 DEGRADED | runInstaller — Pre-execution

Triệu chứng: Generic setup failure, thường do permissions
```

```bash
# Fix: Kiểm tra ownership của installation directories
chown -R oracle:oinstall /u01/app/oracle
chmod -R 775 /u01/app/oracle
# Re-run installer
```

### Case 24: ORA-00845 — MEMORY_TARGET not supported

```
🔴 BLOCKING | DBCA / Database startup post-install

Triệu chứng: Database không start với AMM (MEMORY_TARGET)
```

```bash
# Chẩn đoán — /dev/shm quá nhỏ
df -h /dev/shm

# Fix: Tăng /dev/shm size
mount -o remount,size=8G /dev/shm
# Permanent: edit /etc/fstab
echo "tmpfs /dev/shm tmpfs defaults,size=16g 0 0" >> /etc/fstab
```

### Case 25: DBCA template creation hangs

```
🟡 DEGRADED | DBCA — Silent mode hang

Triệu chứng: DBCA chạy mãi không kết thúc khi tạo database
```

```bash
# Chẩn đoán: process có đang chạy thật không hay đã hang
ps -ef | grep dbca
tail -f $ORACLE_BASE/cfgtoollogs/dbca/$ORACLE_SID/trace.log_*

# Fix: thường do disk I/O chậm hoặc ASM chưa sẵn sàng
# Kiểm tra ASM
asmcmd lsdg
# Nếu cần kill và retry:
kill -9 $(pgrep -f dbca)
dbca -silent -deleteDatabase -sourceDB ORCL 2>/dev/null
# Retry với cấu hình storage rõ ràng hơn
```

### Case 26: ORA-12537 — TNS connection closed (RAC instance)

```
🟡 DEGRADED | Post RAC install — connection issue

Triệu chứng: Kết nối qua SCAN bị đóng đột ngột
```

```bash
# Fix: SCAN listener chưa đăng ký service đầy đủ
srvctl status scan_listener
lsnrctl services LISTENER_SCAN1
# Force re-register
sqlplus / as sysdba << 'EOF'
ALTER SYSTEM REGISTER;
EOF
```

### Case 27: addNode.sh — CRS-1013: resource not unique

```
🔴 BLOCKING | RAC Add Node

Triệu chứng: Resource đã tồn tại khi add node thứ N
```

```bash
# Fix: Cleanup leftover resources từ attempt trước
crsctl stat res -t | grep node4
crsctl delete resource ora.node4.vip -f
# Retry addNode.sh
```

### Case 28: OUI — "[INS-30131] Failed to access temporary location"

```
🟡 DEGRADED | runInstaller temp directory access

Triệu chứng: Không truy cập được temp dir
```

```bash
# Fix: Thường do /tmp mounted noexec
mount | grep /tmp
# Nếu noexec, dùng custom temp:
./runInstaller -J"-Djava.io.tmpdir=/u01/tmp"
```

### Case 29: DBCA fails with "PDB Already Exists" (CDB creation)

```
🟡 DEGRADED | DBCA CDB+PDB creation

Triệu chứng: PDB tên trùng từ attempt trước đó còn sót lại
```

```sql
-- Cleanup leftover PDB
SELECT con_id, name, open_mode FROM v$pdbs;
ALTER PLUGGABLE DATABASE orclpdb CLOSE IMMEDIATE;
DROP PLUGGABLE DATABASE orclpdb INCLUDING DATAFILES;
```

### Case 30: ASM disk discovery shows no candidate disks

```
🔴 BLOCKING | Grid install — ASM disk setup

Triệu chứng: DBCA/ASMCA không thấy disk nào để tạo diskgroup
```

```bash
# Chẩn đoán
asmcmd lsdsk --candidate
ls -la /dev/oracleasm/disks/ 2>/dev/null
ls -la /dev/CRS* /dev/DATA* 2>/dev/null

# Fix: kiểm tra ASM_DISKSTRING parameter
sqlplus / as sysasm << 'EOF'
SHOW PARAMETER asm_diskstring;
EOF
# Set đúng pattern:
ALTER SYSTEM SET asm_diskstring='/dev/CRS*','/dev/DATA*' SCOPE=BOTH;
```

### Case 31: Grid install — gpnpd fails to start

```
🔴 BLOCKING | Grid Infrastructure — GPnP daemon

Triệu chứng: gpnpd không start, ảnh hưởng toàn bộ cluster bootstrap
```

```bash
tail -100 $GRID_HOME/log/$(hostname)/gpnpd/gpnpd.log
# Common cause: profile.xml corrupt
$GRID_HOME/bin/gpnptool check -p=$GRID_HOME/gpnp/$(hostname)/profiles/peer/profile.xml
# Nếu corrupt, có thể cần re-extract từ OCR (advanced, contact Oracle Support)
```

### Case 32: ORA-29807 — specified operator class does not exist

```
🟡 DEGRADED | Post-install — Oracle Text/Spatial component

Triệu chứng: Component không cài đặt đúng (thường options không chọn lúc install)
```

```sql
-- Verify component status
SELECT comp_name, status FROM dba_registry WHERE comp_name LIKE '%Text%';
-- Cài lại nếu cần (chạy script catctx.sql etc. - tham khảo Oracle Text Guide)
```

### Case 33: Network configuration assistant — multiple listener conflict

```
🟡 DEGRADED | Install — multiple Oracle Home conflict

Triệu chứng: Conflict giữa listener của Oracle Home cũ và mới
```

```bash
# Fix: Đảm bảo chỉ 1 listener active, hoặc dùng port khác
lsnrctl status
# Stop listener cũ nếu không cần:
$OLD_ORACLE_HOME/bin/lsnrctl stop
# Start listener mới
$NEW_ORACLE_HOME/bin/lsnrctl start
```

### Case 34: DBCA — character set conflict with NLS_LANG

```
🟡 DEGRADED | DBCA database creation

Triệu chứng: Database tạo ra với character set không như ý do biến môi trường
```

```bash
# Fix: Unset NLS_LANG trước khi chạy DBCA, set characterSet trong DBCA params
unset NLS_LANG
dbca -silent -createDatabase -characterSet AL32UTF8 ...
```

### Case 35: Grid install root.sh hangs at "Adding daemon to inittab"

```
🔴 BLOCKING | Grid Infrastructure root.sh

Triệu chứng: root.sh treo vô thời hạn ở bước init
```

```bash
# Chẩn đoán
ps -ef | grep -E "ohasd|crsd|cssd"
tail -f $GRID_HOME/log/$(hostname)/ohasd/ohasd.log

# Fix: thường do conflict với existing init system process
# Kiểm tra firewall/SELinux không chặn
getenforce
setenforce 0  # Tạm thời để test
# Nếu vẫn hang sau 10 phút: kill và xem log chi tiết để tìm nguyên nhân
```

---

## NHÓM C: PATCHING FAILURES (Case 36-55)

### Case 36: OPatch — "OUI-67073: Plugin Identified Conflicts"

```
🔴 BLOCKING | opatch apply — Conflict check

Triệu chứng: Patch conflict với patch đã có
```

```bash
cd /opt/patches/<patch_id>
$ORACLE_HOME/OPatch/opatch prereq \
  CheckConflictAgainstOHWithDetail -ph ./
# Output sẽ liệt kê conflicting patches

# Fix 1: Tìm merge patch (bundle bao gồm cả 2)
# Tìm trên MOS: search "merge patch <patch1> <patch2>"

# Fix 2: Rollback patch cũ trước (nếu an toàn)
$ORACLE_HOME/OPatch/opatch rollback -id <old_patch_id>
$ORACLE_HOME/OPatch/opatch apply
```

### Case 37: OPatch fails — "Could not load inventory"

```
🔴 BLOCKING | opatch apply — Inventory issue

Triệu chứng: OPatch không đọc được inventory.xml
```

```bash
# Fix: Inventory locked hoặc corrupt
ls -la $ORACLE_HOME/.patch_storage/
cat /u01/app/oraInventory/locks/*.lck 2>/dev/null
# Xóa lock file nếu process cũ đã chết
rm -f /u01/app/oraInventory/locks/*.lck
$ORACLE_HOME/OPatch/opatch lsinventory  # Test lại
```

### Case 38: datapatch fails — ORA-04063: package has errors

```
🟡 DEGRADED | datapatch sau khi opatch apply

Triệu chứng: SQL changes không apply được do invalid objects
```

```sql
-- Fix: compile invalid objects trước
@$ORACLE_HOME/rdbms/admin/utlrp.sql
-- Sau đó retry datapatch
```

```bash
$ORACLE_HOME/OPatch/datapatch -verbose
```

### Case 39: OPatchAuto — "Patch is not applicable on the current platform"

```
🔴 BLOCKING | opatchauto apply — Wrong patch

Triệu chứng: Patch download không khớp OS/platform
```

```bash
# Fix: Kiểm tra patch đã download đúng platform chưa
$ORACLE_HOME/OPatch/opatch query -all -dir /opt/patches/<patch_id>
# Re-download patch đúng platform từ MOS (Linux x86-64 vs Solaris vs AIX...)
```

### Case 40: OPatch hangs at "Verifying environment and performing prerequisite checks"

```
🟡 DEGRADED | opatch apply — Hang during prereq

Triệu chứng: OPatch không tiến triển sau nhiều phút
```

```bash
# Chẩn đoán
ps -ef | grep opatch
# Kiểm tra disk I/O không bị nghẽn
iostat -x 5 3

# Fix: thường do disk space check chậm trên NFS/slow storage
# Force timeout và retry với verbose
$ORACLE_HOME/OPatch/opatch apply -silent -verbose 2>&1 | tee /tmp/opatch_debug.log
```

### Case 41: OPatchAuto rolling patch fails mid-way on Node 2

```
🔴 BLOCKING | RAC rolling patch — Partial failure

Triệu chứng: Node 1 patched OK, Node 2 fails giữa chừng
```

```bash
# Chẩn đoán
tail -200 /u01/app/grid/cfgtoollogs/opatchautodb/opatchauto_*.log

# Fix: Rollback node đã patch một phần, retry
$ORACLE_HOME/OPatch/opatchauto rollback \
  /opt/patches/<patch_id> -oh $GRID_HOME,$ORACLE_HOME

# Sau khi rollback thành công, fix root cause rồi retry toàn bộ
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/<patch_id> \
  -oh $GRID_HOME,$ORACLE_HOME
```

### Case 42: ORA-29548 — Java class not found sau patch

```
🟡 DEGRADED | Post-patch — Java components broken

Triệu chứng: Java-related features lỗi sau khi patch
```

```sql
-- Recompile Java classes
@$ORACLE_HOME/javavm/install/initjvm.sql
@$ORACLE_HOME/rdbms/admin/utlrp.sql
```

### Case 43: OPatch — "ApplySession failed: Prerequisite check failed"

```
🔴 BLOCKING | opatch apply — Generic prereq fail

Triệu chứng: Check fail không rõ nguyên nhân cụ thể
```

```bash
# Xem chi tiết log
find $ORACLE_HOME/cfgtoollogs/opatch -name "opatch*.log" -newer /tmp/ref | \
  xargs tail -100

# Common causes:
# 1. OPatch version cũ — update OPatch
# 2. Disk space thiếu trong ORACLE_HOME
df -h $ORACLE_HOME
# 3. Running processes locking files
fuser -v $ORACLE_HOME/bin/oracle
```

### Case 44: GI Patch — "CRS-4640: Oracle High Availability Services is already active"

```
🟡 DEGRADED | GI patch apply — CRS still running

Triệu chứng: Patch yêu cầu CRS down nhưng vẫn đang chạy
```

```bash
# Fix: Stop CRS trước khi patch (nếu non-rolling)
crsctl stop crs -f
# Verify stopped
crsctl check crs
# Sau đó apply patch
```

### Case 45: opatch lsinventory shows "Interim patches: None" sau apply

```
🟡 DEGRADED | opatch verify — Patch không ghi nhận

Triệu chứng: Apply "thành công" nhưng lsinventory không thấy
```

```bash
# Fix: thường do apply nhầm ORACLE_HOME hoặc patch chưa thực sự commit
echo $ORACLE_HOME
$ORACLE_HOME/OPatch/opatch lsinventory -oh $ORACLE_HOME
# Re-apply với explicit oh
cd /opt/patches/<patch_id>
$ORACLE_HOME/OPatch/opatch apply -silent -oh $ORACLE_HOME
```

### Case 46: ORA-600 sau khi apply RU patch

```
🔴 BLOCKING | Post-patch — Internal error

Triệu chứng: Database báo lỗi internal sau patch (hiếm nhưng nghiêm trọng)
```

```bash
# Đây là tình huống cần Oracle Support ngay
# Thu thập thông tin trước khi escalate
sqlplus / as sysdba << 'EOF'
SELECT * FROM v$diag_info;
EOF
# Tìm trace file liên quan
find $ORACLE_BASE/diag -name "*.trc" -newer /tmp/patch_marker

# Workaround tạm: rollback patch nếu có thể
$ORACLE_HOME/OPatch/opatch rollback -id <patch_id>
```

### Case 47: Patch conflict — "OPatch found patches in OCM cache"

```
🟡 DEGRADED | opatch apply — OCM (Oracle Config Manager) conflict

Triệu chứng: Cached patch metadata gây nhầm lẫn
```

```bash
# Fix: clean OCM cache
rm -rf $ORACLE_HOME/ccr/state/*
$ORACLE_HOME/OPatch/opatch apply -silent
```

### Case 48: Datapatch hangs indefinitely

```
🟡 DEGRADED | datapatch — Long-running hang

Triệu chứng: datapatch chạy mãi không xong (bình thường vài phút)
```

```sql
-- Kiểm tra session đang làm gì
SELECT sid, sql_id, event, seconds_in_wait
FROM v$session WHERE program LIKE '%datapatch%' OR module LIKE '%SQL Patch%';

-- Nếu thực sự hang (không phải đang xử lý chậm vì DB lớn):
-- Kill session đó, sau đó cleanup và retry
SELECT * FROM dba_registry_sqlpatch WHERE status='IN PROGRESS';
```

```bash
# Sau khi confirm hang, cleanup status
sqlplus / as sysdba << 'EOF'
EXEC SYS.DBMS_SQLPATCH.RESET_REGISTRY_STATE;
EOF
$ORACLE_HOME/OPatch/datapatch -verbose
```

### Case 49: PSU rollback — "Cannot rollback because of dependency"

```
🟡 DEGRADED | opatch rollback — Dependent patches

Triệu chứng: Rollback fail vì patch khác phụ thuộc patch này
```

```bash
# Xem dependency tree
$ORACLE_HOME/OPatch/opatch lsinventory -patch
# Rollback patches phụ thuộc TRƯỚC, sau đó rollback patch gốc
$ORACLE_HOME/OPatch/opatch rollback -id <dependent_patch_first>
$ORACLE_HOME/OPatch/opatch rollback -id <target_patch>
```

### Case 50: opatchauto — "Failed to retrieve database details"

```
🔴 BLOCKING | opatchauto — Database discovery fail

Triệu chứng: OPatchAuto không tự detect được database instances
```

```bash
# Fix: oratab có thể bị sai/thiếu entry
cat /etc/oratab
# Đảm bảo có entry đúng cho database
echo "ORCL:/u01/app/oracle/product/19.3.0/dbhome_1:Y" >> /etc/oratab
```

### Case 51: ORA-01017 sau patch — password file mismatch

```
🟡 DEGRADED | Post-patch — Authentication broken

Triệu chứng: Không login được sau patch (RAC, password file sync issue)
```

```bash
# Fix: re-sync password file across nodes
scp $ORACLE_HOME/dbs/orapw$ORACLE_SID1 \
    oracle@node2:$ORACLE_HOME/dbs/orapw$ORACLE_SID2
```

### Case 52: Patch space exhausted — "/u01/app/oracle filesystem full"

```
🔴 BLOCKING | opatch apply — Disk full

Triệu chứng: Patch fail giữa chừng do hết dung lượng
```

```bash
df -h /u01

# Fix: Cleanup old patch storage
du -sh $ORACLE_HOME/.patch_storage/*
# Xóa patch storage cũ (CẨN THẬN - chỉ xóa khi chắc chắn không cần rollback)
$ORACLE_HOME/OPatch/opatch util cleanup
```

### Case 53: opatch — "ZOP-43: Invalid ORACLE_HOME"

```
🔴 BLOCKING | opatch — Environment misconfiguration

Triệu chứng: ORACLE_HOME pointer sai
```

```bash
echo $ORACLE_HOME
ls -la $ORACLE_HOME/bin/oracle
# Fix: export đúng ORACLE_HOME trước khi chạy opatch
export ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
export PATH=$ORACLE_HOME/OPatch:$PATH
```

### Case 54: Combined GI+DB patch — version mismatch error

```
🔴 BLOCKING | opatchauto — Version compatibility

Triệu chứng: GI và DB Home khác version, patch combined fail
```

```bash
# Fix: Patch riêng từng Home thay vì combined
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/<patch_id> -oh $GRID_HOME
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/<patch_id> -oh $ORACLE_HOME
```

### Case 55: opatch napply — "Bug numbers required for napply"

```
🟡 DEGRADED | opatch napply — Multi-patch apply

Triệu chứng: napply (multiple patches) thiếu bug list file
```

```bash
# Fix: Tạo bugs.txt với danh sách bug numbers
echo "12345678
23456789" > /opt/patches/bugs.txt
$ORACLE_HOME/OPatch/opatch napply -id_file /opt/patches/bugs.txt
```

---

## NHÓM D: UPGRADE FAILURES (Case 56-75)

### Case 56: preupgrade.jar — "Required action: needs to be addressed"

```
🟡 DEGRADED | Pre-upgrade check

Triệu chứng: Pre-upgrade tool báo issues cần fix trước upgrade
```

```bash
# Chạy fixup script được generate tự động
sqlplus / as sysdba << 'EOF'
@$ORACLE_BASE/cfgtoollogs/$ORACLE_SID/preupgrade/preupgrade_fixups.sql
EOF
```

### Case 57: catctl.pl — "Error: upgrade failed in PHASE"

```
🔴 BLOCKING | Manual upgrade — catctl.pl phase fail

Triệu chứng: Upgrade dừng giữa chừng tại 1 phase cụ thể
```

```bash
# Chẩn đoán
cat /tmp/catupgrd*.log | grep -B5 -A20 "ERROR\|fail"

# Fix: Thường do component cụ thể bị lỗi, xem log chi tiết
$ORACLE_HOME/perl/bin/perl $ORACLE_HOME/rdbms/admin/catctl.pl \
  -n 4 -l /tmp -d $ORACLE_HOME/rdbms/admin catupgrd.sql

# Nếu cần resume từ phase bị lỗi
$ORACLE_HOME/perl/bin/perl $ORACLE_HOME/rdbms/admin/catctl.pl \
  -R catupgrd.sql  # Resume mode
```

### Case 58: AutoUpgrade — "Job has STOPPED with errors"

```
🔴 BLOCKING | AutoUpgrade deploy phase

Triệu chứng: AutoUpgrade dừng và báo lỗi
```

```bash
# Xem chi tiết job log
cat /u01/autoupgrade_logs/$ORACLE_SID/*/autoupgrade_*.log | grep -A20 ERROR

# Resume nếu fixable
java -jar autoupgrade.jar -mode deploy -config config.cfg -console
# Trong console: status -job 1 → xem chi tiết → resume -job 1
```

### Case 59: ORA-01882 — timezone region not found post-upgrade

```
🟡 DEGRADED | Post-upgrade — Timezone version mismatch

Triệu chứng: Application lỗi timezone sau upgrade
```

```sql
-- Kiểm tra timezone version
SELECT * FROM v$timezone_file;

-- Upgrade timezone data
SHUTDOWN IMMEDIATE;
STARTUP UPGRADE;
@$ORACLE_HOME/rdbms/admin/utltz_upg_check.sql
-- Nếu cần upgrade:
@$ORACLE_HOME/rdbms/admin/utltz_upg_apply.sql
SHUTDOWN IMMEDIATE;
STARTUP;
```

### Case 60: DBUA fails — "ORA-39700: database must be opened with UPGRADE option"

```
🔴 BLOCKING | DBUA — Open mode issue

Triệu chứng: Database không ở đúng mode để DBUA tiếp tục
```

```sql
SHUTDOWN IMMEDIATE;
STARTUP UPGRADE;
-- Sau đó retry DBUA hoặc tiếp tục manual upgrade
```

### Case 61: Upgrade — Invalid objects count tăng cao sau upgrade

```
🟡 DEGRADED | Post-upgrade validation

Triệu chứng: Nhiều invalid objects sau khi upgrade hoàn tất
```

```sql
SELECT COUNT(*) FROM dba_objects WHERE status='INVALID';
@$ORACLE_HOME/rdbms/admin/utlrp.sql
-- Verify
SELECT owner, object_type, COUNT(*) FROM dba_objects
WHERE status='INVALID' AND owner NOT IN ('SYS','SYSTEM')
GROUP BY owner, object_type;
```

### Case 62: AutoUpgrade — "PRCZ-2103: Failed to execute command"

```
🔴 BLOCKING | AutoUpgrade — RAC environment

Triệu chứng: AutoUpgrade fail trên RAC do thiếu quyền hoặc node access
```

```bash
# Fix: Kiểm tra SSH equivalence cho AutoUpgrade user
su - oracle -c "ssh node2 date"
# Đảm bảo oracle user có quyền execute trên tất cả nodes
```

### Case 63: catupgrd — ORA-00604: error occurred at recursive SQL level

```
🔴 BLOCKING | Manual upgrade — Recursive SQL error

Triệu chứng: Lỗi cascade trong quá trình upgrade scripts
```

```bash
# Xem error gốc trong log (thường ẩn dưới ORA-00604)
grep -B5 "ORA-00604" /tmp/catupgrd*.log
# Tìm ORA error thực sự gây ra (thường ngay phía trên)

# Common root cause: SYSAUX tablespace đầy
sqlplus / as sysdba << 'EOF'
SELECT used_percent FROM dba_tablespace_usage_metrics
WHERE tablespace_name='SYSAUX';
ALTER TABLESPACE SYSAUX ADD DATAFILE '+DATA' SIZE 5G AUTOEXTEND ON;
EOF
```

### Case 64: Upgrade hangs at "Upgrading Java packages"

```
🟡 DEGRADED | catctl.pl — Java component slow/hang

Triệu chứng: Upgrade dừng rất lâu ở phase Java
```

```bash
# Thường KHÔNG phải hang thật, chỉ chậm (Java component upgrade rất lâu)
# Verify đang xử lý không phải treo
ps -ef | grep java
# Monitor session activity
sqlplus / as sysdba << 'EOF'
SELECT sid, sql_id, event FROM v$session WHERE username='SYS' AND status='ACTIVE';
EOF
# Nếu thực sự > 2 giờ không tiến triển, mới cần investigate sâu hơn
```

### Case 65: PDB upgrade fails — "ORA-65020: pluggable database already plugged"

```
🟡 DEGRADED | CDB/PDB upgrade

Triệu chứng: PDB trong trạng thái không đúng để upgrade
```

```sql
SELECT con_id, name, open_mode FROM v$pdbs;
ALTER PLUGGABLE DATABASE pdb1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb1 OPEN UPGRADE;
-- Sau đó upgrade riêng PDB:
ALTER PLUGGABLE DATABASE pdb1 UPGRADE;
```

### Case 66: AutoUpgrade — Flashback restore point creation fails

```
🟡 DEGRADED | AutoUpgrade — Restoration setup

Triệu chứng: Không tạo được restore point trước upgrade
```

```sql
-- Kiểm tra Flashback enabled
SELECT flashback_on FROM v$database;
-- Nếu chưa, enable trước
ALTER DATABASE FLASHBACK ON;
-- Hoặc disable restoration trong config (chấp nhận rủi ro không rollback được)
-- upg1.restoration=no
```

### Case 67: Upgrade — Component XDB stuck in UPGRADING status

```
🔴 BLOCKING | catctl.pl — XDB component issue

Triệu chứng: 1 component cụ thể không hoàn thành upgrade
```

```sql
SELECT comp_name, version, status FROM dba_registry WHERE comp_name='XDB';
-- Nếu stuck, thường cần re-run riêng component đó
@$ORACLE_HOME/rdbms/admin/catqm.sql change_password SYSAUX TEMP
```

### Case 68: DBUA — "SYS password does not meet complexity requirements"

```
🟡 DEGRADED | DBUA — Password policy mismatch

Triệu chứng: Password hiện tại không đạt chuẩn version mới
```

```sql
-- Fix: đổi password trước khi upgrade
ALTER USER sys IDENTIFIED BY "NewComplex_Pass_2026!";
ALTER USER system IDENTIFIED BY "NewComplex_Pass_2026!";
```

### Case 69: Upgrade — listener incompatible after version change

```
🟡 DEGRADED | Post-upgrade — Listener version mismatch

Triệu chứng: Listener cũ không nhận diện service mới
```

```bash
# Fix: Restart listener với Home mới
lsnrctl stop
export ORACLE_HOME=$NEW_ORACLE_HOME
lsnrctl start
```

### Case 70: Rollback upgrade — Flashback fails "insufficient flashback logs"

```
🔴 BLOCKING | Upgrade rollback via Flashback

Triệu chứng: Không đủ flashback log để rollback về trước upgrade
```

```sql
-- Nếu flashback log đã bị purge, PHẢI dùng RMAN restore thay thế
-- Kiểm tra restore point còn valid
SELECT name, scn, guarantee_flashback_database FROM v$restore_point;

-- Nếu flashback fail, restore từ RMAN backup (trước upgrade)
-- rman target / <<'EOF'
-- RESTORE DATABASE UNTIL SCN <pre_upgrade_scn>;
-- RECOVER DATABASE UNTIL SCN <pre_upgrade_scn>;
-- ALTER DATABASE OPEN RESETLOGS;
-- EOF
```

### Case 71: Upgrade — ORA-04021: timeout occurred while waiting to lock object

```
🟡 DEGRADED | catctl.pl — Lock contention during upgrade

Triệu chứng: Upgrade bị block bởi session khác đang giữ lock
```

```sql
-- Đảm bảo KHÔNG có application connections trong khi upgrade
SELECT username, COUNT(*) FROM v$session WHERE username IS NOT NULL
GROUP BY username;
-- Kill non-SYS sessions nếu có
```

### Case 72: AutoUpgrade — disk space check fails before deploy

```
🔴 BLOCKING | AutoUpgrade — Storage prereq

Triệu chứng: Không đủ disk space cho cả old + new Oracle Home + backup
```

```bash
df -h /u01
# Fix: Free up space hoặc point new Oracle Home sang disk khác
# AutoUpgrade cần: source DB size + ~10GB cho temp/logs
```

### Case 73: Upgrade — APEX version incompatible

```
🟡 DEGRADED | Post-upgrade — APEX component

Triệu chứng: Application Express không hoạt động sau upgrade DB
```

```sql
-- Kiểm tra APEX version
SELECT comp_name, version FROM dba_registry WHERE comp_name LIKE '%Application Express%';
-- Cần upgrade APEX riêng (không tự động theo DB upgrade)
-- Download APEX version tương ứng, chạy apexins.sql
```

### Case 74: catctl.pl — out of memory during upgrade

```
🔴 BLOCKING | Manual upgrade — Resource exhaustion

Triệu chứng: Process bị OOM kill giữa chừng
```

```bash
dmesg | grep -i "killed process"
free -g
# Fix: Giảm parallel degree (-n) trong catctl.pl
$ORACLE_HOME/perl/bin/perl $ORACLE_HOME/rdbms/admin/catctl.pl \
  -n 2 -d $ORACLE_HOME/rdbms/admin catupgrd.sql  # Giảm từ 4 xuống 2
```

### Case 75: Upgrade succeeded but compatible parameter not updated

```
🟡 DEGRADED | Post-upgrade — compatible parameter

Triệu chứng: Database chạy version mới nhưng vẫn dùng compatible cũ
```

```sql
SHOW PARAMETER compatible;
-- Update sau khi confirm upgrade ổn định (KHÔNG THỂ ROLLBACK sau bước này!)
ALTER SYSTEM SET compatible='19.0.0' SCOPE=SPFILE;
-- SHUTDOWN IMMEDIATE; STARTUP;
```

---

## NHÓM E: MIGRATION FAILURES (Case 76-90)

### Case 76: expdp — ORA-39001: invalid argument value

```
🟡 DEGRADED | DataPump export — Parameter error

Triệu chứng: expdp fail ngay khi start do tham số sai
```

```bash
# Thường do directory object không tồn tại hoặc sai tên
sqlplus / as sysdba << 'EOF'
SELECT directory_name, directory_path FROM dba_directories;
EOF
# Tạo directory nếu thiếu
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/u01/datapump';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO system;
```

### Case 77: impdp — ORA-39083: Object type fails to create with error

```
🟡 DEGRADED | DataPump import — Object creation fail

Triệu chứng: Một số objects không tạo được khi import
```

```bash
# Xem chi tiết trong log
grep -B5 -A10 "ORA-39083" import.log

# Common cause: missing tablespace, dùng remap
impdp system/pass directory=DATA_PUMP_DIR dumpfile=exp.dmp \
  remap_tablespace=OLD_TBS:NEW_TBS
```

### Case 78: RMAN Duplicate — RMAN-05501: aborting duplication

```
🔴 BLOCKING | RMAN Active Duplicate — Generic abort

Triệu chứng: Duplicate process abort giữa chừng
```

```bash
# Xem lỗi chi tiết phía trên (RMAN-05501 chỉ là tổng kết)
# Common causes:
# 1. Network connectivity giữa source-target không ổn định
tnsping TARGET
# 2. Auxiliary instance chưa NOMOUNT đúng cách
sqlplus / as sysdba << 'EOF'
SELECT status FROM v$instance;
EOF
```

### Case 79: expdp — ORA-31693: Table data object failed to load/unload

```
🟡 DEGRADED | DataPump — Specific table fail

Triệu chứng: 1 table cụ thể fail trong export, các table khác OK
```

```bash
# Xem nguyên nhân chi tiết (thường ORA-01555 hoặc storage issue)
grep -A20 "ORA-31693" export.log

# Fix: exclude table đó, export riêng với retry
expdp ... exclude=TABLE:"='PROBLEMATIC_TABLE'"
# Sau đó export riêng table này với flashback_scn cụ thể
```

### Case 80: TTS (Transportable Tablespace) — ORA-39123: violations check

```
🔴 BLOCKING | TTS export — Self-containment violation

Triệu chứng: Tablespace có dependencies bên ngoài, không thể transport
```

```sql
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('APP_DATA', TRUE);
SELECT * FROM transport_set_violations;
-- Fix: thêm tablespace bị thiếu vào transport set, hoặc move objects
```

### Case 81: Migration — Cross-platform endian mismatch not detected

```
🔴 BLOCKING | TTS cross-platform — Data corruption risk

Triệu chứng: Quên convert endian, data sẽ corrupt nếu import trực tiếp
```

```sql
-- LUÔN kiểm tra trước khi TTS cross-platform
SELECT platform_name, endian_format FROM v$database;
SELECT platform_name, endian_format FROM v$transportable_platform
WHERE endian_format != (SELECT endian_format FROM v$database);
-- Nếu khác endian, BẮT BUỘC dùng RMAN CONVERT trước
```

### Case 82: impdp — ORA-39014: One or more workers have prematurely exited

```
🔴 BLOCKING | DataPump import — Worker crash

Triệu chứng: Import process chết đột ngột
```

```bash
# Xem log chi tiết worker nào fail và tại sao
grep -B10 "ORA-39014" import.log

# Common cause: PGA/temp space exhausted
sqlplus / as sysdba << 'EOF'
SELECT name, value FROM v$pgastat WHERE name='over allocation count';
EOF
# Giảm parallel hoặc tăng PGA
impdp ... parallel=2  # Giảm từ giá trị cao hơn
```

### Case 83: RMAN Duplicate for Standby — archivelog not found

```
🟡 DEGRADED | RMAN duplicate for standby

Triệu chứng: Duplicate hoàn tất nhưng standby không catch up được
```

```bash
# Fix: Đảm bảo FAL_SERVER đúng và archive logs available
sqlplus / as sysdba << 'EOF'
SHOW PARAMETER fal_server;
EOF
# Force archive trên Primary
ALTER SYSTEM SWITCH LOGFILE;
```

### Case 84: GoldenGate ZDM — Initial load row count mismatch

```
🟡 DEGRADED | GoldenGate migration — Data inconsistency

Triệu chứng: Row count giữa source và target không khớp sau initial load
```

```sql
-- Verify row counts
SELECT 'SOURCE' src, COUNT(*) FROM orders@source_link
UNION ALL
SELECT 'TARGET', COUNT(*) FROM orders;

-- Common cause: GoldenGate Extract bắt đầu SAU thời điểm export SCN
-- Fix: Kiểm tra lại SCN alignment, có thể cần resync
```

### Case 85: SQL Loader — SQL*Loader-704: Internal error: ulconn

```
🔴 BLOCKING | SQL Loader — Connection issue

Triệu chứng: sqlldr không kết nối được database
```

```bash
# Fix: thường do TNS/credentials sai
tnsping ORCL
sqlplus scott/tiger@ORCL  # Test connection riêng
# Đảm bảo connection string đúng format trong sqlldr command
sqlldr userid=scott/tiger@ORCL control=load.ctl
```

### Case 86: PDB plug-in — ORA-65169: error encountered file move

```
🟡 DEGRADED | PDB migration (unplug/plug) — File operation fail

Triệu chứng: Plug PDB fail khi cố di chuyển files
```

```sql
-- Fix: dùng NOCOPY nếu không cần move, hoặc fix permissions
CREATE PLUGGABLE DATABASE pdb1
  USING '/tmp/pdb1.xml'
  NOCOPY  -- Giữ nguyên location
  TEMPFILE REUSE;
```

### Case 87: expdp network_link — ORA-02085: database link referenced

```
🟡 DEGRADED | DataPump network import — DB Link character set mismatch

Triệu chứng: Network link export/import fail do charset không khớp
```

```sql
-- Kiểm tra characterset 2 bên
SELECT * FROM nls_database_parameters WHERE parameter='NLS_CHARACTERSET';
-- Trên cả source và target, phải giống nhau hoặc target phải superset
```

### Case 88: RMAN convert — datafile size mismatch sau convert

```
🟡 DEGRADED | Cross-platform convert — Size inconsistency

Triệu chứng: File sau CONVERT có size khác với gốc
```

```bash
# Đây thường là BÌNH THƯỜNG (do block size alignment khác platform)
# Verify bằng cách so sánh row counts thay vì file size
# Nếu thực sự lo ngại, chạy DBVERIFY trên file đã convert
dbv FILE=/path/converted_datafile.dbf
```

### Case 89: Migration cutover — Application cannot connect to new DB

```
🔴 BLOCKING | Post-migration cutover

Triệu chứng: Sau khi switch connection string, app không kết nối được
```

```bash
# Checklist nhanh
tnsping NEW_SERVICE
sqlplus app_user/pass@NEW_SERVICE
# Kiểm tra: firewall, listener, service registration, user privileges
sqlplus / as sysdba << 'EOF'
SELECT username, account_status FROM dba_users WHERE username='APP_USER';
EOF
```

### Case 90: Zero Downtime Migration — GoldenGate lag không giảm về 0

```
🟡 DEGRADED | ZDM cutover blocked — Lag persistent

Triệu chứng: Trước khi cutover, lag vẫn còn cao, không đạt < 1s
```

```bash
# Chẩn đoán nguyên nhân lag
GGSCI> SEND REPLICAT rep1, GETLAG
GGSCI> STATS REPLICAT rep1, TOTAL

# Common fix: tăng BATCHSQL parameters hoặc convert sang Parallel Replicat
# Xem chi tiết SK07-04 to SK07-13 cho GoldenGate performance tuning
```

---

## NHÓM F: UNINSTALL FAILURES (Case 91-100)

### Case 91: deinstall — "database is still running"

```
🟡 DEGRADED | deinstall — Pre-check fail

Triệu chứng: deinstall script không cho phép tiếp tục vì DB còn chạy
```

```bash
# Fix: Stop tất cả databases/instances trước
srvctl stop database -d ORCL
$ORACLE_HOME/deinstall/deinstall -checkonly  # Verify trước
$ORACLE_HOME/deinstall/deinstall
```

### Case 92: deinstall hangs at "Checking for existing temp files"

```
🟡 DEGRADED | deinstall — Slow filesystem scan

Triệu chứng: deinstall chạy rất lâu không tiến triển
```

```bash
# Thường KHÔNG phải hang, chỉ là scan filesystem lớn chậm
# Verify process còn alive
ps -ef | grep deinstall
# Nếu thực sự stuck > 30 phút, kill và xem log
tail -100 /tmp/deinstall*.log
```

### Case 93: DBCA deleteDatabase fails — "ORA-01093: ALTER DATABASE CLOSE"

```
🟡 DEGRADED | dbca deleteDatabase — Active sessions blocking

Triệu chứng: Không xóa được database do còn connections
```

```sql
-- Force disconnect tất cả trước
SHUTDOWN ABORT;
STARTUP MOUNT EXCLUSIVE RESTRICT;
-- Sau đó retry dbca deleteDatabase
```

### Case 94: Uninstall leftover — orphan processes still running

```
🟡 DEGRADED | Post-uninstall — Process cleanup

Triệu chứng: Sau khi deinstall xong, vẫn còn process Oracle chạy
```

```bash
ps -ef | grep -E "ora_|tnslsnr|asm_"
# Kill orphan processes
pkill -9 -f "ora_.*ORCL"
pkill -9 -f tnslsnr
```

### Case 95: Uninstall — /etc/oratab vẫn còn entry cũ

```
🟢 COSMETIC | Post-uninstall cleanup

Triệu chứng: oratab không tự động cleanup
```

```bash
# Fix: Manual cleanup
sed -i '/ORCL/d' /etc/oratab
cat /etc/oratab  # Verify
```

### Case 96: Grid deinstall — "CRS-4047: No Oracle Clusterware components"

```
🟡 DEGRADED | Grid deinstall — Already partially removed

Triệu chứng: deinstall confused vì cluster components đã bị xóa 1 phần
```

```bash
# Fix: Force cleanup thủ công
crsctl stop crs -f 2>/dev/null
# Xóa cấu hình cluster manually nếu cần
$GRID_HOME/crs/install/rootcrs.sh -deconfig -force
```

### Case 97: Uninstall — Central Inventory không update sau khi xóa Home

```
🟡 DEGRADED | Post-uninstall — Inventory stale entry

Triệu chứng: opatch/installer khác vẫn thấy Home đã xóa
```

```bash
# Fix: Detach Home khỏi inventory thủ công
$ORACLE_HOME/oui/bin/runInstaller -silent -detachHome \
  ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_1 \
  -local
```

### Case 98: Uninstall ASM diskgroup — disk vẫn còn label cũ

```
🟡 DEGRADED | Post-uninstall — ASM disk cleanup

Triệu chứng: Disk vẫn còn ASM header, không tái sử dụng được ngay
```

```bash
# Fix: Clear ASM header (CẨN THẬN — mất hết data trên disk!)
dd if=/dev/zero of=/dev/CRS1 bs=1M count=100
# Hoặc nếu dùng oracleasm:
oracleasm deletedisk CRS1
```

### Case 99: Uninstall — group/user vẫn còn sau cleanup

```
🟢 COSMETIC | OS-level cleanup

Triệu chứng: oracle/grid users và groups còn tồn tại sau uninstall
```

```bash
# Fix: Xóa users/groups nếu không còn Oracle install nào khác
userdel -r oracle
userdel -r grid
groupdel oinstall dba asmadmin asmdba oper
```

### Case 100: Reinstall sau uninstall — "directory already exists" conflict

```
🟡 DEGRADED | Re-install — Leftover directories

Triệu chứng: Cài lại Oracle bị conflict với thư mục cũ chưa xóa hết
```

```bash
# Fix: Cleanup hoàn toàn trước khi reinstall
rm -rf /u01/app/oracle
rm -rf /u01/app/oraInventory
rm -f /etc/oraInst.loc
rm -f /etc/oratab
# Verify sạch sẽ trước khi bắt đầu install mới
ls -la /u01/app/ 2>/dev/null
```

---

## TỔNG KẾT — ESCALATION DECISION TREE

```
Gặp lỗi trong Install/Patch/Upgrade/Migration?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Xem log file chi tiết (luôn có thông tin root cause)
   - Install: $ORACLE_BASE/oraInventory/logs/
   - OPatch: $ORACLE_HOME/cfgtoollogs/opatch/
   - AutoUpgrade: $LOG_DIR/cfgtoollogs/upgrade/
   - RMAN: output trực tiếp hoặc spool log

2. Search MOS theo error code chính xác (PRVF-/INS-/ORA-/CRS-)

3. Nếu BLOCKING và không tự fix được trong 30 phút:
   → Backup current state (snapshot/export logs)
   → Mở SR với Oracle Support (xem SK10-14 to 16)

4. Nếu liên quan PRODUCTION:
   → Có rollback plan SẴN SÀNG trước khi thử fix
   → Test fix trên non-production trước nếu có thể
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Tài liệu tham khảo:**
- MOS Note 169706.1 (Master Note for OUI/Installer)
- MOS Note 1641742.1 (Master Note for AutoUpgrade)
- MOS Note 1931634.1 (OPatch Troubleshooting)
- MOS Note 1075337.1 (DataPump Troubleshooting)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
