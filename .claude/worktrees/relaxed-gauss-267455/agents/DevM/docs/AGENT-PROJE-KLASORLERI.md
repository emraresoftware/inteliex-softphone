# Her agent, her proje için ayrı klasör

Projeyi karıştırmamak için **her agent yalnızca kendi workspace’indeki `proje/` klasörüne yazar.**

## Kural

- **Proje** = bir yazılım üretim run’ı (örn. “Node Express mini API”).
- **Agent** = ws-1-orchestrator, ws-2-model-broker, ws-3-ide-runner.
- **Çıktı yeri:** Her agent’ın **kendi workspace’i içinde** `proje/` klasörü. Agent sadece buraya yazar.

## Klasör yapısı (geçerli)

```
örnek proje/
  ws-1-orchestrator/
    proje/          ← sadece orchestrator buraya yazar (spec, backlog, run state)
  ws-2-model-broker/
    proje/          ← sadece model-broker buraya yazar (consensus, provider)
  ws-3-ide-runner/
    proje/          ← sadece ide-runner buraya yazar (talimatlar, loglar)
```

- **ws-1**: Spec, task backlog, run state, stage geçişleri → `ws-1-orchestrator/proje/`
- **ws-2**: Consensus giriş/çıkış, provider cevapları → `ws-2-model-broker/proje/`
- **ws-3**: IDE talimatları, loglar, sonuç dosyaları → `ws-3-ide-runner/proje/`

Birden fazla proje varsa: `proje/<proje-id>/` (örn. `proje/ornek-proje-api/`) kullanılabilir.

## Neden?

- Bir agent diğerinin dosyasını ezmez.
- Her workspace kendi çıktısını kendi içinde tutar; karışıklık olmaz.
- Hangi klasörün hangi ajana ait olduğu net.

## Uygulama

- TALIMATLAR.md veya script’lerde çıktı yolu: **workspace köküne göre `proje/`** (veya `proje/<proje-id>/`).
- Her workspace’te `proje/` klasörü vardır; agent sadece oraya yazar.

Referans: **DECISIONS.md — D-005**.
