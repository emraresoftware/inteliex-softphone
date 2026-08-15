// VS Code Copilot Agent ile calisir.
// run-talimatlar-ai.js (yerel simulasyon) calistirilir;
// Copilot Agent modu TALIMATLAR.md icerigini uygular.

const { spawnSync } = require('child_process');
const path = require('path');

console.log('Yerel simulasyon calistiriliyor...');
console.log('VS Code Copilot Agent modunda calistirmak icin:');
console.log('  Copilot Agent chat: "TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula"');
console.log('');

const env = Object.assign({}, process.env, { APPLY: 'true' });
const res = spawnSync(process.execPath, [path.resolve(__dirname, 'run-talimatlar-ai.js')], {
  stdio: 'inherit',
  env,
});
process.exit(res.status);
