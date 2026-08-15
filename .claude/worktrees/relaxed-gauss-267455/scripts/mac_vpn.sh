#!/bin/zsh
set -euo pipefail

WORKDIR="/Users/emre/Dergah"
CONFIG_FILE="${DERGAH_VPN_CONFIG:-$WORKDIR/data/config/vpn.local.json}"
ACTION="${1:-status}"
CHECK_INTERVAL="${CHECK_INTERVAL:-8}"
MAX_CONNECT_RETRIES="${MAX_CONNECT_RETRIES:-3}"
CONNECT_TIMEOUT_SEC="${CONNECT_TIMEOUT_SEC:-45}"
PROBE_GRACE_SEC="${PROBE_GRACE_SEC:-8}"

json_get() {
  local key_path="$1"
  python3 - "$CONFIG_FILE" "$key_path" <<'PY'
import json
import sys

config_path = sys.argv[1]
key_path = sys.argv[2].split('.')

with open(config_path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)

value = data
for part in key_path:
    value = value.get(part)
    if value is None:
        break

if value is None:
    sys.exit(1)

print(value)
PY
}

SERVICE_NAME="$(json_get service_name)"
VPN_TYPE="$(json_get type || true)"
SELECTED_PROTOCOL="$(json_get selected_protocol || true)"
PROBE_HOST="$(json_get preferred_hosts.probe_host || true)"

if [[ -z "$SELECTED_PROTOCOL" ]]; then
  SELECTED_PROTOCOL="$VPN_TYPE"
fi

if [[ "$SELECTED_PROTOCOL" != "l2tp_ipsec" ]]; then
  echo "Desteklenmeyen VPN protokolu secildi: $SELECTED_PROTOCOL"
  echo "Bu script sadece l2tp_ipsec icin standartlastirildi."
  exit 1
fi

if [[ -n "$VPN_TYPE" && "$VPN_TYPE" != "l2tp_ipsec" ]]; then
  echo "Config uyumsuz: type=$VPN_TYPE, selected_protocol=$SELECTED_PROTOCOL"
  echo "Lutfen data/config/vpn.local.json dosyasinda type degerini l2tp_ipsec yap."
  exit 1
fi

status_text() {
  scutil --nc status "$SERVICE_NAME" 2>&1 || true
}

status_line() {
  status_text | sed -n '1p'
}

last_cause() {
  status_text | awk -F': ' '/LastCause/{print $2}' | tail -n 1
}

device_last_cause() {
  status_text | awk -F': ' '/DeviceLastCause/{print $2}' | tail -n 1
}

ppp_has_shared_secret_error() {
  tail -n 80 /var/log/ppp.log 2>/dev/null | grep -qi 'incorrect user shared secret found'
}

is_connected() {
  status_text | head -n 1 | grep -qi '^Connected$'
}

probe_host() {
  if [[ -z "$PROBE_HOST" ]]; then
    return 0
  fi
  ping -c 1 -W 1000 "$PROBE_HOST" >/dev/null 2>&1
}

connect_vpn() {
  local attempt
  for attempt in $(seq 1 "$MAX_CONNECT_RETRIES"); do
    echo "VPN baglanma denemesi ${attempt}/${MAX_CONNECT_RETRIES}: $SERVICE_NAME"
    scutil --nc start "$SERVICE_NAME" || true

    local waited=0
    while [[ "$waited" -lt "$CONNECT_TIMEOUT_SEC" ]]; do
      if is_connected; then
        if probe_host; then
          echo "VPN baglandi ve probe basarili."
          status_text
          return 0
        else
          # Yeni baglantida route tablosu gec gelebilir; hemen dusurme.
          sleep "$PROBE_GRACE_SEC"
          if probe_host; then
            echo "VPN baglandi (grace sonrasi probe OK)."
            status_text
            return 0
          fi
        fi
      fi
      sleep 2
      waited=$((waited + 2))
    done

    echo "Deneme basarisiz. Durum: $(status_line)"
    echo "DeviceLastCause=$(device_last_cause) LastCause=$(last_cause)"

    if ppp_has_shared_secret_error; then
      echo "Kritik: ppp.log icinde 'incorrect user shared secret found' goruldu."
      echo "Bu durumda otomatik retry anlamsiz; macOS VPN profilindeki Shared Secret degerini yeniden gir."
      return 2
    fi
  done

  echo "VPN baglanti denemeleri tukenmis durumda."
  echo "Ipucu: macOS VPN ayarlarinda '$SERVICE_NAME' baglantisini bir kez manuel ac/kapat ve tekrar dene."
  echo "Ipucu: LastCause=8 ise kimlik bilgisi veya paylasilan gizli anahtar tarafini kontrol et."
  status_text
  return 1
}

disconnect_vpn() {
  echo "VPN kapatiliyor: $SERVICE_NAME"
  scutil --nc stop "$SERVICE_NAME"
  sleep 1
  status_text
}

watch_vpn() {
  echo "VPN izleme basladi: $SERVICE_NAME"
  echo "Protokol: $SELECTED_PROTOCOL"
  echo "Kontrol araligi: ${CHECK_INTERVAL}s"
  if [[ -n "$PROBE_HOST" ]]; then
    echo "Probe host: $PROBE_HOST"
  fi

  while true; do
    if ! is_connected; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] VPN dusmus. Yeniden baglaniyor..."
      connect_vpn || true
    elif ! probe_host; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Probe ilk denemede basarisiz. Grace bekleniyor..."
      sleep "$PROBE_GRACE_SEC"
      if ! probe_host; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Probe tekrar basarisiz. Yeniden baglanma denenecek..."
        connect_vpn || true
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Probe grace sonrasi toparlandi."
      fi
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] VPN saglam."
    fi

    sleep "$CHECK_INTERVAL"
  done
}

case "$ACTION" in
  status)
    status_text
    ;;
  connect)
    connect_vpn
    ;;
  disconnect)
    disconnect_vpn
    ;;
  restart)
    disconnect_vpn
    connect_vpn
    ;;
  probe)
    if probe_host; then
      echo "Probe OK: $PROBE_HOST"
    else
      echo "Probe FAIL: $PROBE_HOST"
      exit 1
    fi
    ;;
  watch)
    watch_vpn
    ;;
  doctor)
    echo "Service: $SERVICE_NAME"
    echo "Protokol: $SELECTED_PROTOCOL"
    echo "Durum: $(status_line)"
    echo "DeviceLastCause=$(device_last_cause) LastCause=$(last_cause)"
    echo "--- scutil --nc show"
    scutil --nc show "$SERVICE_NAME" 2>&1 | sed -n '1,80p'
    echo "--- /var/log/ppp.log (son 40)"
    tail -n 40 /var/log/ppp.log 2>/dev/null || echo "ppp.log okunamadi"
    ;;
  *)
    echo "Kullanim: scripts/mac_vpn.sh [status|connect|disconnect|restart|probe|watch|doctor]"
    exit 1
    ;;
esac