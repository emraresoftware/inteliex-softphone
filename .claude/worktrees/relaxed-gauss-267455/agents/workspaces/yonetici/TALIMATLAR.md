# TALIMATLAR — yonetici

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## AKTIF SPRINT — E6
> durum: completed | odak: coverage esik yukseltme faz-2

- [x] E6-001 tamamlandi
- [x] E6-002 tamamlandi
- [x] E6-003 tamamlandi
- [x] `npm test -- --runInBand` green sonuc verdi
- [x] storage ve observability testlenebilirlik iyilestirmeleri kayda gecti

## E3-103 — Teslim ozet artifacti
> sprint: E3 | durum: in_progress | ajan: yonetici

- [x] `delivery_summary.txt` dosyasini olustur; icinde `sunucu-dev smoke ok`, `test-dev regression ok`, `runner artifact guard ok` satirlari yer alsin

## ARSIV — E1
> not: E1 teslimleri tamamlandi, referans olarak korunuyor.

## E1-000 — Sprint koordinasyonu ve proje iskeleti
> sprint: E1 | durum: completed

- [x] `projects/emarecloud_ceyiz/package.json` oluşturuldu (name, version, scripts, dependencies)
- [x] `projects/emarecloud_ceyiz/README.md` yazıldı (proje amacı, kurulum, endpoint listesi)
- [x] `projects/emarecloud_ceyiz/.env.example` oluşturuldu (PORT, NODE_ENV)
- [x] Tüm E1-001..E1-004 görevleri `in_progress` başladı
- [x] `agents/handoffs.ndjson`'a E1 sprint açılış kaydı eklendi
- [x] E1-005 (test) için bağımlılık kapısı onaylandı

## E1-002 — REST endpoint tasarimi ve implementasyon
> sprint: E1 | durum: completed | ajan: api-dev

- [x] `src/routes/items.js` — tüm CRUD route'ları tanımlı
- [x] `src/controllers/itemsController.js` — thin controller, request/response işler
- [x] `src/services/itemsService.js` — iş mantığı katmanı
- [x] `docs/API.md` — tüm 6 endpoint tablo formatında belgelenmiş
- [x] GET /api/v1/items → `{ "data": [...], "total": N }` + sayfalama (page, limit)
- [x] GET /api/v1/items/:id → 200 + nesne || 404 + error
- [x] POST /api/v1/items → 201 + oluşturulan nesne
- [x] PUT /api/v1/items/:id → 200 + güncellenmiş nesne || 404
- [x] PATCH /api/v1/items/:id → 200 + kısmen güncellenmiş nesne
- [x] DELETE /api/v1/items/:id → 204 No Content || 404
- [x] UUID kullanımı doğrulandı (sıralı integer değil)
- [x] Yanıt formatı düzgün: success `{ "data": {...}, "message": "ok" }` | error `{ "error": "...", "code": "..." }

## E2-000 — Veritabanı entegrasyonu ve migration
> sprint: E2 | durum: completed | ajan: yonetici

- [x] PostgreSQL bağlantısı kur (environment variables ile)
- [x] Migration scripts yaz (items tablosu için)
- [x] Seed data ekle (örnek 10 item)
- [x] NODE_ENV=production için production DB bağlantısı
- [x] Connection pooling aktif et
- [x] `npm run migrate` scripti ekle

## E2-001 — Gelişmiş API özellikleri
> sprint: E2 | durum: completed | ajan: api-dev

- [x] Filtreleme desteği: GET /api/v1/items?name=foo&tags=bar
- [x] Sıralama: GET /api/v1/items?sort=name:asc,createdAt:desc
- [x] İlişkili veriler: tags için ayrı endpoint
- [x] Bulk operations: POST /api/v1/items/bulk (create/update/delete)
- [x] Export: GET /api/v1/items/export?format=json|csv
- [x] API versioning kontrolü (v1, v2 hazırlığı)

## E2-002 — Güvenlik ve performans iyileştirmeleri
> sprint: E2 | durum: completed | ajan: guvenlik-dev

- [x] API key rotation mekanizması
- [x] Rate limiting per user (DB'de track)
- [x] Input sanitization (XSS prevention)
- [x] CORS policy güncelle (production domains)
- [x] Request logging to DB
- [x] Performance monitoring (response times, error rates)
- [x] `agents/validate.sh` kalite kapısı geçti

## E1-003 — Veri katmani ve model tasarimi
> sprint: E1 | durum: completed | ajan: veri-dev

- [x] `src/models/Item.js` — Item şeması: `{ id, name, description, tags, createdAt, updatedAt, deletedAt }`
- [x] `src/storage/fileAdapter.js` — JSON dosya okuma/yazma (atomic write ile)
- [x] `src/storage/memoryAdapter.js` — test için in-memory adapter (aynı interface)
- [x] `src/storage/index.js` — `NODE_ENV=test` ise memory, diğerlerinde file adapter döner
- [x] `src/data/items.json` — başlangıç dosyası (`[]` ile)
- [x] CRUD metodları: `findAll()`, `findById()`, `create()`, `update()`, `delete()` (soft delete)
- [x] Tüm yazma işlemleri atomic (temp dosya → rename)
- [x] `agents/validate.sh` kalite kapısı geçiyor

## E1-004 — Validasyon auth ve guvenlik onlemleri
> sprint: E1 | durum: completed | ajan: guvenlik-dev

- [x] `src/middleware/auth.js` — `Authorization: Bearer <API_KEY>` header kontrolü
- [x] `src/middleware/validate.js` — Joi şemasıyla request body/query validasyonu
- [x] `src/middleware/rateLimit.js` — IP başına dakikada 60 istek limiti
- [x] `helmet` middleware aktif (XSS, HSTS, Content-Type sniffing önleme)
- [x] `src/validation/itemSchema.js` — Item create/update için Joi şemaları
- [x] Geçersiz input → `422 Unprocessable Entity` + alan bazlı hata detayı
- [x] Auth hatası → `401 Unauthorized` (hangi key olduğu açıklanmaz)
- [x] Rate limit aşımı → `429 Too Many Requests` + Retry-After header
- [x] `agents/validate.sh` kalite kapısı geçiyor
- [x] `delivery_summary.txt` dosyasini olustur; icinde `sunucu-dev smoke ok`, `test-dev regression ok`, `runner artifact guard ok` satirlari yer alsin

## E4-003 — Sprint kapanis ozeti
> sprint: E4 | durum: completed

- [x] `sunucu-dev/ci_health_report.txt` ve `test-dev/coverage_report.txt` iceriklerini oku
- [x] `sprint_close_summary.txt` dosyasina su ozet satirlarini yaz: `sunucu-dev ci report ok`, `test-dev coverage report ok`, `coverage thresholds 80 altinda`, `E4 kapanis ozeti hazir`

## E5-003 — E5 teslim ozetini yayinla
> sprint: E5 | durum: completed

- [x] E5-003: E5 teslim ozetini yayinla
- [x] Sonucu `e5_delivery_summary.txt` dosyasına yaz

## E6-003 — E6 teslim ozetini yayinla
> sprint: E6 | durum: completed

- [x] E6-003: E6 teslim ozetini yayinla
- [x] Sonucu `e6_delivery_summary.txt` dosyasına yaz
