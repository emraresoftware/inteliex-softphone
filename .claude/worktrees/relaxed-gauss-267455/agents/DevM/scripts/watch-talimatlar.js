#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TALIMATLAR_PATH = path.join(ROOT, 'TALIMATLAR.md');
const RUN_AI_SCRIPT = path.join(__dirname, 'run-talimatlar-ai.js');
const DEBOUNCE_MS = 5000;

let timer = null;

function runAI() {
  timer = null;
  console.log('[watch] TALIMATLAR.md degisti, AI calistiriliyor...');
  const child = spawn('node', [RUN_AI_SCRIPT], {
    cwd: ROOT,
    stdio: 'inherit',
    shell: false,
  });
  child.on('close', () => {
    console.log('[watch] Izleme devam ediyor.');
  });
}

if (!fs.existsSync(TALIMATLAR_PATH)) {
  console.log('TALIMATLAR.md bulunamadi.');
  process.exit(1);
}

console.log('TALIMATLAR.md izleniyor (debounce: ' + (DEBOUNCE_MS / 1000) + ' sn). Ctrl+C ile durdur.');

fs.watch(TALIMATLAR_PATH, (eventType) => {
  if (eventType !== 'change') return;
  if (timer) clearTimeout(timer);
  timer = setTimeout(runAI, DEBOUNCE_MS);
});
