# ws-1-orchestrator — Talimatlar

Bu workspace **orchestrator** katmanına odaklanır: run state machine, stage geçişleri, retry/backoff, human approval gate.

## Önce oku

- `../../context/PROMPT-BOOTSTRAP.md` (DevM ortak)
- `../../context/SESSION-CONTEXT.md` (DevM ortak)
- `context/DECISIONS.md` (bu workspace)
- `context/TASKS.md` (bu workspace)

## Sorumluluk alanı

- Run lifecycle (created → running → completed / failed)
- Stage geçişleri (spec → consensus → ide_run → validation → deploy)
- Retry/backoff politikası
- Human approval kapıları (kritik adımlarda)

---

## Talimatlar (kopyala-yapıştır)

Yapılan maddeleri `[x]` ile işaretleyin. `npm run talimatlar-ai` veya `npm run talimatlar` ile çalıştırılabilir.

### Run state machine

- [x] Run durumları için bir enum veya sabit listesi tanımla: `created`, `running`, `completed`, `failed`, `blocked`.
- [x] Geçerli stage geçişlerini dokümante et: hangi durumdan hangi duruma geçilebilir (örn. `running` → `completed` veya `failed`).
- [x] `../context/DECISIONS.md` içine "Run state machine kararları" bölümü ekle ve seçilen geçiş kurallarını yaz.

### Stage geçişleri

- [x] Stage listesini sabitle: `spec` → `consensus` → `ide_run` → `validation` → `deploy`.
- [x] Her stage için "tamamlanma kriteri" tek cümleyle yaz (örn. spec: "project_spec.md ve task_backlog.json üretildi").
- [x] Bir stage tamamlanmadan sonrakine geçilmemesi kuralını DECISIONS.md'ye ekle.

### Retry / backoff
- [x] selim diye bir md dosyası yaz içine 2384 ile 4222 çarpımının toplamını yaz.
- [x] API çağrısı başarısız olduğunda maksimum deneme sayısını belirle (örn. 3).
- [x] Backoff stratejisini yaz: sabit bekleme mi, üstel artan mı (örn. 1s, 2s, 4s).
- [x] Bu politikayı DECISIONS.md veya docs içinde "Retry/backoff" başlığıyla kaydet.

### Human approval gate

- [x] Hangi adımlarda insan onayı zorunlu olsun listele (örn. deploy, prod merge).
- [x] "Human approval gate" kurallarını DECISIONS.md'ye ekle.

### Örnek proje ile uyum

- [x] Örnek proje (Node + Express mini API) için tek bir "demo run" senaryosu tasarla: spec → consensus → ide_run → validation (deploy opsiyonel). Bunu TASKS.md veya ayrı bir `demo-run.md` dosyasında özetle.j

### Test: proje/ klasörüne çok basit bir proje yazdır

- [x] proje/index.html dosyası oluştur içine <!DOCTYPE html><html><head><meta charset="utf-8"><title>Ws-1 Test</title></head><body><h1>Merhaba</h1><p>ws-1-orchestrator test projesi.</p></body></html> yaz.
- [x] proje/test-README.md dosyası oluştur içine # Test Projesi ws-1 deneme. Bu proje ws-1 talimatlar testi ile olusturuldu. yaz.

**Test sonucu:** Script (APPLY=true npm run talimatlar-ai) bu iki maddeyi işlediğinde aşağıdaki bash bloğunu çalıştırır ve `proje/index.html` ile `proje/test-README.md` oluşturulur. Tarayıcıda `proje/index.html` açarak "Merhaba" sayfasını görebilirsin.

**VS Code’da tekrar test:** İki satırı `[ ]` yap, kaydet, terminalde `APPLY=true npm run talimatlar-ai` çalıştır — script bash bloğunu çalıştırıp dosyaları yazar ve maddeleri `[x]` yapar.

```bash
mkdir -p proje && echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Ws-1 Test</title></head><body><h1>Merhaba</h1><p>ws-1 test.</p></body></html>' > proje/index.html && echo '# Test Projesi — ws-1 deneme' > proje/test-README.md
```

### Karmaşık test: proje/ altında mini web projesi + spec + backlog

Tek maddede: proje/ içinde **project_spec.md**, **task_backlog.json**, **index.html** (style.css ve app.js bağlı), **style.css**, **app.js**, **README.md** oluşturulsun. Script aşağıdaki bash bloğunu çalıştırarak hepsini yazacak.

- [x] proje/ altında mini web projesi oluştur: project_spec.md, task_backlog.json, index.html (css ve js bağlı), style.css, app.js, README.md. Tüm dosyalar aşağıdaki bash bloğu ile yazılacak.

```bash
mkdir -p proje
printf '%s\n' '# Proje Spesifikasyonu — Mini Web' 'Hedef: Tek sayfa, CSS ve JS ile. Butona tıklanınca sayaç artacak.' > proje/project_spec.md
echo '{"proje":"mini-web","gorevler":[{"id":"1","baslik":"HTML"},{"id":"2","baslik":"CSS"},{"id":"3","baslik":"JS sayaç"}]}' > proje/task_backlog.json
echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Mini Web</title><link rel="stylesheet" href="style.css"></head><body><h1>Karmaşık Test</h1><p>Sayaç: <span id="sayac">0</span></p><button id="artir">Artır</button><script src="app.js"></script></body></html>' > proje/index.html
echo 'body{font-family:sans-serif;margin:2rem;} h1{color:#333;} button{padding:0.5rem 1rem;cursor:pointer;}' > proje/style.css
echo 'var sayac=0; document.getElementById("artir").onclick=function(){ sayac++; document.getElementById("sayac").textContent=sayac; };' > proje/app.js
printf '%s\n' '# Mini Web Projesi' 'Ws-1 karmaşık test. index.html aç, butona tıkla, sayaç artsın.' > proje/README.md
```

### Ağır test: proje/api/ altında mini Express API + npm install

Tek maddede: **proje/api/** klasörü oluştur, package.json (express), server.js (3 endpoint), README, .gitignore yaz, ardından **npm install** çalıştır. İşlem birkaç saniye sürebilir.

- [x] proje/api/ altında mini Express API oluştur: package.json, server.js (GET / GET /health GET /api/time), README.md, .gitignore; sonra proje/api/ içinde npm install çalıştır. Tümü aşağıdaki bash bloğu ile.

```bash
mkdir -p proje/api
echo '{"name":"mini-api","version":"0.1.0","main":"server.js","scripts":{"start":"node server.js"},"dependencies":{"express":"^4.18.0"}}' > proje/api/package.json
printf '%s\n' 'const express=require("express");const app=express();' 'app.get("/",(req,res)=>res.send("Merhaba — ağır test API"));' 'app.get("/health",(req,res)=>res.json({ok:true,ts:Date.now()}));' 'app.get("/api/time",(req,res)=>res.json({time:new Date().toISOString()}));' 'app.listen(3000,()=>console.log("http://localhost:3000"));' > proje/api/server.js
printf '%s\n' '# Mini API — Ağır test' 'Express, 3 endpoint. Çalıştır: cd proje/api && npm install && npm start' > proje/api/README.md
echo 'node_modules/' > proje/api/.gitignore
cd proje/api && npm install --no-audit --no-fund
```
# edit 1772054523
# trigger 1772054831
