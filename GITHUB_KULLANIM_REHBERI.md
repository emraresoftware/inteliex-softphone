# 🐙 Emare GitHub Entegrasyon ve Repo Yönetim Rehberi

Bu proje klasörü (`inteliex softphone`) ve tüm Emare ekosistemi, **otomatik GitHub Token entegrasyonu** ile yapılandırılmıştır. Tüm IDE'ler (Antigravity, Cursor, Windsurf, VS Code, Xcode, JetBrains) ve terminal ortamları hiçbir şifre gerektirmeden çalışır.

---

## 🔑 Otomatik Kimlik Doğrulama Katmanları

1. **Keychain & Credential Store**: macOS Keychain ve `~/.git-credentials` üzerinden yetkilendirme aktiftir.
2. **Ortam Değişkenleri**: `GITHUB_TOKEN` ve `GH_TOKEN` sistem genelinde (`~/.zshenv`, `~/.zshrc`) tanımlıdır.
3. **IDE Entegrasyonu**: Tüm IDE ayarları (`settings.json`) otomatik push/pull işlemleri için yapılandırılmıştır.

---

## 🚀 Hızlı Kullanım Komutları

### 1. Bu Klasörü / Projeyi Otomatik GitHub'a Push Etme
Bulunduğunuz proje klasöründe terminale yazın:
```bash
emare-repo push
```
*(Klasör adı ile `emraresoftware` veya `emarehq` altında otomatik repo açar ve push eder.)*

Farklı organizasyon veya görünürlük ile push etmek için:
```bash
emare-repo push inteliex-softphone emraresoftware public
```

### 2. Sıfırdan Yeni GitHub Reposu Oluşturma
```bash
# Public repo oluşturma:
emare-repo create <repo-adi> emraresoftware public

# Private repo oluşturma:
emare-repo create <repo-adi> emraresoftware private
```

### 3. Standart GitHub CLI (`gh`) Kullanımı
```bash
gh repo create emraresoftware/<repo-adi> --public --source=. --push
```

### 4. Repoları Listeleme
```bash
emare-repo list emraresoftware
emare-repo list emarehq
```

---

## 💻 IDE Arayüzünden (GUI) Push Etme

IDE arayüzündeki (Antigravity / Cursor / VS Code / Windsurf) **Source Control (Git)** panelinden **"Publish to GitHub"** veya **"Sync Changes / Push"** butonuna basıldığında sistem hiçbir şifre sormadan otomatik senkronizasyon yapacaktır.
