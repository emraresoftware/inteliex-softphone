#!/usr/bin/env bash
# Ajan Otomatik Tetikleyici Daemon v2.0
# TALIMATLAR.md dosyalarındaki değişiklikleri izler ve yeni görevler varsa çalıştırır
#
# İyileştirmeler v2.0:
# - Daha iyi loglama (tarihli log dosyaları)
# - Concurrent çalışma desteği (workspace başına ayrı PID)
# - Error recovery
# - Dry-run modu
# - Ajan durumu takibi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER_SCRIPT="${AJAN_RUNNER_SCRIPT:-$ROOT_DIR/scripts/ajan_workspace_runner.py}"
RUNNER_MAX_STEPS="${AJAN_RUNNER_MAX_STEPS:-8}"
LOG_DIR="$ROOT_DIR/data/ajan_logs"
PID_DIR="/tmp/ajan_tetikleyici_pids"

# Log setup
mkdir -p "$LOG_DIR" "$PID_DIR"

log() {
    local level="${1:-INFO}"
    local msg="${2:-}"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$ts] [$level] $msg" | tee -a "$LOG_DIR/tetikleyici_$(date '+%Y%m%d').log"
}

error() { log "ERROR" "$*"; }
warn()  { log "WARN"  "$*"; }
info()  { log "INFO"  "$*"; }
debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        log "DEBUG" "$*"
    fi
}

# Tek instance kilidi
acquire_lock() {
    local lock_file="$PID_DIR/main.lock"
    
    if mkdir "$lock_file" 2>/dev/null; then
        echo "$$" > "$lock_file/pid"
        trap "rm -rf '$lock_file' 2>/dev/null || true" EXIT INT TERM
        info "Lock acquired: $$"
        return 0
    fi
    
    local existing_pid
    existing_pid="$(cat "$lock_file/pid" 2>/dev/null || true)"
    
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        info "Daemon zaten calisiyor (PID=$existing_pid)"
        exit 0
    fi
    
    warn "Stale lock temizleniyor"
    rm -rf "$lock_file"
    mkdir "$lock_file" 2>/dev/null || { error "Lock alinamadi"; exit 1; }
    echo "$$" > "$lock_file/pid"
    trap "rm -rf '$lock_file' 2>/dev/null || true" EXIT INT TERM
}

# Python binary bul
find_python() {
    local pythons=(
        "$ROOT_DIR/.venv/bin/python3.14"
        "$ROOT_DIR/.venv/bin/python3"
        "$(command -v python3.14 2>/dev/null || true)"
        "$(command -v python3 2>/dev/null || true)"
    )
    
    for py in "${pythons[@]}"; do
        if [[ -x "$py" ]]; then
            echo "$py"
            return 0
        fi
    done
    
    error "Python bulunamadi"
    return 1
}

# Workspace PID yönetimi
workspace_pid_file() {
    local workspace_name="$1"
    echo "$PID_DIR/workspace_${workspace_name}.pid"
}

is_workspace_running() {
    local workspace_name="$1"
    local pid_file
    pid_file="$(workspace_pid_file "$workspace_name")"
    
    if [[ ! -f "$pid_file" ]]; then
        return 1
    fi
    
    local pid
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    
    if [[ -z "$pid" ]]; then
        rm -f "$pid_file"
        return 1
    fi
    
    if kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    
    # Stale PID
    rm -f "$pid_file"
    return 1
}

set_workspace_pid() {
    local workspace_name="$1"
    local pid_file
    pid_file="$(workspace_pid_file "$workspace_name")"
    echo "$2" > "$pid_file"
}

clear_workspace_pid() {
    local workspace_name="$1"
    rm -f "$(workspace_pid_file "$workspace_name")"
}

# unchecked maddeleri kontrol et
has_unchecked_items() {
    local talimat_file="$1"
    
    if [[ ! -f "$talimat_file" ]]; then
        return 1
    fi
    
    if grep -q '^\s*-\s*\[\s\]' "$talimat_file" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Artifact extraction
extract_artifacts() {
    local talimat_file="$1"
    local py="$2"
    
    "$py" - "$talimat_file" <<'PYEOF' 2>/dev/null || echo "[]"
import json
import re
from pathlib import Path

talimat_file = Path("$1")
if not talimat_file.exists():
    print("[]")
    exit(0)

content = talimat_file.read_text(encoding="utf-8")
items = []
seen = set()

for line in content.splitlines():
    match = re.match(r"^\s*-\s*\[\s\]\s+(.*)$", line)
    if not match:
        continue
    
    item = match.group(1).strip()
    
    # Backtick quoted paths
    for candidate in re.findall(r"`([^`]+)`", item):
        suffix = Path(candidate.strip("`'\".,:;()[]{}")).suffix.lower()
        if suffix in {".txt", ".md", ".json", ".ndjson", ".csv", ".log", ".xml", ".yaml", ".yml"}:
            key = candidate.strip()
            if key not in seen:
                seen.add(key)
                items.append(key)
    
    # File extension patterns
    for candidate in re.findall(r"\b[\w./-]+\.(?:txt|md|json|ndjson|csv|log|xml|yaml|yml)\b", item):
        key = candidate.strip()
        if key not in seen:
            seen.add(key)
            items.append(key)

print(json.dumps(items, ensure_ascii=False))
PYEOF
}

# Ana tetikleyici döngüsü
run_tetikleyici() {
    local py
    py="$(find_python)" || exit 1
    
    info "Python: $py"
    
    # fswatch kontrolü
    if ! command -v fswatch >/dev/null 2>&1; then
        error "fswatch gerekli: brew install fswatch"
        exit 1
    fi
    
    local workspaces_dir="$ROOT_DIR/agents/workspaces"
    if [[ ! -d "$workspaces_dir" ]]; then
        error "Workspaces dizini yok: $workspaces_dir"
        exit 1
    fi
    
    info "Tetikleyici baslatildi"
    info "Izlenen dizin: $workspaces_dir"
    info "Runner script: $RUNNER_SCRIPT"
    info "Max steps: $RUNNER_MAX_STEPS"
    
    # Her workspace için sayaç
    local run_count=0
    
    while true; do
        local changed_count=0
        
        # fswatch tek değişiklik raporlar, sürekli döngü
        while IFS= read -r -d '' changed_file; do
            local basename
            basename="$(basename "$changed_file")"
            
            # Sadece TALIMATLAR.md dosyalarını işle
            if [[ "$basename" != "TALIMATLAR.md" ]]; then
                debug "Atlandi (TALIMATLAR.md degil): $changed_file"
                continue
            fi
            
            if [[ ! -f "$changed_file" ]]; then
                continue
            fi
            
            local ts
            ts="$(date '+%Y-%m-%d %H:%M:%S')"
            
            local workspace_dir
            workspace_dir="$(dirname "$changed_file")"
            
            local workspace_name
            workspace_name="$(basename "$workspace_dir")"
            
            echo "[$ts] Degisiklik: $workspace_name"
            
            # unchecked maddeler var mı kontrol et
            if ! has_unchecked_items "$changed_file"; then
                echo "[$ts] [$workspace_name] Yeni gorev yok, atlandi"
                continue
            fi
            
            # Workspace zaten çalışıyor mu?
            if is_workspace_running "$workspace_name"; then
                echo "[$ts] [$workspace_name] Zaten calisiyor, atlandi"
                continue
            fi
            
            echo "[$ts] [$workspace_name] Gorevler tespit edildi, ajan baslatiliyor..."
            
            # Arka planda çalıştır
            (
                set_workspace_pid "$workspace_name" "$$"
                
                local run_log="$LOG_DIR/run_${workspace_name}_$(date '+%Y%m%d_%H%M%S').log"
                local artifacts
                artifacts="$(extract_artifacts "$changed_file" "$py")"
                
                echo "[$ts] Runner baslatildi" >> "$run_log"
                echo "[$ts] Artifacts: $artifacts" >> "$run_log"
                
                "$py" "$RUNNER_SCRIPT" \
                    --workspace-dir "$workspace_dir" \
                    --workspace-name "$workspace_name" \
                    --max-steps "$RUNNER_MAX_STEPS" \
                    >> "$run_log" 2>&1
                
                local runner_exit=$?
                
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Runner tamamlandi (exit=$runner_exit)" >> "$run_log"
                
                clear_workspace_pid "$workspace_name"
                
                # Koordinatöre bildirim
                if [[ -f "$ROOT_DIR/scripts/dervis_mesajlasma.py" ]]; then
                    "$py" - "$workspace_name" "$runner_exit" "$run_log" <<'MSGPY' 2>/dev/null || true
import sys
sys.path.insert(0, "/Users/emre/Dergah/scripts")
try:
    from dervis_mesajlasma import send_message
    agent = sys.argv[1]
    exit_code = sys.argv[2]
    log_file = sys.argv[3]
    
    content = f"Ajan runner tamamlandi: {agent} (exit={exit_code})\nLog: {log_file}"
    send_message("system", "yonetici", content, kind="system_notification")
except Exception as e:
    pass
MSGPY
                fi
                
            ) &
            
            set_workspace_pid "$workspace_name" "$!"
            changed_count=$((changed_count + 1))
            run_count=$((run_count + 1))
            
            echo "[$ts] [$workspace_name] Arka plan gorevi baslatildi"
            
        done < <(fswatch -0 -r "$workspaces_dir" 2>/dev/null || echo "")
        
        # Hiç değişiklik yoksa 5 saniye bekle
        if [[ $changed_count -eq 0 ]]; then
            sleep 5
        fi
        
    done
}

# Status komutu
show_status() {
    echo "=== Ajan Tetikleyici Durumu ==="
    echo ""
    
    # Ana daemon
    local lock_file="$PID_DIR/main.lock"
    if [[ -f "$lock_file/pid" ]]; then
        local pid
        pid="$(cat "$lock_file/pid")"
        if kill -0 "$pid" 2>/dev/null; then
            echo "Ana Tetikleyici: CALISIYOR (PID=$pid)"
        else
            echo "Ana Tetikleyici: DURMUS (stale lock)"
        fi
    else
        echo "Ana Tetikleyici: CALISMIYOR"
    fi
    
    echo ""
    echo "Calisan Workspace'ler:"
    
    local any_running=0
    for pid_file in "$PID_DIR"/workspace_*.pid; do
        if [[ -f "$pid_file" ]]; then
            local workspace_name
            workspace_name="$(basename "$pid_file" | sed 's/^workspace_//;s/\.pid$//')"
            local pid
            pid="$(cat "$pid_file")"
            
            if kill -0 "$pid" 2>/dev/null; then
                echo "  - $workspace_name: CALISIYOR (PID=$pid)"
                any_running=1
            else
                echo "  - $workspace_name: DURMUS"
            fi
        fi
    done
    
    if [[ $any_running -eq 0 ]]; then
        echo "  (hic calisan workspace yok)"
    fi
    
    echo ""
    echo "Son loglar:"
    tail -5 "$LOG_DIR/tetikleyici_$(date '+%Y%m%d').log" 2>/dev/null || echo "(log yok)"
}

# Dry-run modu
dry_run() {
    local py
    py="$(find_python)" || exit 1
    
    local workspaces_dir="$ROOT_DIR/agents/workspaces"
    
    echo "=== DRY-RUN: Workspace Analizi ==="
    echo ""
    
    for talimatlar in "$workspaces_dir"/*/TALIMATLAR.md; do
        if [[ ! -f "$talimatlar" ]]; then
            continue
        fi
        
        local workspace_name
        workspace_name="$(basename "$(dirname "$talimatlar")")"
        
        local unchecked_count
        unchecked_count=$(grep -c '^\s*-\s*\[\s\]' "$talimatlar" 2>/dev/null || echo "0")
        
        local artifacts
        artifacts="$(extract_artifacts "$talimatlar" "$py")"
        local artifact_count
        artifact_count=$(echo "$artifacts" | "$py" -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
        
        echo "[$workspace_name]"
        echo "  Unchecked: $unchecked_count"
        echo "  Artifacts: $artifact_count"
        echo "  Status: $([ "$unchecked_count" -gt 0 ] && echo 'HAZIR' || echo 'TAMAMLANDI')"
        echo ""
    done
}

# Komut parse
COMMAND="${1:-run}"

case "$COMMAND" in
    run)
        acquire_lock || exit 1
        run_tetikleyici
        ;;
    status)
        show_status
        ;;
    dry-run)
        dry_run
        ;;
    stop)
        info "Durduruluyor..."
        rm -rf "$PID_DIR"/*.pid "$PID_DIR"/main.lock 2>/dev/null || true
        info "Durduruldu"
        ;;
    *)
        echo "Kullanim: $0 {run|status|dry-run|stop}"
        echo ""
        echo "Komutlar:"
        echo "  run      - Tetikleyiciyi baslat (arka planda calisir)"
        echo "  status   - Calisan workspace'leri goster"
        echo "  dry-run  - Workspace'leri analiz et, calistirma"
        echo "  stop     - Tetikleyiciyi durdur"
        exit 1
        ;;
esac
