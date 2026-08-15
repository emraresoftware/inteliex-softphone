# Talimatlar Sistemi

Bu proje, TALIMATLAR.md dosyasindan otomatik calisan bir is akisi kullanir.
AI motoru: **VS Code Copilot Agent**.

## Komutlar

- `npm run talimatlar-ai`: TALIMATLAR.md'deki isaretlenmemis maddeleri yerel simulasyon ile uygular (`[x]` isareti + bash blok calistirma).
- `npm run talimatlar-agent`: Yerel simulasyonu calistirir ve Copilot Agent icin hazir prompt yazdirir.
- `npm run talimatlar-watch`: TALIMATLAR.md dosyasini izler; her kaydetmede otomatik tetikler.
- `npm run talimatlar`: TALIMATLAR.md icindeki bash bloklarini listeler/calistirir (`EXEC=true` ile).

## Isleyis

1. TALIMATLAR.md dosyasina `- [ ] gorev` formatinda talimatlar yazin.
2. `APPLY=true npm run talimatlar-ai` ile yerel simulasyon uygular ve `[x]` isareti koyar.
3. Karmasik kod degisiklikleri icin VS Code Copilot Agent modunda:
   `TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula` deyin.
4. Sonraki calistirmada `[x]` olanlar atlanir.

## Gereksinim

- Node.js
- VS Code + GitHub Copilot (Agent modu icin)
- Cursor veya harici CLI gerekmez.
