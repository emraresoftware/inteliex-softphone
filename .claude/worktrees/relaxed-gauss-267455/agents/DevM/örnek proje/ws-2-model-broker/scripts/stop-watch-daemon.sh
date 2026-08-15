#!/usr/bin/env bash
# Durdur: PID dosyasına bakar ve süreci öldürür.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="$ROOT_DIR/.watcher.pid"

if [ ! -f "$PIDFILE" ]; then
  echo "PID dosyası bulunamadı; watcher çalışmıyor olabilir."
  exit 1
fi
PID=$(cat "$PIDFILE")
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  rm -f "$PIDFILE"
  echo "Watcher (PID $PID) durduruldu."
else
  echo "PID bulundu ama süreç yok; PID dosyası siliniyor."
  rm -f "$PIDFILE"
fi
