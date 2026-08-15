#!/usr/bin/env node
/**
 * agents/dispatch.js
 *
 * backlog.json'daki in_progress (ve bağımlılıkları karşılanmış todo) görevleri
 * ilgili ajan workspace'ine TALIMATLAR.md olarak yazar.
 *
 * Kullanım:
 *   node agents/dispatch.js              → in_progress görevleri dağıt
 *   node agents/dispatch.js --all        → todo + in_progress (bağımlılık kontrollü)
 *   node agents/dispatch.js --role ops   → sadece belirli ajan
 *   node agents/dispatch.js --dry-run    → yazmadan göster
 */

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const AGENTS_DIR = path.join(REPO_ROOT, 'agents');
const BACKLOG_PATH = path.join(AGENTS_DIR, 'backlog.json');
const AGENTS_JSON_PATH = path.join(AGENTS_DIR, 'agents.json');
const HANDOFFS_PATH = path.join(AGENTS_DIR, 'handoffs.ndjson');
const WORKSPACES_DIR = path.join(AGENTS_DIR, 'workspaces');
const CARDS_DIR = path.join(AGENTS_DIR, 'cards');

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');
const ALL = args.includes('--all');
const roleFilter = (() => {
  const idx = args.indexOf('--role');
  return idx !== -1 ? args[idx + 1] : null;
})();

// --- Yardımcı fonksiyonlar ---

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function appendHandoff(entry) {
  const line = JSON.stringify(entry) + '\n';
  if (!DRY_RUN) fs.appendFileSync(HANDOFFS_PATH, line, 'utf8');
  else console.log('[dry-run] handoff:', JSON.stringify(entry));
}

function ensureDir(p) {
  if (!DRY_RUN) fs.mkdirSync(p, { recursive: true });
}

/**
 * İş kartından DoD maddeleri (- [ ] satırları) çıkarır.
 * Kart yoksa task.title'dan basit bir madde üretir.
 */
function extractTodoItems(taskId, taskTitle) {
  const cardPath = path.join(CARDS_DIR, `${taskId}-is-karti.md`);
  if (!fs.existsSync(cardPath)) {
    return [`${taskId}: ${taskTitle}`];
  }

  const content = fs.readFileSync(cardPath, 'utf8');
  const items = [];
  for (const line of content.split(/\r?\n/)) {
    if (/^\s*-\s*\[\s*\]/.test(line)) {
      items.push(line.trim().replace(/^-\s*\[\s*\]\s*/, ''));
    }
  }
  // DoD yoksa kart başlığından bir madde yap
  if (items.length === 0) {
    items.push(`${taskId}: ${taskTitle}`);
  }
  return items;
}

/**
 * Bağımlılıkları karşılanmış mı kontrol eder.
 */
function depsResolved(task, allTasks) {
  if (!task.dependsOn || task.dependsOn.length === 0) return true;
  const doneIds = new Set(allTasks.filter(t => t.status === 'done').map(t => t.id));
  return task.dependsOn.every(dep => doneIds.has(dep));
}

/**
 * Workspace'teki mevcut TALIMATLAR.md'ye görev başlığını kontrol eder.
 * Zaten eklenmiş mi?
 */
function alreadyInTalimatlar(talimatlarPath, taskId) {
  if (!fs.existsSync(talimatlarPath)) return false;
  return fs.readFileSync(talimatlarPath, 'utf8').includes(taskId);
}

/**
 * TALIMATLAR.md'ye yeni görev bloğu ekler.
 * task.artifact varsa madde listesine explicit bir artifact maddesi eklenir;
 * bu sayede ajan_workspace_runner.py dosya tabanlı doğrulama yapabilir.
 */
function appendToTalimatlar(talimatlarPath, task, items) {
  // task.artifact field'ı varsa ve mevcut maddeler arasında yoksa ekle
  const allItems = [...items];
  if (task.artifact && !items.some(i => i.includes(task.artifact))) {
    allItems.push(`Sonucu \`${task.artifact}\` dosyasına yaz`);
  }

  const block = [
    ``,
    `## ${task.id} — ${task.title}`,
    `> sprint: ${task.sprint || '-'} | durum: ${task.status}`,
    ``,
    ...allItems.map(i => `- [ ] ${i}`),
    ``,
  ].join('\n');

  if (!fs.existsSync(talimatlarPath)) {
    const header = `# TALIMATLAR — ${task.owner}\n\nBu dosyadaki \`- [ ]\` maddeleri Copilot Agent ile uygulayın.\nUyguladıktan sonra her maddeyi \`- [x]\` ile işaretleyin.\n`;
    if (!DRY_RUN) fs.writeFileSync(talimatlarPath, header + block, 'utf8');
    else console.log(`[dry-run] yeni dosya: ${talimatlarPath}\n${header + block}`);
  } else {
    if (!DRY_RUN) fs.appendFileSync(talimatlarPath, block, 'utf8');
    else console.log(`[dry-run] eklenecek ${talimatlarPath}:\n${block}`);
  }

  return allItems.length;
}

/**
 * Workspace için .instructions.md oluşturur (yoksa).
 */
function ensureInstructions(wsDir, agentId, agentInfo, fileOwnership) {
  const instrPath = path.join(wsDir, '.instructions.md');
  if (fs.existsSync(instrPath)) return;

  const ownedFiles = fileOwnership[agentId] || [];
  const content = [
    `---`,
    `applyTo: "**"`,
    `---`,
    ``,
    `# Dergah Ajan Workspace — ${agentId}`,
    ``,
    `## Rol`,
    `${(agentInfo && agentInfo.focus) ? agentInfo.focus.join(', ') : agentId}`,
    ``,
    `## Dosya Sahipliği`,
    `Bu ajan yalnızca aşağıdaki dosyalara yazar:`,
    ``,
    ...ownedFiles.map(f => `- \`${f}\``),
    ``,
    `## TALIMATLAR.md Kuralları`,
    ``,
    `- \`- [ ]\` = yapılacak`,
    `- \`- [x]\` = tamamlandı, bir dahaki çalışmada atlanır`,
    `- Bir maddeyi tamamlayınca \`- [ ]\` → \`- [x]\` yap`,
    `- Görev ID'si ile başlayan maddeleri önce o görevin iş kartını okuyarak anla`,
    ``,
    `## Referans`,
    ``,
    `- Backlog: \`agents/backlog.json\``,
    `- İş kartları: \`agents/cards/\``,
    `- Handoff log: \`agents/handoffs.ndjson\``,
    `- Mesaj bus: \`agents/messages.ndjson\``,
    `- Inbox: \`INBOX.md\` (gelen mesajlar)`,
    `- Validate: \`agents/validate.sh\``,
    ``,
    `## Mesajlaşma`,
    ``,
    `- Mesaj gönder: \`dervis mesaj gonder --from-agent <id> --to-agent <id> --icerik "..."\``,
    `- Gelen kutusu: \`dervis mesaj kutu --agent <id>\``,
    `- Okundu işaretle: \`dervis mesaj okundu --agent <id> --id <mesaj_id>\``,
    ``,
  ].join('\n');

  if (!DRY_RUN) fs.writeFileSync(instrPath, content, 'utf8');
  else console.log(`[dry-run] .instructions.md olusturulacak: ${instrPath}`);
}

// --- Ana akış ---

function main() {
  const backlog = readJson(BACKLOG_PATH);
  const agentsConfig = readJson(AGENTS_JSON_PATH);
  const agentMap = Object.fromEntries(agentsConfig.agents.map(a => [a.id, a]));

  // Sprint seçimi: --sprint E1 ile override, yoksa activeSprint, yoksa eski format
  const sprintFlag = (() => {
    const idx = args.indexOf('--sprint');
    return idx !== -1 ? args[idx + 1] : null;
  })();

  let tasks, fileOwnership, sprintLabel;

  if (backlog.sprints) {
    // Yeni çoklu-sprint format (v2+)
    const activeSprint = sprintFlag || backlog.activeSprint || Object.keys(backlog.sprints)[0];
    const sprintData = backlog.sprints[activeSprint];
    if (!sprintData) {
      console.error(`Sprint bulunamadı: ${activeSprint}. Mevcut: ${Object.keys(backlog.sprints).join(', ')}`);
      process.exit(1);
    }
    tasks = sprintData.tasks.map(t => ({ ...t, sprint: activeSprint }));
    fileOwnership = sprintData.rules?.fileOwnership || {};
    sprintLabel = `${activeSprint} — ${sprintData.label || ''}`;
    console.log(`[sprint] ${sprintLabel}`);
  } else {
    // Eski tek-sprint format (v1 geriye dönük uyumluluk)
    tasks = backlog.tasks || [];
    fileOwnership = backlog.rules?.fileOwnership || {};
    sprintLabel = backlog.sprint || '?';
  }

  // Hangi statüler dahil?
  const allowedStatuses = ALL ? ['in_progress', 'todo'] : ['in_progress'];

  const matching = tasks.filter(t => {
    if (!allowedStatuses.includes(t.status)) return false;
    if (roleFilter && t.owner !== roleFilter) return false;
    if (t.status === 'todo' && !depsResolved(t, tasks)) return false;
    return true;
  });

  if (matching.length === 0) {
    console.log('Dağıtılacak görev yok.' + (roleFilter ? ` (--role ${roleFilter})` : ''));
    process.exit(0);
  }

  const ts = new Date().toISOString();

  for (const task of matching) {
    const agentId = task.owner;
    const wsDir = path.join(WORKSPACES_DIR, agentId);
    const talimatlarPath = path.join(wsDir, 'TALIMATLAR.md');

    ensureDir(wsDir);

    // .instructions.md yoksa oluştur (ensureDir sonrası, her zaman)
    ensureInstructions(wsDir, agentId, agentMap[agentId], fileOwnership);

    if (alreadyInTalimatlar(talimatlarPath, task.id)) {      console.log(`[skip] ${task.id} zaten ${agentId}/TALIMATLAR.md içinde`);
      continue;
    }

    const items = extractTodoItems(task.id, task.title);
    const writtenItemCount = appendToTalimatlar(talimatlarPath, task, items);

    console.log(`[dispatch] ${task.id} → agents/workspaces/${agentId}/TALIMATLAR.md (${writtenItemCount} madde)`);

    appendHandoff({
      ts,
      agent: 'dispatch',
      event: 'dispatched',
      task: task.id,
      owner: agentId,
      items: writtenItemCount,
      note: `${task.id} gorev maddeleri workspaces/${agentId}/TALIMATLAR.md dosyasina yazildi`,
    });
  }

  if (!DRY_RUN) {
    console.log('');
    console.log('Sonraki adım: Her ajan workspace\'ini ayrı VS Code penceresinde açın.');
    console.log(`  agents/workspaces/{rol}/   ← Copilot Agent burada TALIMATLAR.md'yi uygular`);
  }
}

main();
