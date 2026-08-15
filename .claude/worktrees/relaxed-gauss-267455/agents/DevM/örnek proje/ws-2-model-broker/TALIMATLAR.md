# ws-2-model-broker — Talimatlar

Bu workspace **model broker** ve **consensus** giriş/çıkış formatına odaklanır: provider adapter sözleşmeleri, API-first routing, consensus input normalization.

## Önce oku

- `../../context/PROMPT-BOOTSTRAP.md` (DevM ortak)
- `../../context/SESSION-CONTEXT.md` (DevM ortak)
- `context/DECISIONS.md` (bu workspace)
- `context/TASKS.md` (bu workspace)

## Sorumluluk alanı

- Provider adapter sözleşmeleri (OpenAI, Gemini, vb.)
- API-first model routing
- Fallback policy entegrasyonu
- Consensus input/output formatı (normalizasyon)

---

## Talimatlar (kopyala-yapıştır)

Yapılan maddeleri `[x]` ile işaretleyin. `npm run talimatlar-ai` veya `npm run talimatlar` ile çalıştırılabilir.

### Provider adapter

- [ ] Tek bir provider için (örn. OpenAI veya Gemini) "adapter sözleşmesi" tanımla: giriş (prompt, max_tokens, model_id) ve çıkış (text, usage, model) alanları.
- [ ] İkinci bir provider için aynı sözleşmeye uyan örnek çıkış formatı yaz (consensus katmanının tek format beklemesi için).
- [ ] Bu sözleşmeyi `docs/` veya bu workspace içinde `provider-contract.md` (veya benzeri) olarak kaydet.

### Consensus format

- [ ] Consensus katmanının beklediği tek giriş formatını yaz: örn. `{ "prompt": "...", "task_ref": "...", "context": { ... } }`.
- [ ] Consensus çıkış formatını yaz: örn. `{ "plan": "...", "steps": [...], "artefacts": [...] }` — IDE ajanlarının kullanacağı yapı.
- [x] Bu formatları DECISIONS.md'de "Consensus I/O" bölümünde veya ayrı `consensus-format.md` dosyasında dokümante et.

### API-first routing

- [ ] "Hangi görev hangi modele gider?" kuralını tek cümleyle yaz (örn. tüm spec/plan görevleri önce Gemini, timeout olursa OpenAI).
- [x] Routing kuralını DECISIONS.md'ye ekle.

### Örnek proje ile uyum

- [x] Örnek proje (Node + Express mini API) için örnek bir consensus girişi ve çıkışı yaz: tek endpoint (GET /health) ekleme senaryosu. Bunu dokümana örnek olarak ekle.

### Test: proje/ klasörüne ws-2 çıktıları yazdır

- [x] proje/ altında model-broker test çıktıları oluştur: consensus-input.json, consensus-output.json, provider-contract.md. Tümü aşağıdaki bash bloğu ile.

```bash
mkdir -p proje
echo '{"prompt":"GET /health ekle","task_ref":"task-1","context":{"proje":"mini-api"}}' > proje/consensus-input.json
echo '{"plan":"Health endpoint ekle","steps":[{"id":"1","desc":"server.js get /health"}],"artefacts":["server.js"]}' > proje/consensus-output.json
printf '%s\n' '# Provider adapter sözleşmesi (ws-2 test)' 'Giriş: prompt, max_tokens, model_id' 'Çıkış: text, usage, model' '' 'Bu dosya ws-2 talimatlar testi ile oluşturuldu.' > proje/provider-contract.md
```
