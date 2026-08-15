# Diger Mac'leri Dergah'a Baglama

Bu rehber worker Mac'leri mevcut Dergah sistemine katmak icin en kisa operasyon akisini verir.

## 0) Once VPN'i profil yerine komut satirindan yonet

Bu repoda yerel bir VPN config akisi vardir. Gercek kimlik bilgileri `data/config/vpn.local.json` icinde tutulur ve git'e gonderilmez.

Bu makinede mevcut macOS VPN servis adi `hipernet` olarak kaydedildi. Profil dosyasi yerine mevcut servisi komut satirindan yonetmek daha stabil olabilir.

### Tek protokol karari

- Standart protokol: `L2TP/IPSec`
- Config anahtari: `selected_protocol: l2tp_ipsec`
- Bu repodaki `scripts/mac_vpn.sh` sadece bu protokol icin calisir.
- Sunucuda baska VPN portlari acik olsa bile operasyon standardi degismez.

Durum kontrolu:

```bash
cd /Users/emre/Dergah
scripts/mac_vpn.sh status
```

Baglan:

```bash
cd /Users/emre/Dergah
scripts/mac_vpn.sh connect
```

Koparsa otomatik yeniden bagla:

```bash
cd /Users/emre/Dergah
scripts/mac_vpn.sh watch
```

Istersen yine profil dosyasi da uretebilirsin:

```bash
cd /Users/emre/Dergah
python3 scripts/generate_macos_vpn_mobileconfig.py
open data/config/dergah-vpn.mobileconfig
```

Ancak onerilen akış: mevcut `hipernet` servisini manuel olusturup bundan sonra `scripts/mac_vpn.sh` ile kullanmak.

Not:

- VPN sunucu adresi: `185.189.54.8`
- VPN ic ag araligi: `172.17.0.10-172.17.0.16`
- Varsayilan M5/coordinator host: `172.17.0.10`
- Varsayilan probe host: `172.17.0.10`
- Node katilim komutlarinda `--m5-host` olarak VPN ic IP adresini kullanin.
- `data/config/vpn.local.json` icindeki `preferred_hosts` alanina ic IP'leri yazarsaniz operasyon notlari tek yerde kalir.

## 1) Her worker Mac'te repo ve venv hazir olmalı

```bash
cd /Users/emre/Dergah
source .venv/bin/activate
```

## 2) Worker env dosyasini olustur

Worker1 (iMac) icin:

```bash
cd /Users/emre/Dergah
scripts/join_mac_node.sh \
  --role worker1 \
  --m5-host 172.17.0.10 \
  --github-owner ORG_VEYA_USER \
  --github-repo REPO_ADI \
  --github-issue 12 \
  --github-token GITHUB_TOKEN \
  --start-status
```

Worker2 (MacBook Pro) icin:

```bash
cd /Users/emre/Dergah
scripts/join_mac_node.sh \
  --role worker2 \
  --m5-host 172.17.0.10 \
  --github-owner ORG_VEYA_USER \
  --github-repo REPO_ADI \
  --github-issue 12 \
  --github-token GITHUB_TOKEN \
  --start-status
```

Bu komut `.env.worker1.local` veya `.env.worker2.local` dosyasini olusturur. `start_node.sh` artik bu local dosyalari, example dosyalarina tercih eder.

## 3) Durumu kontrol et

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker1 status
scripts/start_node.sh worker2 status
```

Beklenen:

- `OPENAI_API_BASE` M5 adresini gostermeli.
- `GITHUB_RELAY=configured` olmali.

## 4) Mesaj kanalina baglan

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker1 relay-listen
```

veya:

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker2 relay-listen
```

Log:

- `/tmp/dervis_relay.log`

## 5) OpenClaw worker baslat

```bash
cd /Users/emre/Dergah
scripts/start_node.sh worker1 openclaw
```

OpenClaw CLI yoksa once `OPENCLAW_BIN` tanimlanmali ya da resmi CLI kurulumu yapilmali.

## 6) Orchestrator tarafi

M5 cihazinda:

```bash
cd /Users/emre/Dergah
source .env.m5-orchestrator.example
/Users/emre/Dergah/.venv/bin/python scripts/dergah_orkestrator.py --operator --github-announce --github-heartbeat
```

## 7) Hata ayiklama

- Relay env eksikse `scripts/dervis_haberlesme_github.py` ValueError verir.
- Exo hala stabil degilse worker'lar `DERGAH_LLM_FALLBACK_OLLAMA=1` ile fallback kullanir.
- Mesaj sistemi icin ayni repo ve ayni issue tum cihazlarda ortak olmalidir.

## 8) SSH varsa uzaktan tek komutla bagla

Bu makineden diger Mac'e anahtarsiz ya da hazir SSH erisimi varsa:

```bash
cd /Users/emre/Dergah
scripts/bootstrap_remote_mac.sh \
  --host 192.168.1.60 \
  --user emre \
  --role worker1 \
  --m5-host 172.17.0.10 \
  --github-owner ORG_VEYA_USER \
  --github-repo REPO_ADI \
  --github-issue 12 \
  --github-token GITHUB_TOKEN \
  --start-relay
```

Not: Bunun calismasi icin hedef Mac'te `Remote Login` acik olmali ve bu makineden SSH baglantisi kabul edilmeli.

## 9) VPN yerine dis IP ile baglan

Eger VPN yerine dogrudan public SSH kullanacaksan, yerel kayit dosyasi [data/config/sunucular.local.json](/Users/emre/Dergah/data/config/sunucular.local.json) icinde tutulur.

Yapilan testte `185.189.54.104:22` acik bulundu ancak `root` kullanicisi parola kabul etmedi. Sunucu sadece `publickey` ile giris kabul ediyor.

Bu erisim artik dogrulandi. Tek komutla baglanmak icin:

```bash
cd /Users/emre/Dergah
scripts/public_server_ssh.sh
```

Uzakta tek komut calistirmak icin:

```bash
cd /Users/emre/Dergah
scripts/public_server_ssh.sh 'hostname && pwd'
```

Bu akista `bootstrap_remote_mac.sh` parola ile de calisabilir. Parolayi komut satirina yazmak yerine ortam degiskeni kullan:

```bash
cd /Users/emre/Dergah
export DERGAH_REMOTE_PASSWORD='PAROLAYI_BURAYA_YAZ'
scripts/bootstrap_remote_mac.sh \
  --host 185.189.54.104 \
  --user root \
  --role worker1 \
  --m5-host 172.17.0.10 \
  --github-owner ORG_VEYA_USER \
  --github-repo REPO_ADI \
  --github-issue 12 \
  --github-token GITHUB_TOKEN \
  --start-relay
unset DERGAH_REMOTE_PASSWORD
```

Notlar:

- Bu sunucuda mevcut durumda parola degil `publickey` gerekiyor.
- Elindeki uygun public key: `/Users/emre/.ssh/id_ed25519.pub`
- Sunucuya eklenmesi gereken satir:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB42kZLXK6/ZytItYWcQ2+8CvSpc6Q9LNhFsoDKlBZbf emre@ecomaiq
```

- Bu anahtari sunucuda `/root/.ssh/authorized_keys` icine ekledikten sonra mevcut `bootstrap_remote_mac.sh` anahtar moduyla dogrudan calisir.
- Pratikte bu sunucuda repo henuz bulunmuyor; bootstrap once uzak makinede repo varligini gerektirir.
- M5 host olarak hala ic servis IP'si kullaniliyor; bunu mimaride degistirmek istersen ayri ele alalim.
