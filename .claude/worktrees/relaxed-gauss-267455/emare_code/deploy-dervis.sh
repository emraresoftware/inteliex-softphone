#!/bin/bash
# Deploy emrecode derviş instance to Docker Swarm
# Usage: ./deploy-dervis.sh <dervish_id> [profile] [org_id] [project_id]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
DERVISH_ID="${1:-dervis-001}"
DERVISH_PROFILE="${2:-general}"
ORG_ID="${3:-org_local}"
PROJECT_ID="${4:-project_local}"

# Paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_COMPOSE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env.${DERVISH_ID}"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose not found. Please install Docker Compose."
        exit 1
    fi
    
    if [ ! -f "$DOCKER_COMPOSE" ]; then
        log_error "docker-compose.yml not found at $DOCKER_COMPOSE"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create .env file for this derviş
create_env_file() {
    log_info "Creating .env file for derviş: $DERVISH_ID"
    
    cat > "$ENV_FILE" <<EOF
# Auto-generated for $DERVISH_ID on $(date -u +%Y-%m-%dT%H:%M:%SZ)

DERVISH_ID=$DERVISH_ID
DERVISH_PROFILE=$DERVISH_PROFILE
ORG_ID=$ORG_ID
PROJECT_ID=$PROJECT_ID

# Hub Connection
HUB_URL=http://dergah-gate:9860
FLEET_TOKEN_FILE=./.fleet-token

# Ollama
OLLAMA_HOST=http://ollama:11434

# Database
DB_URL=sqlite+aiosqlite:////data/emrecode_\${DERVISH_ID}.db
DB_AUTO_CREATE=true

# Resources
RESOURCE_CPU=2
RESOURCE_MEMORY=2G
RESOURCE_CPU_RESERVE=1
RESOURCE_MEMORY_RESERVE=1G

# Workspace
WORKSPACE_PATH=/data/emrecode_workspace/\${DERVISH_ID}

# Port (will be dynamically assigned if using Swarm)
LISTEN_PORT=9870
EOF
    
    log_success "Created $ENV_FILE"
}

# Build Docker image (if not exists)
build_image() {
    log_info "Building Docker image (if needed)..."
    
    if ! docker image inspect emarecloud/emrecode:latest &> /dev/null; then
        log_info "Image not found, building..."
        cd "$SCRIPT_DIR"
        docker build -t emarecloud/emrecode:latest -f Dockerfile .
        log_success "Image built successfully"
    else
        log_info "Image already exists: emarecloud/emrecode:latest"
    fi
}

# Create required volumes and directories
create_volumes() {
    log_info "Creating volumes and directories..."
    
    # Create workspace directory
    WORKSPACE_PATH="/data/emrecode_workspace/${DERVISH_ID}"
    mkdir -p "$WORKSPACE_PATH"
    log_success "Workspace directory: $WORKSPACE_PATH"
    
    # Create/verify token file
    if [ ! -f ".fleet-token" ]; then
        log_warn "Fleet token file not found, creating placeholder"
        touch .fleet-token
        chmod 600 .fleet-token
        echo "generated-token-$(date +%s)" > .fleet-token
    fi
}

# Deploy using docker-compose (standalone)
deploy_standalone() {
    log_info "Deploying emrecode (standalone docker-compose)..."
    
    export DERVISH_ID DERVISH_PROFILE ORG_ID PROJECT_ID
    export WORKSPACE_PATH="/data/emrecode_workspace/${DERVISH_ID}"
    
    cd "$SCRIPT_DIR"
    docker-compose -f "$DOCKER_COMPOSE" --env-file "$ENV_FILE" \
        -p "emrecode-${DERVISH_ID}" up -d
    
    log_success "Deployed emrecode-${DERVISH_ID}"
}

# Deploy to Docker Swarm (if running)
deploy_swarm() {
    log_info "Deploying to Docker Swarm..."
    
    if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q active; then
        log_warn "Docker Swarm not active, falling back to standalone"
        deploy_standalone
        return
    fi
    
    log_info "Swarm detected, deploying as stack..."
    
    # Convert docker-compose to stack
    export DERVISH_ID DERVISH_PROFILE ORG_ID PROJECT_ID
    export WORKSPACE_PATH="/data/emrecode_workspace/${DERVISH_ID}"
    
    # Note: Swarm doesn't support environment variable substitution directly
    # Use a temporary manifest or template-replace approach
    MANIFEST="/tmp/emrecode-${DERVISH_ID}-manifest.yml"
    
    envsubst < "$DOCKER_COMPOSE" > "$MANIFEST"
    
    docker stack deploy -c "$MANIFEST" "emrecode-${DERVISH_ID}"
    
    log_success "Deployed to Swarm as stack: emrecode-${DERVISH_ID}"
    
    # Cleanup
    rm -f "$MANIFEST"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    sleep 3
    
    # Check container status
    if docker ps | grep -q "emrecode-${DERVISH_ID}"; then
        log_success "Container is running"
        
        # Check health
        if docker inspect "emrecode-${DERVISH_ID}" --format='{{.State.Status}}' | grep -q running; then
            log_success "Health check passed"
        fi
    else
        log_error "Container not running"
        log_info "Logs:"
        docker logs "emrecode-${DERVISH_ID}" || true
        return 1
    fi
}

# Display status
show_status() {
    log_info "Deployment Status for $DERVISH_ID:"
    echo ""
    
    docker ps --filter "name=emrecode-${DERVISH_ID}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    log_info "API Health: http://localhost:9870/api/health"
    log_info "WebSocket: ws://localhost:9870/ws"
}

# Cleanup (optional)
cleanup() {
    log_info "Cleanup..."
    # Remove env file if needed
    # rm -f "$ENV_FILE"
}

# Main
main() {
    log_info "=========================================="
    log_info "Emrecode Derviş Deployment Script"
    log_info "=========================================="
    log_info "Derviş ID: $DERVISH_ID"
    log_info "Profile: $DERVISH_PROFILE"
    log_info "Org: $ORG_ID"
    log_info "Project: $PROJECT_ID"
    echo ""
    
    check_prerequisites
    create_env_file
    build_image
    create_volumes
    deploy_standalone  # Can switch to deploy_swarm for Swarm
    verify_deployment
    show_status
    
    log_success "Deployment complete!"
}

# Trap errors
trap cleanup EXIT

# Run main
main "$@"
