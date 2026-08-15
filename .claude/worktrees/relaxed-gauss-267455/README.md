# 🧙 Dergah — Emare Ekosisteminin Merkezi API

> **Proje Adı:** Dergah (Mürşid)  
> **Rolle:** API Servisi & Ekosistem Orkestrasyonu  
> **Ekosistem:** Emare (43+ proje)  
> **Başlangıç:** 28 Mart 2026

---

## 📖 Nedir?

**Dergah**, Emare ekosistemindeki tüm dervişlere (projelere) **merkezi API servisleri** sağlayan ana projedir.

### 🎯 Ana Görevleri
- ✅ Derviş otentikasyonu ve yetkilendirme (RBAC)
- ✅ Proje ve derviş bilgisi yönetimi
- ✅ Ortak veri depolaması
- ✅ Ekosistem monitörü
- ✅ Entegrasyon API'si

---

## 🏗️ Proje Yapısı

```
Dergah/
├── scripts/                 # Çalışan düğüm, panel ve orkestrasyon scriptleri
│   ├── start_node.sh
│   ├── dervis_core.py
│   ├── dervis_panel.py
│   └── legacy/              # Eski giriş betikleri (kökten taşındı)
├── data/                    # Defterler, öğrenme profili ve çalışma verileri
│   └── config/
│       └── sunucular.json
├── projects/                # Bağlı proje kısayolları/symlink alanı
├── projects_meta/           # Proje meta ve arşiv dosyaları
│   └── archives/
├── docs/                    # Operasyon ve kurulum dokümantasyonu
├── dergah/                  # Ceyiz/ham proje paketleri ve çalışma alanı
├── user_data/               # Lokal tarayıcı/profil verileri (git ignore)
├── .env.*.example           # Ortam şablonları
└── README.md
```

---

## 🚀 Hızlı Başlangıç

### 1. Kurulum
```bash
cd /Users/emre/Dergah

# Sanal ortam
python3 -m venv .venv
source .venv/bin/activate

# Bağımlılıklar
pip install -r requirements.txt
```

### 2. Yapılandırma
```bash
# Örnek .env dosyası kopyala
cp .env.m5-orchestrator.example .env.m5-orchestrator
cp .env.openclaw.example .env.openclaw
```

### 3. Çalıştırma
```bash
# Yapılandırmayı kontrol et
scripts/start_node.sh orchestrator status

# Ana paneli başlat
scripts/start_node.sh orchestrator panel

# Worker örneği
scripts/start_node.sh worker1 core
```

---

## 🔐 Güvenlik & RBAC

Dergah, Emare Anayasası'nda tanımlanmış RBAC yapısını kullanır:

```
SuperAdmin
  ↓
Admin (Derviş Yöneticileri)
  ↓
Operator (Proje Operatörleri)
  ↓
ReadOnly (Monitör)
```

Detaylı bilgi için: `DERVISHIN_CEYIZI.md`

---

## 📡 API Endpoint'leri

### Derviş Yönetimi
- `GET /dervishes` — Tüm dervişleri listele
- `POST /dervishes` — Yeni derviş ekle
- `GET /dervishes/{id}` — Derviş detayları
- `PUT /dervishes/{id}` — Derviş güncelle
- `DELETE /dervishes/{id}` — Derviş sil

### Kimlik Doğrulama
- `POST /auth/login` — Giriş yap
- `POST /auth/refresh` — Token yenile
- `POST /auth/logout` — Çıkış yap

### Sistem Sağlığı
- `GET /health` — Sistem durumu
- `GET /metrics` — Performans metrikleri

*Tam API dokümantasyonu için: `docs/API.md`*

---

## 🔗 Ekosistem Entegrasyonu

### Bağlı Derviş Projeleri
| Proje | Rol | Bağlantı |
|-------|-----|----------|
| **emaregithup** | Proje Yöneticisi | GitHub entegrasyonu |
| **EmareCloud** | Auth Servisi | Kimlik yönetimi |
| **EmareHub** | Dashboard | Merkezi ui |
| *Diğer Dervişler* | Tüketici | REST API |

### Haberleşme
Dervişler arası iletişim için GitHub Issues Messenger sistemini kullanırız:
```bash
# Mesaj gönder
python3 EMARE_ORTAK_CALISMA/emare_messenger.py dergah gonder emaregithup "Rapor: API sağlıklı"

# Herkese duyuru
python3 EMARE_ORTAK_CALISMA/emare_messenger.py dergah herkese "Bakım: 3 saat kapalı"
```

---

## 📚 Geliştirme Kuralları

### Zorunlu Okuma
1. ✅ `EMARE_ANAYASA.md` — Kodlama kuralları (18 madde)
2. ✅ `EMARE_ORTAK_HAFIZA.md` — Ekosistem standartları
3. ✅ `DERVISHIN_CEYIZI.md` — RBAC hiyerarşisi
4. ✅ `DERGAH_HAFIZA.md` — Lokkal hafıza

### Kod Standartları
- ✅ PEP 8 — Python stil rehberi
- ✅ Type hints — Her fonksiyon
- ✅ Docstrings — Her sınıf/modül
- ✅ Tests — Minimum %70 coverage
- ✅ Commit messages — Conventional commits

### Git Workflow
```bash
# Feature geliştir
git checkout -b feature/new-api-endpoint
git add .
git commit -m "feat: Yeni endpoint ekle"
git push

# Pull request aç ve birleştir
```

---

## 🧪 Test Çalıştırma

```bash
# Tüm testleri çalıştır
pytest tests/

# Coverage raporu
pytest --cov=dergah tests/

# Belirli test dosyası
pytest tests/test_auth.py -v
```

---

## 📊 Monitörleme

Dergah otomatik olarak ekosistem sağlığını kontrol eder:

```bash
# Sistem durumunu kontrol et
curl http://localhost:8000/health

# Metrikleri gör
curl http://localhost:8000/metrics
```

---

## 🐛 Hata Giderme

### Common Issues

**Problem:** Module import hatası
```bash
# Çözüm: PYTHONPATH ayarla
export PYTHONPATH="${PYTHONPATH}:/Users/emre/Dergah"
```

**Problem:** Database bağlantı hatası
```bash
# Çözüm: .env dosyasını kontrol et
cat .env.m5-orchestrator | grep DATABASE_URL
```

**Problem:** Token geçersiz
```bash
# Çözüm: Token yenile
curl -X POST http://localhost:8000/auth/refresh
```

---

## 🤝 Katkı Yapma

Dergah geliştirmesine katkıda bulunmak için:

1. **Fork & Clone**
   ```bash
   git clone https://github.com/dergah-mürşidi/dergah.git
   cd dergah
   ```

2. **Branch Oluştur**
   ```bash
   git checkout -b feature/your-feature
   ```

3. **Değişiklik Yap**
   - Kodu yazı
   - Testleri ekle
   - Dokümantasyonu güncelle

4. **Commit & Push**
   ```bash
   git commit -m "feat: Özellik açıklaması"
   git push origin feature/your-feature
   ```

5. **Pull Request Aç**

---

## 📞 İletişim

### Derviş Haberleşmesi
```bash
# emaregithup'a mesaj gönder
python3 EMARE_ORTAK_CALISMA/emare_messenger.py dergah gonder emaregithup "Soru: X endpoint nerede?"

# Tüm dervişlere duyuru
python3 EMARE_ORTAK_CALISMA/emare_messenger.py dergah herkese "Bakım penceresinde kapalı olacağım"
```

### Doğrudan İletişim
- **Derviş ID:** dergah-mürşidi
- **GitHub Issues:** github.com/dergah-mürşidi/dergah/issues

---

## 📜 Lisans

Emare Ekosistemi İç Kullanım Belgesi — Gizli

---

*Dergah — Emare'nin yüreği* ❤️  
*Son Güncelleme: 28 Mart 2026*
