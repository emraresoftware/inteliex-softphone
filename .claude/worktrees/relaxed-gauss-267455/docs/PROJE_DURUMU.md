# DERGAH PROJESİ — MEVCUT DURUM RAPORU

**Tarih:** 28 Mart 2026  
**Platform:** Apple M5 Pro — macOS  
**Python:** 3.14 (virtualenv)  
**Model:** Env tabanli (varsayilan: qwen2.5-coder:14b)  
**Yedek Model:** llama3.2:latest (2.0 GB)

---

## 1. Vizyon

60 yazılım projesini otonom yöneten, yerel dil modeli (Qwen) üzerinden terminal, internet ve dosya sistemi yetkilerine sahip dijital bir tekke/dergah sistemi.

### Aktörler

| Rol | Kim | Görev |
|-----|-----|-------|
| **Mürşid** | Emre / Gemini | Stratejik karar verici |
| **Derviş** | Qwen 2.5 Coder 14B (lokal) | Kararları uygulayan otonom ajan |
| **Amele** | GitHub Copilot | Manifestoya göre kod inşa eden işçi |

---

## 2. Dizin Yapısı

```
Dergah/
├── docs/                        # Dokümantasyon
│   ├── DERGAH_MANIFESTO.md      # Temel manifesto
│   └── PROJE_DURUMU.md          # Bu dosya
├── scripts/                     # Otomasyon ve ajan scriptleri (1403 satır)
│   ├── dervis_core.py           # Ana ajan çekirdeği (582 satır)
│   ├── tescil_merasimi.py       # Proje tarama ve tescil (132 satır)
│   ├── dervis_operator.py       # Komut döngüsü operatörü (118 satır)
│   ├── logger.py                # Renkli log altyapısı (95 satır)
│   ├── init_dergah.py           # Sistem başlatıcı (64 satır)
│   ├── dergah_orkestrator.py    # Tek komut orkestratör (50 satır)
│   ├── hayalet_dongu.py         # Hayalet döngü servisi (76 satır)
│   ├── hayalet_brain.py         # Hayalet beyin modülü (50 satır)
│   ├── dosya_oku.py             # Dosya okuyucu yardımcı (45 satır)
│   ├── komuta.py                # Komuta modülü (37 satır)
│   ├── copilot_deneme.py        # Copilot deney alanı (36 satır)
│   ├── analizci.py              # Analiz modülü (34 satır)
│   ├── brain_bridge.py          # Beyin köprüsü (34 satır)
│   ├── kapi_nobetcisi.py        # Kapı nöbetçisi (29 satır)
│   └── operator.py              # Operatör temel modül (21 satır)
├── data/                        # Veri ve log deposu
│   ├── dergah_defteri.json      # Proje tescil defteri (ledger)
│   ├── islem_gunlugu.log        # İşlem günlüğü
│   └── chat_memory/             # Sohbet hafızası dosyaları
├── projects/                    # Proje hücreleri (henüz boş)
├── Desktop/
│   └── DervishCore.command      # Masaüstü çift tıkla başlatıcı
└── .venv/                       # Python sanal ortamı
```

---

## 3. Ana Bileşenler

### 3.1 dervis_core.py — Ajan Çekirdeği

Sistemin kalbi. Qwen modeli ile iletişim kuran, 11 farklı aksiyonu yönetebilen otonom ajan.

**Yetenekler:**

| # | Aksiyon | Açıklama |
|---|---------|----------|
| 1 | `terminal` | Shell komutu çalıştırır (subprocess) |
| 2 | `fetch_url` | Web sayfası içeriği çeker (Playwright + requests fallback) |
| 3 | `read_file` | Dosya okur |
| 4 | `write_file` | Dosya oluşturur / üstüne yazar |
| 5 | `append_file` | Dosya sonuna ekleme yapar |
| 6 | `list_dir` | Dizin içeriği listeler |
| 7 | `search_files` | Dosyalarda metin/regex arar |
| 8 | `delete_path` | Dosya veya klasör siler |
| 9 | `python_eval` | Python kodu çalıştırır |
| 10 | `think` | Düşünür, plan yapar, kullanıcıya cevap verir |
| 11 | `stop` | Döngüyü sonlandırır |

**Model Parametreleri:**

| Parametre | Değer |
|-----------|-------|
| Context Window | 16384 token |
| Temperature | 0.4 |
| Top P | 0.9 |
| Repeat Penalty | 1.1 |
| Komut Timeout | 300 saniye |
| HTTP Timeout | 25 saniye |
| Maks Adım/Görev | 20 |

**Çalışma Modları:**

| Mod | Komut | Açıklama |
|-----|-------|----------|
| Etkileşimli Chat | `--chat` | Terminalde sohbet, spinner, streaming çıktı |
| Otonom Döngü | (varsayılan) | Sonsuz döngüde otonom çalışma |

**Sohbet Komutları:**

| Komut | İşlev |
|-------|-------|
| `cikis` | Hafızayı kaydedip çıkar |
| `/temizle` | Sohbet hafızasını sıfırlar |
| `/hafiza` | Mesaj sayısını gösterir |
| `/verbose` | Detaylı/sade mod geçişi |

**Sohbet Hafızası:**
- Her oturum `data/chat_memory/` altında JSON olarak saklanır
- Son sohbet `latest.json` olarak kalır, yeniden açılınca devam eder
- Eski mesajlar otomatik özetlenerek context taşması önlenir

### 3.2 tescil_merasimi.py — Proje Tescil Sistemi

- `projects/` altındaki tüm klasörleri tarar
- Her projenin dosya parmak izini çıkarır (uzantı dağılımı + örnek dosyalar)
- Qwen modeline proje analizi yaptırır
- Sonuçları `data/dergah_defteri.json` içine profesyonel ledger formatında yazar
- Asenkron, semaphore bazlı (6 eşzamanlı) yüksek performanslı çalışır

### 3.3 dervis_operator.py — Komut Operatörü

- Modelden `KOMUT: <komut>` formatında talimat alır
- Komutu async subprocess ile çalıştırır
- Sonucu modele raporlar, yeni adım ister
- Timeout ve format kontrolü içerir

### 3.4 logger.py — Log Altyapısı

- Terminale renkli çıktı (ANSI renk kodları)
- Dosyaya eşzamanlı yazım (`data/islem_gunlugu.log`)
- Seviyeler: debug, info, warning, error, success

### 3.5 init_dergah.py — Başlatıcı

- `projects/`, `scripts/`, `data/` dizinlerini oluşturur
- Varsayılan ledger ve log dosyalarını hazırlar
- Asenkron çalışır

### 3.6 dergah_orkestrator.py — Orkestratör

- Tek komutla init → tescil → (opsiyonel) operatör akışını yönetir
- `--operator` bayrağıyla operatör döngüsünü de başlatır

---

## 4. Bağımlılıklar

| Paket | Kullanım |
|-------|----------|
| `ollama` | Yerel model iletişimi (ollama provider) |
| `requests` | HTTP istekleri ve OpenAI-compatible bridge |
| `playwright` | Headless browser ile web kazıma |

---

## 5. Başlatma Komutları

```bash
# 1. Masaüstü kısayolu (çift tıkla)
~/Desktop/DervishCore.command

# 2. Etkileşimli sohbet
/Users/emre/Dergah/.venv/bin/python scripts/dervis_core.py --chat

# 3. Otonom döngü
/Users/emre/Dergah/.venv/bin/python scripts/dervis_core.py

# 4. Tam orkestrasyon (init + tescil)
/Users/emre/Dergah/.venv/bin/python scripts/dergah_orkestrator.py

# 5. Tam orkestrasyon + operatör
/Users/emre/Dergah/.venv/bin/python scripts/dergah_orkestrator.py --operator

# 6. OpenClaw/Exo modu (M5 Pro Exo endpoint)
source .env.openclaw.example
/Users/emre/Dergah/.venv/bin/python scripts/dervis_panel.py
```

---

## 6. Mevcut Durum

| Alan | Durum |
|------|-------|
| Dizin yapısı | Hazır |
| Init sistemi | Çalışıyor |
| Ajan çekirdeği (dervis_core) | Çalışıyor — 11 yetenek aktif |
| Tescil sistemi | Çalışıyor — proje bekleniyor |
| Log altyapısı | Çalışıyor |
| Orkestratör | Çalışıyor |
| Masaüstü kısayolu | Hazır |
| Sohbet hafızası | Aktif |
| Streaming çıktı | Aktif |
| projects/ dizini | Boş — projeler eklenmeyi bekliyor |
| Toplam kod | 1403 satır (15 script) |

---

## 7. Sonraki Adımlar

- [ ] 60 projeyi `projects/` altına yerleştirmek
- [ ] `tescil_merasimi.py` ile toplu analiz ve defter kaydı
- [ ] Ajan görev planlayıcı (hedef odaklı otonom iş akışı)
- [ ] Projeler arası bağımlılık haritası
- [ ] Web dashboard (localhost üzerinden durum izleme)

---

## 8. OpenClaw + Exo Gecis Notu

- LLM cagrilari artik `scripts/llm_bridge.py` uzerinden yapiliyor.
- `DERGAH_LLM_PROVIDER=ollama` ise eski davranis korunur.
- `DERGAH_LLM_PROVIDER=openai_compat` ise Exo/OpenAI-compatible endpoint kullanilir.
- Ornek ortam degiskenleri: `.env.openclaw.example`.
- Role bazli env dosyalari: `.env.m5-orchestrator.example`, `.env.worker1.example`, `.env.worker2.example`.
- Tek komut baslatma scripti: `scripts/start_node.sh`.
- Gorev komut seti: `docs/OPENCLAW_GOREV_SETI.md`.
- Otomatik failover: `openai_compat` timeout/hata verirse `llm_bridge.py` ile Ollama'ya dusus (env: `DERGAH_LLM_FALLBACK_OLLAMA=1`).
- Hedef dagilim:
	- M5 Pro: Exo ana model sunucusu + OpenClaw orchestrator
	- Intel Mac 1-2: OpenClaw worker (komut/test/dosya islemleri)
