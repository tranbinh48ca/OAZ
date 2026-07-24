---
name: oracle-rac-architecture-grid
description: >
  Oracle RAC Architecture, Grid Infrastructure và ASM toàn diện.
  Kích hoạt khi hỏi về: Oracle RAC architecture, Real Application Clusters,
  Grid Infrastructure Oracle, Clusterware Oracle, CRS Oracle,
  CRSD CSSD CSS Oracle, OCR Oracle Cluster Registry, voting disk Oracle,
  SCAN Single Client Access Name, VIP virtual IP Oracle RAC,
  interconnect Oracle RAC, Cache Fusion Oracle RAC, GCS GES Oracle,
  ASM Oracle RAC, shared storage RAC, diskgroup RAC,
  GI topology Oracle RAC, RAC network configuration, private network RAC,
  public network RAC, Oracle RAC 11g 12c 19c architecture,
  srvctl crsctl Oracle RAC, ocrcheck votedisk RAC, clusterware resources,
  RAC background processes LMON LMD LMS LCK DIAG,
  instance membership Oracle RAC, split brain RAC protection.
---

# SK06-01 · Oracle RAC Architecture & Grid Infrastructure

**Phạm vi:** Oracle RAC 11g R2, 12c, 19c, 21c  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. RAC ARCHITECTURE OVERVIEW

```
Oracle RAC: Multiple Instances, Single Database
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    Client Applications
                          │
              ┌───────────┴───────────┐
              │   Oracle RAC Network  │
              ├── Public: 192.168.1.x (app traffic)
              ├── SCAN:   192.168.1.100-102 (3 IPs, load balance)
              └── VIP:    node1-vip, node2-vip (failover)
                          │
          ┌───────────────┼───────────────┐
          │               │               │
    ┌──────────┐    ┌──────────┐    ┌──────────┐
    │  Node 1  │    │  Node 2  │    │  Node 3  │
    │ Instance1│◄──►│ Instance2│◄──►│ Instance3│
    │ ORCL1    │    │ ORCL2    │    │ ORCL3    │
    └──────────┘    └──────────┘    └──────────┘
          │               │               │
          └───────────────┼───────────────┘
              Private Interconnect: 10.10.1.x
              (Cache Fusion traffic, MTU 9000)
                          │
              ┌───────────┴───────────┐
              │    Shared Storage     │
              ├── +CRS  diskgroup (OCR + Voting)
              ├── +DATA diskgroup (Datafiles)
              └── +FRA  diskgroup (Archive + Backup)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 2. GRID INFRASTRUCTURE COMPONENTS

### 2.1 Clusterware Stack

```
Clusterware Layer (từ dưới lên):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
┌─────────────────────────────────────────────────────┐
│  CRS (Cluster Ready Services) Layer                 │
│  ├── CRSD: Resource management, failover, policy    │
│  ├── OHAS: High Availability Services daemon        │
│  └── MDNSD: Multicast DNS (SCAN resolution)        │
├─────────────────────────────────────────────────────┤
│  CSS (Cluster Synchronization Services) Layer       │
│  ├── CSSD: Heartbeat, node membership, eviction     │
│  └── Voting: Write to voting disks (quorum)        │
├─────────────────────────────────────────────────────┤
│  GINS (Grid Interprocess Network Services)          │
│  └── Node-to-node communication infrastructure     │
├─────────────────────────────────────────────────────┤
│  ASM (Automatic Storage Management)                 │
│  └── Shared storage management for all components  │
└─────────────────────────────────────────────────────┘

Key processes:
  ohasd   = Oracle High Availability Services Daemon (starts first)
  crsd    = Cluster Ready Services Daemon
  cssd    = Cluster Synchronization Services Daemon
  diskmon = Disk Monitor Daemon (I/O fencing)
  evmd    = Event Management Daemon
  gpnpd   = Grid Plug-and-Play Daemon
  mdnsd   = Multicast DNS Daemon (SCAN)
  gipcd   = Grid IPC Daemon
  gnsd    = Grid Naming Service Daemon
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 2.2 OCR và Voting Disk

```bash
# ── OCR (Oracle Cluster Registry) ────────────────────────
# Lưu: cluster topology, resource definitions, network config
# Backup: tự động mỗi 4 giờ, giữ 3 copies
# Stored in: ASM diskgroup hoặc shared filesystem

# Kiểm tra OCR integrity
ocrcheck
# Output: Server's configuration file location = +CRS
#         Is ASM based OCR configured = YES
#         ASM based OCR location = +CRS

# Xem OCR backup history
ocrconfig -showbackup

# Manual OCR backup
ocrconfig -manualbackup

# List backup files
ocrconfig -showbackup manual

# Restore OCR từ backup (cần cluster DOWN)
ocrconfig -restore /u01/backup/ocr_backup.bkp

# ── Voting Disk ───────────────────────────────────────────
# Voting disk: node dùng để vote khi network partition
# Quorum rule: node cần win > 50% votes để tiếp tục
# Cần ODD number: 1, 3, 5 (với NORMAL redundancy ASM: 3 embedded)

# Xem voting disks
crsctl query css votedisk
# Output: ## STATE    File Universal Id ...
#          1. ONLINE  <uid> (/dev/CRS1) [+CRS]
#          2. ONLINE  <uid> (/dev/CRS2) [+CRS]
#          3. ONLINE  <uid> (/dev/CRS3) [+CRS]

# Add voting disk
crsctl add css votedisk /dev/NEW_VD -force

# Remove voting disk (phải còn đủ quorum)
crsctl delete css votedisk /dev/OLD_VD -force
```

### 2.3 SCAN (Single Client Access Name)

```bash
# SCAN: 1 hostname → 3 IPs (DNS round-robin)
# Lợi ích: application không cần biết node IPs
# Auto load balance connections across nodes

# DNS cấu hình:
# orcl-scan.vietdba.local → 192.168.1.100
# orcl-scan.vietdba.local → 192.168.1.101
# orcl-scan.vietdba.local → 192.168.1.102

# Verify SCAN
nslookup orcl-scan.vietdba.local
# Phải trả về 3 địa chỉ IP

srvctl status scan
# SCAN VIP orcl-scan1 is enabled
# SCAN VIP orcl-scan1 is running on node node1
# ...

srvctl config scan
# SCAN name: orcl-scan.vietdba.local
# SCAN Subnet: 192.168.1.0/255.255.255.0
# SCAN Port: 1521

# SCAN listener
srvctl status scan_listener
srvctl config  scan_listener
srvctl start   scan_listener
srvctl stop    scan_listener

# Kiểm tra kết nối qua SCAN
sqlplus system@orcl-scan:1521/ORCLPDB

# SCAN là SINGLE point of connection cho clients
# Application chỉ cần 1 connection string:
# jdbc:oracle:thin:@//orcl-scan:1521/ORCL_SERVICE
```

---

## 3. NETWORK CONFIGURATION

### 3.1 Network Types và Requirements

```bash
# ── Public Network ───────────────────────────────────────
# Purpose: Client connections, VIP failover
# Protocol: TCP/IP
# Speed: 1GbE minimum, 10GbE recommended
# Example: eth0, 192.168.1.x/24

# ── Private Interconnect (Critical!) ─────────────────────
# Purpose: Cache Fusion, GCS/GES messages, node heartbeat
# Protocol: UDP (primarily)
# Speed: 10GbE MINIMUM (1GbE causes performance issues)
# MTU: 9000 (Jumbo frames - MANDATORY)
# Dedicated: MUST be dedicated network, no other traffic
# Example: eth1, 10.10.1.x/24

# Set Jumbo Frames (MTU 9000)
ip link set eth1 mtu 9000
# Permanent (NetworkManager):
nmcli con modify eth1 802-3-ethernet.mtu 9000

# Test jumbo frames
ping -M do -s 8972 10.10.1.2  # Should not fragment

# ── VIP (Virtual IP) ──────────────────────────────────────
# Purpose: Immediate client failover when node fails
# VIP floats between nodes automatically
# Clients connected to VIP get fast TCP RST (not timeout)

srvctl status vip -node node1
srvctl config vip -node node1
# VIP Name: node1-vip
# VIP IPv4 Address/subnet: 192.168.1.11/255.255.255.0

# ── /etc/hosts (minimum for non-DNS) ────────────────────
cat >> /etc/hosts << 'EOF'
# Public
192.168.1.1    node1.vietdba.local    node1
192.168.1.2    node2.vietdba.local    node2
192.168.1.3    node3.vietdba.local    node3

# VIP
192.168.1.11   node1-vip.vietdba.local    node1-vip
192.168.1.12   node2-vip.vietdba.local    node2-vip
192.168.1.13   node3-vip.vietdba.local    node3-vip

# Private Interconnect
10.10.1.1      node1-priv.vietdba.local   node1-priv
10.10.1.2      node2-priv.vietdba.local   node2-priv
10.10.1.3      node3-priv.vietdba.local   node3-priv
EOF

# Kiểm tra network interfaces
oifcfg getif
# eth0   192.168.1.0  global  public
# eth1   10.10.1.0    global  cluster_interconnect
```

---

## 4. CACHE FUSION

```sql
-- Cache Fusion: cơ chế Oracle RAC đồng bộ data blocks giữa các nodes
-- Thay vì read từ disk, node copy block từ instance khác qua interconnect

/*
Cache Fusion Block Transfer Flow:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Node 2 cần block X, nhưng Node 1 đang giữ (dirty)
2. Node 2 gửi request qua GES (Global Enqueue Services)
3. GCS (Global Cache Services) coordinate transfer
4. Node 1 ship block X to Node 2 qua Interconnect
5. Node 2 có block X trong buffer cache

CR Block: Consistent Read image (read-consistent view)
Current Block: Latest version (for modification)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GCS (Global Cache Services): Manages data block access
GES (Global Enqueue Services): Manages locks/resources

Background processes RAC:
  LMS (Lock Manager Server): Process GCS messages
    - Multiple LMSn processes (LMS0, LMS1...)
    - More LMS = better Cache Fusion throughput
  LMD (Lock Manager Daemon): Manages GES messages
  LMON (Lock Monitor): Cluster reconfiguration
  LCK (Lock): Non-cache fusion lock requests
  RMS (RAC Management): RAC services management
  DIAG: Diagnostics
*/

-- Kiểm tra Cache Fusion statistics
SELECT inst_id,
       gc_cr_blocks_received,
       gc_current_blocks_received,
       gc_cr_blocks_served,
       gc_current_blocks_served
FROM gv$sysstat
WHERE name IN ('gc cr blocks received','gc current blocks received',
               'gc cr blocks served','gc current blocks served')
ORDER BY inst_id;

-- GC waits (indicator of interconnect health)
SELECT inst_id, event, wait_class,
       total_waits,
       ROUND(time_waited/100, 2) time_sec,
       ROUND(average_wait/100*1000, 2) avg_wait_ms
FROM gv$system_event
WHERE event LIKE 'gc%'
  AND total_waits > 0
ORDER BY inst_id, time_waited DESC;

-- Hot blocks causing GC contention
SELECT o.object_name, o.object_type,
       COUNT(*) gc_waits
FROM gv$session_wait sw
JOIN dba_objects o ON sw.p1 = o.object_id
WHERE sw.event LIKE 'gc buffer busy%'
  OR sw.event LIKE 'gc cr%'
GROUP BY o.object_name, o.object_type
ORDER BY gc_waits DESC
FETCH FIRST 15 ROWS ONLY;

-- Interconnect throughput
SELECT inst_id, name, value
FROM gv$sysstat
WHERE name IN (
  'gc cr blocks received',
  'gc current blocks received',
  'gc cr block receive time',
  'gc current block receive time'
)
ORDER BY inst_id, name;
```

---

## 5. ASM TRONG RAC

```sql
-- ── ASM Instance (Grid user) ──────────────────────────────
export ORACLE_SID=+ASM1  -- Node 1
sqlplus / as sysasm

-- Xem ASM diskgroups từ tất cả instances
SELECT dg.name, dg.state, dg.type,
       ROUND(dg.total_mb/1024, 2) total_gb,
       ROUND(dg.free_mb/1024, 2)  free_gb,
       dg.offline_disks,
       dg.voting_files
FROM v$asm_diskgroup dg
ORDER BY dg.name;

-- Diskgroup clients (DB instances)
SELECT cl.db_name, cl.instance_name, cl.db_version,
       dg.name diskgroup
FROM v$asm_client cl
JOIN v$asm_diskgroup dg ON cl.group_number = dg.group_number
ORDER BY cl.instance_name, dg.name;

-- ASMCMD (ASM command line utility)
asmcmd lsdg              -- List diskgroups
asmcmd lsdg --discovery  -- Discovery mode

-- ASM diskgroup cho RAC - must be accessible from ALL nodes
-- CRS diskgroup: OCR và Voting disks
-- DATA diskgroup: datafiles, controlfiles, redo logs
-- FRA diskgroup: archive logs, backups, flashback logs

-- Verify diskgroup mounted trên tất cả nodes
SELECT inst_id, dg.name, dg.state
FROM gv$asm_diskgroup dg
ORDER BY dg.name, inst_id;
-- Tất cả nodes phải có state = MOUNTED
```

---

## 6. CLUSTER STATUS COMMANDS

```bash
# ── Master status commands ────────────────────────────────

# Tất cả cluster resources
crsctl stat res -t
# Output:
# NAME              TARGET  STATE   SERVER     STATE_DETAILS
# ora.CRS.dg        ONLINE  ONLINE  node1
# ora.ORCL.db       ONLINE  ONLINE
# ora.ORCL.ORCL1.inst ONLINE ONLINE node1
# ora.scan1.vip     ONLINE  ONLINE  node1

# Check cluster health
crsctl check cluster -all
crsctl check crs

# Specific resource
crsctl stat res ora.ORCL.db
crsctl stat res ora.ORCL.db -v  -- Verbose

# Node membership
olsnodes -n         -- List nodes with numbers
olsnodes -l         -- Local node only
olsnodes -v         -- Verbose with node roles

# Cluster version
crsctl query crs releaseversion
crsctl query crs softwareversion

# ── DB Instance status ────────────────────────────────────
srvctl status database -d ORCL
srvctl status database -d ORCL -v  -- Verbose

# Specific instance
srvctl status instance -d ORCL -i ORCL1

# ── Service status ────────────────────────────────────────
srvctl status service -d ORCL
srvctl status service -d ORCL -s APP_SERVICE

# ── ASM status ────────────────────────────────────────────
srvctl status asm
srvctl status asm -n node1

# ── Listener status ───────────────────────────────────────
srvctl status listener
srvctl status listener -l LISTENER

# ── SCAN status ───────────────────────────────────────────
srvctl status scan
srvctl status scan_listener
```

---

## 7. SQL QUERIES ĐẶC TRƯNG CHO RAC

```sql
-- GV$ views: Global views across all instances (g = global)
-- V$ views: Local instance only

-- All instances info
SELECT inst_id, instance_name, host_name, version,
       status, database_status, logins,
       TO_CHAR(startup_time,'YYYY-MM-DD HH24:MI') startup_time,
       ROUND(SYSDATE - startup_time, 1) uptime_days
FROM gv$instance
ORDER BY inst_id;

-- Sessions per instance
SELECT inst_id,
       COUNT(*) total_sessions,
       SUM(CASE WHEN status='ACTIVE' THEN 1 ELSE 0 END) active,
       SUM(CASE WHEN status='INACTIVE' THEN 1 ELSE 0 END) inactive
FROM gv$session
WHERE type = 'USER'
GROUP BY inst_id
ORDER BY inst_id;

-- Top waits per instance
SELECT inst_id, event, wait_class, total_waits,
       ROUND(time_waited_micro/1e6, 2) time_sec
FROM gv$system_event
WHERE wait_class NOT IN ('Idle','Background')
  AND total_waits > 0
ORDER BY inst_id, time_waited_micro DESC
FETCH FIRST 30 ROWS ONLY;

-- Database info (RAC specific)
SELECT name, db_unique_name, open_mode,
       cluster_database,       -- YES for RAC
       cluster_database_instances,
       log_mode
FROM v$database;

-- RAC cluster interconnect info
SELECT inst_id, name, ip_address, is_public,
       source, adapter
FROM gv$cluster_interconnects
ORDER BY inst_id;

-- Redo log groups per thread (instance)
SELECT l.thread#, l.group#, l.members,
       ROUND(l.bytes/1024/1024, 0) size_mb,
       l.status, l.archived,
       lf.member log_file
FROM v$log l
JOIN v$logfile lf ON l.group# = lf.group#
ORDER BY l.thread#, l.group#;
```

---

## 8. RAC SPECIFIC PARAMETERS

```sql
-- Parameters quan trọng cho RAC
SELECT name, value, description
FROM v$parameter
WHERE name IN (
  'cluster_database',           -- TRUE for RAC
  'cluster_database_instances', -- Number of instances
  'db_name',
  'instance_number',            -- Unique per instance (1, 2, 3...)
  'instance_name',              -- e.g., ORCL1, ORCL2
  'thread',                     -- Redo thread number
  'undo_tablespace',            -- Separate UNDO per instance
  'local_listener',             -- Points to node's VIP listener
  'remote_listener',            -- Points to SCAN listener
  'service_names',              -- Services this instance offers
  'parallel_instance_group',    -- For parallel query
  'gcs_server_processes',       -- LMS processes count
  'cluster_interconnects'       -- Private interconnect NIC
)
ORDER BY name;

-- RAC best practice parameters
/*
cluster_database          = TRUE
instance_number           = 1 (node1), 2 (node2), 3 (node3)
undo_tablespace           = UNDOTBS1 (node1), UNDOTBS2 (node2), UNDOTBS3 (node3)
thread                    = 1 (node1), 2 (node2), 3 (node3)
local_listener            = '(ADDRESS=(PROTOCOL=TCP)(HOST=node1-vip)(PORT=1521))'
remote_listener           = 'orcl-scan:1521'
gcs_server_processes      = 4 (increase for high Cache Fusion workload)
cluster_interconnects     = 10.10.1.1 (specific private NIC)
enable_goldengate_replication = TRUE (if using GoldenGate)
*/
```

---

**Tài liệu tham khảo:**
- Oracle Grid Infrastructure Administrator's Guide 19c
- Oracle Real Application Clusters Administrator's Guide 19c
- Oracle Database 2 Day + Real Application Clusters Guide
- MOS Note 1053147.1 (RAC Installation and Configuration Best Practices)
- www.tranvanbinh.vn
