// Basit, güvenli bir implementasyon: TALIMATLAR.md içindeki unchecked maddeleri (- [ ] ...) bulur,
// her birini - [x] ile işaretler ve yapılanları konsola yazar.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const FILE = path.resolve(__dirname, '..', 'TALIMATLAR.md');
const LIVE_LOG_PATH = path.resolve(__dirname, '..', 'logs', 'live.log');

function liveLog(level, ...args) {
  try {
    fs.mkdirSync(path.dirname(LIVE_LOG_PATH), { recursive: true });
    const line = `[${new Date().toISOString()}] [${level}] ${args.map(a => typeof a === 'string' ? a : JSON.stringify(a)).join(' ')}\n`;
    fs.appendFileSync(LIVE_LOG_PATH, line, 'utf8');
  } catch (e) {}
}

const _log = console.log;
const _err = console.error;
try {
  fs.mkdirSync(path.dirname(LIVE_LOG_PATH), { recursive: true });
  fs.appendFileSync(LIVE_LOG_PATH, `[${new Date().toISOString()}] [INFO] --- run-talimatlar-ai basladi ---\n`, 'utf8');
} catch (e) {}
console.log = function (...args) { liveLog('INFO', ...args); _log.apply(console, args); };
console.error = function (...args) { liveLog('ERR', ...args); _err.apply(console, args); };

function readFile() {
  return fs.readFileSync(FILE, 'utf8');
}

function writeFile(content) {
  fs.writeFileSync(FILE, content, 'utf8');
}

function runShellCommand(cmd) {
  try {
    // Aggressive mode: run command on host shell, inherit stdio so pm2 logs show output.
    const res = spawnSync(cmd, { shell: true, stdio: 'inherit' });
    return res.status === 0;
  } catch (e) {
    console.error('runShellCommand error:', e && e.message);
    return false;
  }
}

function gitCommitAuto(message) {
  try {
    // Stage TALIMATLAR.md and other changed files
    spawnSync('git add TALIMATLAR.md', { shell: true });
    const res = spawnSync(`git commit -m "${message.replace(/"/g, '\\"')}" || true`, { shell: true, stdio: 'pipe' });
    // ignore non-zero commit (no changes) silently
    return true;
  } catch (e) {
    console.error('gitCommitAuto error:', e && e.message);
    return false;
  }
}

function writeAudit(entry) {
  try {
    const LOG = path.resolve(__dirname, '..', 'logs', 'agent-auto.log');
    fs.mkdirSync(path.dirname(LOG), { recursive: true });
    const line = `[${new Date().toISOString()}] ${entry}\n`;
    fs.appendFileSync(LOG, line, 'utf8');
  } catch (e) {
    // ignore audit failures
  }
}

function applyTalimatlar() {
  if (!fs.existsSync(FILE)) {
    console.error('TALIMATLAR.md bulunamadı:', FILE);
    process.exit(1);
  }

  const original = readFile();
  const lines = original.split(/\r?\n/);

  let changed = false;
  const report = [];

  // Pre-scan to find code blocks positions
  const codeBlocks = {};
  let inCode = false;
  let codeStart = -1;
  let codeLang = '';
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const fence = l.match(/^```(?:([a-zA-Z0-9_-]+))?\s*$/);
    if (fence) {
      if (!inCode) {
        inCode = true;
        codeStart = i;
        codeLang = fence[1] || '';
      } else {
        // close
        inCode = false;
        codeBlocks[codeStart] = {
          end: i,
          lang: codeLang,
          content: lines.slice(codeStart + 1, i).join('\n')
        };
        codeStart = -1;
        codeLang = '';
      }
    }
  }

  const newLines = lines.slice();

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const uncheckedMatch = /^\s*-\s*\[\s*\]\s*(.*)/.exec(line);
    const alreadyDone = /\[x\]|✅|Tamamlandi|Tamamlandı/.test(line);
    if (uncheckedMatch && !alreadyDone) {
      const text = uncheckedMatch[1].trim();
      report.push(text);

      // Determine action: prefer a code block immediately after this line
      let performed = false;

      // look for a code block that starts within next few lines (increase window
      // so blocks slightly further down are also associated)
      let cb = null;
      for (let j = i + 1; j <= i + 10 && j < lines.length; j++) {
        if (codeBlocks[j]) { cb = codeBlocks[j]; break; }
      }

      if (cb && cb.lang && cb.lang.toLowerCase().includes('bash')) {
        if (process.env.APPLY === 'true') {
          console.log(`Çalıştırılıyor (aggressive): satır ${i+1} ile ilişkili bash blok`);
          // aggressive: run the bash content directly and treat exit-code==0 as success
          const exitOk = runShellCommand(cb.content);
          if (!exitOk) {
            console.error('Bash blok çalıştırılırken hata oluştu (exit != 0).');
            performed = false;
          } else {
            performed = true;
          }
        } else {
          console.log('Dry-run: bash blok çalıştırılmadı (aggressive).');
          performed = false;
        }
      }

      // Eğer bash blok yoksa, basit doğal dil pattern'leri deneyelim (ör: "X.md dosyası oluştur içine Y yaz")
      if (!performed) {
        // "selim diye bir md dosyası yaz içine 2384 ile 4222 çarpımının toplamını yaz" gibi kalıplar
      const diyeMdMatch = /(\w+)\s+diye\s+bir\s+md\s+dosyası\s+(?:yaz|oluştur)\s+içine\s+(.*?)\s*yaz/i.exec(text);
      if (diyeMdMatch) {
        const fname = diyeMdMatch[1].replace(/\s+/g, '') + '.md';
        let content = diyeMdMatch[2].trim();
        const carpimMatch = /(\d+)\s*ile\s*(\d+)\s*çarpımının\s*(?:toplamını|sonucunu)?/i.exec(content);
        if (carpimMatch) {
          const a = parseInt(carpimMatch[1], 10);
          const b = parseInt(carpimMatch[2], 10);
          content = `${a} * ${b} = ${a * b}`;
        }
        const target = path.resolve(path.dirname(FILE), fname);
        console.log(`Eylem: dosya oluşturma (diye md) -> ${target}`);
        if (process.env.APPLY === 'true') {
          try {
            fs.writeFileSync(target, content + '\n', { flag: 'w' });
            performed = fs.existsSync(target) && fs.statSync(target).size >= 0;
          } catch (e) {
            console.error('Dosya oluşturulurken hata:', e.message);
            performed = false;
          }
        } else {
          performed = false;
        }
      }

      const createFileMatch = !performed && /([\w\-\.\/]+\.[a-zA-Z0-9]+)\s+dosyası oluştur(?: içine (.*) yaz)?/i.exec(text);
        if (createFileMatch) {
          const fname = createFileMatch[1];
          const content = createFileMatch[2] || '';
          const target = path.resolve(path.dirname(FILE), fname);
          console.log(`Eylem: dosya oluşturma -> ${target}`);
          if (process.env.APPLY === 'true') {
            try {
                fs.writeFileSync(target, content + (content ? '\n' : ''), { flag: 'w' });
                // doğrula: dosya gerçekten oluşturuldu mu?
                if (fs.existsSync(target)) {
                  const stats = fs.statSync(target);
                  performed = stats.isFile() && stats.size >= 0;
                } else {
                  performed = false;
                }
              } catch (e) {
                console.error('Dosya oluşturulurken hata:', e.message);
                performed = false;
              }
          } else {
            console.log('Dry-run: dosya oluşturulmadı.');
            performed = false;
          }
        }
      }

      // If still not performed, detect references to common doc files and mark
      // as performed if the referenced file already exists and is non-empty.
      if (!performed) {
  const refMatch = /(DECISIONS\.md|TASKS\.md|demo-run\.md|context\/DECISIONS\.md|context\/TASKS\.md)/i.exec(text);
        if (refMatch) {
          let ref = refMatch[1];
          // normalize paths we create in the repo
          if (/DECISIONS\.md/i.test(ref) && !/context\//i.test(ref)) ref = 'context/DECISIONS.md';
          if (/TASKS\.md/i.test(ref) && !/context\//i.test(ref)) ref = 'context/TASKS.md';
          const targetPath = path.resolve(path.dirname(FILE), ref);
          try {
            if (fs.existsSync(targetPath) && fs.statSync(targetPath).size > 0) {
              console.log('Referans dosya bulundu ve dolu; görev otomatik olarak tamamlandı:', ref);
              performed = true;
            } else {
              console.log('Referans dosya bulunamadı veya boş:', targetPath);
            }
          } catch (e) {
            console.error('Referans dosya kontrolü sırasında hata:', e.message);
          }
        }
      }

      // Heuristic checks for abstract tasks: if DECISIONS.md contains the
      // required enum/stage/retry text, mark as done.
      if (!performed) {
        const decisionsPath = path.resolve(path.dirname(FILE), 'context/DECISIONS.md');
        try {
          if (fs.existsSync(decisionsPath)) {
            const dtxt = fs.readFileSync(decisionsPath, 'utf8');
            const lower = text.toLowerCase();

            // Run enum detection
            if (/run durumlari|enum/i.test(text) || /\bcreated\b/i.test(text)) {
              if (/\bcreated\b/i.test(dtxt) && /\brunning\b/i.test(dtxt) && /\bcompleted\b/i.test(dtxt)) {
                console.log('DECISIONS.md içinde enum satırları bulundu; görev tamamlandı.');
                performed = true;
              }
            }

            // Stage list detection
            if (!performed && /stage listesini sabitle|spec.*consensus.*ide_run.*validation.*deploy/i.test(text)) {
              if (/spec\s*→\s*consensus/i.test(dtxt) || /spec\s*->\s*consensus/i.test(dtxt)) {
                console.log('DECISIONS.md içinde stage listesi bulundu; görev tamamlandı.');
                performed = true;
              }
            }

            // Geçerli stage geçişlerini dokümante et: DECISIONS'da geçiş kuralları varsa tamamlandı say
            if (!performed && /stage\s*geçiş.*dokümante|geçerli\s*stage\s*geçiş/i.test(text)) {
              if (/\-\>\s*/.test(dtxt) && /\brunning\b/i.test(dtxt) && (/\bcompleted\b/i.test(dtxt) || /\bfailed\b/i.test(dtxt))) {
                console.log('DECISIONS.md içinde stage geçiş kuralları bulundu; görev tamamlandı.');
                performed = true;
              }
            }

            // Per-stage criteria detection
            if (!performed && /tamamlanma kriteri/i.test(text)) {
              if (/tamamlanma kriterleri/i.test(dtxt) || /project_spec\.md/i.test(dtxt)) {
                console.log('DECISIONS.md içinde tamamlanma kriterleri bulundu; görev tamamlandı.');
                performed = true;
              }
            }

            // Retry/backoff detection
            if (!performed && /retry|backoff|deneme sayısı|backoff stratejisi/i.test(text)) {
              if (/Maksimum deneme sayısı/i.test(dtxt) || /Backoff strategy/i.test(dtxt) || /exponential backoff/i.test(dtxt) || /max(imum)? retry/i.test(dtxt)) {
                console.log('DECISIONS.md içinde retry/backoff politikası bulundu; görev tamamlandı.');
                performed = true;
              }
            }
          }
        } catch (e) {
          console.error('DECISIONS.md kontrolü sırasında hata:', e.message);
        }
      }

      // If performed (success) then mark line as done
      if (performed) {
        newLines[i] = newLines[i].replace(/\[\s*\]/, '[x]');
        changed = true;
        console.log(`Başarılı: '${text}' işaretlendi.`);
        writeAudit(`Performed: ${text}`);
      } else {
        console.log(`Atlandı / başarısız: '${text}' — işaretlenmedi.`);
        writeAudit(`Skipped: ${text}`);
      }
    }
  }

  if (!report.length) {
    console.log('İşlenecek yeni talimat bulunamadı.');
    return;
  }

  console.log('Bulunan maddeler (rapor):');
  report.forEach((r, idx) => console.log(`${idx+1}. ${r}`));

  if (process.env.APPLY === 'true' && changed) {
    writeFile(newLines.join('\n'));
    console.log('\nTALIMATLAR.md güncellendi — başarılı eylemler işaretlendi.');
  } else if (process.env.APPLY === 'true' && !changed) {
    console.log('\nAPPLY=true verildi ama hiçbir eylem başarılı olmadı; dosya değiştirilmedi.');
  } else {
    console.log('\nDry-run modunda çalıştı. Gerçek uygulamak için: APPLY=true npm run talimatlar-ai');
  }
}

applyTalimatlar();
