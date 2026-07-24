---
name: mongodb-administration
description: >
  MongoDB administration, Replica Set và Sharding.
  Kích hoạt khi hỏi về: MongoDB, quản trị MongoDB, MongoDB admin,
  cài đặt MongoDB, mongod, mongosh, replica set MongoDB,
  MongoDB replication, primary secondary arbiter,
  initiate replica set, MongoDB failover, rs.stepDown,
  MongoDB sharding, shard key, chunk, mongos, config server,
  horizontal scaling MongoDB, MongoDB backup mongodump,
  MongoDB restore mongorestore, Atlas backup MongoDB,
  MongoDB performance, aggregation pipeline, explain MongoDB,
  index MongoDB, compound index MongoDB, MongoDB security,
  authentication MongoDB, role MongoDB, TLS MongoDB,
  MongoDB monitoring, mongostat mongotop, Atlas monitoring.
---

# SK08-MongoDB · MongoDB Administration

**Phiên bản:** MongoDB 6.0, 7.0, 8.0  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. CÀI ĐẶT MONGODB

### 1.1 MongoDB 7.0 trên RHEL/OL 8

```bash
# Thêm repo
cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/8/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
EOF

dnf install -y mongodb-org

systemctl enable mongod
systemctl start mongod

# Kết nối với mongosh
mongosh

# Kiểm tra version
db.version()
```

### 1.2 mongod.conf — Cấu hình

```yaml
# /etc/mongod.conf

systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

storage:
  dbPath: /var/lib/mongo
  journal:
    enabled: true
  engine: wiredTiger    # Default engine
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4    # Mặc định 50% RAM - 1GB; thường để mặc định
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy
    indexConfig:
      prefixCompression: true

net:
  port: 27017
  bindIp: 0.0.0.0      # Bind tất cả interfaces
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/ssl/mongodb/mongod.pem
    CAFile: /etc/ssl/mongodb/ca.pem

security:
  authorization: enabled
  keyFile: /etc/mongodb/keyfile  # Cho Replica Set auth

replication:
  replSetName: "rs0"             # Uncomment khi setup Replica Set

#operationProfiling:
#  slowOpThresholdMs: 100        # Log queries > 100ms
#  mode: slowOp
```

---

## 2. QUẢN LÝ CƠ BẢN

### 2.1 Database & Collection Operations

```javascript
// ── Kết nối và navigation
mongosh "mongodb://admin:pass@host:27017/admin"

// Xem databases
show dbs
use myapp          // Switch database
show collections   // Xem collections

// Tạo user admin (lần đầu — khi chưa có auth)
use admin
db.createUser({
  user: "admin",
  pwd: passwordPrompt(),  // Hỏi password
  roles: [{ role: "userAdminAnyDatabase", db: "admin" },
          { role: "readWriteAnyDatabase", db: "admin" }]
})

// Tạo user cho application
use myapp
db.createUser({
  user: "app_user",
  pwd: "AppPass_123",
  roles: [{ role: "readWrite", db: "myapp" }]
})

// Tạo collection với schema validation
db.createCollection("orders", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["order_id", "customer_id", "status", "created_at"],
      properties: {
        order_id:    { bsonType: "string" },
        customer_id: { bsonType: "string" },
        status:      { 
          bsonType: "string",
          enum: ["pending","processing","completed","cancelled"]
        },
        amount:      { bsonType: "double", minimum: 0 },
        created_at:  { bsonType: "date" }
      }
    }
  },
  validationAction: "error"  // error = reject, warn = log và accept
})

// CRUD Operations
// Insert
db.orders.insertOne({
  order_id: "ORD-001",
  customer_id: "CUST-001",
  status: "pending",
  amount: 150000,
  items: [
    { product: "Oracle DBA Course", qty: 1, price: 150000 }
  ],
  created_at: new Date()
})

db.orders.insertMany([...])

// Find
db.orders.find({ status: "pending" }).limit(10).sort({ created_at: -1 })
db.orders.findOne({ order_id: "ORD-001" })
db.orders.countDocuments({ status: "completed" })

// Update
db.orders.updateOne(
  { order_id: "ORD-001" },
  { $set: { status: "processing", updated_at: new Date() } }
)

db.orders.updateMany(
  { status: "pending", created_at: { $lt: new Date("2026-01-01") } },
  { $set: { status: "cancelled" } }
)

// Delete
db.orders.deleteOne({ order_id: "ORD-001" })
db.orders.deleteMany({ status: "cancelled", created_at: { $lt: new Date("2025-01-01") } })

// Aggregation Pipeline
db.orders.aggregate([
  { $match: { status: "completed", created_at: { $gte: new Date("2026-01-01") } } },
  { $group: {
    _id: "$customer_id",
    total_orders: { $sum: 1 },
    total_amount: { $sum: "$amount" },
    avg_amount:   { $avg: "$amount" }
  }},
  { $sort: { total_amount: -1 } },
  { $limit: 10 }
])
```

### 2.2 Index Management

```javascript
// Tạo indexes
db.orders.createIndex({ customer_id: 1 })                         // Single field
db.orders.createIndex({ status: 1, created_at: -1 })              // Compound
db.orders.createIndex({ customer_id: 1 }, { unique: true })       // Unique
db.orders.createIndex({ created_at: 1 }, { expireAfterSeconds: 7776000 })  // TTL (90 days)
db.orders.createIndex({ "$**": "text" })                          // Text search
db.orders.createIndex({ location: "2dsphere" })                   // Geo

// Tạo index ở background (không block operations — MongoDB < 4.2)
// MongoDB 4.2+: mặc định hybrid build, không block
db.orders.createIndex({ amount: -1 }, { background: true })

// Xem indexes
db.orders.getIndexes()
db.orders.indexStats()  // Stats về usage

// Xóa index
db.orders.dropIndex("status_1_created_at_-1")

// Explain — xem query plan
db.orders.find({ status: "pending" }).explain("executionStats")
// Tìm: "IXSCAN" (index) vs "COLLSCAN" (full scan)
// Kiểm tra: "totalDocsExamined" vs "nReturned" — ratio gần 1 = tốt

// Kiểm tra slow queries
db.setProfilingLevel(1, { slowms: 100 })  // Profile queries > 100ms
db.system.profile.find().sort({ ts: -1 }).limit(10)
```

---

## 3. REPLICA SET

### 3.1 Kiến trúc Replica Set

```
                  ┌────────────────────────────────┐
                  │          Replica Set "rs0"     │
                  │                                │
         Write ──►│  ┌─────────┐  ┌─────────┐  ┌─────────┐ │
         Read  ──►│  │ PRIMARY │  │SECONDARY│  │SECONDARY│ │
                  │  │ node1   │◄►│  node2  │◄►│  node3  │ │
                  │  │:27017   │  │ :27017  │  │ :27017  │ │
                  │  └─────────┘  └─────────┘  └─────────┘ │
                  │                                         │
                  │  Optional: ARBITER (vote only, no data)  │
                  └────────────────────────────────────────┘
```

### 3.2 Khởi tạo Replica Set

```bash
# Cấu hình /etc/mongod.conf trên tất cả nodes:
# replication:
#   replSetName: "rs0"

# Khởi động mongod trên tất cả nodes
systemctl restart mongod

# Tạo keyfile cho internal auth
openssl rand -base64 756 > /etc/mongodb/keyfile
chmod 400 /etc/mongodb/keyfile
chown mongod:mongod /etc/mongodb/keyfile
# Copy keyfile sang tất cả nodes
```

```javascript
// Kết nối vào node1, khởi tạo replica set
mongosh --host node1:27017

rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "node1:27017", priority: 2 },     // Higher priority = ưu tiên làm Primary
    { _id: 1, host: "node2:27017", priority: 1 },
    { _id: 2, host: "node3:27017", priority: 1,
      hidden: false, slaveDelay: 0 }                   // Delayed member: slaveDelay: 3600 (1 giờ)
  ]
})

// Hoặc thêm từng member:
rs.add("node2:27017")
rs.add({ host: "node3:27017", priority: 0, votes: 0 }) // Hidden secondary
rs.addArb("node4:27017")  // Arbiter (chỉ vote, không có data)

// Kiểm tra status
rs.status()    // Tình trạng tổng thể
rs.conf()      // Cấu hình hiện tại
rs.isMaster()  // Primary?
```

### 3.3 Monitoring Replica Set

```javascript
// Status và lag
rs.status()
// Tìm: stateStr: "PRIMARY" / "SECONDARY" / "RECOVERING"
// optime: timestamp của operation cuối cùng

// Tính replication lag
rs.printReplicationInfo()        // Trên Primary — info về oplog
rs.printSecondaryReplicationInfo()  // Trên Secondary — lag info

// Oplog info
use local
db.oplog.rs.stats()
db.oplog.rs.find().sort({ $natural: -1 }).limit(5)

// Xem lag từ Primary
db.adminCommand("replSetGetStatus").members.forEach(m => {
  if (m.stateStr === "SECONDARY") {
    print(`${m.name}: lag = ${m.optimeDate - rs.status().members[0].optimeDate}ms`);
  }
})
```

### 3.4 Failover và Operations

```javascript
// Stepdown Primary (trigger election)
rs.stepDown(60)  // 60 giây before eligible lại

// Force member thành Primary (cẩn thận!)
// Tăng priority của member muốn thành Primary
cfg = rs.conf()
cfg.members[1].priority = 10
rs.reconfig(cfg)
// Member có priority cao nhất sẽ được elect sau 10 giây

// Freeze một member (không thể thành Primary trong N giây)
rs.freeze(300)  // 300 giây

// Maintenance mode (cho phép read từ này khi đang sync)
db.adminCommand({ replSetMaintenance: 1 })  // Bật
db.adminCommand({ replSetMaintenance: 0 })  // Tắt

// Xóa member
cfg = rs.conf()
cfg.members = cfg.members.filter(m => m.host !== "old-node:27017")
rs.reconfig(cfg)

// Read từ Secondary (readPreference)
// Connection string:
// mongodb://user:pass@node1,node2,node3/myapp?replicaSet=rs0&readPreference=secondaryPreferred

// Từ mongosh:
db.orders.find({ status: "completed" }).readPref("secondary")
```

---

## 4. SHARDING

### 4.1 Kiến trúc Sharding

```
Application
    │
    ▼
┌─────────────────┐
│   mongos Router │  (Query routing)
└────────┬────────┘
         │
    ┌────┴────────────────────────────┐
    │ Config Servers (Replica Set)   │  (Metadata: chunk locations)
    └────┬────────────────────────────┘
         │
    ┌────┼──────────────┬──────────────┐
    ▼    ▼              ▼              ▼
  Shard 0            Shard 1        Shard 2
  (Replica Set)      (Replica Set)  (Replica Set)
  node0a,0b,0c       node1a,1b,1c   node2a,2b,2c
```

### 4.2 Setup Sharded Cluster

```bash
# Bước 1: Config Servers (Replica Set riêng)
# mongod.conf cho config servers:
# sharding:
#   clusterRole: configsvr
# replication:
#   replSetName: "configReplSet"
```

```javascript
// Trên config server rs, khởi tạo
mongosh --port 27019
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "config1:27019" },
    { _id: 1, host: "config2:27019" },
    { _id: 2, host: "config3:27019" }
  ]
})
```

```bash
# Bước 2: Shard Servers (mỗi shard là 1 Replica Set)
# mongod.conf cho shards:
# sharding:
#   clusterRole: shardsvr

# Bước 3: mongos (Query Router)
# mongos.conf:
# sharding:
#   configDB: configReplSet/config1:27019,config2:27019,config3:27019
```

```javascript
// Bước 4: Thêm shards vào cluster (từ mongos)
mongosh --port 27017  // Kết nối mongos

sh.addShard("shard0/shard0a:27018,shard0b:27018,shard0c:27018")
sh.addShard("shard1/shard1a:27018,shard1b:27018,shard1c:27018")
sh.addShard("shard2/shard2a:27018,shard2b:27018,shard2c:27018")

// Bước 5: Enable sharding trên database
sh.enableSharding("myapp")

// Bước 6: Shard collection với shard key
// QUAN TRỌNG: Chọn shard key đúng ảnh hưởng performance toàn cluster

// Hashed sharding (phân tán đều, tốt cho high cardinality, nhưng range query tệ hơn)
sh.shardCollection("myapp.orders", { "customer_id": "hashed" })

// Ranged sharding (tốt cho range queries, có thể hot spot)
sh.shardCollection("myapp.events", { "created_at": 1, "region": 1 })

// Compound hashed (tốt cho nhiều trường hợp — MongoDB 4.4+)
sh.shardCollection("myapp.sessions", { "user_id": "hashed", "created_at": 1 })
```

### 4.3 Quản lý Sharding

```javascript
// Xem trạng thái cluster
sh.status()
sh.status({ verbose: true })

// Xem chunk distribution
db.adminCommand({ listShards: 1 })

// Xem chunks cho một collection
use config
db.chunks.find({ ns: "myapp.orders" }).count()
db.chunks.aggregate([
  { $match: { ns: "myapp.orders" } },
  { $group: { _id: "$shard", chunks: { $sum: 1 } } },
  { $sort: { chunks: -1 } }
])

// Enable/disable balancer
sh.stopBalancer()
sh.startBalancer()
sh.isBalancerRunning()

// Kiểm tra migration history
db.changelog.find({ what: "moveChunk.commit" }).sort({ time: -1 }).limit(10)

// Zone sharding (geographic distribution)
// Thêm zone cho shard
sh.addShardToZone("shard0", "HN")   // Hà Nội
sh.addShardToZone("shard1", "HCM")  // Hồ Chí Minh

// Gán zone range cho collection
sh.addTagRange(
  "myapp.orders",
  { region: "HN",  _id: MinKey },
  { region: "HN",  _id: MaxKey },
  "HN"
)
sh.addTagRange(
  "myapp.orders",
  { region: "HCM", _id: MinKey },
  { region: "HCM", _id: MaxKey },
  "HCM"
)
```

---

## 5. BACKUP & RESTORE

### 5.1 mongodump / mongorestore

```bash
# Backup toàn bộ
mongodump \
  --uri "mongodb://admin:pass@host:27017" \
  --out /backup/mongodb/$(date +%Y%m%d) \
  --gzip \
  --numParallelCollections=4

# Backup một database
mongodump \
  --uri "mongodb://admin:pass@host:27017/myapp" \
  --out /backup/myapp_$(date +%Y%m%d) \
  --gzip

# Backup một collection
mongodump \
  --uri "mongodb://admin:pass@host:27017/myapp" \
  --collection orders \
  --out /backup/orders_$(date +%Y%m%d) \
  --gzip

# Backup với oplog (point-in-time cho Replica Set)
mongodump \
  --uri "mongodb://admin:pass@host:27017" \
  --oplog \    # Include oplog for consistent point-in-time
  --out /backup/mongodb_oplog_$(date +%Y%m%d) \
  --gzip

# Restore
mongorestore \
  --uri "mongodb://admin:pass@host:27017" \
  --gzip \
  --numParallelCollections=4 \
  --drop \     # Drop existing collections trước khi restore
  /backup/mongodb/20260101/

# Restore với oplog replay
mongorestore \
  --uri "mongodb://admin:pass@host:27017" \
  --oplogReplay \
  --gzip \
  /backup/mongodb_oplog_20260101/

# Restore một collection
mongorestore \
  --uri "mongodb://admin:pass@host:27017/myapp" \
  --collection orders \
  --gzip \
  /backup/orders_20260101/myapp/orders.bson.gz
```

### 5.2 Atlas Backup (Cloud)

```javascript
// Cloud Manager / Ops Manager
// Point-in-time restore từ Atlas:
// Atlas UI → Backup → Point in Time Restore → Select timestamp

// Programmatic restore via Atlas API
// (Dùng Atlas Data API hoặc Atlas Admin API)
```

---

## 6. PERFORMANCE TUNING

```javascript
// Profiler — log slow operations
db.setProfilingLevel(2)    // Level 0: off, 1: slow ops, 2: all
db.setProfilingLevel(1, { slowms: 50 })  // Log > 50ms

// Xem profiled operations
db.system.profile.find().sort({ ts: -1 }).limit(20)

// Tìm slow aggregations
db.system.profile.find({
  "command.aggregate": { $exists: true },
  millis: { $gt: 100 }
}).sort({ ts: -1 })

// Explain aggregation
db.orders.aggregate([...]).explain("executionStats")

// currentOp — xem operations đang chạy
db.currentOp({ active: true, secs_running: { $gt: 5 } })

// killOp — kill một operation
db.killOp(opId)

// Server status
db.serverStatus().connections    // Connection count
db.serverStatus().opcounters     // Operations per type
db.serverStatus().wiredTiger.cache  // Cache stats

// Collection stats
db.orders.stats()
db.orders.stats().wiredTiger.cache  // WiredTiger cache info

// Index statistics
db.orders.aggregate([{ $indexStats: {} }])
```

---

## 7. SECURITY

```javascript
// Tạo users với specific roles
use admin
db.createUser({
  user: "dba_user",
  pwd: "DBAPass_123",
  roles: [
    { role: "clusterAdmin", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" }
  ]
})

// Custom role
use myapp
db.createRole({
  role: "orderReader",
  privileges: [
    {
      resource: { db: "myapp", collection: "orders" },
      actions: ["find"]
    }
  ],
  roles: []
})

db.createUser({
  user: "report_user",
  pwd: "ReportPass_123",
  roles: [{ role: "orderReader", db: "myapp" }]
})

// Xem users và roles
db.getUsers()
db.getRoles()
use admin
db.system.users.find()

// Audit logging (MongoDB Enterprise)
// mongod.conf:
// auditLog:
//   destination: file
//   format: JSON
//   path: /var/log/mongodb/audit.json
//   filter: '{ atype: { $in: ["authenticate", "createUser", "dropUser"] } }'
```

---

## 8. MONITORING

```bash
# mongostat — real-time server stats
mongostat --uri "mongodb://admin:pass@host:27017" --all 5

# mongotop — per-collection read/write time
mongotop --uri "mongodb://admin:pass@host:27017" 5

# Output mongostat:
# insert query update delete getmore command dirty used flushes
# *0     *0    *0     *0      0       2|0     0.5% 68.1%   0
```

```javascript
// Atlas / Cloud monitoring
// Metrics: Operations per second, Query targeting ratio, Cache usage

// Free monitoring (community)
db.enableFreeMonitoring()  // Returns URL to access metrics

// Health check script
const status = db.adminCommand({ replSetGetStatus: 1 })
const myMember = status.members.find(m => m.self)
if (!myMember) throw new Error("Not in replica set!")
if (myMember.health !== 1) throw new Error(`Member unhealthy: ${myMember.stateStr}`)
print(`OK: ${myMember.stateStr}, optimeDate: ${myMember.optimeDate}`)

// Replication lag script
const primary = status.members.find(m => m.stateStr === "PRIMARY")
const secondaries = status.members.filter(m => m.stateStr === "SECONDARY")
secondaries.forEach(s => {
  const lagSec = (primary.optime.ts.t - s.optime.ts.t)
  print(`${s.name}: lag = ${lagSec}s`)
  if (lagSec > 60) print(`WARNING: High lag on ${s.name}!`)
})
```

---

**Tài liệu tham khảo:**
- MongoDB Manual: docs.mongodb.com/manual/
- Replica Set: docs.mongodb.com/manual/replication/
- Sharding: docs.mongodb.com/manual/sharding/
- MongoDB Atlas: docs.atlas.mongodb.com/
- www.tranvanbinh.vn
