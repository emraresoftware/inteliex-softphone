#!/usr/bin/env bash
set -euo pipefail

CF_BASE="https://api.cloudflare.com/client/v4"

require_env() {
  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN gerekli}"
  : "${CLOUDFLARE_ZONE_ID:?CLOUDFLARE_ZONE_ID gerekli}"
}

headers() {
  echo "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
}

help_text() {
  cat <<'EOF'
Kullanim:
  bash 02_HIZLI_ISLEMLER.sh help
  bash 02_HIZLI_ISLEMLER.sh zones <domain>
  bash 02_HIZLI_ISLEMLER.sh list [name]
  bash 02_HIZLI_ISLEMLER.sh create <type> <name> <content> <proxied:true|false> [ttl]
  bash 02_HIZLI_ISLEMLER.sh update <record_id> <type> <name> <content> <proxied:true|false> [ttl]
  bash 02_HIZLI_ISLEMLER.sh delete <record_id>
  bash 02_HIZLI_ISLEMLER.sh ssl-get
  bash 02_HIZLI_ISLEMLER.sh ssl-set <off|flexible|full|strict>
  bash 02_HIZLI_ISLEMLER.sh purge-all
EOF
}

zones() {
  local domain="$1"
  curl -s -X GET "$CF_BASE/zones?name=$domain" \
    -H "$(headers)" -H "Content-Type: application/json"
  echo
}

list_records() {
  require_env
  local name_filter="${1:-}"
  local url="$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100"
  if [[ -n "$name_filter" ]]; then
    url+="&name=$name_filter"
  fi
  curl -s -X GET "$url" -H "$(headers)" -H "Content-Type: application/json"
  echo
}

create_record() {
  require_env
  local type="$1"
  local name="$2"
  local content="$3"
  local proxied="$4"
  local ttl="${5:-1}"

  curl -s -X POST "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
    -H "$(headers)" -H "Content-Type: application/json" \
    --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":$ttl,\"proxied\":$proxied}"
  echo
}

update_record() {
  require_env
  local record_id="$1"
  local type="$2"
  local name="$3"
  local content="$4"
  local proxied="$5"
  local ttl="${6:-1}"

  curl -s -X PUT "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
    -H "$(headers)" -H "Content-Type: application/json" \
    --data "{\"type\":\"$type\",\"name\":\"$name\",\"content\":\"$content\",\"ttl\":$ttl,\"proxied\":$proxied}"
  echo
}

delete_record() {
  require_env
  local record_id="$1"
  curl -s -X DELETE "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" \
    -H "$(headers)" -H "Content-Type: application/json"
  echo
}

ssl_get() {
  require_env
  curl -s -X GET "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/settings/ssl" \
    -H "$(headers)" -H "Content-Type: application/json"
  echo
}

ssl_set() {
  require_env
  local mode="$1"
  curl -s -X PATCH "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/settings/ssl" \
    -H "$(headers)" -H "Content-Type: application/json" \
    --data "{\"value\":\"$mode\"}"
  echo
}

purge_all() {
  require_env
  curl -s -X POST "$CF_BASE/zones/$CLOUDFLARE_ZONE_ID/purge_cache" \
    -H "$(headers)" -H "Content-Type: application/json" \
    --data '{"purge_everything": true}'
  echo
}

cmd="${1:-help}"
case "$cmd" in
  help)
    help_text
    ;;
  zones)
    zones "${2:-}"
    ;;
  list)
    list_records "${2:-}"
    ;;
  create)
    create_record "${2:?type}" "${3:?name}" "${4:?content}" "${5:?proxied}" "${6:-1}"
    ;;
  update)
    update_record "${2:?record_id}" "${3:?type}" "${4:?name}" "${5:?content}" "${6:?proxied}" "${7:-1}"
    ;;
  delete)
    delete_record "${2:?record_id}"
    ;;
  ssl-get)
    ssl_get
    ;;
  ssl-set)
    ssl_set "${2:?mode}"
    ;;
  purge-all)
    purge_all
    ;;
  *)
    help_text
    exit 1
    ;;
esac
