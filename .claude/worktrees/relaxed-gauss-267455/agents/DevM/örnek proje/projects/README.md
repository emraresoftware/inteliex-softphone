# Proje çıktı klasörleri

Her **proje** için bir alt klasör; her **agent** sadece kendi `ws-1` / `ws-2` / `ws-3` klasörüne yazar. Karışıklık olmaması için bu kurala uyun.

## Örnek yapı

```
projects/
  ornek-proje-api/
    ws-1/   ← orchestrator çıktısı (spec, backlog, run state)
    ws-2/   ← model-broker çıktısı (consensus, provider)
    ws-3/   ← ide-runner çıktısı (talimatlar, loglar)
```

Detay: `DevM/docs/AGENT-PROJE-KLASORLERI.md`
