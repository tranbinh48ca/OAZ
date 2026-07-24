---
name: oracle-opatch-patching
description: >
  Oracle Patching với OPatch và OPatchAuto toàn diện.
  Kích hoạt khi hỏi về: OPatch Oracle, patch Oracle, CPU patch Oracle,
  Release Update RU Oracle, opatch apply, opatch rollback,
  opatch lsinventory, opatch prereq, conflict check OPatch,
  OPatchAuto RAC, rolling patch Oracle, datapatch Oracle,
  catbundle.sql Oracle, patch bundle Oracle, one-off patch,
  PSU patch, GI patch, DB patch, combined patch Oracle,
  out-of-place patching, minimum downtime patching Oracle,
  opatchauto apply rollback, patch history Oracle, lspatches.
---

# SK01-04 · Oracle Patching: OPatch & OPatchAuto

**Phạm vi:** Oracle 11g R2 → 26ai | Single Instance & RAC  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ORACLE PATCH TAXONOMY

```
Patch Types (từ mới nhất đến cũ):
┌─────────────────────────────────────────────────────┐
│ Release Update (RU)     — Quarterly, cumulative     │
│   Example: 19.21.0.0.0 = Jan 2024 RU               │
│ Release Update Revision (RUR) — Security-only subset│
│ One-off Patch            — Fix cho bug cụ thể       │
│ Database Release Update  — Database-only RU         │
│ GI Release Update        — Grid-only RU             │
│ Combined Patch           — GI + DB cùng patch number│
└─────────────────────────────────────────────────────┘

Patch Strategy cho Production:
- Apply RU mỗi 6-12 tháng (chọn N-1 version, ổn định hơn)
- Apply Security-only RU Revision hàng quý nếu cần compliance
- One-off patch khi có bug cụ thể ảnh hưởng

MOS: https://updates.oracle.com
Search: "Release Update 19c" → Latest = 19.24+ RU
```

---

## 2. OPATCH PRE-WORK

```bash
# ── 1. Update OPatch trước (LUÔN LUÔN làm trước) ────────
# Download OPatch mới nhất từ MOS (patch 6880880)
$ORACLE_HOME/OPatch/opatch version
# Nếu version cũ hơn yêu cầu của patch:
cd $ORACLE_HOME
mv OPatch OPatch_$(date +%Y%m%d)_bak
unzip -q /opt/patches/p6880880_190000_Linux-x86-64.zip
$ORACLE_HOME/OPatch/opatch version  # Verify mới

# ── 2. Kiểm tra inventory ────────────────────────────────
$ORACLE_HOME/OPatch/opatch lsinventory
$ORACLE_HOME/OPatch/opatch lspatches      # Compact listing

# ── 3. Download và extract patch ────────────────────────
mkdir -p /opt/patches
cd /opt/patches
unzip -q p35943157_190000_Linux-x86-64.zip
ls /opt/patches/35943157/

# ── 4. Conflict check (QUAN TRỌNG) ──────────────────────
cd /opt/patches/35943157
$ORACLE_HOME/OPatch/opatch prereq \
  CheckConflictAgainstOHWithDetail \
  -ph ./

# Nếu conflict → xem "Conflict Patches" section trong output
# Cần apply bundle patch bao gồm cả patches đó

# ── 5. Apply prerequisite check ─────────────────────────
$ORACLE_HOME/OPatch/opatch prereq \
  CheckSystemSpace \
  -ph ./
# Cần >= 3GB free trong ORACLE_HOME cho mỗi patch

# ── 6. Backup spfile ─────────────────────────────────────
sqlplus -S / as sysdba << 'EOF'
CREATE PFILE='/tmp/init_pre_patch_$(date +%Y%m%d).ora' FROM SPFILE;
EXIT;
EOF

# ── 7. RMAN backup (nếu có thời gian) ───────────────────
# rman target / << 'EOF'
# BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG DELETE INPUT;
# EOF
```

---

## 3. OPATCH — SINGLE INSTANCE PATCH

```bash
# ── Step 1: Shutdown DB và Listener ─────────────────────
sqlplus / as sysdba << 'EOF'
SHUTDOWN IMMEDIATE;
EOF
lsnrctl stop

# ── Step 2: Apply patch ──────────────────────────────────
cd /opt/patches/35943157
$ORACLE_HOME/OPatch/opatch apply -silent

# Monitor log:
# /u01/app/oracle/cfgtoollogs/opatch/opatch<timestamp>.log

# ── Step 3: Startup + datapatch ─────────────────────────
lsnrctl start
sqlplus / as sysdba << 'EOF'
STARTUP;
EXIT;
EOF

# datapatch: apply SQL changes vào database (bắt buộc từ 12.2+)
cd $ORACLE_HOME/OPatch
./datapatch -verbose 2>&1 | tee /tmp/datapatch_$(date +%Y%m%d).log

# Verify datapatch thành công
sqlplus -S / as sysdba << 'EOF'
SELECT patch_id, patch_uid, version, action, status, action_time,
       description
FROM sys.registry\$history
ORDER BY action_time DESC
FETCH FIRST 5 ROWS ONLY;

-- Status phải là SUCCESS
SELECT * FROM dba_registry_sqlpatch ORDER BY action_time DESC
FETCH FIRST 5 ROWS ONLY;
EOF

# ── Step 4: Verify patch applied ─────────────────────────
$ORACLE_HOME/OPatch/opatch lspatches | grep 35943157
```

---

## 4. OPATCHAUTO — RAC ROLLING PATCH

```bash
# OPatchAuto patches Grid + DB đồng thời, rolling từng node
# PHẢI chạy với root
# PHẢI có password được setup trong wallet (hoặc dùng -sshkeys)

# ── Analyze (xem trước khi thực hiện) ───────────────────
$ORACLE_HOME/OPatch/opatchauto apply \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME \
  -analyze

# Output: "opatchauto succeeded" nếu OK

# ── Apply Rolling (node-by-node) ─────────────────────────
# Workflow tự động:
# 1. Stop DB instances trên node1 (workload → node2)
# 2. Patch GI + DB Home trên node1
# 3. Start instances trên node1
# 4. Verify node1 healthy
# 5. Repeat cho node2

$ORACLE_HOME/OPatch/opatchauto apply \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME

# Monitor:
tail -f /u01/app/oracle/cfgtoollogs/opatchautodb/opatchauto_*.log

# ── Non-Rolling (cần downtime, đơn giản hơn) ─────────────
$ORACLE_HOME/OPatch/opatchauto apply \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME \
  -nonrolling

# ── Rollback ─────────────────────────────────────────────
$ORACLE_HOME/OPatch/opatchauto rollback \
  /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME

# ── Verify sau rolling patch ─────────────────────────────
# Kiểm tra cả 2 nodes:
crsctl stat res -t
srvctl status database -d ORCL

# Chạy datapatch 1 lần (từ 1 node, áp dụng cho cả RAC)
$ORACLE_HOME/OPatch/datapatch -verbose

# Verify từ SQL
sqlplus / as sysdba << 'EOF'
SELECT inst_id, patch_id, status
FROM gv$session_patch_info
ORDER BY inst_id;

SELECT patch_id, action, status FROM dba_registry_sqlpatch
ORDER BY action_time DESC FETCH FIRST 5 ROWS ONLY;
EOF
```

---

## 5. OUT-OF-PLACE PATCHING (19c+)

```bash
# Tạo ORACLE_HOME mới với patch đã apply
# Không ảnh hưởng running instances cho đến khi switch

# Bước 1: Tạo mới ORACLE_HOME
NEW_OH=/u01/app/oracle/product/19.3.0/dbhome_2
mkdir -p $NEW_OH
cd $NEW_OH
unzip -q /opt/install/LINUX.X64_193000_db_home.zip

# Bước 2: Install software vào new home
su - oracle << 'EOF'
/u01/app/oracle/product/19.3.0/dbhome_2/runInstaller \
  -silent -responseFile /tmp/db_install.rsp \
  -ORACLE_HOME=/u01/app/oracle/product/19.3.0/dbhome_2 \
  -waitforcompletion
EOF

# Bước 3: Apply patch vào new home
cd /opt/patches/35943157
ORACLE_HOME=$NEW_OH $NEW_OH/OPatch/opatch apply -silent

# Bước 4: Switch database ke new home (với srvctl)
srvctl stop database -d ORCL -stopoption immediate

srvctl modify database -d ORCL \
  -oraclehome $NEW_OH

srvctl start database -d ORCL

# Bước 5: datapatch
$NEW_OH/OPatch/datapatch -verbose

# Bước 6: Update oratab
sed -i "s|ORCL:$OLD_OH|ORCL:$NEW_OH|" /etc/oratab
```

---

## 6. CDB/PDB PATCHING (Multitenant)

```sql
-- datapatch với CDB — chạy một lần, apply cho tất cả PDBs
-- Nhưng có thể apply riêng cho từng PDB:

-- Kiểm tra patch status per container
SELECT con_id, patch_id, version, status, action_time
FROM cdb_registry_sqlpatch
ORDER BY con_id, action_time DESC;

-- Nếu PDB ở READ ONLY (Active DataGuard) không thể patch
-- PDB phải OPEN READ WRITE để datapatch chạy

-- Force datapatch cho PDB cụ thể
$ORACLE_HOME/OPatch/datapatch \
  -pdbs ORCLPDB1,ORCLPDB2 \
  -verbose
```

---

## 7. PATCH TROUBLESHOOTING

```bash
# opatch apply fail → xem log
find $ORACLE_HOME -name "opatch*.log" -newer /tmp/ref | head -5
# /u01/app/oracle/cfgtoollogs/opatch/opatch<timestamp>.log

# Lỗi "inventory locked"
rm -f $ORACLE_HOME/.patch_storage/*/in_progress
$ORACLE_HOME/OPatch/opatch util cleanup -silent

# Lỗi "patch already applied"
$ORACLE_HOME/OPatch/opatch lspatches | grep <patch_id>
# Nếu đã có → không cần apply lại

# datapatch fail → xem log
find $ORACLE_HOME -name "datapatch_*.log" | xargs tail -50

# datapatch lỗi "ORA-04063: package body has errors"
sqlplus / as sysdba << 'EOF'
@$ORACLE_HOME/rdbms/admin/utlrp.sql
EOF
$ORACLE_HOME/OPatch/datapatch -verbose  # Retry

# opatchauto fail mid-way → rollback partial
$ORACLE_HOME/OPatch/opatchauto rollback \
  /opt/patches/<patch_id> \
  -oh $GRID_HOME,$ORACLE_HOME \
  -recover  # Recover mode
```

---

## 8. PATCH MANAGEMENT BEST PRACTICES

```sql
-- Lịch sử patches đã apply (từ SQL)
SELECT patch_id, patch_uid,
       TO_CHAR(action_time,'YYYY-MM-DD HH24:MI') applied_time,
       action, namespace, version, description
FROM dba_registry_history
ORDER BY action_time DESC;

-- Patches hiện đang apply
SELECT patch_id, version, action, status
FROM dba_registry_sqlpatch
WHERE status = 'SUCCESS'
ORDER BY action_time DESC
FETCH FIRST 10 ROWS ONLY;
```

```bash
# Script kiểm tra patch version mỗi ngày
cat > /u01/scripts/check_patch_level.sh << 'SCRIPT'
#!/bin/bash
echo "=== Patch Level Report $(date) ==="
echo "ORACLE_HOME: $ORACLE_HOME"
echo ""
echo "--- Installed Patches ---"
$ORACLE_HOME/OPatch/opatch lspatches 2>/dev/null

echo ""
echo "--- DB Registry History ---"
sqlplus -S / as sysdba << 'EOF'
SET LINESIZE 150 PAGESIZE 30
SELECT patch_id, TO_CHAR(action_time,'YYYY-MM-DD') date_applied,
       action, status, description
FROM dba_registry_sqlpatch
WHERE status = 'SUCCESS'
ORDER BY action_time DESC
FETCH FIRST 5 ROWS ONLY;
EXIT;
EOF
SCRIPT
chmod +x /u01/scripts/check_patch_level.sh
```

---

**Tài liệu tham khảo:**
- My Oracle Support: support.oracle.com
- MOS Note 2001921.1 (Database 19c Patches)
- MOS Note 1931634.1 (Complete Checklist for Manual Patch Application)
- OPatch User's Guide: docs.oracle.com
- www.tranvanbinh.vn
