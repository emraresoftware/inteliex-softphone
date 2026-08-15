**Bu klasör, başka bir projeden bağımsız olarak tek başına (ayrı proje) VS Code + Copilot ile açılır.** Cursor veya Cursor CLI gerekmez; talimatlar tamamen yerel Node script ile çalışır.

**ws-2-model-broker:** Provider adapter, consensus formatı, API-first routing.

Ne yapıldı:
- `package.json`: `talimatlar-ai`, `talimatlar-watch`, `talimatlar` script’leri.
- `scripts/`: run-talimatlar-ai.js, watch-talimatlar.js, run-talimatlar.js, setup.sh, daemon script’leri.

VS Code / Copilot’ta (bu projeyi ayrı açtığınızda):
1. Klasörü **File → Open Folder** ile **tek proje** olarak açın.
2. Node.js kurulu olsun (`node -v`).
3. Terminalde (proje kökünde):
   - **Uygula ve dosyayı güncelle:** `APPLY=true npm run talimatlar-ai`
   - **Kaydettiğinizde otomatik:** `npm run talimatlar-watch` (açık bırakın)
   - Bash blokları: `npm run talimatlar` — çalıştırmak: `EXEC=true npm run talimatlar`

Kurulum:

```bash
./scripts/setup.sh
```

Node kontrolü, `npm install`, watcher. Cursor veya agent kurulumu gerekmez.
