#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/agents"
if [[ -d "$ROOT_DIR/.agents" ]]; then
  AGENTS_DIR="$ROOT_DIR/.agents"
fi

WORKTREE_ROOT="$AGENTS_DIR/worktrees"
COPY_ROOT="$AGENTS_DIR/copies"
RUNTIME_FILE="$AGENTS_DIR/runtime.env"
BASE_BRANCH="${BASE_BRANCH:-main}"

if [[ -f "$RUNTIME_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_FILE"
else
  MODE="worktree"
fi

if [[ "$MODE" == "copy" ]]; then
  if [[ -z "${REPO_DIR:-}" ]]; then
    echo "[agents:sync] ERROR: REPO_DIR missing in runtime file" >&2
    exit 1
  fi
  if [[ ! -d "$COPY_ROOT" ]]; then
    echo "[agents:sync] copy root not found: $COPY_ROOT"
    exit 1
  fi
  for WS in "$COPY_ROOT"/*; do
    [[ -d "$WS" ]] || continue
    NAME="$(basename "$WS")"
    echo "[agents:sync] $NAME: syncing from canonical repo (safe copy)"
    rsync -a --delete --exclude '.git' --exclude 'vendor' --exclude 'node_modules' "$REPO_DIR/" "$WS/"
  done
else
  if [[ ! -d "$WORKTREE_ROOT" ]]; then
    echo "[agents:sync] worktree root not found: $WORKTREE_ROOT"
    exit 1
  fi
  for WT in "$WORKTREE_ROOT"/*; do
    [[ -d "$WT" ]] || continue
    NAME="$(basename "$WT")"
    echo "[agents:sync] $NAME: fetch + rebase origin/$BASE_BRANCH"
    git -C "$WT" fetch origin "$BASE_BRANCH"
    git -C "$WT" rebase "origin/$BASE_BRANCH" || {
      echo "[agents:sync] WARNING: rebase conflict in $NAME. resolve manually." >&2
    }
  done
fi

echo "[agents:sync] done"
