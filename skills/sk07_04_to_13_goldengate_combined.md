---
name: oracle-goldengate-complete-dg-combined
description: >
  Oracle GoldenGate toàn diện: Architecture, Configuration, Cross-Platform,
  MicroServices, Troubleshooting, kết hợp với DataGuard cho HA toàn diện.
  Kích hoạt khi hỏi về: GoldenGate Oracle, OGG architecture,
  Extract Pump Replicat GoldenGate, GoldenGate Manager,
  Integrated Extract Classic Extract, trail file GoldenGate,
  GoldenGate Microservices Architecture, ServiceManager OGG,
  Performance Metrics Server GoldenGate, Distribution Service,
  cross-platform replication GoldenGate, heterogeneous replication,
  GoldenGate Oracle to PostgreSQL, GoldenGate Oracle to Kafka,
  GoldenGate conflict resolution, bidirectional replication GoldenGate,
  GoldenGate troubleshooting, OGG-01519 abend, GoldenGate lag,
  DBLOGIN GGSCI commands, ADD EXTRACT ADD REPLICAT,
  DataGuard GoldenGate combined, hybrid HA architecture Oracle,
  zero downtime migration GoldenGate, GoldenGate initial load.
---

# SK07-04 to SK07-13 · GoldenGate Complete & DataGuard+GoldenGate Combined HA

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

# SK07-04 · GOLDENGATE ARCHITECTURE

## 1. Kiến trúc GoldenGate

```
GoldenGate Classic Architecture:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SOURCE DATABASE                      TARGET DATABASE
┌──────────────┐                    ┌──────────────┐
│ Redo/Archive │                    │              │
│   Logs       │                    │  Application │
└──────┬───────┘                    │   Tables     │
       │                            └──────▲───────┘
       ▼                                   │
┌──────────────┐                    ┌──────┴───────┐
│   Extract    │                    │   Replicat   │
│ (Capture)    │                    │   (Apply)    │
└──────┬───────┘                    └──────▲───────┘
       │                                   │
       ▼                                   │
┌──────────────┐    Network        ┌───────┴──────┐
│ Local Trail  │ ════════════════► │ Remote Trail │
│   Files      │   (Data Pump)     │   Files      │
└──────────────┘                    └──────────────┘
       ▲
       │
┌──────────────┐
│     Pump     │  (Extract phụ, ship trail sang Target)
│  (Optional)  │
└──────────────┘

Capture Modes:
  Classic Capture:    Đọc trực tiếp redo/archive logs
  Integrated Capture: Dùng Oracle LogMiner API (khuyến dùng 11.2.0.3+)
    - Tốt hơn cho RAC, CDB/PDB, ASM
    - Ít overhead trên source DB

Components:
  Manager:     Quản lý tất cả processes, port mặc định 7809
  Extract:     Capture changes từ source
  Pump:        Extract phụ, chuyển trail file sang remote
  Replicat:    Apply changes vào target
    - Classic Replicat: Single-threaded
    - Coordinated Replicat: Multi-threaded, phân theo key range
    - Integrated Replicat: Dùng Oracle apply API (12c+)
    - Parallel Replicat (19c+): Best performance, auto-parallel
```

---

# SK07-05 · GOLDENGATE INSTALLATION & CONFIGURATION

## 1. Cài đặt GoldenGate

```bash
# ── Download và Extract ───────────────────────────────────
mkdir -p /u01/ogg
cd /u01/ogg
unzip /opt/install/OGG_*.zip

# Install bằng OGG Installer (Oracle Universal Installer based)
cat > /tmp/ogg_install.rsp << 'EOF'
INSTALL_OPTION=ORA19c
SOFTWARE_LOCATION=/u01/ogg/19.1.0
START_MANAGER=false
DATABASE_LOCATION=/u01/app/oracle/product/19.3.0/dbhome_1
EOF

./fbo_ggs_Linux_x64_shiphome/Disk1/runInstaller \
  -silent -responseFile /tmp/ogg_install.rsp
```

## 2. Chuẩn bị Database cho GoldenGate

```sql
-- ── Enable supplemental logging ───────────────────────────
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- Hoặc per table:
ALTER TABLE scott.orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- ── Enable GoldenGate replication parameter ──────────────
ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE=BOTH;

-- ── Tạo GoldenGate Admin User ──────────────────────────────
CREATE TABLESPACE gg_tbs DATAFILE '+DATA' SIZE 5G AUTOEXTEND ON;
CREATE USER ggadmin IDENTIFIED BY "GGAdmin_2026!"
  DEFAULT TABLESPACE gg_tbs;
GRANT DBA TO ggadmin;
-- Hoặc quyền tối thiểu:
EXEC DBMS_GOLDENGATE_AUTH.GRANT_ADMIN_PRIVILEGE('GGADMIN');

-- ── Prepare tables cho replication ────────────────────────
EXEC DBMS_CAPTURE_ADM.PREPARE_TABLE_INSTANTIATION(
  table_name => 'SCOTT.ORDERS');

-- Hoặc cho toàn schema:
EXEC DBMS_CAPTURE_ADM.PREPARE_SCHEMA_INSTANTIATION(
  schema_name => 'SCOTT',
  supplemental_log_data_any => 'ALWAYS');
```

## 3. Cấu hình Manager

```bash
cd /u01/ogg/19.1.0
./ggsci

GGSCI> CREATE SUBDIRS

GGSCI> EDIT PARAMS MGR
```

```
-- mgr.prm
PORT 7809
DYNAMICPORTLIST 7810-7820
AUTOSTART ER *
AUTORESTART EXTRACT *, RETRIES 5, WAITMINUTES 2, RESETMINUTES 60
PURGEOLDEXTRACTS ./dirdat/*, USECHECKPOINTS, MINKEEPDAYS 3
LAGREPORTHOURS 1
LAGINFOMINUTES 30
LAGCRITICALMINUTES 60
```

```bash
GGSCI> START MGR
GGSCI> INFO MGR
GGSCI> SEND MGR STATUS
```

## 4. Cấu hình Extract

```bash
GGSCI> DBLOGIN USERID ggadmin PASSWORD GGAdmin_2026!

-- Integrated Extract (khuyến dùng)
GGSCI> REGISTER EXTRACT ext1 DATABASE

GGSCI> ADD EXTRACT ext1, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/et, EXTRACT ext1, MEGABYTES 200

GGSCI> EDIT PARAMS ext1
```

```
-- ext1.prm
EXTRACT ext1
USERID ggadmin, PASSWORD GGAdmin_2026!
EXTTRAIL ./dirdat/et
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT
GETUPDATEBEFORES

TABLE SCOTT.ORDERS;
TABLE SCOTT.CUSTOMERS;
TABLE SCOTT.ORDER_ITEMS;
```

```bash
GGSCI> START EXTRACT ext1
GGSCI> INFO EXTRACT ext1, DETAIL
GGSCI> VIEW REPORT ext1
```

## 5. Cấu hình Pump

```bash
GGSCI> ADD EXTRACT pmp1, EXTTRAILSOURCE ./dirdat/et, BEGIN NOW
GGSCI> ADD RMTTRAIL ./dirdat/rt, EXTRACT pmp1, MEGABYTES 200

GGSCI> EDIT PARAMS pmp1
```

```
-- pmp1.prm
EXTRACT pmp1
USERID ggadmin, PASSWORD GGAdmin_2026!
RMTHOST target-server, MGRPORT 7809
RMTTRAIL ./dirdat/rt
PASSTHRU

TABLE SCOTT.*;
```

```bash
GGSCI> START EXTRACT pmp1
```

## 6. Cấu hình Replicat (trên Target)

```bash
GGSCI> DBLOGIN USERID ggadmin PASSWORD GGAdmin_2026!

-- Integrated Replicat (khuyến dùng 12c+)
GGSCI> ADD REPLICAT rep1, INTEGRATED, EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS rep1
```

```
-- rep1.prm
REPLICAT rep1
USERID ggadmin, PASSWORD GGAdmin_2026!
ASSUMETARGETDEFS
DISCARDFILE ./dirrpt/rep1.dsc, APPEND, MEGABYTES 50

MAP SCOTT.ORDERS, TARGET SCOTT.ORDERS;
MAP SCOTT.CUSTOMERS, TARGET SCOTT.CUSTOMERS;
MAP SCOTT.ORDER_ITEMS, TARGET SCOTT.ORDER_ITEMS;
```

```bash
GGSCI> START REPLICAT rep1
GGSCI> INFO REPLICAT rep1, DETAIL
GGSCI> STATS REPLICAT rep1, TOTAL
```

## 7. Coordinated / Parallel Replicat (High Throughput)

```bash
-- Coordinated Replicat: phân chia theo key range, multi-thread
GGSCI> ADD REPLICAT rep_coord, COORDINATED MAXTHREADS 4,
         EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS rep_coord
```

```
REPLICAT rep_coord
USERID ggadmin, PASSWORD GGAdmin_2026!
ASSUMETARGETDEFS

-- Partition theo column để parallel
MAP SCOTT.ORDERS, TARGET SCOTT.ORDERS,
  THREADRANGE(1-4, customer_id);
```

```bash
-- Parallel Replicat (19c+, tự động parallel, không cần config thread)
GGSCI> ADD REPLICAT rep_parallel, PARALLEL,
         EXTTRAIL ./dirdat/rt

GGSCI> EDIT PARAMS rep_parallel
```

```
REPLICAT rep_parallel
USERID ggadmin, PASSWORD GGAdmin_2026!
ASSUMETARGETDEFS

MAP SCOTT.*, TARGET SCOTT.*;
```

---

# SK07-06 · GOLDENGATE INITIAL LOAD

```bash
# ── Phương pháp 1: DataPump (cho database lớn) ───────────
# Lấy SCN trước khi export
sqlplus / as sysdba << 'EOF'
SELECT current_scn FROM v$database;
EOF
# SCN: 12345678

# Export với flashback_scn (consistent snapshot)
expdp ggadmin/"GGAdmin_2026!" \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=initial_load.dmp \
  flashback_scn=12345678

# Bắt đầu Extract TỪ SCN này (capture changes sau export point)
GGSCI> ALTER EXTRACT ext1, BEGIN NOW
# Hoặc explicit SCN:
GGSCI> ALTER EXTRACT ext1, ATCSN 12345678

# Import trên target
impdp ggadmin/"GGAdmin_2026!"@TARGET \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=initial_load.dmp

# Start replication (apply changes từ sau export point)
GGSCI> START EXTRACT ext1
GGSCI> START EXTRACT pmp1
GGSCI> START REPLICAT rep1

# ── Phương pháp 2: GoldenGate Direct Load (small tables) ──
GGSCI> ADD EXTRACT initld1, SOURCEISTABLE

GGSCI> EDIT PARAMS initld1
```

```
EXTRACT initld1
USERID ggadmin, PASSWORD GGAdmin_2026!
RMTHOST target-server, MGRPORT 7809
RMTTASK REPLICAT, GROUP initrep1
TABLE SCOTT.LOOKUP_CODES;
```

```bash
GGSCI> ADD REPLICAT initrep1, SPECIALRUN
GGSCI> EDIT PARAMS initrep1
```

```
REPLICAT initrep1
USERID ggadmin, PASSWORD GGAdmin_2026!
ASSUMETARGETDEFS
MAP SCOTT.LOOKUP_CODES, TARGET SCOTT.LOOKUP_CODES;
```

```bash
GGSCI> START EXTRACT initld1
```

---

# SK07-07 · CROSS-PLATFORM REPLICATION

## 1. Oracle to PostgreSQL

```bash
# ── Extract trên Oracle (giống setup thông thường) ─────────
GGSCI> ADD EXTRACT ext_pg, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/pg, EXTRACT ext_pg

GGSCI> EDIT PARAMS ext_pg
```

```
EXTRACT ext_pg
USERID ggadmin@ORCL, PASSWORD GGAdmin_2026!
EXTTRAIL ./dirdat/pg
TABLE SCOTT.ORDERS;
TABLE SCOTT.CUSTOMERS;
```

```bash
# ── Replicat trên PostgreSQL target ────────────────────────
# Cần ODBC DSN config cho PostgreSQL connection
cat > /u01/ogg/dirsrv/odbc.ini << 'EOF'
[PG_TARGET]
Driver=/usr/lib/psqlodbcw.so
ServerName=pg-server
Port=5432
Database=targetdb
UserName=postgres
EOF

GGSCI> DBLOGIN SOURCEDB PG_TARGET, USERID postgres, PASSWORD pgpass
GGSCI> ADD REPLICAT rep_pg, EXTTRAIL ./dirdat/pg

GGSCI> EDIT PARAMS rep_pg
```

```
REPLICAT rep_pg
TARGETDB PG_TARGET, USERID postgres, PASSWORD pgpass
SOURCEDEFS ./dirdef/oracle_source.def

-- Mapping với datatype conversion
MAP SCOTT.ORDERS, TARGET public.orders,
  COLMAP (
    order_id    = order_id,
    customer_id = customer_id,
    order_date  = order_date,
    amount      = amount,
    status      = status
  );
```

```bash
# Tạo source definitions file (cần cho heterogeneous targets)
GGSCI> DEFGEN
GGSCI> EDIT PARAMS defgen
```

```
DEFSFILE ./dirdef/oracle_source.def
USERID ggadmin@ORCL, PASSWORD GGAdmin_2026!
TABLE SCOTT.ORDERS;
TABLE SCOTT.CUSTOMERS;
```

```bash
# Chạy DEFGEN để tạo definitions
./defgen paramfile dirprm/defgen.prm
# Copy file .def sang target server
scp dirdef/oracle_source.def oracle@pg-server:/u01/ogg/dirdef/
```

## 2. Oracle to Kafka (Streaming)

```
-- rep_kafka.prm
REPLICAT rep_kafka
TARGETDB LIBFILE libggjava.so SET property=./dirprm/kafka.props
REPORTCOUNT EVERY 1 MINUTES, RATE
GROUPTRANSOPS 1000
MAP SCOTT.ORDERS, TARGET SCOTT.ORDERS;
```

```properties
# kafka.props
gg.handlerlist=kafkahandler
gg.handler.kafkahandler.type=kafka
gg.handler.kafkahandler.KafkaProducerConfigFile=kafka-producer.properties
gg.handler.kafkahandler.TopicName=oracle_orders_topic
gg.handler.kafkahandler.format=json
gg.handler.kafkahandler.mode=op
```

```properties
# kafka-producer.properties
bootstrap.servers=kafka-broker1:9092,kafka-broker2:9092
acks=1
compression.type=gzip
```

---

# SK07-08 · GOLDENGATE MICROSERVICES ARCHITECTURE (19c+)

## 1. Microservices vs Classic Architecture

```
GoldenGate Microservices Architecture (MA):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ServiceManager (orchestrator)
       │
   ┌───┼────────┬────────────┬─────────────┐
   ▼            ▼            ▼             ▼
Admin       Distribution  Receiver    Performance
Service     Service       Service     Metrics Server
   │            │            │             │
   └── REST API based, web UI dashboard ───┘

Lợi ích MA vs Classic:
  + Web-based admin UI (không cần GGSCI command line)
  + REST API cho automation
  + Better security (TLS, authentication tokens)
  + Containerized deployment friendly
  + Built-in monitoring dashboard
```

## 2. Cài đặt Microservices

```bash
# ── Install GoldenGate MA ──────────────────────────────────
cd /u01/ogg_ma
unzip /opt/install/OGG_Microservices.zip
./fbo_ggs_Linux_x64_services_shiphome/Disk1/runInstaller \
  -silent \
  -responseFile /tmp/ogg_ma_install.rsp

# ── Configure ServiceManager ──────────────────────────────
cat > /u01/ogg_ma/deployment.json << 'EOF'
{
  "name": "OracleDeployment",
  "type": "oracle",
  "rootPath": "/u01/ogg_ma/deployments/OracleDeployment"
}
EOF

# Start ServiceManager
/u01/ogg_ma/bin/ServiceManager &

# ── Truy cập Web UI ────────────────────────────────────────
# https://server:443/sm  (ServiceManager UI)
# https://server:443/admin (Admin Service)
```

## 3. Quản lý qua REST API

```bash
# Tạo deployment
curl -k -X POST https://localhost:443/services/v2/deployments \
  -H "Content-Type: application/json" \
  -u oggadmin:Password_2026! \
  -d '{
    "name": "OracleDeployment",
    "deploymentSubType": "oracle",
    "credentialStorePassword": "Pass_2026!"
  }'

# Tạo Extract qua REST API
curl -k -X POST \
  https://localhost:443/services/v2/deployments/OracleDeployment/extracts \
  -H "Content-Type: application/json" \
  -u oggadmin:Password_2026! \
  -d '{
    "name": "EXT1",
    "processType": "INTEGRATED_EXTRACT",
    "begin": "now"
  }'

# Start Extract
curl -k -X POST \
  https://localhost:443/services/v2/deployments/OracleDeployment/extracts/EXT1/start \
  -u oggadmin:Password_2026!

# Get status
curl -k -X GET \
  https://localhost:443/services/v2/deployments/OracleDeployment/extracts/EXT1 \
  -u oggadmin:Password_2026!
```

---

# SK07-09 · GOLDENGATE MONITORING

```bash
# ── GGSCI Monitoring Commands ──────────────────────────────
GGSCI> INFO ALL
GGSCI> INFO EXTRACT ext1, DETAIL
GGSCI> INFO REPLICAT rep1, DETAIL

GGSCI> LAG EXTRACT ext1
GGSCI> LAG REPLICAT rep1

GGSCI> STATS EXTRACT ext1, TOTAL
GGSCI> STATS REPLICAT rep1, TOTAL, REPORTRATE MIN

GGSCI> VIEW REPORT ext1
GGSCI> VIEW GGSEVT

# Checkpoint info
GGSCI> INFO EXTRACT ext1, SHOWCH
GGSCI> INFO REPLICAT rep1, SHOWCH

# ── Trail file info ────────────────────────────────────────
GGSCI> INFO EXTTRAIL ./dirdat/et, DETAIL
GGSCI> SEND EXTRACT ext1, STATUS
GGSCI> SEND REPLICAT rep1, STATUS
```

```sql
-- ── Heartbeat table (monitor lag từ SQL) ──────────────────
EXEC DBMS_GOLDENGATE.ADD_HEARTBEAT_TABLE;

SELECT path_name, lag_secs,
       TO_CHAR(last_updated, 'YYYY-MM-DD HH24:MI:SS') last_update
FROM gg_heartbeat
ORDER BY last_updated DESC;
```

```bash
#!/bin/bash
# gg_monitor.sh — Automation script
export OGG_HOME=/u01/ogg/19.1.0
cd $OGG_HOME

REPORT=/tmp/gg_status_$(date +%Y%m%d_%H%M).txt
echo "=== GoldenGate Status $(date) ===" > $REPORT

echo "INFO ALL" | ./ggsci >> $REPORT 2>&1

# Check for ABENDED processes
if grep -q "ABENDED" $REPORT; then
  mail -s "⚠️ GoldenGate ABEND Alert" dba-team@company.com < $REPORT
fi

# Check lag threshold
LAG=$(echo "LAG REPLICAT rep1" | ./ggsci | grep -oP 'Lag.*?\K[\d:]+' | head -1)
echo "Current lag: $LAG"
```

---

# SK07-10 · GOLDENGATE TROUBLESHOOTING

```bash
# ── OGG-01519: Error processing record (fetch column error) ──
# Nguyên nhân: Schema thay đổi mà GG chưa biết
GGSCI> STOP EXTRACT ext1
GGSCI> DBLOGIN USERID ggadmin PASSWORD pass
GGSCI> ALTER EXTRACT ext1, TRANLOG, BEGIN NOW
GGSCI> START EXTRACT ext1

# ── Replicat ABEND - Duplicate key error ──────────────────
# Xem report để biết SQL/row gây lỗi
GGSCI> VIEW REPORT rep1

# Add error handling vào params
```

```
-- Thêm vào rep1.prm
REPERROR (DEFAULT, DISCARD)
-- Hoặc skip specific errors:
REPERROR (ORA-00001, DISCARD)   -- Skip duplicate key
REPERROR (ORA-01403, DISCARD)   -- Skip no data found
```

```bash
GGSCI> START REPLICAT rep1

# ── Resolve ABEND và restart từ checkpoint cụ thể ─────────
GGSCI> INFO REPLICAT rep1, SHOWCH
# Xem checkpoint hiện tại

GGSCI> ALTER REPLICAT rep1, AFTERCSN 12345678
GGSCI> START REPLICAT rep1

# ── High lag troubleshooting ───────────────────────────────
# 1. Kiểm tra network bandwidth giữa source-target
# 2. Kiểm tra target DB performance (locks, slow disk)
GGSCI> SEND REPLICAT rep1, GETLAG

# 3. Tăng BATCHSQL cho throughput
```

```
-- Thêm vào replicat params
BATCHSQL
  BATCHESPERQUEUE 50
  BATCHTRANSOPS 1000
```

```bash
# 4. Convert sang Parallel Replicat nếu vẫn chậm (xem SK07-05)

# ── Trail file space issues ────────────────────────────────
GGSCI> INFO EXTTRAIL ./dirdat/et
# Kiểm tra disk space:
df -h /u01/ogg/dirdat

# Purge old trail files đã processed
GGSCI> SEND MGR FORCESTOP
GGSCI> EDIT PARAMS MGR
-- Đảm bảo PURGEOLDEXTRACTS configured đúng

# ── Recovery sau crash ─────────────────────────────────────
GGSCI> INFO ALL
# Kiểm tra tất cả processes status

# Restart từng process
GGSCI> START EXTRACT ext1
GGSCI> START EXTRACT pmp1
GGSCI> START REPLICAT rep1

# Nếu cần resync hoàn toàn (last resort):
GGSCI> DELETE REPLICAT rep1
GGSCI> ADD REPLICAT rep1, EXTTRAIL ./dirdat/rt, BEGIN NOW
-- Cần initial load lại data trước!
```

---

# SK07-11 to SK07-13 · DATAGUARD + GOLDENGATE COMBINED HA

## 1. Kiến trúc Hybrid HA

```
Combined DataGuard + GoldenGate Architecture:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                  PRIMARY DATACENTER
         ┌─────────────────────────────────┐
         │  PRIMARY DB                     │
         │  (RAC + Active Data Guard)      │
         └──────────┬───────────────────────┘
                     │
        ┌────────────┼────────────┐
        │ DataGuard   │  GoldenGate
        │ (Sync)      │  (Async, selective)
        ▼             ▼
┌──────────────┐  ┌──────────────────────┐
│ DR DATACENTER│  │  REPORTING/ANALYTICS  │
│              │  │  DATACENTER           │
│ STANDBY DB   │  │  (Different schema/   │
│ (Physical)   │  │   different platform) │
└──────────────┘  └──────────────────────┘

Use Cases cho Combined Architecture:
1. DataGuard cho Disaster Recovery (full DB, identical structure)
2. GoldenGate cho:
   - Cross-platform reporting database (different indexes)
   - Real-time data feed to Kafka/Data Lake
   - Multi-master writes ở multiple datacenters
   - Zero-downtime migration trong khi DG vẫn protect
```

## 2. Setup Combined Architecture

```sql
-- ── Trên Primary: Cả 2 cùng hoạt động ─────────────────────
-- DataGuard configuration (như SK07-01)
ALTER SYSTEM SET log_archive_dest_2 =
  'SERVICE=ORCL_STB ASYNC
   VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
   DB_UNIQUE_NAME=ORCL_STB' SCOPE=BOTH;

-- GoldenGate cần riêng supplemental logging
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE=BOTH;

-- Cả hai dùng CHUNG archive logs từ Primary
-- DataGuard: Redo Apply trên Standby
-- GoldenGate: Integrated Extract đọc cùng archive logs
```

```bash
# GoldenGate Extract chạy độc lập với DataGuard
GGSCI> ADD EXTRACT ext_reporting, INTEGRATED TRANLOG, BEGIN NOW
GGSCI> ADD EXTTRAIL ./dirdat/rp, EXTRACT ext_reporting

GGSCI> EDIT PARAMS ext_reporting
```

```
EXTRACT ext_reporting
USERID ggadmin, PASSWORD GGAdmin_2026!
EXTTRAIL ./dirdat/rp

-- Chỉ replicate tables cần cho reporting (không phải toàn DB)
TABLE SCOTT.ORDERS;
TABLE SCOTT.ORDER_SUMMARY;
```

## 3. Failover Coordination

```bash
# ── Khi DataGuard Failover xảy ra ──────────────────────────
# GoldenGate Extract phải switch sang Standby (giờ là Primary mới)

# Trước Failover: GoldenGate Extract đọc từ Primary cũ
# Sau Failover: Cần update Extract để đọc từ Primary mới (= Standby cũ)

# Bước 1: Stop Extract trên Primary cũ (nếu accessible)
GGSCI> STOP EXTRACT ext_reporting

# Bước 2: Restart Extract trên server MỚI là Primary
# (Có thể cần ADD EXTRACT mới nếu GoldenGate process chạy trên DB server)
GGSCI> DBLOGIN USERID ggadmin@NEW_PRIMARY PASSWORD pass
GGSCI> ALTER EXTRACT ext_reporting, ETROLLOVER
GGSCI> START EXTRACT ext_reporting

# ── Automation: Script handle Combined Failover ───────────
```

```bash
#!/bin/bash
# combined_failover.sh — Coordinate DG failover + GG restart

echo "=== Step 1: DataGuard Failover ==="
dgmgrl / << 'EOF'
FAILOVER TO 'ORCL_STB';
EOF

echo "=== Step 2: Verify new Primary ==="
NEW_PRIMARY_ROLE=$(sqlplus -S sys/pass@ORCL_STB as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT database_role FROM v$database;
EOF
)

if [ "$NEW_PRIMARY_ROLE" != "PRIMARY" ]; then
  echo "ERROR: Failover did not complete successfully!"
  exit 1
fi

echo "=== Step 3: Restart GoldenGate Extract on new Primary ==="
ssh oracle@new-primary-server << 'EOF'
cd /u01/ogg/19.1.0
echo "DBLOGIN USERID ggadmin PASSWORD GGAdmin_2026!
ALTER EXTRACT ext_reporting, ETROLLOVER
START EXTRACT ext_reporting" | ./ggsci
EOF

echo "=== Combined Failover Complete ==="
```

## 4. Best Practices cho Combined HA

```
Khuyến nghị triển khai:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Dùng DataGuard cho:
   - Full database disaster recovery
   - Zero/minimal data loss requirements
   - Identical structure failover target

2. Dùng GoldenGate cho:
   - Selective table replication
   - Cross-platform/cross-version targets
   - Zero-downtime migrations
   - Active-Active multi-master (nếu cần)
   - Real-time feeds to non-Oracle targets

3. Monitoring cả hai:
   - DataGuard: v$dataguard_stats, DGMGRL SHOW CONFIGURATION
   - GoldenGate: GGSCI LAG/STATS, Heartbeat table

4. Testing Failover Procedures:
   - Test DataGuard switchover hàng quý
   - Test GoldenGate reconnection sau DG failover
   - Document RTO/RPO cho mỗi component
   - Automation script cho coordinated failover (như trên)

5. Resource Planning:
   - GoldenGate Extract thêm overhead lên Primary
   - Đảm bảo đủ CPU/Memory cho cả DG + GG processes
   - Network bandwidth: DG (full redo) + GG (selective) traffic
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

**Tài liệu tham khảo — SK07-04 đến SK07-13:**
- Oracle GoldenGate Administration Guide 19c
- Oracle GoldenGate Microservices Architecture Guide
- Oracle GoldenGate for Big Data and Streaming
- Oracle Data Guard + GoldenGate Combined Architectures (MOS Note 1929625.1)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
