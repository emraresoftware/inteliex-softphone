// Daha sağlam bir izleyici: chokidar kullanır. Dosya kaydı, yeniden adlandırma veya taşınma
// gibi durumlarda daha güvenilir olaylar sağlar.

const path = require('path');
const { spawn } = require('child_process');
const chokidar = require('chokidar');

const FILE = path.resolve(__dirname, '..', 'TALIMATLAR.md');
let timeout = null;

const startWatcher = () => {
  const WATCH_DIR = path.dirname(FILE);
  const basename = path.basename(FILE);

  // Watch the directory instead of the single file. Many editors save via
  // atomic rename (write to temp + rename) which can miss events when
  // watching a single file path. Filtering by basename ensures we only react
  // to changes to TALIMATLAR.md.
  const watcher = chokidar.watch(WATCH_DIR, {
    persistent: true,
    ignoreInitial: false,
    depth: 0,
    awaitWriteFinish: {
      stabilityThreshold: 1200,
      pollInterval: 100
    }
  });

  console.log('TALIMATLAR.md izleniyor (chokidar). Kaydetme sonrası talimatlar çalıştırılacak. Durmak için Ctrl+C');

  const trigger = () => {
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(() => {
  console.log('Değişiklik algılandı — talimatlar çalıştırılıyor (APPLY=true)...');
  const env = Object.assign({}, process.env, { APPLY: 'true' });
  const p = spawn(process.execPath, [path.resolve(__dirname, 'run-talimatlar-ai.js')], { stdio: 'inherit', env });
      p.on('close', (code) => {
        if (code !== 0) console.error('run-talimatlar-ai.js exit code:', code);
      });
    }, 500);
  };

  watcher.on('add', (p) => { if (path.basename(p) === basename) trigger(); });
  watcher.on('change', (p) => { if (path.basename(p) === basename) trigger(); });
  watcher.on('unlink', (p) => { if (path.basename(p) === basename) trigger(); });
};

const fs = require('fs');
if (!fs.existsSync(FILE)) {
  console.warn('TALIMATLAR.md bulunamadı; dizini izleyeceğim. Dosya eklendiğinde tetiklenecek:', FILE);
}

startWatcher();
