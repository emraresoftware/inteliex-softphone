# TALIMATLAR — veri-dev

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## E1-003 — Veri katmani ve model tasarimi
> sprint: E1 | durum: completed | ajan: veri-dev

- [x] `src/models/Item.js` — Item şeması: `{ id, name, description, tags, createdAt, updatedAt, deletedAt }`
- [x] `src/storage/fileAdapter.js` — JSON dosya okuma/yazma (atomic write ile)
- [x] `src/storage/memoryAdapter.js` — test için in-memory adapter (aynı interface)
- [x] `src/storage/index.js` — `NODE_ENV=test` ise memory, diğerlerinde file adapter döner
- [x] `src/data/items.json` — başlangıç dosyası (`[]` ile)
- [x] CRUD metodları: `findAll()`, `findById()`, `create()`, `update()`, `delete()` (soft delete)
- [x] Tüm yazma işlemleri atomic (temp dosya → rename)
- [x] `agents/validate.sh` kalite kapısı geçiyor
- [x] Test görevi: Daemon çalışıyor mu kontrol et
