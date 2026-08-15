# Örnek Proje — Talimatlar

Bu dosya **örnek proje** kökü için genel talimatlardır. Hedef: **Node + Express mini API** ile ws-1 / ws-2 / ws-3 ajanlarının birlikte çalıştığı tek referans proje.

## Kullanım

- Talimatları aşağıya madde olarak ekleyin; yapılanları `[x]` ile işaretleyin.
- `npm run talimatlar-ai` veya `npm run talimatlar` (DevM kökündeki scripts) ile çalıştırılabilir.
- Bu klasörde doğrudan çalıştırmak için: `DevM/scripts/` içindeki run-talimatlar script'ini bu dizine göre kullanın.

---

## Genel kurallar

- Tüm değişiklikler `örnek proje` altındaki tek proje yapısına uygun olsun.
- Ortak bağlam için `../context/SESSION-CONTEXT.md`, `DECISIONS.md`, `TASKS.md` kullanılsın.
- ws-1, ws-2, ws-3 kendi `TALIMATLAR.md` dosyalarındaki talimatlara göre hareket etsin; bu dosya örnek proje bütünü için rehberdir.

---

## Örnek proje hedefi (referans)

Örnek proje: **REST mini API** (Node + Express).

- [ ] Proje kökünde `package.json` oluştur (name: `ornek-proje-api`, express bağımlılığı).
- [ ] `src/index.js` ile Express sunucusu başlat (port 3000).
- [ ] `GET /health` endpoint'i ekle; `{ "status": "ok" }` dönsün.
- [ ] `README.md` güncelle: proje adı, çalıştırma komutu (`npm start`), endpoint listesi.

---

## Yapılacaklar (kopyala-yapıştır)

Aşağıdaki maddeleri ihtiyaca göre ekleyip işaretleyin:

- [ ] Örnek: `docs/API.md` oluştur ve mevcut endpoint'leri listele.
- [ ] Örnek: `.env.example` ekle (PORT=3000).

```bash
# Buraya gerekirse tek seferlik komutlar yazılabilir (npm install vb.)
```
