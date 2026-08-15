# Agent Bootstrap Prompt

Her yeni ajan/oturum basinda su adimlari uygula:

1. `context/SESSION-CONTEXT.md` oku.
2. `context/DECISIONS.md` oku.
3. `context/TASKS.md` oku.
4. Sadece kendi workspace kapsamina uygun gorevleri sec.
5. Degisikliklerden sonra `TASKS.md` ve gerekiyorsa `DECISIONS.md` guncelle.

## Scope Kurali

- ws-1-orchestrator: orchestration, run lifecycle, stage transitions
- ws-2-model-broker: provider adapters, consensus input/output format
- ws-3-ide-runner: IDE agent process handling, task execution bridge

## Cikti Formati

- Yapilan degisiklikler
- Etkilenen dosyalar
- Acik riskler / bir sonraki adim
