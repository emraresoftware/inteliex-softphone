# E1-005 — Unit ve integration testleri

**Ajan:** test-dev  
**Sprint:** E1  
**Durum:** todo  
**Bağımlılıklar:** E1-001, E1-002, E1-003, E1-004

---

## Kapsam

Tüm katmanlar için kapsamlı test suite oluştur. Unit testler (storage adapter, service katmanı), integration testler (HTTP endpoint'leri supertest ile), smoke test (sunucu ayağa kalktığında /health OK). Test coverage %80+ olmalı. CI için `npm test` komutu hazır.

## Teslim Kriterleri (Definition of Done)

- [ ] `tests/unit/storage.test.js` — MemoryAdapter unit testleri (CRUD hepsi)
- [ ] `tests/unit/itemsService.test.js` — service katmanı unit testleri
- [ ] `tests/integration/items.test.js` — supertest ile tüm endpoint'ler
- [ ] `tests/integration/auth.test.js` — auth middleware testleri (401, geçerli key)
- [ ] `tests/integration/rateLimit.test.js` — rate limit aşım testi
- [ ] `tests/smoke.test.js` — `/health` 200 döner, sunucu başlar
- [ ] `npm test` → tüm testler yeşil
- [ ] Coverage raporu: `npm run coverage` → %80+ branch, %80+ line
- [ ] `jest.config.js` yapılandırıldı
- [ ] `agents/validate.sh` kalite kapısı geçiyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `tests/unit/storage.test.js` | Storage adapter unit testleri |
| `tests/unit/itemsService.test.js` | Service katmanı testleri |
| `tests/integration/items.test.js` | Endpoint integration testleri |
| `tests/integration/auth.test.js` | Auth middleware testleri |
| `tests/smoke.test.js` | Smoke / sağlık testleri |
| `jest.config.js` | Jest yapılandırması |

## Test Kuralları

```js
// Her test dosyasında:
// ✅ beforeEach → temiz state (memory adapter sıfırla)
// ✅ afterAll → sunucu kapat (port leak önle)
// ✅ describe/it isimleri Türkçe olabilir ama İngilizce tercih edilir
// ✅ AAA pattern: Arrange → Act → Assert

// Integration testleri için:
// PORT=0 ile çalış (random port, çakışma yok)
// supertest(app) kullan, gerçek port bağlamadan
```

## Notlar

- `jest` + `supertest` ana bağımlılıklar
- `@jest/coverage` ile coverage üret
- Test ortamında `NODE_ENV=test` → memory adapter seçilir (E1-003)
- Mock: dış isteği (`fetch`) jest mock ile
- Testlerde gerçek API anahtarı kullanma, `.env.test` dosyası oluştur
