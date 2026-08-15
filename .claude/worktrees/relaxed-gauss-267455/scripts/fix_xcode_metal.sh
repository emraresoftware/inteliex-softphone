#!/bin/zsh
set -euo pipefail

echo "[1/6] Xcode developer path"
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

echo "[2/6] Xcode license"
sudo xcodebuild -license accept

echo "[3/6] First launch tasks"
sudo xcodebuild -runFirstLaunch

echo "[4/6] Download MetalToolchain component"
xcodebuild -downloadComponent MetalToolchain || true
xcodebuild -showComponent MetalToolchain -json || true

echo "[5/6] Re-check metal tools"
xcrun -f metal
xcrun -f metallib

echo "[6/6] If metallib still missing, reinstall CLT"
echo "Open: System Settings > General > Software Update"
echo "Then reinstall Command Line Tools manually if prompted."

echo "Final check"
xcrun -f metallib || true
