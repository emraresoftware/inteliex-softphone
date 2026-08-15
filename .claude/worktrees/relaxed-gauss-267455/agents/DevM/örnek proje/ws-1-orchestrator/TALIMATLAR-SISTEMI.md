# Talimatlar Sistemi - Kullanim ve Teknik Aciklama

Bu projede **TALIMATLAR.md** dosyasina yazdiginiz maddeleri VS Code Copilot Agent veya
yerel Node scripti otomatik uygular.

---

## Ne yapiyoruz?

1. **TALIMATLAR.md** - Dogal dille talimatlar yaziyorsunuz (orn. "README guncelle", "yeni dosya olustur").
2. **VS Code Copilot Agent** - Karmasik degisiklikler Copilot Agent chat ile uygulanir.
3. **Script'ler** - Yerel simulasyon: bash bloklari calistirir, `[x]` isareti koyar.
4. **Tekrar uygulama engelleme** - Tamamlanan maddeler `[x]` ile isaretlenir;
   bir sonraki calistirmada sadece isaretlenmemis maddeler uygulanir.

---

## Gereksinimler

- Node.js kurulu olmali (`node -v`)
- VS Code + GitHub Copilot (Agent modu icin)
- Cursor veya harici CLI gerekmez

---

## Nasil kullanilir?

### 1. Talimatlari yazmak

`TALIMATLAR.md` dosyasini acin. Yapilmamis maddeler `- [ ]` ile:

```
- [ ] README.md'ye kurulum adimlarini ekle
- [ ] package.json description alanini guncelle
```

### 2. Yerel simulasyon ile uygulamak

```bash
APPLY=true npm run talimatlar-ai
```

TALIMATLAR.md deki `- [ ]` satirlari bulur, bash bloklari calistirir, `- [x]` ile isareter.

### 3. VS Code Copilot Agent ile uygulamak

VS Code Copilot chat acin, Agent modunu secin:

```
TALIMATLAR.md dosyasindaki isaretlenmemis maddeleri uygula ve her birini [x] ile isaretle.
```

### 4. Kaydettiginde otomatik tetiklemek

```bash
npm run talimatlar-watch
```

### 5. Sadece bash bloklarini listele/calistir

```bash
npm run talimatlar           # listeler
EXEC=true npm run talimatlar # calistirir
```
