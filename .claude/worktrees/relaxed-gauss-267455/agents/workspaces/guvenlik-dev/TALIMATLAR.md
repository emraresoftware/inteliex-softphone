# TALIMATLAR — guvenlik-dev

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## E1-004 — Validasyon auth ve guvenlik önlemleri
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

## E2-002 — Güvenlik ve performans iyileştirmeleri
> sprint: E2 | durum: completed | ajan: guvenlik-dev

- [x] API key rotation mekanizması
- [x] Rate limiting per user (DB'de track)
- [x] Input sanitization (XSS prevention)
- [x] CORS policy güncelle (production domains)
- [x] Request logging to DB
- [x] Performance monitoring (response times, error rates)
- [x] `agents/validate.sh` kalite kapısı geçiyor
