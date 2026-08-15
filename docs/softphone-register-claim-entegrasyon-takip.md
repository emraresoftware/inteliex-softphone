# Softphone Register Claim Entegrasyon Takibi

## Amac
Musteri talebine gore her register denemesinde merkezi servise bilgi gondermek, cihaz kaydini `/devices` ile upsert etmek, register eventlerini auditlenebilir hale getirmek ve opsiyonel tek-cihaz politikasina teknik zemin hazirlamak.

## Kapsam
- Register oncesi cihaz kaydi upsert (`POST /devices`)
- Register oncesi karar servisi (`allow/reject`) cagrisi (opsiyonel enforcement)
- Register sonucu event postlama (`started/success/failed/unregistered`)
- Cihaz kimligi kaliciligi (native stable id + secure fallback)

## Netlestirilen Kararlar (2026-06-06)
- [x] Hata politikasi: kritik alan fail-closed, ancak altyapi/rate-limit baglantili hatalarda fail-open.
- [x] Device ID backend tarafinda gelen degeri saklar; mobil tarafta kalicilik saglanmali.
- [x] Coklu paralel login su an serbest; tek-cihaz politikasi zorunlu degil, opsiyonel.
- [x] Admin onayli cihaz degisim akisi istenmiyor.
- [x] Guvenlik modeli JWT degil, opaque Bearer token.

## Runtime Ayarlari (dart-define)
- `INTELIEX_CLAIM_BASE_URL`: claim backend base url
- `INTELIEX_CLAIM_API_KEY`: opaque bearer token
- `INTELIEX_CLAIM_ENFORCED`: claim check enforcement ac/kapat
- `INTELIEX_CLAIM_DEVICES_PATH`: varsayilan `/api/v2/index.php?_path=devices`
- `INTELIEX_CLAIM_CHECK_PATH`: varsayilan bos (endpoint tanimsizsa disable)
- `INTELIEX_CLAIM_EVENT_PATH`: varsayilan bos (endpoint tanimsizsa disable)
- `INTELIEX_CLAIM_FAIL_OPEN_STATUS_CODES`: fail-open HTTP kodlari (varsayilan: `429,500,502,503`)
- `INTELIEX_CLAIM_FAIL_OPEN_ON_NETWORK_ERROR`: status kodu olmayan network/time-out hatalarinda fail-open (varsayilan: `true`)

## Postman Hazir Dosyalar
- `docs/postman/Inteliex_API_v2_Auth_Devices.postman_collection.json`
- `docs/postman/Inteliex_API_v2_Staging.postman_environment.json`

Not: Collection sirasiyla `Auth - Login` -> `Auth - Refresh` -> `Devices - Upsert` akisini kapsar ve login/refresh test scriptleri tokenlari environment'a otomatik yazar.

## Ortam Komutlari
### Staging (onerilen)
```bash
flutter run \
  --dart-define=INTELIEX_CLAIM_BASE_URL=https://staging-claim.example.com \
  --dart-define=INTELIEX_CLAIM_API_KEY=REPLACE_WITH_STAGING_TOKEN \
  --dart-define=INTELIEX_CLAIM_ENFORCED=false \
  --dart-define=INTELIEX_CLAIM_FAIL_OPEN_STATUS_CODES=429,500,502,503 \
  --dart-define=INTELIEX_CLAIM_FAIL_OPEN_ON_NETWORK_ERROR=true
```

### Production (musteri cevabina gore)
```bash
flutter build apk --release \
  --dart-define=INTELIEX_CLAIM_BASE_URL=https://claim.example.com \
  --dart-define=INTELIEX_CLAIM_API_KEY=REPLACE_WITH_PROD_TOKEN \
  --dart-define=INTELIEX_CLAIM_ENFORCED=false \
  --dart-define=INTELIEX_CLAIM_FAIL_OPEN_STATUS_CODES=429,500,502,503 \
  --dart-define=INTELIEX_CLAIM_FAIL_OPEN_ON_NETWORK_ERROR=true
```

Not: Tek-cihaz policy acilacaksa sadece `INTELIEX_CLAIM_ENFORCED=true` alinmalidir.

## Mimari Taslak
1. Uygulama register oncesi `POST /devices` ile `deviceId + pushToken` upsert eder.
2. Enforcement aciksa `device-claim/check` cagrilir, kapaliysa register direkt devam eder.
3. Enforcement acik oldugunda `allow/reject` kararina gore register devam eder veya durdurulur.
4. Register denemesi/sonucu `register/event` endpointine post edilir.
5. Coklu login varsayilan serbesttir; tek-cihaz davranisi ileride backend policy ile acilabilir.

## Endpoint Taslagi
### 1) Device Claim Check
- Method: POST
- Path: `/softphone/device-claim/check`
- Request alanlari (taslak):
  - `tenantId`
  - `extension`
  - `deviceId`
  - `platform`
  - `appVersion`
  - `pushToken` (opsiyonel)
  - `requestId`
- Response alanlari (taslak):
  - `decision`: `allow | reject`
  - `reasonCode`
  - `message`

### 1.1) Device Upsert
- Method: POST
- Path: `/devices`
- Request alanlari (taslak):
  - `tenantId`
  - `extension`
  - `deviceId`
  - `platform`
  - `appVersion`
  - `pushToken` (opsiyonel)
  - `requestId`

### 2) Register Event
- Method: POST
- Path: `/softphone/register/event`
- Request alanlari (taslak):
  - `tenantId`
  - `extension`
  - `deviceId`
  - `status`: `started | success | failed | unregistered`
  - `sipCode` (opsiyonel)
  - `reason` (opsiyonel)
  - `requestId`
  - `occurredAt`

## Uygulama Is Plani (Sirali)
- [x] 1. DTO ve servis arayuzunu ekle
- [x] 2. Register oncesi pre-check hook ekle
- [x] 3. Register sonucu event hook ekle
- [x] 4. Feature flag (`claimEnforced`) ekle
- [x] 5. Reject durumunda kullanici mesaji ve durum satiri
- [x] 6. Timeout/retry/idempotency kurallari
- [x] 7. Loglama ve telemetry alanlarini tamamla
- [ ] 8. Testler (unit + integration + manuel senaryo)

## Durum Guncelleme Formati
Her adim tamamlandiginda asagidaki formatla kayit ac:

- Tarih:
- Adim:
- Yapilan degisiklik:
- Etkilenen dosyalar:
- Test sonucu:
- Not/Risk:

## Ilerleme Gunlugu
- 2026-05-20
  - Durum: Planlama basladi.
  - Not: Musteri netlestirme sorularinin yaniti bekleniyor.
  - Sonraki adim: Kodda 1. adim (DTO + servis arayuzu) ile baseline hazirligi.

- 2026-05-20
  - Adim: 1 (DTO + servis arayuzu)
  - Yapilan degisiklik: Register claim akisi icin request/response DTO'lari, event DTO'su ve servis interface'i eklendi. Noop factory ile entegrasyon sonrasi adimlara hazir hale getirildi.
  - Etkilenen dosyalar: lib/services/sip/softphone_register_claim_service.dart, lib/services/sip/create_softphone_register_claim_service.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: Henuz network implementasyonu yok; karar servisi entegrasyonu 2. ve 3. adimda baglanacak.

- 2026-05-20
  - Adim: 2 (Register oncesi pre-check hook)
  - Yapilan degisiklik: Register denemesi oncesi device claim kontrolu eklendi. Manuel reconnect, hesap secimi ve otomatik sync akislarinda pre-check calisiyor; reject durumunda register baslatilmiyor.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart, lib/services/sip/sip_device_identity_service.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: Su an claim servisi noop oldugu icin tum istekler allow donuyor; gercek endpoint baglantisi 3. adimla devam edecek.

- 2026-05-20
  - Adim: 3 (Register sonucu event hook)
  - Yapilan degisiklik: Register baslangic ve sonuc durumlari (started/success/failed/unregistered) claim servisine event olarak postlanacak sekilde hooklandi. SIP reason icinden code parse yardimcisi eklendi.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: Servis implementasyonu henuz noop; eventler su an dis servise gitmiyor, sadece entegrasyon noktasi hazir.

- 2026-05-20
  - Adim: 4 (Feature flag)
  - Yapilan degisiklik: Claim enforcement akisi compile-time flag ile kontrol edilir hale getirildi. `INTELIEX_CLAIM_ENFORCED` false oldugunda pre-check blocklamiyor.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: Uretimde flag true alinmadan reject mekanizmasi aktif olmayacak.

- 2026-05-20
  - Adim: 5 (Reject mesaji)
  - Yapilan degisiklik: Claim reject durumlari reasonCode'a gore standart ve kullanici-dostu mesajlara maplendi. Status line ve hesap reason alanlari bu mesajla guncelleniyor.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: Backend tarafindan gelen message varsa dogrudan gosteriliyor; metin standardi backend tarafinda da korunmali.

- 2026-05-20
  - Adim: 6 (Timeout/retry/idempotency)
  - Yapilan degisiklik: Claim servisi icin HTTP implementasyonu eklendi. Request timeout, 5xx/429/408 durumunda retry ve `X-Idempotency-Key`/`X-Request-Id` basliklari eklendi. Factory env'e gore HTTP veya noop secimi yapiyor.
  - Etkilenen dosyalar: lib/services/sip/http_softphone_register_claim_service.dart, lib/services/sip/create_softphone_register_claim_service.dart, lib/services/sip/softphone_register_claim_service.dart
  - Test sonucu: flutter analyze temiz.
  - Not/Risk: INTELIEX_CLAIM_BASE_URL verilmediginde noop servis devreye girer.

- 2026-05-20
  - Adim: 7 (Loglama ve telemetry)
  - Yapilan degisiklik: Claim check ve event post akisina requestId, attempt, HTTP status ve elapsedMs bazli debug loglari eklendi. Controller tarafinda allow/reject karar loglari standardize edildi.
  - Etkilenen dosyalar: lib/services/sip/http_softphone_register_claim_service.dart, lib/services/sip/softphone_controller.dart
  - Test sonucu: flutter analyze + flutter test
  - Not/Risk: Telemetry su an debugPrint seviyesinde; merkezi log toplama entegrasyonu opsiyonel sonraki faz.

- 2026-05-20
  - Adim: 8 (Testler) - Kismi
  - Yapilan degisiklik: Claim DTO parse/serialize davranisi icin unit testler eklendi.
  - Etkilenen dosyalar: test/services/sip/softphone_register_claim_service_test.dart
  - Test sonucu: flutter test gecti.
  - Not/Risk: Integration ve manuel claim endpoint senaryolari henuz acik.

- 2026-05-20
  - Adim: 8 (Testler) - Guncelleme
  - Yapilan degisiklik: HTTP claim servisi icin integration-benzeri unit testler eklendi (request/headers, retry, error handling).
  - Etkilenen dosyalar: test/services/sip/http_softphone_register_claim_service_test.dart
  - Test sonucu: flutter test gecti.
  - Not/Risk: Gercek backend ile manuel E2E senaryolari halen calistirilmadi; bu nedenle 8. adim tamamen kapanmadi.

- 2026-06-06
  - Adim: Backend kararlarina uyarlama
  - Yapilan degisiklik: Coklu login varsayimi ve fail policy kararlarina gore dokuman revize edildi. Kod tarafinda register oncesi `/devices` upsert eklendi, claim enforcement fail policy status-code bazli hale getirildi ve Android icin native stable device id kanali eklendi.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart, lib/services/sip/softphone_register_claim_service.dart, lib/services/sip/http_softphone_register_claim_service.dart, lib/services/sip/create_softphone_register_claim_service.dart, lib/services/sip/sip_device_identity_service.dart, android/app/src/main/kotlin/com/example/inteliex_softphone/MainActivity.kt
  - Test sonucu: flutter analyze + flutter test gecti.
  - Not/Risk: 500/502/503 ve 429 fail-open karari dokumanda netlesti; policy degisirse `_shouldFailOpenForClaimError` guncellenmeli.

- 2026-06-06
  - Adim: Fail policy parametriklestirme
  - Yapilan degisiklik: Claim fail-open/fail-closed davranisi `dart-define` ile runtime konfigüre edilebilir hale getirildi.
  - Etkilenen dosyalar: lib/services/sip/softphone_controller.dart
  - Test sonucu: flutter analyze + flutter test gecti.
  - Not/Risk: Ortamlar arasi farkli define degerleri beklenmeyen davranis uretebilir; release pipeline'da sabitlenmeli.

- 2026-06-06
  - Adim: E2E calistirma hazirligi
  - Yapilan degisiklik: Staging/production icin dogrudan kullanilabilir `dart-define` komutlari ve manuel E2E kapanis kayit sablonu eklendi.
  - Etkilenen dosyalar: docs/softphone-register-claim-entegrasyon-takip.md
  - Test sonucu: Dokumantasyon guncellemesi.
  - Not/Risk: Gercek endpoint/token degerleri ortama gore doldurulmali.

- 2026-06-06
  - Adim: Demo auth/devices smoke test
  - Yapilan degisiklik: Query-string endpoint formatiyla (`/api/v2/index.php?_path=...`) login + refresh + devices upsert canli test edildi.
  - Etkilenen dosyalar: Dokuman guncellemesi (kod degisikligi yok).
  - Test sonucu: `login_status=200`, `refresh_status=200`, `devices_status=201`.
  - Not/Risk: `/softphone/device-claim/check` ve `/softphone/register/event` endpointleri backendde tanimli degil; bu nedenle check/event pathleri varsayilan olarak disabled.

- 2026-06-06
  - Adim: Paralel login dogrulamasi
  - Yapilan degisiklik: Ayni kullaniciyla iki ayri login tokeni alindi; her iki token ile `/api/v2/index.php?_path=extensions` cagrisi basarili oldu.
  - Etkilenen dosyalar: Dokuman guncellemesi (kod degisikligi yok).
  - Test sonucu: `login_a=200`, `login_b=200`, `extensions_token_a=200`, `extensions_token_b=200`.
  - Not/Risk: Beklenen sekilde paralel login aktif; tek-cihaz politikasi backend tarafinda bilerek kapali.

## Manuel Test Checklist (E2E)
- [x] 1. `INTELIEX_CLAIM_BASE_URL` ve (varsa) `INTELIEX_CLAIM_API_KEY` ile uygulamayi ac.
- [x] 2. `POST /devices` kaydi her register oncesi upsert oluyor mu (yeni token ile ayni device guncelleniyor mu) kontrol et.
- [x] 3. `INTELIEX_CLAIM_ENFORCED=false` iken paralel login akisi bloklanmadan calisiyor mu kontrol et.
- [ ] 4. `INTELIEX_CLAIM_ENFORCED=true` iken backend reject donerse mesaj dogru mu kontrol et.
- [ ] 5. Backend 500/502/503 ve 429 senaryolarinda fail-open davranisi beklendigi gibi mi kontrol et.
- [ ] 6. Claim check disindaki kritik policy hatalarinda fail-closed davranisi dogrula.
- [ ] 7. Register eventleri (started/success/failed/unregistered) backend audit kayitlarina dusuyor mu kontrol et.

## E2E Sonuc Kaydi (Kapatma Icin)
- Tarih:
- Ortam: staging / production
- Build:
- Cihaz(lar):
- Claim enforcement: true / false
- Sonuclar:
  - [ ] `/devices` upsert dogrulandi
  - [ ] paralel login dogrulandi
  - [ ] reject mesaji dogrulandi (enforced=true)
  - [ ] fail-open kodlari dogrulandi
  - [ ] fail-closed senaryosu dogrulandi
  - [ ] register event audit dogrulandi
- Acik risk/not:

## Riskler
- Fail policy yorum farki olursa (ozellikle 5xx/429) beklenmeyen bloklama veya gereksiz aciklik olusabilir.
- Android reinstall kaliciliginda cihaz degiskenligi olursa backendde gereksiz yeni claim kaydi acilabilir.
- Sunucu saat farki ve tekrar denemeler idempotency olmadan cift kayit uretebilir.

## Cikis Kriteri
- Register oncesi cihaz upsert mekanizmasi canli
- Register oncesi karar mekanizmasi (opsiyonel enforcement) canli
- Coklu login varsayilan davranisla uyumlu
- Event kayitlari auditlenebilir
