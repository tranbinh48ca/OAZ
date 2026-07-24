---
name: sqlserver-administration
description: >
  SQL Server administration, AlwaysOn Availability Groups, Query Store.
  Kích hoạt khi hỏi về: SQL Server, MSSQL, quản trị SQL Server,
  SQL Server backup restore, AlwaysOn Availability Groups, AG,
  SQL Server Always On, synchronous asynchronous replica,
  AG listener failover, Query Store SQL Server, query regression,
  plan forcing SQL Server, SQL Server Agent jobs, maintenance plans,
  SQL Server performance, DMV dynamic management views,
  SQL Server index optimization, tempdb SQL Server,
  SQL Server replication, log shipping, database mail,
  SQL Server security, transparent data encryption MSSQL,
  SQL Server monitoring, wait stats SQL Server.
---

# SK08-MSSQL · SQL Server Administration

**Phiên bản:** SQL Server 2016, 2017, 2019, 2022  
**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

## 1. QUẢN TRỊ CƠ BẢN SQL SERVER

### 1.1 Startup & Shutdown

```bash
# Linux (SQL Server 2017+)
systemctl start  mssql-server
systemctl stop   mssql-server
systemctl status mssql-server

# Windows — PowerShell
Start-Service MSSQLSERVER
Stop-Service MSSQLSERVER -Force

# Kết nối
sqlcmd -S localhost -U sa -P "YourPass_123"
sqlcmd -S "server\instance" -E  # Windows Authentication
```

### 1.2 Database Operations

```sql
-- Tạo database
CREATE DATABASE myapp
ON PRIMARY (
  NAME = N'myapp_data',
  FILENAME = N'/var/opt/mssql/data/myapp.mdf',
  SIZE = 1GB,
  MAXSIZE = UNLIMITED,
  FILEGROWTH = 256MB
)
LOG ON (
  NAME = N'myapp_log',
  FILENAME = N'/var/opt/mssql/data/myapp_log.ldf',
  SIZE = 256MB,
  MAXSIZE = 4GB,
  FILEGROWTH = 64MB
);

-- Multiple filegroups (tốt cho performance)
ALTER DATABASE myapp ADD FILEGROUP FG_HISTORY;
ALTER DATABASE myapp ADD FILE (
  NAME = N'myapp_history',
  FILENAME = N'/var/opt/mssql/data/myapp_history.ndf',
  SIZE = 5GB, FILEGROWTH = 1GB
) TO FILEGROUP FG_HISTORY;

-- Kiểm tra database
SELECT name, database_id, state_desc,
       recovery_model_desc, log_reuse_wait_desc,
       is_read_only, user_access_desc
FROM sys.databases
ORDER BY name;

-- Xem size
SELECT name, type_desc,
       ROUND(size * 8.0 / 1024, 2) size_mb,
       physical_name
FROM sys.master_files
WHERE database_id = DB_ID('myapp');

-- Shrink log file (sau khi backup transaction log)
USE myapp;
BACKUP LOG myapp TO DISK = N'/backup/myapp_log.bak';
DBCC SHRINKFILE (N'myapp_log', 1);

-- Offline / Online database
ALTER DATABASE myapp SET OFFLINE WITH ROLLBACK IMMEDIATE;
ALTER DATABASE myapp SET ONLINE;
```

---

## 2. BACKUP & RESTORE

### 2.1 Backup Strategy

```sql
-- Full Backup
BACKUP DATABASE myapp
TO DISK = N'/backup/myapp_full_20260101.bak'
WITH
  COMPRESSION,
  CHECKSUM,
  STATS = 10,
  NAME = N'myapp-Full Backup 2026-01-01';

-- Differential Backup (từ Full gần nhất)
BACKUP DATABASE myapp
TO DISK = N'/backup/myapp_diff_20260101.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10;

-- Transaction Log Backup (recovery model FULL hoặc BULK_LOGGED)
BACKUP LOG myapp
TO DISK = N'/backup/myapp_log_20260101_1200.bak'
WITH COMPRESSION, CHECKSUM, STATS = 10;

-- Striped backup (nhanh hơn với nhiều files)
BACKUP DATABASE myapp
TO DISK = N'/backup/myapp_1.bak',
   DISK = N'/backup/myapp_2.bak',
   DISK = N'/backup/myapp_3.bak',
   DISK = N'/backup/myapp_4.bak'
WITH COMPRESSION, CHECKSUM, STATS = 10;

-- Copy-only backup (không ảnh hưởng backup chain)
BACKUP DATABASE myapp
TO DISK = N'/backup/myapp_copyonly.bak'
WITH COPY_ONLY, COMPRESSION;

-- Verify backup
RESTORE VERIFYONLY FROM DISK = N'/backup/myapp_full_20260101.bak'
WITH CHECKSUM;
```

### 2.2 Restore

```sql
-- Kiểm tra backup contents
RESTORE HEADERONLY FROM DISK = N'/backup/myapp_full_20260101.bak';
RESTORE FILELISTONLY FROM DISK = N'/backup/myapp_full_20260101.bak';

-- Restore Full
RESTORE DATABASE myapp
FROM DISK = N'/backup/myapp_full_20260101.bak'
WITH
  MOVE N'myapp_data' TO N'/var/opt/mssql/data/myapp.mdf',
  MOVE N'myapp_log'  TO N'/var/opt/mssql/data/myapp_log.ldf',
  NORECOVERY,  -- Chưa mở DB, chờ apply differential/log
  REPLACE,
  STATS = 10;

-- Apply Differential
RESTORE DATABASE myapp
FROM DISK = N'/backup/myapp_diff_20260101.bak'
WITH NORECOVERY, STATS = 10;

-- Apply Transaction Logs (sequence từ trước đến target time)
RESTORE LOG myapp
FROM DISK = N'/backup/myapp_log_20260101_0800.bak'
WITH NORECOVERY;

RESTORE LOG myapp
FROM DISK = N'/backup/myapp_log_20260101_1200.bak'
WITH
  STOPAT = N'2026-01-01 11:30:00',  -- PITR
  RECOVERY;  -- Mở DB

-- Kiểm tra sau restore
SELECT name, state_desc, recovery_model_desc FROM sys.databases WHERE name = 'myapp';
SELECT GETDATE();
```

---

## 3. ALWAYS ON AVAILABILITY GROUPS

### 3.1 Kiến trúc

```
                  Windows Server Failover Cluster (WSFC)
              ┌─────────────────────────────────────────┐
              │  AG Listener: ag-listener,1433           │
              │  ┌─────────────┐    ┌─────────────┐     │
              │  │  node1      │    │  node2      │     │
              │  │  [PRIMARY]  │◄──►│  [SECONDARY]│     │
              │  │  Sync/Async │    │  Sync/Async │     │
              │  └─────────────┘    └─────────────┘     │
              └─────────────────────────────────────────┘
```

### 3.2 Cài đặt AlwaysOn AG

```sql
-- Bước 1: Enable AlwaysOn trên tất cả nodes
-- PowerShell:
-- Enable-SqlAlwaysOn -Path SQLSERVER:\SQL\node1\DEFAULT -Force

-- Bước 2: Tạo AG (trên PRIMARY)
CREATE AVAILABILITY GROUP [AG_myapp]
WITH (
  AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
  DB_FAILOVER = ON,
  DTC_SUPPORT = NONE,
  REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0
)
FOR
  DATABASE myapp, myapp_reports  -- Các DBs trong AG
REPLICA ON
  N'node1' WITH (
    ENDPOINT_URL      = N'TCP://node1.domain.local:5022',
    FAILOVER_MODE     = AUTOMATIC,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,    -- Sync = zero data loss
    BACKUP_PRIORITY   = 50,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)
  ),
  N'node2' WITH (
    ENDPOINT_URL      = N'TCP://node2.domain.local:5022',
    FAILOVER_MODE     = AUTOMATIC,
    AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
    BACKUP_PRIORITY   = 50,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY)  -- Read-only replica
  ),
  N'node3' WITH (
    ENDPOINT_URL      = N'TCP://node3.domain.local:5022',
    FAILOVER_MODE     = MANUAL,
    AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,   -- Async = DR site
    BACKUP_PRIORITY   = 80,
    SECONDARY_ROLE(ALLOW_CONNECTIONS = READ_ONLY)
  );

-- Bước 3: Tạo Listener
ALTER AVAILABILITY GROUP [AG_myapp]
ADD LISTENER N'ag-listener' (
  WITH IP ((N'192.168.1.100', N'255.255.255.0')),
  PORT = 1433
);

-- Bước 4: Join Secondary nodes (chạy trên từng Secondary)
ALTER AVAILABILITY GROUP [AG_myapp] JOIN;
ALTER DATABASE myapp SET HADR AVAILABILITY GROUP = [AG_myapp];
```

### 3.3 Monitoring AlwaysOn

```sql
-- Dashboard summary
SELECT ag.name ag_name,
       ar.replica_server_name,
       ar.availability_mode_desc,
       ar.failover_mode_desc,
       ars.role_desc,
       ars.operational_state_desc,
       ars.synchronization_health_desc,
       ars.log_send_queue_size,   -- KB chờ gửi
       ars.redo_queue_size,       -- KB chờ apply
       ars.log_send_rate,         -- KB/s
       ars.redo_rate              -- KB/s
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
ORDER BY ag.name, ars.role_desc DESC;

-- Database-level health
SELECT ag.name ag_name,
       d.name db_name,
       drs.synchronization_state_desc,
       drs.synchronization_health_desc,
       drs.redo_queue_size,
       drs.redo_rate,
       drs.log_send_queue_size,
       drs.log_send_rate,
       drs.last_commit_time,
       drs.end_of_log_lsn
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.availability_groups ag ON ar.group_id = ag.group_id
JOIN sys.databases d ON drs.database_id = d.database_id
ORDER BY ag.name, d.name;

-- Estimated lag (secondaries)
SELECT replica_server_name,
       database_name,
       secondary_lag_seconds
FROM sys.dm_hadr_database_replica_cluster_states cs
JOIN sys.dm_hadr_database_replica_states rs ON cs.replica_id = rs.replica_id
JOIN sys.availability_replicas ar ON rs.replica_id = ar.replica_id;
```

### 3.4 Failover Operations

```sql
-- Manual Failover (Planned — zero data loss, sync only)
ALTER AVAILABILITY GROUP [AG_myapp] FAILOVER;

-- Forced Failover (Unplanned — có thể mất data)
ALTER AVAILABILITY GROUP [AG_myapp] FORCE_FAILOVER_ALLOW_DATA_LOSS;

-- Kiểm tra sau failover
SELECT replica_server_name, role_desc
FROM sys.dm_hadr_availability_replica_states ars
JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id;

-- Offline một secondary replica tạm thời
ALTER AVAILABILITY GROUP [AG_myapp]
MODIFY REPLICA ON N'node3'
WITH (AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT);

-- Suspend / Resume data movement
ALTER DATABASE myapp SET HADR SUSPEND;
ALTER DATABASE myapp SET HADR RESUME;
```

### 3.5 Backup từ Secondary

```sql
-- Backup từ Secondary (giảm tải Primary)
-- Đặt backup preference = SECONDARY trong AG definition

-- T-SQL: Kiểm tra đang chạy trên primary hay secondary
IF (SELECT ars.role_desc
    FROM sys.dm_hadr_availability_replica_states ars
    JOIN sys.availability_replicas ar ON ars.replica_id = ar.replica_id
    JOIN sys.availability_databases_cluster adc ON ar.group_id = adc.group_id
    WHERE adc.database_name = DB_NAME()
      AND ars.is_local = 1) = 'PRIMARY'
BEGIN
  PRINT 'Running on PRIMARY - skip backup, let secondary handle';
  RETURN;
END;

BACKUP DATABASE myapp
TO DISK = N'/backup/myapp_secondary.bak'
WITH COMPRESSION, COPY_ONLY;
```

---

## 4. QUERY STORE

### 4.1 Enable và Cấu hình

```sql
-- Enable Query Store
ALTER DATABASE myapp SET QUERY_STORE = ON;

-- Cấu hình Query Store
ALTER DATABASE myapp SET QUERY_STORE (
  OPERATION_MODE         = READ_WRITE,
  CLEANUP_POLICY         = (STALE_QUERY_THRESHOLD_DAYS = 30),
  DATA_FLUSH_INTERVAL_SECONDS = 900,      -- Flush vào disk mỗi 15 phút
  MAX_STORAGE_SIZE_MB    = 1000,
  INTERVAL_LENGTH_MINUTES = 60,           -- Collection interval
  SIZE_BASED_CLEANUP_MODE = AUTO,
  QUERY_CAPTURE_MODE     = AUTO,          -- ALL | AUTO | NONE
  MAX_PLANS_PER_QUERY    = 200
);

-- Xem config
SELECT * FROM sys.database_query_store_options;
```

### 4.2 Top Queries Analysis

```sql
-- Top queries by CPU time (last 24h)
SELECT TOP 20
  q.query_id,
  qt.query_sql_text,
  rs.avg_cpu_time / 1000.0             avg_cpu_ms,
  rs.avg_duration / 1000.0            avg_duration_ms,
  rs.avg_logical_io_reads              avg_logical_reads,
  rs.avg_physical_io_reads             avg_physical_reads,
  rs.count_executions                  executions,
  p.plan_id,
  TRY_CAST(p.query_plan AS XML)        execution_plan
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p ON q.query_id = p.query_id
JOIN sys.query_store_runtime_stats rs ON p.plan_id = rs.plan_id
JOIN sys.query_store_runtime_stats_interval rsi ON rs.runtime_stats_interval_id = rsi.runtime_stats_interval_id
WHERE rsi.start_time > DATEADD(HOUR, -24, GETDATE())
ORDER BY rs.avg_cpu_time DESC;

-- Queries có plan regression (plan thay đổi và tệ hơn)
SELECT
  q.query_id,
  qt.query_sql_text,
  p1.plan_id AS regressed_plan,
  p2.plan_id AS recommended_plan,
  rs1.avg_duration AS regressed_duration,
  rs2.avg_duration AS recommended_duration
FROM sys.query_store_query q
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
JOIN sys.query_store_plan p1 ON q.query_id = p1.query_id
JOIN sys.query_store_plan p2 ON q.query_id = p2.query_id
JOIN sys.query_store_runtime_stats rs1 ON p1.plan_id = rs1.plan_id
JOIN sys.query_store_runtime_stats rs2 ON p2.plan_id = rs2.plan_id
WHERE rs1.avg_duration > rs2.avg_duration * 2   -- regressed plan > 2x slower
  AND p1.plan_id != p2.plan_id
ORDER BY (rs1.avg_duration - rs2.avg_duration) DESC;
```

### 4.3 Plan Forcing

```sql
-- Force plan (tốt nhất để fix regression ngay lập tức)
EXEC sp_query_store_force_plan
  @query_id = 1234,
  @plan_id  = 5678;

-- Unforce plan
EXEC sp_query_store_unforce_plan
  @query_id = 1234,
  @plan_id  = 5678;

-- Xem các plans đang bị force
SELECT q.query_id, qt.query_sql_text,
       p.plan_id, p.is_forced_plan
FROM sys.query_store_plan p
JOIN sys.query_store_query q ON p.query_id = q.query_id
JOIN sys.query_store_query_text qt ON q.query_text_id = qt.query_text_id
WHERE p.is_forced_plan = 1;

-- Automatic Plan Correction (SQL Server 2017+)
ALTER DATABASE myapp SET AUTOMATIC_TUNING (FORCE_LAST_GOOD_PLAN = ON);

-- Xem recommendations từ Automatic Tuning
SELECT *
FROM sys.dm_db_tuning_recommendations
WHERE state = 'Active'
ORDER BY score DESC;
```

---

## 5. PERFORMANCE MONITORING

```sql
-- Top Wait Stats
SELECT wait_type,
       waiting_tasks_count,
       ROUND(wait_time_ms / 1000.0, 2) wait_time_sec,
       ROUND(100.0 * wait_time_ms / SUM(wait_time_ms) OVER(), 2) pct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
  'SLEEP_TASK','HADR_FILESTREAM_IOMGR_IOCOMPLETION',
  'BROKER_TO_FLUSH','BROKER_TASK_STOP','LOGMGR_QUEUE',
  'CHECKPOINT_QUEUE','REQUEST_FOR_DEADLOCK_MONITOR',
  'DBMIRROR_EVENTS_QUEUE','BROKER_EVENTHANDLER',
  'SQLTRACE_BUFFER_FLUSH','CLR_AUTO_EVENT',
  'DISPATCHER_QUEUE_SEMAPHORE','FT_IFTS_SCHEDULER_IDLE_WAIT',
  'XE_DISPATCHER_WAIT','XE_TIMER_EVENT',
  'WAITFOR','LAZYWRITER_SLEEP','SLEEP_DBSTARTUP',
  'SLEEP_DCOMSTARTUP','SLEEP_MASTERDBREADY','SLEEP_MASTERMDREADY',
  'SLEEP_MASTERUPGRADED','SLEEP_MSDBSTARTUP','SLEEP_SYSTEMTASK',
  'SLEEP_TEMPDBSTARTUP','SNI_HTTP_ACCEPT','SP_SERVER_DIAGNOSTICS_SLEEP',
  'SQLTRACE_INCREMENTAL_FLUSH_SLEEP','WAITFOR_TASKSHUTDOWN',
  'WAIT_XTP_HOST_WAIT','WAIT_XTP_OFFLINE_CKPT_NEW_LOG')
ORDER BY wait_time_ms DESC;

-- Active requests và blocking
SELECT r.session_id,
       r.status,
       r.blocking_session_id,
       r.wait_type,
       r.wait_time / 1000.0 wait_sec,
       r.cpu_time / 1000.0  cpu_sec,
       r.total_elapsed_time / 1000.0 elapsed_sec,
       DB_NAME(r.database_id) db_name,
       LEFT(t.text, 100) query_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
ORDER BY r.total_elapsed_time DESC;

-- Missing Indexes
SELECT TOP 20
  mig.index_group_handle,
  mid.index_handle,
  ROUND(migs.avg_total_user_cost * migs.avg_user_impact * (migs.user_seeks + migs.user_scans), 0)
    AS improvement_measure,
  'CREATE INDEX idx_' + OBJECT_NAME(mid.object_id) + '_' +
    REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns,'') + '_' +
                           ISNULL(mid.inequality_columns,''), '[',''), ']',''), ',','_')
    AS create_index_statement,
  mid.equality_columns,
  mid.inequality_columns,
  mid.included_columns,
  migs.user_seeks,
  migs.user_scans
FROM sys.dm_db_missing_index_groups mig
JOIN sys.dm_db_missing_index_group_stats migs ON mig.index_group_handle = migs.group_handle
JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY improvement_measure DESC;

-- TempDB usage
SELECT session_id,
       ROUND(user_objects_alloc_page_count * 8.0 / 1024, 2) user_obj_mb,
       ROUND(internal_objects_alloc_page_count * 8.0 / 1024, 2) internal_obj_mb,
       ROUND(task_alloc_page_count * 8.0 / 1024, 2) task_mb
FROM sys.dm_db_session_space_usage
WHERE session_id > 50
  AND user_objects_alloc_page_count + internal_objects_alloc_page_count > 0
ORDER BY (user_objects_alloc_page_count + internal_objects_alloc_page_count) DESC;
```

---

## 6. SQL SERVER AGENT JOBS

```sql
-- Tạo Job backup hàng đêm
USE msdb;
EXEC sp_add_job
  @job_name = N'Nightly Full Backup - myapp';

EXEC sp_add_jobstep
  @job_name = N'Nightly Full Backup - myapp',
  @step_name = N'Full Backup',
  @subsystem = N'TSQL',
  @command = N'BACKUP DATABASE myapp
    TO DISK = N''/backup/myapp_full_'' + CONVERT(NVARCHAR, GETDATE(), 112) + ''.bak''
    WITH COMPRESSION, CHECKSUM, STATS = 10;',
  @on_success_action = 1,
  @on_fail_action = 2;

EXEC sp_add_schedule
  @schedule_name = N'Daily 02:00',
  @freq_type = 4,           -- Daily
  @freq_interval = 1,
  @active_start_time = 20000;  -- 02:00:00

EXEC sp_attach_schedule
  @job_name = N'Nightly Full Backup - myapp',
  @schedule_name = N'Daily 02:00';

EXEC sp_add_jobserver
  @job_name = N'Nightly Full Backup - myapp';

-- Xem jobs
SELECT j.name, j.enabled,
       jh.run_date, jh.run_time, jh.run_duration,
       jh.message,
       CASE jh.run_status
         WHEN 0 THEN 'Failed'
         WHEN 1 THEN 'Succeeded'
         WHEN 2 THEN 'Retry'
         WHEN 3 THEN 'Cancelled'
       END AS status
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobhistory jh ON j.job_id = jh.job_id
WHERE jh.step_id = 0  -- Overall job result
ORDER BY jh.run_date DESC, jh.run_time DESC;
```

---

## 7. SECURITY

```sql
-- Transparent Data Encryption (TDE)
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'MasterKey_123!';
CREATE CERTIFICATE MyServerCert WITH SUBJECT = 'TDE Certificate';

USE myapp;
CREATE DATABASE ENCRYPTION KEY
  WITH ALGORITHM = AES_256
  ENCRYPTION BY SERVER CERTIFICATE MyServerCert;
ALTER DATABASE myapp SET ENCRYPTION ON;

-- Kiểm tra TDE status
SELECT name, is_encrypted FROM sys.databases;
SELECT percent_complete, estimated_completion_time
FROM sys.dm_database_encryption_keys
WHERE encryption_state != 3;  -- 3 = fully encrypted

-- Database roles
CREATE ROLE db_app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO db_app_readwrite;

CREATE USER app_user FOR LOGIN app_login;
ALTER ROLE db_app_readwrite ADD MEMBER app_user;

-- Row-Level Security
CREATE SCHEMA Security;
GO

CREATE FUNCTION Security.tvf_securitypredicate(@tenant_id AS INTEGER)
  RETURNS TABLE
  WITH SCHEMABINDING
AS
  RETURN SELECT 1 AS tvf_securitypredicate_result
  WHERE @tenant_id = CAST(SESSION_CONTEXT(N'tenant_id') AS INTEGER)
    OR IS_MEMBER('db_owner') = 1;
GO

CREATE SECURITY POLICY Security.TenantFilter
  ADD FILTER PREDICATE Security.tvf_securitypredicate(tenant_id) ON dbo.orders,
  ADD BLOCK  PREDICATE Security.tvf_securitypredicate(tenant_id) ON dbo.orders
  WITH (STATE = ON);

-- Set tenant context trong application
EXEC sp_set_session_context @key = N'tenant_id', @value = 5;
SELECT * FROM orders;  -- Tự động filter tenant_id = 5
```

---

**Tài liệu tham khảo:**
- SQL Server Documentation: docs.microsoft.com/sql/sql-server/
- AlwaysOn AG: docs.microsoft.com/sql/database-engine/availability-groups/
- Query Store: docs.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store
- www.tranvanbinh.vn
