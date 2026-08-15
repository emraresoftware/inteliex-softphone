# D1-001 — Node startup akisini netlestir

**Ajan:** ops  
**Sprint:** D1  
**Durum:** in_progress  
**Bagimliliklar:** —

---

## Kapsam

Dergah node baslatma akisinda rol/mode secimini netlestirmek ve tek komutla tekrarlanabilir hale getirmek. `scripts/start_node.sh` ve iliskili start scriptlerinde orchestrator/worker davranisi tutarlastirilacak. Hata mesajlari acik ve operasyon odakli hale getirilecek.

## Teslim Kriterleri (Definition of Done)

- [ ] `scripts/start_node.sh` rolde tutarli sekilde calisiyor
- [ ] `orchestrator status` ve `worker status` ciktilari dogru
- [ ] Baslatma scriptlerinde syntax hatasi yok
- [ ] `agents/validate.sh` kalite kapisi geciyor
- [ ] handoff girdisi eklendi

## Zorunlu Dosyalar

| Dosya | Aciklama |
|-------|----------|
| `scripts/start_node.sh` | Ana startup yonetimi |
| `scripts/start_dervis_panel.sh` | Panel baslatma yardimcisi |
| `agents/runtime.env` | Runtime parametreleri |

## Operasyon Komutlari

```bash
scripts/start_node.sh orchestrator status
scripts/start_node.sh orchestrator panel
scripts/start_node.sh worker1 core
```

## Notlar

- Bu gorev operasyon güvenilirligi odaklidir.
- Diger ajanlarin startup dosyalarina paralel yazimi engellenmelidir.
