#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const TALIMATLAR_PATH = path.join(ROOT, 'TALIMATLAR.md');

function extractCommands(content) {
  const commands = [];
  const lines = content.split(/\r?\n/);

  for (const line of lines) {
    const t = line.trim();
    if (t.startsWith('$ ') && t.length > 2) commands.push(t.slice(2).trim());
  }

  let inBlock = false;
  let blockType = '';
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith('```')) {
      if (!inBlock) {
        inBlock = true;
        blockType = trimmed.slice(3).toLowerCase();
        if (blockType === 'bash' || blockType === 'sh' || blockType === '') blockType = 'bash';
      } else {
        inBlock = false;
      }
      continue;
    }
    if (inBlock && (blockType === 'bash' || blockType === 'sh')) {
      const cmd = line.replace(/^\s*\$\s*/, '').trim();
      if (cmd && !cmd.startsWith('#')) commands.push(cmd);
    }
  }

  return commands;
}

if (!fs.existsSync(TALIMATLAR_PATH)) {
  console.log('TALIMATLAR.md bulunamadi.');
  process.exit(0);
}

const content = fs.readFileSync(TALIMATLAR_PATH, 'utf8');
const commands = extractCommands(content);
if (commands.length === 0) {
  console.log('Calistirilacak terminal komutu bulunamadi.');
  process.exit(0);
}

for (const cmd of commands) {
  console.log('> ' + cmd);
  execSync(cmd, { cwd: ROOT, stdio: 'inherit', shell: true });
}

console.log('Komutlar tamamlandi.');
