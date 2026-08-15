**Bu klasör, başka bir projeden bağımsız olarak tek başına (ayrı proje) VS Code + Copilot ile açılır.** Cursor veya Cursor CLI gerekmez; talimatlar tamamen yerel Node script ile çalışır.

Ne yapıldı:
- `package.json`: `talimatlar-ai`, `talimatlar-watch`, `talimatlar` script’leri.
- `scripts/`:
  - `run-talimatlar-ai.js` — TALIMATLAR.md’deki `- [ ]` maddeleri uygular, `- [x]` ile işaretler (yerel; API/CLI yok).
  - `watch-talimatlar.js` — TALIMATLAR.md’yi izler, kaydedince otomatik tetikler.
  - `run-talimatlar.js` — ```bash``` bloklarını listeler; `EXEC=true` ile çalıştırır.

VS Code / Copilot’ta (bu projeyi ayrı açtığınızda):
1. Klasörü **File → Open Folder** ile **tek proje** olarak açın.
2. Node.js kurulu olsun (`node -v`).
3. Terminalde (proje kökünde):
   - **Uygula ve dosyayı güncelle:** `APPLY=true npm run talimatlar-ai`
   - **Kaydettiğinizde otomatik:** `npm run talimatlar-watch` (açık bırakın)
   - Bash blokları: `npm run talimatlar` — çalıştırmak: `EXEC=true npm run talimatlar`

**Logları canlı izlemek (iki terminal):**
- **Terminal 1:** `npm run talimatlar-watch` (veya `APPLY=true npm run talimatlar-ai`) — her çalıştırma otomatik olarak `logs/live.log` dosyasına da yazar.
- **Terminal 2:** `npm run talimatlar-logs` — `tail -f logs/live.log` ile logları canlı izle. TALIMATLAR.md kaydettiğinde veya talimatlar-ai çalıştığında bu terminalde yeni satırlar görünür.

Kurulum:

```bash
./scripts/setup.sh
```

Node kontrolü, `npm install`, watcher. Cursor veya agent kurulumu gerekmez.

Kolay kurulum (tek komut)
-------------------------

Bu depoyu yeni bir makinede hızlıca kurmak için:

```bash
git clone <repo-url> && cd talimatlar && ./scripts/setup.sh
```

`setup.sh` Node.js'in kurulu olduğunu varsayar; bağımlılıkları yükler, scriptlere izin verir ve watcher'ı arka planda başlatır.

Örnekler:

```bash
# Sadece kurulum (daemon başlatma)
./scripts/setup.sh --no-daemon

# Kurulum (daemon ile; isteğe bağlı agent kontrolü)
./scripts/setup.sh --check-agent
```
