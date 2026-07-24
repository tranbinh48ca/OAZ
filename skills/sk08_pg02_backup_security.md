---
name: postgresql-backup-security
description: >
  PostgreSQL Backup, Recovery và Row Level Security (RLS).
  Kích hoạt khi hỏi về: backup PostgreSQL, pg_dump, pg_restore,
  pg_basebackup, WAL archiving, PITR PostgreSQL, point-in-time recovery,
  pgBackRest, barman backup, restore PostgreSQL, recovery.conf,
  row level security PostgreSQL, RLS policy, CREATE POLICY,
  bảo mật PostgreSQL, audit PostgreSQL, pgAudit, SSL PostgreSQL,
  column level security PostgreSQL, security PostgreSQL.
---

# SK08-PG02 · PostgreSQL Backup, Recovery & Security

**Phiên bản:** PostgreSQL 14, 15, 16, 17  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. BACKUP STRATEGIES

```
Chiến lược backup PostgreSQL:
┌─────────────────────────────────────────────────────────────┐
│ Level 1: pg_dump (Logical backup — đơn giản)               │
│   ├─ Backup từng database/schema/table                     │
│   ├─ Cross-version compatible                               │
│   └─ Không hỗ trợ PITR                                     │
│                                                             │
│ Level 2: pg_basebackup (Physical backup — khuyến dùng)     │
│   ├─ Backup toàn bộ data directory                         │
│   ├─ Base backup + WAL = PITR                               │
│   └─ Nhanh hơn pg_dump cho DB lớn                          │
│                                                             │
│ Level 3: pgBackRest / Barman (Enterprise — tốt nhất)       │
│   ├─ Full / Differential / Incremental                      │
│   ├─ Compression, encryption, parallel                     │
│   ├─ PITR, remote backup                                    │
│   └─ Retention management                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. pg_dump — LOGICAL BACKUP

```bash
# Backup toàn bộ database (custom format — khuyến dùng)
pg_dump -U postgres \
  -Fc \          # Format custom (compressed, parallel restore)
  -v \           # Verbose
  --no-password \
  -f /backup/myapp_db_$(date +%Y%m%d_%H%M).dump \
  myapp_db

# Backup dạng SQL plain text
pg_dump -U postgres -Fp \
  -f /backup/myapp_db_$(date +%Y%m%d).sql \
  myapp_db

# Backup dạng directory (hỗ trợ parallel)
pg_dump -U postgres -Fd \
  -j 4 \           # 4 parallel workers
  -f /backup/myapp_db_dir/ \
  myapp_db

# Backup chỉ schema (không có data)
pg_dump -U postgres -s -f /backup/schema_only.sql myapp_db

# Backup chỉ data (không có DDL)
pg_dump -U postgres -a -f /backup/data_only.sql myapp_db

# Backup một schema cụ thể
pg_dump -U postgres -n app_schema -f /backup/app_schema.dump myapp_db

# Backup một table cụ thể
pg_dump -U postgres -t "public.orders" -f /backup/orders.dump myapp_db

# Backup tất cả databases (dùng pg_dumpall)
pg_dumpall -U postgres \
  --globals-only \    # Chỉ roles, tablespaces
  -f /backup/globals.sql

pg_dumpall -U postgres \
  -f /backup/all_databases_$(date +%Y%m%d).sql

# Backup với compression
pg_dump -U postgres myapp_db | gzip > /backup/myapp_db_$(date +%Y%m%d).sql.gz
```

### 2.1 pg_restore — Restore từ Logical Backup

```bash
# Restore toàn bộ database
createdb -U postgres new_myapp_db
pg_restore -U postgres \
  -d new_myapp_db \
  -v \
  -j 4 \           # Parallel restore
  /backup/myapp_db_20260101.dump

# Restore chỉ một table
pg_restore -U postgres \
  -d myapp_db \
  -t orders \
  /backup/myapp_db_20260101.dump

# Restore chỉ một schema
pg_restore -U postgres \
  -d myapp_db \
  -n app_schema \
  /backup/myapp_db_20260101.dump

# Restore với --clean (drop objects trước khi create)
pg_restore -U postgres \
  --clean \
  --if-exists \
  -d myapp_db \
  /backup/myapp_db_20260101.dump

# Restore từ SQL file
psql -U postgres myapp_db < /backup/myapp_db_20260101.sql

# Restore từ compressed
gunzip -c /backup/myapp_db_20260101.sql.gz | psql -U postgres myapp_db
```

---

## 3. pg_basebackup — PHYSICAL BACKUP

### 3.1 Cấu hình cho Physical Backup

```sql
-- postgresql.conf cần:
wal_level = replica            -- Tối thiểu replica
archive_mode = on
archive_command = 'cp %p /backup/wal_archive/%f'
max_wal_senders = 3            -- Số lượng WAL senders
wal_keep_size = 1024           -- MB WAL giữ lại (PG 13+)
```

```
-- pg_hba.conf thêm:
host    replication     backup_user     192.168.1.0/24    scram-sha-256
```

```sql
-- Tạo backup user
CREATE USER backup_user WITH REPLICATION PASSWORD 'BackupPass_123';
GRANT pg_read_all_settings TO backup_user;  -- PG 14+
```

### 3.2 Chạy pg_basebackup

```bash
# Backup cơ bản
pg_basebackup \
  -h 192.168.1.10 \
  -U backup_user \
  -D /backup/base/$(date +%Y%m%d) \
  -Ft \           # Format tar
  -z \            # Compress
  -P \            # Progress
  -Xs \           # Stream WAL (include WAL trong backup)
  -v

# Backup với checkpoint
pg_basebackup \
  -h localhost \
  -U backup_user \
  -D /backup/base/latest \
  -Fp \           # Format plain (không nén, sẵn sàng restore ngay)
  -Xs \
  --checkpoint=fast \
  -P -v

# Script backup tự động
cat > /usr/local/bin/pg_backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR=/backup/postgresql
DATE=$(date +%Y%m%d_%H%M)
LOG=/var/log/pg_backup.log

echo "[$DATE] Starting backup..." >> $LOG

pg_basebackup \
  -h localhost \
  -U backup_user \
  -D ${BACKUP_DIR}/base_${DATE} \
  -Ft -z -Xs -P \
  --checkpoint=fast 2>> $LOG

if [ $? -eq 0 ]; then
  echo "[$DATE] Backup COMPLETED: ${BACKUP_DIR}/base_${DATE}" >> $LOG
  # Xóa backup > 7 ngày
  find ${BACKUP_DIR} -name "base_*" -mtime +7 -exec rm -rf {} \;
else
  echo "[$DATE] Backup FAILED!" >> $LOG
  echo "PG Backup FAILED on $(hostname)" | mail -s "ALERT: PG Backup Fail" dba@company.com
fi
EOF
chmod +x /usr/local/bin/pg_backup.sh

# Cron: 2AM daily
echo "0 2 * * * postgres /usr/local/bin/pg_backup.sh" >> /etc/crontab
```

---

## 4. WAL ARCHIVING & PITR

### 4.1 Cấu hình WAL Archiving

```ini
# postgresql.conf
wal_level = replica
archive_mode = on

# archive_command — chọn một trong hai:
# Option 1: Copy đơn giản
archive_command = 'cp %p /backup/wal_archive/%f && echo Archived: %f'

# Option 2: rsync sang remote server
archive_command = 'rsync -a %p backup@backup-server:/backup/wal/%f'

# Option 3: Nén trước khi archive
archive_command = 'gzip -c %p > /backup/wal_archive/%f.gz'
```

```sql
-- Test archive command hoạt động
SELECT pg_switch_wal();
-- Kiểm tra file xuất hiện trong /backup/wal_archive/

-- Xem WAL archiving status
SELECT archived_count, failed_count, last_archived_wal,
       last_archived_time, last_failed_wal, last_failed_time
FROM pg_stat_archiver;
```

### 4.2 Point-in-Time Recovery (PITR)

```bash
# Bước 1: Dừng PostgreSQL (nếu restore trên cùng server)
systemctl stop postgresql-16

# Bước 2: Backup data directory hiện tại (phòng ngừa)
mv /var/lib/postgresql/16/main /var/lib/postgresql/16/main_old

# Bước 3: Restore base backup
tar -xzf /backup/base_20260101.tar.gz -C /var/lib/postgresql/16/main/
# hoặc nếu format plain:
cp -r /backup/base_20260101/* /var/lib/postgresql/16/main/

# Bước 4: Tạo recovery signal file
touch /var/lib/postgresql/16/main/recovery.signal

# Bước 5: Cấu hình recovery trong postgresql.conf
cat >> /var/lib/postgresql/16/main/postgresql.conf << 'EOF'
# Recovery settings
restore_command = 'cp /backup/wal_archive/%f %p'
# Hoặc nếu WAL nén:
# restore_command = 'gunzip -c /backup/wal_archive/%f.gz > %p'

# PITR target (chọn một):
recovery_target_time = '2026-01-15 10:30:00'    # Đến thời điểm cụ thể
# recovery_target_lsn = '0/15000000'             # Đến LSN cụ thể
# recovery_target_xid = '12345'                  # Đến transaction ID cụ thể
# recovery_target = 'immediate'                   # Consistent point gần nhất

# Sau recovery, đóng ở trạng thái nào?
recovery_target_action = 'promote'  # promote = mở DB bình thường
# recovery_target_action = 'pause'  # pause = dừng, đợi confirm
EOF

# Bước 6: Fix ownership
chown -R postgres:postgres /var/lib/postgresql/16/main/

# Bước 7: Start PostgreSQL (sẽ tự apply WAL đến target time)
systemctl start postgresql-16

# Monitor recovery progress
tail -f /var/log/postgresql/postgresql-$(date +%Y-%m-%d).log
# Tìm: "recovery stopping before commit"
# Tìm: "database system is ready to accept connections"
```

---

## 5. pgBackRest — ENTERPRISE BACKUP

```ini
# /etc/pgbackrest/pgbackrest.conf

[global]
repo1-path=/backup/pgbackrest
repo1-retention-full=4          # Giữ 4 full backups
repo1-retention-diff=14         # Giữ 14 differential backups
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=StrongPassphrase_123
compress-type=lz4
compress-level=6
process-max=4
log-level-console=info
log-level-file=detail

[myapp_db]
pg1-path=/var/lib/postgresql/16/main
pg1-port=5432
pg1-user=postgres
```

```bash
# Khởi tạo repository
pgbackrest --stanza=myapp_db stanza-create

# Check config
pgbackrest --stanza=myapp_db check

# Full backup
pgbackrest --stanza=myapp_db --type=full backup

# Differential backup (từ full gần nhất)
pgbackrest --stanza=myapp_db --type=diff backup

# Incremental backup (từ backup gần nhất)
pgbackrest --stanza=myapp_db --type=incr backup

# Xem danh sách backups
pgbackrest --stanza=myapp_db info

# PITR restore
pgbackrest --stanza=myapp_db \
  --target="2026-01-15 10:30:00" \
  --target-action=promote \
  --type=time restore

# Restore full
pgbackrest --stanza=myapp_db restore
```

---

## 6. ROW LEVEL SECURITY (RLS)

### 6.1 Khái niệm

```
Row Level Security trong PostgreSQL:
- Filter rows TRONG DATABASE (không phải ở application layer)
- Mỗi policy định nghĩa điều kiện cho từng operation
- Trong suốt với application — không cần thay đổi SQL
- Bảo vệ dữ liệu ngay cả khi có SQL injection
```

### 6.2 Cài đặt RLS

```sql
-- Ví dụ: Multi-tenant SaaS — mỗi tenant chỉ thấy data của mình

-- Bước 1: Tạo tables
CREATE TABLE tenants (
  id       SERIAL PRIMARY KEY,
  name     TEXT NOT NULL,
  slug     TEXT UNIQUE NOT NULL
);

CREATE TABLE orders (
  id          SERIAL PRIMARY KEY,
  tenant_id   INTEGER NOT NULL REFERENCES tenants(id),
  customer    TEXT,
  amount      NUMERIC(12,2),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Bước 2: Tạo function lấy tenant_id của current user
CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS INTEGER AS $$
  SELECT COALESCE(
    current_setting('app.tenant_id', TRUE)::INTEGER,
    0
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Bước 3: Enable RLS trên table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;  -- Áp dụng cả với owner

-- Bước 4: Tạo policies
-- Policy SELECT: chỉ thấy orders của tenant mình
CREATE POLICY tenant_isolation_select ON orders
  FOR SELECT
  USING (tenant_id = current_tenant_id());

-- Policy INSERT: chỉ insert cho tenant mình
CREATE POLICY tenant_isolation_insert ON orders
  FOR INSERT
  WITH CHECK (tenant_id = current_tenant_id());

-- Policy UPDATE: chỉ update orders của tenant mình
CREATE POLICY tenant_isolation_update ON orders
  FOR UPDATE
  USING (tenant_id = current_tenant_id())
  WITH CHECK (tenant_id = current_tenant_id());

-- Policy DELETE: chỉ delete orders của tenant mình
CREATE POLICY tenant_isolation_delete ON orders
  FOR DELETE
  USING (tenant_id = current_tenant_id());

-- Bước 5: Sử dụng trong application
-- Khi user của tenant 5 kết nối:
SET app.tenant_id = 5;
SELECT * FROM orders;  -- Chỉ thấy tenant_id = 5

-- Xem policies đã tạo
SELECT schemaname, tablename, policyname, permissive,
       roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'orders';
```

### 6.3 RLS cho Row-Level Permission

```sql
-- Ví dụ: Employee chỉ thấy salary của mình, HR thấy tất cả

CREATE TABLE employees (
  id          SERIAL PRIMARY KEY,
  username    TEXT NOT NULL,
  department  TEXT,
  salary      NUMERIC(10,2),
  manager_id  INTEGER REFERENCES employees(id)
);

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- HR role thấy tất cả
CREATE POLICY hr_full_access ON employees
  TO hr_role
  USING (TRUE);

-- Manager thấy nhân viên của mình
CREATE POLICY manager_access ON employees
  TO manager_role
  USING (
    id = (SELECT id FROM employees WHERE username = current_user)
    OR
    manager_id = (SELECT id FROM employees WHERE username = current_user)
  );

-- Employee chỉ thấy row của mình
CREATE POLICY employee_self_access ON employees
  TO employee_role
  USING (username = current_user);

-- Gán roles
GRANT SELECT ON employees TO employee_role;
GRANT SELECT ON employees TO manager_role;
GRANT SELECT, INSERT, UPDATE ON employees TO hr_role;

-- Test
SET ROLE emp_nguyen;
SELECT * FROM employees;  -- Chỉ thấy row của nguyen
```

### 6.4 Column-Level Security

```sql
-- Ẩn salary khỏi những user không có quyền
REVOKE SELECT ON employees FROM PUBLIC;

-- Cho phép xem tất cả columns trừ salary
GRANT SELECT (id, username, department, manager_id) ON employees TO employee_role;

-- HR thấy tất cả columns
GRANT SELECT ON employees TO hr_role;
```

---

## 7. pgAudit — AUDIT LOGGING

```bash
# Cài pgAudit (sau khi cài postgresql-16-contrib)
apt-get install -y postgresql-16-pgaudit
```

```ini
# postgresql.conf
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'write, ddl'   # write=DML, ddl=DDL, read=SELECT
pgaudit.log_catalog = off    # Không log system catalog queries
pgaudit.log_level = log
pgaudit.log_parameter = on   # Log bind parameters
pgaudit.log_statement_once = off
```

```sql
-- Reload config
SELECT pg_reload_conf();

-- Enable pgaudit extension
CREATE EXTENSION pgaudit;

-- Session-level audit (audit tất cả operations của session)
SET pgaudit.log = 'all';

-- Object-level audit (audit specific objects)
SELECT pgaudit.set_config('log', 'read,write', FALSE);

-- Tạo audit role và gán
CREATE ROLE audit_role;
GRANT SELECT ON sensitive_table TO audit_role;
SECURITY LABEL FOR pgaudit ON ROLE audit_role IS 'audit';
```

---

## 8. SSL/TLS CHO POSTGRESQL

```bash
# Tạo self-signed certificate
openssl req -new -x509 -days 365 -nodes \
  -out /etc/ssl/postgresql/server.crt \
  -keyout /etc/ssl/postgresql/server.key \
  -subj "/CN=postgres-server"

chmod 600 /etc/ssl/postgresql/server.key
chown postgres:postgres /etc/ssl/postgresql/server.*
```

```ini
# postgresql.conf
ssl = on
ssl_cert_file = '/etc/ssl/postgresql/server.crt'
ssl_key_file  = '/etc/ssl/postgresql/server.key'
ssl_ca_file   = '/etc/ssl/postgresql/root.crt'    # CA cho client certs
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_min_protocol_version = 'TLSv1.2'
```

```
# pg_hba.conf — yêu cầu SSL
hostssl  all  all  0.0.0.0/0  scram-sha-256
```

```bash
# Kiểm tra SSL
psql "postgresql://user:pass@host/db?sslmode=require"

# Từ SQL
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

---

**Tài liệu tham khảo:**
- PostgreSQL Backup and Recovery: postgresql.org/docs/16/backup.html
- pgBackRest: pgbackrest.org
- RLS: postgresql.org/docs/16/ddl-rowsecurity.html
- pgAudit: pgaudit.org
- www.tranvanbinh.vn
