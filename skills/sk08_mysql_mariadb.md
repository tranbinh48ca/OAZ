---
name: mysql-mariadb-administration
description: >
  MySQL và MariaDB administration, GTID replication, Group Replication, ProxySQL.
  Kích hoạt khi hỏi về: MySQL, MariaDB, quản trị MySQL, cài đặt MySQL,
  my.cnf cấu hình, MySQL backup mysqldump, Percona XtraBackup,
  MySQL replication, master slave MySQL, GTID replication,
  MySQL Group Replication, InnoDB Cluster, ProxySQL,
  MySQL performance, slow query log, EXPLAIN MySQL,
  MySQL indexes, InnoDB buffer pool, MySQL security,
  binary log binlog MySQL, MySQL failover, orchestrator MySQL,
  Galera Cluster MariaDB, MariaDB MaxScale, MariaDB backup.
---

# SK08-MySQL · MySQL & MariaDB Administration

**Phiên bản:** MySQL 8.0, 8.4 LTS, MariaDB 10.6+  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. CÀI ĐẶT & CẤU HÌNH

### 1.1 Cài đặt MySQL 8.0 trên RHEL/OL

```bash
# Thêm MySQL repo
rpm -Uvh https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm

dnf install -y mysql-community-server

systemctl enable mysqld
systemctl start mysqld

# Lấy password tạm
grep 'temporary password' /var/log/mysqld.log

# Secure installation
mysql_secure_installation

# Kết nối
mysql -u root -p
```

### 1.2 Cài đặt MariaDB 10.6

```bash
# RHEL/OL 8
cat > /etc/yum.repos.d/MariaDB.repo << 'EOF'
[mariadb]
name = MariaDB
baseurl = https://downloads.mariadb.com/MariaDB/mariadb-10.6/yum/rhel8-amd64
gpgkey = https://downloads.mariadb.com/MariaDB/RPM-GPG-KEY-MariaDB
gpgcheck = 1
EOF

dnf install -y MariaDB-server MariaDB-client
systemctl enable mariadb && systemctl start mariadb
mysql_secure_installation
```

### 1.3 my.cnf — Cấu hình tối ưu

```ini
# /etc/my.cnf hoặc /etc/mysql/mysql.conf.d/mysqld.cnf

[mysqld]
#── CƠ BẢN ──────────────────────────────────────────────
server_id      = 1               # Unique per server (bắt buộc cho replication)
port           = 3306
socket         = /var/lib/mysql/mysql.sock
datadir        = /var/lib/mysql
pid_file       = /var/run/mysqld/mysqld.pid
bind_address   = 0.0.0.0
max_connections = 300
connect_timeout = 10

#── CHARACTER SET ────────────────────────────────────────
character_set_server  = utf8mb4
collation_server      = utf8mb4_unicode_ci

#── INNODB ──────────────────────────────────────────────
innodb_buffer_pool_size     = 8G     # 70-80% RAM — quan trọng nhất
innodb_buffer_pool_instances = 8      # buffer_pool_size / 1GB
innodb_log_file_size        = 2G     # Bigger = faster writes, slower crash recovery
innodb_log_buffer_size      = 64M
innodb_flush_log_at_trx_commit = 1   # 1=an toàn nhất; 2=nhanh hơn 1 chút; 0=nhanh nhất nhưng có thể mất data
innodb_flush_method         = O_DIRECT
innodb_file_per_table       = ON
innodb_io_capacity          = 2000   # SSD: 2000+, HDD: 200
innodb_io_capacity_max      = 4000
innodb_read_io_threads      = 8
innodb_write_io_threads     = 8
innodb_redo_log_capacity    = 4G     # MySQL 8.0.30+ (thay innodb_log_file_size)

#── REPLICATION ──────────────────────────────────────────
log_bin                     = /var/lib/mysql/binlog
binlog_format               = ROW    # ROW cho GTID, khuyến dùng
binlog_row_image            = MINIMAL
expire_logs_days            = 7      # Xóa binlog cũ hơn 7 ngày
                                     # MySQL 8.0: binlog_expire_logs_seconds = 604800
sync_binlog                 = 1      # 1=sync mỗi commit (an toàn nhất)
gtid_mode                   = ON
enforce_gtid_consistency     = ON
log_replica_updates         = ON     # Propagate replication events (chain)

#── LOGGING ─────────────────────────────────────────────
general_log                 = 0      # Tắt production (tốn I/O)
slow_query_log              = 1
slow_query_log_file         = /var/log/mysql/slow.log
long_query_time             = 1      # Log query > 1 giây
log_queries_not_using_indexes = 1
min_examined_row_limit      = 100
log_error                   = /var/log/mysql/error.log

#── PERFORMANCE SCHEMA ───────────────────────────────────
performance_schema          = ON

#── QUERY CACHE (MySQL 5.7 — TẮTỞ 8.0) ─────────────────
# query_cache_type = 0  # Đã bị remove khỏi MySQL 8.0

#── TEMP TABLES ──────────────────────────────────────────
tmp_table_size              = 256M
max_heap_table_size         = 256M

#── CONNECTIONS ──────────────────────────────────────────
wait_timeout                = 28800   # 8 giờ — idle connection timeout
interactive_timeout         = 28800
max_allowed_packet          = 64M
thread_cache_size           = 16
```

---

## 2. QUẢN LÝ USER VÀ PRIVILEGES

```sql
-- Tạo user
CREATE USER 'app_user'@'192.168.1.%'
  IDENTIFIED BY 'AppPass_123'
  REQUIRE SSL;                -- Bắt buộc SSL

-- Cấp quyền
GRANT SELECT, INSERT, UPDATE, DELETE
  ON myapp.* TO 'app_user'@'192.168.1.%';

-- Cấp quyền stored procedures
GRANT EXECUTE ON myapp.* TO 'app_user'@'192.168.1.%';

-- Cấp quyền read-only
GRANT SELECT ON myapp.* TO 'report_user'@'192.168.1.%';

-- Cấp quyền admin (cẩn thận!)
GRANT ALL PRIVILEGES ON *.* TO 'admin_user'@'localhost' WITH GRANT OPTION;

FLUSH PRIVILEGES;

-- Đổi password
ALTER USER 'app_user'@'192.168.1.%'
  IDENTIFIED BY 'NewPass_456';

-- Xóa user
DROP USER 'old_user'@'%';

-- Xem privileges
SHOW GRANTS FOR 'app_user'@'192.168.1.%';

-- Xem tất cả users
SELECT user, host, account_locked, password_expired
FROM mysql.user
WHERE user NOT IN ('mysql.infoschema','mysql.session','mysql.sys')
ORDER BY user, host;
```

---

## 3. BACKUP & RESTORE

### 3.1 mysqldump

```bash
# Backup toàn bộ database
mysqldump \
  --single-transaction \   # Consistent snapshot (InnoDB)
  --routines \             # Include stored procedures/functions
  --events \               # Include events
  --triggers \             # Include triggers
  --all-databases \
  --master-data=2 \        # Ghi binlog position vào comment (cho replication)
  -u root -p | \
  gzip > /backup/mysql_all_$(date +%Y%m%d).sql.gz

# Backup một database
mysqldump \
  --single-transaction \
  --routines --events --triggers \
  -u root -p myapp | \
  gzip > /backup/myapp_$(date +%Y%m%d).sql.gz

# Backup một table
mysqldump -u root -p myapp orders \
  --single-transaction \
  --no-create-info \  # Chỉ data, không DDL
  > /backup/orders.sql

# Backup structure only (schema)
mysqldump -u root -p --no-data myapp > /backup/myapp_schema.sql

# Restore
mysql -u root -p myapp < /backup/myapp_20260101.sql
# Restore từ gzip
gunzip < /backup/myapp_20260101.sql.gz | mysql -u root -p myapp

# Restore từ all databases
gunzip < /backup/mysql_all_20260101.sql.gz | mysql -u root -p
```

### 3.2 Percona XtraBackup (Hot Backup)

```bash
# Cài đặt
dnf install -y percona-xtrabackup-80  # Cho MySQL 8.0

# Full backup
xtrabackup \
  --backup \
  --target-dir=/backup/xtrabackup/full/ \
  --user=root \
  --password=RootPass_123

# Incremental backup
xtrabackup \
  --backup \
  --target-dir=/backup/xtrabackup/inc1/ \
  --incremental-basedir=/backup/xtrabackup/full/ \
  --user=root --password=RootPass_123

# Prepare (apply logs để consistent)
xtrabackup --prepare --target-dir=/backup/xtrabackup/full/
xtrabackup --prepare --target-dir=/backup/xtrabackup/full/ \
  --incremental-dir=/backup/xtrabackup/inc1/

# Restore
systemctl stop mysqld
rm -rf /var/lib/mysql/*
xtrabackup --copy-back --target-dir=/backup/xtrabackup/full/
chown -R mysql:mysql /var/lib/mysql
systemctl start mysqld
```

---

## 4. GTID REPLICATION

### 4.1 Kiến trúc

```
Global Transaction Identifier (GTID):
  Format: server_uuid:transaction_id
  Ví dụ: 6b7b8a9c-1234-5678-abcd-ef0123456789:1-1000

PRIMARY → REPLICA1 (GTID-based, auto-position)
        → REPLICA2

Lợi ích so với binlog position:
  ✓ Failover đơn giản hơn (không cần MASTER_LOG_FILE, MASTER_LOG_POS)
  ✓ Multi-source replication dễ hơn
  ✓ Kiểm tra consistency dễ hơn
```

### 4.2 Cấu hình GTID Replication

```ini
# my.cnf trên PRIMARY (server_id=1)
server_id = 1
gtid_mode = ON
enforce_gtid_consistency = ON
log_bin = binlog
binlog_format = ROW
log_replica_updates = ON

# my.cnf trên REPLICA (server_id=2)
server_id = 2
gtid_mode = ON
enforce_gtid_consistency = ON
log_bin = binlog
binlog_format = ROW
log_replica_updates = ON
read_only = ON              # Replica không nhận writes trực tiếp
super_read_only = ON        # Ngay cả SUPER user cũng không write
```

```sql
-- Trên PRIMARY: tạo replication user
CREATE USER 'replicator'@'192.168.1.%'
  IDENTIFIED BY 'ReplPass_123'
  REQUIRE SSL;
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'192.168.1.%';

-- Backup Primary để init Replica
mysqldump \
  --single-transaction \
  --master-data=2 \         # Ghi GTID position
  --set-gtid-purged=ON \    # Include GTID info
  --all-databases \
  -u root -p > /tmp/primary_backup.sql

-- Trên REPLICA: restore backup
mysql -u root -p < /tmp/primary_backup.sql

-- Cấu hình replication (GTID auto-position)
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = '192.168.1.10',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'replicator',
  SOURCE_PASSWORD = 'ReplPass_123',
  SOURCE_AUTO_POSITION = 1,   -- GTID mode
  SOURCE_SSL = 1,
  SOURCE_SSL_CA = '/etc/mysql/ssl/ca.pem',
  SOURCE_SSL_CERT = '/etc/mysql/ssl/client-cert.pem',
  SOURCE_SSL_KEY = '/etc/mysql/ssl/client-key.pem',
  GET_SOURCE_PUBLIC_KEY = 1;

START REPLICA;

-- Kiểm tra replication
SHOW REPLICA STATUS\G
-- Quan trọng:
-- Replica_IO_Running: Yes
-- Replica_SQL_Running: Yes
-- Seconds_Behind_Source: 0
-- Retrieved_Gtid_Set: ...
-- Executed_Gtid_Set: ...
```

### 4.3 Monitoring và Troubleshooting

```sql
-- Replication status summary
SELECT
  CHANNEL_NAME,
  SERVICE_STATE AS io_running,
  (SELECT SERVICE_STATE FROM performance_schema.replication_applier_status
   WHERE CHANNEL_NAME = s.CHANNEL_NAME) AS sql_running,
  RECEIVED_TRANSACTION_SET AS received_gtids
FROM performance_schema.replication_connection_status s;

-- Lag in seconds
SELECT TIMESTAMPDIFF(
  SECOND,
  MIN(APPLYING_TRANSACTION_ORIGINAL_COMMIT_TIMESTAMP),
  NOW()
) AS lag_seconds
FROM performance_schema.replication_applier_status_by_worker
WHERE APPLYING_TRANSACTION != '';

-- Xem GTID executed
SELECT @@global.gtid_executed;
SELECT @@global.gtid_purged;

-- Fix replication error (skip specific GTID)
-- Cẩn thận: chỉ skip nếu chắc chắn không mất data
STOP REPLICA SQL_THREAD;
SET @@session.gtid_next = '6b7b8a9c-1234-5678-abcd-ef0123456789:999';
BEGIN; COMMIT;  -- Empty transaction để consume GTID này
SET @@session.gtid_next = AUTOMATIC;
START REPLICA SQL_THREAD;
```

---

## 5. GROUP REPLICATION (InnoDB Cluster)

### 5.1 Kiến trúc

```
                    ┌─────────────────────────────────┐
                    │   MySQL Shell / MySQL Router     │
                    └──────────────┬──────────────────┘
          ┌───────────────────────┼────────────────────┐
          ▼                       ▼                    ▼
    ┌──────────┐          ┌──────────┐          ┌──────────┐
    │ node1    │◄────────►│ node2    │◄────────►│ node3    │
    │ PRIMARY  │  Paxos   │ SECONDARY│  Paxos   │ SECONDARY│
    │ (R/W)    │ protocol │ (RO)     │          │ (RO)     │
    └──────────┘          └──────────┘          └──────────┘
```

### 5.2 Cài đặt MySQL InnoDB Cluster

```bash
# Cài MySQL Shell
dnf install -y mysql-shell

# Trên mỗi node, chuẩn bị
mysqlsh -- dba configure-instance {
  "host": "localhost",
  "port": 3306,
  "user": "root",
  "password": "RootPass_123"
}
```

```javascript
// Trong MySQL Shell (JS mode)

// Tạo cluster từ node1
var cluster = dba.createCluster('myapp_cluster', {
  multiPrimary: false,
  gtidSetIsComplete: true,
  memberWeight: 50
});

// Thêm nodes
cluster.addInstance('root@node2:3306', {
  password: 'RootPass_123',
  recoveryMethod: 'clone'     // Tự động clone từ Primary
});

cluster.addInstance('root@node3:3306', {
  password: 'RootPass_123',
  recoveryMethod: 'clone'
});

// Kiểm tra cluster
cluster.status();
cluster.describe();

// Switchover
cluster.setPrimaryInstance('node2:3306');

// Rejoin node sau khi restart
cluster.rejoinInstance('node3:3306');

// Rescan sau khi thay đổi
cluster.rescan();
```

### 5.3 MySQL Router

```bash
# Bootstrap Router (điều hướng connections)
mysqlrouter --bootstrap root@node1:3306 \
  --directory /etc/mysqlrouter \
  --user mysqlrouter \
  --force

systemctl enable mysqlrouter
systemctl start mysqlrouter

# Router tạo 4 ports:
# 6446: R/W (Primary)
# 6447: R-only (round-robin Secondaries)
# 6448: R/W via classic protocol
# 6449: R-only via classic protocol

# Application kết nối:
# Writes: mysql://user:pass@router-host:6446/myapp
# Reads:  mysql://user:pass@router-host:6447/myapp
```

---

## 6. ProxySQL

### 6.1 Cài đặt và cấu hình

```bash
# Cài ProxySQL
cat > /etc/yum.repos.d/proxysql.repo << 'EOF'
[proxysql_repo]
name= ProxySQL
baseurl=https://repo.proxysql.com/ProxySQL/proxysql-2.x/centos/latest/
gpgcheck=1
gpgkey=https://repo.proxysql.com/ProxySQL/repo_pub_key
EOF
dnf install -y proxysql

systemctl enable proxysql && systemctl start proxysql

# Kết nối admin interface
mysql -u admin -padmin -h 127.0.0.1 -P6032
```

```sql
-- Cấu hình MySQL servers
INSERT INTO mysql_servers (hostgroup_id, hostname, port, weight) VALUES
  (10, 'node1', 3306, 1000),   -- hostgroup 10 = Writer
  (20, 'node1', 3306, 1000),   -- hostgroup 20 = Reader (backup)
  (20, 'node2', 3306, 1000),   -- hostgroup 20 = Reader
  (20, 'node3', 3306, 1000);   -- hostgroup 20 = Reader

-- Cấu hình user
INSERT INTO mysql_users (username, password, default_hostgroup, transaction_persistent) VALUES
  ('app_user', 'AppPass_123', 10, 1);  -- Mặc định vào Writer group

-- Query rules: tự động route read sang Readers
-- SELECT → hostgroup 20 (readers)
INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
  (1, 1, '^SELECT .* FOR UPDATE', 10, 1),   -- SELECT FOR UPDATE → Writer
  (2, 1, '^SELECT',               20, 1);   -- SELECT → Readers

-- Cấu hình monitor
SET mysql-monitor_username = 'monitor';
SET mysql-monitor_password = 'MonitorPass_123';
SET mysql-monitor_ping_interval = 2000;
SET mysql-monitor_read_only_interval = 1500;

-- Apply config
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL USERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
LOAD MYSQL VARIABLES TO RUNTIME;

-- Lưu vào disk (persistent)
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL USERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
SAVE MYSQL VARIABLES TO DISK;

-- Monitor status
SELECT * FROM mysql_server_group_replication_log ORDER BY time_start_us DESC LIMIT 10;
SELECT * FROM stats_mysql_global;
SELECT * FROM stats_mysql_query_rules;
```

### 6.2 Tạo monitor user trên MySQL

```sql
-- Trên MySQL Primary:
CREATE USER 'monitor'@'%' IDENTIFIED BY 'MonitorPass_123';
GRANT USAGE ON *.* TO 'monitor'@'%';
GRANT REPLICATION CLIENT ON *.* TO 'monitor'@'%';
```

---

## 7. PERFORMANCE MONITORING

```sql
-- InnoDB Buffer Pool hit ratio (phải > 99%)
SELECT
  variable_name,
  variable_value
FROM performance_schema.global_status
WHERE variable_name IN (
  'Innodb_buffer_pool_reads',
  'Innodb_buffer_pool_read_requests'
);

-- Tính hit ratio
SELECT
  ROUND(100 * (1 - (
    (SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_reads') /
    NULLIF((SELECT variable_value FROM performance_schema.global_status WHERE variable_name = 'Innodb_buffer_pool_read_requests'), 0)
  )), 2) AS buffer_pool_hit_ratio_pct;

-- Top queries từ Performance Schema
SELECT
  LEFT(DIGEST_TEXT, 100) AS query_template,
  COUNT_STAR AS executions,
  ROUND(SUM_TIMER_WAIT / 1e12, 2) AS total_sec,
  ROUND(AVG_TIMER_WAIT / 1e9, 2)  AS avg_ms,
  ROUND(MAX_TIMER_WAIT / 1e9, 2)  AS max_ms,
  SUM_ROWS_EXAMINED,
  SUM_ROWS_SENT
FROM performance_schema.events_statements_summary_by_digest
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 15;

-- Table I/O stats
SELECT
  object_schema,
  object_name,
  count_read,
  count_write,
  ROUND(sum_timer_read / 1e12, 2)  AS read_sec,
  ROUND(sum_timer_write / 1e12, 2) AS write_sec
FROM performance_schema.table_io_waits_summary_by_table
WHERE object_schema NOT IN ('mysql','performance_schema','information_schema')
ORDER BY (sum_timer_read + sum_timer_write) DESC
LIMIT 15;

-- Slow query log analysis
-- Dùng mysqldumpslow:
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log
# -s t: sort by query time, -t 10: top 10

-- Dùng pt-query-digest (Percona Toolkit)
pt-query-digest /var/log/mysql/slow.log > /tmp/digest_report.txt
```

---

## 8. MARIADB GALERA CLUSTER

```ini
# /etc/mysql/mariadb.conf.d/galera.cnf

[mysqld]
binlog_format               = ROW
innodb_autoinc_lock_mode    = 2    # Bắt buộc cho Galera
wsrep_on                    = ON
wsrep_provider              = /usr/lib/galera/libgalera_smm.so
wsrep_cluster_name          = "galera_cluster"
wsrep_cluster_address       = "gcomm://node1,node2,node3"  # Tất cả nodes
wsrep_node_name             = "node1"                        # Tên node này
wsrep_node_address          = "192.168.1.11"
wsrep_sst_method            = mariabackup    # Snapshot Transfer
wsrep_sst_auth              = sst_user:SSTPass_123
wsrep_slave_threads         = 4
wsrep_causal_reads          = ON
wsrep_sync_wait             = 1
```

```bash
# Bootstrap cluster (chỉ lần đầu, từ node1)
galera_new_cluster

# Các nodes khác join
systemctl start mariadb  # Sẽ tự join cluster

# Kiểm tra cluster
mysql -u root -p -e "SHOW STATUS LIKE 'wsrep%';"
# wsrep_cluster_size: 3
# wsrep_local_state_comment: Synced
# wsrep_ready: ON
```

---

**Tài liệu tham khảo:**
- MySQL 8.0 Reference: dev.mysql.com/doc/refman/8.0/
- MySQL InnoDB Cluster: dev.mysql.com/doc/mysql-shell/8.0/en/mysql-innodb-cluster.html
- ProxySQL Documentation: proxysql.com/documentation/
- Galera Cluster: galeracluster.com/documentation/
- Percona XtraBackup: percona.com/software/mysql-database/percona-xtrabackup
- www.tranvanbinh.vn
