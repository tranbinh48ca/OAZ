---
name: oracle-rac-services-taf-fcf-backup-performance
description: >
  Oracle RAC Services, TAF, FCF, Backup, Performance và Patching.
  Kích hoạt khi hỏi về: RAC services Oracle, srvctl add service,
  service preferred available RAC, service failover RAC,
  TAF transparent application failover Oracle RAC,
  FCF fast connection failover Oracle RAC, ONS Oracle Notification Service,
  connection load balance RAC, CLB goal Oracle RAC,
  RMAN backup RAC, backup RAC database, RAC archive log,
  RAC performance tuning, gc waits Oracle RAC, Cache Fusion performance,
  sequence cache RAC, global cache Oracle, hot block RAC,
  rolling patch RAC, OPatchAuto RAC, zero downtime patch RAC,
  add node RAC, remove node Oracle RAC, nodeadd nodedel Oracle,
  RAC troubleshooting, node eviction Oracle RAC, split brain RAC,
  CSS eviction Oracle, voting disk failure Oracle RAC.
---

# SK06-02 · RAC Services, TAF/FCF, Backup, Performance & Patching

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. RAC SERVICES MANAGEMENT

### 1.1 Create và Configure Services

```bash
# ── Tạo service cho OLTP workload ────────────────────────
srvctl add service -d ORCL \
  -s OLTP_SVC \
  -preferred ORCL1,ORCL2 \
  -available ORCL3 \
  -pdb ORCLPDB \
  -policy AUTOMATIC \
  -role PRIMARY \
  -failovertype SELECT \
  -failovermethod BASIC \
  -failoverretry 5 \
  -failoverdelay 5 \
  -clbgoal LONG \
  -rlbgoal THROUGHPUT \
  -notification TRUE

# ── Tạo service cho batch workload ───────────────────────
srvctl add service -d ORCL \
  -s BATCH_SVC \
  -preferred ORCL3 \
  -available ORCL1 \
  -pdb ORCLPDB \
  -policy AUTOMATIC \
  -clbgoal LONG \
  -rlbgoal NONE

# ── Tạo service cho reporting (read-only) ────────────────
srvctl add service -d ORCL \
  -s REPORT_SVC \
  -preferred ORCL1,ORCL2,ORCL3 \
  -policy AUTOMATIC \
  -clbgoal SHORT \
  -rlbgoal THROUGHPUT

# ── Service Operations ────────────────────────────────────
srvctl start   service -d ORCL -s OLTP_SVC
srvctl stop    service -d ORCL -s OLTP_SVC
srvctl status  service -d ORCL -s OLTP_SVC
srvctl config  service -d ORCL -s OLTP_SVC
srvctl modify  service -d ORCL -s OLTP_SVC -failoverretry 10
srvctl remove  service -d ORCL -s OLTP_SVC
```

### 1.2 Services từ SQL

```sql
-- Tạo service với DBMS_SERVICE (thay thế SRVCTL)
BEGIN
  DBMS_SERVICE.CREATE_SERVICE(
    service_name    => 'APP_SERVICE',
    network_name    => 'APP_SERVICE.vietdba.local',
    goal            => DBMS_SERVICE.GOAL_THROUGHPUT,
    clb_goal        => DBMS_SERVICE.CLB_GOAL_LONG,
    failover_method => 'BASIC',
    failover_type   => 'SELECT',
    failover_retries => 10,
    failover_delay  => 5
  );
  DBMS_SERVICE.START_SERVICE('APP_SERVICE');
END;
/

-- Xem all services
SELECT name, network_name, failover_method, failover_type,
       failover_retries, goal, clb_goal, enabled,
       pdb, edition
FROM dba_services
WHERE name NOT IN ('SYS$BACKGROUND','SYS$USERS','SYS$AQBG')
ORDER BY name;

-- Services per instance (real-time)
SELECT inst_id, name, network_name, failed_over
FROM gv$active_services
ORDER BY inst_id, name;

-- Service performance metrics
SELECT service_name, inst_id,
       calls_total, elapsed_time_total,
       ROUND(elapsed_time_total/NULLIF(calls_total,0)/1000, 2) avg_ela_ms,
       cpu_time_total,
       user_io_wait_time
FROM gv$service_stats
WHERE service_name NOT IN ('SYS$BACKGROUND','SYS$USERS')
ORDER BY service_name, inst_id;

-- Connections per service
SELECT s.service_name, s.inst_id,
       COUNT(*) sessions,
       SUM(CASE WHEN s.status='ACTIVE' THEN 1 ELSE 0 END) active
FROM gv$session s
WHERE s.type = 'USER'
GROUP BY s.service_name, s.inst_id
ORDER BY s.service_name, s.inst_id;
```

---

## 2. TAF (TRANSPARENT APPLICATION FAILOVER)

### 2.1 TAF Configuration

```bash
# TAF: Khi node fail, client connection tự động chuyển sang instance khác
# Application không biết failover đã xảy ra

# ── Server-side TAF (qua srvctl service) ─────────────────
srvctl add service -d ORCL \
  -s TAF_SERVICE \
  -preferred ORCL1,ORCL2 \
  -available ORCL3 \
  -policy AUTOMATIC \
  -failovertype SELECT \   # SELECT: resume query  SESSION: just reconnect
  -failovermethod BASIC \  # BASIC: reconnect after fail  PRECONNECT: keep backup conn
  -failoverretry 15 \      # Retry count
  -failoverdelay 5         # Seconds between retries
```

```bash
# ── Client-side TAF (trong tnsnames.ora) ──────────────────
# $ORACLE_HOME/network/admin/tnsnames.ora

ORCL_TAF =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=orcl-scan.vietdba.local)(PORT=1521))
    (CONNECT_DATA =
      (SERVICE_NAME = TAF_SERVICE)
      (FAILOVER_MODE =
        (TYPE = SELECT)       # SELECT | SESSION | NONE
        (METHOD = BASIC)      # BASIC | PRECONNECT
        (RETRIES = 15)
        (DELAY = 5)
      )
    )
  )

# PRECONNECT: Oracle pre-establishes backup connection
# More resource intensive but faster failover
ORCL_TAF_PRECON =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=node1-vip)(PORT=1521))
    (ADDRESS = (PROTOCOL=TCP)(HOST=node2-vip)(PORT=1521))
    (CONNECT_DATA =
      (SERVICE_NAME = TAF_SERVICE)
      (FAILOVER_MODE =
        (TYPE = SELECT)
        (METHOD = PRECONNECT)
        (RETRIES = 15)
        (DELAY = 3)
        (BACKUP = ORCL_TAF_BACKUP)  # Backup connection
      )
    )
  )

ORCL_TAF_BACKUP =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL=TCP)(HOST=node2-vip)(PORT=1521))
    (CONNECT_DATA = (SERVICE_NAME = TAF_SERVICE))
  )
```

```sql
-- Kiểm tra TAF status cho session
SELECT failed_over, failover_type, failover_method
FROM v$session
WHERE username = 'APP_USER'
  AND audsid = USERENV('sessionid');
-- failed_over: YES khi đang chạy trên failover instance

-- Kiểm tra tất cả failed-over sessions
SELECT sid, serial#, username, machine,
       failed_over, failover_type, failover_method,
       service_name
FROM v$session
WHERE failed_over = 'YES';

-- TAF callback (PL/SQL cho application-level response)
CREATE OR REPLACE PACKAGE pkg_taf_handler AS
  PROCEDURE taf_callback(
    ns       IN DBMS_SESSION.AppCallbackInterface,
    event    IN PLS_INTEGER,
    opt      IN PLS_INTEGER
  );
END;
/

CREATE OR REPLACE PACKAGE BODY pkg_taf_handler AS
  PROCEDURE taf_callback(ns IN DBMS_SESSION.AppCallbackInterface,
                          event IN PLS_INTEGER, opt IN PLS_INTEGER) AS
  BEGIN
    IF event = DBMS_SESSION.TAF_EVENT_BEGIN THEN
      -- Session is failing over
      DBMS_APPLICATION_INFO.SET_CLIENT_INFO('TAF_FAILOVER_IN_PROGRESS');
    ELSIF event = DBMS_SESSION.TAF_EVENT_END THEN
      -- Failover complete, re-set session state
      DBMS_APPLICATION_INFO.SET_MODULE('APP', 'RESTORED');
    ELSIF event = DBMS_SESSION.TAF_EVENT_ERROR THEN
      -- Failover failed
      NULL;
    END IF;
  END;
END;
/
```

---

## 3. FCF (FAST CONNECTION FAILOVER)

### 3.1 FCF với ONS

```bash
# FCF: Proactive failover — client được notify NGAY KHI node down
# Không cần đợi connection timeout
# Requires: UCP (Universal Connection Pool) hoặc WebLogic JDBC

# ── ONS (Oracle Notification Service) ────────────────────
# ONS: Event notification service
# Pub/Sub: DB publishes events → ONS → Clients subscribe

# Kiểm tra ONS status
srvctl status ons
srvctl config  ons

# Start/Stop ONS
srvctl start ons
srvctl stop  ons

# ONS configuration file: $GRID_HOME/opmn/conf/ons.config
cat $GRID_HOME/opmn/conf/ons.config
# localport=6100
# remoteport=6200
# nodes=node1:6200,node2:6200,node3:6200
```

```java
// ── Java UCP với FCF ──────────────────────────────────────
import oracle.ucp.jdbc.PoolDataSource;
import oracle.ucp.jdbc.PoolDataSourceFactory;

PoolDataSource pds = PoolDataSourceFactory.getPoolDataSource();
pds.setConnectionFactoryClassName("oracle.jdbc.pool.OracleDataSource");

// SCAN URL
pds.setURL("jdbc:oracle:thin:@//orcl-scan:1521/OLTP_SVC");
pds.setUser("app_user");
pds.setPassword("AppPass_2026!");

// FCF Settings
pds.setFastConnectionFailoverEnabled(true);
pds.setONSConfiguration("nodes=node1:6200,node2:6200,node3:6200");

// Connection pool settings
pds.setInitialPoolSize(5);
pds.setMinPoolSize(5);
pds.setMaxPoolSize(50);
pds.setConnectionWaitTimeout(30);
pds.setInactiveConnectionTimeout(60);
```

---

## 4. RMAN BACKUP TRONG RAC

### 4.1 RMAN RAC Backup Strategy

```bash
# ── RMAN kết nối RAC ─────────────────────────────────────
rman target sys/pass@ORCL

# Kiểm tra instances
SELECT * FROM v$instance;

# ── Backup với parallel channels (từ nhiều nodes) ─────────
rman target / << 'EOF'
RUN {
  -- Allocate channels trên từng node
  ALLOCATE CHANNEL c1 DEVICE TYPE DISK
    CONNECT 'sys/pass@ORCL1'
    FORMAT '+FRA/ORCL/RMAN/%d_%T_%s_%p.bkp';
  ALLOCATE CHANNEL c2 DEVICE TYPE DISK
    CONNECT 'sys/pass@ORCL2'
    FORMAT '+FRA/ORCL/RMAN/%d_%T_%s_%p.bkp';
  ALLOCATE CHANNEL c3 DEVICE TYPE DISK
    CONNECT 'sys/pass@ORCL3'
    FORMAT '+FRA/ORCL/RMAN/%d_%T_%s_%p.bkp';

  BACKUP AS COMPRESSED BACKUPSET
    DATABASE
    PLUS ARCHIVELOG DELETE INPUT;

  BACKUP CURRENT CONTROLFILE
    FORMAT '+FRA/ORCL/RMAN/ctl_%T_%s.bkp';

  RELEASE CHANNEL c1;
  RELEASE CHANNEL c2;
  RELEASE CHANNEL c3;

  DELETE NOPROMPT OBSOLETE;
}
EOF

# ── Archive log backup (RAC: multi-thread) ────────────────
rman target / << 'EOF'
-- RAC: archive logs on each node (thread 1, 2, 3)
BACKUP ARCHIVELOG ALL
  FORMAT '+FRA/ORCL/RMAN/arch_%d_%t_%s_%p_%T.bkp'
  DELETE INPUT;
-- RMAN automatically handles multi-thread archives

LIST ARCHIVELOG ALL;
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
EOF

# ── Backup configuration cho RAC ─────────────────────────
rman target / << 'EOF'
CONFIGURE DEVICE TYPE DISK PARALLELISM 3;  -- 3 parallel channels = 3 nodes
CONFIGURE DEFAULT DEVICE TYPE TO DISK;
CONFIGURE BACKUP OPTIMIZATION ON;
CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 7 DAYS;
CONFIGURE ARCHIVELOG DELETION POLICY TO APPLIED ON STANDBY;
SHOW ALL;
EOF
```

---

## 5. RAC PERFORMANCE TUNING

### 5.1 Interconnect Performance

```sql
-- ── GC (Global Cache) wait analysis ──────────────────────
SELECT inst_id, event, wait_class,
       total_waits,
       ROUND(time_waited_micro/1e6, 2) total_sec,
       ROUND(average_wait*10, 2) avg_wait_ms
FROM gv$system_event
WHERE event LIKE 'gc%'
  AND total_waits > 100
ORDER BY inst_id, time_waited_micro DESC;

-- GC wait timing breakdown
SELECT inst_id, name, value
FROM gv$sysstat
WHERE name IN (
  'gc cr block receive time',
  'gc cr blocks received',
  'gc current block receive time',
  'gc current blocks received',
  'gc cr block build time',
  'gc cr block flush time'
)
ORDER BY inst_id, name;

-- Compute average GC transfer time
SELECT s1.inst_id,
  ROUND(s1.value/NULLIF(s2.value, 0), 3) cr_transfer_ms,
  ROUND(s3.value/NULLIF(s4.value, 0), 3) current_transfer_ms
FROM gv$sysstat s1
JOIN gv$sysstat s2 ON s1.inst_id=s2.inst_id
  AND s1.name='gc cr block receive time'
  AND s2.name='gc cr blocks received'
JOIN gv$sysstat s3 ON s1.inst_id=s3.inst_id
  AND s3.name='gc current block receive time'
JOIN gv$sysstat s4 ON s1.inst_id=s4.inst_id
  AND s4.name='gc current blocks received'
ORDER BY s1.inst_id;
-- CR transfer < 5ms: EXCELLENT
-- CR transfer 5-15ms: OK
-- CR transfer > 15ms: investigate interconnect

-- ── Hot blocks detection ──────────────────────────────────
SELECT o.owner, o.object_name, o.object_type,
       COUNT(*) hot_block_waits,
       s.inst_id
FROM gv$session_wait sw
JOIN gv$session s ON sw.inst_id=s.inst_id AND sw.sid=s.sid
JOIN dba_objects o ON sw.p1=o.object_id
WHERE sw.event LIKE 'gc buffer busy%'
  AND o.owner NOT IN ('SYS','SYSTEM')
GROUP BY o.owner, o.object_name, o.object_type, s.inst_id
ORDER BY hot_block_waits DESC
FETCH FIRST 20 ROWS ONLY;
```

### 5.2 Sequence Cache Tuning

```sql
-- RAC: Sequence values reserved per instance
-- If cache too small → frequent GES contention
-- Recommended: cache >= 20 * num_instances

-- Find sequences with low cache (high contention risk)
SELECT sequence_owner, sequence_name,
       increment_by, cache_size, order_flag,
       CASE WHEN cache_size < 100 THEN '⚠️ Low Cache'
            WHEN order_flag = 'Y' THEN '⚠️ ORDER (serialized!)'
            ELSE 'OK'
       END recommendation
FROM dba_sequences
WHERE sequence_owner NOT IN ('SYS','SYSTEM','DBSNMP','AUDSYS')
  AND (cache_size < 100 OR order_flag = 'Y')
ORDER BY cache_size ASC;

-- Fix: Increase sequence cache for RAC
ALTER SEQUENCE app_user.order_seq CACHE 1000;
ALTER SEQUENCE app_user.txn_seq  CACHE 500 NOORDER;  -- Remove ORDER

-- SYS.DUAL contention (common in RAC)
SELECT * FROM gv$latch_children
WHERE name = 'row cache objects'
ORDER BY sleeps DESC
FETCH FIRST 10 ROWS ONLY;

-- Minimize DUAL selects: use DBMS_UTILITY or sequence.CURRVAL
-- Bad:  SELECT seq.NEXTVAL FROM DUAL  (one at a time)
-- Good: Use bulk sequence generation
```

### 5.3 Connection Load Balancing

```sql
-- RAC load balancing: Client load balanced via SCAN
-- Two types:
-- CLB_GOAL_LONG:  Connect to least loaded instance (by session count)
-- CLB_GOAL_SHORT: Connect to fastest instance (by response time)

-- Service-level load balancing recommendations
SELECT service_name, goal, clb_goal
FROM dba_services
WHERE service_name NOT IN ('SYS$BACKGROUND','SYS$USERS');

-- OLTP: CLB_GOAL_SHORT (fast connection to responsive instance)
-- Batch: CLB_GOAL_LONG (distribute by session count)

-- Verify connections distributed correctly
SELECT s.service_name, s.inst_id, COUNT(*) conn_count
FROM gv$session s
WHERE s.type = 'USER' AND s.username IS NOT NULL
GROUP BY s.service_name, s.inst_id
ORDER BY s.service_name, s.inst_id;

-- Skewed distribution = check service CLB config
```

---

## 6. ROLLING PATCH (Zero Downtime)

### 6.1 OPatchAuto Rolling Patch

```bash
# Rolling patch: patch node-by-node, application stays up
# Requires: RAC, OPatchAuto, root access

# ── Pre-check ─────────────────────────────────────────────
$ORACLE_HOME/OPatch/opatchauto apply \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME \
  -analyze     # Analysis only, no apply

# Review output carefully before proceeding

# ── Apply Rolling Patch ───────────────────────────────────
# Must run as root!
$ORACLE_HOME/OPatch/opatchauto apply \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME
  # -rolling is default for RAC
  # Patches node1 first, relocates workload to node2
  # Then patches node2

# Monitor progress
tail -f /u01/app/grid/cfgtoollogs/opatchautodb/opatchauto_*.log

# ── Rollback ─────────────────────────────────────────────
$ORACLE_HOME/OPatch/opatchauto rollback \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME

# ── Verify patch applied ──────────────────────────────────
$ORACLE_HOME/OPatch/opatch lspatches | head -5
# All nodes should show same patch level

$ORACLE_HOME/OPatch/datapatch -verbose
# Apply SQL changes to database

sqlplus / as sysdba
SELECT patch_id, action, status FROM dba_registry_sqlpatch
ORDER BY action_time DESC FETCH FIRST 5 ROWS ONLY;
```

### 6.2 Manual Rolling Patch

```bash
# When OPatchAuto không available hoặc cần granular control

# NODE 1: Evict workload
srvctl relocate service -d ORCL -s APP_SVC \
  -oldinst ORCL1 -newinst ORCL2

# Verify no connections on node1
sqlplus / as sysdba << 'EOF'
SELECT COUNT(*) FROM v$session WHERE inst_id=1 AND type='USER';
EOF

# NODE 1: Shutdown instance
srvctl stop instance -d ORCL -i ORCL1 -stopoption immediate

# Stop node1 Grid (if GI patch included)
crsctl stop crs -wait

# NODE 1: Apply patch on node1
cd /opt/patches/35943157
$ORACLE_HOME/OPatch/opatch apply -silent
# If GI patch too:
$GRID_HOME/OPatch/opatch apply -silent -oh $GRID_HOME

# NODE 1: Start Grid and DB
crsctl start crs
# Wait for CRS to start
srvctl start instance -d ORCL -i ORCL1

# NODE 1: Bring services back
srvctl relocate service -d ORCL -s APP_SVC \
  -oldinst ORCL2 -newinst ORCL1

# Repeat for NODE 2, NODE 3...

# Final: Run datapatch (one time, from any node)
$ORACLE_HOME/OPatch/datapatch -verbose
```

---

## 7. ADD / REMOVE NODE

### 7.1 Add Node to RAC Cluster

```bash
# ── Phase 1: OS preparation on new node ──────────────────
# 1. Install OS packages, set kernel params
# 2. Create oracle/grid users with same UID/GID
# 3. Setup NTP, SSH equivalence
# 4. Configure /etc/hosts
# 5. Configure shared disks accessible from new node

# ── Phase 2: Extend Clusterware ──────────────────────────
# From existing node (node1), add new node
$GRID_HOME/oui/bin/addNode.sh \
  "CLUSTER_NEW_NODES={node4}" \
  "CLUSTER_NEW_VIRTUAL_HOSTNAMES={node4-vip}"

# Run root.sh on new node when prompted
# ssh root@node4 "$GRID_HOME/root.sh"

# Verify new node joined cluster
olsnodes -n
crsctl stat res -t

# ── Phase 3: Extend Oracle DB Home ───────────────────────
# From existing node:
$ORACLE_HOME/oui/bin/addNode.sh \
  "CLUSTER_NEW_NODES={node4}"

# Run root.sh on new node
# ssh root@node4 "$ORACLE_HOME/root.sh"

# ── Phase 4: Add Database Instance ───────────────────────
# Create instance ORCL4 on node4
dbca -silent -addInstance \
  -nodeName node4 \
  -gdbName ORCL \
  -instanceName ORCL4 \
  -sysDBAUserName sys \
  -sysDBAPassword Oracle_2026!

# OR using srvctl:
srvctl add instance -d ORCL -i ORCL4 -node node4
srvctl start instance -d ORCL -i ORCL4

# Verify
srvctl status database -d ORCL
SELECT inst_id, instance_name, host_name FROM gv$instance;
```

### 7.2 Remove Node from RAC

```bash
# ── Phase 1: Gracefully remove workload ──────────────────
# Relocate all services off node4
srvctl relocate service -d ORCL -s APP_SVC \
  -oldinst ORCL4 -newinst ORCL1

# Kill remaining sessions
sqlplus / as sysdba << 'EOF'
BEGIN
  FOR s IN (SELECT sid, serial# FROM gv$session
             WHERE inst_id=4 AND type='USER') LOOP
    EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION '''||
                      s.sid||','||s.serial#||',@4'' IMMEDIATE';
  END LOOP;
END;
/
EOF

# ── Phase 2: Remove DB Instance ──────────────────────────
srvctl stop instance -d ORCL -i ORCL4 -stopoption immediate
dbca -silent -deleteInstance \
  -nodeName node4 \
  -gdbName ORCL \
  -instanceName ORCL4 \
  -sysDBAUserName sys \
  -sysDBAPassword Oracle_2026!

# ── Phase 3: Remove Oracle Home from node ────────────────
# Run from node4:
$ORACLE_HOME/oui/bin/runInstaller -updateNodeList \
  ORACLE_HOME=$ORACLE_HOME \
  "CLUSTER_NODES={node1,node2,node3}" \
  -local

$ORACLE_HOME/deinstall/deinstall -local

# ── Phase 4: Remove node from cluster ────────────────────
# From node4:
crsctl stop crs

# From another node (node1):
crsctl delete node -n node4

# Verify
olsnodes -n  -- node4 should be gone
```

---

## 8. TROUBLESHOOTING RAC

### 8.1 Node Eviction Investigation

```bash
# Node eviction: CSS forcibly removes node from cluster
# Cause: missed heartbeat on voting disk or interconnect failure

# ── Find eviction cause in logs ──────────────────────────
# CSS log (most important)
grep -E "evict|eviction|reconfig|CSSD" \
  $GRID_DIAG/cssd/trace/ocssd.log | tail -100

# CRS alert log
adrci << 'EOF'
set home grid/client/$(hostname)/+asm
show alert -tail 200 -term
EOF

# ── Common eviction causes ────────────────────────────────
# 1. SLOW I/O on voting disk (disk timeout)
grep "I/O error\|I/O timeout\|disk timeout" \
  $GRID_DIAG/cssd/trace/ocssd.log | tail -30

# 2. Network (interconnect) split
grep "network\|split\|heartbeat\|halted" \
  $GRID_DIAG/cssd/trace/ocssd.log | tail -30

# 3. High load on node (unable to write heartbeat in time)
grep "load\|busy\|cpu\|hung" \
  $GRID_DIAG/cssd/trace/ocssd.log | tail -30

# ── OS-level checks ──────────────────────────────────────
# Network errors
netstat -s | grep -E "error|fail|drop"
ip -s link show eth1  # Private interconnect stats

# Disk I/O latency (should be < 100ms for voting disk)
iostat -x 1 10 | grep -E "sdc|sdd"  # Voting disk devices

# CPU and load average at eviction time
dmesg | grep -E "hung|stall|blocked"
sar -q  # Load history (if sysstat configured)

# ── Rejoin node after eviction ────────────────────────────
# 1. Investigate and fix root cause first!
# 2. Start Clusterware on evicted node:
crsctl start crs

# 3. Verify node rejoined
crsctl check crs
olsnodes -n

# 4. Start DB instance
srvctl start instance -d ORCL -i ORCL2
```

### 8.2 Split Brain Prevention

```bash
# Split Brain: beide partitions denken sie sind Primary
# Oracle verhindet durch Voting Disk Quorum

# Quorum rules:
# - Need majority votes to stay alive
# - 3 voting disks: need 2+ votes
# - 4 voting disks: need 3+ votes
# Always use ODD number of voting disks

# Check voting disk health
crsctl query css votedisk
# All must show ONLINE

# Voting disk latency test (should be < 200ms)
dd if=/dev/CRS1 of=/dev/null bs=512 count=100 2>&1

# ── OCR backup and verify ─────────────────────────────────
ocrcheck         # Verify OCR integrity
ocrconfig -showbackup  # View backup history

# Restore OCR if corrupted (cluster must be DOWN)
# ocrconfig -restore /u01/backup/ocr_backup.bkp
```

### 8.3 Common RAC Issues Quick Reference

```sql
-- 1. Find which instance is causing high GC waits
SELECT inst_id, event,
       ROUND(time_waited_micro/1e6, 2) time_sec,
       total_waits
FROM gv$system_event
WHERE event LIKE 'gc%'
ORDER BY time_waited_micro DESC
FETCH FIRST 10 ROWS ONLY;

-- 2. Find hot blocks causing cross-instance contention
SELECT o.owner, o.object_name, o.subobject_name,
       COUNT(*) waits, s.inst_id
FROM gv$session_wait sw
JOIN gv$session s ON sw.inst_id=s.inst_id AND sw.sid=s.sid
JOIN dba_objects o ON sw.p1=o.object_id
WHERE sw.event IN ('gc buffer busy acquire','gc buffer busy release',
                   'gc cr request','gc current request')
GROUP BY o.owner, o.object_name, o.subobject_name, s.inst_id
ORDER BY waits DESC;

-- 3. Sequence contention (SQ enqueue)
SELECT inst_id, sq_name, sq_enqueue,
       ROUND(sq_wait/NULLIF(sq_enqueue,0)*100, 2) pct_wait
FROM gv$sequences
WHERE sq_wait > 0
ORDER BY sq_wait DESC;

-- 4. Library cache contention (prevent hard parses in RAC)
SELECT inst_id,
       ROUND(pinhits/NULLIF(pins,0)*100, 2) lib_cache_hit_pct
FROM gv$librarycache
WHERE namespace = 'SQL AREA';

-- 5. Instance-level load distribution
SELECT inst_id,
       SUM(CASE WHEN name='user calls' THEN value END) user_calls,
       SUM(CASE WHEN name='DB time' THEN value END)/1e6 db_time_sec,
       SUM(CASE WHEN name='physical reads' THEN value END) phy_reads
FROM gv$sysstat
WHERE name IN ('user calls','DB time','physical reads')
GROUP BY inst_id
ORDER BY inst_id;
```

---

## 9. KEY srvctl và crsctl REFERENCE

```bash
# ── srvctl — RAC Resource Management ─────────────────────
# Database
srvctl start  database  -d ORCL
srvctl stop   database  -d ORCL -stopoption immediate
srvctl status database  -d ORCL [-v]
srvctl config database  -d ORCL
srvctl modify database  -d ORCL -attribute value

# Instance
srvctl start  instance  -d ORCL -i ORCL1
srvctl stop   instance  -d ORCL -i ORCL1 -stopoption abort
srvctl status instance  -d ORCL -i ORCL1

# Service
srvctl add     service  -d ORCL -s SVC_NAME -preferred ORCL1,ORCL2
srvctl start   service  -d ORCL -s SVC_NAME
srvctl stop    service  -d ORCL -s SVC_NAME [-i ORCL1]
srvctl relocate service -d ORCL -s SVC_NAME -oldinst ORCL1 -newinst ORCL2
srvctl status  service  -d ORCL [-s SVC_NAME]
srvctl remove  service  -d ORCL -s SVC_NAME

# Listener
srvctl start  listener [-l LISTENER] [-n node1]
srvctl stop   listener [-l LISTENER]
srvctl status listener
srvctl config listener

# SCAN
srvctl status scan
srvctl status scan_listener
srvctl config scan

# ASM
srvctl start  asm [-n node1]
srvctl stop   asm [-n node1]
srvctl status asm
srvctl config asm

# VIP
srvctl start  vip -node node1
srvctl stop   vip -node node1
srvctl status vip -node node1

# ── crsctl — Clusterware Management ─────────────────────
crsctl stat  res -t              # All resources status
crsctl stat  res -t -init        # Init resources (internal)
crsctl stat  res ora.ORCL.db -v  # Verbose resource status
crsctl check crs                  # Overall health
crsctl check cluster -all         # Check all nodes
crsctl query crs activeversion    # Active CRS version
crsctl query crs releaseversion   # Release version

# Start/Stop Clusterware
crsctl stop  crs                  # Stop THIS node
crsctl start crs                  # Start THIS node
crsctl stop  cluster -all         # Stop ALL nodes (dangerous!)

# OCR management
ocrcheck                          # OCR integrity check
ocrconfig -showbackup             # View OCR backup history
ocrconfig -manualbackup           # Manual backup
ocrconfig -export /tmp/ocr.bkp   # Export OCR

# Voting disk
crsctl query css votedisk         # View voting disks
crsctl add    css votedisk /dev/VD4  # Add voting disk
crsctl delete css votedisk /dev/VD1  # Remove voting disk
```

---

**Tài liệu tham khảo:**
- Oracle RAC Administration Guide 19c: Services, Patching, Troubleshooting
- Oracle Clusterware Administration Guide 19c
- MOS Note 1302736.1 (RAC Troubleshooting Guide)
- MOS Note 1059008.1 (Node Eviction / Reboot Troubleshooting)
- www.tranvanbinh.vn
