# ws-3-ide-runner — Talimatlar

Bu workspace **IDE ajan çalıştırma** katmanına odaklanır: Cursor/VSCode process orchestration, task-to-agent execution bridge, result/log collection, branch/task isolation.

## Önce oku

- `../../context/PROMPT-BOOTSTRAP.md` (DevM ortak)
- `../../context/SESSION-CONTEXT.md` (DevM ortak)
- `context/DECISIONS.md` (bu workspace)
- `context/TASKS.md` (bu workspace)

## Sorumluluk alanı

- Cursor/VSCode process orchestration
- Task → ajan execution bridge (consensus çıktısını IDE'ye taşıma)
- Result ve log toplama
- Branch/task isolation stratejisi

---

## Talimatlar (kopyala-yapıştır)

Yapılan maddeleri `[x]` ile işaretleyin. `npm run talimatlar-ai` veya `npm run talimatlar` ile çalıştırılabilir.

### Process orchestration

- [ ] IDE ajanının "bir görev için" nasıl tetikleneceğini tek cümleyle yaz (örn. Cursor CLI ile belirli bir prompt + workspace path).
- [ ] Aynı anda kaç IDE ajanının paralel çalışabileceğine dair kuralı belirle (örn. 1 veya N) ve DECISIONS.md'ye ekle.

### Task–agent bridge

- [ ] Consensus çıktısındaki "steps" veya "artefacts" alanının IDE'ye nasıl iletileceğini tanımla (örn. tek bir markdown talimat dosyası + workspace yolu).
- [ ] Bu bridge formatını dokümante et (örn. `task-bridge-format.md` veya DECISIONS.md).

### Result / log toplama

- [ ] Ajan tamamlandığında hangi çıktıların toplanacağını listele: stdout, stderr, oluşturulan/değişen dosya listesi, exit code.
- [ ] Toplanan çıktıların nereye yazılacağını belirle (örn. run klasörü, `logs/run-<id>.json`).

### Branch / task isolation

- [ ] Her run veya task için ayrı branch kullanılacak mı, tek branch mi karar ver; DECISIONS.md'ye yaz.
- [ ] "Task isolation" stratejisini özetle: aynı repo içinde farklı klasör mü, farklı branch mi?

### Örnek proje ile uyum

- [ ] Örnek proje (Node + Express mini API) için tek bir "IDE görevi" örneği yaz: "GET /health endpoint'ini ekle" talimatı + beklenen çıktı (hangi dosyaların değişeceği). Bunu dokümana örnek olarak ekle.

```bash
# Gerekirse bu workspace'e özel komutlar (örn. Cursor CLI test)
```
