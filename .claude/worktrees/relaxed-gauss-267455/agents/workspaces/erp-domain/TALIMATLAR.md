# TALIMATLAR — erp-domain

Bu dosyadaki `- [ ]` maddeleri uygulanacak görevlerdir.
Uygulanan maddeler `- [x]` ile işaretlenir.

## Proje Bilgisi
- **Proje**: EmareRP (emare-crm)
- **Konum**: `ssh emre@192.168.1.64:/Users/emre/Desktop/Emare/emarerp/emare-crm`
- **PHP**: `/usr/local/bin/php`
- **Framework**: Laravel 11, Livewire 4, PostgreSQL
- **Test**: `PATH=/usr/local/bin:$PATH vendor/bin/phpunit`
- **Validate**: `PATH=/usr/local/bin:$PATH bash tools/agents/validate.sh emare-crm`

## ERP-S1-002 — Approval engine with SoD checks
> sprint: ERP-S1 | durum: in_progress | bagimlilik: ERP-S1-001

### 1. OnayController API endpointleri
- [x] `app/Http/Controllers/Api/V1/OnayController.php` — ApiController'dan extend et
- [x] GET `/api/v1/onay/bekleyen` — Giriş yapan kullanıcının bekleyen onaylarını listele
- [x] GET `/api/v1/onay/gecmis` — Kullanıcının onay geçmişi (sayfalanmış)
- [x] POST `/api/v1/onay/{id}/onayla` — Onay adımını onayla (not opsiyonel)
- [x] POST `/api/v1/onay/{id}/reddet` — Onay adımını reddet (not zorunlu)
- [x] POST `/api/v1/onay/{id}/iptal` — Onay talebini iptal et
- [x] POST `/api/v1/onay/adim/{id}/vekil-ata` — Vekil kullanıcı ata

### 2. Route kayıtları
- [x] `routes/api.php` — Onay prefix grubunu ekle (sanctum middleware altında)

### 3. Satınalma-Onay entegrasyonu
- [x] `app/Http/Controllers/Api/V1/SatinalmaController.php` — `onayaGonder` metodunda OnayMotoru::talepOlustur çağır
- [x] `app/Models/SatinalmaTalebi.php` — `onaylandiIsle()` metodu ekle (durum→onaylandi geçişi)

### 4. Test katmanı
- [x] `tests/Feature/Api/OnayApiTest.php` — Onay akışı oluşturma ve bekleyen listeleme testi
- [x] `tests/Feature/Api/OnayApiTest.php` — SoD: talep eden kendi talebini onaylayamaz testi
- [x] `tests/Feature/Api/OnayApiTest.php` — Onay başarılı + SatinalmaTalebi durum geçişi testi
- [x] `tests/Feature/Api/OnayApiTest.php` — Reddet testi
- [x] `tests/Feature/Api/OnayApiTest.php` — İptal testi

### 5. Doğrulama
- [x] Tüm testler yeşil (444 test, 1554 assertion — OK)
- [x] PHP syntax kontrolü — 0 hata
- [ ] validate.sh — PHPStan session driver sorunlu (mevcut ortam hatası, bizim kodumuza ait değil)
