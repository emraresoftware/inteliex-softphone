# F1-002 — Frontend UX iyilestirmeleri

**Ajan:** eb-frontend  
**Sprint:** F1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

EmareBuild frontend'ine streaming token gösterimi, yazma animasyonu ve genel UX iyileştirmeleri ekle. Kullanıcı deneyimini lovable.dev seviyesine yaklaştır.

Proje dizini: `projects/emarebuild/`

## Teslim Kriterleri (Definition of Done)

- [ ] `frontend/app.js` — `type: "token"` mesajlarını yakalayıp asistan balonuna karakter karakter ekle (streaming efekti)
- [ ] `frontend/app.js` — Bağlantı hatalarında kullanıcıya uyarı göster, otomatik yeniden bağlanma sayacı ekle
- [ ] `frontend/style.css` — Asistan mesajlarına yazma animasyonu (typing indicator: üç nokta yanıp sönen efekt)
- [ ] `frontend/style.css` — Kod görüntüleyiciye basit syntax highlighting (anahtar kelimeler, stringler, yorumlar farklı renk)
- [ ] `frontend/app.js` — Dosya listesinde tıklanan dosyanın kodu Kod sekmesinde görünsün, aktif dosya vurgulansın
- [ ] `frontend/index.html` — Sayfa başlığında favicon ekle (emoji veya inline SVG)
- [ ] Tüm değişiklikler `/static/` yolundan doğru yükleniyor, konsol hatası yok

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `frontend/app.js` | WebSocket client, streaming UI, hata yönetimi |
| `frontend/style.css` | Animasyonlar, syntax renklendirme, responsive |
| `frontend/index.html` | Favicon, meta güncellemeleri |

## Teknik Notlar

- Streaming mesajlar: backend `{ "type": "token", "content": "abc" }` gönderecek
- Her token geldiğinde aktif asistan balonuna `.textContent += content` yap
- Typing indicator: `.typing-dots` div'i ile 3 nokta animasyonu, mesaj tamamlanınca kaldır
- Syntax highlight için regex tabanlı basit bir `highlightCode(text)` fonksiyonu yeterli — library gerekmez
