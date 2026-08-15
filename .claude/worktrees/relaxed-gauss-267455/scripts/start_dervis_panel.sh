#!/bin/zsh
set -u

WORKDIR="/Users/emre/Dergah"
PYTHON_BIN="/Users/emre/Dergah/.venv/bin/python3.14"
SCRIPT_PATH="$WORKDIR/scripts/dervis_panel.py"
MODEL_NAME="qwen2.5-coder:14b"
VISION_MODEL_NAME="llama3.2-vision:latest"
OLLAMA_BIN="/opt/homebrew/bin/ollama"
OLLAMA_HOST_VALUE="[::]:11434"
LLM_PROVIDER="${DERGAH_LLM_PROVIDER:-ollama}"
DERGAH_MODEL_NAME="${DERGAH_MODEL_NAME:-$MODEL_NAME}"
DERGAH_VISION_MODEL_NAME="${DERGAH_VISION_MODEL_NAME:-$VISION_MODEL_NAME}"

cd "$WORKDIR" || exit 1

if [[ "$LLM_PROVIDER" == "ollama" ]]; then
  if [[ ! -x "$OLLAMA_BIN" ]]; then
    exit 1
  fi

  if ! pgrep -x ollama >/dev/null 2>&1; then
    OLLAMA_HOST="$OLLAMA_HOST_VALUE" nohup "$OLLAMA_BIN" serve >/tmp/dergah_ollama.log 2>&1 &
    sleep 2
  fi

  if ! "$OLLAMA_BIN" list | grep -q "$DERGAH_MODEL_NAME"; then
    "$OLLAMA_BIN" pull "$DERGAH_MODEL_NAME"
  fi
fi

# Eski instance varsa kapat
pkill -f "scripts/dervis_panel.py" 2>/dev/null || true
sleep 0.5

nohup env DERGAH_MODEL_NAME="$DERGAH_MODEL_NAME" DERGAH_VISION_MODEL_NAME="$DERGAH_VISION_MODEL_NAME" DERGAH_LLM_PROVIDER="$LLM_PROVIDER" "$PYTHON_BIN" "$SCRIPT_PATH" >/tmp/dervis_panel.log 2>&1 &
disown
exit 0
