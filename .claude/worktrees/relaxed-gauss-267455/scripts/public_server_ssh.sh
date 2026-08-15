#!/bin/zsh
set -euo pipefail

HOST="${SSH_HOST:-185.189.54.107}"
USER_NAME="root"
KEY_FILE="${SSH_KEY_FILE:-$HOME/.ssh/id_ed25519}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "SSH anahtari bulunamadi: $KEY_FILE"
  exit 1
fi

if [[ "${1:-}" == "--host" && -n "${2:-}" ]]; then
  HOST="$2"
  shift 2
fi

if [[ "${1:-}" == "--user" && -n "${2:-}" ]]; then
  USER_NAME="$2"
  shift 2
fi

if [[ $# -eq 0 ]]; then
  exec ssh -i "$KEY_FILE" "$USER_NAME@$HOST"
else
  exec ssh -i "$KEY_FILE" "$USER_NAME@$HOST" "$@"
fi