# E1-002 — REST endpoint tasarimi ve implementasyon

**Ajan:** api-dev  
**Sprint:** E1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

REST API endpoint'lerini tasarla ve uygula. Kaynak: `items` (genel amaçlı). CRUD tam set: liste, tekil okuma, oluşturma, güncelleme, silme. HTTP metodları, durum kodları ve yanıt formatı REST standartlarına uygun olmalı. OpenAPI/Swagger dokümantasyonu oluştur.

## Teslim Kriterleri (Definition of Done)

- [ ] `src/routes/items.js` — tüm CRUD route'ları tanımlı
- [ ] `src/controllers/itemsController.js` — iş mantığı (veri katmanını çağırır)
- [ ] `docs/API.md` — tüm endpoint'ler tablo formatında belgelenmiş
- [ ] `GET /api/v1/items` → `{ "data": [...], "total": N }` döner
- [ ] `GET /api/v1/items/:id` → bulunamazsa `404 { "error": "Not found" }`
- [ ] `POST /api/v1/items` → `201` + oluşturulan nesne
- [ ] `PUT /api/v1/items/:id` → `200` + güncellenmiş nesne
- [ ] `DELETE /api/v1/items/:id` → `204 No Content`
- [ ] `agents/validate.sh` kalite kapısı geçiyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `src/routes/items.js` | Items router |
| `src/controllers/itemsController.js` | Controller (thin — mantık service'te) |
| `src/services/itemsService.js` | İş mantığı katmanı |
| `docs/API.md` | API dokümantasyonu |

## API Endpoint Listesi

```
GET    /api/v1/items          → tümünü listele (sayfalama: ?page&limit)
GET    /api/v1/items/:id      → tekil oku
POST   /api/v1/items          → yeni oluştur
PUT    /api/v1/items/:id      → tümünü güncelle
PATCH  /api/v1/items/:id      → kısmen güncelle
DELETE /api/v1/items/:id      → sil
```

## Yanıt Formatı

```json
// Başarı
{ "data": { ... }, "message": "ok" }

// Hata
{ "error": "açıklama", "code": "ITEM_NOT_FOUND" }
```

## Notlar

- Controller sadece request/response işler; iş mantığı service katmanında
- ID için `uuid` kütüphanesi kullan, sıralı integer değil
- Sayfalama varsayılanı: `page=1`, `limit=20`
