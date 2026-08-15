# D1-004 — Dergah kalite kapisi ve smoke

**Ajan:** quality  
**Sprint:** D1  
**Durum:** todo  
**Bagimliliklar:** D1-001, D1-002, D1-003

---

## Kapsam

Dergah icin Python odakli kalite kapisinin (syntax + script + json + smoke) stabil calistigini dogrulamak ve raporlamak. Bu gorev merge-oncesi son kapidir.

## Teslim Kriterleri (Definition of Done)

- [ ] `agents/validate.sh` hic fail vermiyor
- [ ] Kritik script syntax kontrolleri temiz
- [ ] JSON dogrulamasi temiz
- [ ] Start status smoke testi basarili
- [ ] Kapanis notu ve handoff tamam

## Zorunlu Dosyalar

| Dosya | Aciklama |
|-------|----------|
| `agents/validate.sh` | Kalite kapisi scripti |
| `agents/backlog.json` | Gorev bagimliliklari |
| `agents/handoffs.ndjson` | Devir teslim logu |

## Test/Senaryo

```bash
agents/validate.sh /Users/emre/Dergah
```

## Notlar

- Bu gorev orchestrator merge kararini dogrudan etkiler.
