#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$ROOT_DIR/agents"
if [[ -d "$ROOT_DIR/.agents" ]]; then
  AGENTS_DIR="$ROOT_DIR/.agents"
fi

RUNTIME_FILE="$AGENTS_DIR/runtime.env"
HANDOFF_FILE="$AGENTS_DIR/handoffs.ndjson"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./tools/agents/intake.sh <agent-name> [since-minutes]"
  exit 1
fi

AGENT="$1"
SINCE_MINUTES="${2:-180}"

if [[ ! -f "$RUNTIME_FILE" ]]; then
  echo "[agents:intake] runtime file missing: $RUNTIME_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$RUNTIME_FILE"

if [[ "${MODE:-}" != "copy" ]]; then
  echo "[agents:intake] intake is only needed in copy mode"
  exit 0
fi

if [[ -z "${REPO_DIR:-}" ]]; then
  echo "[agents:intake] REPO_DIR missing in runtime file" >&2
  exit 1
fi

SRC="$REPO_DIR"
DST="$AGENTS_DIR/copies/$AGENT"

if [[ ! -d "$DST" ]]; then
  echo "[agents:intake] agent copy not found: $DST" >&2
  exit 1
fi

TMP_LIST="$(mktemp)"
find "$SRC" -type f -mmin "-$SINCE_MINUTES" \
  ! -path '*/.git/*' \
  ! -path '*/vendor/*' \
  ! -path '*/node_modules/*' \
  -print > "$TMP_LIST"

COUNT="$(wc -l < "$TMP_LIST" | tr -d ' ')"
if [[ "$COUNT" -eq 0 ]]; then
  echo "[agents:intake] no recent files found in last $SINCE_MINUTES minutes"
  rm -f "$TMP_LIST"
  exit 0
fi

while IFS= read -r FILE; do
  REL="${FILE#$SRC/}"
  mkdir -p "$DST/$(dirname "$REL")"
  cp "$FILE" "$DST/$REL"
done < "$TMP_LIST"

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
printf '{"ts":"%s","from":"direct-repo","to":"%s","type":"intake","message":"%s recent file synced from canonical repo"}\n' "$TS" "$AGENT" "$COUNT" >> "$HANDOFF_FILE"

echo "[agents:intake] synced $COUNT recent files to $AGENT"
rm -f "$TMP_LIST"
