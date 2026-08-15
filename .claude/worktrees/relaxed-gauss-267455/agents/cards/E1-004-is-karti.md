# E1-004 — Validasyon auth ve guvenlik onlemleri

**Ajan:** guvenlik-dev  
**Sprint:** E1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

API'nin güvenlik katmanını oluştur. Input validasyonu (Joi veya Zod), API anahtarı tabanlı basit auth middleware, rate limiting ve güvenlik header'ları (helmet). XSS, injection ve aşırı yük saldırılarına karşı koruma. Hatalı input için anlaşılır hata mesajları.

## Teslim Kriterleri (Definition of Done)

- [ ] `src/middleware/auth.js` — `Authorization: Bearer <API_KEY>` header kontrolü
- [ ] `src/middleware/validate.js` — Joi şemasıyla request body/query validasyonu
- [ ] `src/middleware/rateLimit.js` — IP başına dakikada 60 istek limiti
- [ ] `helmet` middleware aktif (XSS, HSTS, Content-Type sniffing önleme)
- [ ] `src/validation/itemSchema.js` — Item create/update için Joi şemaları
- [ ] Geçersiz input → `422 Unprocessable Entity` + alan bazlı hata detayı
- [ ] Auth hatası → `401 Unauthorized` (hangi key olduğu açıklanmaz)
- [ ] Rate limit aşımı → `429 Too Many Requests` + Retry-After header
- [ ] `agents/validate.sh` kalite kapısı geçiyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `src/middleware/auth.js` | API key doğrulama |
| `src/middleware/validate.js` | Joi validasyon wrapper |
| `src/middleware/rateLimit.js` | express-rate-limit yapılandırması |
| `src/validation/itemSchema.js` | Item şemaları (create, update, query) |

## Güvenlik Kuralları

```js
// Kesinlikle yapılmayacaklar:
// ❌ API key'i loglara yazma
// ❌ Hata mesajında stack trace döndürme (production)
// ❌ SQL injection için parametre escape unutma
// ❌ res.json(err) ile ham hata gönderme

// Yapılacaklar:
// ✅ helmet() en başta
// ✅ API_KEY ortam değişkeninden, hardcode değil
// ✅ timing-safe compare (crypto.timingSafeEqual) ile key karşılaştır
// ✅ 404 ile 401'i aynı response süresiyle döndür (zamanlama saldırısı önleme)
```

## Notlar

- `express-rate-limit` kütüphanesi kullan
- `joi` validasyon şemaları `abortEarly: false` ile (tüm hataları bir anda göster)
- `.env`'de `API_KEY` ve `API_KEY_HASH` (bcrypt hash) sakla
- Production'da `X-Powered-By: Express` header'ını kaldır (helmet yapar)
