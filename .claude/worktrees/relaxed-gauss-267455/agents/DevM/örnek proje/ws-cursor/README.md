# ws-cursor — Cursor IDE için talimatlar

Bu klasör **Cursor** ile ayrı proje olarak açılır. İki şekilde çalışır:

---

## 1. API'siz (yerel script) — otomatik çalışır

**Cursor API veya Cursor CLI gerekmez.** Aynı Node script’ler (ws-1/ws-2/ws-3’teki gibi) burada da çalışır:

- **Uygula ve dosyayı güncelle:** `APPLY=true npm run talimatlar-ai`
- **Kaydettiğinizde otomatik:** `npm run talimatlar-watch` (açık bırakın)

Ne yapar? TALIMATLAR.md’deki `- [ ]` maddeleri **sadece tanımlı kalıplar ve heuristic’lerle** işler (dosya oluşturma, DECISIONS.md referansı, bash blokları vb.). Doğal dildeki her türlü talimatı “anlamaz”; bu yüzden bazı maddeler “Atlandı” kalabilir.

---

## 2. Cursor Agent (API) — tam otomatik için

Doğal dildeki **tüm** talimatları gerçekten uygulatmak istiyorsan **Cursor CLI (agent)** gerekir:

1. Cursor CLI kur: https://cursor.com/install  
2. Terminalde: `agent login`  
3. Bu projede: `npm run talimatlar-agent`

Bu komut, TALIMATLAR.md’deki işaretsiz maddeleri **Cursor AI**’a gönderir; AI projede değişiklik yapar ve uyguladıklarını `[x]` ile işaretlemeni ister. **API/hesap gerekir.**

---

## Özet

| Yöntem              | API/CLI gerekir mi? | Ne kadar otomatik?                          |
|---------------------|----------------------|---------------------------------------------|
| Yerel script        | **Hayır**            | Sadece kalıp/heuristic; bazı maddeler atlanır |
| Cursor Agent        | **Evet** (agent login) | Doğal dil talimatları AI uygular            |

Cursor IDE içinde sohbetten **“TALIMATLAR.md’yi oku ve işaretsiz maddeleri uygula, yaptıklarını [x] ile işaretle”** diyerek de aynı işi yaptırabilirsin; bu da Cursor’un kendi AI’ını kullanır.

---

## Kurulum

```bash
./scripts/setup.sh
```

Node kontrolü, `npm install`, isteğe bağlı watcher. Agent kullanacaksan ayrıca `agent login` yap.
