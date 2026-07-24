---
name: oracle-goldengate-migration-zdm
description: >
  GoldenGate Zero Downtime Migration và SQL Loader Oracle.
  Kích hoạt khi hỏi về: GoldenGate migration zero downtime ZDM,
  GoldenGate online migration, zero downtime Oracle migration,
  SQL Loader Oracle sqlldr, sqlldr control file, direct path load,
  conventional path load, external tables Oracle, ORACLE_LOADER,
  ORACLE_DATAPUMP external table, big data loading Oracle,
  parallel load Oracle, sqlldr bad file discard file,
  GoldenGate initial load, GoldenGate cutover, ZDM Oracle tool,
  Oracle Cloud migration ZDM, logical migration GoldenGate,
  Multitenant PDB migration unplug plug clone PDB,
  PDB relocation cross-CDB, Oracle 23ai 26ai new features setup.
---

# SK01-08 → SK01-14 · GoldenGate ZDM, SQL Loader, PDB Migration & 26ai

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

# SK01-08 · GoldenGate Zero-Downtime Migration

## 1. KIẾN TRÚC ZDM VỚI GOLDENGATE

```
Giai đoạn migration với GoldenGate:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase 1 — Initial Load (DataPump export/import):
  SOURCE DB ──[expdp]──► dump files ──[impdp]──► TARGET DB
  GoldenGate Extract đã chạy → capture tất cả changes

Phase 2 — Delta Apply (GoldenGate replication):
  SOURCE DB ──[OGG Extract]──[trail]──[Replicat]──► TARGET DB
  Continuous sync cho đến khi lag < 1 giây

Phase 3 — Cutover:
  - Quiesce SOURCE application
  - Chờ GoldenGate lag = 0
  - Verify TARGET data complete
  - Switch application → TARGET
  - Stop GoldenGate

Total Downtime: < 5 phút (chỉ trong cutover phase)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. GOLDENGATE SETUP CHO MIGRATION

### 2.1 Chuẩn bị Source DB

```sql
-- Enable supplemental logging đầy đủ
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
-- Hoặc per table:
ALTER TABLE scott.orders ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;

-- Enable GoldenGate replication
ALTER SYSTEM SET enable_goldengate_replication = TRUE SCOPE=BOTH;

-- Tạo GoldenGate admin user
CREATE USER c##gg_admin IDENTIFIED BY "GG_2026!"
  DEFAULT TABLESPACE USERS
  CONTAINER = ALL;
EXEC DBMS_GOLDENGATE_AUTH.GRANT_ADMIN_PRIVILEGE('C##GG_ADMIN',container=>'ALL');
GRANT DBA TO c##gg_admin CONTAINER=ALL;

-- Tạo GoldenGate Heartbeat table (monitor lag)
EXEC DBMS_GOLDENGATE.ADD_HEARTBEAT_TABLE;
```

### 2.2 Phase 1: Initial Load (DataPump)

```bash
# 1. Lấy SCN tại thời điểm bắt đầu export
SOURCE_SCN=$(sqlplus -S sys/"Oracle_2026!"@SOURCE as sysdba << 'EOF'
SET HEADING OFF FEEDBACK OFF
SELECT current_scn FROM v$database;
EXIT;
EOF
)
echo "Export SCN: $SOURCE_SCN"

# 2. Export từ SCN này (consistent snapshot)
expdp system/"Oracle_2026!"@SOURCE \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=zdm_full_%U.dmp \
  logfile=zdm_export.log \
  flashback_scn=$SOURCE_SCN \
  parallel=8 \
  compression=ALL \
  exclude=STATISTICS

# 3. Import vào TARGET
impdp system/"Oracle_2026!"@TARGET \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=zdm_full_%U.dmp \
  logfile=zdm_import.log \
  parallel=8 \
  exclude=STATISTICS

# 4. Gather stats trên TARGET
sqlplus / as sysdba@TARGET << 'EOF'
EXEC DBMS_STATS.GATHER_DATABASE_STATS(options=>'GATHER',degree=>8);
EXIT;
EOF
```

### 2.3 Phase 2: GoldenGate Setup

```bash
# ── Extract (Source) ──────────────────────────────────────
ggsci << 'EOF'
DBLOGIN USERID c##gg_admin PASSWORD GG_2026! SYSDBA

-- Create extract từ SCN của export
ADD EXTRACT ZDM_EXT, INTEGRATED TRANLOG, SCN $SOURCE_SCN
ADD EXTTRAIL ./dirdat/zd, EXTRACT ZDM_EXT, MEGABYTES 500
EDIT PARAMS ZDM_EXT
EOF

# Params file ZDM_EXT:
cat > $OGG_HOME/dirprm/zdm_ext.prm << 'EOF'
EXTRACT ZDM_EXT
USERID c##gg_admin@SOURCE, PASSWORD GG_2026!
EXTTRAIL ./dirdat/zd
LOGALLSUPCOLS
UPDATERECORDFORMAT COMPACT

-- Capture tất cả tables (hoặc chỉ định schema)
TABLE SCOTT.*;
TABLE HR.*;
TABLE APP.*;
EOF

# ── Pump (Source → Target) ───────────────────────────────
ggsci << 'EOF'
ADD EXTRACT ZDM_PMP, EXTTRAILSOURCE ./dirdat/zd, BEGIN NOW
ADD RMTTRAIL ./dirdat/zr, EXTRACT ZDM_PMP, MEGABYTES 500
EDIT PARAMS ZDM_PMP
EOF

cat > $OGG_HOME/dirprm/zdm_pmp.prm << 'EOF'
EXTRACT ZDM_PMP
USERID c##gg_admin@SOURCE, PASSWORD GG_2026!
RMTHOST target-server, MGRPORT 7809
RMTTRAIL ./dirdat/zr
TABLE SCOTT.*;
TABLE HR.*;
TABLE APP.*;
EOF

# ── Replicat (Target) ────────────────────────────────────
ggsci << 'EOF'
DBLOGIN USERID gg_admin@TARGET PASSWORD GG_2026!
ADD CHECKPOINTTABLE gg_admin.checkpoint
ADD REPLICAT ZDM_REP, INTEGRATED, EXTTRAIL ./dirdat/zr, CHECKPOINTTABLE gg_admin.checkpoint
EDIT PARAMS ZDM_REP
EOF

cat > $OGG_HOME/dirprm/zdm_rep.prm << 'EOF'
REPLICAT ZDM_REP
USERID gg_admin@TARGET, PASSWORD GG_2026!
ASSUMETARGETDEFS

-- Error handling: skip duplicate key errors (từ initial load overlap)
REPERROR (ORA-00001, DISCARD)

MAP SCOTT.*, TARGET SCOTT.*;
MAP HR.*, TARGET HR.*;
MAP APP.*, TARGET APP.*;
EOF

# ── Start processes ──────────────────────────────────────
ggsci << 'EOF'
START EXTRACT ZDM_EXT
START EXTRACT ZDM_PMP
-- (Trên target server:)
-- START REPLICAT ZDM_REP
EOF
```

### 2.4 Phase 3: Monitor và Cutover

```bash
# Monitor lag đến khi < 1 giây
watch -n 5 'ggsci << EOF
INFO ALL
LAG EXTRACT ZDM_EXT
LAG REPLICAT ZDM_REP
EOF'

# Cutover procedure:
# 1. Thông báo application team
# 2. Stop ứng dụng viết vào SOURCE
# 3. Đợi GoldenGate flush (lag = 0)
ggsci << 'EOF'
STATUS REPLICAT ZDM_REP
STATS REPLICAT ZDM_REP, TOTAL, REPORTRATE MIN
EOF

# 4. Verify TARGET data count
sqlplus / as sysdba@TARGET << 'EOF'
SELECT 'ORDERS', COUNT(*) FROM scott.orders UNION ALL
SELECT 'CUSTOMERS', COUNT(*) FROM scott.customers;
EOF

# So sánh với SOURCE
sqlplus / as sysdba@SOURCE << 'EOF'
SELECT 'ORDERS', COUNT(*) FROM scott.orders UNION ALL
SELECT 'CUSTOMERS', COUNT(*) FROM scott.customers;
EOF

# 5. Switch application → TARGET
# 6. Stop GoldenGate
ggsci << 'EOF'
STOP REPLICAT ZDM_REP
STOP EXTRACT ZDM_PMP
STOP EXTRACT ZDM_EXT
DELETE REPLICAT ZDM_REP
DELETE EXTRACT ZDM_PMP
DELETE EXTRACT ZDM_EXT
EOF
```

---

# SK01-09 · SQL Loader & External Tables

## 1. SQL LOADER (sqlldr)

### 1.1 Control File và Command

```bash
# Control file cơ bản
cat > /tmp/orders_load.ctl << 'EOF'
LOAD DATA
INFILE '/data/orders.csv'
BADFILE '/data/orders.bad'
DISCARDFILE '/data/orders.dsc'
APPEND INTO TABLE scott.orders_staging
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
TRAILING NULLCOLS
(
  order_id    INTEGER EXTERNAL,
  customer_id INTEGER EXTERNAL,
  order_date  DATE "YYYY-MM-DD",
  amount      DECIMAL EXTERNAL,
  status      CHAR(20)
)
EOF

# Chạy sqlldr
sqlldr userid=scott/"Tiger_2026!" \
  control=/tmp/orders_load.ctl \
  log=/tmp/orders_load.log \
  rows=10000 \
  bindsize=10485760 \
  readsize=10485760 \
  direct=true \         # Direct path = bypass SGA, nhanh hơn
  parallel=true         # Parallel direct path load

# Monitor progress
tail -f /tmp/orders_load.log
```

### 1.2 Advanced SQL Loader Options

```bash
# ── Multiple input files ──────────────────────────────────
cat > /tmp/multi_file.ctl << 'EOF'
LOAD DATA
INFILE '/data/orders_jan.csv'
INFILE '/data/orders_feb.csv'
INFILE '/data/orders_mar.csv'
APPEND INTO TABLE orders_staging
FIELDS TERMINATED BY ','
(order_id, customer_id, order_date DATE "YYYYMMDD", amount)
EOF

# ── Multiple tables from single file ─────────────────────
cat > /tmp/multi_table.ctl << 'EOF'
LOAD DATA
INFILE '/data/mixed_data.dat'
INTO TABLE orders
  WHEN (1:1) = 'O'
  FIELDS TERMINATED BY '|'
  (rec_type FILLER, order_id, customer_id, amount)
INTO TABLE customers
  WHEN (1:1) = 'C'
  FIELDS TERMINATED BY '|'
  (rec_type FILLER, customer_id, name, email)
EOF

# ── LOB loading ───────────────────────────────────────────
cat > /tmp/lob_load.ctl << 'EOF'
LOAD DATA
INFILE '/data/products.csv'
APPEND INTO TABLE products
FIELDS TERMINATED BY '|'
(
  product_id  INTEGER EXTERNAL,
  name        CHAR,
  description CHAR(4000),
  image_file  LOBFILE(image_file_name) TERMINATED BY EOF,
  image_file_name FILLER CHAR
)
EOF

# ── Transformation trong control file ────────────────────
cat > /tmp/transform.ctl << 'EOF'
LOAD DATA
INFILE '/data/raw.csv'
APPEND INTO TABLE staging
FIELDS TERMINATED BY ','
(
  raw_id,
  full_name,
  first_name  "TRIM(SUBSTR(:full_name, 1, INSTR(:full_name,' ')-1))",
  last_name   "TRIM(SUBSTR(:full_name, INSTR(:full_name,' ')+1))",
  load_date   "SYSDATE",
  status      CONSTANT 'ACTIVE'
)
EOF
```

## 2. EXTERNAL TABLES

```sql
-- External table với ORACLE_LOADER (read CSV)
CREATE TABLE ext_orders (
  order_id    NUMBER,
  customer_id NUMBER,
  order_date  DATE,
  amount      NUMBER,
  status      VARCHAR2(20)
)
ORGANIZATION EXTERNAL (
  TYPE ORACLE_LOADER
  DEFAULT DIRECTORY EXT_DATA_DIR
  ACCESS PARAMETERS (
    RECORDS DELIMITED BY NEWLINE
    SKIP 1                          -- Skip header row
    FIELDS TERMINATED BY ','
    OPTIONALLY ENCLOSED BY '"'
    MISSING FIELD VALUES ARE NULL
    REJECT ROWS WITH ALL NULL FIELDS
    (
      order_id    INTEGER EXTERNAL,
      customer_id INTEGER EXTERNAL,
      order_date  CHAR DATE_FORMAT DATE MASK "YYYY-MM-DD",
      amount      DECIMAL EXTERNAL,
      status      CHAR
    )
  )
  LOCATION ('orders_jan.csv', 'orders_feb.csv')  -- Multiple files
)
REJECT LIMIT UNLIMITED
PARALLEL;

-- Query external table (no load needed)
SELECT COUNT(*), SUM(amount) FROM ext_orders WHERE status='COMPLETED';

-- Load from external table
INSERT /*+ APPEND */ INTO orders SELECT * FROM ext_orders;
COMMIT;

-- External table với ORACLE_DATAPUMP format
CREATE TABLE ext_datapump_export
ORGANIZATION EXTERNAL (
  TYPE ORACLE_DATAPUMP
  DEFAULT DIRECTORY DATA_PUMP_DIR
  LOCATION ('ext_export.dmp')
)
AS SELECT * FROM orders WHERE order_date > SYSDATE - 90;

-- Sau đó import trên server khác:
CREATE TABLE orders_imported
ORGANIZATION EXTERNAL (
  TYPE ORACLE_DATAPUMP
  DEFAULT DIRECTORY DATA_PUMP_DIR
  LOCATION ('ext_export.dmp')
);
INSERT INTO orders_final SELECT * FROM orders_imported;
```

---

# SK01-10 · Multitenant PDB Migration

## 1. UNPLUG/PLUG MIGRATION

```sql
-- ── Unplug từ source CDB ──────────────────────────────────
-- Bước 1: Đảm bảo PDB healthy
ALTER PLUGGABLE DATABASE pdb_app OPEN READ WRITE;
SELECT * FROM pdb_alert_logs WHERE con_id = (
  SELECT con_id FROM v$pdbs WHERE name = 'PDB_APP');

-- Bước 2: Kiểm tra compatibility
SELECT DBMS_PDB.CHECK_PLUG_COMPATIBILITY(
  pdb_descr_file => '/tmp/pdb_app.xml') compatible
FROM dual;
-- YES = compatible; NO = xem dba_pdb_plug_in_violations

-- Bước 3: Close và Unplug
ALTER PLUGGABLE DATABASE pdb_app CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_app
  UNPLUG INTO '/tmp/pdb_app_manifest.xml';

-- Bước 4: Drop từ source (giữ files nếu muốn plug vào CDB khác)
DROP PLUGGABLE DATABASE pdb_app KEEP DATAFILES;

-- ── Plug vào target CDB ──────────────────────────────────
-- Kiểm tra compatibility trên target
SELECT DBMS_PDB.CHECK_PLUG_COMPATIBILITY(
  pdb_descr_file => '/tmp/pdb_app_manifest.xml',
  pdb_name       => 'PDB_APP') compatible
FROM dual;

-- Plug (NOCOPY: files giữ nguyên location)
CREATE PLUGGABLE DATABASE pdb_app
  USING '/tmp/pdb_app_manifest.xml'
  NOCOPY
  TEMPFILE REUSE;

-- Plug với COPY (sao chép files sang location mới)
CREATE PLUGGABLE DATABASE pdb_app
  USING '/tmp/pdb_app_manifest.xml'
  COPY
  FILE_NAME_CONVERT = (
    '/old/oradata/SOURCE/',
    '/new/oradata/TARGET/'
  );

-- Open và verify
ALTER PLUGGABLE DATABASE pdb_app OPEN;
ALTER PLUGGABLE DATABASE pdb_app SAVE STATE;

SELECT con_id, name, open_mode FROM v$pdbs WHERE name = 'PDB_APP';
```

## 2. PDB CLONING (ONLINE)

```sql
-- Clone PDB (không cần đưa source về READ ONLY)
-- 19c+: Refreshable Clone
CREATE PLUGGABLE DATABASE pdb_clone
  FROM pdb_source
  FILE_NAME_CONVERT = (
    '/oradata/SOURCE/', '/oradata/CLONE/'
  )
  REFRESH MODE MANUAL;   -- Có thể refresh manually

-- Thin Clone với ASM (tiết kiệm storage)
CREATE PLUGGABLE DATABASE pdb_thin
  FROM pdb_source
  SNAPSHOT COPY           -- Chỉ dùng với ASM + ACFS

-- Refresh clone từ source
ALTER PLUGGABLE DATABASE pdb_clone CLOSE;
ALTER PLUGGABLE DATABASE pdb_clone REFRESH;
ALTER PLUGGABLE DATABASE pdb_clone OPEN;

-- PDB Relocation (cross-CDB, online, 12.2+)
-- Từ TARGET CDB, kéo PDB sang:
CREATE PLUGGABLE DATABASE pdb_app
  FROM pdb_app@source_cdb_link  -- DB Link đến source CDB
  RELOCATE
  FILE_NAME_CONVERT = (
    '/source/oradata/', '/target/oradata/'
  )
  AVAILABILITY MAX;   -- AVAILABILITY MAX = zero downtime
```

---

# SK01-11 · Cross-Platform Migration (Endian Conversion)

## 1. XTTS (Cross-Platform Transportable Tablespace)

```bash
# XTTS = phương pháp migration với minimal downtime cross-endian

# ── Phase 1: Initial copy (DB vẫn open READ WRITE) ──────
# Trên source (Linux):
rman target / << 'EOF'
BACKUP
  FOR TRANSPORT
  ALLOW INCONSISTENT
  FORMAT '/xtts/backup/%d_%T_%s_%p.bkp'
  TABLESPACE APP_DATA, APP_INDX, APP_LOB;
EOF

# ── Phase 2: Convert (trên target hoặc source) ───────────
rman target sys/"Oracle_2026!"@TARGET << 'EOF'
RESTORE
  FROM PLATFORM 'Linux x86 64-bit'
  FORMAT '/u01/oradata/TARGET/%N_%f.dbf'
  FOREIGN TABLESPACE APP_DATA, APP_INDX, APP_LOB
  FROM BACKUPSET '/xtts/backup/ORCL_20260115_*.bkp';
EOF

# ── Phase 3: Incremental backup + merge ──────────────────
# Lặp lại nhiều lần để giảm downtime
rman target / << 'EOF'
BACKUP INCREMENTAL FROM SCN $PREV_SCN
  FOR TRANSPORT
  ALLOW INCONSISTENT
  FORMAT '/xtts/incr/%d_%T_%s_%p.bkp'
  TABLESPACE APP_DATA, APP_INDX, APP_LOB;
EOF

rman target sys/"Oracle_2026!"@TARGET << 'EOF'
RECOVER FOREIGN TABLESPACE APP_DATA, APP_INDX, APP_LOB
  FROM BACKUPSET '/xtts/incr/*.bkp'
  FROM PLATFORM 'Linux x86 64-bit'
  FOREIGN DATAFILECOPY '/u01/oradata/TARGET/app_data01.dbf';
EOF

# ── Phase 4: Final cutover (minimal downtime) ─────────────
# Đưa tablespace READ ONLY → final export metadata → cutover
```

---

# SK01-12 · Oracle 23ai / 26ai Features Setup

## 1. AI VECTOR SEARCH

```sql
-- Vector data type (23ai+)
CREATE TABLE doc_embeddings (
  id          NUMBER GENERATED ALWAYS AS IDENTITY,
  doc_id      VARCHAR2(100),
  chunk_text  CLOB,
  embedding   VECTOR(1536)    -- 1536-dim cho text-embedding-ada-002
);

-- Load ONNX model cho local embedding
CREATE OR REPLACE DIRECTORY ONNX_MODEL_DIR AS '/u01/onnx_models';

EXECUTE DBMS_VECTOR.LOAD_ONNX_MODEL(
  directory  => 'ONNX_MODEL_DIR',
  file_name  => 'multilingual-e5-small.onnx',
  model_name => 'MY_EMBED_MODEL',
  metadata   => JSON('{"function":"embedding",
                       "embeddingOutput":"embedding",
                       "input":{"input":["DATA"]}}')
);

-- Generate embedding bằng model
INSERT INTO doc_embeddings (doc_id, chunk_text, embedding)
SELECT 'DOC001', 'Oracle Database là hệ quản trị CSDL mạnh nhất',
  VECTOR_EMBEDDING(MY_EMBED_MODEL USING
    'Oracle Database là hệ quản trị CSDL mạnh nhất' AS DATA)
FROM dual;

-- Vector search (tìm tài liệu tương tự)
SELECT doc_id, chunk_text,
       VECTOR_DISTANCE(embedding, :query_vector, COSINE) distance
FROM doc_embeddings
ORDER BY distance
FETCH APPROX FIRST 10 ROWS ONLY
WITH TARGET ACCURACY 90;

-- HNSW Index cho tìm kiếm nhanh (approximate)
CREATE VECTOR INDEX vec_idx ON doc_embeddings(embedding)
  ORGANIZATION INMEMORY NEIGHBOR GRAPH
  DISTANCE COSINE
  WITH TARGET ACCURACY 90;

-- IVF Index (Inverted File Flat, tiết kiệm memory)
CREATE VECTOR INDEX vec_ivf_idx ON doc_embeddings(embedding)
  ORGANIZATION NEIGHBOR PARTITIONS
  DISTANCE COSINE
  WITH TARGET ACCURACY 95
  PARAMETERS (type IVF, neighbor partitions 64);
```

## 2. JSON RELATIONAL DUALITY VIEWS (23ai)

```sql
-- Duality View: expose relational data as JSON documents
-- Application dùng REST API với JSON, DB lưu relational

CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW order_dv AS
SELECT JSON {
  '_id'       : o.order_id,
  'status'    : o.status,
  'orderDate' : o.order_date,
  'amount'    : o.amount,
  'customer'  : (
    SELECT JSON {
      'id'    : c.customer_id,
      'name'  : c.name,
      'email' : c.email
    }
    FROM customers c WHERE c.customer_id = o.customer_id
    WITH UPDATE
  ),
  'items'     : [
    SELECT JSON {
      'product' : i.product_name,
      'qty'     : i.quantity,
      'price'   : i.unit_price
    }
    FROM order_items i WHERE i.order_id = o.order_id
    WITH INSERT UPDATE DELETE
  ]
}
FROM orders o
WITH INSERT UPDATE DELETE;

-- Dùng như JSON document
SELECT json_value(data, '$._id') FROM order_dv WHERE json_value(data,'$.status')='ACTIVE';
```

## 3. SQL FIREWALL (23ai)

```sql
-- Capture và enforce allowed SQL
EXEC DBMS_SQL_FIREWALL.ENABLE;

-- Bắt đầu capture cho user
EXEC DBMS_SQL_FIREWALL.CREATE_CAPTURE(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.ENABLE_CAPTURE(username => 'APP_USER');

-- Sau 1-2 tuần capture production SQL:
EXEC DBMS_SQL_FIREWALL.STOP_CAPTURE(username => 'APP_USER');
EXEC DBMS_SQL_FIREWALL.CREATE_ALLOW_LIST(username => 'APP_USER');

-- Enable enforcement
EXEC DBMS_SQL_FIREWALL.ENABLE_ALLOW_LIST(
  username => 'APP_USER',
  enforce  => DBMS_SQL_FIREWALL.ENFORCE_SQL,
  block    => TRUE);

-- Xem violations
SELECT username, sql_text, fire_time, violation_type
FROM dba_sql_firewall_violations
ORDER BY fire_time DESC;
```

## 4. TRUE CACHE (23ai/26ai)

```sql
-- True Cache: read-only in-memory cache gần application tier

-- Bước 1: Enable trên Primary DB
ALTER SYSTEM SET enable_true_cache = TRUE SCOPE=SPFILE;

-- Bước 2: Setup True Cache instance (separate server)
-- true_cache.init.ora:
-- db_name=ORCL
-- enable_true_cache=TRUE
-- db_cache_size=8G
-- true_cache_target=PRIMARY_DB_SERVICE

-- Bước 3: Verify
SELECT * FROM v$true_cache_config;
SELECT * FROM v$true_cache_stats;
```

---

# SK01-13 · Uninstall Oracle Database

## 1. UNINSTALL CHECKLIST

```bash
#!/bin/bash
# uninstall_oracle.sh — Complete Oracle uninstall

ORACLE_SID=${1:-ORCL}
ORACLE_HOME=${2:-/u01/app/oracle/product/19.3.0/dbhome_1}

echo "=== Oracle Uninstall: $ORACLE_SID ==="

# Step 1: Drop database
echo "[1] Dropping database $ORACLE_SID..."
$ORACLE_HOME/bin/dbca -silent \
  -deleteDatabase \
  -sourceDB $ORACLE_SID \
  -sysDBAUserName sys \
  -sysDBAPassword "Oracle_2026!"

# Step 2: Stop listener
echo "[2] Stopping listener..."
$ORACLE_HOME/bin/lsnrctl stop

# Step 3: Deinstall Oracle Home
echo "[3] Deinstalling Oracle Home..."
$ORACLE_HOME/deinstall/deinstall -silent

# Step 4: Deinstall Grid Home (nếu có)
GRID_HOME=/u01/app/grid/19.3.0
if [ -d "$GRID_HOME/deinstall" ]; then
  echo "[4] Deinstalling Grid Home..."
  $GRID_HOME/deinstall/deinstall -silent
fi

# Step 5: Manual cleanup
echo "[5] Manual cleanup..."
rm -rf /u01/app/oracle
rm -rf /u01/app/grid
rm -rf /u01/oradata
rm -rf /u01/fra
rm -rf /u01/arch
rm -f  /etc/oraInst.loc
rm -f  /etc/oratab

# Step 6: Remove users
echo "[6] Removing users..."
userdel -r oracle 2>/dev/null
userdel -r grid   2>/dev/null
groupdel asmadmin 2>/dev/null
groupdel asmdba   2>/dev/null
groupdel dba      2>/dev/null
groupdel oinstall 2>/dev/null

# Step 7: Remove OS settings
echo "[7] Cleaning OS settings..."
sed -i '/^#.*Oracle/d; /^oracle /d; /^grid /d' /etc/security/limits.conf
sed -i '/fs.aio-max-nr\|kernel.sem\|kernel.shm/d' /etc/sysctl.conf
sysctl -p

# Step 8: ASM disk cleanup
echo "[8] Cleaning ASM labels..."
if command -v oracleasm &>/dev/null; then
  for disk in $(oracleasm listdisks); do
    oracleasm deletedisk $disk
  done
fi

echo "=== Uninstall Complete ==="
```

---

# SK01-14 · Migration Validation & Cutover Plan

## 1. PRE-CUTOVER VALIDATION

```bash
#!/bin/bash
# validate_migration.sh — Validate source vs target

SOURCE_CONN="sys/pass@SOURCE"
TARGET_CONN="sys/pass@TARGET"

echo "=== MIGRATION VALIDATION REPORT ==="
echo "Date: $(date)"
echo ""

# 1. Row counts comparison
echo "[1] Row Count Comparison:"
sqlplus -S $SOURCE_CONN << 'EOF'
SET HEADING OFF FEEDBACK OFF LINESIZE 200
SELECT 'SOURCE', owner, table_name, num_rows
FROM dba_tables
WHERE owner IN ('SCOTT','HR','APP')
ORDER BY owner, table_name;
EXIT;
EOF

sqlplus -S $TARGET_CONN << 'EOF'
SET HEADING OFF FEEDBACK OFF LINESIZE 200
SELECT 'TARGET', owner, table_name, num_rows
FROM dba_tables
WHERE owner IN ('SCOTT','HR','APP')
ORDER BY owner, table_name;
EXIT;
EOF

# 2. Object counts
sqlplus -S $TARGET_CONN << 'EOF'
SET HEADING ON LINESIZE 200 PAGESIZE 50
SELECT owner, object_type, COUNT(*) cnt,
       SUM(CASE WHEN status='INVALID' THEN 1 ELSE 0 END) invalid_cnt
FROM dba_objects
WHERE owner IN ('SCOTT','HR','APP')
GROUP BY owner, object_type
ORDER BY owner, object_type;
EXIT;
EOF

# 3. Data checksum (sample verification)
echo "[3] Checksum Verification (sample tables):"
for table in SCOTT.ORDERS SCOTT.CUSTOMERS HR.EMPLOYEES; do
  src_sum=$(sqlplus -S $SOURCE_CONN << EOF
SET HEADING OFF FEEDBACK OFF
SELECT TO_CHAR(SUM(DBMS_SQLHASH.GETHASH(
  'SELECT * FROM $table ORDER BY 1',3))) FROM dual;
EXIT;
EOF
)
  tgt_sum=$(sqlplus -S $TARGET_CONN << EOF
SET HEADING OFF FEEDBACK OFF
SELECT TO_CHAR(SUM(DBMS_SQLHASH.GETHASH(
  'SELECT * FROM $table ORDER BY 1',3))) FROM dual;
EXIT;
EOF
)
  if [ "$src_sum" = "$tgt_sum" ]; then
    echo "  ✅ $table: MATCH"
  else
    echo "  ❌ $table: MISMATCH (src=$src_sum, tgt=$tgt_sum)"
  fi
done
```

## 2. CUTOVER RUNBOOK

```markdown
## CUTOVER RUNBOOK — Oracle Migration

### T-30 phút (Chuẩn bị)
- [ ] Thông báo teams: DBA, App, Network, Management
- [ ] Đảm bảo đội backup sẵn sàng rollback
- [ ] Verify TARGET DB healthy: srvctl status database
- [ ] Final validation: row counts match

### T-15 phút (Pre-cutover)
- [ ] Suspend scheduled jobs trên SOURCE
- [ ] Stop batch processing trên SOURCE
- [ ] Kiểm tra active sessions: v$session WHERE type='USER'

### T-0 (Cutover)
1. Stop application servers (hoặc switch connection pool)
2. Verify no active transactions:
   SELECT COUNT(*) FROM v$transaction;  -- Phải = 0
3. Final sync GoldenGate (nếu dùng):
   ggsci> LAG REPLICAT ZDM_REP  -- Phải = 00:00:00
4. Perform final validation script
5. Update connection strings → TARGET
6. Start/restart application servers
7. Smoke test: login, basic operations
8. Monitor error logs 15 phút đầu

### T+15 phút (Post-cutover)
- [ ] Confirm application healthy
- [ ] Monitor TARGET DB performance
- [ ] Update monitoring targets
- [ ] Decommission GoldenGate (nếu dùng)
- [ ] Update DNS/SCAN entries

### Rollback Plan (nếu fail)
1. Stop application
2. Repoint application → SOURCE
3. Restart application
4. Investigate failure
5. Estimate new cutover window
Rollback thời gian: < 10 phút

### Go/No-Go Decision
- ✅ GO: Tất cả validation PASS, lag = 0
- ❌ NO-GO: Bất kỳ validation FAIL, lag > 30s
```

---

**Tài liệu tham khảo — SK01-08 đến SK01-14:**
- Oracle GoldenGate Documentation 19c+
- Oracle SQL Loader User's Guide 19c
- Oracle Database External Tables Guide
- Oracle Multitenant Administrator's Guide 19c
- Oracle Database New Features Guide 23ai/26ai
- MOS Note 2876506.1 (Oracle 23ai New Features)
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
