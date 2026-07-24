---
name: postgresql-replication-ha
description: >
  PostgreSQL Replication và High Availability với Patroni.
  Kích hoạt khi hỏi về: PostgreSQL replication, streaming replication,
  physical replication, logical replication, standby PostgreSQL,
  hot standby, warm standby, read replica PostgreSQL,
  replication slot, wal_sender, wal_receiver, replication lag PG,
  Patroni, Patroni failover, Patroni switchover, etcd PostgreSQL HA,
  pg_rewind, high availability PostgreSQL, HA PostgreSQL,
  promote standby PostgreSQL, failover PostgreSQL, HAProxy PostgreSQL,
  publication subscription logical replication PostgreSQL.
---

# SK08-PG03 · PostgreSQL Replication & High Availability

**Phiên bản:** PostgreSQL 14, 15, 16, 17  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. STREAMING REPLICATION

### 1.1 Kiến trúc

```
PRIMARY ──[WAL stream]──► STANDBY (Hot Standby — read-only)
                │
                └──[WAL stream]──► STANDBY 2 (Cascading)

Synchronous: Primary chờ Standby confirm trước khi commit
Asynchronous: Primary không chờ (tốt hơn performance, có thể mất data)
```

### 1.2 Cấu hình Primary

```ini
# postgresql.conf trên Primary
listen_addresses = '*'
wal_level = replica
max_wal_senders = 5             # Số replication connections tối đa
max_replication_slots = 5       # Số replication slots
wal_keep_size = 1024            # MB — giữ WAL phòng khi standby chậm
hot_standby = on                # Cho phép read trên standby

# Synchronous replication (optional — zero data loss)
# synchronous_standby_names = 'FIRST 1 (standby1, standby2)'
# synchronous_commit = on
```

```
# pg_hba.conf trên Primary
host    replication    replicator    192.168.1.0/24    scram-sha-256
```

```sql
-- Tạo replication user
CREATE USER replicator WITH REPLICATION PASSWORD 'ReplPass_123';

-- Tạo replication slot (optional nhưng khuyến dùng)
-- Slot đảm bảo WAL không bị xóa trước khi standby nhận
SELECT pg_create_physical_replication_slot('standby1_slot');

-- Xem replication slots
SELECT slot_name, slot_type, active, restart_lsn
FROM pg_replication_slots;
```

### 1.3 Tạo Standby từ pg_basebackup

```bash
# Trên Standby server — dừng PostgreSQL trước
systemctl stop postgresql-16

# Xóa data directory cũ
rm -rf /var/lib/postgresql/16/main

# Clone từ Primary
sudo -u postgres pg_basebackup \
  -h 192.168.1.10 \      # Primary IP
  -U replicator \
  -D /var/lib/postgresql/16/main \
  -Fp \                  # Format plain
  -Xs \                  # Stream WAL
  -R \                   # Tạo recovery config tự động
  -S standby1_slot \     # Dùng replication slot
  --checkpoint=fast \
  -P -v
# -R tự động tạo standby.signal và postgresql.auto.conf

# Kiểm tra file được tạo
cat /var/lib/postgresql/16/main/postgresql.auto.conf
# Sẽ thấy: primary_conninfo = 'host=192.168.1.10 ...'
ls /var/lib/postgresql/16/main/standby.signal  # File này = standby mode

# Cấu hình thêm cho standby
cat >> /var/lib/postgresql/16/main/postgresql.conf << 'EOF'
# Standby settings
hot_standby = on
hot_standby_feedback = on    # Thông báo active queries để tránh conflict
wal_receiver_status_interval = 10s
wal_receiver_timeout = 60s
recovery_min_apply_delay = 0  # Delay apply (0 = không delay)
                               # Có thể set 30min để có "delayed standby"
EOF

# Start Standby
systemctl start postgresql-16
```

### 1.4 Monitoring Replication

```sql
-- Trên PRIMARY: xem replication connections
SELECT pid,
       client_addr,
       state,                        -- streaming / catchup
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       write_lag,
       flush_lag,
       replay_lag,                   -- ← Lag quan trọng nhất
       sync_state                    -- sync / async
FROM pg_stat_replication;

-- Trên STANDBY: kiểm tra đang nhận WAL
SELECT status,           -- streaming
       receive_start_lsn,
       received_lsn,
       last_msg_send_time,
       last_msg_receipt_time,
       latest_end_lsn
FROM pg_stat_wal_receiver;

-- Tính lag theo byte
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Tính lag theo thời gian (trên Standby)
SELECT now() - pg_last_xact_replay_timestamp() AS replication_delay;

-- Kiểm tra Standby đang apply
SELECT pg_is_in_recovery();  -- TRUE = standby mode

-- Xem replication slots
SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag
FROM pg_replication_slots;
```

### 1.5 Failover Thủ công (Không có Patroni)

```bash
# PROMOTE STANDBY thành Primary

# Cách 1: pg_ctl promote (PG 12 trở về trước)
sudo -u postgres pg_ctl promote -D /var/lib/postgresql/16/main

# Cách 2: pg_promote() function (PG 12+)
psql -U postgres -c "SELECT pg_promote();"

# Kiểm tra sau promote
psql -U postgres -c "SELECT pg_is_in_recovery();"  -- Phải trả về FALSE
psql -U postgres -c "SELECT pg_current_wal_lsn();" -- Phải có giá trị

# Cập nhật connection string của application → trỏ vào Standby mới
```

### 1.6 pg_rewind — Tái đồng bộ Primary cũ

```bash
# Sau failover, Primary cũ có diverged timeline
# pg_rewind đồng bộ lại để làm Standby mới

systemctl stop postgresql-16  # Dừng Primary cũ

# Rewind
sudo -u postgres pg_rewind \
  --target-pgdata=/var/lib/postgresql/16/main \
  --source-server="host=new-primary-ip user=postgres"

# Tạo standby.signal
touch /var/lib/postgresql/16/main/standby.signal

# Cấu hình primary_conninfo
cat >> /var/lib/postgresql/16/main/postgresql.auto.conf << 'EOF'
primary_conninfo = 'host=new-primary-ip port=5432 user=replicator password=ReplPass_123'
EOF

# Start làm Standby
systemctl start postgresql-16
```

---

## 2. LOGICAL REPLICATION (14+)

```sql
-- Logical replication: chọn lọc tables, cross-version, cross-platform

-- Trên PUBLISHER (Source):
-- Cấu hình: wal_level = logical

-- Tạo publication
CREATE PUBLICATION myapp_pub
  FOR TABLE orders, customers, products;  -- Chỉ định tables

-- Hoặc cho toàn database
CREATE PUBLICATION myapp_pub FOR ALL TABLES;

-- Xem publications
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;

-- Trên SUBSCRIBER (Target):
-- Tạo tables với schema tương tự

CREATE SUBSCRIPTION myapp_sub
  CONNECTION 'host=source-host dbname=myapp_db user=replicator password=ReplPass_123'
  PUBLICATION myapp_pub;

-- Kiểm tra subscription
SELECT subname, subenabled, subslotname
FROM pg_subscription;

SELECT * FROM pg_stat_subscription;

-- Refresh sau khi thêm table vào publication
ALTER SUBSCRIPTION myapp_sub REFRESH PUBLICATION;

-- Enable/disable subscription
ALTER SUBSCRIPTION myapp_sub DISABLE;
ALTER SUBSCRIPTION myapp_sub ENABLE;
```

---

## 3. PATRONI — HIGH AVAILABILITY

### 3.1 Kiến trúc Patroni

```
                    ┌─────────────────────────────┐
                    │   DCS (Distributed Config)  │
                    │   etcd / Consul / ZooKeeper  │
                    └────────────┬────────────────┘
                                 │ Quorum / Leader election
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
   ┌──────────┐            ┌──────────┐            ┌──────────┐
   │ Patroni  │            │ Patroni  │            │ Patroni  │
   │   node1  │            │   node2  │            │   node3  │
   │[PRIMARY] │            │[STANDBY] │            │[STANDBY] │
   │ PG:5432  │            │ PG:5432  │            │ PG:5432  │
   └──────────┘            └──────────┘            └──────────┘
         ▲
         │ HAProxy/Keepalived
   VIP: 192.168.1.100:5432  ← Application connects here
```

### 3.2 Cài đặt etcd (3 nodes)

```bash
# Cài etcd trên 3 nodes
dnf install -y etcd

# /etc/etcd/etcd.conf trên node1
ETCD_NAME="etcd1"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_LISTEN_PEER_URLS="http://192.168.1.11:2380"
ETCD_LISTEN_CLIENT_URLS="http://192.168.1.11:2379,http://127.0.0.1:2379"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.1.11:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.1.11:2379"
ETCD_INITIAL_CLUSTER_TOKEN="pg-ha-cluster"
ETCD_INITIAL_CLUSTER="etcd1=http://192.168.1.11:2380,etcd2=http://192.168.1.12:2380,etcd3=http://192.168.1.13:2380"
ETCD_INITIAL_CLUSTER_STATE="new"

systemctl enable etcd && systemctl start etcd

# Kiểm tra
etcdctl endpoint health
etcdctl member list
```

### 3.3 Cài đặt Patroni

```bash
# Cài đặt
pip3 install patroni[etcd]

# Hoặc từ package
dnf install -y patroni patroni-etcd
```

```yaml
# /etc/patroni/patroni.yml trên node1

scope: pg-ha-cluster
namespace: /db/
name: pg-node1

restapi:
  listen: 0.0.0.0:8008
  connect_address: 192.168.1.11:8008

etcd3:
  hosts: 192.168.1.11:2379,192.168.1.12:2379,192.168.1.13:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576      # 1MB lag max
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_connections: 200
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 1024
        archive_mode: "on"
        archive_command: "cp %p /backup/wal_archive/%f"
        checkpoint_completion_target: 0.9
        shared_buffers: 4GB
        effective_cache_size: 12GB
        work_mem: 64MB

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - host replication replicator 0.0.0.0/0 scram-sha-256
    - host all all 0.0.0.0/0 scram-sha-256

  users:
    admin:
      password: Admin_1234
      options:
        - createrole
        - createdb

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.1.11:5432
  data_dir: /var/lib/postgresql/16/main
  bin_dir: /usr/pgsql-16/bin
  pgpass: /tmp/pgpass

  authentication:
    replication:
      username: replicator
      password: ReplPass_123
    superuser:
      username: postgres
      password: Postgres_1234

  parameters:
    max_connections: 200
    shared_buffers: 4GB
    logging_collector: "on"
    log_directory: "/var/log/postgresql"

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
```

### 3.4 Khởi động và vận hành Patroni

```bash
# Start Patroni trên tất cả nodes
systemctl enable patroni
systemctl start patroni

# Kiểm tra cluster status
patronictl -c /etc/patroni/patroni.yml list

# Output mẫu:
# + Cluster: pg-ha-cluster (7890123456789) +---------+----+-----------+
# | Member    | Host          | Role    | State   | TL | Lag in MB |
# +-----------+---------------+---------+---------+----+-----------+
# | pg-node1  | 192.168.1.11  | Leader  | running |  1 |           |
# | pg-node2  | 192.168.1.12  | Replica | running |  1 |         0 |
# | pg-node3  | 192.168.1.13  | Replica | running |  1 |         0 |
# +-----------+---------------+---------+---------+----+-----------+
```

### 3.5 Patroni Operations

```bash
# SWITCHOVER (planned — zero downtime)
patronictl -c /etc/patroni/patroni.yml switchover \
  --master pg-node1 \
  --candidate pg-node2 \
  --scheduled now \
  --force

# FAILOVER (unplanned — khi leader down)
patronictl -c /etc/patroni/patroni.yml failover \
  pg-ha-cluster \
  --master pg-node1 \    # Node đang down
  --candidate pg-node2 \ # Node muốn promote
  --force

# Reinitialize node (khi node bị diverged)
patronictl -c /etc/patroni/patroni.yml reinit pg-ha-cluster pg-node3

# Pause cluster (maintenance)
patronictl -c /etc/patroni/patroni.yml pause pg-ha-cluster

# Resume
patronictl -c /etc/patroni/patroni.yml resume pg-ha-cluster

# Xem config
patronictl -c /etc/patroni/patroni.yml show-config

# Thay đổi config cluster (không cần restart)
patronictl -c /etc/patroni/patroni.yml edit-config pg-ha-cluster

# Xem history switchover/failover
patronictl -c /etc/patroni/patroni.yml history pg-ha-cluster

# Restart postgres trên 1 node
patronictl -c /etc/patroni/patroni.yml restart pg-ha-cluster pg-node2

# Reload config trên tất cả
patronictl -c /etc/patroni/patroni.yml reload pg-ha-cluster
```

### 3.6 HAProxy cho Load Balancing

```ini
# /etc/haproxy/haproxy.cfg

global
    maxconn 10000
    log /dev/log local0

defaults
    log global
    retries 2
    timeout client 30m
    timeout connect 4s
    timeout server 30m
    timeout check 5s

# PRIMARY — Read/Write
listen pg_primary
    bind *:5000
    mode tcp
    option httpchk GET /primary   # Patroni REST API check
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 192.168.1.11:5432 maxconn 100 check port 8008
    server pg-node2 192.168.1.12:5432 maxconn 100 check port 8008
    server pg-node3 192.168.1.13:5432 maxconn 100 check port 8008

# STANDBYS — Read Only
listen pg_standbys
    bind *:5001
    mode tcp
    balance roundrobin
    option httpchk GET /replica   # Patroni chỉ healthy nếu là replica
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg-node1 192.168.1.11:5432 maxconn 100 check port 8008
    server pg-node2 192.168.1.12:5432 maxconn 100 check port 8008
    server pg-node3 192.168.1.13:5432 maxconn 100 check port 8008

# HAProxy Stats
listen stats
    bind *:7000
    stats enable
    stats uri /haproxy
    stats refresh 10s
```

```bash
systemctl enable haproxy && systemctl start haproxy

# Application kết nối:
# Read/Write: postgresql://app:pass@haproxy-vip:5000/myapp
# Read Only:  postgresql://app:pass@haproxy-vip:5001/myapp
```

---

## 4. MONITORING REPLICATION

```bash
# Script monitoring replication lag
cat > /usr/local/bin/check_pg_replication.sh << 'SCRIPT'
#!/bin/bash
MAX_LAG_MB=10   # Alert khi lag > 10MB
ALERT_EMAIL="dba@company.com"

# Kiểm tra lag
LAG_BYTES=$(psql -U postgres -t -A -c "
  SELECT COALESCE(
    pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn),
    0
  ) FROM pg_stat_replication LIMIT 1;")

LAG_MB=$((${LAG_BYTES:-0} / 1024 / 1024))

echo "Replication lag: ${LAG_MB} MB"

if [ "${LAG_MB}" -gt "$MAX_LAG_MB" ]; then
  echo "⚠️ ALERT: Replication lag ${LAG_MB}MB > threshold ${MAX_LAG_MB}MB" | \
    mail -s "ALERT: PG Replication Lag" $ALERT_EMAIL
fi
SCRIPT
chmod +x /usr/local/bin/check_pg_replication.sh

# Cron mỗi 5 phút
echo "*/5 * * * * postgres /usr/local/bin/check_pg_replication.sh" >> /etc/crontab
```

---

**Tài liệu tham khảo:**
- PostgreSQL Replication: postgresql.org/docs/16/high-availability.html
- Patroni Documentation: patroni.readthedocs.io
- pg_rewind: postgresql.org/docs/16/app-pgrewind.html
- www.tranvanbinh.vn
