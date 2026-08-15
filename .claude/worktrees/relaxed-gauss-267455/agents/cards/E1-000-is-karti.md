# E1-000 — Sprint koordinasyonu ve proje iskeleti

**Ajan:** yonetici  
**Sprint:** E1  
**Durum:** in_progress  
**Bağımlılıklar:** —

---

## Kapsam

Örnek Proje (Node + Express REST API) sprint E1'i koordine et. Proje klasör iskeletini oluştur, diğer 5 ajana görev dağılımını netleştir, `package.json` temelini kur. Sprint boyunca merge kararlarını ver, blokajları çöz, tüm TALIMATLAR.md'lerin güncel olmasını sağla.

## Teslim Kriterleri (Definition of Done)

- [ ] `projects/emarecloud_ceyiz/package.json` oluşturuldu (name, version, scripts, dependencies)
- [ ] `projects/emarecloud_ceyiz/README.md` yazıldı (proje amacı, kurulum, endpoint listesi)
- [ ] `projects/emarecloud_ceyiz/.env.example` oluşturuldu (PORT, NODE_ENV)
- [ ] Tüm E1-001..E1-004 görevleri `in_progress` başladı
- [ ] `agents/handoffs.ndjson`'a E1 sprint açılış kaydı eklendi
- [ ] E1-005 (test) için bağımlılık kapısı onaylandı

## Zorunlu Dosyalar

| Dosya | Açıklama |
|-------|----------|
| `projects/emarecloud_ceyiz/package.json` | Proje bağımlılıkları |
| `projects/emarecloud_ceyiz/README.md` | Proje dokümantasyonu |
| `projects/emarecloud_ceyiz/.env.example` | Ortam değişkenleri şablonu |
| `agents/backlog.json` | Sprint durumu (yalnızca yonetici günceller) |

## Koordinasyon Kuralları

- Diğer ajanların tamamladığı maddeleri `[x]` ile işaretle
- Çakışma durumunda `agents/handoffs.ndjson`'a yorum ekle
- E1-005 (test-dev) ancak E1-001..004 bittikten sonra `in_progress` yapılabilir
- Merge kararı için: syntax hata yok + testler yeşil + validate.sh geçiyor

## Notlar

- Bu ajan **kod yazmaz**, koordine eder ve karar verir
- Diğer ajanların workspace'lerine müdahale **etmez**
