# F1-003 — Pytest entegrasyon testleri

**Ajan:** eb-test  
**Sprint:** F1  
**Durum:** todo  
**Bağımlılıklar:** F1-001, F1-002

---

## Kapsam

EmareBuild backend için pytest tabanlı test altyapısı kur. WebSocket endpoint'ini, chat engine'i ve builder modülünü test et. Ollama'yı mock'layarak CI'da çalışabilir testler yaz.

Proje dizini: `projects/emarebuild/`

## Teslim Kriterleri (Definition of Done)

- [ ] `tests/conftest.py` — FastAPI test client fixture, mock Ollama fixture, geçici workspace fixture
- [ ] `tests/test_health.py` — `/api/health` endpoint'i `{"status": "ok"}` döner
- [ ] `tests/test_chat_engine.py` — `ChatEngine.plan_app()` mock Ollama ile doğru JSON plan döner
- [ ] `tests/test_chat_engine.py` — `ChatEngine.generate_code()` mock Ollama ile dosya kodu döner
- [ ] `tests/test_builder.py` — `Builder.generate_file()` dosyayı diske yazar ve context'e ekler
- [ ] `tests/test_websocket.py` — WebSocket bağlantısı açılır, greeting mesajı alınır
- [ ] `pytest.ini` — test konfigürasyonu, `asyncio_mode = auto`
- [ ] Tüm testler `pytest` ile geçiyor, sonuç `test_report.txt` dosyasına yazılır

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `tests/conftest.py` | Ortak fixture'lar |
| `tests/test_health.py` | Health check testi |
| `tests/test_chat_engine.py` | LLM entegrasyon testleri (mock) |
| `tests/test_builder.py` | Dosya üretim testleri |
| `tests/test_websocket.py` | WebSocket akış testleri |
| `pytest.ini` | Test konfigürasyonu |
| `test_report.txt` | Test sonuç raporu (artifact) |

## Teknik Notlar

- `httpx.AsyncClient` ile FastAPI test: `from httpx import ASGITransport, AsyncClient`
- Ollama mock: `unittest.mock.patch` ile `ChatEngine._call_llm` veya `httpx.AsyncClient.post` mock'la
- WebSocket test: `from starlette.testclient import TestClient` ile `with client.websocket_connect("/ws/test-session"):`
- Builder test: `tmp_path` fixture ile geçici workspace oluştur
