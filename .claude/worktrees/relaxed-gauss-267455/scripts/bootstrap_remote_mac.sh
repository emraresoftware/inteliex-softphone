#!/bin/zsh
set -euo pipefail

WORKDIR="/Users/emre/Dergah"

usage() {
  echo "Kullanim: scripts/bootstrap_remote_mac.sh --host HOST --user USER --role worker1|worker2 --m5-host HOST --github-owner OWNER --github-repo REPO --github-issue ISSUE [secenekler]"
  echo "Secenekler:"
  echo "  --remote-dir DIR"
  echo "  --password PASSWORD"
  echo "  --github-token TOKEN"
  echo "  --node-name NAME"
  echo "  --model MODEL"
  echo "  --provider openai_compat|ollama"
  echo "  --coordinator-url URL"
  echo "  --start-relay"
  echo "  --start-openclaw"
  exit 1
}

HOST=""
USER_NAME=""
ROLE=""
REMOTE_DIR="/Users/emre/Dergah"
M5_HOST=""
REMOTE_PASSWORD="${DERGAH_REMOTE_PASSWORD:-}"
GITHUB_OWNER=""
GITHUB_REPO=""
GITHUB_ISSUE=""
GITHUB_TOKEN="${DERGAH_GITHUB_TOKEN:-}"
NODE_NAME=""
MODEL_NAME="qwen2.5:32b"
PROVIDER="openai_compat"
COORDINATOR_URL=""
START_RELAY="0"
START_OPENCLAW="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:-}"
      shift 2
      ;;
    --password)
      REMOTE_PASSWORD="${2:-}"
      shift 2
      ;;
    --m5-host)
      M5_HOST="${2:-}"
      shift 2
      ;;
    --github-owner)
      GITHUB_OWNER="${2:-}"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="${2:-}"
      shift 2
      ;;
    --github-issue)
      GITHUB_ISSUE="${2:-}"
      shift 2
      ;;
    --github-token)
      GITHUB_TOKEN="${2:-}"
      shift 2
      ;;
    --node-name)
      NODE_NAME="${2:-}"
      shift 2
      ;;
    --model)
      MODEL_NAME="${2:-}"
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --coordinator-url)
      COORDINATOR_URL="${2:-}"
      shift 2
      ;;
    --start-relay)
      START_RELAY="1"
      shift
      ;;
    --start-openclaw)
      START_OPENCLAW="1"
      shift
      ;;
    *)
      echo "Bilinmeyen arguman: $1"
      usage
      ;;
  esac
done

[[ -n "$HOST" && -n "$USER_NAME" && -n "$ROLE" && -n "$M5_HOST" && -n "$GITHUB_OWNER" && -n "$GITHUB_REPO" && -n "$GITHUB_ISSUE" ]] || usage

SSH_TARGET="${USER_NAME}@${HOST}"

echo "SSH erisimi test ediliyor: ${SSH_TARGET}"
if [[ -n "$REMOTE_PASSWORD" ]]; then
  /Users/emre/Dergah/.venv/bin/python "$WORKDIR/scripts/bootstrap_remote_mac_paramiko.py" \
    --host "$HOST" \
    --user "$USER_NAME" \
    --password "$REMOTE_PASSWORD" \
    --command "echo ok" >/dev/null
else
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_TARGET" "echo ok" >/dev/null
fi

REMOTE_CMD="cd ${REMOTE_DIR} && chmod +x scripts/join_mac_node.sh scripts/start_node.sh && scripts/join_mac_node.sh --role ${ROLE} --m5-host ${M5_HOST} --github-owner ${GITHUB_OWNER} --github-repo ${GITHUB_REPO} --github-issue ${GITHUB_ISSUE}"

if [[ -n "$GITHUB_TOKEN" ]]; then
  REMOTE_CMD+=" --github-token '${GITHUB_TOKEN}'"
fi
if [[ -n "$NODE_NAME" ]]; then
  REMOTE_CMD+=" --node-name ${NODE_NAME}"
fi
if [[ -n "$MODEL_NAME" ]]; then
  REMOTE_CMD+=" --model ${MODEL_NAME}"
fi
if [[ -n "$PROVIDER" ]]; then
  REMOTE_CMD+=" --provider ${PROVIDER}"
fi
if [[ -n "$COORDINATOR_URL" ]]; then
  REMOTE_CMD+=" --coordinator-url ${COORDINATOR_URL}"
fi
REMOTE_CMD+=" --start-status"

if [[ "$START_RELAY" == "1" ]]; then
  REMOTE_CMD+=" --start-relay"
fi
if [[ "$START_OPENCLAW" == "1" ]]; then
  REMOTE_CMD+=" --start-openclaw"
fi

if [[ -n "$REMOTE_PASSWORD" ]]; then
  /Users/emre/Dergah/.venv/bin/python "$WORKDIR/scripts/bootstrap_remote_mac_paramiko.py" \
    --host "$HOST" \
    --user "$USER_NAME" \
    --password "$REMOTE_PASSWORD" \
    --command "$REMOTE_CMD"
else
  ssh "$SSH_TARGET" "$REMOTE_CMD"
fi

echo "Remote bootstrap tamamlandi: ${SSH_TARGET}"
