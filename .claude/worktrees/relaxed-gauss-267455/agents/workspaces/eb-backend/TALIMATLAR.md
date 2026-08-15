# TALIMATLAR — eb-backend

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## F1-001 — Backend streaming ve hata yonetimi
> sprint: F1 | durum: in_progress

- [x] `backend/chat.py` — `plan_app` ve `generate_code` metotlarına streaming desteği ekle (Ollama `stream: true`)
- [x] `backend/main.py` — WebSocket handler'da streaming token'ları `{"type": "token", "content": "..."}` olarak ilet
- [x] `backend/main.py` — Ollama bağlantı hatası durumunda kullanıcıya anlamlı hata mesajı gönder
- [x] `backend/chat.py` — LLM JSON parse hatası durumunda 2 kez yeniden dene, başarısızsa fallback plan kullan
- [x] `backend/config.py` — `OLLAMA_URL`, `MODEL`, `PORT` gibi ayarları tek dosyada topla
- [x] `backend/requirements.txt` — Proje bağımlılıklarını listele (fastapi, uvicorn, httpx)
- [x] Sunucu `python -m uvicorn main:app --port 8765` ile hatasız başlıyor
