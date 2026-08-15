#!/bin/zsh
set -euo pipefail

WORKDIR="/Users/emre/Dergah"
PYTHON_BIN="$WORKDIR/.venv/bin/python"

ROLE="${1:-orchestrator}"
MODE="${2:-panel}"

resolve_env_file() {
  local role_name="$1"
  local local_file="$WORKDIR/.env.${role_name}.local"
  local example_file

  case "$role_name" in
    orchestrator)
      example_file="$WORKDIR/.env.m5-orchestrator.example"
      ;;
    worker1|worker2)
      example_file="$WORKDIR/.env.${role_name}.example"
      ;;
    *)
      return 1
      ;;
  esac

  if [[ -f "$local_file" ]]; then
    echo "$local_file"
    return 0
  fi

  if [[ -f "$example_file" ]]; then
    echo "$example_file"
    return 0
  fi

  return 1
}

case "$ROLE" in
  orchestrator)
    ENV_FILE="$(resolve_env_file orchestrator)"
    ;;
  worker1)
    ENV_FILE="$(resolve_env_file worker1)"
    ;;
  worker2)
    ENV_FILE="$(resolve_env_file worker2)"
    ;;
  *)
    echo "Bilinmeyen rol: $ROLE"
    echo "Kullanim: scripts/start_node.sh [orchestrator|worker1|worker2] [panel|core|operator|openclaw|relay-listen|status]"
    exit 1
    ;;
esac

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env dosyasi bulunamadi: $ENV_FILE"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

cd "$WORKDIR"

start_panel() {
  pkill -f "scripts/dervis_panel.py" >/dev/null 2>&1 || true
  sleep 0.3
  nohup "$PYTHON_BIN" "$WORKDIR/scripts/dervis_panel.py" >/tmp/dervis_panel.log 2>&1 &
  disown
  echo "Panel baslatildi: /tmp/dervis_panel.log"
}

start_core() {
  pkill -f "scripts/dervis_core.py" >/dev/null 2>&1 || true
  sleep 0.3
  nohup "$PYTHON_BIN" "$WORKDIR/scripts/dervis_core.py" >/tmp/dervis_core.log 2>&1 &
  disown
  echo "Core baslatildi: /tmp/dervis_core.log"
}

start_operator() {
  pkill -f "scripts/dervis_operator.py" >/dev/null 2>&1 || true
  sleep 0.3
  nohup "$PYTHON_BIN" "$WORKDIR/scripts/dervis_operator.py" >/tmp/dervis_operator.log 2>&1 &
  disown
  echo "Operator baslatildi: /tmp/dervis_operator.log"
}

start_openclaw() {
  if [[ -n "${OPENCLAW_BIN:-}" && -x "${OPENCLAW_BIN}" ]]; then
    nohup "${OPENCLAW_BIN}" >/tmp/openclaw.log 2>&1 &
    disown
    echo "OPENCLAW_BIN ile openclaw baslatildi: /tmp/openclaw.log"
    return
  fi

  if command -v openclaw >/dev/null 2>&1; then
    nohup openclaw >/tmp/openclaw.log 2>&1 &
    disown
    echo "openclaw baslatildi: /tmp/openclaw.log"
    return
  fi

  if "$PYTHON_BIN" -m openclaw --help >/dev/null 2>&1; then
    nohup "$PYTHON_BIN" -m openclaw >/tmp/openclaw.log 2>&1 &
    disown
    echo "python -m openclaw baslatildi: /tmp/openclaw.log"
    return
  fi

  echo "openclaw komutu bulunamadi."
  echo "Not: pip ile kurulu openclaw paketi bu ortamda CLI/entrypoint saglamiyor."
  echo "Cozum: resmi kurulum scriptiyle CLI kur veya OPENCLAW_BIN degiskenini tanimla."
  echo "Ornek: export OPENCLAW_BIN=\"/usr/local/bin/openclaw\""
  exit 1
}

start_relay_listen() {
  nohup "$PYTHON_BIN" "$WORKDIR/scripts/dervis_haberlesme_github.py" listen --poll-seconds 8 >/tmp/dervis_relay.log 2>&1 &
  disown
  echo "GitHub relay listener baslatildi: /tmp/dervis_relay.log"
}

print_status() {
  echo "ENV_FILE=$ENV_FILE"
  echo "NODE=${DERGAH_NODE_NAME:-unknown}"
  echo "ROLE=${DERGAH_NODE_ROLE:-unknown}"
  echo "PROVIDER=${DERGAH_LLM_PROVIDER:-unset}"
  echo "MODEL=${DERGAH_MODEL_NAME:-unset}"
  echo "OPENAI_API_BASE=${DERGAH_OPENAI_API_BASE:-unset}"
  echo "GITHUB_RELAY=$([[ -n "${DERGAH_GITHUB_OWNER:-}" && -n "${DERGAH_GITHUB_REPO:-}" && -n "${DERGAH_GITHUB_CHANNEL_ISSUE:-}" ]] && echo configured || echo missing)"
}

case "$MODE" in
  panel)
    start_panel
    ;;
  core)
    start_core
    ;;
  operator)
    start_operator
    ;;
  openclaw)
    start_openclaw
    ;;
  relay-listen)
    start_relay_listen
    ;;
  status)
    print_status
    ;;
  *)
    echo "Bilinmeyen mod: $MODE"
    echo "Kullanim: scripts/start_node.sh [orchestrator|worker1|worker2] [panel|core|operator|openclaw|relay-listen|status]"
    exit 1
    ;;
esac

echo "ROL=$ROLE MODE=$MODE NODE=${DERGAH_NODE_NAME:-unknown} PROVIDER=${DERGAH_LLM_PROVIDER:-unset} MODEL=${DERGAH_MODEL_NAME:-unset}"
