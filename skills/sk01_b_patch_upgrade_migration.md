---
name: oracle-patch-upgrade-migration
description: >
  Oracle Patching, Upgrading và Migration toàn diện.
  Kích hoạt khi hỏi về: patch Oracle, OPatch, OPatchAuto, CPU patch,
  RU release update Oracle, PSU patch Oracle, opatch lsinventory,
  opatch prereq conflict, rollback patch Oracle, rolling patch RAC,
  upgrade Oracle, DBUA upgrade, AutoUpgrade Oracle, catupgrd,
  nâng cấp Oracle 11g 12c 19c, pre-upgrade checks, pre-upgrade fixup,
  postupgrade Oracle, migration Oracle, DataPump migration, expdp impdp,
  RMAN duplicate migration, transportable tablespace TTS,
  SQL Loader sqlldr, GoldenGate migration, zero downtime migration,
  cross-platform migration Oracle, PDB migration unplug plug.
---

# SK01-B · Patching, Upgrading & Migration Oracle

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ORACLE PATCHING

### 1.1 OPatch — Single Patch

```bash
# ── Step 1: Chuẩn bị ──────────────────────────────────
# Kiểm tra OPatch version (phải đủ mới để apply patch)
$ORACLE_HOME/OPatch/opatch version
# Cập nhật OPatch nếu cần:
cd $ORACLE_HOME
mv OPatch OPatch_bak
unzip -q /opt/patches/p6880880_190000_Linux-x86-64.zip

# ── Step 2: Pre-checks ─────────────────────────────────
cd /opt/patches/35943157  # Thư mục patch
$ORACLE_HOME/OPatch/opatch prereq CheckConflictAgainstOHWithDetail \
  -ph ./
# Nếu conflict → cần apply bundle patch hoặc remove conflicting patch

# ── Step 3: Backup spfile (phòng ngừa) ────────────────
sqlplus / as sysdba << 'EOF'
CREATE PFILE='/tmp/initORCL_pre_patch.ora' FROM SPFILE;
EOF

# ── Step 4: Shutdown DB ───────────────────────────────
sqlplus / as sysdba << 'EOF'
SHUTDOWN IMMEDIATE;
EOF
lsnrctl stop

# ── Step 5: Apply patch ───────────────────────────────
cd /opt/patches/35943157
$ORACLE_HOME/OPatch/opatch apply -silent
# Với binary patches cần catbundle:
# $ORACLE_HOME/OPatch/opatch apply -silent -oh $ORACLE_HOME

# ── Step 6: Post-patch SQL scripts ───────────────────
lsnrctl start
sqlplus / as sysdba << 'EOF'
STARTUP;
@$ORACLE_HOME/rdbms/admin/catbundle.sql psu apply
@$ORACLE_HOME/rdbms/admin/utlrp.sql
SELECT patch_id, action, action_time FROM dba_registry_history
ORDER BY action_time DESC FETCH FIRST 5 ROWS ONLY;
EOF

# ── Verify ────────────────────────────────────────────
$ORACLE_HOME/OPatch/opatch lsinventory | grep "Patch "
$ORACLE_HOME/OPatch/opatch lspatches

# ── Rollback nếu cần ─────────────────────────────────
cd /opt/patches/35943157
$ORACLE_HOME/OPatch/opatch rollback -id 35943157 -silent
sqlplus / as sysdba << 'EOF'
STARTUP;
@$ORACLE_HOME/rdbms/admin/catbundle.sql psu rollback
@$ORACLE_HOME/rdbms/admin/utlrp.sql
EOF
```

### 1.2 OPatchAuto — RAC Rolling Patch (Zero Downtime)

```bash
# OPatchAuto patches Grid + DB đồng thời, rolling từng node

# Pre-check (bắt buộc)
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME \
  -analyze  # Chỉ phân tích, không apply

# Apply rolling (Node 1 patch trước, workload chuyển Node 2)
# Phải chạy với root!
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME \
  -nonrolling  # Bỏ flag này để enable rolling

# Monitor progress
tail -f /u01/app/grid/cfgtoollogs/opatchautodb/opatchauto*.log

# Rollback toàn bộ
$ORACLE_HOME/OPatch/opatchauto rollback /opt/patches/35943157 \
  -oh $GRID_HOME,$ORACLE_HOME

# Out-of-place patching (19c+) — tạo ORACLE_HOME mới
# Không ảnh hưởng Oracle Home cũ, rollback bằng cách switch home
$ORACLE_HOME/OPatch/opatchauto apply /opt/patches/35943157 \
  -oh $ORACLE_HOME \
  -outofplace
```

---

## 2. UPGRADING ORACLE DATABASE

### 2.1 AutoUpgrade (Recommended 19c+)

```bash
# AutoUpgrade tự động hoá toàn bộ upgrade process
# Supports: 11.2.0.4 → 19c → 21c

# ── Tạo config file ──────────────────────────────────
cat > /tmp/autoupgrade.cfg << 'EOF'
global.autoupg_log_dir=/u01/autoupgrade_logs

upg1.source_home=/u01/app/oracle/product/11.2.0/dbhome_1
upg1.target_home=/u01/app/oracle/product/19.3.0/dbhome_1
upg1.sid=ORCL
upg1.start_time=NOW
upg1.log_dir=/u01/autoupgrade_logs/ORCL
upg1.run_utluppkg=yes
upg1.upgrade_node=localhost
upg1.target_version=19
upg1.restoration=yes    # Enable flashback restore point
EOF

# ── Analyze mode (kiểm tra issues) ──────────────────
java -jar /u01/app/oracle/product/19.3.0/dbhome_1/rdbms/admin/autoupgrade.jar \
  -mode analyze \
  -config /tmp/autoupgrade.cfg

# Review report
cat /u01/autoupgrade_logs/cfgtoollogs/upgrade/auto/status/status.html

# ── Fixup mode (sửa issues tự động) ─────────────────
java -jar $NEW_ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode fixups \
  -config /tmp/autoupgrade.cfg

# ── Deploy mode (upgrade thực sự) ────────────────────
java -jar $NEW_ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode deploy \
  -config /tmp/autoupgrade.cfg

# Monitor trong khi đang chạy (interactive console)
java -jar $NEW_ORACLE_HOME/rdbms/admin/autoupgrade.jar \
  -mode deploy \
  -config /tmp/autoupgrade.cfg &

# Trong Java console (nếu chạy foreground):
# lsj      → list jobs
# status   → overall status
# status -job 1  → job detail
# resume -job 1  → resume paused job
```

### 2.2 Manual Upgrade (DBUA hoặc thủ công)

```bash
# Khi cần control hoàn toàn

# ── Pre-upgrade steps ──────────────────────────────
# Chạy pre-upgrade information tool từ NEW Oracle Home
$NEW_ORACLE_HOME/jdk/bin/java -jar \
  $NEW_ORACLE_HOME/rdbms/admin/preupgrade.jar FILE TEXT

# Review /u01/app/oracle/cfgtoollogs/ORCL/preupgrade/
cat /u01/app/oracle/cfgtoollogs/ORCL/preupgrade/preupgrade.log
cat /u01/app/oracle/cfgtoollogs/ORCL/preupgrade/preupgrade_fixups.sql

# Chạy pre-upgrade fixup script (với OLD Oracle Home)
sqlplus / as sysdba << 'EOF'
@/u01/app/oracle/cfgtoollogs/ORCL/preupgrade/preupgrade_fixups.sql
EOF

# Gather dictionary stats
sqlplus / as sysdba << 'EOF'
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;
EXEC DBMS_STATS.GATHER_FIXED_OBJECTS_STATS;
EOF

# ── Upgrade bằng DBUA (GUI) ───────────────────────
export ORACLE_HOME=$NEW_ORACLE_HOME
$NEW_ORACLE_HOME/bin/dbua

# ── Upgrade thủ công (advanced) ───────────────────
# Shutdown với OLD Oracle Home
export ORACLE_HOME=$OLD_ORACLE_HOME
sqlplus / as sysdba << 'EOF'
SHUTDOWN IMMEDIATE;
EOF

# Startup với NEW Oracle Home, UPGRADE mode
export ORACLE_HOME=$NEW_ORACLE_HOME
sqlplus / as sysdba << 'EOF'
STARTUP UPGRADE;
EOF

# Chạy catupgrd.sql (parallel upgrade, nhanh nhất)
$NEW_ORACLE_HOME/perl/bin/perl \
  $NEW_ORACLE_HOME/rdbms/admin/catctl.pl \
  -n 4 \              # 4 parallel processes
  -d $NEW_ORACLE_HOME/rdbms/admin \
  catupgrd.sql

# Post-upgrade
sqlplus / as sysdba << 'EOF'
@$ORACLE_HOME/rdbms/admin/catuppst.sql
@$ORACLE_HOME/rdbms/admin/utlrp.sql
SELECT comp_name, version, status FROM dba_registry WHERE status != 'VALID';
EOF

# Chạy post-upgrade fixup script
sqlplus / as sysdba << 'EOF'
@/u01/app/oracle/cfgtoollogs/ORCL/preupgrade/postupgrade_fixups.sql
EOF

# Update oratab
sed -i 's|ORCL:.*:N|ORCL:'$NEW_ORACLE_HOME':N|' /etc/oratab
```

---

## 3. MIGRATION

### 3.1 DataPump (expdp/impdp)

```bash
# ── Export toàn bộ schema ─────────────────────────
expdp system/pass@SOURCE \
  schemas=SCOTT,HR,SALES,APP_USER \
  directory=DATA_PUMP_DIR \
  dumpfile=migration_%U.dmp \   # %U = numbered files
  logfile=export.log \
  parallel=4 \
  compression=ALL \
  exclude=STATISTICS \
  cluster=N

# ── Export với network link (không tạo dump file) ──
impdp system/pass@TARGET \
  schemas=SCOTT,HR \
  network_link=SOURCE_LINK \  # DB link đến SOURCE
  logfile=import_network.log \
  parallel=4 \
  remap_schema=SCOTT:SCOTT_V2 \
  remap_tablespace=OLD_TBS:NEW_TBS

# ── Import ────────────────────────────────────────
impdp system/pass@TARGET \
  schemas=SCOTT,HR,SALES \
  directory=DATA_PUMP_DIR \
  dumpfile=migration_%U.dmp \
  logfile=import.log \
  parallel=4 \
  remap_tablespace=USERS:APP_DATA \
  transform=SEGMENT_ATTRIBUTES:N  # Không copy storage clauses

# ── Full database export/import ───────────────────
expdp system/pass@SOURCE \
  full=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=full_export_%U.dmp \
  logfile=full_export.log \
  parallel=8 \
  compression=ALL \
  exclude=STATISTICS,SCHEMA:"IN('SYS','SYSTEM')"

# ── Restart failed job ────────────────────────────
expdp system/pass attach=SYS_EXPORT_SCHEMA_01
Export> status
Export> continue_client
# Hoặc kill và restart:
Export> kill_job

# ── Table-level export ────────────────────────────
expdp scott/tiger \
  tables=ORDERS,ORDER_ITEMS \
  directory=DATA_PUMP_DIR \
  dumpfile=tables.dmp \
  query="ORDERS:\"WHERE order_date > DATE '2024-01-01'\""
```

### 3.2 RMAN Duplicate (Cross-Server Migration)

```bash
# ACTIVE DUPLICATE — không cần backup, stream từ source
rman target sys/pass@SOURCE auxiliary sys/pass@TARGET << 'EOF'
DUPLICATE TARGET DATABASE TO TARGET_DB
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT
      'SOURCE','TARGET',
      '/u01/oradata/SOURCE/','/u01/oradata/TARGET/'
    SET DB_UNIQUE_NAME='TARGET'
    SET LOG_ARCHIVE_DEST_1='LOCATION=/u01/arch'
    SET CONTROL_FILES='/u01/oradata/TARGET/control01.ctl'
    SET AUDIT_FILE_DEST='/u01/app/oracle/admin/TARGET/adump'
  LOGFILE
    GROUP 1 '/u01/oradata/TARGET/redo01.log' SIZE 500M,
    GROUP 2 '/u01/oradata/TARGET/redo02.log' SIZE 500M
  NOFILENAMECHECK;
EOF

# BACKUP-BASED DUPLICATE
rman target / catalog rman_cat/pass@CATALOG auxiliary sys/pass@TARGET << 'EOF'
DUPLICATE DATABASE TO TARGET_DB
  BACKUP LOCATION '/backup/rman'
  LOGFILE
    GROUP 1 '/u01/oradata/TARGET/redo01.log' SIZE 500M
  NOFILENAMECHECK
  UNTIL TIME "TO_DATE('2026-01-15','YYYY-MM-DD')";
EOF
```

### 3.3 Transportable Tablespace (TTS)

```bash
# Tốt cho: migrate tablespace lớn, cross-platform nếu cùng endian
# Cross-platform check:
SELECT platform_name, endian_format FROM v$transportable_platform
WHERE endian_format = (SELECT endian_format FROM v$database);

# Source DB:
sqlplus / as sysdba << 'EOF'
-- Check self-containment
EXEC DBMS_TTS.TRANSPORT_SET_CHECK('APP_DATA,APP_INDX', TRUE);
SELECT * FROM transport_set_violations;  -- Phải rỗng

-- Make READ ONLY
ALTER TABLESPACE APP_DATA READ ONLY;
ALTER TABLESPACE APP_INDX READ ONLY;
EOF

# Export metadata
expdp system/pass \
  transport_tablespaces=APP_DATA,APP_INDX \
  transport_full_check=Y \
  dumpfile=tts_meta.dmp \
  directory=DATA_PUMP_DIR

# Copy: metadata dump + tất cả datafiles sang target server

# Target DB:
impdp system/pass@TARGET \
  dumpfile=tts_meta.dmp \
  directory=DATA_PUMP_DIR \
  transport_datafiles='/u01/oradata/TARGET/app_data01.dbf',
                      '/u01/oradata/TARGET/app_indx01.dbf'

# Source: Make READ WRITE lại
sqlplus / as sysdba << 'EOF'
ALTER TABLESPACE APP_DATA READ WRITE;
ALTER TABLESPACE APP_INDX READ WRITE;
EOF
```

### 3.4 PDB Migration (Unplug/Plug)

```sql
-- Unplug từ CDB cũ
ALTER PLUGGABLE DATABASE pdb_app1 CLOSE IMMEDIATE;
ALTER PLUGGABLE DATABASE pdb_app1
  UNPLUG INTO '/tmp/pdb_app1_manifest.xml';
DROP PLUGGABLE DATABASE pdb_app1 KEEP DATAFILES;

-- Plug vào CDB mới
CREATE PLUGGABLE DATABASE pdb_app1
  USING '/tmp/pdb_app1_manifest.xml'
  COPY                                    -- COPY files sang location mới
  FILE_NAME_CONVERT = (
    '/u01/oradata/OLD_CDB/pdb_app1/',
    '/u01/oradata/NEW_CDB/pdb_app1/'
  );
ALTER PLUGGABLE DATABASE pdb_app1 OPEN;

-- Verify compatibility
SELECT DBMS_PDB.CHECK_PLUG_COMPATIBILITY(
  pdb_descr_file => '/tmp/pdb_app1_manifest.xml',
  pdb_name       => 'pdb_app1') compatible
FROM dual;
-- YES = compatible
```

### 3.5 Zero Downtime Migration với GoldenGate

```bash
# Chiến lược ZDM (Zero Downtime Migration):
# Phase 1: Initial load (DataPump full export/import)
# Phase 2: GoldenGate replicate changes trong khi import đang chạy
# Phase 3: Sync GoldenGate đến lag < 1 giây
# Phase 4: Cutover (chuyển application → target)
# Phase 5: Decommission source

# Setup GoldenGate trên Source (Extract)
# GGSCI> ADD EXTRACT ZDM_EXT, INTEGRATED TRANLOG, BEGIN NOW
# GGSCI> ADD EXTTRAIL ./dirdat/zm, EXTRACT ZDM_EXT

# Export và Import đồng thời với GoldenGate capturing
expdp system/pass@SOURCE full=Y dumpfile=zdm_full_%U.dmp parallel=8 &

# Theo dõi lag
# GGSCI> LAG EXTRACT ZDM_EXT
# Khi lag < 5 giây → sẵn sàng cutover
```

---

**Tài liệu tham khảo:**
- Oracle Database Upgrade Guide 19c
- Oracle AutoUpgrade Quick Start Guide
- Oracle DataPump User's Guide 19c
- MOS Note 2542817.1 (AutoUpgrade)
- www.tranvanbinh.vn
