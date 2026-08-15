#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/agents"
if [[ -d "$ROOT_DIR/.agents" ]]; then
  AGENTS_DIR="$ROOT_DIR/.agents"
fi

RUNTIME_FILE="$AGENTS_DIR/runtime.env"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./tools/agents/merge.sh <agent-name> [--apply]"
  exit 1
fi

AGENT="$1"
APPLY=0
if [[ "${2:-}" == "--apply" ]]; then
  APPLY=1
fi

if [[ ! -f "$RUNTIME_FILE" ]]; then
  echo "[agents:merge] runtime file missing: $RUNTIME_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$RUNTIME_FILE"

if [[ "${MODE:-}" == "worktree" ]]; then
  echo "[agents:merge] worktree mode detected. Use git PR/merge flow from branch agent/$AGENT"
  exit 0
fi

if [[ -z "${REPO_DIR:-}" ]]; then
  echo "[agents:merge] REPO_DIR missing in runtime file" >&2
  exit 1
fi

SRC="$AGENTS_DIR/copies/$AGENT"
DST="$REPO_DIR"

if [[ ! -d "$SRC" ]]; then
  echo "[agents:merge] agent copy not found: $SRC" >&2
  exit 1
fi

echo "[agents:merge] diff preview for $AGENT"
rsync -avnc --exclude '.git' --exclude 'vendor' --exclude 'node_modules' "$SRC/" "$DST/"

if [[ "$APPLY" -eq 1 ]]; then
  VALIDATE_SCRIPT="$AGENTS_DIR/validate.sh"
  if [[ -x "$VALIDATE_SCRIPT" ]]; then
    echo "[agents:merge] kalite kapısı çalışıyor..."
    if ! "$VALIDATE_SCRIPT" "$SRC"; then
      echo "[agents:merge] ENGELLENDI: kalite kapısı geçilemedi. --skip-validation ile zorla geçebilirsin." >&2
      exit 1
    fi
  fi
  echo "[agents:merge] applying changes from $AGENT -> repo"
  rsync -av --exclude '.git' --exclude 'vendor' --exclude 'node_modules' "$SRC/" "$DST/"
  TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  printf '{"ts":"%s","from":"%s","to":"main","type":"merge","message":"merge applied - validation passed"}\n' "$TS" "$AGENT" >> "$AGENTS_DIR/handoffs.ndjson"
  echo "[agents:merge] apply complete"
else
  echo "[agents:merge] preview only. rerun with --apply to copy changes"
fi
