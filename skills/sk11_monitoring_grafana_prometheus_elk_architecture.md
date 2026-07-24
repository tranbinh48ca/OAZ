---
name: monitoring-architecture-prometheus-grafana-elk-microservices
description: >
  Hướng dẫn toàn diện kiến trúc, mô hình, cài đặt và cấu hình hệ thống
  giám sát doanh nghiệp với Prometheus, Grafana, Alertmanager, ELK Stack
  (Elasticsearch, Logstash, Kibana, Filebeat). Bao phủ giám sát phần cứng
  (node_exporter, IPMI), hệ điều hành (Linux/Windows), database (Oracle,
  PostgreSQL, MySQL, MongoDB), middleware (HAProxy, Nginx, Redis, Kafka,
  RabbitMQ, WebLogic/JVM), tải transaction (RED method, Golden Signals),
  log tập trung (ELK pipeline), alerting đa kênh (Slack/Email/PagerDuty),
  dashboard tổng quan, và kiến trúc chuyên sâu cho microservices
  (distributed tracing, service mesh, SLO/error budget).
  Kích hoạt khi hỏi về: kiến trúc giám sát Prometheus Grafana, cài đặt
  ELK Stack, node_exporter cấu hình, Alertmanager rules, dashboard
  Grafana tổng quan, RED method USE method, distributed tracing Jaeger
  OpenTelemetry, service mesh Istio metrics, SLO error budget
  microservices, giám sát hạ tầng CNTT toàn diện.
---

# SK09-MONITORING · Kiến trúc & Triển khai Giám sát Toàn diện: Prometheus, Grafana, ELK Stack

**Phạm vi:** Prometheus 2.5x, Grafana 11.x, Alertmanager, ELK Stack 8.x (Elasticsearch/Logstash/Kibana/Filebeat), OpenTelemetry, Jaeger
**Tác giả:** Trần Văn Bình — VietDBA (Hotline/Zalo: 0902 912 888 — www.tranvanbinh.vn)

---

## MENU TỔNG THỂ (MỤC LỤC)

```
KIẾN TRÚC GIÁM SÁT TOÀN DIỆN — Layered Observability Map
══════════════════════════════════════════════════════════════════

┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 1: KIẾN TRÚC & MÔ HÌNH TỔNG QUAN                        │  |
│  1.1 Ba trụ cột Observability: Metrics-Logs-Traces            │  |
│  1.2 Sơ đồ kiến trúc tổng thể (Prometheus+Grafana+ELK)         │  |
│  1.3 Mô hình pull vs push, kiến trúc HA                        │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 2: CÀI ĐẶT NỀN TẢNG (Docker Compose)                    │  |
│  2.1 Prometheus + Alertmanager + Grafana                       │  |
│  2.2 ELK Stack (Elasticsearch/Logstash/Kibana/Filebeat)        │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 3: GIÁM SÁT PHẦN CỨNG & HỆ ĐIỀU HÀNH                    │  |
│  3.1 node_exporter (CPU/RAM/Disk/Network)                      │  |
│  3.2 IPMI/iLO/iDRAC hardware exporter                          │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 4: GIÁM SÁT DATABASE & MIDDLEWARE                        │  |
│  4.1 Database exporters (Oracle/PostgreSQL/MySQL/MongoDB/Redis)│  |
│  4.2 Middleware exporters (HAProxy/Nginx/Kafka/RabbitMQ/JVM)   │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 5: GIÁM SÁT TẢI TRANSACTION & APM                        │  |
│  5.1 RED Method & USE Method                                   │  |
│  5.2 Distributed Tracing (OpenTelemetry + Jaeger)              │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 6: LOG TẬP TRUNG VỚI ELK                                  │  |
│  6.1 Pipeline Filebeat → Logstash → Elasticsearch               │  |
│  6.2 Cấu trúc hóa log & correlation với trace/metric            │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 7: ALERTING ĐA KÊNH                                       │  |
│  7.1 Alertmanager routing (Slack/Email/PagerDuty)               │  |
│  7.2 Thư viện alert rule theo mức độ nghiêm trọng                │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 8: DASHBOARD TỔNG QUAN GRAFANA                            │  |
│  8.1 Dashboard Tier-0 (tổng quan toàn hệ thống)                 │  |
│  8.2 Dashboard drill-down theo layer                            │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 9: CHUYÊN SÂU CHO MICROSERVICES                           │  |
│  9.1 Service Mesh metrics (Istio/Linkerd)                       │  |
│  9.2 SLO/Error Budget & Service Dependency Map                  │  |
└────────────────────────────────────────────────────────────┘  |
┌────────────────────────────────────────────────────────────┐  |
│  PHẦN 10: TỔNG KẾT — KẾT LUẬN                                    │  |
└────────────────────────────────────────────────────────────┘  |
══════════════════════════════════════════════════════════════════
```

---

# PHẦN 1: KIẾN TRÚC & MÔ HÌNH TỔNG QUAN

## 1.1 Ba trụ cột Observability: Metrics — Logs — Traces

Một hệ thống giám sát trưởng thành cho môi trường microservices cần đủ 3 trụ cột, mỗi trụ cột trả lời một câu hỏi khác nhau khi có sự cố:

| Trụ cột | Câu hỏi trả lời | Công cụ | Tần suất thu thập |
|---|---|---|---|
| **Metrics** | "Cái gì đang bất thường?" (con số theo thời gian) | Prometheus + Grafana | 15-30 giây/lần (scrape) |
| **Logs** | "Chuyện gì đã xảy ra chi tiết?" (sự kiện rời rạc) | ELK Stack (Filebeat/Logstash/Elasticsearch/Kibana) | Real-time (streaming) |
| **Traces** | "Request đi qua đường nào, chậm ở đâu?" (hành trình một request qua nhiều service) | OpenTelemetry + Jaeger/Tempo | Per-request (sampling) |

Nguyên tắc vận hành: **Metric để phát hiện** (dashboard đỏ) → **Trace để định vị** (service nào chậm) → **Log để chẩn đoán** (dòng lệnh/exception cụ thể). Ba trụ cột phải liên kết được với nhau qua `trace_id`/`request_id` chung để điều tra sự cố nhanh nhất.

## 1.2 Sơ đồ kiến trúc tổng thể

```
                         ┌─────────────────────────┐
                         │   GRAFANA (Dashboard)    │
                         │  - Metrics + Logs + Trace │
                         │  - Alerting UI            │
                         └────┬──────────┬──────────┘
                              │          │
              ┌───────────────┘          └───────────────┐
              ▼                                            ▼
   ┌──────────────────────┐                    ┌──────────────────────┐
   │      PROMETHEUS        │                    │     ELASTICSEARCH      │
   │  (Metrics TSDB)         │◄──Alertmanager────│   (Log Storage/Search) │
   │  Scrape interval: 15s   │                    │                        │
   └────────────┬────────────┘                    └───────────┬────────────┘
                │  pull (scrape)                                │ push (bulk index)
   ┌────────────┴─────────────────────────┐          ┌─────────┴──────────┐
   │                                        │          │                     │
   ▼            ▼            ▼             ▼          ▼                     ▼
┌────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐      ┌──────────────┐
│ node_   │ │ Oracle/  │ │ HAProxy/ │ │ App /    │ │Logstash │      │   Filebeat    │
│exporter │ │PG/MySQL  │ │Nginx/    │ │ Java JMX │ │(parse,  │◄─────│ (log shipper  │
│(HW/OS)  │ │exporter  │ │Redis/    │ │exporter  │ │enrich)  │      │  trên mỗi     │
│         │ │          │ │Kafka exp │ │          │ │         │      │  server/pod)  │
└────────┘ └──────────┘ └──────────┘ └──────────┘ └─────────┘      └───────┬───────┘
                                                                             │
                                                              ┌──────────────┴──────────────┐
                                                              │  Server/VM/Container logs    │
                                                              │  (syslog, app log, DB alert)  │
                                                              └───────────────────────────────┘

   ┌─────────────────────────────────────────────────────────────────┐
   │  DISTRIBUTED TRACING (Microservices)                              │
   │  App instrumented với OpenTelemetry SDK                            │
   │       → OTel Collector → Jaeger/Tempo (storage) → Grafana (view)   │
   └─────────────────────────────────────────────────────────────────┘
```

## 1.3 Mô hình Pull vs Push, kiến trúc HA

- **Prometheus dùng mô hình PULL**: Prometheus server chủ động "kéo" (scrape) metric từ endpoint `/metrics` của từng target theo chu kỳ (thường 15-30s). Ưu điểm: dễ biết target nào "chết" (scrape thất bại = down ngay lập tức), không cần target tự quản lý việc gửi đi.
- **Trường hợp cần PUSH** (batch job ngắn hạn, serverless không tồn tại đủ lâu để bị scrape): dùng **Pushgateway** làm trung gian — job đẩy metric vào Pushgateway, Prometheus scrape từ Pushgateway như một target bình thường.
- **Logs dùng mô hình PUSH**: Filebeat/Logstash chủ động đẩy log vào Elasticsearch ngay khi có log mới (streaming), vì log là sự kiện rời rạc không có khái niệm "scrape định kỳ" phù hợp.
- **Kiến trúc HA cho production**: Prometheus không có clustering nội tại (mỗi Prometheus instance độc lập) — triển khai HA bằng cách chạy 2 Prometheus instance giống hệt nhau scrape song song cùng target, đặt sau Grafana hoặc dùng **Thanos/Mimir** để có long-term storage + global query view hợp nhất nhiều Prometheus. Elasticsearch có clustering nội tại (multi-node cluster với replica shard).

---

# PHẦN 2: CÀI ĐẶT NỀN TẢNG (Docker Compose)

## 2.1 Prometheus + Alertmanager + Grafana

```yaml
# docker-compose-monitoring.yml
version: '3.8'

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data: {}
  grafana_data: {}
  alertmanager_data: {}

services:
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/rules:/etc/prometheus/rules
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'          # cho phép reload config qua API
    ports:
      - "9090:9090"
    networks: [monitoring]
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: alertmanager
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager
    ports:
      - "9093:9093"
    networks: [monitoring]
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=ChangeMe_VietDBA_2026
      - GF_INSTALL_PLUGINS=grafana-piechart-panel
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"
    networks: [monitoring]
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.1
    container_name: node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - "9100:9100"
    networks: [monitoring]
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    container_name: cadvisor
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    ports:
      - "8080:8080"
    networks: [monitoring]
    restart: unless-stopped
```

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'vietdba-production'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - "/etc/prometheus/rules/*.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
        labels: { env: 'production', tier: 'os' }

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
        labels: { env: 'production', tier: 'container' }

  # Ví dụ database exporter, middleware exporter — thêm dần theo Phần 4
  - job_name: 'oracle-exporter'
    static_configs:
      - targets: ['oracle-exporter:9161']
        labels: { env: 'production', tier: 'database' }

  # Service discovery tự động cho Kubernetes (thay static_configs khi có K8s)
  # - job_name: 'kubernetes-pods'
  #   kubernetes_sd_configs:
  #     - role: pod
```

**Bước cài đặt:**
```bash
mkdir -p prometheus/rules alertmanager grafana/provisioning
# Đặt file prometheus.yml, alertmanager.yml theo cấu trúc trên
docker compose -f docker-compose-monitoring.yml up -d
# Kiểm tra targets đang UP
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

## 2.2 ELK Stack (Elasticsearch/Logstash/Kibana/Filebeat)

```yaml
# docker-compose-elk.yml
version: '3.8'

networks:
  elk:
    driver: bridge

volumes:
  es_data: {}

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.14.3
    container_name: elasticsearch
    environment:
      - discovery.type=single-node          # production: chuyển sang multi-node cluster
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=ChangeMe_VietDBA_2026
      - "ES_JAVA_OPTS=-Xms4g -Xmx4g"          # 50% RAM server, không quá 32GB
    volumes:
      - es_data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"
    networks: [elk]
    restart: unless-stopped
    ulimits:
      memlock: { soft: -1, hard: -1 }

  logstash:
    image: docker.elastic.co/logstash/logstash:8.14.3
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml
    environment:
      - "LS_JAVA_OPTS=-Xms1g -Xmx1g"
    ports:
      - "5044:5044"    # nhận từ Filebeat
      - "5000:5000/tcp" # nhận syslog/TCP trực tiếp nếu cần
    depends_on: [elasticsearch]
    networks: [elk]
    restart: unless-stopped

  kibana:
    image: docker.elastic.co/kibana/kibana:8.14.3
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=ChangeMe_Kibana_2026
    ports:
      - "5601:5601"
    depends_on: [elasticsearch]
    networks: [elk]
    restart: unless-stopped
```

```ruby
# logstash/pipeline/logstash.conf
input {
  beats {
    port => 5044
  }
}

filter {
  # Parse log Oracle alert log dạng semi-structured
  if [fields][log_type] == "oracle_alert" {
    grok {
      match => { "message" => "%{TIMESTAMP_ISO8601:log_timestamp}.*ORA-%{NUMBER:ora_error_code}" }
      tag_on_failure => ["_grokparsefailure_oracle"]
    }
    if "ORA-" in [message] {
      mutate { add_tag => ["oracle_error"] }
    }
  }

  # Parse log ứng dụng dạng JSON có sẵn (structured logging — khuyến nghị chuẩn)
  if [fields][log_type] == "application_json" {
    json { source => "message" }
    # Liên kết với trace_id để correlation với distributed tracing (Phần 5)
    if [trace_id] {
      mutate { add_field => { "[@metadata][trace_id]" => "%{trace_id}" } }
    }
  }

  # Parse access log Nginx/HAProxy
  if [fields][log_type] == "nginx_access" {
    grok {
      match => { "message" => '%{IPORHOST:client_ip} - - \[%{HTTPDATE:timestamp}\] "%{WORD:http_method} %{URIPATHPARAM:request_path} HTTP/%{NUMBER:http_version}" %{NUMBER:response_code} %{NUMBER:bytes} "%{DATA:referrer}" "%{DATA:user_agent}" %{NUMBER:request_time}' }
    }
    mutate { convert => { "response_code" => "integer" "request_time" => "float" } }
  }

  date {
    match => ["log_timestamp", "ISO8601"]
    target => "@timestamp"
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    user => "elastic"
    password => "ChangeMe_VietDBA_2026"
    index => "vietdba-logs-%{[fields][log_type]}-%{+YYYY.MM.dd}"
  }
}
```

```yaml
# filebeat.yml — deploy trên MỖI server/node cần thu thập log
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /u01/app/oracle/diag/rdbms/*/*/trace/alert_*.log
    fields: { log_type: oracle_alert }
    fields_under_root: false

  - type: log
    enabled: true
    paths:
      - /var/log/myapp/*.log
    fields: { log_type: application_json }
    json.keys_under_root: true
    json.add_error_key: true

  - type: log
    enabled: true
    paths:
      - /var/log/nginx/access.log
    fields: { log_type: nginx_access }

output.logstash:
  hosts: ["logstash-server:5044"]

# Với Kubernetes: dùng Filebeat DaemonSet thay vì cài từng node thủ công
# helm repo add elastic https://helm.elastic.co
# helm install filebeat elastic/filebeat -f filebeat-values.yaml
```

---

# PHẦN 3: GIÁM SÁT PHẦN CỨNG & HỆ ĐIỀU HÀNH

## 3.1 node_exporter — chỉ số CPU/RAM/Disk/Network chi tiết

`node_exporter` đã cài ở Phần 2.1, cung cấp hàng trăm metric OS-level. Các nhóm chỉ số quan trọng nhất cần đưa vào dashboard/alert:

| Nhóm | Metric PromQL mẫu | Ý nghĩa |
|---|---|---|
| CPU | `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` | % CPU đang sử dụng |
| Load Average | `node_load15 / count(node_cpu_seconds_total{mode="idle"}) by (instance)` | Load trung bình chuẩn hóa theo số core |
| RAM | `(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100` | % RAM đã dùng thực tế |
| Swap | `rate(node_vmstat_pswpin[5m]) + rate(node_vmstat_pswpout[5m])` | Hoạt động swap in/out — xem lại Case swappiness (case09b) |
| Disk Space | `(node_filesystem_avail_bytes / node_filesystem_size_bytes) * 100` | % dung lượng còn trống |
| Disk Inode | `(node_filesystem_files_free / node_filesystem_files) * 100` | % inode còn trống — xem Case inode exhaustion (case09b) |
| Disk I/O Latency | `rate(node_disk_io_time_seconds_total[5m])` | % thời gian disk bận |
| Network Errors | `rate(node_network_receive_errs_total[5m])` | Lỗi gói tin nhận — dấu hiệu NIC/cáp lỗi |
| File Descriptor | `node_filefd_allocated / node_filefd_maximum` | Tỷ lệ file descriptor đã dùng — xem Case ulimit (case09b) |

## 3.2 Giám sát phần cứng vật lý (iLO/iDRAC/iRMC/IPMI)

Với server vật lý (HP/Dell/Fujitsu — đã đề cập ở case09), cần giám sát riêng tầng phần cứng (RAID, nhiệt độ, quạt, nguồn) độc lập với OS-level, vì OS có thể "khỏe" trong khi phần cứng đang cảnh báo predictive failure.

```yaml
# Thêm vào prometheus.yml — dùng ipmi_exporter (community)
  - job_name: 'ipmi-exporter'
    static_configs:
      - targets: ['server1-bmc:623', 'server2-bmc:623']
    metrics_path: /ipmi
    params:
      module: [default]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: ipmi-exporter:9290
```

Metric quan trọng: `ipmi_sensor_state` (0=ok, 1=warning, 2=critical), `ipmi_temperature_celsius`, `ipmi_fan_speed_rpm`, `ipmi_power_watts` — alert ngay khi `ipmi_sensor_state != 0`, tương ứng trực tiếp với Case 1 (iLO predictive failure) và Case 3 (ECC memory) đã phân tích ở tài liệu case09.

---

# PHẦN 4: GIÁM SÁT DATABASE & MIDDLEWARE

## 4.1 Database Exporters

| Database | Exporter | Metric quan trọng nhất |
|---|---|---|
| Oracle | `oracledb_exporter` (iamseth/oracledb_exporter) | `oracledb_up`, `oracledb_tablespace_used_percent`, `oracledb_wait_time`, `oracledb_sessions_active` |
| PostgreSQL | `postgres_exporter` | `pg_up`, `pg_stat_database_xact_commit`, `pg_replication_lag`, `pg_stat_activity_count` |
| MySQL/MariaDB | `mysqld_exporter` | `mysql_up`, `mysql_slave_lag_seconds`, `mysql_global_status_threads_connected` |
| MongoDB | `mongodb_exporter` | `mongodb_up`, `mongodb_replset_member_state`, `mongodb_op_counters_total` |
| Redis | `redis_exporter` | `redis_up`, `redis_memory_used_bytes`, `redis_connected_clients`, `redis_evicted_keys_total` |

```yaml
# docker-compose bổ sung — oracledb_exporter ví dụ điển hình
  oracle-exporter:
    image: iamseth/oracledb_exporter:0.5.1
    container_name: oracle-exporter
    environment:
      - DATA_SOURCE_NAME=monitor_user/password@//dbhost:1521/ORCLPDB1
    ports: ["9161:9161"]
    networks: [monitoring]
```

> **Lưu ý bảo mật:** Tạo user giám sát riêng (`monitor_user`) chỉ có quyền `SELECT` trên các view động (`V$SESSION`, `V$SYSSTAT`...), tuân thủ nguyên tắc minimum-privilege đã áp dụng cho health check trong project knowledge — không dùng tài khoản SYS/SYSTEM cho exporter.

```sql
-- Tạo user giám sát tối thiểu quyền cho Oracle
CREATE USER monitor_user IDENTIFIED BY "StrongP@ssw0rd";
GRANT CREATE SESSION TO monitor_user;
GRANT SELECT_CATALOG_ROLE TO monitor_user;
GRANT SELECT ON V_$SESSION TO monitor_user;
GRANT SELECT ON V_$SYSSTAT TO monitor_user;
GRANT SELECT ON DBA_TABLESPACE_USAGE_METRICS TO monitor_user;
```

## 4.2 Middleware Exporters

| Middleware | Exporter | Metric quan trọng nhất |
|---|---|---|
| HAProxy | `/stats` endpoint có sẵn dạng Prometheus (`?stats;csv` hoặc module tích hợp) | `haproxy_backend_up`, `haproxy_backend_current_sessions`, `haproxy_backend_http_responses_total{code="5xx"}` |
| Nginx | `nginx-prometheus-exporter` (cần bật `stub_status`) | `nginx_connections_active`, `nginx_http_requests_total` |
| Kafka | `kafka_exporter` (danielqsj) hoặc JMX Exporter | `kafka_topic_partition_under_replicated_partition` (liên hệ Case 14, case09c), `kafka_consumergroup_lag` |
| RabbitMQ | `rabbitmq-prometheus` plugin tích hợp sẵn từ 3.8+ | `rabbitmq_queue_messages_ready`, `rabbitmq_queue_consumers` (liên hệ Case 15, case09c) |
| WebLogic/JVM | `jmx_exporter` (javaagent) | `jvm_memory_bytes_used{area="heap"}`, `jvm_gc_pause_seconds` (liên hệ Case 20 GC storm, case09) |
| Kubernetes | `kube-state-metrics` + `cAdvisor` (đã có ở 2.1) | `kube_pod_status_phase`, `kube_deployment_status_replicas_available` |

```yaml
# JMX Exporter cho WebLogic/JVM — chạy như javaagent kèm theo Managed Server
# setDomainEnv.sh hoặc startup script:
JAVA_OPTIONS="$JAVA_OPTIONS -javaagent:/opt/jmx_exporter/jmx_prometheus_javaagent-0.20.0.jar=9404:/opt/jmx_exporter/weblogic-config.yaml"
```
```yaml
# weblogic-config.yaml (jmx_exporter rule mẫu)
rules:
  - pattern: 'com.bea:Type=JDBCDataSourceRuntime,Name=(\w+),.*'
    name: weblogic_jdbc_active_connections
    value: ActiveConnectionsCurrentCount
  - pattern: 'java.lang:type=Memory'
    name: jvm_heap_used_bytes
    value: HeapMemoryUsage.used
```

Với HAProxy, bật endpoint Prometheus native (2.0+):
```
# haproxy.cfg
frontend prometheus
    bind *:8405
    http-request use-service prometheus-exporter if { path /metrics }
```

---

# PHẦN 5: GIÁM SÁT TẢI TRANSACTION & APM

## 5.1 RED Method (cho request-driven service) & USE Method (cho resource)

Hai phương pháp luận kinh điển để không "giám sát sót":

**RED Method** — áp dụng cho MỌI service xử lý request (API, microservice):
- **R**ate: số request/giây (`rate(http_requests_total[5m])`)
- **E**rrors: tỷ lệ lỗi (`rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])`)
- **D**uration: độ trễ (p50/p95/p99 qua histogram: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))`)

**USE Method** — áp dụng cho MỌI tài nguyên hạ tầng (CPU, disk, network):
- **U**tilization: % thời gian tài nguyên bận
- **S**aturation: mức độ tài nguyên bị "xếp hàng chờ" (queue length)
- **E**rrors: số lỗi phần cứng/tài nguyên

Ứng dụng cần expose metric theo chuẩn Prometheus (dùng client library: `prometheus-client` cho Python, `micrometer` cho Java/Spring Boot, `prom-client` cho Node.js):

```java
// Spring Boot (Micrometer) — ví dụ RED method cho một REST controller
@RestController
public class OrderController {
    private final MeterRegistry registry;

    @GetMapping("/api/orders/{id}")
    @Timed(value = "http.server.requests", description = "Order API latency")
    public Order getOrder(@PathVariable String id) {
        // Micrometer tự động expose: rate, error rate (theo status code), duration histogram
        return orderService.findById(id);
    }
}
```
```yaml
# prometheus.yml — scrape ứng dụng Spring Boot Actuator
  - job_name: 'spring-boot-apps'
    metrics_path: '/actuator/prometheus'
    static_configs:
      - targets: ['order-service:8080', 'payment-service:8080', 'inventory-service:8080']
        labels: { env: 'production', tier: 'application' }
```

## 5.2 Distributed Tracing — OpenTelemetry + Jaeger

Với kiến trúc microservices, một request đi qua NHIỀU service (API Gateway → Order Service → Payment Service → Inventory Service) — chỉ nhìn metric riêng lẻ từng service không đủ để biết TOÀN BỘ hành trình chậm ở đâu. Distributed tracing giải quyết đúng vấn đề này.

```yaml
# docker-compose bổ sung — Jaeger all-in-one (dev/test); production dùng Jaeger + Elasticsearch/Cassandra backend
  jaeger:
    image: jaegertracing/all-in-one:1.58
    container_name: jaeger
    environment:
      - COLLECTOR_OTLP_ENABLED=true
    ports:
      - "16686:16686"   # Jaeger UI
      - "4317:4317"     # OTLP gRPC receiver
      - "4318:4318"     # OTLP HTTP receiver
    networks: [monitoring]

  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.105.0
    container_name: otel-collector
    volumes:
      - ./otel/otel-collector-config.yaml:/etc/otelcol/config.yaml
    command: ["--config=/etc/otelcol/config.yaml"]
    ports:
      - "4319:4317"     # nhận OTLP từ ứng dụng
    networks: [monitoring]
```

```yaml
# otel/otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }

processors:
  batch: {}
  # Sampling để giảm tải lưu trữ — chỉ giữ 10% trace bình thường, 100% trace có lỗi
  tail_sampling:
    policies:
      - name: errors-policy
        type: status_code
        status_code: { status_codes: [ERROR] }
      - name: probabilistic-policy
        type: probabilistic
        probabilistic: { sampling_percentage: 10 }

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls: { insecure: true }
  prometheus:
    endpoint: 0.0.0.0:8889   # OTel Collector cũng có thể xuất metric ra Prometheus

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch, tail_sampling]
      exporters: [otlp/jaeger]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

```java
// Instrumentation tự động cho ứng dụng Java — không cần sửa code, dùng javaagent
// java -javaagent:opentelemetry-javaagent.jar \
//   -Dotel.service.name=order-service \
//   -Dotel.exporter.otlp.endpoint=http://otel-collector:4317 \
//   -jar order-service.jar
```

Với trace đã có, mỗi log ứng dụng NÊN đính kèm `trace_id` (Phần 6.1 đã cấu hình Logstash filter cho việc này), cho phép click từ một span chậm trong Jaeger UI → nhảy thẳng tới log chi tiết tương ứng trong Kibana — đây chính là sự liên kết ba trụ cột Observability đã nêu ở Phần 1.1.

---

# PHẦN 6: LOG TẬP TRUNG VỚI ELK

## 6.1 Nguyên tắc thiết kế pipeline log

Kiến trúc chuẩn: **Filebeat (shipper nhẹ, chạy trên từng host/pod) → Logstash (parse/enrich, chạy tập trung) → Elasticsearch (lưu trữ, index) → Kibana (truy vấn, dashboard)**.

Với khối lượng log rất lớn, chèn thêm **Kafka** làm buffer giữa Filebeat và Logstash để chống mất log khi Logstash/Elasticsearch quá tải tạm thời:
```
Filebeat → Kafka topic 'logs' → Logstash (consumer) → Elasticsearch
```

## 6.2 Cấu trúc hóa log (Structured Logging) — khuyến nghị bắt buộc cho ứng dụng mới

Log dạng text tự do (`grok` parse) luôn dễ vỡ khi format thay đổi — ứng dụng mới nên xuất log dạng JSON có cấu trúc sẵn, giảm tải parsing ở Logstash và tăng độ tin cậy:

```json
{"timestamp":"2026-07-01T10:23:45.123Z","level":"ERROR","service":"order-service","trace_id":"4bf92f3577b34da6a3ce929d0e0e4736","message":"Payment gateway timeout","order_id":"ORD-88213","duration_ms":5023}
```

```yaml
# Index Lifecycle Management (ILM) trong Elasticsearch — tự động xoay vòng/xóa log cũ
PUT _ilm/policy/vietdba-logs-policy
{
  "policy": {
    "phases": {
      "hot":   { "actions": { "rollover": { "max_size": "50gb", "max_age": "1d" } } },
      "warm":  { "min_age": "3d", "actions": { "shrink": { "number_of_shards": 1 } } },
      "delete": { "min_age": "30d", "actions": { "delete": {} } }
    }
  }
}
```

> Đây là biện pháp trực tiếp phòng ngừa Case "journald log phình to gây đầy disk" (Case 15, case09b) áp dụng ở quy mô tập trung: Elasticsearch ILM tự động dọn log cũ theo policy, không để tích lũy vô hạn.

---

# PHẦN 7: ALERTING ĐA KÊNH

## 7.1 Alertmanager routing (Slack/Email/PagerDuty)

```yaml
# alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/XXX/YYY/ZZZ'

route:
  receiver: 'default-slack'
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - match: { severity: 'critical' }
      receiver: 'pagerduty-critical'
      continue: true
    - match: { severity: 'critical' }
      receiver: 'slack-critical'
    - match: { severity: 'warning' }
      receiver: 'slack-warning'
    - match: { team: 'dba' }
      receiver: 'email-dba-team'

receivers:
  - name: 'default-slack'
    slack_configs:
      - channel: '#alerts-general'
        send_resolved: true

  - name: 'slack-critical'
    slack_configs:
      - channel: '#alerts-critical'
        send_resolved: true
        title: '🔴 CRITICAL: {{ .GroupLabels.alertname }}'

  - name: 'slack-warning'
    slack_configs:
      - channel: '#alerts-warning'
        send_resolved: true
        title: '🟡 WARNING: {{ .GroupLabels.alertname }}'

  - name: 'pagerduty-critical'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'

  - name: 'email-dba-team'
    email_configs:
      - to: 'dba-team@vietdba.vn'
        from: 'alertmanager@vietdba.vn'
        smarthost: 'smtp.company.com:587'

inhibit_rules:
  # Nếu server DOWN hoàn toàn, không cần bắn thêm alert CPU/RAM cao của chính server đó
  - source_match: { alertname: 'InstanceDown' }
    target_match_re: { alertname: 'HighCPU|HighMemory|HighDiskUsage' }
    equal: ['instance']
```

## 7.2 Thư viện Alert Rule theo mức độ nghiêm trọng

Thiết kế alert rule theo đúng 3 mức Severity đã dùng xuyên suốt các tài liệu case study trong project (🔴 CRITICAL / 🟡 DEGRADED / 🟢 MINOR):

```yaml
# prometheus/rules/infrastructure.yml
groups:
  - name: hardware_os_alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels: { severity: critical }
        annotations:
          summary: "{{ $labels.instance }} không phản hồi scrape"
          description: "Target đã down hơn 1 phút — kiểm tra ngay kết nối/service."

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 90
        for: 10m
        labels: { severity: warning }
        annotations:
          summary: "CPU {{ $labels.instance }} > 90% trong 10 phút"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
        for: 10m
        labels: { severity: warning }

      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes) * 100 < 10
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "Disk {{ $labels.instance }} {{ $labels.mountpoint }} còn dưới 10%"

      - alert: DiskInodeCritical    # trực tiếp phòng ngừa Case 6 (case09b)
        expr: (node_filesystem_files_free / node_filesystem_files) * 100 < 10
        for: 5m
        labels: { severity: critical }

      - alert: SwapActivityAbnormal   # trực tiếp phòng ngừa Case 18 (case09b)
        expr: rate(node_vmstat_pswpout[5m]) > 0 and (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) < 0.7
        for: 10m
        labels: { severity: warning }
        annotations:
          summary: "Swap hoạt động dù RAM còn trống — kiểm tra vm.swappiness"

  - name: database_alerts
    rules:
      - alert: OracleTablespaceCritical
        expr: oracledb_tablespace_used_percent > 90
        for: 5m
        labels: { severity: critical }

      - alert: OracleXIDWraparoundRisk   # trực tiếp phòng ngừa Case Multixact/XID (case08b tương đương PostgreSQL)
        expr: pg_database_age_datfrozenxid > 1000000000
        for: 5m
        labels: { severity: critical }

      - alert: ReplicationLagHigh
        expr: pg_replication_lag > 300 or mysql_slave_lag_seconds > 300
        for: 5m
        labels: { severity: critical, team: 'dba' }

      - alert: RedisEvictedKeysAbnormal   # trực tiếp phòng ngừa Case 19 (case09c)
        expr: rate(redis_evicted_keys_total[5m]) > 0
        for: 5m
        labels: { severity: warning }

  - name: application_alerts
    rules:
      - alert: HighErrorRate     # RED method - Errors
        expr: |
          sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) by (service)
          /
          sum(rate(http_server_requests_seconds_count[5m])) by (service) > 0.05
        for: 5m
        labels: { severity: critical }
        annotations:
          summary: "{{ $labels.service }} có tỷ lệ lỗi 5xx > 5%"

      - alert: HighLatencyP95    # RED method - Duration
        expr: histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le, service)) > 2
        for: 5m
        labels: { severity: warning }
        annotations:
          summary: "{{ $labels.service }} p95 latency > 2 giây"

      - alert: JVMHeapUsageCritical   # trực tiếp phòng ngừa Case 20 GC storm (case09)
        expr: jvm_memory_bytes_used{area="heap"} / jvm_memory_bytes_max{area="heap"} > 0.90
        for: 10m
        labels: { severity: critical }

      - alert: KafkaConsumerLagHigh
        expr: kafka_consumergroup_lag > 10000
        for: 10m
        labels: { severity: warning }

      - alert: RabbitMQQueueGrowing   # trực tiếp phòng ngừa Case 15 (case09c)
        expr: rabbitmq_queue_messages_ready > 50000 and rabbitmq_queue_consumers == 0
        for: 5m
        labels: { severity: critical }
```

---

# PHẦN 8: DASHBOARD TỔNG QUAN GRAFANA

## 8.1 Dashboard Tier-0 — Tổng quan toàn hệ thống (dành cho màn hình NOC/vận hành hàng ngày)

Thiết kế theo nguyên tắc **"1 màn hình, biết ngay hệ thống có ổn không"**, chia thành các hàng (row) theo layer:

```json
{
  "dashboard": {
    "title": "VietDBA - Tổng quan Hệ thống CNTT (Tier-0)",
    "refresh": "30s",
    "panels": [
      { "title": "Số service DOWN", "type": "stat", "targets": [{ "expr": "count(up == 0)" }],
        "thresholds": [{ "value": 0, "color": "green" }, { "value": 1, "color": "red" }] },
      { "title": "SLO Error Budget còn lại (7 ngày)", "type": "gauge",
        "targets": [{ "expr": "1 - (sum(increase(http_requests_total{status=~\"5..\"}[7d])) / sum(increase(http_requests_total[7d])) / 0.001)" }] },
      { "title": "Request Rate toàn hệ thống", "type": "timeseries",
        "targets": [{ "expr": "sum(rate(http_server_requests_seconds_count[5m])) by (service)" }] },
      { "title": "Error Rate theo Service", "type": "timeseries",
        "targets": [{ "expr": "sum(rate(http_server_requests_seconds_count{status=~\"5..\"}[5m])) by (service)" }] },
      { "title": "p95 Latency theo Service", "type": "timeseries",
        "targets": [{ "expr": "histogram_quantile(0.95, sum(rate(http_server_requests_seconds_bucket[5m])) by (le,service))" }] },
      { "title": "CPU/RAM theo Server", "type": "heatmap",
        "targets": [{ "expr": "100 - (avg by(instance)(rate(node_cpu_seconds_total{mode='idle'}[5m]))*100)" }] },
      { "title": "Database Tablespace/Disk", "type": "bargauge",
        "targets": [{ "expr": "oracledb_tablespace_used_percent" }] },
      { "title": "Số Alert đang active theo severity", "type": "piechart",
        "targets": [{ "expr": "count(ALERTS{alertstate='firing'}) by (severity)" }] }
    ]
  }
}
```

**Cách provisioning tự động (không thao tác UI thủ công):**
```yaml
# grafana/provisioning/datasources/datasources.yml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
  - name: Elasticsearch
    type: elasticsearch
    url: http://elasticsearch:9200
    jsonData: { index: "vietdba-logs-*", timeField: "@timestamp" }
  - name: Jaeger
    type: jaeger
    url: http://jaeger:16686
```
```yaml
# grafana/provisioning/dashboards/dashboards.yml
apiVersion: 1
providers:
  - name: 'VietDBA Dashboards'
    folder: 'VietDBA'
    type: file
    options: { path: /etc/grafana/provisioning/dashboards/json }
```

## 8.2 Dashboard drill-down theo layer

Từ dashboard Tier-0, thiết lập link điều hướng (Grafana **Data Links**) xuống các dashboard chi tiết hơn khi click vào một panel bất thường:

| Dashboard con | Nội dung | Dùng khi |
|---|---|---|
| **Tier-1: Hardware/OS** | Chi tiết CPU/RAM/Disk/Network/IPMI theo từng server | Panel "CPU/RAM theo Server" ở Tier-0 báo đỏ |
| **Tier-1: Database** | Session, wait event, tablespace, replication lag theo từng instance | Panel Database ở Tier-0 báo đỏ |
| **Tier-1: Application/Microservices** | RED method chi tiết từng service, JVM/GC, connection pool | Panel Error Rate/Latency báo đỏ |
| **Tier-1: Message Queue** | Kafka consumer lag, RabbitMQ queue depth theo từng topic/queue | Cần điều tra pipeline bất đồng bộ |
| **Tier-2: Trace Explorer** | Nhúng Jaeger UI qua Grafana Tempo/Jaeger datasource | Cần xem hành trình một request cụ thể |
| **Tier-2: Log Explorer** | Nhúng Kibana Discover, filter theo `trace_id` | Cần xem log chi tiết một lỗi cụ thể |

---

# PHẦN 9: CHUYÊN SÂU CHO MICROSERVICES

## 9.1 Service Mesh Metrics (Istio/Linkerd)

Với kiến trúc microservices quy mô lớn (hàng chục service), instrument thủ công từng service (Phần 5.1) tốn công sức lặp lại — Service Mesh (Istio, Linkerd) tự động cung cấp metric RED method cho MỌI service trong mesh mà không cần sửa code ứng dụng, thông qua sidecar proxy (Envoy).

```yaml
# Istio tự động expose metric qua Envoy sidecar, Prometheus scrape qua annotation
apiVersion: v1
kind: Pod
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "15090"
    prometheus.io/path: "/stats/prometheus"
```

Metric quan trọng từ Istio: `istio_requests_total` (có sẵn label `source_app`, `destination_app`, `response_code` — cho phép vẽ **service dependency map** tự động), `istio_request_duration_milliseconds`, `istio_tcp_connections_opened_total`.

```promql
# PromQL vẽ ma trận gọi giữa các service (service dependency)
sum(rate(istio_requests_total[5m])) by (source_app, destination_app)

# Tỷ lệ lỗi giữa 2 service cụ thể (định vị chính xác cặp service có vấn đề)
sum(rate(istio_requests_total{source_app="order-service",destination_app="payment-service",response_code=~"5.."}[5m]))
/
sum(rate(istio_requests_total{source_app="order-service",destination_app="payment-service"}[5m]))
```

Đây là công cụ trực tiếp giải quyết lớp bài toán đã nêu ở Case 18 (case09c — "GoldenGate mất đồng bộ sau failover, cần biết chain phụ thuộc") áp dụng cho tầng microservices: khi một service downstream lỗi, dependency map cho biết NGAY những service nào bị ảnh hưởng dây chuyền.

## 9.2 SLO / Error Budget & Service Dependency Map

**Service Level Objective (SLO)** là cam kết định lượng (ví dụ "99.9% request trả về dưới 500ms trong 30 ngày") — **Error Budget** là "ngân sách lỗi" cho phép trước khi vi phạm SLO (100% - 99.9% = 0.1% request được phép lỗi/chậm).

```promql
# Error Budget còn lại (dạng %) cho SLO 99.9% availability trong 30 ngày
1 - (
  sum(increase(http_requests_total{status=~"5.."}[30d]))
  /
  sum(increase(http_requests_total[30d]))
) / 0.001
```

**Nguyên tắc vận hành với Error Budget:**
- Error Budget còn nhiều → team có thể tự tin release tính năng mới, chấp nhận rủi ro cao hơn
- Error Budget cạn dần/hết → tạm dừng release tính năng mới, ưu tiên tuyệt đối cho ổn định hệ thống (feature freeze)

```yaml
# Alert khi Error Budget burn rate quá nhanh (multi-window multi-burn-rate alert — kỹ thuật chuẩn Google SRE)
- alert: ErrorBudgetBurnRateFast
  expr: |
    (
      sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > (14.4 * 0.001)
    )
    and
    (
      sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > (14.4 * 0.001)
    )
  labels: { severity: critical }
  annotations:
    summary: "Error budget đang cháy với tốc độ sẽ hết trong ~2 giờ nếu không xử lý"
```

Kỹ thuật "multi-window multi-burn-rate" (kiểm tra đồng thời cửa sổ ngắn 5 phút VÀ cửa sổ dài 1 giờ cùng vượt ngưỡng) giúp tránh alert giả (short burst tạm thời) trong khi vẫn phát hiện đủ sớm xu hướng burn rate nguy hiểm thực sự — đây là kỹ thuật tương đương về triết lý với "rise/fall" đã dùng trong health check HAProxy (Case 9, case09) để tránh flapping.

---

# PHẦN 10: TỔNG KẾT — KẾT LUẬN

```
Checklist triển khai giám sát toàn diện — theo thứ tự ưu tiên:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GIAI ĐOẠN 1 (Nền tảng — tuần 1-2):
  ☐ Triển khai Prometheus + Grafana + Alertmanager
  ☐ Cài node_exporter trên MỌI server (hardware/OS baseline)
  ☐ Dashboard Tier-0 tổng quan + alert rule CRITICAL cơ bản
     (InstanceDown, DiskSpaceCritical, HighMemoryUsage)

GIAI ĐOẠN 2 (Database & Middleware — tuần 3-4):
  ☐ Triển khai exporter cho từng database (Oracle/PostgreSQL/MySQL/...)
  ☐ Triển khai exporter cho middleware (HAProxy/Nginx/Kafka/RabbitMQ/Redis)
  ☐ Dashboard Tier-1 drill-down + alert rule theo từng case đã phân tích
     trong các tài liệu case study (tablespace, replication lag, queue growth...)

GIAI ĐOẠN 3 (Log tập trung — tuần 5-6):
  ☐ Triển khai ELK Stack + Filebeat trên mọi server
  ☐ Chuẩn hóa structured logging (JSON) cho ứng dụng mới
  ☐ Cấu hình ILM tự động xoay vòng log, tránh phình dung lượng

GIAI ĐOẠN 4 (APM & Microservices — tuần 7-8):
  ☐ Instrument ứng dụng theo RED method (Micrometer/OpenTelemetry)
  ☐ Triển khai OpenTelemetry Collector + Jaeger cho distributed tracing
  ☐ Liên kết trace_id xuyên suốt Metrics-Logs-Traces
  ☐ Định nghĩa SLO/Error Budget cho từng service quan trọng
  ☐ (Nếu dùng K8s quy mô lớn) Triển khai Service Mesh cho dependency map tự động

GIAI ĐOẠN 5 (Vận hành liên tục):
  ☐ Diễn tập phản ứng alert định kỳ (đảm bảo đúng người nhận đúng kênh)
  ☐ Review và tinh chỉnh ngưỡng alert định kỳ (giảm alert fatigue)
  ☐ Audit dashboard/alert rule theo mỗi case sự cố mới xảy ra — bổ sung
     alert phòng ngừa dựa trên bài học kinh nghiệm (feedback loop)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Nguyên tắc cốt lõi xuyên suốt kiến trúc giám sát:
- Ba trụ cột Metrics-Logs-Traces phải LIÊN KẾT được với nhau qua
  trace_id/request_id chung — giám sát rời rạc từng trụ cột riêng lẻ
  làm chậm đáng kể quá trình điều tra sự cố thực tế
- Mọi alert CRITICAL phải map trực tiếp tới MỘT case cụ thể đã biết
  trước (tham khảo thư viện case study đã xây dựng: HA, multi-database,
  system admin, middleware) — alert không có runbook xử lý tương ứng
  là alert vô nghĩa, chỉ gây nhiễu
- Dashboard Tier-0 phải trả lời được câu hỏi "hệ thống có ổn không"
  trong VÒNG 10 GIÂY nhìn vào, mọi chi tiết sâu hơn thuộc về Tier-1/
  Tier-2 drill-down — tránh nhồi nhét quá nhiều thông tin vào một
  màn hình duy nhất
- Với microservices, RED method + Service Mesh dependency map + SLO/
  Error Budget là bộ ba công cụ thay thế hiệu quả cho việc "biết hết
  mọi chi tiết nội bộ từng service" — tập trung vào ranh giới giao
  tiếp giữa các service (nơi hầu hết sự cố phân tán thực sự xảy ra)
  thay vì cố gắng giám sát chi tiết bên trong từng service riêng lẻ
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Tài liệu tham khảo
- Prometheus Official Documentation — Querying, Alerting Rules, Service Discovery
- Grafana Documentation — Dashboard Provisioning, Data Links
- Elastic Documentation — ELK Stack, Index Lifecycle Management, Filebeat
- OpenTelemetry Documentation — Collector, Instrumentation, Sampling
- Google SRE Workbook — SLO, Error Budget, Multi-Window Multi-Burn-Rate Alerting
- Istio Documentation — Observability, Telemetry API
- www.tranvanbinh.vn — Khóa học Oracle & Monitoring/Observability DBA A-Z Enterprise
