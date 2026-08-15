# F1-001 — Backend streaming ve hata yonetimi

**Ajan:** eb-backend  
**Sprint:** F1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

EmareBuild backend'ine LLM streaming desteği ekle. Şu anda Ollama'dan tüm yanıt beklenip tek seferde gönderiliyor — bunun yerine token token WebSocket'e akması lazım. Ayrıca Ollama bağlantı hatası, timeout ve geçersiz JSON planı gibi durumlar için sağlam hata yönetimi ekle.

Proje dizini: `projects/emarebuild/`

## Teslim Kriterleri (Definition of Done)

- [ ] `backend/chat.py` — `plan_app` ve `generate_code` metotlarına streaming desteği ekle (Ollama `stream: true`)
- [ ] `backend/main.py` — WebSocket handler'da streaming token'ları `{"type": "token", "content": "..."}` olarak ilet
- [ ] `backend/main.py` — Ollama bağlantı hatası durumunda kullanıcıya anlamlı hata mesajı gönder
- [ ] `backend/chat.py` — LLM JSON parse hatası durumunda 2 kez yeniden dene, başarısızsa fallback plan kullan
- [ ] `backend/config.py` — `OLLAMA_URL`, `MODEL`, `PORT` gibi ayarları tek dosyada topla
- [ ] `backend/requirements.txt` — Proje bağımlılıklarını listele (fastapi, uvicorn, httpx)
- [ ] Sunucu `python -m uvicorn main:app --port 8765` ile hatasız başlıyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `backend/chat.py` | Streaming LLM entegrasyonu |
| `backend/main.py` | WebSocket streaming handler |
| `backend/config.py` | Merkezi konfigürasyon |
| `backend/requirements.txt` | Python bağımlılıkları |

## Teknik Notlar

- Ollama streaming: `POST /api/chat` ile `"stream": true` gönder, her satır bir JSON chunk
- Her chunk'ta `message.content` alanı token içerir, `done: true` bitişi bildirir
- httpx `stream()` context manager kullanılabilir
- Timeout: planlama 60s, kod üretimi 120s
