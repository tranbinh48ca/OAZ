---
name: oracle-rman-duplicate-migration
description: >
  RMAN Duplicate và Cross-platform Migration Oracle.
  Kích hoạt khi hỏi về: RMAN duplicate, RMAN migration,
  active database duplicate, backup-based duplicate,
  duplicate for standby, cross-platform migration Oracle,
  Transportable Tablespace TTS cross-platform,
  convert datafile Oracle, endian format Oracle,
  RMAN duplicate parameters, RMAN clone database,
  database duplication Oracle, migrate Oracle to new server,
  RMAN NOFILENAMECHECK, SET NEWNAME RMAN, CONFIGURE CHANNEL,
  RMAN active duplicate ASM, cross-endian migration Oracle,
  XTTS Oracle migration, dbms_backup_restore Oracle.
---

# SK01-07 · RMAN Duplicate & Cross-Platform Migration

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. ACTIVE DATABASE DUPLICATE

```
Active Duplicate: Clone DB trực tiếp từ source đang chạy
  - Không cần dừng source DB
  - Source → Target qua network (Oracle Net)
  - Nhanh nhất cho same platform, same endian
  - Cần space = source DB size tại target
```

### 1.1 Chuẩn bị

```bash
# ── Trên SOURCE ──────────────────────────────────────────
# 1. Tạo password file nếu chưa có
orapwd file=$ORACLE_HOME/dbs/orapwORCL password="Oracle_2026!" force=y

# 2. Cấu hình listener tnsnames để target kết nối được
lsnrctl status

# ── Trên TARGET ──────────────────────────────────────────
# 1. Tạo password file
orapwd file=$ORACLE_HOME/dbs/orapwTARGET password="Oracle_2026!" force=y

# 2. Tạo pfile tối thiểu để startup nomount
cat > $ORACLE_HOME/dbs/initTARGET.ora << 'EOF'
db_name=TARGET
EOF

# 3. Tạo directories
mkdir -p /u01/oradata/TARGET
mkdir -p /u01/fra/TARGET
mkdir -p /u01/app/oracle/admin/TARGET/{adump,dpdump,scripts}

# 4. Startup NOMOUNT trên target
export ORACLE_SID=TARGET
sqlplus / as sysdba << 'EOF'
STARTUP NOMOUNT PFILE='$ORACLE_HOME/dbs/initTARGET.ora';
EOF

# 5. tnsnames.ora trên cả source và target
cat >> $TNS_ADMIN/tnsnames.ora << 'EOF'
ORCL =
  (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=source-server)(PORT=1521))
   (CONNECT_DATA=(SERVICE_NAME=ORCL)))

TARGET =
  (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=target-server)(PORT=1521))
   (CONNECT_DATA=(SERVICE_NAME=TARGET)(SERVER=DEDICATED)))
EOF
```

### 1.2 Active Duplicate Commands

```bash
# ── Filesystem to Filesystem ─────────────────────────────
rman \
  target  sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TARGET \
<< 'EOF'

DUPLICATE TARGET DATABASE TO TARGET
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT
      'ORCL','TARGET',
      '/u01/oradata/ORCL/','/u01/oradata/TARGET/',
      '/u01/fra/ORCL/','/u01/fra/TARGET/'
    SET DB_UNIQUE_NAME = 'TARGET'
    SET INSTANCE_NAME  = 'TARGET'
    SET LOG_ARCHIVE_DEST_1 = 'LOCATION=/u01/fra/TARGET/arch'
    SET CONTROL_FILES  = '/u01/oradata/TARGET/control01.ctl',
                         '/u01/fra/TARGET/control02.ctl'
    SET AUDIT_FILE_DEST = '/u01/app/oracle/admin/TARGET/adump'
  LOGFILE
    GROUP 1 '/u01/oradata/TARGET/redo01.log' SIZE 500M REUSE,
    GROUP 2 '/u01/oradata/TARGET/redo02.log' SIZE 500M REUSE,
    GROUP 3 '/u01/oradata/TARGET/redo03.log' SIZE 500M REUSE
  NOFILENAMECHECK;

EOF

# ── ASM to ASM ───────────────────────────────────────────
rman \
  target  sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TARGET \
<< 'EOF'

DUPLICATE TARGET DATABASE TO TARGET
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT 'ORCL','TARGET'
    SET DB_UNIQUE_NAME = 'TARGET'
    SET CONTROL_FILES  = '+DATA_TGT/TARGET/control01.ctl',
                         '+FRA_TGT/TARGET/control02.ctl'
  LOGFILE
    GROUP 1 '+DATA_TGT/TARGET/redo01.log' SIZE 500M,
    GROUP 2 '+DATA_TGT/TARGET/redo02.log' SIZE 500M
  NOFILENAMECHECK;

EOF

# ── Filesystem to ASM ────────────────────────────────────
rman \
  target  sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TARGET \
<< 'EOF'

DUPLICATE TARGET DATABASE TO TARGET
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    SET DB_UNIQUE_NAME = 'TARGET'
    SET DB_FILE_NAME_CONVERT =
      '/u01/oradata/ORCL/','+DATA',
      '/u01/fra/ORCL/','+FRA'
    SET LOG_FILE_NAME_CONVERT =
      '/u01/oradata/ORCL/','+DATA',
      '/u01/fra/ORCL/','+DATA'
    SET CONTROL_FILES = '+DATA/TARGET/control01.ctl','+FRA/TARGET/control02.ctl'
  NOFILENAMECHECK;

EOF
```

---

## 2. BACKUP-BASED DUPLICATE

```bash
# Khi source không available hoặc network không đủ bandwidth
# Dùng backup sets đã có sẵn

# ── Bước 1: Backup source ────────────────────────────────
rman target / << 'EOF'
BACKUP AS COMPRESSED BACKUPSET
  TAG 'MIGRATION_BACKUP'
  FORMAT '/backup/migration/%d_%T_%s_%p.bkp'
  DATABASE PLUS ARCHIVELOG DELETE INPUT;
BACKUP CURRENT CONTROLFILE
  FORMAT '/backup/migration/ctlfile.bkp';
BACKUP SPFILE
  FORMAT '/backup/migration/spfile.bkp';
EOF

# ── Bước 2: Copy backup sang target server ───────────────
rsync -avz /backup/migration/ oracle@target-server:/backup/migration/

# ── Bước 3: Catalog backup trên target ──────────────────
rman target / << 'EOF'
CATALOG START WITH '/backup/migration/' NOPROMPT;
LIST BACKUP SUMMARY;
EOF

# ── Bước 4: Duplicate từ backup ─────────────────────────
rman \
  target sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TARGET \
<< 'EOF'

DUPLICATE TARGET DATABASE TO TARGET
  BACKUP LOCATION '/backup/migration'
  SPFILE
    PARAMETER_VALUE_CONVERT 'ORCL','TARGET'
    SET DB_UNIQUE_NAME = 'TARGET'
    SET LOG_ARCHIVE_DEST_1 = 'LOCATION=/u01/arch/TARGET'
    SET CONTROL_FILES = '/u01/oradata/TARGET/control01.ctl'
  LOGFILE
    GROUP 1 '/u01/oradata/TARGET/redo01.log' SIZE 500M REUSE
  NOFILENAMECHECK;

EOF
```

---

## 3. DUPLICATE FOR STANDBY

```bash
# Dùng để tạo Physical Standby Database
rman \
  target  sys/"Oracle_2026!"@PRIMARY \
  auxiliary sys/"Oracle_2026!"@STANDBY \
<< 'EOF'

DUPLICATE TARGET DATABASE FOR STANDBY
  FROM ACTIVE DATABASE
  USING COMPRESSED BACKUPSET
  SPFILE
    PARAMETER_VALUE_CONVERT 'PRIMARY','STANDBY'
    SET DB_UNIQUE_NAME = 'STANDBY'
    SET FAL_SERVER     = 'PRIMARY'
    SET FAL_CLIENT     = 'STANDBY'
    SET STANDBY_FILE_MANAGEMENT = 'AUTO'
    SET LOG_ARCHIVE_DEST_2 =
      'SERVICE=PRIMARY ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE)
       DB_UNIQUE_NAME=PRIMARY'
    SET CONTROL_FILES =
      '/u01/oradata/STANDBY/control01.ctl',
      '/u01/fra/STANDBY/control02.ctl'
  DORECOVER              -- Apply logs sau duplicate
  NOFILENAMECHECK;

EOF

# Verify standby tạo thành công
sqlplus / as sysdba << 'EOF'
SELECT name, db_unique_name, open_mode, database_role FROM v$database;
SELECT process, status, sequence# FROM v$managed_standby;
EOF
```

---

## 4. POINT-IN-TIME DUPLICATE

```bash
# Duplicate đến thời điểm cụ thể (PITR clone)
rman \
  target  sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TESTDB \
<< 'EOF'

RUN {
  SET UNTIL TIME
    "TO_DATE('2026-01-15 10:30:00','YYYY-MM-DD HH24:MI:SS')";

  DUPLICATE TARGET DATABASE TO TESTDB
    FROM ACTIVE DATABASE
    USING COMPRESSED BACKUPSET
    SPFILE
      PARAMETER_VALUE_CONVERT 'ORCL','TESTDB'
      SET DB_UNIQUE_NAME = 'TESTDB'
      SET DB_NAME = 'TESTDB'
    NOFILENAMECHECK;
}

EOF

# Duplicate đến SCN cụ thể
rman \
  target sys/"Oracle_2026!"@ORCL \
  auxiliary sys/"Oracle_2026!"@TESTDB \
<< 'EOF'

RUN {
  SET UNTIL SCN 12345678;
  DUPLICATE TARGET DATABASE TO TESTDB
    FROM ACTIVE DATABASE
    SPFILE PARAMETER_VALUE_CONVERT 'ORCL','TESTDB'
    NOFILENAMECHECK;
}

EOF
```

---

## 5. CROSS-PLATFORM MIGRATION

### 5.1 Kiểm tra Platform Compatibility

```sql
-- Kiểm tra endian format của source
SELECT platform_name, endian_format FROM v$database;

-- Xem platforms hỗ trợ transportable
SELECT platform_id, platform_name, endian_format
FROM v$transportable_platform
ORDER BY endian_format, platform_name;

-- Same endian → TTS có thể direct copy
-- Different endian → cần RMAN convert
```

### 5.2 Same Endian (Linux → Linux)

```bash
# Đơn giản nhất: copy datafiles trực tiếp

# Source:
sqlplus / as sysdba << 'EOF'
ALTER TABLESPACE APP_DATA READ ONLY;
ALTER TABLESPACE APP_INDX READ ONLY;
EOF

expdp system/"Oracle_2026!" \
  transport_tablespaces=APP_DATA,APP_INDX \
  transport_full_check=Y \
  directory=DATA_PUMP_DIR \
  dumpfile=xtts_meta.dmp

# Copy files
scp /u01/oradata/ORCL/app_data01.dbf oracle@target:/u01/oradata/TARGET/
scp /u01/oradata/ORCL/app_indx01.dbf oracle@target:/u01/oradata/TARGET/
scp /u01/datapump/xtts_meta.dmp oracle@target:/u01/datapump/

# Target:
impdp system/"Oracle_2026!"@TARGET \
  dumpfile=xtts_meta.dmp \
  directory=DATA_PUMP_DIR \
  transport_datafiles='/u01/oradata/TARGET/app_data01.dbf',
                      '/u01/oradata/TARGET/app_indx01.dbf'

sqlplus / as sysdba << 'EOF' -- trên source
ALTER TABLESPACE APP_DATA READ WRITE;
ALTER TABLESPACE APP_INDX READ WRITE;
EOF
```

### 5.3 Different Endian (Linux x86 → Solaris SPARC)

```bash
# Cần RMAN CONVERT để chuyển đổi endian

# SOURCE (Linux, Little Endian):
# Bước 1: Make tablespace READ ONLY
sqlplus / as sysdba << 'EOF'
ALTER TABLESPACE APP_DATA READ ONLY;
EOF

# Bước 2: Convert datafiles (chạy trên source)
rman target / << 'EOF'
CONVERT TABLESPACE APP_DATA
  TO PLATFORM 'Solaris[tm] OE (64-bit)'
  FORMAT '/tmp/converted/%N_%f.dbf';
CONVERT CURRENT CONTROLFILE
  TO PLATFORM 'Solaris[tm] OE (64-bit)'
  FORMAT '/tmp/converted/standby_ctlfile.ctl';
EOF

# Bước 3: Copy converted files + export metadata
scp /tmp/converted/* oracle@solaris-server:/u01/oradata/TARGET/
expdp system/"Oracle_2026!" transport_tablespaces=APP_DATA \
  directory=DATA_PUMP_DIR dumpfile=xtts_sol.dmp
scp /u01/datapump/xtts_sol.dmp oracle@solaris-server:/u01/datapump/

# Bước 4: TARGET (Solaris) — convert lại nếu cần
rman target / << 'EOF'
CONVERT DATAFILE '/u01/oradata/TARGET/app_data01.dbf'
  TO PLATFORM 'Solaris[tm] OE (64-bit)'
  FROM PLATFORM 'Linux x86 64-bit'
  FORMAT '/u01/oradata/TARGET/app_data01_converted.dbf';
EOF

# Bước 5: Import metadata trên target
impdp system/"Oracle_2026!"@TARGET \
  dumpfile=xtts_sol.dmp \
  directory=DATA_PUMP_DIR \
  transport_datafiles='/u01/oradata/TARGET/app_data01_converted.dbf'
```

---

## 6. POST-DUPLICATE VALIDATION

```bash
# Validate duplicate thành công
sqlplus / as sysdba << 'EOF'
-- Database opened correctly
SELECT name, db_unique_name, open_mode FROM v$database;

-- Datafiles status
SELECT file#, status, name FROM v$datafile;

-- Verify blocks (RMAN)
EOF

rman target / << 'EOF'
VALIDATE DATABASE;
REPORT UNRECOVERABLE;
LIST FAILURE;
EOF

# Test application connectivity
sqlplus app_user/"AppPass_2026!"@TARGET \
  @/u01/scripts/app_validation.sql
```

---

**Tài liệu tham khảo:**
- Oracle RMAN Backup and Recovery User's Guide 19c — Duplicating a Database
- Oracle Database Backup and Recovery Reference 19c
- MOS Note 1079563.1 (RMAN Duplicate — Common Issues)
- www.tranvanbinh.vn
