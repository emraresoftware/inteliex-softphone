# TALIMATLAR — panel

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## D2-001 — FastAPI dashboard backend — sprint board, ajan durumlari, mesaj kutusu, handoff gecmisi
> sprint: D2 | durum: in_progress

### Kabul Kriterleri (DoD)
- [x] FastAPI uygulamasi `scripts/dervis_dashboard.py` olarak olusturulacak
- [x] `GET /api/sprint` — `agents/backlog.json`'dan aktif sprint ve gorevleri donecek
- [x] `GET /api/agents` — `agents/agents.json`'dan ajan listesi ve durumlarini donecek
- [x] `GET /api/messages` — `agents/messages.ndjson`'dan mesajlari donecek
- [x] `GET /api/handoffs` — `agents/handoffs.ndjson`'dan handoff gecmisini donecek
- [x] `POST /api/dispatch` — `agents/dispatch.js`'yi tetikleyecek
- [x] `POST /api/messages` — mesaj gonderecek (`scripts/dervis_mesajlasma.py` entegrasyonu)
- [x] HTML/JS frontend — Sprint kanban board, ajan kartlari, mesaj kutusu, handoff tablosu
- [x] Tek sayfa SPA, `localhost:8766` uzerinden erisim
- [x] Mevcut JSON/NDJSON dosyalarini dogrudan okuyacak, yeni DB gerektirmeyecek

### Teknik Notlar
- Proje koku: `/Users/emre/Dergah`
- `agents/backlog.json` — sprint ve gorev verileri
- `agents/agents.json` — ajan tanimlari (id, role)
- `agents/messages.ndjson` — mesaj bus (NDJSON formatinda, her satir bir JSON objesi)
- `agents/handoffs.ndjson` — handoff kayitlari (NDJSON)
- `scripts/dervis_mesajlasma.py` — `send_message()` fonksiyonu import edilebilir
- Venv: `/Users/emre/Dergah/.venv` (fastapi, uvicorn zaten kurulu olabilir, yoksa kur)
- Frontend icin ayri framework gerekmeyen inline HTML/JS yeterli (dervis_widget.py ornegine bak)
