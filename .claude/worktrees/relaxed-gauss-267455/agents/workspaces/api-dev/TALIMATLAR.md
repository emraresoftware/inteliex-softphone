# TALIMATLAR — api-dev

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## E1-002 — REST endpoint tasarimi ve implementasyon
> sprint: E1 | durum: in_progress

- [x] `src/routes/items.js` — tüm CRUD route'ları tanımlı
- [x] `src/controllers/itemsController.js` — iş mantığı (veri katmanını çağırır)
- [x] `docs/API.md` — tüm endpoint'ler tablo formatında belgelenmiş
- [x] `GET /api/v1/items` → `{ "data": [...], "total": N }` döner
- [x] `GET /api/v1/items/:id` → bulunamazsa `404 { "error": "Not found" }`
- [x] `POST /api/v1/items` → `201` + oluşturulan nesne
- [x] `PUT /api/v1/items/:id` → `200` + güncellenmiş nesne
- [x] `DELETE /api/v1/items/:id` → `204 No Content`
- [x] `agents/validate.sh` kalite kapısı geçiyor

## E2-001 — Gelişmiş API özellikleri
> sprint: E2 | durum: completed | ajan: api-dev

- [x] Filtreleme desteği: GET /api/v1/items?name=foo&tags=bar
- [x] Sıralama: GET /api/v1/items?sort=name:asc,createdAt:desc
- [x] İlişkili veriler: tags için ayrı endpoint
- [x] Bulk operations: POST /api/v1/items/bulk (create/update/delete)
- [x] Export: GET /api/v1/items/export?format=json|csv
- [x] API versioning kontrolü (v1, v2 hazırlığı)
