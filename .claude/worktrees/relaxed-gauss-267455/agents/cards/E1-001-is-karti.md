# E1-001 — Express server kurulumu ve middleware

**Ajan:** sunucu-dev  
**Sprint:** E1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

Node.js + Express sunucusunu sıfırdan kur. Ana `src/index.js` ve `src/app.js` dosyalarını oluştur. JSON body parsing, CORS, hata yakalama ve request logging middleware'lerini ekle. Sunucu `PORT` env değişkeninden port almalı, `process.env.NODE_ENV` farkındalığı olmalı.

## Teslim Kriterleri (Definition of Done)

- [ ] `src/index.js` — sunucu başlatma, port dinleme, graceful shutdown
- [ ] `src/app.js` — Express app factory, middleware zinciri, route mount
- [ ] `src/middleware/errorHandler.js` — merkezi hata yakalayıcı (status + message)
- [ ] `src/middleware/requestLogger.js` — her isteği `[METHOD] /path → status ms` formatında logla
- [ ] `GET /health` endpoint'i → `{ "status": "ok", "uptime": <sn> }` döner
- [ ] `npm start` ile sunucu :3000'de çalışır, `npm run dev` nodemon ile çalışır
- [ ] `agents/validate.sh` kalite kapısı geçiyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `src/index.js` | Sunucu giriş noktası |
| `src/app.js` | Express uygulama fabrikası |
| `src/middleware/errorHandler.js` | Merkezi hata yönetimi |
| `src/middleware/requestLogger.js` | İstek loglama |
| `src/routes/health.js` | Sağlık kontrolü route'u |

## Teknik Gereksinimler

```js
// Middleware sırası (app.js)
app.use(express.json({ limit: '1mb' }));
app.use(cors());
app.use(requestLogger);
app.use('/health', healthRouter);
// ... diğer route'lar ...
app.use(errorHandler);   // en sona
```

## Notlar

- `express-async-errors` kütüphanesi ile async hata yakalamayı otomatik yap
- console.log değil, `src/logger.js` modülü kullan
- Portun 3000 olduğunu hardcode yapma, `.env`'den oku
