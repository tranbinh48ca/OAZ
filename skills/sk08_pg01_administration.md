---
name: postgresql-administration
description: >
  Quản trị PostgreSQL toàn diện từ cài đặt đến vận hành production.
  Kích hoạt khi hỏi về: PostgreSQL, Postgres, PG admin, cài đặt PostgreSQL,
  cấu hình postgresql.conf, pg_hba.conf, quản lý user role PostgreSQL,
  tablespace PostgreSQL, schema, VACUUM ANALYZE, autovacuum, bloat,
  table bloat, pg_stat, extension PostgreSQL, pgAdmin, psql commands,
  quản lý kết nối PgBouncer, connection pooling, pg_stat_activity,
  kiểm tra disk space PostgreSQL, lock PostgreSQL, pg_locks,
  long running query PostgreSQL, maintenance PostgreSQL, seq scan index scan.
---

# SK08-PG01 · PostgreSQL Administration

**Phiên bản:** PostgreSQL 14, 15, 16, 17  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. CÀI ĐẶT POSTGRESQL

### 1.1 RHEL/OL 8/9

```bash
# Cài PostgreSQL 16 từ PGDG repo
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql
dnf install -y postgresql16-server postgresql16-contrib

# Khởi tạo data directory
/usr/pgsql-16/bin/postgresql-16-setup initdb

# Enable & start
systemctl enable postgresql-16
systemctl start  postgresql-16
systemctl status postgresql-16

# Kết nối lần đầu
sudo -u postgres psql
```

### 1.2 Ubuntu/Debian

```bash
# Thêm PGDG repo
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get -y install postgresql-16 postgresql-contrib

sudo -u postgres psql
```

---

## 2. CẤU HÌNH POSTGRESQL

### 2.1 postgresql.conf — Các tham số quan trọng

```ini
# FILE: /etc/postgresql/16/main/postgresql.conf
# (hoặc $PGDATA/postgresql.conf)

#── KẾT NỐI ─────────────────────────────────────────
listen_addresses = '*'          # Lắng nghe tất cả interfaces
port = 5432
max_connections = 200           # Tổng connections tối đa

#── MEMORY ──────────────────────────────────────────
shared_buffers = 4GB            # 25% RAM — buffer cache chính
huge_pages = on                 # Bật HugePages cho hiệu năng
effective_cache_size = 12GB     # 75% RAM — gợi ý cho optimizer
work_mem = 64MB                 # RAM cho sort/hash mỗi operation
                                # Cẩn thận: max_connections * work_mem
maintenance_work_mem = 1GB      # VACUUM, CREATE INDEX
wal_buffers = 64MB              # Buffer WAL (tự tính từ shared_buffers)

#── WAL / CHECKPOINT ────────────────────────────────
wal_level = replica             # minimal | replica | logical
max_wal_size = 4GB              # Tối đa WAL trước checkpoint
min_wal_size = 1GB
checkpoint_completion_target = 0.9
synchronous_commit = on         # on=an toàn | off=nhanh nhưng có thể mất data

#── QUERY OPTIMIZER ─────────────────────────────────
random_page_cost = 1.1          # SSD: 1.1, HDD: 4.0
effective_io_concurrency = 200  # SSD: 200, HDD: 2
default_statistics_target = 100 # Độ chính xác statistics (10-10000)

#── LOGGING ─────────────────────────────────────────
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_min_duration_statement = 1000  # Log query > 1 giây (ms)
log_line_prefix = '%t [%p] %u@%d '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

#── AUTOVACUUM ──────────────────────────────────────
autovacuum = on
autovacuum_max_workers = 5
autovacuum_naptime = 30s
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.01    # 1% thay đổi → trigger vacuum
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.005  # 0.5% → trigger analyze
autovacuum_vacuum_cost_delay = 2ms       # Giảm để vacuum nhanh hơn

#── PARALLELISM ─────────────────────────────────────
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
max_worker_processes = 16
```

### 2.2 pg_hba.conf — Authentication

```
# FILE: /etc/postgresql/16/main/pg_hba.conf
# TYPE  DATABASE    USER        ADDRESS         METHOD

# Local connections
local   all         postgres                    peer
local   all         all                         md5

# IPv4 local connections
host    all         all         127.0.0.1/32    scram-sha-256
host    all         all         192.168.1.0/24  scram-sha-256

# Replication connections
host    replication replicator  192.168.1.0/24  scram-sha-256

# Specific database and user
host    myapp_db    app_user    10.0.0.0/8      scram-sha-256

# Block all other
# (implicit deny at end)
```

```bash
# Reload config (không cần restart)
pg_ctl reload -D $PGDATA
# hoặc:
psql -U postgres -c "SELECT pg_reload_conf();"
```

---

## 3. QUẢN LÝ USER, ROLE, PRIVILEGES

```sql
-- Tạo role (group)
CREATE ROLE app_readwrite;
CREATE ROLE app_readonly;

-- Gán quyền cho role
GRANT CONNECT ON DATABASE myapp TO app_readwrite;
GRANT USAGE ON SCHEMA public TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_readwrite;

GRANT CONNECT ON DATABASE myapp TO app_readonly;
GRANT USAGE ON SCHEMA public TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;

-- Đặt default privileges cho tables mới tạo trong tương lai
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO app_readonly;

-- Tạo user và gán role
CREATE USER dev_user WITH PASSWORD 'DevPass_123' LOGIN;
GRANT app_readwrite TO dev_user;

CREATE USER report_user WITH PASSWORD 'RptPass_123' LOGIN;
GRANT app_readonly TO report_user;

-- Đổi password
ALTER USER dev_user WITH PASSWORD 'NewPass_456';

-- Vô hiệu hóa user
ALTER USER dev_user NOLOGIN;
ALTER USER dev_user LOGIN;  -- Kích hoạt lại

-- Xem users và quyền
\du+   -- trong psql

SELECT r.rolname, r.rolsuper, r.rolcreatedb, r.rolcanlogin,
       ARRAY(SELECT g.rolname FROM pg_auth_members m
             JOIN pg_roles g ON g.oid = m.roleid
             WHERE m.member = r.oid) AS member_of
FROM pg_roles r
WHERE r.rolname NOT LIKE 'pg_%'
ORDER BY r.rolname;
```

---

## 4. QUẢN LÝ DATABASE, SCHEMA, TABLESPACE

```sql
-- Tạo tablespace trên storage riêng
CREATE TABLESPACE fast_ssd LOCATION '/mnt/nvme/pgdata';

-- Tạo database
CREATE DATABASE myapp_db
  OWNER        = dev_owner
  ENCODING     = 'UTF8'
  LC_COLLATE   = 'en_US.UTF-8'
  LC_CTYPE     = 'en_US.UTF-8'
  TEMPLATE     = template0
  TABLESPACE   = fast_ssd
  CONNECTION LIMIT = 100;

-- Tạo schema
\c myapp_db
CREATE SCHEMA app AUTHORIZATION dev_owner;
CREATE SCHEMA audit;
SET search_path TO app, public;

-- Xem sizes
SELECT datname,
       pg_size_pretty(pg_database_size(datname)) db_size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) total,
       pg_size_pretty(pg_relation_size(schemaname||'.'||tablename))        table_only,
       pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename))         indexes
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog','information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 20;
```

---

## 5. VACUUM & AUTOVACUUM

### 5.1 Hiểu VACUUM trong PostgreSQL

```
PostgreSQL dùng MVCC (Multi-Version Concurrency Control):
- UPDATE/DELETE không xóa row cũ ngay → tạo "dead tuples"
- VACUUM thu hồi space từ dead tuples
- VACUUM FULL: compact table (lock exclusive, không dùng production)
- AUTOVACUUM: tự động chạy background

Triệu chứng cần VACUUM gấp:
- n_dead_tup trong pg_stat_user_tables tăng cao
- Bloat ratio > 20%
- Transaction ID wraparound (CRITICAL!)
```

### 5.2 Manual VACUUM

```sql
-- VACUUM thông thường (không lock, chạy được trong production)
VACUUM orders;
VACUUM ANALYZE orders;  -- + cập nhật statistics

-- VERBOSE để xem chi tiết
VACUUM VERBOSE orders;

-- VACUUM FULL (lock exclusive, giải phóng disk thực sự)
-- CHỈ chạy trong maintenance window!
VACUUM FULL orders;

-- Kiểm tra bloat và dead tuples
SELECT schemaname, relname AS table_name,
       n_live_tup, n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) dead_pct,
       last_vacuum, last_autovacuum,
       last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;

-- Tables cần VACUUM gấp (bloat > 20%)
SELECT schemaname, relname,
       n_dead_tup,
       ROUND(n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) * 100, 1) dead_pct,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) total_size
FROM pg_stat_user_tables
WHERE n_dead_tup > 10000
  AND n_dead_tup::numeric / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1
ORDER BY n_dead_tup DESC;
```

### 5.3 Transaction ID Wraparound — CRITICAL

```sql
-- Kiểm tra wraparound risk (CRITICAL nếu < 10 triệu)
SELECT datname,
       age(datfrozenxid) xid_age,
       2147483648 - age(datfrozenxid) AS xids_remaining,
       CASE
         WHEN age(datfrozenxid) > 1900000000 THEN 'EMERGENCY - VACUUM NOW!'
         WHEN age(datfrozenxid) > 1500000000 THEN 'WARNING - Schedule VACUUM'
         ELSE 'OK'
       END AS status
FROM pg_database
ORDER BY age(datfrozenxid) DESC;

-- Freeze để tránh wraparound
VACUUM FREEZE orders;

-- Autovacuum anti-wraparound đã kick in chưa
SELECT pid, query, state, wait_event_type, wait_event
FROM pg_stat_activity
WHERE query LIKE '%autovacuum%';
```

---

## 6. EXTENSION MANAGEMENT

```sql
-- Cài extension (cần superuser)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS uuid-ossp;
CREATE EXTENSION IF NOT EXISTS pg_trgm;      -- Full-text search
CREATE EXTENSION IF NOT EXISTS postgis;       -- Geo data
CREATE EXTENSION IF NOT EXISTS timescaledb;   -- Time-series

-- Xem extensions đã cài
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;

-- pg_stat_statements — Top queries
SELECT query,
       calls,
       ROUND(total_exec_time::numeric, 2) total_ms,
       ROUND(mean_exec_time::numeric, 2)  avg_ms,
       ROUND(stddev_exec_time::numeric, 2) stddev_ms,
       rows,
       ROUND(100 * total_exec_time / sum(total_exec_time) OVER (), 2) pct
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat%'
ORDER BY total_exec_time DESC
LIMIT 15;
```

---

## 7. MONITORING & DIAGNOSTICS

```sql
-- Active connections
SELECT count(*) total,
       sum(CASE WHEN state = 'active'    THEN 1 ELSE 0 END) active,
       sum(CASE WHEN state = 'idle'      THEN 1 ELSE 0 END) idle,
       sum(CASE WHEN state = 'idle in transaction' THEN 1 ELSE 0 END) idle_in_txn,
       sum(CASE WHEN wait_event_type IS NOT NULL THEN 1 ELSE 0 END) waiting
FROM pg_stat_activity
WHERE pid <> pg_backend_pid();

-- Long-running queries
SELECT pid,
       now() - query_start AS duration,
       state,
       wait_event_type,
       wait_event,
       left(query, 120) query_preview,
       usename,
       application_name
FROM pg_stat_activity
WHERE state != 'idle'
  AND now() - query_start > interval '5 minutes'
ORDER BY duration DESC;

-- Locks và blocking
SELECT blocked_locks.pid     AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid    AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query  AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
  ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
  AND blocking_locks.page     IS NOT DISTINCT FROM blocked_locks.page
  AND blocking_locks.tuple    IS NOT DISTINCT FROM blocked_locks.tuple
  AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
  ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- Kill query
SELECT pg_cancel_backend(pid);   -- Graceful cancel
SELECT pg_terminate_backend(pid); -- Force terminate

-- Cache hit ratio (mục tiêu > 99%)
SELECT sum(heap_blks_read)  disk_reads,
       sum(heap_blks_hit)   cache_hits,
       ROUND(100.0 * sum(heap_blks_hit) /
         NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0), 2) hit_ratio_pct
FROM pg_statio_user_tables;

-- Index usage
SELECT schemaname, relname, indexrelname,
       idx_scan, idx_tup_read, idx_tup_fetch,
       pg_size_pretty(pg_relation_size(indexrelid)) index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC
LIMIT 20;  -- Indexes ít được dùng
```

---

## 8. CONNECTION POOLING — PgBouncer

```ini
# /etc/pgbouncer/pgbouncer.ini

[databases]
myapp_db = host=127.0.0.1 port=5432 dbname=myapp_db

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt

# Pool modes:
# transaction = tốt nhất cho web apps (connection chỉ dùng khi có transaction)
# session     = mỗi client = 1 DB connection (tương đương không pool)
pool_mode = transaction

# Pool sizing
default_pool_size = 25       # Connections per database per user
max_client_conn = 1000       # Tổng client connections tối đa
reserve_pool_size = 5
reserve_pool_timeout = 3

# Timeouts
client_idle_timeout = 60
server_idle_timeout = 600
server_lifetime = 3600

# Logging
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
admin_users = pgbouncer_admin
```

```bash
# userlist.txt — password hashed với pg_md5
# Lấy hash: psql -c "SELECT concat('\"', usename, '\" \"', passwd, '\"') FROM pg_shadow WHERE usename='app_user';"
echo '"app_user" "SCRAM-SHA-256$..."' >> /etc/pgbouncer/userlist.txt

# Start PgBouncer
systemctl enable pgbouncer
systemctl start  pgbouncer

# Monitor PgBouncer
psql -h 127.0.0.1 -p 6432 -U pgbouncer_admin pgbouncer
pgbouncer=# SHOW STATS;
pgbouncer=# SHOW POOLS;
pgbouncer=# SHOW CLIENTS;
pgbouncer=# SHOW SERVERS;

# Reload config không restart
psql -h 127.0.0.1 -p 6432 -U pgbouncer_admin pgbouncer -c "RELOAD;"
```

---

## 9. PERFORMANCE TUNING

```sql
-- EXPLAIN ANALYZE
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM orders o
JOIN customers c ON o.customer_id = c.id
WHERE o.created_at > NOW() - INTERVAL '7 days'
  AND c.region = 'HN';

-- Đọc output:
-- "Seq Scan" trên bảng lớn → cần index
-- "Buffers: shared hit=xxx read=yyy" → read cao = cache miss
-- Rows ước tính vs thực tế lệch nhiều → cần ANALYZE

-- Tạo index thường
CREATE INDEX CONCURRENTLY idx_orders_created
  ON orders(created_at DESC);

-- Partial index (nhỏ hơn, nhanh hơn cho query có điều kiện)
CREATE INDEX CONCURRENTLY idx_orders_active
  ON orders(customer_id, created_at)
  WHERE status = 'ACTIVE';

-- Index trên expression
CREATE INDEX CONCURRENTLY idx_customers_upper_email
  ON customers(LOWER(email));

-- GIN index cho full-text search
CREATE INDEX CONCURRENTLY idx_products_fts
  ON products USING GIN(to_tsvector('english', name || ' ' || description));

-- Query full-text search
SELECT * FROM products
WHERE to_tsvector('english', name || ' ' || description) @@
      to_tsquery('english', 'oracle & database');

-- BRIN index cho time-series (rất nhỏ, tốt cho append-only data)
CREATE INDEX CONCURRENTLY idx_logs_brin
  ON event_logs USING BRIN(event_time)
  WITH (pages_per_range = 128);

-- pg_stat_statements — tìm SQL chậm nhất
SELECT LEFT(query, 100) query_preview,
       calls,
       ROUND(mean_exec_time::numeric, 2) avg_ms,
       ROUND(total_exec_time::numeric / 1000, 2) total_sec
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Reset stats
SELECT pg_stat_reset();
SELECT pg_stat_statements_reset();
```

---

## 10. PSQL COMMANDS QUAN TRỌNG

```sql
-- Meta-commands trong psql
\l          -- List databases
\c myapp    -- Connect to database
\dt         -- List tables
\dt+        -- List tables with size
\di         -- List indexes
\dv         -- List views
\ds         -- List sequences
\df         -- List functions
\du         -- List users/roles
\du+        -- Detailed users/roles
\dn         -- List schemas
\dp orders  -- Show privileges on table
\d orders   -- Describe table
\d+ orders  -- Detailed describe with stats
\e          -- Open query in editor
\timing     -- Toggle query timing
\x          -- Expanded mode (pivot display)
\copy       -- Client-side copy
\i file.sql -- Execute SQL file
\q          -- Quit
\?          -- Help for meta-commands
\h SELECT   -- Help for SQL commands
```

---

**Tài liệu tham khảo:**
- PostgreSQL Documentation: postgresql.org/docs/16/
- PgBouncer Documentation: pgbouncer.org
- www.tranvanbinh.vn
