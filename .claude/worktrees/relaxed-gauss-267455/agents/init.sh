#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/agents"
if [[ -d "$ROOT_DIR/.agents" ]]; then
  AGENTS_DIR="$ROOT_DIR/.agents"
fi

REPO_DIR="${1:-$ROOT_DIR}"
WORKTREE_ROOT="$AGENTS_DIR/worktrees"
COPY_ROOT="$AGENTS_DIR/copies"
RUNTIME_FILE="$AGENTS_DIR/runtime.env"
BASE_BRANCH="${BASE_BRANCH:-main}"
AGENTS=(orchestrator core panel integration quality ops)

echo "[agents:init] repo=$REPO_DIR base=$BASE_BRANCH agents_dir=$AGENTS_DIR"
mkdir -p "$WORKTREE_ROOT"
mkdir -p "$COPY_ROOT"

if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[agents:init] ERROR: not a git repo: $REPO_DIR" >&2
  exit 1
fi

HAS_HEAD=0
if git -C "$REPO_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  HAS_HEAD=1
fi

if [[ "$HAS_HEAD" -eq 1 ]] && ! git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BASE_BRANCH"; then
  CURRENT_BRANCH="$(git -C "$REPO_DIR" branch --show-current || true)"
  if [[ -n "$CURRENT_BRANCH" ]]; then
    BASE_BRANCH="$CURRENT_BRANCH"
  else
    ORIGIN_HEAD="$(git -C "$REPO_DIR" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)"
    if [[ -n "$ORIGIN_HEAD" ]]; then
      BASE_BRANCH="$ORIGIN_HEAD"
    elif git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/master"; then
      BASE_BRANCH="master"
    else
      BASE_BRANCH="$(git -C "$REPO_DIR" for-each-ref --format='%(refname:short)' refs/heads | head -n1)"
    fi
  fi
fi

if [[ -z "$BASE_BRANCH" ]]; then
  echo "[agents:init] ERROR: could not determine base branch" >&2
  exit 1
fi

echo "[agents:init] resolved base branch: $BASE_BRANCH"

if [[ "$HAS_HEAD" -eq 1 ]]; then
  echo "MODE=worktree" > "$RUNTIME_FILE"
  echo "REPO_DIR=$REPO_DIR" >> "$RUNTIME_FILE"
  echo "BASE_BRANCH=$BASE_BRANCH" >> "$RUNTIME_FILE"
  for AGENT in "${AGENTS[@]}"; do
    BRANCH="agent/$AGENT"
    WT_PATH="$WORKTREE_ROOT/$AGENT"

    if [[ -d "$WT_PATH/.git" || -f "$WT_PATH/.git" ]]; then
      echo "[agents:init] exists: $AGENT -> $WT_PATH"
      continue
    fi

    if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git -C "$REPO_DIR" worktree add "$WT_PATH" "$BRANCH"
    else
      git -C "$REPO_DIR" worktree add -b "$BRANCH" "$WT_PATH" "$BASE_BRANCH"
    fi

    echo "[agents:init] ready: $AGENT branch=$BRANCH"
  done
else
  echo "[agents:init] no commit found. switching to copy mode"
  echo "MODE=copy" > "$RUNTIME_FILE"
  echo "REPO_DIR=$REPO_DIR" >> "$RUNTIME_FILE"
  for AGENT in "${AGENTS[@]}"; do
    WS_PATH="$COPY_ROOT/$AGENT"
    mkdir -p "$WS_PATH"
    rsync -a --delete --exclude '.git' --exclude 'vendor' --exclude 'node_modules' "$REPO_DIR/" "$WS_PATH/"
    echo "[agents:init] ready copy: $AGENT path=$WS_PATH"
  done
fi

echo "[agents:init] done"
