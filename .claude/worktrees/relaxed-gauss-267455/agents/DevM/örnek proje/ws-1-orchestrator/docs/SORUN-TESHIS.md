# ws-1-orchestrator — Sorun teşhis özeti

Bu dosya, sistemin tam randımanlı çalışmamasına yol açan nedenler ve yapılan düzeltmeleri özetler.

---

## 1. Agent prompt’unda bozuk karakterler (düzeltildi)

**Dosya:** `scripts/run-talimatlar-agent.js`

**Sorun:** `agent` komutuna verilen prompt metninde Türkçe karakterler bozulmuştu (encoding):
- "işaretsiz" → "i5faretsiz"
- "uyguladıklarını satıra [x] ile işaretle" → "uyguladklarnnu satra [x] ile ig..."

**Sonuç:** Cursor CLI’a giden talimat anlaşılmıyordu; agent doğru işi yapamıyordu.

**Düzeltme:** Prompt düz metin olarak düzgün Türkçe ile yeniden yazıldı.

---

## 2. Agent yokken simülasyon dry-run kalıyordu (düzeltildi)

**Dosya:** `scripts/run-talimatlar-agent.js`

**Sorun:** `agent` kurulu değilken fallback olarak `run-talimatlar-ai.js` çalışıyordu ama **APPLY** geçirilmiyordu. Simülasyon sadece "dry-run" modunda çalışıp TALIMATLAR.md’yi güncellemiyordu.

**Düzeltme:** Fallback çağrısında `APPLY: 'true'` env ile script çalıştırılıyor; böylece yapılan maddeler dosyada `[x]` ile işaretleniyor.

---

## 3. "Geçerli stage geçişlerini dokümante et" hep atlanıyordu (düzeltildi)

**Dosya:** `scripts/run-talimatlar-ai.js`

**Sorun:** Bu madde ne bash bloğu ne dosya oluşturma ne de mevcut ref dosya kontrolüyle eşleşiyordu. DECISIONS.md’de zaten geçiş kuralları varken bile "Skipped" kalıyordu.

**Düzeltme:** DECISIONS.md içinde geçiş kuralları (örn. `->`, `running`, `completed`/`failed`) varsa bu maddeyi "tamamlandı" sayan bir heuristic eklendi.

---

## 4. "X diye bir md dosyası yaz içine Y yaz" tanınmıyordu (düzeltildi)

**Dosya:** `scripts/run-talimatlar-ai.js`

**Sorun:** Sadece "`dosyaadi.md` dosyası oluştur içine ... yaz" kalıbı vardı. "selim diye bir md dosyası yaz içine 2384 ile 4222 çarpımının toplamını yaz" gibi ifadeler tanınmıyordu.

**Düzeltme:** "X diye bir md dosyası (yaz|oluştur) içine Y yaz" kalıbı eklendi. İçerik "N ile M çarpımının..." ise N*M hesaplanıp dosyaya yazılıyor (örn. `selim.md` → "2384 * 4222 = 10065248").

---

## 5. TALIMATLAR.md "Önce oku" yolları yanlıştı (düzeltildi)

**Dosya:** `TALIMATLAR.md`

**Sorun:** `../context/...` yazıyordu; bu workspace’te `context` klasörü **içeride** (ws-1-orchestrator/context). DevM ortak bağlamı ise `DevM/context` (yani iki üst dizin).

**Düzeltme:**
- DevM ortak: `../../context/PROMPT-BOOTSTRAP.md`, `../../context/SESSION-CONTEXT.md`
- Bu workspace: `context/DECISIONS.md`, `context/TASKS.md`

---

## 6. Watcher log’da "TALIMATLAR.md bulunamadı"

**Dosya:** `logs/watch.log`

**Açıklama:** Watcher bazen dosyayı bulamıyor diye logluyor; örneğin watcher farklı bir çalışma dizininden (veya dosya henüz yokken) başlatılmış olabilir. Şu an TALIMATLAR.md mevcut; watcher’ı **ws-1-orchestrator** kökünden başlatırsanız (`npm run talimatlar-watch`) doğru yolu kullanır.

---

## 7. Kullanım notları

- **Gerçek uygulama (dosyayı güncellemek):**  
  `APPLY=true npm run talimatlar-ai`  
  veya watcher açıkken TALIMATLAR.md’yi kaydetmek (watcher zaten APPLY=true ile tetikliyor).

- **Agent ile çalıştırma:**  
  `npm run talimatlar-agent`  
  Cursor CLI kurulu ve `agent login` yapılmış olmalı.

- **Teknik detay:**  
  `TALIMATLAR-SISTEMI.md` ve `README.md` içinde komutlar ve akış anlatılıyor.
