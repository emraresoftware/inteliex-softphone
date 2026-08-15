#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Simple POSIX-compatible arg parsing
NO_DAEMON=0
CHECK_AGENT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-daemon) NO_DAEMON=1; shift;;
    --check-agent) CHECK_AGENT=1; shift;;
    --help) cat <<EOF
usage: setup.sh [--no-daemon] [--check-agent] [--help]

Options:
  --no-daemon    Do not start the watcher daemon after setup.
  --check-agent  Check for Cursor 'agent' CLI and print instructions if missing.
  --help         Show this help.

Typical quick run (default starts daemon):
  ./scripts/setup.sh

Install only (do not start daemon):
  ./scripts/setup.sh --no-daemon

Check for agent and install (no interactive install provided):
  ./scripts/setup.sh --check-agent
EOF
      exit 0;;
    *) echo "Bilinmeyen arg: $1"; exit 1;;
  esac
done

echo "Başlatılıyor: kurulum betiği (no-daemon=$NO_DAEMON, check-agent=$CHECK_AGENT)"

if [ "$(id -u)" -eq 0 ]; then
  echo "UYARI: Betik root olarak çalıştırılıyor. Genelde root ile npm paketleri kurmaktan kaçının."
fi

echo "1/5: Node.js sürümünü kontrol ediliyor..."
if ! command -v node >/dev/null 2>&1; then
  echo "Hata: Node.js bulunamadı. Lütfen Node.js kurun: https://nodejs.org/"
  exit 1
fi

echo "2/5: npm bağımlılıkları yükleniyor (npm install)..."
npm install --no-audit --no-fund

echo "3/5: scriptlere çalıştırma izni veriliyor..."
chmod +x scripts/*.sh || true

if [ "$CHECK_AGENT" -eq 1 ]; then
  echo "4/5: agent (Cursor CLI) kontrol ediliyor..."
  if command -v agent >/dev/null 2>&1; then
    echo "agent bulundu. Eğer kullanmak isterseniz 'agent login' yapın."
  else
    cat <<MSG
agent bulunamadı. Cursor CLI gerekli ise: https://cursor.com/install
(Bu betik agent kurmaz; manuel kurulum gereklidir.)
MSG
  fi
fi

if [ "$NO_DAEMON" -eq 0 ]; then
  echo "5/5: watcher arka planda başlatılıyor (talimatlar-watch-daemon)..."
  npm run talimatlar-watch-daemon
  echo "Kurulum tamamlandı. Durum kontrolü için: npm run talimatlar-watch-status"
else
  echo "5/5: daemon başlatılmadı (--no-daemon). Kurulum tamamlandı."
fi
