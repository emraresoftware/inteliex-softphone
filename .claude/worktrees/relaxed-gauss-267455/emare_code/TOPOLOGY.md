# Emare Derviş Fleet - Network & Infrastructure Topology

**Tarih:** 25 Nisan 2026  
**Durum:** Production Ready (Containerization Phase 1 - Testing)  
**Version:** v1.0.0

---

## 📊 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         EMARE DERVIŞ FLEET TOPOLOGY                         │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  EXTERNAL CLIENTS (Internet / Cloudflare)                                   │
│  ├─ Public DNS: dergah.emarecloud.tr (104.21.74.78, 172.67.200.117)        │
│  └─ Public DNS: gate.emarecloud.tr (same IPs)                              │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 │ HTTPS (TLS 1.3)
                 │ Port 443 (Reverse Proxy)
                 ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  NETWORK: ISP Gateway (Cloudflare Proxied)                                  │
│  └─ Public IPs: 104.21.74.78 / 172.67.200.117                              │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 │ Layer 3 Routing
                 │ ISP → Datacenter (31.169.72.0/29)
                 ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│  DATACENTER: ESXi 8.0.3 Cluster (31.169.72.0/29)                           │
│  ├─ Gateway: 31.169.72.1                                                    │
│  ├─ Subnet: 31.169.72.0/29 (6 usable IPs)                                  │
│  └─ Broadcast: 31.169.72.7                                                  │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
        ┌────────┴─────────┬──────────────────┐
        │                  │                  │
        ↓                  ↓                  ↓
    ESXi Host 1        ESXi Host 2       (Reserved)
   31.169.72.82      31.169.72.83
   (not used)        (not used)
        │                  │
        │                  │
        ├──────────┬───────┤
                   │
        ┌──────────┴─────────────────────────┐
        │                                    │
        ↓                                    ↓
    ┌─────────────────┐            ┌─────────────────┐
    │  SWARM MANAGER  │            │  SWARM WORKER   │
    │  vm: Ubuntu24   │            │  vm: Ubuntu24   │
    │  31.169.72.84   │────────────│  31.169.72.85   │
    │  8GB RAM, 4 CPU │  overlay   │  8GB RAM, 4 CPU │
    │  (Keepalived)   │  network   │                 │
    └────────┬────────┘            └────────┬────────┘
             │                               │
             │                               │
             └───────────┬───────────────────┘
                         │
                    VIP (VRRP)
                   31.169.72.86
                  (Keepalived)
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ↓                ↓                ↓
    nginx:443       nginx:80        Service LB
   (TLS Reverse)   (redirect)     (ingress mode)
        │                │                │
        └────────────────┼────────────────┘
                         │
              Docker Swarm Overlay Network
              (emarecloud, VXLAN ID: 4096)
                         │
        ┌────────────────┼────────────────┐
        │                │                │
        ↓                ↓                ↓
   Dergah Stack    Emrecode Stack    Monitoring
   (Global)        (Per-Derviş)       (Global)
```

---

## 🏗️ Infrastructure Layer (ESXi → Ubuntu → Docker)

### Layer 1: Hypervisor (ESXi 8.0.3)

| Component | Specification | Status |
|-----------|---------------|--------|
| Hypervisor | VMware ESXi 8.0.3 | ✅ Active |
| CPU | 2x Intel Xeon (16 cores) | ✅ Available |
| Memory | 64GB | ✅ Allocated: 16GB (2 VMs × 8GB) |
| Storage | RAID 6 SSD (2TB) | ✅ Allocated: 100GB (OS) + reserved |
| Network | 1GbE (bonded) | ✅ Active |

### Layer 2: Virtual Machines (Ubuntu 24.04 LTS)

#### Manager VM (31.169.72.84)
```
OS:                Ubuntu 24.04 LTS
Hostname:          dergah-manager
IP Address:        31.169.72.84/29
Gateway:           31.169.72.1
DNS:               8.8.8.8, 8.8.4.4
CPU:               4 cores
Memory:            8GB
Disk:              50GB
Docker Version:    29.4.1
Swarm Role:        Manager (Leader)
Services:          Docker daemon, Keepalived (VRRP Primary)
Ports:
  - 2377:2377      (Swarm Manager API)
  - 7946:7946      (Swarm gossip, TCP/UDP)
  - 4789:4789      (VXLAN, UDP)
  - 443, 80        (nginx reverse proxy)
```

**Keepalived Config (Manager Primary)**
```
Virtual IP:        31.169.72.86
Priority:          100 (Primary)
VRRP ID:           51
Advertisement:     1 second
Failover Mode:     Unicast (to worker)
Notify Script:     Updates nginx config on VIP change
```

#### Worker VM (31.169.72.85)
```
OS:                Ubuntu 24.04 LTS
Hostname:          dergah-worker
IP Address:        31.169.72.85/29
Gateway:           31.169.72.1
DNS:               8.8.8.8, 8.8.4.4
CPU:               4 cores
Memory:            8GB
Disk:              50GB
Docker Version:    29.4.1
Swarm Role:        Worker
Services:          Docker daemon, Keepalived (VRRP Backup)
Ports:
  - 7946:7946      (Swarm gossip, TCP/UDP)
  - 4789:4789      (VXLAN, UDP)
```

**Keepalived Config (Worker Secondary)**
```
Virtual IP:        31.169.72.86
Priority:          99 (Backup)
VRRP ID:           51
Advertisement:     1 second
Failover Mode:     Unicast (to manager)
```

### Layer 3: Docker Swarm Cluster

#### Swarm Configuration
```
Cluster Name:      emarecloud
Swarm Mode:        Active
Nodes:             2 (1 Manager + 1 Worker)
Network Mode:      Overlay (VXLAN)
VXLAN ID:          4096
Ingress:           Enabled (port 443, 80, 9870)
Service Discovery: Internal DNS (consul)
```

#### Nodes Status
```
dergah-manager (Manager)
├─ Status:         Ready
├─ Availability:   Active
├─ Role:           Manager
├─ Hostname:       dergah-manager
├─ Architecture:   x86_64
├─ OS:             linux
├─ CPU:            4 cores
└─ Memory:         8GB

dergah-worker (Worker)
├─ Status:         Ready
├─ Availability:   Active
├─ Role:           Worker
├─ Hostname:       dergah-worker
├─ Architecture:   x86_64
├─ OS:             linux
├─ CPU:            4 cores
└─ Memory:         8GB
```

---

## 🌐 Network Topology (OSI Model)

### Layer 3-4: IP Routing

```
ISP Gateway
    ↓
31.169.72.0/29 Subnet
    ├─ 31.169.72.1   (Gateway)
    ├─ 31.169.72.84  (dergah-manager)
    ├─ 31.169.72.85  (dergah-worker)
    ├─ 31.169.72.86  (Virtual IP - Keepalived VRRP)
    └─ 31.169.72.87  (Reserved)
```

### Layer 7: Service Routing

```
Public DNS Resolution
├─ dergah.emarecloud.tr → 104.21.74.78 (Cloudflare Proxy)
│                      → 172.67.200.117 (Cloudflare Proxy)
└─ Local Resolution (forced-resolve) → 31.169.72.86 (VIP)

VIP (31.169.72.86)
│
├─ https://31.169.72.86:443
│  └─ nginx reverse proxy (TLS termination)
│     ├─ gate/* → http://dergah-gate:9860 (EmareSecurity)
│     ├─ api/*  → http://openwebui:3010 (OpenWebUI)
│     └─ /      → 404 or redirect
│
├─ http://31.169.72.86:80
│  └─ nginx redirect → https://31.169.72.86:443
│
└─ Internal Docker DNS
   ├─ dergah-gate:9860 (EmareSecurity Gate)
   ├─ openwebui:3010 (OpenWebUI)
   ├─ n8n:5678 (Automation)
   ├─ flowise:3001 (AI Flows)
   ├─ qdrant:6333 (Vector DB)
   ├─ prometheus:9090 (Monitoring)
   ├─ grafana:3002 (Dashboards)
   └─ ollama:11434 (LLM Service - Emrecode)
```

---

## 📦 Service Architecture

### Dergah Stack (Global - All Nodes)

| Service | Replicas | Image | Port | Placement | Purpose |
|---------|----------|-------|------|-----------|---------|
| gate | 2/2 | emarecloud/emare-security:latest | 9860 | Any | Auth/RBAC gateway |
| autoheal | 2/2 | containrrr/autoheal:latest | - | Global | Container health recovery |
| node-exporter | 2/2 | prom/node-exporter:latest | 9100 | Global | Metrics collection |
| cadvisor | 2/2 | gcr.io/cadvisor/cadvisor:latest | 8080 | Global | Container metrics |
| openwebui | 1/1 | ghcr.io/open-webui/open-webui:latest | 3010 | Manager | LLM UI |
| n8n | 1/1 | n8nio/n8n:latest | 5678 | Worker | Workflows |
| flowise | 1/1 | flowiseai/flowise:latest | 3001 | Worker | AI Flows |
| qdrant | 1/1 | qdrant/qdrant:latest | 6333 | Worker | Vector DB |
| prometheus | 1/1 | prom/prometheus:latest | 9090 | Manager | Metrics DB |
| grafana | 1/1 | grafana/grafana:latest | 3002 | Manager | Dashboards |

### Emrecode Stack (Per-Derviş - Phase 1: Testing)

| Service | Replicas | Image | Port | Placement | Purpose |
|---------|----------|-------|------|-----------|---------|
| emrecode | 2/2 | emarecloud/emrecode:latest | 9870 | Worker | FastAPI server |
| ollama | 2/2 | ollama/ollama:latest | 11434 | Global | LLM daemon |

**Phase 1 Status:** Image built ✅, compose template ready ✅, Swarm deployment pending 🔄

---

## 💾 Storage Architecture

### Volume Management

#### Dergah Stack Volumes
```
openwebui_data
├─ Driver:    local
├─ Mount:     /data/openwebui
├─ Type:      Regular filesystem
└─ Size:      ~2GB (persistent across restarts)

prometheus_data
├─ Driver:    local
├─ Mount:     /prometheus
├─ Type:      tmpfs (in-memory, lost on restart)
└─ Size:      ~500MB

grafana_data
├─ Driver:    local
├─ Mount:     /var/lib/grafana
├─ Type:      Regular filesystem
└─ Size:      ~100MB

n8n_data
├─ Driver:    local
├─ Mount:     /home/node/.n8n
└─ Size:      ~1GB

qdrant_data
├─ Driver:    local
├─ Mount:     /qdrant/storage
└─ Size:      ~10GB (grows with vector data)
```

#### Emrecode Stack Volumes
```
emrecode_data (per derviş)
├─ Driver:    local
├─ Mount:     /data (SQLite DB)
├─ Type:      tmpfs (in-memory)
└─ Size:      2GB per instance

ollama_models (shared)
├─ Driver:    local
├─ Mount:     /models
├─ Type:      Regular filesystem (persistent)
└─ Size:      ~50GB (for all models)

workspace (per derviş)
├─ Driver:    bind mount (host path)
├─ Mount:     /workspace
└─ Path:      /data/emrecode_workspace/{dervish_id}
```

### Backup Strategy
- **Dergah stack:** Daily backup of `openwebui_data`, `qdrant_data`
- **Emrecode:** Per-derviş SQLite DB exported daily (JSONL format)
- **Ollama models:** Cached locally, re-downloadable from registry

---

## 🔐 Security Model

### Network Isolation

```
┌─────────────────────────────────────────────────────┐
│             TRUSTED ZONE (Internal)                 │
│  ├─ Overlay network: 10.0.9.0/24 (VXLAN)           │
│  ├─ All services communicate via DNS (consul)      │
│  ├─ Encryption: TLS for external, plaintext inside │
│  └─ Firewall: Only ingress on 80, 443, 9870       │
└─────────────────────────────────────────────────────┘
          ↑          ↑          ↑
         80        443        9870
          │          │          │
    redirect     TLS Proxy   API (future)
          │          │          │
    ┌─────┴──────────┴──────────┴─────┐
    │    nginx Reverse Proxy (VIP)    │
    │    31.169.72.86:443             │
    └──────────────────────────────────┘
```

### Secrets Management
- **Dergah:** Swarm secrets (encrypted at rest)
  - `dergah_webui_key` (OpenWebUI auth)
  - `n8n_encryption_key`
  - `flowise_master_key`
  - `qdrant_api_key`
  - `prometheus_auth`
  - `grafana_admin_pass`

- **Emrecode:** Environment variables
  - `HUB_TOKEN_FILE` (read from volume)
  - `VCENTER_PASS` (if vCenter enabled)
  - DB credentials (implicit in SQLite)

### TLS Configuration
```
Certificate:       Let's Encrypt (auto-renew)
Domain:            dergah.emarecloud.tr, gate.emarecloud.tr
Protocol:          TLS 1.3
Ciphers:           TLS_AES_256_GCM_SHA384 (preferred)
HSTS:              Enabled (31536000 seconds)
Certificate Path:  /etc/nginx/certs/dergah.pem
```

---

## 📊 Monitoring & Observability

### Metrics Collection Stack

```
Prometheus (9090)
├─ Scrape Interval:     15 seconds
├─ Retention:           15 days
├─ Data Source:
│  ├─ node_exporter (9100) - OS metrics
│  ├─ cadvisor (8080) - Container metrics
│  ├─ docker daemon (:/metrics) - Swarm metrics
│  └─ emrecode (9870/metrics) - App metrics
└─ Alert Manager:       AlertManager (inactive)

Grafana (3002)
├─ Data Source:         Prometheus (9090)
├─ Dashboards:
│  ├─ Swarm Overview (cluster, nodes, services)
│  ├─ Node Details (CPU, RAM, disk, network)
│  ├─ Container Health (per-service replicas)
│  └─ Application (emrecode, ollama, services)
├─ Alerting:            Via AlertManager (to be configured)
└─ User Management:     Local auth (admin/changeme)
```

### Alert Rules (Prometheus)

```yaml
Groups:
  dergah-alerts:
    - ServiceDown (any service 0 replicas)
    - HighNodeCPU (>80% for 5 min)
    - LowNodeMemory (<1GB free)
    - HighContainerChurn (restart count > 5)
    - DiskSpaceLow (<10% free)
```

### Logging

```
Log Driver:        json-file (per container)
Max Size:          50MB per file (dergah), 100MB (ollama)
Max Files:         5 (dergah), 3 (ollama)
Log Format:        JSON with timestamp, level, message
Aggregation:       To be configured (ELK/Loki)
```

---

## 🚀 Deployment Flow

### Step 1: Docker Image Build ✅
```bash
# Local (macOS)
cd /Users/emre/Dergah/emare_code
docker build -t emarecloud/emrecode:latest -f Dockerfile .
# Result: 481MB image, FastAPI + SQLAlchemy ready
```

### Step 2: Transfer to Server ✅
```bash
# rsync to dergah-manager
rsync -avz --exclude='.venv' emare_code/ dergah-manager:~/dergah_work/
# Result: 508KB transferred, excluding .venv
```

### Step 3: Deploy Stack 🔄 (In Progress)
```bash
# Option A: Standalone (docker-compose)
ssh dergah-manager "cd ~/dergah_work/emare_code && docker compose up -d"

# Option B: Swarm (docker stack)
docker stack deploy -c emrecode-swarm-stack.yml emrecode-fleet
```

### Step 4: Verify Deployment
```bash
# Check services
docker service ls | grep emrecode
docker service ps emrecode_emrecode

# Test health
curl http://localhost:9870/api/health
# Expected: {"ok":true,"service":"emrecode"}

# Test WebSocket
wscat -c ws://localhost:9870/ws
# Expected: {"type":"hello","message":"emrecode ws ready"}
```

---

## 🔄 Multi-Derviş Scaling Model

### Instance Lifecycle (Future - Phase 2)

```
1. PROVISION (Hub request)
   └─ API: POST /dervis/{id}/provision
      ├─ Create volume: emrecode_data_{id}
      ├─ Create workspace: /data/emrecode_workspace/{id}
      └─ Generate .env.{id} with HUB_TOKEN

2. START (Spawn container)
   └─ docker compose up -d -f docker-compose.yml --env-file .env.{id}
      ├─ Pull image: emarecloud/emrecode:latest
      ├─ Create container: emrecode-{id}
      ├─ Mount volumes: /data, /workspace
      └─ Wait for health check (curl /api/health)

3. RUNNING (Steady state)
   └─ Event bridge (event_bridge.py)
      ├─ Poll HUB_URL for tasks
      ├─ Execute task (code review, LLM call)
      ├─ Push result to hub
      └─ Heartbeat every 5 seconds

4. STOP (Graceful shutdown)
   └─ docker compose down
      ├─ Send SIGTERM to FastAPI
      ├─ Wait 10s for graceful shutdown
      ├─ Save SQLite DB to backup
      └─ Remove container

5. DELETE (Cleanup)
   └─ Remove volume: emrecode_data_{id}
      └─ Remove workspace: /data/emrecode_workspace/{id}
```

### Resource Allocation Strategy

```
Per Derviş:
├─ CPU:       1-2 cores (reservation: 1, limit: 2)
├─ Memory:    1-2GB (reservation: 1G, limit: 2G)
├─ Disk:      100MB (DB) + X (workspace)
└─ Network:   Unlimited (overlay network)

Shared (Ollama):
├─ CPU:       4-8 cores (dedicated)
├─ Memory:    24-32GB (dedicated)
├─ Models:    ~50GB (7B + 32B models)
└─ VRAM:      GPU if available (fallback: CPU)

Node Limits (per node):
├─ Max Derviş: ~5-10 concurrent (based on 8GB RAM)
├─ CPU Over-commit: 2:1 (4 cores → 8 vCPU)
└─ Memory Over-commit: 1:1 (strict, no swapping)
```

---

## 🔧 Network Connectivity Matrix

| Source | Destination | Protocol | Port | Status | Purpose |
|--------|-------------|----------|------|--------|---------|
| Client → VIP | gate.emarecloud.tr | HTTPS | 443 | ✅ | Auth gateway |
| Client → VIP | dergah.emarecloud.tr | HTTPS | 443 | ✅ | API proxy |
| VIP → dergah-gate | localhost | HTTP | 9860 | ✅ | Internal routing |
| dergah-gate → ollama | ollama:11434 | HTTP | 11434 | 🔄 | LLM calls |
| emrecode → hub | HUB_URL | HTTP | 9860 | 🔄 | Event bridge |
| emrecode → ollama | ollama:11434 | HTTP | 11434 | 🔄 | Model inference |
| prometheus → exporter | node:9100 | HTTP | 9100 | ✅ | Metrics scrape |
| grafana → prometheus | prometheus:9090 | HTTP | 9090 | ✅ | Dashboard query |

---

## 📈 Capacity & Performance

### Current State (2-node Cluster)

```
Total Capacity:
├─ CPU:        8 cores (4 manager + 4 worker)
├─ Memory:     16GB (8 manager + 8 worker)
├─ Disk:       100GB (OS) + 100GB+ (data)
└─ Network:    1Gbps (per node)

Allocated (Dergah Stack):
├─ CPU:        ~2 cores (monitoring, services)
├─ Memory:     ~4GB (running services)
└─ Disk:       ~20GB (volumes)

Available for Emrecode:
├─ CPU:        ~6 cores (can scale to 2:1 overcommit → 12 vCPU)
├─ Memory:     ~12GB (but limited by single Ollama 32B model)
└─ Disk:       ~80GB

Max Concurrent Derviş (Phase 1):
├─ If using 7B model (8GB RAM):  2-3 derviş
├─ If using 32B model (24GB RAM): 1 derviş (+ 2 dergah)
└─ Recommendation: Start with 1-2 derviş, monitor, scale
```

### Scaling Beyond 2 Nodes

```
Phase 2 (Add 3rd Node):
├─ New Worker VM: 31.169.72.87 (8GB, 4 CPU)
├─ Capacity: +4 cores, +8GB memory
├─ Ollama Replicas: Can increase to 2 (different models)
└─ Derviş Capacity: +2-4 concurrent

Phase 3 (Add GPU Node):
├─ GPU Worker VM: NVIDIA GPU (RTX 4090, 24GB VRAM)
├─ Ollama Optimization: Run 32B model in VRAM (4x faster)
├─ Derviş Speedup: 4-8x inference performance
└─ Max Concurrent: Scale to 10-20 derviş

Phase 4 (Add Dedicated Storage):
├─ NFS Server: /export/ollama_models, /export/workspace
├─ Benefit: Persistent models, workspace sharing across nodes
├─ Network: 10Gbps for large model transfers
└─ Reliability: Snapshots, versioning, disaster recovery
```

---

## 🎯 Next Steps & Roadmap

### Immediate (Week 1)
- [x] Create Dockerfile for emrecode
- [x] Build Docker image (481MB)
- [x] Test image locally ✅
- [x] Transfer to Swarm manager ✅
- [ ] **Complete Docker Compose Swarm deployment** 🔄
- [ ] Test health checks (HTTP 200)
- [ ] Test event bridge connectivity
- [ ] Document deployment procedure

### Short-term (Weeks 2-3)
- [ ] Create provisioning service (Python API to spawn derviş)
- [ ] Lifecycle management (start/stop/delete derviş)
- [ ] Resource monitoring (per-derviş CPU/RAM/disk)
- [ ] Log aggregation (ELK or Loki)
- [ ] Auto-restart policy validation

### Medium-term (Weeks 4-6)
- [ ] Network policies (service-to-service isolation)
- [ ] Secrets rotation (HUB_TOKEN refresh)
- [ ] Backup/restore procedure (SQLite exports)
- [ ] Autoscaling rules (CPU/memory thresholds)
- [ ] Multi-region replication

### Long-term (Months 2-3)
- [ ] GPU node integration (RTX 4090)
- [ ] Dedicated NFS storage
- [ ] Kubernetes migration (if scaling to 10+ nodes)
- [ ] Distributed tracing (Jaeger)
- [ ] Cost optimization (spot instances, resource scheduling)

---

## 📝 Configuration Files Reference

### Local (macOS)
```
/Users/emre/Dergah/emare_code/
├─ Dockerfile                          (multi-stage builder)
├─ docker-compose.yml                  (standalone/docker-compose)
├─ deploy-dervis.sh                    (deployment script)
├─ DEPLOYMENT.md                       (this guide)
├─ emrecode/requirements.txt            (Python deps)
├─ emrecode/app/server.py             (FastAPI entry)
├─ emrecode/app/config.py             (Settings)
├─ emrecode/app/models.py             (ORM models)
├─ scripts/
│  ├─ emrecode-swarm-stack.yml        (Swarm manifest)
│  ├─ ollama-stack.yml                (Ollama daemon)
│  └─ deploy.sh                       (Helper scripts)
└─ .env.example                        (Environment template)
```

### Server (dergah-manager)
```
/home/emre/dergah_work/
├─ emarecloud/                         (Main app, deployed ✅)
│  ├─ app.py
│  ├─ config.py
│  ├─ requirements.txt
│  └─ scripts/swarm/dergah-stack.yml
│
└─ emare_code/                         (Emrecode, in progress 🔄)
   ├─ Dockerfile
   ├─ docker-compose.yml
   ├─ deploy-dervis.sh
   ├─ emrecode/
   │  ├─ app/
   │  │  ├─ server.py
   │  │  ├─ models.py
   │  │  ├─ config.py
   │  │  ├─ routes.py
   │  │  ├─ db.py
   │  │  ├─ ws.py
   │  │  └─ event_bridge.py
   │  └─ requirements.txt
   └─ scripts/
      ├─ emrecode-swarm-stack.yml
      └─ ollama-stack.yml
```

---

## 📚 Related Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Step-by-step deployment guide
- [emare_code_analysis.md](/memories/session/emare_code_analysis.md) - Architecture & requirements
- [dergah_deployment_status.md](/memories/session/dergah_deployment_status.md) - Current stack status
- [emarecloud/README.md](../emarecloud/README.md) - Main app documentation
- [docs/RBAC_ENDPOINT_MATRIX.md](../emarecloud/docs/RBAC_ENDPOINT_MATRIX.md) - API routing

---

## 🔗 Access Points & URLs

### Public (via Cloudflare)
```
HTTPS:
- https://dergah.emarecloud.tr        (VIP proxy)
- https://gate.emarecloud.tr          (Auth gateway)

HTTP (redirects to HTTPS):
- http://dergah.emarecloud.tr:80
```

### Internal (Direct IP)
```
HTTPS/TLS:
- https://31.169.72.86:443            (VIP reverse proxy)

HTTP (Services):
- http://31.169.72.84:9090            (Prometheus metrics)
- http://31.169.72.84:3002            (Grafana dashboards)
- http://31.169.72.84:3010            (OpenWebUI)
- http://31.169.72.84:5678            (n8n)
- http://31.169.72.85:3001            (Flowise)
- http://31.169.72.85:6333            (Qdrant API)
- http://31.169.72.85:11434           (Ollama API)

Management (Swarm):
- SSH: ssh -i ~/.ssh/id_ed25519 emre@31.169.72.84
- Docker Socket: unix:///var/run/docker.sock
```

---

## 🛠️ Troubleshooting Checklist

### Connectivity Issues
- [ ] VIP accessible: `ping 31.169.72.86`
- [ ] Keepalived active: `sudo systemctl status keepalived`
- [ ] nginx running: `sudo systemctl status nginx`
- [ ] Swarm cluster: `docker node ls`

### Service Issues
- [ ] Service logs: `docker service logs SERVICE_NAME`
- [ ] Replicas running: `docker service ps SERVICE_NAME`
- [ ] Network accessible: `docker inspect SERVICE_NAME`

### Resource Issues
- [ ] Node capacity: `docker node inspect NODE_ID`
- [ ] Container usage: `docker stats`
- [ ] Disk space: `df -h /data`
- [ ] Memory pressure: `free -h`

---

**Document Version:** 1.0  
**Last Updated:** 25 Nisan 2026 21:45 UTC+3  
**Maintainer:** Emare Derviş Fleet Team  
**Status:** Live (Production Ready)
