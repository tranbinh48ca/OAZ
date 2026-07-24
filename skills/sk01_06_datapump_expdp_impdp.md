---
name: oracle-datapump-expdp-impdp
description: >
  Oracle Data Pump (expdp/impdp) toàn diện cho migration và backup.
  Kích hoạt khi hỏi về: DataPump Oracle, expdp, impdp,
  export database Oracle, import database Oracle,
  expdp full export, expdp schema export, expdp table export,
  impdp remap schema, impdp remap tablespace, network_link impdp,
  parallel DataPump, DataPump compression, DataPump encryption,
  DataPump exclude include filter, DataPump restart attach,
  DataPump status monitor, DataPump performance tuning,
  Oracle directory DataPump, dumpfile pattern %U,
  DataPump logfile, DataPump access_parameters,
  DataPump transportable tablespace, expdp flashback_time,
  expdp query filter, impdp table_exists_action.
---

# SK01-06 · Oracle Data Pump: expdp & impdp

**Phạm vi:** Oracle 11g → 26ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. SETUP DIRECTORY

```sql
-- Tạo OS directory trước
-- mkdir -p /u01/datapump

-- Tạo Oracle Directory object
CREATE OR REPLACE DIRECTORY DATA_PUMP_DIR AS '/u01/datapump';
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO system;
GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR TO app_user;

-- Verify directories
SELECT directory_name, directory_path FROM dba_directories
ORDER BY directory_name;

-- Default directory (không cần chỉ định nếu dùng DATA_PUMP_DIR)
SELECT * FROM dba_directories WHERE directory_name = 'DATA_PUMP_DIR';
-- Nếu không tồn tại sẽ dùng /u01/app/oracle/admin/ORCL/dpdump/

-- Kiểm tra permissions trên OS
ls -la /u01/datapump
# oracle:oinstall với 775
```

---

## 2. EXPORT (expdp)

### 2.1 Full Database Export

```bash
# ── Full export (toàn bộ DB) ─────────────────────────────
expdp system/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_${ORACLE_SID}_$(date +%Y%m%d)_%U.dmp \
  logfile=full_export_$(date +%Y%m%d).log \
  parallel=4 \
  compression=ALL \
  exclude=STATISTICS \
  cluster=N

# Với network_link (không tạo file, export qua network)
expdp system/"Oracle_2026!"@TARGET \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_via_net.dmp \
  network_link=SOURCE_LINK \
  parallel=4

# Full export với flashback (consistent snapshot)
expdp system/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_flashback_%U.dmp \
  flashback_time="TO_TIMESTAMP('2026-01-15 02:00:00','YYYY-MM-DD HH24:MI:SS')" \
  parallel=4
```

### 2.2 Schema Export

```bash
# ── Schema export ────────────────────────────────────────
expdp system/"Oracle_2026!" \
  schemas=SCOTT,HR,SALES,APP_USER \
  directory=DATA_PUMP_DIR \
  dumpfile=schemas_$(date +%Y%m%d)_%U.dmp \
  logfile=schemas_export_$(date +%Y%m%d).log \
  parallel=4 \
  compression=ALL \
  exclude=STATISTICS,GRANT \
  cluster=N

# Schema export với exclusions (không export sensitive data)
expdp system/"Oracle_2026!" \
  schemas=APP_USER \
  directory=DATA_PUMP_DIR \
  dumpfile=app_user.dmp \
  exclude=TABLE:"IN('AUDIT_LOG','SESSION_LOG')" \
  exclude=SEQUENCE:"LIKE 'TMP%'" \
  logfile=app_user_export.log
```

### 2.3 Table Export với Filter

```bash
# ── Table export ─────────────────────────────────────────
expdp scott/"Tiger_2026!" \
  tables=SCOTT.ORDERS,SCOTT.ORDER_ITEMS,SCOTT.CUSTOMERS \
  directory=DATA_PUMP_DIR \
  dumpfile=tables_$(date +%Y%m%d).dmp \
  logfile=tables_export.log

# Table export với WHERE clause
expdp scott/"Tiger_2026!" \
  tables=ORDERS \
  query=ORDERS:'"WHERE order_date >= DATE '"'"'2025-01-01'"'"'"' \
  directory=DATA_PUMP_DIR \
  dumpfile=orders_2025.dmp

# Multiple tables với different queries
expdp system/"Oracle_2026!" \
  directory=DATA_PUMP_DIR \
  dumpfile=filtered.dmp \
  tables=SCOTT.ORDERS,SCOTT.PRODUCTS \
  'query=SCOTT.ORDERS:"WHERE status='"'"'COMPLETED'"'"'",SCOTT.PRODUCTS:"WHERE active=1"'
```

### 2.4 Export Options Quan Trọng

```bash
# Compression options:
# ALL         = metadata + data (tốt nhất, cần Advanced Compression)
# DATA_ONLY   = chỉ data (không cần license)
# METADATA_ONLY = chỉ DDL/structure
# NONE        = không nén (default)

# Content options:
# ALL          = DDL + DML (default)
# DATA_ONLY    = chỉ data, không DDL
# METADATA_ONLY = chỉ DDL, không data

expdp system/"Oracle_2026!" \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=scott_metadata.dmp \
  content=METADATA_ONLY \     # Chỉ lấy structure
  logfile=metadata_only.log

# Encryption (cần Oracle Advanced Security hoặc 12c+)
expdp system/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=encrypted_full.dmp \
  encryption=ALL \
  encryption_password="EncryptPass_2026!" \
  encryption_algorithm=AES256

# Versioning (export cho DB cũ hơn)
expdp system/"Oracle_2026!"@19C_DB \
  schemas=APP \
  directory=DATA_PUMP_DIR \
  dumpfile=app_for_12c.dmp \
  version=12.2.0.1     # Export compatible với 12c

# Nologging (tăng tốc import)
expdp system/"Oracle_2026!" \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=scott.dmp \
  cluster=N \
  parallel=8 \
  metrics=Y    # Log performance metrics
```

---

## 3. IMPORT (impdp)

### 3.1 Full Database Import

```bash
# ── Full import (tạo mới toàn bộ từ dump) ───────────────
impdp system/"Oracle_2026!"@TARGET \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_ORCL_20260101_%U.dmp \
  logfile=full_import_$(date +%Y%m%d).log \
  parallel=4 \
  cluster=N

# Full import với remap (đổi tablespace)
impdp system/"Oracle_2026!"@TARGET \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_source.dmp \
  remap_tablespace=OLD_TBS:NEW_TBS,OLD_INDX:NEW_INDX \
  exclude=STATISTICS \
  parallel=4 \
  logfile=full_import_remap.log
```

### 3.2 Schema Import với Remap

```bash
# ── Remap schema (đổi tên schema) ───────────────────────
impdp system/"Oracle_2026!"@TARGET \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=schemas_20260101_%U.dmp \
  remap_schema=SCOTT:SCOTT_NEW \
  remap_tablespace=USERS:APP_DATA \
  logfile=schema_import.log \
  parallel=4

# Import schema với table_exists_action
# SKIP    = bỏ qua nếu table tồn tại (default)
# REPLACE = drop và recreate
# TRUNCATE= truncate trước khi import
# APPEND  = thêm dữ liệu vào table hiện có
impdp system/"Oracle_2026!" \
  schemas=APP_USER \
  directory=DATA_PUMP_DIR \
  dumpfile=app_user.dmp \
  table_exists_action=REPLACE \
  logfile=app_import.log
```

### 3.3 Network Link Import (Không cần file)

```bash
# Import trực tiếp từ source DB qua DB Link
# Tạo DB Link trước:
# CREATE DATABASE LINK SOURCE_LINK
#   CONNECT TO system IDENTIFIED BY "Oracle_2026!"
#   USING 'SOURCE_DB';

impdp system/"Oracle_2026!"@TARGET \
  schemas=SCOTT,HR \
  directory=DATA_PUMP_DIR \
  network_link=SOURCE_LINK \   # Không cần dumpfile
  remap_tablespace=USERS:APP_DATA \
  logfile=network_import.log \
  parallel=4 \
  cluster=N

# Full DB migration qua network
impdp system/"Oracle_2026!"@TARGET \
  full=Y \
  directory=DATA_PUMP_DIR \
  network_link=SOURCE_LINK \
  exclude=STATISTICS \
  parallel=8 \
  logfile=full_network_import.log
```

### 3.4 Table-Level Import Options

```bash
# Import chỉ một số tables từ full export
impdp system/"Oracle_2026!" \
  tables=SCOTT.ORDERS,SCOTT.CUSTOMERS \
  directory=DATA_PUMP_DIR \
  dumpfile=full_source.dmp \    # Đọc từ full export
  logfile=tables_import.log

# Import với remap datafile (thay đổi path)
impdp system/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full.dmp \
  remap_datafile='/old/path/data01.dbf':'/new/path/data01.dbf' \
  logfile=import_remap_df.log

# Transform: remove storage clauses (cho clean import)
impdp system/"Oracle_2026!" \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=scott.dmp \
  transform=SEGMENT_ATTRIBUTES:N \  # Không import storage clauses
  transform=STORAGE:N \              # Không import STORAGE clause
  logfile=scott_transform.log

# SQLFILE: chỉ generate DDL, không import
impdp system/"Oracle_2026!" \
  schemas=SCOTT \
  directory=DATA_PUMP_DIR \
  dumpfile=scott.dmp \
  sqlfile=scott_ddl.sql \   # Chỉ xuất DDL ra file
  logfile=sqlfile.log
```

---

## 4. MONITOR VÀ MANAGE JOBS

```bash
# ── Monitor running job ──────────────────────────────────
# Trong cửa sổ khác, attach vào job đang chạy:
expdp system/"Oracle_2026!" attach=SYS_EXPORT_SCHEMA_01

# Trong Export prompt:
Export> status        # Xem trạng thái
Export> status -interval=30  # Auto refresh 30s
Export> parallel=8    # Tăng parallel
Export> continue_client  # Disconnect client, job tiếp tục
Export> stop_job      # Dừng job (có thể resume)
Export> kill_job      # Kill hoàn toàn (không resume)
Export> exit          # Exit prompt (job tiếp tục background)

# ── Xem jobs từ SQL ──────────────────────────────────────
SELECT owner_name, job_name, operation, job_mode,
       state, degree, attached_sessions
FROM dba_datapump_jobs
WHERE state != 'NOT RUNNING';

-- Details
SELECT sid, serial#, context, sofar, totalwork,
       ROUND(sofar/NULLIF(totalwork,0)*100, 1) pct_done,
       message
FROM v$session_longops
WHERE opname LIKE 'KUPC%' AND totalwork > 0
ORDER BY pct_done DESC;

# ── Resume stopped job ────────────────────────────────────
impdp system/"Oracle_2026!" attach=SYS_IMPORT_FULL_01
Import> start_job
Import> status
```

---

## 5. PERFORMANCE TUNING DATA PUMP

```bash
# 1. PARALLEL — tăng throughput
# Rule: parallel = min(CPU_count, number_of_dump_files)
expdp system/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_%U.dmp \   # %U tạo multiple files
  parallel=8 \             # 8 workers, 8 files
  logfile=perf.log

# 2. DIRECT PATH read (tăng tốc reads lớn)
expdp system/"Oracle_2026!" \
  schemas=DWH \
  access_parameters='SKIP_UNUSABLE_INDEXES=y' \
  directory=DATA_PUMP_DIR \
  dumpfile=dwh.dmp

# 3. Compression giảm I/O
expdp system/"Oracle_2026!" full=Y \
  compression=DATA_ONLY \   # Không cần Advanced Compression license
  directory=DATA_PUMP_DIR \
  dumpfile=compressed_%U.dmp \
  parallel=8

# 4. Exclude heavy objects
expdp system/"Oracle_2026!" full=Y \
  exclude=STATISTICS \          # Gather stats sau khi import
  exclude=CLUSTER \             # Không export IOT clusters
  exclude=TRIGGER:"LIKE 'AUD%'" \ # Exclude audit triggers
  directory=DATA_PUMP_DIR \
  dumpfile=optimized_%U.dmp

# 5. Split export (export nhiều lần, combine khi import)
expdp system/"Oracle_2026!" \
  schemas=APP \
  dumpfile=app_part1.dmp \
  include=TABLE:"IN('ORDERS','ORDER_ITEMS')" \
  directory=DATA_PUMP_DIR

expdp system/"Oracle_2026!" \
  schemas=APP \
  dumpfile=app_part2.dmp \
  include=TABLE:"NOT IN('ORDERS','ORDER_ITEMS')" \
  directory=DATA_PUMP_DIR

# Import cả 2:
impdp system/"Oracle_2026!" \
  directory=DATA_PUMP_DIR \
  dumpfile=app_part1.dmp,app_part2.dmp \
  schemas=APP
```

---

## 6. DATAPUMP CHO CDB/PDB (12c+)

```bash
# Export từ CDB (common user)
expdp c##dba/"Oracle_2026!"@CDB_SERVICE \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=cdb_full.dmp \
  parallel=4

# Export từ PDB cụ thể
expdp system/"Oracle_2026!"@ORCLPDB \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=pdb1_full.dmp

# Export tất cả PDBs (19c+)
expdp c##dba/"Oracle_2026!" \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=all_pdbs_%U.dmp \
  parallel=8

# Import vào PDB khác
impdp system/"Oracle_2026!"@TARGET_PDB \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=pdb1_full.dmp \
  remap_tablespace=OLD:NEW \
  logfile=pdb_import.log
```

---

## 7. SCRIPTS THỰC TẾ

```bash
#!/bin/bash
# datapump_migration.sh — Script migration production
# Usage: ./datapump_migration.sh SOURCE_SID TARGET_SID SCHEMAS

SOURCE_SID=$1
TARGET_SID=$2
SCHEMAS=$3
DATE=$(date +%Y%m%d_%H%M)
DUMP_DIR=/u01/datapump
DUMP_FILE="${SOURCE_SID}_${DATE}_%U.dmp"
LOG_PREFIX="${DUMP_DIR}/${SOURCE_SID}_${DATE}"

echo "=== Starting Migration: $SOURCE_SID → $TARGET_SID ==="
echo "Schemas: $SCHEMAS"

# Step 1: Export từ source
echo "[1] Exporting..."
expdp system/"$SOURCE_PASS"@$SOURCE_SID \
  schemas=$SCHEMAS \
  directory=DATA_PUMP_DIR \
  dumpfile=$DUMP_FILE \
  logfile=export_${DATE}.log \
  parallel=$(nproc) \
  compression=ALL \
  exclude=STATISTICS \
  cluster=N

if [ $? -ne 0 ]; then
  echo "Export FAILED! Check $DUMP_DIR/export_${DATE}.log"
  exit 1
fi

# Step 2: Import vào target
echo "[2] Importing..."
impdp system/"$TARGET_PASS"@$TARGET_SID \
  directory=DATA_PUMP_DIR \
  dumpfile=$DUMP_FILE \
  logfile=import_${DATE}.log \
  remap_tablespace=USERS:APP_DATA \
  parallel=$(nproc) \
  exclude=STATISTICS \
  cluster=N

if [ $? -ne 0 ]; then
  echo "Import FAILED! Check $DUMP_DIR/import_${DATE}.log"
  exit 2
fi

# Step 3: Gather statistics trên target
echo "[3] Gathering statistics..."
sqlplus system/"$TARGET_PASS"@$TARGET_SID << 'EOF'
BEGIN
  FOR s IN (SELECT DISTINCT schema_name FROM dba_datapump_jobs
             WHERE 1=2) LOOP
    DBMS_STATS.GATHER_SCHEMA_STATS(s.schema_name,
      options=>'GATHER', degree=>4, cascade=>TRUE);
  END LOOP;
END;
/
EXIT;
EOF

echo "=== Migration COMPLETED ==="
echo "Export log: $DUMP_DIR/export_${DATE}.log"
echo "Import log: $DUMP_DIR/import_${DATE}.log"
```

---

**Tài liệu tham khảo:**
- Oracle Database Utilities 19c: Data Pump Export and Import
- MOS Note 552424.1 (DataPump Troubleshooting)
- docs.oracle.com/en/database/oracle/oracle-database/19/sutil/
- www.tranvanbinh.vn
