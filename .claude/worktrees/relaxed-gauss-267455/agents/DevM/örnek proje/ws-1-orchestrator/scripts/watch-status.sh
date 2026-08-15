#!/usr/bin/env bash
# Status: PID dosyasına bakar ve süreç durumunu gösterir.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="$ROOT_DIR/.watcher.pid"
LOGFILE="$ROOT_DIR/logs/watch.log"

if [ ! -f "$PIDFILE" ]; then
  echo "Watcher PID dosyası yok; çalışmıyor olabilir."
  exit 1
fi
PID=$(cat "$PIDFILE")
if kill -0 "$PID" 2>/dev/null; then
  echo "Watcher çalışıyor (PID $PID). Log: $LOGFILE"
  tail -n 200 "$LOGFILE" || true
else
  echo "PID bulundu ama süreç aktif değil."
  exit 1
fi
