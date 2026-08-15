# E1-003 — Veri katmani ve model tasarimi

**Ajan:** veri-dev  
**Sprint:** E1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

Proje için hafif JSON dosya tabanlı veri saklama katmanı oluştur. Gerçek DB bağımlılığı olmadan CRUD işlemleri yapabilen bir `StorageAdapter` soyutlaması yaz. `Item` modelini tanımla: şema, validasyon, timestamp yönetimi. İleride DB geçişini kolaylaştıracak adapter pattern uygula.

## Teslim Kriterleri (Definition of Done)

- [ ] `src/models/Item.js` — Item şeması: `{ id, name, description, tags, createdAt, updatedAt, deletedAt }`
- [ ] `src/storage/fileAdapter.js` — JSON dosya okuma/yazma (atomic write ile)
- [ ] `src/storage/memoryAdapter.js` — test için in-memory adapter (aynı interface)
- [ ] `src/storage/index.js` — `NODE_ENV=test` ise memory, diğerlerinde file adapter döner
- [ ] `src/data/items.json` — başlangıç dosyası (`[]` ile)
- [ ] CRUD metodları: `findAll()`, `findById()`, `create()`, `update()`, `delete()` (soft delete)
- [ ] Tüm yazma işlemleri atomic (temp dosya → rename)
- [ ] `agents/validate.sh` kalite kapısı geçiyor

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `src/models/Item.js` | Veri modeli ve şema tanımı |
| `src/storage/fileAdapter.js` | Dosya tabanlı storage |
| `src/storage/memoryAdapter.js` | Bellek içi storage (test) |
| `src/storage/index.js` | Adapter seçici factory |
| `src/data/items.json` | Kalıcı veri dosyası |

## Interface Tanımı

```js
// Her adapter şu metodları implemente eder:
class StorageAdapter {
  async findAll(query = {})     // → Item[]
  async findById(id)            // → Item | null
  async create(data)            // → Item
  async update(id, data)        // → Item | null
  async delete(id)              // → boolean  (soft delete: deletedAt set)
}
```

## Notlar

- `fs.promises` kullan, sync okuma/yazma değil
- Atomic write: `data.json.tmp` yaz → `data.json` rename
- `findAll()` silinmiş kayıtları (`deletedAt != null`) varsayılan olarak hariç tutar
- Model timestamp'larını otomatik yönet (create → createdAt, update → updatedAt)
