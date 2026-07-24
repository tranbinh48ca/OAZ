---
name: oracle-dbua-autoupgrade
description: >
  Nâng cấp Oracle Database bằng DBUA và AutoUpgrade tool.
  Kích hoạt khi hỏi về: nâng cấp Oracle, upgrade Oracle database,
  DBUA upgrade tool, AutoUpgrade Oracle, autoupgrade.jar,
  upgrade 11g to 19c, upgrade 12c to 19c, upgrade Oracle 19c 21c,
  pre-upgrade checks Oracle, preupgrade.jar, catupgrd.sql,
  catctl.pl parallel upgrade, postupgrade fixup, utlrp.sql,
  timezone upgrade Oracle, invalid objects after upgrade,
  component upgrade Oracle, upgrade RAC database,
  upgrade CDB PDB Oracle, AutoUpgrade analyze fixup deploy,
  AutoUpgrade caution restore, upgrade rollback Oracle,
  upgrade checklist Oracle, downtime upgrade Oracle.
---

# SK01-05 · Nâng cấp Oracle Database: DBUA & AutoUpgrade

**Phạm vi:** 11.2.0.4 / 12.1 / 12.2 / 18c → 19c → 21c → 23ai  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. UPGRADE PATHS VÀ STRATEGY

```
Supported upgrade paths → 19c:
  11.2.0.4 → 19c  (direct, nhưng khuyến dùng qua 12.2)
  12.1.0.2 → 19c  (direct)
  12.2.0.1 → 19c  (direct, phổ biến nhất)
  18.x     → 19c  (direct)

Recommended: 11.2.0.4 → 12.2.0.1 → 19c
Nếu muốn skip: 11.2.0.4 → 19c (apply PSU 11.2.0.4.x trước)

Upgrade methods:
┌──────────────────────────────────────────────────────────┐
│ AutoUpgrade (khuyến dùng 19c+)                          │
│   + Tự động analyze → fixup → upgrade → validate        │
│   + Hỗ trợ multiple databases cùng lúc                  │
│   + Rollback tự động nếu fail (khi caution=yes)         │
│                                                          │
│ DBUA (Database Upgrade Assistant)                        │
│   + GUI-based hoặc silent mode                          │
│   + Pre/Post checks tự động                             │
│   + Tốt cho single database upgrade                     │
│                                                          │
│ Manual Upgrade (advanced, full control)                  │
│   + catctl.pl parallel upgrade                          │
│   + Phải làm tất cả steps thủ công                     │
└──────────────────────────────────────────────────────────┘
```

---

## 2. PRE-UPGRADE PREPARATION

### 2.1 Kiểm tra compatibility

```sql
-- Chạy với SOURCE Oracle Home TRƯỚC khi upgrade

-- 1. Kiểm tra DB version
SELECT banner FROM v$version;
SELECT name, db_unique_name, log_mode, platform_name FROM v$database;
SELECT comp_name, version, status FROM dba_registry ORDER BY comp_name;

-- 2. Kiểm tra tính năng không còn support
SELECT name, version, detected_usages, currently_used
FROM dba_feature_usage_statistics
WHERE currently_used = 'TRUE'
ORDER BY name;

-- 3. Deprecated parameters
SELECT name, value, description
FROM v$parameter
WHERE name IN (
  'sec_case_sensitive_logon',   -- Removed 12.2
  'o7_dictionary_accessibility', -- Removed 12.2
  'parallel_server',            -- RAC: renamed cluster_database
  'background_dump_dest',       -- Removed 11.2
  'user_dump_dest'              -- Removed 11.2
);

-- 4. Invalid objects BEFORE upgrade
SELECT owner, object_type, COUNT(*) FROM dba_objects
WHERE status = 'INVALID'
  AND owner NOT IN ('SYS','SYSTEM')
GROUP BY owner, object_type ORDER BY 1,2;

-- 5. Database size
SELECT ROUND(SUM(bytes)/1024/1024/1024, 2) db_size_gb
FROM dba_data_files;
```

### 2.2 Pre-upgrade Information Tool

```bash
# Chạy với TARGET Oracle Home (19c)
# Tool này phân tích và sinh fixup scripts

$NEW_HOME/jdk/bin/java \
  -jar $NEW_HOME/rdbms/admin/preupgrade.jar \
  FILE TEXT \
  -c "ORCL" 2>&1 | tee /tmp/preupgrade_report.txt

# Output files:
# $ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/
ls $ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/
# preupgrade.log          — Full report
# preupgrade_fixups.sql   — Chạy trước upgrade
# postupgrade_fixups.sql  — Chạy sau upgrade

# Review báo cáo
cat $ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/preupgrade.log | \
  grep -E "ERROR|WARNING|ACTION REQUIRED"

# Chạy pre-upgrade fixups (với SOURCE Oracle Home)
sqlplus / as sysdba << 'EOF'
@$ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/preupgrade_fixups.sql
EOF
```

### 2.3 Pre-upgrade Tasks

```sql
-- 1. Gather dictionary statistics (tăng tốc upgrade)
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;
EXEC DBMS_STATS.GATHER_FIXED_OBJECTS_STATS;

-- 2. Purge recycle bin
PURGE DBA_RECYCLEBIN;

-- 3. Xóa invalid objects nếu có thể
@$ORACLE_HOME/rdbms/admin/utlrp.sql

-- 4. Backup: RMAN full backup (LUÔN LÀM TRƯỚC)
-- rman target / <<'EOF'
-- BACKUP AS COMPRESSED BACKUPSET DATABASE PLUS ARCHIVELOG;
-- BACKUP CURRENT CONTROLFILE;
-- EOF

-- 5. Ghi lại configuration
SELECT name, value FROM v$parameter
WHERE value IS NOT NULL ORDER BY name;
SHOW PARAMETER sga_target;
SHOW PARAMETER pga_aggregate_target;

-- 6. Flashback DB restore point (nếu có FRA, không bắt buộc)
CREATE RESTORE POINT pre_upgrade_rp
  GUARANTEE FLASHBACK DATABASE;
SELECT name, guarantee_flashback_database FROM v$restore_point;

-- 7. Timezone check
SELECT * FROM v$timezone_file;
-- Nếu timezone version < target → timezone upgrade cần thiết sau upgrade
```

---

## 3. AUTOUPGRADE (KHUYẾN DÙNG)

### 3.1 AutoUpgrade Config File

```bash
# AutoUpgrade tự động hoá toàn bộ flow:
# analyze → fixup → upgrade → postupgrade → validate

# Config file đơn giản (single DB)
cat > /tmp/autoupgrade_single.cfg << 'EOF'
# Global settings
global.autoupg_log_dir=/u01/autoupgrade_logs

# DB 1: ORCL
upg1.sid=ORCL
upg1.source_home=/u01/app/oracle/product/12.2.0/dbhome_1
upg1.target_home=/u01/app/oracle/product/19.3.0/dbhome_1
upg1.log_dir=/u01/autoupgrade_logs/ORCL
upg1.start_time=NOW
upg1.upgrade_node=localhost
upg1.target_version=19
upg1.run_utluppkg=yes
upg1.restoration=yes               # Enable flashback restore point
upg1.timezone_upg=yes              # Upgrade timezone data
upg1.post_fixed_objects=yes        # Fix invalid objects sau upgrade
EOF

# Config file nâng cao (multiple DBs, CDB)
cat > /tmp/autoupgrade_multi.cfg << 'EOF'
global.autoupg_log_dir=/u01/autoupgrade_logs
global.target_home=/u01/app/oracle/product/19.3.0/dbhome_1

# DB 1: ORCL12 → 19c
upg1.sid=ORCL12
upg1.source_home=/u01/app/oracle/product/12.2.0/dbhome_1
upg1.log_dir=/u01/autoupgrade_logs/ORCL12
upg1.start_time=NOW
upg1.upgrade_node=db-server1

# DB 2: TESTDB → 19c (với PDB)
upg2.sid=TESTDB
upg2.source_home=/u01/app/oracle/product/12.1.0/dbhome_1
upg2.log_dir=/u01/autoupgrade_logs/TESTDB
upg2.start_time=+60                # Bắt đầu sau 60 phút
upg2.pdbs=PDB1,PDB2               # Chỉ upgrade PDBs này
upg2.pdb_parallels=2              # Upgrade 2 PDBs song song
EOF
```

### 3.2 AutoUpgrade Execution Modes

```bash
export NEW_HOME=/u01/app/oracle/product/19.3.0/dbhome_1
AUTOUPG=$NEW_HOME/rdbms/admin/autoupgrade.jar

# ── Mode 1: ANALYZE (chỉ kiểm tra, KHÔNG thay đổi gì) ──────
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode analyze \
  -config /tmp/autoupgrade_single.cfg \
  2>&1 | tee /tmp/autoupg_analyze.log

# Review HTML report:
ls /u01/autoupgrade_logs/cfgtoollogs/upgrade/auto/status/
# status.html — mở bằng browser

# ── Mode 2: FIXUP (fix issues tự động, chưa upgrade) ────────
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode fixups \
  -config /tmp/autoupgrade_single.cfg

# ── Mode 3: DEPLOY (upgrade thật sự) ────────────────────────
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode deploy \
  -config /tmp/autoupgrade_single.cfg

# ── Mode 4: UPGRADE (skip fixup phase) ──────────────────────
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode upgrade \
  -config /tmp/autoupgrade_single.cfg
```

### 3.3 AutoUpgrade Interactive Console

```bash
# Chạy deploy ở background + dùng console để monitor/control
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode deploy \
  -config /tmp/autoupgrade_single.cfg &

# Console commands (connect to running process):
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode deploy \
  -config /tmp/autoupgrade_single.cfg -console

# Trong console:
# lsj              → list all jobs
# status           → overall status
# status -job 1    → detail của job 1
# resume -job 1    → resume paused job
# abort  -job 1    → abort và rollback job
# quit             → exit console (job vẫn chạy background)
```

### 3.4 AutoUpgrade - Xử lý khi fail

```bash
# Khi AutoUpgrade fail ở bước nào đó:

# 1. Xem log chi tiết
cat /u01/autoupgrade_logs/ORCL/*/autoupgrade_*.log | \
  grep -E "ERROR|SEVERE|Exception"

# 2. Xem job status
$NEW_HOME/jdk/bin/java -jar $AUTOUPG \
  -mode deploy \
  -config /tmp/autoupgrade_single.cfg -console
# > status -job 1
# > jobs

# 3. Resume nếu có thể (sau khi fix issue)
# > resume -job 1

# 4. Rollback về source (nếu restoration=yes và có flashback)
# > abort -job 1
# AutoUpgrade sẽ tự flashback về restore point

# Rollback thủ công:
sqlplus / as sysdba << 'EOF'
STARTUP MOUNT;
FLASHBACK DATABASE TO RESTORE POINT pre_upgrade_rp;
ALTER DATABASE OPEN RESETLOGS;
EOF
# Sau đó update ORACLE_HOME trong /etc/oratab về source
```

---

## 4. DBUA UPGRADE

### 4.1 DBUA Silent Mode

```bash
# DBUA Silent — ít tương tác hơn AutoUpgrade nhưng đơn giản
export ORACLE_HOME=$NEW_HOME

$NEW_HOME/bin/dbua -silent \
  -sid ORCL \
  -oracleHome $NEW_HOME \
  -sysDBAUserName sys \
  -sysDBAPassword "Oracle_2026!" \
  -recompileInvalidObjects true \
  -upgradeTimezone true

# Nếu RAC:
$NEW_HOME/bin/dbua -silent \
  -sid ORCL \
  -oracleHome $NEW_HOME \
  -sysDBAUserName sys \
  -sysDBAPassword "Oracle_2026!" \
  -upgradeTimezone true \
  -nodelist node1,node2
```

### 4.2 DBUA GUI Mode

```bash
# Set DISPLAY nếu remote
export DISPLAY=:0.0
# Hoặc dùng X11 forwarding:
ssh -X oracle@dbserver

# Chạy DBUA
$NEW_HOME/bin/dbua

# DBUA GUI steps:
# 1. Select database to upgrade
# 2. Pre-Upgrade checks summary
# 3. Select upgrade options
# 4. Summary screen → Start
# 5. Monitor progress
# 6. Post-upgrade checks
# 7. Completion
```

---

## 5. MANUAL UPGRADE (ADVANCED)

```bash
# Khi cần control hoàn toàn hoặc DBUA/AutoUpgrade không dùng được

# ── Phase 1: Pre-upgrade (SOURCE Home) ───────────────────
export OLD_HOME=/u01/app/oracle/product/12.2.0/dbhome_1
export NEW_HOME=/u01/app/oracle/product/19.3.0/dbhome_1

$NEW_HOME/jdk/bin/java \
  -jar $NEW_HOME/rdbms/admin/preupgrade.jar FILE TEXT

sqlplus / as sysdba << 'EOF'
@$ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/preupgrade_fixups.sql
EXEC DBMS_STATS.GATHER_DICTIONARY_STATS;
EXEC DBMS_STATS.GATHER_FIXED_OBJECTS_STATS;
PURGE DBA_RECYCLEBIN;
SHUTDOWN IMMEDIATE;
EOF

# ── Phase 2: Startup UPGRADE mode (NEW Home) ─────────────
export ORACLE_HOME=$NEW_HOME
export PATH=$NEW_HOME/bin:$PATH
export ORACLE_SID=ORCL

sqlplus / as sysdba << 'EOF'
STARTUP UPGRADE;
EOF

# ── Phase 3: Run catctl.pl (parallel upgrade) ─────────────
$NEW_HOME/perl/bin/perl \
  $NEW_HOME/rdbms/admin/catctl.pl \
  -n  4 \              # 4 parallel streams
  -d  $NEW_HOME/rdbms/admin \
  catupgrd.sql \
  2>&1 | tee /tmp/catupgrd_$(date +%Y%m%d).log

# Monitor progress:
tail -f /tmp/catupgrd_*.log
# Hoặc xem phase file:
cat /tmp/catupgrd*.log | grep -E "^Phase|^Execution"

# ── Phase 4: Post-upgrade ─────────────────────────────────
sqlplus / as sysdba << 'EOF'
-- Restart normal mode
SHUTDOWN IMMEDIATE;
STARTUP;

-- Post-upgrade fixup
@$ORACLE_HOME/rdbms/admin/catuppst.sql

-- Recompile invalid objects
@$ORACLE_HOME/rdbms/admin/utlrp.sql

-- Apply post-upgrade fixups từ preupgrade tool
@$ORACLE_BASE/cfgtoollogs/ORCL/preupgrade/postupgrade_fixups.sql

-- Upgrade timezone
@$ORACLE_HOME/rdbms/admin/utltz_upg_check.sql
-- Nếu cần nâng cấp:
-- @$ORACLE_HOME/rdbms/admin/utltz_upg_apply.sql

-- Gather fixed objects stats (QUAN TRỌNG cho performance)
EXEC DBMS_STATS.GATHER_FIXED_OBJECTS_STATS;

-- Verify
SELECT comp_name, version_full, status
FROM dba_registry ORDER BY comp_name;
-- TẤT CẢ phải VALID

SELECT COUNT(*) invalid_after_upgrade
FROM dba_objects WHERE status='INVALID'
  AND owner NOT IN ('SYS','SYSTEM');

EXIT;
EOF
```

---

## 6. POST-UPGRADE VALIDATION CHECKLIST

```sql
-- Chạy sau upgrade để confirm thành công

-- 1. Version và components
SELECT comp_name, version_full, status FROM dba_registry;
SELECT * FROM v$instance;

-- 2. Invalid objects = 0
SELECT owner, object_type, COUNT(*) FROM dba_objects
WHERE status='INVALID' AND owner NOT IN ('SYS','SYSTEM','DBSNMP')
GROUP BY owner, object_type;

-- 3. Timezone
SELECT * FROM v$timezone_file;
SELECT property_name, property_value FROM database_properties
WHERE property_name LIKE 'DST%';

-- 4. Parameters không còn hợp lệ
SELECT name, value, description
FROM v$parameter WHERE name IN (
  'compatible','db_recovery_file_dest',
  'sga_target','pga_aggregate_target',
  'undo_management','undo_tablespace'
);
-- compatible phải được update sau upgrade:
ALTER SYSTEM SET compatible = '19.0.0' SCOPE=SPFILE;

-- 5. Performance baseline (so sánh với pre-upgrade)
SELECT metric_name, ROUND(value,2) value, metric_unit
FROM v$sysmetric WHERE group_id=2
AND metric_name IN (
  'Buffer Cache Hit Ratio',
  'Library Cache Hit Ratio',
  'Average Active Sessions',
  'Host CPU Utilization (%)');

-- 6. Drop restore point sau khi verify OK
DROP RESTORE POINT pre_upgrade_rp;
```

---

## 7. CDB/PDB UPGRADE SPECIFICS

```sql
-- Khi upgrade CDB, tất cả PDBs cũng được upgrade
-- Nhưng có thể upgrade PDB riêng lẻ:

-- Kiểm tra PDB compatibility
SELECT p.name pdb, p.open_mode,
       regexp_substr(dbms_pdb.check_plug_compatibility(
         pdb_descr_file => null), '.+') compatible
FROM v$pdbs p WHERE p.con_id > 2;

-- Upgrade PDB cụ thể (12.2+)
-- Sau khi CDB đã upgrade, PDB vẫn ở version cũ:
ALTER PLUGGABLE DATABASE pdb1 UPGRADE;

-- Hoặc upgrade tất cả PDBs song song:
ALTER PLUGGABLE DATABASE ALL UPGRADE;
-- Monitor:
SELECT con_id, name, open_mode FROM v$pdbs;

-- PDB sau upgrade cần compile lại:
ALTER SESSION SET CONTAINER = pdb1;
@$ORACLE_HOME/rdbms/admin/utlrp.sql
```

---

**Tài liệu tham khảo:**
- Oracle Database Upgrade Guide 19c: docs.oracle.com/upgrd
- MOS Note 2539751.1 (AutoUpgrade Tool 19c)
- MOS Note 1948882.1 (DBUA Known Issues)
- AutoUpgrade Quick Start: docs.oracle.com/en/database/oracle/oracle-database/19/upgrd/using-autoupgrade-oracle-database-upgrades.html
- www.tranvanbinh.vn
