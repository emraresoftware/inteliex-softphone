#!/usr/bin/env bash
# Dergah multi-agent pre-merge validator (Python-first)
# Usage:
#   agents/validate.sh [target-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-$ROOT_DIR}"

PASS=0
FAIL=0
WARN=0
ERRORS=()

ok()   { PASS=$((PASS+1)); echo "  [OK] $*"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("$*"); echo "  [FAIL] $*"; }
warn() { WARN=$((WARN+1)); echo "  [WARN] $*"; }
info() { echo ""; echo "== $* =="; }

PY_BIN=""
if [[ -x "$ROOT_DIR/.venv/bin/python3.14" ]]; then
  PY_BIN="$ROOT_DIR/.venv/bin/python3.14"
elif [[ -x "$ROOT_DIR/.venv/bin/python3" ]]; then
  PY_BIN="$ROOT_DIR/.venv/bin/python3"
elif command -v python3 >/dev/null 2>&1; then
  PY_BIN="$(command -v python3)"
else
  fail "Python bulunamadi"
fi

info "Python ortam"
if [[ -n "$PY_BIN" ]]; then
  "$PY_BIN" --version >/dev/null 2>&1 && ok "Python hazir: $PY_BIN" || fail "Python calismiyor: $PY_BIN"
fi

info "Python syntax taramasi"
PY_TMP="$(mktemp)"
{
  find "$TARGET" -maxdepth 1 -type f -name "*.py" 2>/dev/null
  find "$TARGET/scripts" -type f -name "*.py" 2>/dev/null
} | sort -u > "$PY_TMP"

SYNTAX_ERRORS=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if ! "$PY_BIN" -m py_compile "$f" >/dev/null 2>&1; then
    fail "Syntax: $f"
    SYNTAX_ERRORS=$((SYNTAX_ERRORS+1))
  fi
done < "$PY_TMP"
rm -f "$PY_TMP"
[[ $SYNTAX_ERRORS -eq 0 ]] && ok "Python syntax temiz"

info "Shell script syntax"
SH_TMP="$(mktemp)"
{
  find "$TARGET/agents" -maxdepth 1 -type f -name "*.sh" 2>/dev/null
  find "$TARGET/scripts" -maxdepth 1 -type f -name "*.sh" 2>/dev/null
} | sort -u > "$SH_TMP"

SH_ERRORS=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  if ! bash -n "$f" >/dev/null 2>&1; then
    fail "Shell syntax: $f"
    SH_ERRORS=$((SH_ERRORS+1))
  fi
done < "$SH_TMP"
rm -f "$SH_TMP"
[[ $SH_ERRORS -eq 0 ]] && ok "Shell syntax temiz"

info "JSON dosya dogrulamasi"
JSON_ERRORS=0
for jf in \
  "$TARGET/agents/agents.json" \
  "$TARGET/agents/backlog.json" \
  "$TARGET/data/dergah_defteri.json" \
  "$TARGET/data/learning_profile.json"; do
  if [[ -f "$jf" ]]; then
    if ! "$PY_BIN" -  <<'PY' "$jf"
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    json.load(f)
PY
    then
      fail "JSON gecersiz: $jf"
      JSON_ERRORS=$((JSON_ERRORS+1))
    fi
  else
    warn "JSON dosyasi yok: $jf"
  fi
done
[[ $JSON_ERRORS -eq 0 ]] && ok "JSON dosyalari dogrulandi"

info "SQLite mesajlaşma veritabani"
if [[ -f "$TARGET/agents/messages.db" ]]; then
  # SQLite veritabani kontrolu
  DB_OK=$("$PY_BIN" -  <<'PY' "$TARGET/agents/messages.db"
import sqlite3, sys
try:
    conn = sqlite3.connect(sys.argv[1])
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM messages")
    cur.execute("SELECT COUNT(*) FROM agent_status")
    conn.close()
    print("ok")
except Exception as e:
    print(f"error: {e}")
    sys.exit(1)
PY
)
  if [[ "$DB_OK" == "ok" ]]; then
    ok "SQLite veritabani temiz"
  else
    fail "SQLite veritabani hatasi: $DB_OK"
  fi
else
  info "SQLite veritabani yok (mesajlasma sistemi henuz kullanilmamis)"
fi

info "Kritik dosya varlik kontrolu"
for req in \
  "$TARGET/scripts/start_node.sh" \
  "$TARGET/scripts/dervis_core.py" \
  "$TARGET/scripts/dervis_panel.py" \
  "$TARGET/scripts/llm_bridge.py"; do
  if [[ -f "$req" ]]; then
    ok "Mevcut: $req"
  else
    fail "Eksik: $req"
  fi
done

info "Start script smoke"
if [[ -x "$TARGET/scripts/start_node.sh" ]]; then
  if "$TARGET/scripts/start_node.sh" orchestrator status >/dev/null 2>&1; then
    ok "start_node status calisiyor"
  else
    warn "start_node status hata verdi (env eksik olabilir)"
  fi
else
  warn "start_node.sh executable degil"
fi

info "Git durumu"
if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CHANGES="$(git -C "$TARGET" status --short | wc -l | tr -d ' ')"
  if [[ "$CHANGES" == "0" ]]; then
    ok "Git temiz"
  else
    warn "Git degisiklik var: $CHANGES satir"
  fi
else
  warn "Git repo tespit edilemedi"
fi

echo ""
echo "----------------------------------------"
echo "PASS: $PASS  FAIL: $FAIL  WARN: $WARN"
echo "----------------------------------------"

if [[ $FAIL -gt 0 ]]; then
  echo "Hatalar:"
  if [[ ${#ERRORS[@]} -gt 0 ]]; then
    for e in "${ERRORS[@]}"; do
      echo "- $e"
    done
  else
    echo "- (detay yok, stderr kontrol et)"
  fi
  exit 1
fi

echo "Kalite kapisi gecti."
exit 0
