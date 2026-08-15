# 🧠 Dergah — Derviş Hafıza Dosyası

> **Derviş ID:** dergah-mürşidi
> **Oluşturulma:** 28 March 2026
> **Durum:** Emare Ekosisteminde Yeni
> **Rol:** API Servisi

---

## 📋 Derviş Bilgileri

| Alan | Değer |
|------|-------|
| **Adı** | Dergah |
| **Derviş ID** | dergah-mürşidi |
| **GitHub Repo** | github.com/dergah-mürşidi/dergah |
| **Kategorisi** | API Servisi |
| **Açıklaması** | Mürşid — Merkezi API ve orkestrasyonu |
| **Teknoloji** | Python |
| **Port** | (TBD) |
| **Durum** | Development |

---

## 🏗️ Proje Yapısı

```
Dergah/
├── dergah/              # Ana modül
├── scripts/             # Otomasyon
├── projects/            # Alt projeler
├── data/                # Veri depolaması
├── docs/                # Dokümantasyon
├── user_data/           # Kullanıcı verisi
├── logs/                # Log dosyaları
├── .env.*               # Ortam yapılandırılması
└── README.md
```

---

## 🔗 Emare Ekosistemi Bağlantıları

### Bağlı Projeler
- **emaregithup**: Derviş ve proje yönetimi aracı
- **EmareCloud**: Central auth + RBAC sistemi
- **EmareHub**: Merkezi dashboard

### API Endpoint'leri
- (TBD) — Dergah API'nin dokümantasyonu

---

## 📝 Teknik Notlar

### Geliştirme

1. **Sanal Ortam:**
   ```bash
   cd /Users/emre/Dergah
   python3 -m venv .venv
   source .venv/bin/activate
   ```

2. **Bağımlılıklar:**
   ```bash
   pip install -r requirements.txt
   ```

3. **Çalıştırma:**
   ```bash
   python3 main.py
   # veya
   python3 otomatik_is.py
   ```

### Git Workflow
```bash
cd /Users/emre/Dergah
git add .
git commit -m "feat: Dergah ilk yerine getirimi"
git remote add origin https://github.com/dergah-mürşidi/dergah.git
git push -u origin master
```

---

## 🚀 Sonraki Adımlar

- [ ] GitHub hesabı oluştur: dergah-mürşidi
- [ ] GitHub reposu: dergah-mürşidi/dergah
- [ ] README.md dokümantasyonu tamamla
- [ ] API endpoint'lerini tanımla
- [ ] EmareCloud ile entegrasyon
- [ ] Webhook sistemine dahil et
- [ ] CI/CD pipeline'ını kurşun

---

## 📚 Zorunlu Okuma

Dergah geliştirme yapmadan önce mutlaka oku:

1. `/Users/emre/Desktop/26.03.2026/emaregithup/EMARE_ANAYASA.md`
2. `/Users/emre/Desktop/26.03.2026/emaregithup/EMARE_ORTAK_HAFIZA.md`
3. `/Users/emre/Desktop/26.03.2026/emaregithup/DERVISHIN_CEYIZI.md`

---

*Bu belge Emare Dervişi tarafından otomatik oluşturulmuştur.*
*Son güncelleme: 28 March 2026*
