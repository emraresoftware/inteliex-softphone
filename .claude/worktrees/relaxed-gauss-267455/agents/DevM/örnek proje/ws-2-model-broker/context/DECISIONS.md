# DECISIONS — ws-2-model-broker

Bu workspace model broker ve consensus formatına odaklanır.

## Consensus I/O (taslak)
- Giriş: `prompt`, `task_ref`, `context`
- Çıkış: `plan`, `steps`, `artefacts`

## Provider adapter
- Tek sözleşme: giriş (prompt, max_tokens, model_id) → çıkış (text, usage, model)

Bu dosya TALIMATLAR.md maddeleri tamamlandıkça güncellenir.
