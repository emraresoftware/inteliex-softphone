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

if [[ -f "$RUNTIME_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$RUNTIME_FILE"
else
  MODE="worktree"
fi

if [[ "$MODE" == "copy" ]]; then
  if [[ ! -d "$COPY_ROOT" ]]; then
    echo "[agents:status] copy root not found: $COPY_ROOT"
    exit 0
  fi
  echo "[agents:status] mode=copy repo=${REPO_DIR:-unknown}"
  for WS in "$COPY_ROOT"/*; do
    [[ -d "$WS" ]] || continue
    NAME="$(basename "$WS")"
    FILES="$(find "$WS" -type f | wc -l | tr -d ' ')"
    echo "[$NAME] files=$FILES path=$WS"
  done
else
  if [[ ! -d "$WORKTREE_ROOT" ]]; then
    echo "[agents:status] worktree root not found: $WORKTREE_ROOT"
    exit 0
  fi
  echo "[agents:status] mode=worktree repo=${REPO_DIR:-unknown}"
  for WT in "$WORKTREE_ROOT"/*; do
    [[ -d "$WT" ]] || continue
    NAME="$(basename "$WT")"
    BRANCH="$(git -C "$WT" branch --show-current 2>/dev/null || echo unknown)"
    SHORT="$(git -C "$WT" status --short 2>/dev/null | wc -l | tr -d ' ')"
    echo "[$NAME] branch=$BRANCH changes=$SHORT path=$WT"
  done
fi
