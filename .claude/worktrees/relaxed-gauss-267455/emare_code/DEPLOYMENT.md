# Emrecode Container Deployment Guide

Emare Derviş Fleet management via Docker/Podman containers.

## Quick Start

### Prerequisites
- Docker 20.10+ or Podman 4.0+
- Docker Compose 2.0+ or `podman-compose`
- 8GB RAM minimum, 16GB recommended
- Ollama binary (optional, for local model serving)

### 1. Build Docker Image

```bash
cd /Users/emre/Dergah/emare_code

# Build image
docker build -t emarecloud/emrecode:latest -f Dockerfile .

# Verify
docker image inspect emarecloud/emrecode:latest
```

### 2. Deploy Single Derviş (Standalone)

```bash
# Set variables
export DERVISH_ID=dervis-001
export DERVISH_PROFILE=general
export ORG_ID=org_local
export PROJECT_ID=project_local

# Run deployment script
bash deploy-dervis.sh $DERVISH_ID $DERVISH_PROFILE $ORG_ID $PROJECT_ID

# Verify
docker ps | grep emrecode
curl http://localhost:9870/api/health
```

### 3. Deploy Ollama Daemon

**Option A: Standalone (local development)**
```bash
docker run -d \
  --name ollama \
  --gpus all \
  -p 11434:11434 \
  -v ollama_models:/models \
  ollama/ollama:latest
```

**Option B: Docker Swarm (production)**
```bash
# Deploy Ollama stack to Swarm
docker stack deploy -c scripts/ollama-stack.yml ollama-fleet

# Verify
docker service ls | grep ollama
```

### 4. Pull LLM Models

```bash
# Pull models to Ollama
ollama pull qwen2.5-coder:32b  # Primary model for code review (~25GB)
ollama pull llama3.3:70b       # Fallback (~40GB)
ollama pull nomic-embed-text   # Embedding model (~1GB)

# Verify
curl http://localhost:11434/api/tags | jq '.models[] | .name'
```

### 5. Configure Event Bridge

Update `.env.dervis-001`:
```bash
HUB_URL=http://dergah-gate:9860
HUB_TOKEN_FILE=./.fleet-token
```

Create `.fleet-token` with actual token:
```bash
echo "your-fleet-token-here" > .fleet-token
chmod 600 .fleet-token
```

### 6. Test Deployment

```bash
# Health check
curl http://localhost:9870/api/health
# Expected: {"ok":true,"service":"emrecode"}

# List instances
curl http://localhost:9870/api/lifecycle/instances
# Expected: []  (empty initially)

# WebSocket test
wscat -c ws://localhost:9870/ws
# Expected: {"type":"hello","message":"emrecode ws ready"}
```

---

## Scaling to Multiple Derviş

### Deploy Multiple Instances

```bash
#!/bin/bash
for i in {1..5}; do
  DERVISH_ID="dervis-$(printf "%03d" $i)"
  bash deploy-dervis.sh "$DERVISH_ID" "general" "org_local" "project_local"
  sleep 2
done
```

### Docker Compose Orchestration

Use per-derviş override files:
```bash
# dervis-001/.env
DERVISH_ID=dervis-001
LISTEN_PORT=9871

# dervis-002/.env
DERVISH_ID=dervis-002
LISTEN_PORT=9872

# Deploy all
for dir in dervis-*; do
  docker-compose -f docker-compose.yml --env-file "$dir/.env" \
    -p "$dir" up -d
done
```

### Swarm Mode Deployment (Production)

```bash
# Convert docker-compose to stack
DERVISH_ID=dervis-001 envsubst < docker-compose.yml > /tmp/dervis-001.yml

# Deploy
docker stack deploy -c /tmp/dervis-001.yml emrecode-dervis-001

# Verify
docker service ls | grep emrecode
docker service ps emrecode-dervis-001_emrecode
```

---

## Monitoring

### Container Logs

```bash
# Standalone
docker logs -f emrecode-dervis-001

# Swarm
docker service logs -f emrecode-dervis-001_emrecode
```

### Metrics

```bash
# CPU/Memory usage
docker stats emrecode-dervis-001

# Network
docker network inspect emarecloud_network
```

### Health Checks

```bash
# Check service health
docker inspect emrecode-dervis-001 --format='{{.State.Health.Status}}'

# Full status
docker ps --filter "name=emrecode" --format "table {{.Names}}\t{{.Status}}"
```

---

## Configuration Reference

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DERVISH_ID` | `default` | Derviş instance identifier |
| `DERVISH_PROFILE` | `general` | Derviş profile/role |
| `ORG_ID` | `org_local` | Organization ID |
| `PROJECT_ID` | `project_local` | Project ID |
| `HUB_URL` | `http://127.0.0.1:9860` | Hub/gate server |
| `OLLAMA_HOST` | `http://ollama:11434` | Ollama daemon address |
| `DB_URL` | `sqlite+aiosqlite:///./emrecode.db` | Database URL |
| `LISTEN_HOST` | `0.0.0.0` | API listen address |
| `LISTEN_PORT` | `9870` | API listen port |
| `RESOURCE_CPU` | `2` | CPU limit |
| `RESOURCE_MEMORY` | `2G` | Memory limit |

### Port Mappings

| Service | Container Port | Host Port | Purpose |
|---------|---|---|---|
| Emrecode | 9870 | 9870-9879 | FastAPI server (per-instance) |
| Ollama | 11434 | 11434 | LLM serving |
| Traefik (LB) | 8080 | 8080 | Ollama load balancer |

---

## Troubleshooting

### Container won't start

```bash
# Check logs
docker logs emrecode-dervis-001

# Check image
docker image inspect emarecloud/emrecode:latest

# Verify dependencies
docker run --rm emarecloud/emrecode:latest python -c "import fastapi; print(fastapi.__version__)"
```

### Health check failing

```bash
# Manual health test
docker exec emrecode-dervis-001 curl http://localhost:9870/api/health

# Check database
docker exec emrecode-dervis-001 ls -la /data/

# Check Ollama connectivity
docker exec emrecode-dervis-001 curl http://ollama:11434/api/tags
```

### Ollama models not loading

```bash
# Pull model directly
docker exec ollama ollama pull qwen2.5-coder:32b

# Check model directory
docker exec ollama ls -la /models/

# Monitor pull progress
docker logs -f ollama
```

### Out of memory

```bash
# Reduce model size
ollama pull qwen2.5-coder:7b  # Instead of 32b

# Increase Docker memory limits (in docker-compose)
# RESOURCE_MEMORY=4G

# Check current usage
docker stats
```

---

## Production Checklist

- [ ] Docker images built and pushed to registry
- [ ] Ollama models pre-downloaded and cached
- [ ] `.fleet-token` configured and distributed
- [ ] Database backup strategy defined
- [ ] Network policies configured (isolation)
- [ ] Resource limits set per derviş
- [ ] Monitoring/alerting enabled
- [ ] Log aggregation configured
- [ ] Rollback plan tested
- [ ] Security audit completed

---

## Next Steps

1. **Faz 1 Complete:** Docker images + compose templates ready
2. **Faz 2:** Provisioning service for on-demand derviş creation
3. **Faz 3:** Auto-scaling + network policies + backup

See `/memories/session/emare_code_analysis.md` for detailed architecture notes.
