// TALIMATLAR.md içindeki ```bash ... ``` bloklarını tespit eder ve konsola yazdırır.
// Güvenlik nedeniyle komutlar varsayılan olarak çalıştırılmaz. Çalıştırmak isterseniz
// environment değişkeni EXEC=true ile script'i çalıştırın (ör: EXEC=true npm run talimatlar).

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const FILE = path.resolve(__dirname, '..', 'TALIMATLAR.md');

if (!fs.existsSync(FILE)) {
  console.error('TALIMATLAR.md bulunamadı:', FILE);
  process.exit(1);
}

const content = fs.readFileSync(FILE, 'utf8');
const codeBlocks = [];

const re = /```(?:bash)?\n([\s\S]*?)\n```/g;
let m;
while ((m = re.exec(content)) !== null) {
  codeBlocks.push(m[1].trim());
}

if (codeBlocks.length === 0) {
  console.log('TALIMATLAR.md içinde çalıştırılacak bash kodu bulunamadı.');
  process.exit(0);
}

console.log(`Bulunan ${codeBlocks.length} bash blok(lar)ı:`);
codeBlocks.forEach((blk, i) => {
  console.log('---- Blok', i+1, '----');
  console.log(blk);
});

if (process.env.EXEC === 'true') {
  console.log('\nEXEC=true; bloklardaki komutlar çalıştırılıyor (sen sorumluluk kabul ediyorsunuz).');
  codeBlocks.forEach((blk, i) => {
    console.log('\n--- Çalıştırılıyor blok', i+1, '---');
    const res = spawnSync(blk, { shell: true, stdio: 'inherit' });
    if (res.error) console.error('Hata:', res.error);
    if (res.status !== 0) console.error('Komut exit code:', res.status);
  });
} else {
  console.log('\nKomutları çalıştırmak için: EXEC=true npm run talimatlar');
}
