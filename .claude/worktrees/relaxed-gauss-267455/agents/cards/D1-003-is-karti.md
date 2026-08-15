# D1-003 — Github relay saglik kontrolleri

**Ajan:** integration  
**Sprint:** D1  
**Durum:** todo  
**Bagimliliklar:** —

---

## Kapsam

GitHub relay hattinin konfigurasyon ve calisma sagligini otomatik kontrol edecek komut akislarini netlestirmek. Eksik env degiskenleri ve poll/listen hata durumlari acikca raporlanacak.

## Teslim Kriterleri (Definition of Done)

- [ ] Relay icin gerekli env alanlari kontrol ediliyor
- [ ] Listen/poll komutlarinda hata raporlama net
- [ ] Dokumanda hizli tani adimlari mevcut
- [ ] `agents/validate.sh` kalite kapisi geciyor
- [ ] handoff girdisi eklendi

## Zorunlu Dosyalar

| Dosya | Aciklama |
|-------|----------|
| `scripts/dervis_haberlesme_github.py` | Relay uygulamasi |
| `scripts/start_node.sh` | relay-listen mode cagrisi |
| `docs/MAC_NODE_KATILIMI.md` | Operasyon notlari |

## Test/Senaryo

```bash
scripts/start_node.sh orchestrator status
scripts/start_node.sh worker1 relay-listen
```

## Notlar

- Token veya repo bilgileri loglara acik yazilmamali.
