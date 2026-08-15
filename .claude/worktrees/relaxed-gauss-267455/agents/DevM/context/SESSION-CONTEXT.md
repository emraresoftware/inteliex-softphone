# DevM Session Context

Bu dosya, farkli VSCode/Cursor oturumlarinin ayni baglami korumasi icin merkezi hafizadir.

## Vizyon

DevM, kullanici girdisinden otomatik yazilim ureten bir platformdur:
- Coklu AI model review (API-first)
- Consensus
- Coklu IDE ajanlar (Cursor/VSCode)
- Validation + Deploy + Feedback loop

## Son Alinan Kararlar

1. Proje yeni klasore tasindi: `DevM`.
2. 3 workspace ile paralel calisilacak:
   - `ws-1-orchestrator`
   - `ws-2-model-broker`
   - `ws-3-ide-runner`
3. Mimari strateji: **API-first + Computer Use fallback**.
4. Hibrit model DB tarafinda eklendi (`execution_policies`, `browser_runs`).

## Ana Dokumanlar

- `docs/MASTER-ARCHITECTURE.md`
- `docs/DB-SCHEMA.md`
- `docs/ROADMAP-90D.md`
- `docs/TALIMATLAR-SISTEMI.md`

## Calisma Prensibi

- Her ajan once bu dosyayi ve `DECISIONS.md` dosyasini okur.
- Ajanlar yalnizca kendi workspace kapsamindaki degisiklikleri yapar.
- **Her agent, her proje icin ayri klasore yazar:** Kendi workspace’indeki `proje/` klasorune (ws-1-orchestrator/proje/, ws-2-model-broker/proje/, ws-3-ide-runner/proje/) — karisiklik olmamasi icin sadece buraya yazilir (D-005).
- Ortak kararlar `DECISIONS.md` dosyasina yazilir.
- Yapilacaklar `TASKS.md` uzerinden takip edilir.
