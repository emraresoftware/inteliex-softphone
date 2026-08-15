#!/usr/bin/env bash
# Basit, güvenli teşhis scripti — hiçbir talimatı otomatik uygulamaz.
# Kullanım: ./scripts/diagnose.sh [--install] [--output file]

OUT_FILE=""
DO_INSTALL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) DO_INSTALL=1; shift ;;
    --output) OUT_FILE="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--install] [--output file]"; exit 0 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

run() {
  if [[ -n "$OUT_FILE" ]]; then
    echo "$@" | tee -a "$OUT_FILE"
  else
    echo "$@"
  fi
}

sep() { run "-----------------------------"; }

TIMESTAMP="$(date --iso-8601=seconds 2>/dev/null || date)"
run "Diagnose run: $TIMESTAMP"
sep
run "PWD: $(pwd)"
run "User: $(id -un) (uid=$(id -u))"
run "Shell: $SHELL"
sep
run "System info:"; uname -a
sep
run "Node / npm:";
if command -v node >/dev/null 2>&1; then
  run "node: "$(node -v)
else
  run "node: NOT FOUND"
fi
if command -v npm >/dev/null 2>&1; then
  run "npm: "$(npm -v)
else
  run "npm: NOT FOUND"
fi
sep
run "agent (Cursor) presence:";
if command -v agent >/dev/null 2>&1; then
  run "agent: present"
else
  run "agent: NOT FOUND"
fi
sep
run "package.json scripts (if any):"
if [[ -f package.json ]]; then
  node -e "try{console.log(Object.keys(require('./package.json').scripts||{}).join(', ')||'<none>')}catch(e){console.error('err',e);}" 2>/dev/null || cat package.json | sed -n '1,120p'
else
  run "package.json: NOT FOUND"
fi
sep
run "scripts/ folder listing:"; ls -la scripts || true
sep
run "node_modules present?"; if [[ -d node_modules ]]; then run "node_modules exists"; else run "node_modules missing"; fi
if [[ $DO_INSTALL -eq 1 ]]; then
  sep
  run "Running npm install (this may take a while)..."
  npm install --no-audit --no-fund 2>&1 | sed -n '1,200p'
fi
sep
run "Dry-run (node scripts/run-talimatlar-ai.js) output:";
if [[ -f scripts/run-talimatlar-ai.js ]]; then
  node scripts/run-talimatlar-ai.js 2>&1 | sed -n '1,200p'
else
  run "scripts/run-talimatlar-ai.js not found"
fi
sep
run "Watcher pid file and status:";
if [[ -f .watcher.pid ]]; then
  PID=$(cat .watcher.pid 2>/dev/null || echo "")
  run ".watcher.pid: $PID"
  if [[ -n "$PID" && -d /proc/$PID ]]; then
    run "Process $PID seems running"
  else
    run "Process $PID not present"
  fi
else
  run ".watcher.pid not found"
fi
sep
run "Recent watcher log (if exists):"
if [[ -f logs/watch.log ]]; then
  tail -n 200 logs/watch.log | sed -n '1,200p'
else
  run "logs/watch.log not found"
fi
sep
run "TALIMATLAR.md preview (first 120 lines):"
if [[ -f TALIMATLAR.md ]]; then
  sed -n '1,120p' TALIMATLAR.md
else
  run "TALIMATLAR.md not found"
fi
sep
run "End of diagnose. If you send the whole output file to me I can help debug further."

if [[ -n "$OUT_FILE" ]]; then
  run "Wrote output to $OUT_FILE"
fi
