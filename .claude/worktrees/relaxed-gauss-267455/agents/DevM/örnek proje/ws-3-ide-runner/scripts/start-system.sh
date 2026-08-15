#!/usr/bin/env bash
# Tek komutla sistemi ayağa kaldırmak için yardımcı script
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

echo "1/4: Bağımlılıklar ve kurulum (setup.sh)"
# --no-daemon: setup.sh daemon'u başlatmasın, biz launchd ile yöneteceğiz
./scripts/setup.sh --no-daemon

echo "2/4: LaunchAgent plist kopyalanıyor ve yüklenecek"
LAUNCH_SRC="$ROOT_DIR/launch_agents/com.emre.talimatlar.watch.plist"
LAUNCH_DST="$HOME/Library/LaunchAgents/com.emre.talimatlar.watch.plist"
mkdir -p "$(dirname "$LAUNCH_DST")"
cp -f "$LAUNCH_SRC" "$LAUNCH_DST"

echo "3/4: LaunchAgent (reload)"
# unload may fail if not loaded; ignore errors
launchctl unload "$LAUNCH_DST" 2>/dev/null || true
launchctl load "$LAUNCH_DST"

echo "4/4: Durum"
launchctl list | grep com.emre.talimatlar.watch || true

echo "Sistem başlatıldı. Log: $ROOT_DIR/logs/watch-launchd.out.log ve err.log"
