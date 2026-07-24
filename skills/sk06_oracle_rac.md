---
name: oracle-rac-administration
description: >
  Oracle Real Application Clusters (RAC) administration.
  Kích hoạt khi hỏi về: Oracle RAC, Real Application Clusters,
  Grid Infrastructure, Clusterware, CRS, CRSD, CSS, OHAS,
  OCR, voting disk, SCAN, VIP, interconnect, Cache Fusion,
  GCS GES, ASM diskgroup RAC, srvctl, crsctl, cluvfy,
  RAC services, TAF transparent application failover, FCF,
  RAC performance, RAC backup, add node remove node RAC,
  RAC troubleshooting, node eviction, split brain, RAC patching.
name:  
MỤC LỤC:
1. SRVCTL — RAC Resource Management
2. CRSCTL — Clusterware Management
3. RAC SQL QUERIES
4. RAC SERVICES
5. RAC BACKUP (RMAN)
6. RAC TROUBLESHOOTING
Tài liệu tham khảo
---

# SK06 · Oracle RAC Administration

**Phạm vi:** Oracle 11g R2, 12c, 19c RAC  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. SRVCTL — RAC Resource Management

```bash
# Database operations
srvctl status database -d ORCL
srvctl start  database -d ORCL
srvctl stop   database -d ORCL
srvctl config database -d ORCL

# Instance operations
srvctl start  instance -d ORCL -i ORCL1
srvctl stop   instance -d ORCL -i ORCL1 -stopoption IMMEDIATE
srvctl status instance -d ORCL -i ORCL1

# Listener operations
srvctl status listener -l LISTENER
srvctl start  listener -l LISTENER
srvctl stop   listener -l LISTENER

# SCAN operations
srvctl status scan
srvctl start  scan
srvctl config scan

# VIP operations
srvctl status vip -n node1
srvctl start  vip -n node1 -i ORCL1-vip

# ASM operations
srvctl status asm -n node1
srvctl start  asm
```

---

## 2. CRSCTL — Clusterware Management

```bash
# Cluster status
crsctl stat  res -t              # Tất cả resources
crsctl stat  res -t -init        # CRS internal resources
crsctl check crs                 # Kiểm tra CRS components
crsctl check cluster             # Kiểm tra toàn cluster

# Start/Stop Clusterware
crsctl stop  crs                 # Dừng trên node hiện tại
crsctl start crs
crsctl stop  cluster -all        # Dừng toàn cluster (từ 1 node)

# OCR Management
ocrcheck                         # Kiểm tra OCR integrity
ocrdump -stdout | head -50       # Xem OCR content
ocrconfig -export /tmp/ocr_backup.ocr  # Backup OCR thủ công

# Voting Disk Management
crsctl query css votedisk        # Xem voting disks
crsctl add css votedisk /dev/VD3 # Thêm voting disk
crsctl delete css votedisk /dev/VD1  # Xóa voting disk (phải có >= 3)

# Cluster verification
cluvfy stage -post crsinst -n node1,node2 -verbose
cluvfy comp nodereach -n node1,node2
```

---

## 3. RAC SQL QUERIES

```sql
-- Xem tất cả instances trong cluster
SELECT inst_id, instance_name, host_name, status, version
FROM gv$instance
ORDER BY inst_id;

-- Sessions per instance
SELECT inst_id, COUNT(*) sessions,
       SUM(CASE WHEN status='ACTIVE' THEN 1 ELSE 0 END) active
FROM gv$session
WHERE type = 'USER'
GROUP BY inst_id
ORDER BY inst_id;

-- Cluster wait events (GC waits — Cache Fusion)
SELECT inst_id, event,
       ROUND(time_waited_micro/1e6,2) time_sec,
       total_waits
FROM gv$system_event
WHERE wait_class NOT IN ('Idle','Background')
  AND event LIKE 'gc%'
ORDER BY time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;

-- RAC interconnect traffic
SELECT inst_id, name, value
FROM gv$sysstat
WHERE name IN (
  'gc cr blocks received',
  'gc current blocks received',
  'gc cr blocks served',
  'gc current blocks served')
ORDER BY inst_id, name;

-- Sequences với CACHE (quan trọng cho RAC performance)
SELECT sequence_name, increment_by, cache_size, order_flag
FROM dba_sequences
WHERE sequence_owner = 'APP_USER'
  AND cache_size < 100;
-- Sequences cần CACHE lớn trong RAC để tránh contention

-- Hot blocks (gc buffer busy waits)
SELECT b.obj object_id,
       o.object_name, o.object_type,
       COUNT(*) waits
FROM gv$session_wait w
JOIN dba_objects o ON o.object_id = w.p1
WHERE w.event LIKE 'gc buffer busy%'
GROUP BY b.obj, o.object_name, o.object_type
ORDER BY waits DESC;
```

---

## 4. RAC SERVICES

```bash
# Tạo service (load balancing giữa các instances)
srvctl add service -d ORCL \
  -s APP_SVC \
  -preferred ORCL1,ORCL2 \
  -pdb ORCLPDB \
  -policy AUTOMATIC \
  -failovertype SELECT \
  -failovermethod BASIC \
  -failoverretry 5 \
  -failoverdelay 5 \
  -clbgoal LONG \
  -rlbgoal THROUGHPUT

srvctl start  service -d ORCL -s APP_SVC
srvctl status service -d ORCL -s APP_SVC
srvctl modify service -d ORCL -s APP_SVC -clbgoal LONG

# Xem services từ SQL
SELECT name, network_name, goal, clb_goal,
       failover_method, failover_type
FROM dba_services
WHERE name NOT IN ('SYS$BACKGROUND','SYS$USERS');
```

---

## 5. RAC BACKUP (RMAN)

```bash
rman target /

# Configure channels per node
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK
    CONNECT 'sys/pass@ORCL1' FORMAT '/backup/rman/node1_%U.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK
    CONNECT 'sys/pass@ORCL2' FORMAT '/backup/rman/node2_%U.bkp';

  BACKUP AS COMPRESSED BACKUPSET DATABASE;
  BACKUP ARCHIVELOG ALL DELETE INPUT;
  BACKUP CURRENT CONTROLFILE;
  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
}
```

---

## 6. RAC TROUBLESHOOTING

```bash
# Node eviction — điều tra nguyên nhân
# Xem CSS logs
$GRID_HOME/log/node1/cssd/ocssd.log

# Xem CRS alert log
$GRID_HOME/log/node1/alertnode1.log

# Clusterware logs
adrci
adrci> show homes
adrci> set home grid/client/node1
adrci> show alert -tail 100

# Kiểm tra network (nguyên nhân thường gặp nhất)
# Ping interconnect
ping -I eth1 10.10.1.2  # Ping qua private network
# Kiểm tra dropped packets
netstat -s | grep -i error

# OSD (out-of-date) node
crsctl stop crs  # Trên node bị evict
crsctl start crs # Rejoin cluster

# Nếu node không rejoin được
# Check and fix OCR:
ocrcheck
ocrconfig -repair  # Nếu OCR bị corrupt trên 1 mirror

# Voting disk issues
crsctl query css votedisk
# Thêm voting disk nếu cần:
crsctl add css votedisk /dev/VD_NEW -force
```

---

**Tài liệu tham khảo:** Oracle RAC Administration Guide 19c, www.tranvanbinh.vn
