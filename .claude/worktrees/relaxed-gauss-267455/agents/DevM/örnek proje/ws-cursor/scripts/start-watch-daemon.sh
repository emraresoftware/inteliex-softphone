#!/usr/bin/env bash
# Start the watcher as a long-running Node process so launchd (or a manual run)
# manages the real PID. This script writes a PID file and then replaces the
# shell with the Node process (exec). No backgrounding with &.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="$ROOT_DIR/.watcher.pid"
LOGDIR="$ROOT_DIR/logs"
LOGFILE="$LOGDIR/watch.log"
WATCHER_JS="$ROOT_DIR/scripts/watch-talimatlar.js"

mkdir -p "$LOGDIR"

if [ -f "$PIDFILE" ]; then
  PID=$(cat "$PIDFILE" || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "Watcher zaten çalışıyor (PID $PID)"
    exit 0
  else
    echo "Eski PID bulundu ama süreç yok; temizliyorum."
    rm -f "$PIDFILE" || true
  fi
fi

if [ ! -f "$WATCHER_JS" ]; then
  echo "Hata: watcher scripti bulunamadı: $WATCHER_JS"
  exit 1
fi

# Redirect stdout/stderr to the log and write PID (the shell PID will remain the
# same after exec, so it's safe to write $$ before exec).
exec >> "$LOGFILE" 2>&1
echo "Watcher başlatılıyor: $(date -u +%FT%T%z)" 
echo "$$" > "$PIDFILE"

# Replace shell with node process so the PID is the Node PID and launchd can
# track it directly.
exec /usr/bin/env node "$WATCHER_JS"
