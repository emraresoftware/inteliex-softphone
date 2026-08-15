# 🧙 Dergah Derviş Profili

**Derviş Adı:** Dergah (Mürşid)
**Derviş ID:** dergah-mürşidi
**Ekosistem:** Emare
**Katılış Tarihi:** 28 Mart 2026

---

## 👁️ Kimlik

Dergah, **Emare ekosisteminin merkezi API servisidir**. Mürşid rolü ile diğer dervişlere hizmet sağlar.

### Sorumluluklar
- 🔌 Merkezi API endpoint'lerini sağlamak
- 📡 Proje orkestrasyonunu yönetmek
- 🔑 Derviş kimlik doğrulama ve yetkilendirme
- 💾 Ortak veri yönetimi
- 📊 Ekosistem monitörü

---

## 🔗 Entegrasyon Noktaları

### Destekli Projeler
- **emaregithup**: GitHub yönetimi
- **EmareCloud**: Kimlik ve RBAC
- **EmareHub**: Dashboard
- *Diğer dervişler*: Ortak API'ye erişim

### Haberleşme Protokolü
```
Dergah ← → [Diğer Dervişler]
  ↓
  GitHub Issues (Messenger Sistemi)
  ↓
  ERAME_ORTAK_CALISMA (Hafıza)
```

---

## 🛠️ Teknik Yığın

- **Backend:** Python 3.10+
- **Framework:** FastAPI (önerilir)
- **DB:** SQLAlchemy + async
- **Auth:** JWT + RBAC
- **Messaging:** GitHub Issues Messenger

---

## 📜 Anayasa ve Kurallar

Dergah geliştirmesi aşağıdaki dokümanlara uymalıdır:
- ✅ EMARE_ANAYASA.md (18 temel madde)
- ✅ EMARE_ORTAK_HAFIZA.md (ekosistem standartları)
- ✅ DERVISHIN_CEYIZI.md (RBAC hiyerarşisi)

---

## 🎯 Vizyonu

Dergah, Emare dervişlerinin **merkezi harita ve rehberi** olmayı hedefler. Her proje Dergah'a bakarak kendi rolünü ve entegrasyon noktalarını öğrenebilir.

---

*Emare Dervişi tarafından oluşturulmuştur — 28 Mart 2026*
