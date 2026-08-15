# DevM

DevM, coklu AI + coklu IDE ajanlari ile otomatik yazilim gelistirme platformu prototipidir.
AI motoru: **VS Code Copilot Agent**.

## Baslangic

- Mimari: `docs/MASTER-ARCHITECTURE.md`
- Veri modeli: `docs/DB-SCHEMA.md`
- Yol haritasi: `docs/ROADMAP-90D.md`
- Talimat sistemi: `docs/TALIMATLAR-SISTEMI.md`

## Talimat Sistemi

```bash
APPLY=true npm run talimatlar-ai   # yerel simulasyon
npm run talimatlar-agent           # simulasyon + Copilot yonlendirmesi
npm run talimatlar-watch           # izleyici (otomatik tetikler)
npm run talimatlar                 # bash bloklarini listele
```

VS Code Copilot Agent ile:
1. Copilot chat acin, Agent modunu secin
2. "TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula" yazin

## Not

Bu repo su an iskelet asamasindadir. Ilk hedef, orchestrator + model broker + tek IDE agent ile MVP cikarimidir.
Cursor veya harici CLI gerekmez — sadece VS Code + Copilot.
