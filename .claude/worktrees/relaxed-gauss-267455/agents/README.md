# Cok-Ajan Gelistirme Sistemi — Dergah Kurulum Rehberi

Bu klasordeki scriptler ve config dosyalari, birden fazla VS Code / Copilot ajaninin **tek bir Dergah reposunda** birlikte calismasi icin uyarlanmistir.

---

## Klasör İçeriği

```
agents/
├── README.md               ← Bu dosya
├── agents.json             ← Ajan tanımları (id, branch, focus alanları)
├── runtime.env             ← Çalışma modu (direct / worktree / copy)
├── backlog.json            ← Sprint görevleri + dosya sahipliği kuralları
├── DIRECT-WRITE-RULES.md  ← Ortak repo'ya yazım kuralları
├── init.sh                 ← Sistemi başlat (worktree veya copy oluştur)
├── intake.sh               ← Yeni görev al / backlog'dan ata
├── merge.sh                ← Orchestrator merge kapısı
├── status.sh               ← Tüm ajanların durumunu göster
├── sync.sh                 ← Canonical repo'dan güncelle
└── validate.sh             ← Kalite kapısı (syntax + test + CDN + güvenlik)
```

---

## Dergah'ta Kurulum

### 1. Script izinlerini ver

```bash
cd /Users/emre/Dergah
chmod +x agents/*.sh
```

### 2. runtime kontrolu

```bash
cat agents/runtime.env
```

Beklenen temel degerler:

```env
MODE=direct
REPO_DIR=/Users/emre/Dergah
BASE_BRANCH=main
```

### 3. backlog doldurma

- `tasks` dizisine Dergah gorevlerini yaz
- `rules.fileOwnership` alanini gercek dosya sahipligine gore guncelle

### 4. Sistemi baslat

```bash
agents/init.sh /Users/emre/Dergah
```

---

## Çalışma Modları

| Mod | Ne zaman kullanılır |
|-----|---------------------|
| `direct` | En basit: tum ajanlar es zamanli tek klasore yazar |
| `worktree` | Git gecmisi onemliyse: her ajan kendi branch'ine yazar |
| `copy` | Git yoksa: her ajan rsync kopyasina yazar |

---

## Ajan Rolleri

| Ajan | Varsayilan Odak |
|------|-----------------|
| orchestrator | Planlama, merge kapisi, release |
| core | dervis_core, orkestrasyon akislar |
| panel | dervis_panel, widget, UI akislari |
| integration | relay, node baglantisi, API guvenligi |
| quality | syntax/smoke dogrulama |
| ops | startup scriptleri ve runtime |

---

## Günlük Kullanım

```bash
# Durumu kontrol et
agents/status.sh

# Kalite kapısını çalıştır
agents/validate.sh /Users/emre/Dergah

# Canonical repo'dan guncelle (direct modda)
agents/sync.sh

# Orchestrator merge
agents/merge.sh AGENT_ADI
```

---

## handoffs.ndjson Formatı

Her ajan devir teslimini bu dosyaya append eder:

```json
{"ts":"2026-01-01T10:00:00Z","agent":"domain","event":"progress","task":"S1-001","note":"SatinalmaService tamamlandı"}
{"ts":"2026-01-01T10:30:00Z","agent":"domain","event":"done","task":"S1-001","validate":"Geçti:5,Hata:0"}
```

Olaylar: `kickoff` | `progress` | `done` | `blocked` | `lock` | `unlock`

---

## Not

Bu klasor Dergah'a gore uyarlanmis bir ornek orkestrasyon paketidir.
`agents/validate.sh` Python/Dergah odakli kalite kapisi calistirir.
