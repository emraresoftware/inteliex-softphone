# TALIMATLAR — sunucu-dev

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## E1-001 — Express server kurulumu ve middleware
> sprint: E1 | durum: completed

- [x] `src/index.js` — sunucu başlatma, port dinleme, graceful shutdown
- [x] `src/app.js` — Express app factory, middleware zinciri, route mount
- [x] `src/middleware/errorHandler.js` — merkezi hata yakalayıcı (status + message)
- [x] `src/middleware/requestLogger.js` — her isteği `[METHOD] /path → status ms` formatında logla
- [x] `GET /health` endpoint'i → `{ "status": "ok", "uptime": <sn> }` döner
- [x] `npm start` ile sunucu :3000'de çalışır, `npm run dev` nodemon ile çalışır
- [x] `agents/validate.sh` kalite kapısı geçiyor

## E3-001 — Musteri arayuzu sunumu ve startup dogrulamasi
> sprint: E3 | durum: in_progress | ajan: sunucu-dev

- [x] `src/app.js` — root path musteri vitrini olarak servis edilir ve static frontend korunur
- [x] `public/index.html` — premium musteri sunumu, net CTA ve guven alani ile iyilestirilir
- [x] `public/styles.css` — mobil/desktop tutarli, cesur ve premium gorunume cekilir
- [x] `public/app.js` — bos katalog halinde demo hissi veren fallback/mesaj akisi eklenir
- [x] `npm start` ve `npm run dev` smoke sonucu `smoke_test_results.txt` icine not edilir

## E3-101 — Smoke artifact yenileme
> sprint: E3 | durum: in_progress | ajan: sunucu-dev

- [x] `smoke_test_results.txt` dosyasini gercek sonuc ile yenile: `npm start ok`, `npm run dev ok`, `GET / ok`, `GET /health ok`, `GET /metrics ok` satirlari ayri ayri yer alsin

## E4-001 — CI boru hatti saglik raporu
> sprint: E4 | durum: completed

- [x] E4-001: CI boru hatti saglik raporu
- [x] Sonucu `ci_health_report.txt` dosyasına yaz

## E5-002 — Bootstrap ve hata akislarini test dostu sertlestir
> sprint: E5 | durum: completed

- [x] `projects/emarecloud_ceyiz/src/index.js` icinde bootstrap akisini test dostu hale getir; server baslatma mantigi import sirasinda yan etki yaratmadan cagrilabilir/export edilebilir olsun ve graceful shutdown dallari testte izole edilebilsin
- [x] `projects/emarecloud_ceyiz/src/app.js` ve gerekiyorsa `src/middleware/errorHandler.js` icinde hata akislarini belirginlestir; `/health` degraded/error, 404 ve merkezi error handler davranislari testte dogrulanabilir ve deterministik olsun
- [x] `bootstrap_hardening_report.txt` dosyasina su satirlari yaz: `bootstrap test hooks hazir`, `error akis sertlestirme hazir`, `npm test -- --runInBand <ok|fail>`
## E6-001 — Storage ve observability katmanini testlenebilir hale getir
> sprint: E6 | durum: completed

- [x] E6-001: Storage ve observability katmanini testlenebilir hale getir
- [x] Sonucu `storage_observability_hardening.txt` dosyasına yaz
