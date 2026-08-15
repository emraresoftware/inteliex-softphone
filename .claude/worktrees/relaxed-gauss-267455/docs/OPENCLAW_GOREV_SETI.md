# OpenClaw Gorev Seti

Bu dosya OpenClaw orchestrator/worker dagiliminda hizli komut kaliplari verir.

## 1) Rolleri baslat

Not: Gercek cihaz kurulumu icin once [docs/MAC_NODE_KATILIMI.md](docs/MAC_NODE_KATILIMI.md) adimlarini uygula. `start_node.sh` local env dosyalarini (`.env.worker1.local`, `.env.worker2.local`) example dosyalarina tercih eder.

Orchestrator (M5):

```bash
cd /Users/emre/Dergah
scripts/start_node.sh orchestrator panel
scripts/start_node.sh orchestrator openclaw
```

Worker1 (iMac):

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker1 openclaw
```

Worker2 (MacBook Pro):

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker2 openclaw
```

## 1.1) GitHub Relay Kanali Kurulumu

1. GitHub'da tek bir repo sec (ornek: org/dergah-relay).
2. Repo icinde bir issue ac (ornek: #12) ve bunu kanal olarak kullan.
3. Her cihazda env dosyasina asagilari gir:

```bash
export DERGAH_GITHUB_OWNER="org-veya-kullanici"
export DERGAH_GITHUB_REPO="repo-adi"
export DERGAH_GITHUB_TOKEN="ghp_..."
export DERGAH_GITHUB_CHANNEL_ISSUE="12"
```

4. Orchestrator'da duyuru+heartbeat ac:

```bash
cd /Users/emre/Dergah
source .env.m5-orchestrator.example
/Users/emre/Dergah/.venv/bin/python scripts/dergah_orkestrator.py --operator --github-announce --github-heartbeat
```

5. Worker tarafta dinleyici ac:

```bash
cd /Users/emre/Dergah
source .env.worker1.example
/Users/emre/Dergah/.venv/bin/python scripts/dervis_haberlesme_github.py listen --poll-seconds 8
```

## 2) Delegasyon komut kaliplari

Asagidaki metinleri OpenClaw panelinde veya agent chat tarafinda kullan:

- "@Worker1 projects altinda tum Python testlerini calistir, failing testleri listele, sadece rapor don."
- "@Worker1 failing testleri tek tek duzelt, patch uygulayip yeniden test et, en sonda ozet ver."
- "@Worker2 lint ve static check calistir, hatalari oncelik sirasiyla duzelt."
- "@Worker2 scripts altinda ollama hardcode endpoint kaldiysa bulup raporla."
- "@MainBrain son degisiklikleri gozden gecir, risk analizi cikar, merge-ready checklist yaz."

## 3) Hazir gorev bloklari

### A) Test + Fix

"""
@Worker1
1) /Users/emre/Dergah altinda test komutunu tespit et.
2) Tum testleri calistir.
3) Kirmizi testleri duzelt.
4) Tekrar test et.
5) Sonuc raporunu su formatta don:
- degisen dosyalar
- test sonucu
- kalan riskler
"""

### B) Refactor + Guard

"""
@Worker2
1) scripts klasorunde tekrar eden kod bloklarini bul.
2) Davranis degistirmeden refactor et.
3) Gerekiyorsa kucuk regression guard ekle.
4) Raporla.
"""

### C) Release Hazirlik

"""
@MainBrain
1) Son degisiklikleri kontrol et.
2) Calistirma komutlarini dogrula.
3) Dokumanda eksik adim varsa ekle.
4) Release notu yaz.
"""

## 4) Hizli kontrol komutlari

```bash
pgrep -fl "dervis_panel|dervis_core|dervis_operator|openclaw"

tail -n 60 /tmp/dervis_panel.log
tail -n 60 /tmp/dervis_core.log
tail -n 60 /tmp/dervis_operator.log
tail -n 60 /tmp/openclaw.log
```

## 5) Notlar

- Worker makinelerde agir model calistirma; sadece uzaktaki Exo endpoint kullan.
- DERGAH_OPENAI_API_BASE alanina M5 Pro IP/Tailscale adresini yaz.
- Role gore env dosyalarini duzeltmeden baslatma yapma.
