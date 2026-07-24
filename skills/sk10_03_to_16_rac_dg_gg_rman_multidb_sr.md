---
name: oracle-rac-dg-gg-rman-multidb-sr-troubleshooting
description: >
  Khắc phục lỗi RAC Node Eviction, DataGuard Gap, GoldenGate Abend,
  RMAN Failure, Multi-DB Common Errors, và Oracle SR Escalation.
  Kích hoạt khi hỏi về: RAC node eviction Oracle, split brain RAC,
  CSS eviction Oracle, cluster reconfiguration Oracle,
  DataGuard gap resolution advanced, archive gap troubleshooting,
  GoldenGate abend OGG-01519, GoldenGate troubleshooting advanced,
  RMAN backup failure, RMAN restore failure, ORA-19625 RMAN,
  RMAN-06059 RMAN-20242, PostgreSQL common errors,
  SQL Server common errors, MySQL common errors,
  multi-database troubleshooting, Oracle SR escalation,
  My Oracle Support escalation, severity 1 SR Oracle,
  RDA Oracle, SQLT Oracle diagnostic, Oracle Support ticket.
---

# SK10-03 to SK10-16 · RAC Eviction, DataGuard Gap, GoldenGate Abend, RMAN Failure, Multi-DB & SR Escalation

**Tác giả:** Trần Văn Bình — VietDBA (www.tranvanbinh.vn)

---

# SK10-03/04 · RAC NODE EVICTION TROUBLESHOOTING

## 1. Phát hiện và Phân loại Eviction

```bash
# ── Xác nhận node bị evicted ──────────────────────────────
crsctl check cluster -all
olsnodes -n -s   # -s shows Active/Inactive status

# ── CSS log — nguồn thông tin quan trọng nhất ─────────────
grep -E "evict|eviction|reconfig|kill|terminat" \
  $GRID_HOME/log/$(hostname)/cssd/ocssd.log | tail -100

# ── Tìm root cause pattern ─────────────────────────────────
# Pattern 1: Network heartbeat miss
grep -E "network.*heartbeat|missed.*heartbeat" \
  $GRID_HOME/log/$(hostname)/cssd/ocssd.log | tail -30

# Pattern 2: Disk heartbeat miss (voting disk I/O issue)
grep -E "disk.*heartbeat|voting.*timeout" \
  $GRID_HOME/log/$(hostname)/cssd/ocssd.log | tail -30

# Pattern 3: Member kill request từ node khác
grep -E "kill.*node|terminat.*node" \
  $GRID_HOME/log/$(hostname)/cssd/ocssd.log | tail -30
```

## 2. Root Cause Investigation theo từng nguyên nhân

```bash
# ── CASE 1: Network Interconnect Issue ────────────────────
# Kiểm tra network errors
netstat -s | grep -E "error|drop|retrans"
ip -s link show eth1   # Private interconnect stats

# Kiểm tra packet loss giữa nodes
ping -c 100 -i 0.2 10.10.1.2 | tail -5

# Kiểm tra MTU mismatch (jumbo frames)
ip link show eth1 | grep mtu
ping -M do -s 8972 10.10.1.2   # Test jumbo frame, should not fragment

# Switch port errors (cần network team check)
# Yêu cầu network team: kiểm tra switch logs cho port flapping

# ── CASE 2: Slow Voting Disk I/O ──────────────────────────
# Kiểm tra disk latency
iostat -x 1 10 | grep -E "$(crsctl query css votedisk | grep -oP '(?<=\().*?(?=\))')"

# Voting disk read/write test
dd if=/dev/CRS1 of=/dev/null bs=512 count=1000 2>&1
time dd if=/dev/CRS1 of=/dev/null bs=512 count=1000

# Kiểm tra css misscount threshold
crsctl get css misscount
crsctl get css disktimeout
crsctl get css reboottime
# Default: misscount=30s, disktimeout=200s, reboottime=3s

# ── CASE 3: High Server Load (CPU/Memory) ─────────────────
# Kiểm tra resource exhaustion tại thời điểm eviction
sar -u -f /var/log/sa/sa$(date +%d) | grep -A5 "<eviction_time>"
dmesg | grep -E "hung|stall|blocked|oom"

# Kiểm tra swap usage
sar -r -f /var/log/sa/sa$(date +%d)

# ── CASE 4: Storage I/O latency cao ───────────────────────
iostat -x 1 10
# Tìm await > 100ms = storage problem
```

## 3. Rejoin Node sau Eviction

```bash
# ── Bước 1: Fix root cause TRƯỚC (network/storage/load) ────

# ── Bước 2: Start Clusterware trên node bị evicted ────────
crsctl start crs

# Monitor startup process
crsctl stat res -t -init

# ── Bước 3: Verify rejoin thành công ──────────────────────
crsctl check crs
olsnodes -n
crsctl stat res -t

# ── Bước 4: Start instance nếu chưa tự động ───────────────
srvctl start instance -d ORCL -i ORCL2

# ── Bước 5: Verify đầy đủ hoạt động ───────────────────────
sqlplus / as sysdba << 'EOF'
SELECT inst_id, instance_name, status FROM gv$instance;
EOF
```

## 4. Tuning để Giảm Eviction trong tương lai

```bash
# Tăng misscount nếu network không ổn định (cẩn thận với recommended values)
# Default: 30s. KHÔNG nên tăng quá cao (chậm phát hiện thật sự node down)
crsctl set css misscount 60   # Chỉ khi có lý do chính đáng

# Đảm bảo dedicated network cho interconnect (không share với public)
oifcfg getif

# Multiple voting disks trên storage tách biệt (giảm single point of failure)
crsctl query css votedisk
```

---

# SK10-05 · DATAGUARD GAP RESOLUTION ADVANCED

## 1. Phân loại Gap

```sql
-- ── Gap type 1: Archive log gap (đơn giản nhất) ───────────
SELECT thread#, low_sequence#, high_sequence# FROM v$archive_gap;

-- ── Gap type 2: Standby chưa nhận archived logs ───────────
SELECT thread#, sequence#, applied
FROM v$archived_log
WHERE applied = 'NO'
ORDER BY sequence# DESC;

-- ── Gap type 3: Foreground (transport) lag ────────────────
SELECT name, value FROM v$dataguard_stats
WHERE name IN ('transport lag','apply lag');
```

## 2. Gap Resolution Workflow

```bash
# ── Phương án 1: FAL tự động (mặc định, không cần can thiệp) ──
# Kiểm tra FAL config đúng chưa
sqlplus / as sysdba << 'EOF'
SHOW PARAMETER fal_server;
EOF

# Force archive trên Primary để trigger FAL
sqlplus / as sysdba << 'EOF'
ALTER SYSTEM SWITCH LOGFILE;
EOF

# Monitor alert log Standby cho FAL activity
tail -f $ORACLE_BASE/diag/rdbms/orcl_stb/ORCL_STB/trace/alert_ORCL_STB.log | \
  grep -i "FAL\|gap"

# ── Phương án 2: Manual archivelog copy (khi FAL fail) ────
# Tìm archived logs bị thiếu trên Primary
sqlplus / as sysdba << 'EOF'
SELECT name FROM v$archived_log
WHERE sequence# BETWEEN &low AND &high
  AND thread# = 1;
EOF

# Copy thủ công sang Standby
scp /u01/arch/1_500_*.arc oracle@standby:/u01/arch/

# Trên Standby: register archived log
sqlplus / as sysdba << 'EOF'
ALTER DATABASE REGISTER LOGFILE '/u01/arch/1_500_xxxxx.arc';
EOF

# ── Phương án 3: RMAN Incremental Backup (gap lớn) ────────
# Lấy SCN hiện tại của Standby
sqlplus / as sysdba << 'EOF'
SELECT current_scn FROM v$database;
EOF

# Trên Primary: tạo incremental backup từ SCN này
rman target / << 'EOF'
BACKUP INCREMENTAL FROM SCN &standby_scn
  DATABASE FORMAT '/tmp/gap_fix_%U.bkp'
  TAG 'GAP_FIX';
BACKUP CURRENT CONTROLFILE FOR STANDBY
  FORMAT '/tmp/standby_ctl.bkp';
EOF

# Copy sang Standby
scp /tmp/gap_fix_*.bkp /tmp/standby_ctl.bkp oracle@standby:/tmp/

# Trên Standby: cancel managed recovery, apply incremental
sqlplus / as sysdba << 'EOF'
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
EOF

rman target / << 'EOF'
CATALOG START WITH '/tmp/gap_fix_';
RECOVER DATABASE NOREDO;
EOF

# Restart managed recovery
sqlplus / as sysdba << 'EOF'
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE
  USING CURRENT LOGFILE DISCONNECT;
EOF

# Verify gap resolved
sqlplus / as sysdba << 'EOF'
SELECT thread#, low_sequence#, high_sequence# FROM v$archive_gap;
EOF
```

## 3. Broker-managed Gap Resolution

```bash
dgmgrl /
DGMGRL> SHOW DATABASE 'ORCL_STB' StatusReport;
DGMGRL> VALIDATE DATABASE 'ORCL_STB';
# Broker tự động detect và đề xuất resolve nếu cần RMAN incremental
```

---

# SK10-06 · GOLDENGATE ABEND TROUBLESHOOTING ADVANCED

## 1. OGG-01519 Deep Dive

```bash
# Xem chi tiết lỗi
GGSCI> VIEW REPORT rep1

# Tìm SQL/record gây lỗi trong report
grep -B5 -A20 "OGG-01519\|OGG-00record" \
  /u01/ogg/dirrpt/REP1.rpt | tail -50

# ── Nguyên nhân 1: Schema thay đổi (column added/dropped) ──
# Trên source: kiểm tra DDL gần đây
sqlplus / as sysdba << 'EOF'
SELECT object_name, last_ddl_time FROM dba_objects
WHERE owner='SCOTT' AND last_ddl_time > SYSDATE-1
ORDER BY last_ddl_time DESC;
EOF

# Fix: Restart Extract từ thời điểm DDL
GGSCI> STOP EXTRACT ext1
GGSCI> ALTER EXTRACT ext1, TRANLOG, BEGIN NOW
GGSCI> START EXTRACT ext1

# ── Nguyên nhân 2: Target table missing column ─────────────
-- Sync DDL thủ công trên Target trước
ALTER TABLE scott.orders ADD new_column VARCHAR2(50);
GGSCI> START REPLICAT rep1
```

## 2. Duplicate Key / Constraint Violation

```
-- Thêm error handling vào replicat params
REPERROR (DEFAULT, DISCARD)
-- Hoặc skip specific errors:
REPERROR (ORA-00001, DISCARD)   -- Duplicate key
REPERROR (ORA-02291, DISCARD)   -- FK constraint violation
REPERROR (ORA-01403, DISCARD)   -- No data found (UPDATE/DELETE target missing)
```

```bash
GGSCI> START REPLICAT rep1

# Review discarded records
cat /u01/ogg/dirrpt/rep1.dsc
```

## 3. Resync sau Critical Abend

```bash
# Khi lag quá lớn hoặc data inconsistent, cần resync

# ── Bước 1: Stop tất cả processes ─────────────────────────
GGSCI> STOP REPLICAT rep1
GGSCI> STOP EXTRACT pmp1
GGSCI> STOP EXTRACT ext1

# ── Bước 2: Lấy SCN hiện tại ──────────────────────────────
sqlplus / as sysdba << 'EOF'
SELECT current_scn FROM v$database;
EOF

# ── Bước 3: Re-export/import data (DataPump) ──────────────
expdp ggadmin/pass schemas=SCOTT \
  directory=DATA_PUMP_DIR dumpfile=resync.dmp \
  flashback_scn=&current_scn

impdp ggadmin/pass@TARGET schemas=SCOTT \
  directory=DATA_PUMP_DIR dumpfile=resync.dmp \
  table_exists_action=REPLACE

# ── Bước 4: Restart Extract từ SCN, Replicat fresh ────────
GGSCI> ALTER EXTRACT ext1, ATCSN &current_scn
GGSCI> START EXTRACT ext1
GGSCI> START EXTRACT pmp1

GGSCI> DELETE REPLICAT rep1
GGSCI> ADD REPLICAT rep1, INTEGRATED, EXTTRAIL ./dirdat/rt
GGSCI> START REPLICAT rep1
```

---

# SK10-07 · RMAN BACKUP/RESTORE FAILURE

## 1. RMAN Backup Failures

```bash
# ── Xem lỗi backup chi tiết ────────────────────────────────
rman target / << 'EOF'
LIST BACKUP SUMMARY;
EOF

sqlplus / as sysdba << 'EOF'
SELECT session_recid, operation, status,
       TO_CHAR(start_time,'YYYY-MM-DD HH24:MI') start_time
FROM v$rman_status
WHERE status != 'COMPLETED'
ORDER BY start_time DESC;
EOF

# ── RMAN-06059: expected archived log not found ───────────
rman target / << 'EOF'
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
EOF

# ── RMAN-20242: incarnation not found ──────────────────────
rman target / << 'EOF'
LIST INCARNATION;
RESET DATABASE TO INCARNATION 2;
EOF

# ── ORA-19625: error identifying file ──────────────────────
# File bị xóa ngoài RMAN, cần crosscheck + delete expired
rman target / << 'EOF'
CROSSCHECK BACKUP;
DELETE NOPROMPT EXPIRED BACKUP;
EOF

# ── Backup failed do disk full ─────────────────────────────
df -h /backup
rman target / << 'EOF'
DELETE NOPROMPT OBSOLETE;
DELETE NOPROMPT ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-3';
EOF
```

## 2. RMAN Restore Failures

```bash
# ── Restore fail: missing piece ────────────────────────────
rman target / << 'EOF'
LIST BACKUP OF DATABASE;
RESTORE DATABASE PREVIEW;
EOF

# ── Restore với corrupted backup piece ─────────────────────
rman target / << 'EOF'
RESTORE DATABASE VALIDATE;
-- Nếu thấy corruption, thử backup khác:
RESTORE DATABASE FROM TAG 'WEEKLY_BACKUP';
EOF

# ── Restore sang server khác (path khác) ───────────────────
rman target / << 'EOF'
RUN {
  SET NEWNAME FOR DATABASE TO '/new_path/%b';
  RESTORE DATABASE;
  SWITCH DATAFILE ALL;
  RECOVER DATABASE;
}
EOF
```

## 3. Test Backup Định kỳ (Phòng ngừa)

```bash
#!/bin/bash
# weekly_restore_test.sh — Test restore vào sandbox

rman target / catalog rman_cat/pass@CATALOG << 'EOF'
RUN {
  RESTORE DATABASE VALIDATE;
  RESTORE ARCHIVELOG ALL VALIDATE;
}
EOF

# Full restore test vào test environment (monthly)
rman target sys/pass@PROD auxiliary sys/pass@TEST_RESTORE << 'EOF'
DUPLICATE TARGET DATABASE TO TEST_RESTORE
  FROM ACTIVE DATABASE
  NOFILENAMECHECK;
EOF
```

---

# SK10-08 to SK10-13 · MULTI-DB COMMON ERRORS

## PostgreSQL Common Errors

```bash
# ── "too many connections" ─────────────────────────────────
psql -c "SHOW max_connections;"
psql -c "SELECT count(*) FROM pg_stat_activity;"
# Fix: tăng max_connections hoặc dùng PgBouncer

# ── Replication broken ─────────────────────────────────────
psql -c "SELECT * FROM pg_stat_replication;"
psql -c "SELECT * FROM pg_replication_slots WHERE active='f';"
# Fix: drop stuck slot
psql -c "SELECT pg_drop_replication_slot('slot_name');"

# ── Table bloat / VACUUM cần gấp ──────────────────────────
psql -c "SELECT relname, n_dead_tup FROM pg_stat_user_tables
          ORDER BY n_dead_tup DESC LIMIT 10;"
psql -c "VACUUM ANALYZE schema.table_name;"

# ── Transaction ID wraparound (CRITICAL) ──────────────────
psql -c "SELECT datname, age(datfrozenxid) FROM pg_database
          ORDER BY age(datfrozenxid) DESC;"
psql -c "VACUUM FREEZE table_name;"
```

## SQL Server Common Errors

```sql
-- ── Database in suspect mode ───────────────────────────────
ALTER DATABASE mydb SET EMERGENCY;
DBCC CHECKDB(mydb, REPAIR_ALLOW_DATA_LOSS);
ALTER DATABASE mydb SET ONLINE;

-- ── TempDB full ─────────────────────────────────────────────
DBCC SQLPERF(LOGSPACE);
-- Add tempdb file hoặc shrink:
ALTER DATABASE tempdb MODIFY FILE (NAME=tempdev, SIZE=10GB);

-- ── AlwaysOn AG not synchronizing ──────────────────────────
SELECT * FROM sys.dm_hadr_database_replica_states;
-- Resume data movement:
ALTER DATABASE mydb SET HADR RESUME;

-- ── Blocking chain ──────────────────────────────────────────
SELECT blocking_session_id, session_id, wait_type
FROM sys.dm_exec_requests WHERE blocking_session_id != 0;
KILL <session_id>;
```

## MySQL Common Errors

```bash
# ── Replication stopped ────────────────────────────────────
mysql -e "SHOW SLAVE STATUS\G" | grep -E "Running|Error"
mysql -e "STOP SLAVE; SET GLOBAL SQL_SLAVE_SKIP_COUNTER=1; START SLAVE;"

# ── InnoDB corruption ───────────────────────────────────────
mysqlcheck --all-databases --check --auto-repair

# ── Connection limit reached ────────────────────────────────
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -e "SET GLOBAL max_connections = 500;"

# ── Disk full / binlog cleanup ─────────────────────────────
mysql -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 7 DAY;"
```

---

# SK10-14 to SK10-16 · ORACLE SUPPORT (SR) ESCALATION

## 1. Khi nào cần mở SR

```
Tiêu chí mở SR với Oracle Support:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SEVERITY 1 (Critical — Production Down):
  - Database down, không thể recover
  - Data corruption nghiêm trọng không tự fix được
  - Phải có người trực 24/7 cho đến khi resolve

SEVERITY 2 (Significant impact):
  - Performance nghiêm trọng, business impact cao
  - Feature quan trọng không hoạt động

SEVERITY 3 (Minor impact):
  - Vấn đề có workaround
  - Cần tư vấn kỹ thuật

SEVERITY 4 (Question/Enhancement):
  - Câu hỏi general, không khẩn cấp
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Thu thập Diagnostic Data Trước Khi Mở SR

```bash
# ── RDA (Remote Diagnostic Agent) ─────────────────────────
cd /tmp
unzip rda_latest.zip
cd rda
perl rda.pl -S    # Silent mode, thu thập toàn diện

# ── OSWatcher (OS-level metrics, để sẵn chạy liên tục) ────
cd /u01/oswatcher
./startOSWbb.sh 30 168    # 30s interval, giữ 7 ngày (168h)

# ── AWR Report cho thời điểm xảy ra vấn đề ────────────────
sqlplus / as sysdba << 'EOF'
SELECT output FROM TABLE(
  DBMS_WORKLOAD_REPOSITORY.AWR_REPORT_TEXT(
    l_dbid => (SELECT dbid FROM v$database),
    l_inst_num => 1,
    l_bid => &begin_snap,
    l_eid => &end_snap)
);
EOF

# ── SQLT (SQL Tuning diagnostic, cho performance issues) ──
cd /tmp/sqlt
unzip sqlt.zip
sqlplus / as sysdba @sqlt/install/sqcreate.sql
sqlplus app_user/pass @sqlt/run/sqltxecute.sql <sql_id>

# ── Alert log và trace files liên quan ────────────────────
find $ORACLE_BASE/diag -name "*.trc" \
  -newer /tmp/incident_marker | head -20

# Tar tất cả diagnostic files
tar czf /tmp/diag_bundle_$(date +%Y%m%d).tar.gz \
  $ORACLE_BASE/diag/rdbms/orcl/ORCL/trace/alert_ORCL.log \
  $ORACLE_BASE/diag/rdbms/orcl/ORCL/incident/ \
  /tmp/rda_output/
```

## 3. Thông tin Cần Cung Cấp Khi Mở SR

```
Checklist thông tin SR:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
□ Oracle version (SELECT * FROM v$version;)
□ Platform/OS version (uname -a, /etc/os-release)
□ Patch level (opatch lsinventory)
□ Database/Instance name, RAC hay Single Instance
□ Severity level và business impact
□ Mô tả vấn đề chi tiết: khi nào bắt đầu, tần suất
□ Steps to reproduce (nếu reproducible)
□ Error messages chính xác (ORA-xxxxx)
□ Recent changes (patch, config change, data growth)
□ Diagnostic files đã thu thập (RDA, AWR, trace)
□ Workaround đã thử (nếu có)
□ Timeline cần resolve (cho Sev 1/2)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 4. SR Escalation Process

```
Quy trình Escalation:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Tạo SR qua support.oracle.com với đầy đủ thông tin
2. Đính kèm diagnostic bundle (RDA, AWR, traces)
3. Set đúng Severity level
4. Nếu Sev 1: gọi hotline ngay sau khi tạo SR
5. Theo dõi SR status, respond nhanh khi Oracle yêu cầu thêm info
6. Nếu sau X giờ (theo SLA) chưa có response phù hợp:
   → Escalate qua Oracle Account Manager
   → Hoặc dùng "Escalate" button trong SR portal
7. Document tất cả actions/workarounds Oracle đề xuất
8. Sau khi resolve: update internal runbook với root cause + fix
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MOS Resources hữu ích:
- support.oracle.com — My Oracle Support portal
- MOS Note 166650.1 — How to Submit a Service Request
- MOS Note 314422.1 — RDA Documentation
- MOS Note 215187.1 — SQLT Documentation
- Doc ID search: tìm theo error code (ORA-xxxxx) để xem known issues
```

---

**Tài liệu tham khảo — SK10-03 đến SK10-16:**
- MOS Note 1050693.1 (Node Eviction Troubleshooting)
- MOS Note 836986.1 (DataGuard Gap Resolution)
- MOS Note 1232562.1 (GoldenGate Troubleshooting)
- MOS Note 1071202.1 (RMAN Troubleshooting)
- MOS Note 166650.1 (How to Submit Service Request)
- PostgreSQL/MySQL/SQL Server Official Troubleshooting Guides
- www.tranvanbinh.vn — Khóa học Oracle DBA A-Z Enterprise
