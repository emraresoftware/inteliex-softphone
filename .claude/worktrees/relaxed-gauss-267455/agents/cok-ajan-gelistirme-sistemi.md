# Çok-Ajan Geliştirme Sistemi — Tam Dokümantasyon

> Oluşturulma tarihi: 28 Mart 2026  
> Proje: **emarecrm / emare-crm** (Laravel 10/11)  
> Repo: `/Users/emre/Desktop/Emare/emarecrm/emare-crm`

---

## 1. Genel Mimari

```
/Users/emre/Desktop/Emare/emarecrm/
├── emare-crm/              ← Canonical Laravel repo (tek ortak repo)
│   ├── app/
│   │   ├── Http/Controllers/Api/V1/
│   │   ├── Services/
│   │   └── ...
│   ├── routes/api.php
│   ├── tests/Feature/Api/
│   ├── tests/Unit/
│   └── tools/agents/
│       └── validate.sh     ← Merkezi doğrulama aracı
└── .agents/                ← Ajan altyapısı
    ├── runtime.env         ← Çalışma modu yapılandırması
    ├── backlog.json        ← Sprint backlog + dosya sahipliği kuralları
    ├── handoffs.ndjson     ← Ajan devir teslim logu (append-only)
    ├── DIRECT-WRITE-RULES.md ← Ortak repo yazım kuralları
    └── cards/              ← Her sprint kartı için MD dosyaları
        ├── S1-001-is-karti.md
        ├── S1-001-eksik-checklist.md
        ├── S1-003-kapanis-notu.md
        ├── S1-004-kapanis-notu.md
        ├── S1-005-kapanis-notu.md
        └── S1-006-kapanis-notu.md
```

---

## 2. Çalışma Modu: `MODE=direct`

### `.agents/runtime.env`
```env
MODE=direct
REPO_DIR=/Users/emre/Desktop/Emare/emarecrm/emare-crm
```

**Önceki mod:** `MODE=copy` — her ajan kendi worktree kopyasına yazıyordu.  
**Mevcut mod:** `MODE=direct` — tüm ajanlar **tek canonical repo**'ya doğrudan yazar. Merge adımı ortadan kalktı, çakışma riski dosya sahipliği kurallarıyla yönetilir.

---

## 3. Ajan Rolleri ve Sprint Sahiplikleri

| Ajan No | Rol | VS Code Klasörü | Sprint Sahiplikleri |
|---------|-----|-----------------|---------------------|
| 1 | Domain | emarecrm | S1-001, S1-002 |
| 2 | Finance | emarecrm | S1-003 |
| 3 | Integration | emarecrm | S1-004 |
| 4 | Quality | emarecrm | S1-005 |
| 5 | UI | emarecrm | S1-006 |

> Her ajan ayrı bir VS Code penceresidir. Hepsi **aynı** `emare-crm` klasörüne yazar.

---

## 4. Backlog (Sprint 1)

### `.agents/backlog.json` — Özet

```json
{
  "sprint": "S1",
  "directWriteCanonicalRepo": true,
  "orchestratorOnlyOperations": ["validate", "merge", "release"],
  "fileOwnership": {
    "app/Services/SatinalmaService.php":        "domain",
    "app/Services/OnayService.php":             "domain",
    "app/Services/BankaMutabakatService.php":   "finance",
    "app/Services/Integration/WebhookService.php": "integration",
    "app/Services/MusteriPortalService.php":    "ui",
    "tests/Feature/Api/CrmFinanceContractApiTest.php": "quality"
  },
  "tasks": {
    "S1-001": { "status": "in_progress", "owner": "domain",       "title": "PR/PO Satın Alma Akışı" },
    "S1-002": { "status": "todo",        "owner": "domain",       "title": "Onay Motoru (SoD)",  "dependsOn": "S1-001" },
    "S1-003": { "status": "done",        "owner": "finance",      "title": "Banka Mutabakatı" },
    "S1-004": { "status": "done",        "owner": "integration",  "title": "Webhook HMAC + Retry" },
    "S1-005": { "status": "done",        "owner": "quality",      "title": "Contract Testler" },
    "S1-006": { "status": "done",        "owner": "ui",           "title": "Müşteri Portalı" }
  }
}
```

---

## 5. Dosya Sahipliği ve Yazım Kuralları

### `.agents/DIRECT-WRITE-RULES.md` — Özet

1. **Tek dosyaya tek ajan yazar.** `fileOwnership` map'te kimin dosyası olduğu bellidir.
2. **Paylaşımlı dosyalar** (`routes/api.php`, `tests/`): değişiklik öncesinde diğer ajanların aynı dosyayı düzenlemediği kontrol edilir.
3. **Kilit mekanizması:** `handoffs.ndjson`'a `lock_acquire` + `lock_release` eventi yazılır.
4. **Orchestrator'a saklı işlemler:** `validate`, `merge`, `release` yalnızca orkestratör ajan tarafından çalıştırılır.
5. **Yasaklar:**
   - Başka ajanın dosyasını doğrudan düzenlemek.
   - `git push --force` veya `git reset --hard`.
   - `backlog.json` güncellenmeden görevi `done` saymak.

---

## 6. Merkezi Doğrulama

### `tools/agents/validate.sh`

```bash
cd /Users/emre/Desktop/Emare/emarecrm && ./tools/agents/validate.sh emare-crm 2>&1 | cat
```

**Son çıktı:** `Geçti: 6, Hata: 0, Uyarı: 150`

Kontrol ettiği şeyler:
- PHP sözdizimi (`php -l`)
- Laravel route kaydı (`php artisan route:list`)
- Pint kod stili (`vendor/bin/pint --test`)
- PHPUnit testler (`php artisan test`)
- Migration tutarlılığı

---

## 7. Tamamlanan Sprint Maddeleri

### S1-004 — Webhook HMAC + Retry + DLQ

**Dosyalar:**
- `app/Services/Integration/WebhookService.php`
- `app/Http/Controllers/Api/V1/IntegrationController.php`
- `database/migrations/2026_03_28_000002_create_webhook_idempotency_kayitlari_table.php`
- `tests/Feature/Api/IntegrationWebhookApiTest.php`
- `tests/Unit/IntegrationWebhookRetryPolicyTest.php`

**Özellikler:**

| Özellik | Uygulama |
|---------|----------|
| HMAC-SHA256 imza doğrulama | `hash_hmac` + `hash_equals` (timing-safe) |
| Idempotency | DB unique constraint (`webhook_idempotency_kayitlari`) + Cache fallback |
| Retry politikası | 408, 425, 429, 5xx → retry; max 3 deneme |
| Dead Letter Queue | `failed_jobs` tablosu, `webhook_dlq` kuyruğu |
| Observability | `request_id`, `provider`, `event`, `deneme_no` zorunlu log alanları |
| Tablo uyumluluğu | `webhookLogTablosu()` — `Schema::hasTable()` ile runtime'da `webhook_logs` veya `webhook_loglari` seçimi |

**Test özeti:** 5/5 PASS
```
IntegrationWebhookApiTest:    3/3 ✅
IntegrationWebhookRetryPolicyTest: 2/2 ✅
```

**Route:**
```
POST /api/v1/integrations/webhooks/{provider}
```

---

### S1-003 — Banka Mutabakatı

**Dosyalar:**
- `app/Services/BankaMutabakatService.php` (güncellendi)
- `app/Http/Controllers/Api/V1/BankaMutabakatController.php` (yeni)
- `tests/Feature/Api/BankaMutabakatApiTest.php`

**Özellikler:**

| Özellik | Uygulama |
|---------|----------|
| Import formatları | CSV, OFX, MT940, API |
| Duplicate suppression | `deterministicReferansNo()` — tarih+tutar+IBAN hash, DB unique |
| Transaction safety | `DB::transaction()` wrapper tüm write işlemlerinde |
| Zorunlu alan kontrolü | `Validator::make()` ile `hareketSatirlariIceAktar()` girişinde |
| Otomatik eşleştirme | Tutar+tarih+karşı hesap üçlüsüyle fuzzy match |
| Manuel eşleştirme | Muhasebe kalemine doğrudan atama |

**Test özeti:** 4/4 PASS

**Route'lar:**
```
POST /api/v1/finance/banka-mutabakat/ice-aktar
POST /api/v1/finance/banka-mutabakat/{bankaHesapId}/otomatik-eslestir
POST /api/v1/finance/banka-mutabakat/manuel-eslestir
GET  /api/v1/finance/banka-mutabakat/{bankaHesapId}/rapor
```

---

### S1-005 — Contract Testler (CRM ↔ Finance Arayüzü)

**Dosya:** `tests/Feature/Api/CrmFinanceContractApiTest.php`

**Kapsam:**

| Test | Kontrol |
|------|---------|
| Webhook başarı zarfı | `success: true`, `data.event`, `data.provider` alanları |
| Webhook reddetme zarfı | HMAC hatalıysa `422` + `success: false` |
| Banka import kontratı | `data.eklenen`, `data.atlanan`, `data.referanslar[]` yapısı |
| Banka rapor kontratı | `data.toplam_hareket`, `data.eslestirilen`, `data.eslestirme_orani` |

**Test özeti:** 4/4 PASS

---

### S1-006 — Müşteri Portalı

**Dosyalar:**
- `app/Services/MusteriPortalService.php` (yeni)
- `app/Http/Controllers/Api/V1/MusteriPortalController.php` (refactor)
- `tests/Feature/Api/MusteriPortalApiTest.php`

**Özellikler:**

| Metot | Açıklama |
|-------|----------|
| `dashboardData()` | Açık ticket sayısı, ödenmemiş fatura toplamı, son 5 aktivite |
| `ticketOlustur()` | Yeni destek talebi — zorunlu: konu, açıklama, öncelik |
| `ticketleriListele()` | Müşteriye ait tüm ticket'lar, durum filtreli |
| `ticketDetay()` | Tek ticket + mesaj zinciri |
| `faturalariListele()` | Ödeme durumuna göre filtrelenmiş fatura listesi |
| `teklifleriListele()` | Kabul/red/bekleyen teklif listesi |

**Controller:** `ApiController`'dan extend — `success()`, `created()`, `notFound()`, `validationError()` standart zarfları kullanır.

**Test özeti:** 4/4 PASS

**Route'lar:**
```
GET  /api/v1/musteri-portal/dashboard
POST /api/v1/musteri-portal/tickets
GET  /api/v1/musteri-portal/tickets
GET  /api/v1/musteri-portal/tickets/{ticketId}
GET  /api/v1/musteri-portal/invoices
GET  /api/v1/musteri-portal/proposals
```

---

## 8. Devam Eden İş: S1-001 — PR/PO Satın Alma Akışı

**Ajan:** Domain (Agent 1)  
**Durum:** `in_progress`

### Kapsam
- Satın Alma Talebi (PR) oluşturma, güncelleme, iptal
- PR → Satın Alma Siparişi (PO) dönüşümü
- Durum makinesi: `taslak → onay_bekliyor → onaylandı → siparişe_dönüştürüldü → tamamlandı | iptal`
- Kalem bazlı toplam hesaplama

### Planlanacak Dosyalar
```
app/Services/SatinalmaService.php
app/Http/Controllers/Api/V1/SatinalmaController.php
routes/api.php (satinalma grubu)
tests/Feature/Api/SatinalmaApiTest.php
```

### Checklist (`.agents/cards/S1-001-eksik-checklist.md`)
- [ ] Adım 1: PR kontrat ve mevcut kod taraması
- [ ] Adım 2: `SatinalmaService` — `talepOlustur()`, `talepGuncelle()`, `sipariseDonustur()`
- [ ] Adım 3: `SatinalmaController` + route grubu
- [ ] Adım 4: Feature testler (4+ test)
- [ ] Adım 5: validate.sh yeşil, kapanis notu

---

## 9. Bekleyen İş: S1-002 — Onay Motoru (SoD)

**Bağımlılık:** S1-001 tamamlanmalı  
**Kapsam:**
- Separation of Duties (SoD) kontrolleri — talep eden kişi onaylayamaz
- Onay eşiği kuralları (tutar bazlı seviye atlaması)
- `OnayService` — onay atama, onaylama, reddetme, eskalasyon
- `notifications` entegrasyonu (email/in-app)

---

## 10. API Standartları

### Başarılı Yanıt Zarfı
```json
{
  "success": true,
  "data": { ... },
  "message": "İşlem başarılı"
}
```

### Hata Yanıt Zarfı
```json
{
  "success": false,
  "message": "Hata açıklaması",
  "errors": { "alan": ["kural hatası"] }
}
```

### HTTP Durum Kodları
| Durum | Kullanım |
|-------|----------|
| 200 | Başarılı GET/POST |
| 201 | Kaynak oluşturuldu |
| 422 | Validation hatası |
| 404 | Kaynak bulunamadı |
| 401 | Kimlik doğrulama hatası |
| 500 | Sunucu hatası |

### `ApiController` Yardımcı Metodları
```php
$this->success($data, $message, $code = 200)
$this->created($data, $message)
$this->error($message, $code = 400)
$this->notFound($message = 'Kayıt bulunamadı')
$this->validationError($errors)
```

---

## 11. Güvenlik Kontrolleri (OWASP Top 10)

| Risk | Uygulanan Kontrol |
|------|-------------------|
| Broken Access Control | Route middleware `auth:sanctum`, kaynak bazlı yetki |
| Cryptographic Failures | HMAC-SHA256 `hash_equals()` (timing-safe) |
| Injection | Eloquent ORM, `Validator::make()`, parametreli sorgular |
| Insecure Design | SoD onay motoru (S1-002), talep eden ≠ onaylayan |
| Security Misconfiguration | `APP_DEBUG=false` production, `.env` dışarıda |
| Identification & Auth Failures | Sanctum token, webhook HMAC imzası |
| Server-Side Request Forgery | Webhook provider whitelist |

---

## 12. Ajan Devir Teslim Logu Formatı

### `.agents/handoffs.ndjson` — Her satır bir JSON objesi
```json
{"ts":"2026-03-28T10:00:00Z","agent":"domain","event":"kickoff","task":"S1-001","note":"PR/PO akışı başlatıldı"}
{"ts":"2026-03-28T09:00:00Z","agent":"integration","event":"done","task":"S1-004","validate":"Geçti:5,Hata:0"}
{"ts":"2026-03-28T08:30:00Z","agent":"finance","event":"done","task":"S1-003","validate":"Geçti:5,Hata:0"}
{"ts":"2026-03-28T08:00:00Z","agent":"quality","event":"done","task":"S1-005","validate":"Geçti:6,Hata:0"}
{"ts":"2026-03-28T07:30:00Z","agent":"ui","event":"done","task":"S1-006","validate":"Geçti:6,Hata:0"}
```

---

## 13. Güncel Test Özeti

| Test Dosyası | Geçen | Fail | Son Çalıştırma |
|--------------|-------|------|----------------|
| `IntegrationWebhookApiTest` | 3 | 0 | 28 Mar 2026 |
| `IntegrationWebhookRetryPolicyTest` | 2 | 0 | 28 Mar 2026 |
| `BankaMutabakatApiTest` | 4 | 0 | 28 Mar 2026 |
| `CrmFinanceContractApiTest` | 4 | 0 | 28 Mar 2026 |
| `MusteriPortalApiTest` | 4 | 0 | 28 Mar 2026 |
| **Toplam** | **17** | **0** | |

**validate.sh:** `Geçti: 6, Hata: 0, Uyarı: 150`

---

## 14. Bilinen Kısıtlamalar ve Çözümler

| Sorun | Çözüm |
|-------|-------|
| `webhook_loglari` tablosunda `webhook_id` NOT NULL kısıtı | `webhookLogTablosu()` helper ile runtime'da doğru tablo seçimi (`Schema::hasTable()`) |
| Cache-tabanlı idempotency yeterli değil | DB unique constraint (`webhook_idempotency_kayitlari`) + Cache fallback ikili katman |
| `gonderRetryIle()` bool döndürüyordu, detay bilgisi yoktu | `gonderRetryIleDetay()` array döndürür, eski metod backward-compat wrapper olarak kaldı |
| `validate.sh` exit 2 veriyor | `2>&1 \| cat` pipe ile terminal pager'ı bypass edildi, gerçek çıktı okunabilir hale geldi |
| Pint terminal ANSI renk kodları çıktıyı kirletiyordu | `TERM=dumb vendor/bin/pint` ile renksiz çıktı |

---

## 15. Komut Referansı

```bash
# Testleri çalıştır
cd /Users/emre/Desktop/Emare/emarecrm/emare-crm
php artisan test

# Belirli test dosyası
php artisan test tests/Feature/Api/SatinalmaApiTest.php

# Kod stili kontrolü (yazmadan)
vendor/bin/pint --test app/Services app/Http

# Kod stili düzelt
vendor/bin/pint app/Services app/Http

# Tüm doğrulama
cd /Users/emre/Desktop/Emare/emarecrm && ./tools/agents/validate.sh emare-crm 2>&1 | cat

# Route listesi
php artisan route:list --path=api/v1

# Migration çalıştır
php artisan migrate --step
```
