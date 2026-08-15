#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const TALIMATLAR_PATH = path.join(ROOT, 'TALIMATLAR.md');

function hasUncheckedItems(content) {
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const t = line.trim();
    if (t.startsWith('- [ ]')) return true;
    if (t.startsWith('- ') && !/[x✅]/.test(t) && t.length > 4) return true;
    if (/^\d+\.\s+/.test(t) && !/\[x\]|✅|Tamamlandi/.test(t)) return true;
  }
  return false;
}

const prompt = [
  'Read TALIMATLAR.md in this project root.',
  'Only execute instructions that are NOT yet marked as done (no [x], no ✅, no "Tamamlandi" on that line).',
  'Skip any line that already has [x], ✅ or "Tamamlandi".',
  'After completing an instruction, update TALIMATLAR.md and mark it as done.',
  'Apply all changes directly. Do not ask for confirmation.'
].join(' ');

if (!fs.existsSync(TALIMATLAR_PATH)) {
  console.log('TALIMATLAR.md bulunamadi.');
  process.exit(0);
}

const content = fs.readFileSync(TALIMATLAR_PATH, 'utf8');
if (!hasUncheckedItems(content)) {
  console.log('Yeni talimat yok. AI cagrilmadi, token kullanilmadi.');
  process.exit(0);
}

const fullPrompt = [
  'TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri (- [ ] ile baslayan satirlar) uygula.',
  'Her maddeyi uyguladiktan sonra o satirda - [ ] yi - [x] ile isaretle.',
  '[x] olan satirlari atla.',
  'Degisiklikleri dogrudan dosyalara uygula, onay isteme.',
  '',
  '--- TALIMATLAR.md ICERIGI ---',
  content,
].join('\n');

// macOS: panoya kopyala
const { spawnSync } = require('child_process');
const pbcopy = spawnSync('pbcopy', [], { input: fullPrompt });
if (pbcopy.status === 0) {
  console.log('Prompt panoya kopyalandi.');
} else {
  console.log('pbcopy basarisiz — prompt asagida:');
  console.log('---');
  console.log(fullPrompt);
  console.log('---');
}

console.log('');
console.log('VS Code Copilot Agent moduna gecin ve panodakini yapistirin.');
console.log('Veya: her workspace klasorunu ayri pencerede acin, Copilot Agent\'a');
console.log('"TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula" deyin.');
process.exit(0);
