# Master Architecture — Otomatik Yazilim Uretim Platformu

Bu belge, platformun hedef mimarisini (coklu AI + coklu IDE + otomatik deploy) ust seviyede tanimlar.

## 1) Hedef Akis

1. Kullanici sohbet ekraninda proje fikrini girer.
2. Sistem girdiyi `project_spec.md` ve `task_backlog.json` olarak yapilandirir.
3. Coklu model (Gemini/OpenAI/...) paralel degerlendirme yapar.
4. Consensus katmani tek bir uygulanabilir taslak uretir.
5. Kullanici "yazalim" onayi verir.
6. IDE ajanlari (Cursor/VSCode) paralel kod uretir.
7. CI dogrulamasi (lint/test/build/security) calisir.
8. Deploy edilir ve canli URL uretilir.
9. Musteri geri bildirimi yeni run olarak sisteme geri doner.

## 2) Servisler

- `frontend-web`
- `api-gateway`
- `orchestrator-service`
- `spec-service`
- `model-broker-service`
- `consensus-service`
- `ide-agent-runner`
- `repo-service`
- `ci-validation-service`
- `deploy-service`
- `feedback-loop-service`
- `event-bus + queue`
- `observability-stack`

## 3) Tasarim Ilkeleri

- API-first
- Human-in-the-loop
- Deterministik run
- Cost-aware orchestration
- Security-by-default

## 4) Hibrit Model Stratejisi (API + Computer Use)

DevM iki kanal kullanir:

1. **Primary kanal: Model API**
   - OpenAI/Gemini gibi resmi API'ler
   - Hizli, stabil, daha ucuz ve olceklenebilir
   - Varsayilan tum run'lar once bu yoldan gider

2. **Fallback kanal: Cloud Agent + Computer Use**
   - Browser UI uzerinden adim adim otomasyon
   - Sadece API olmayan veya UI zorunlu senaryolarda
   - Daha kirilgan ve maliyetli oldugu icin kontrollu kullanilir

## 5) Karar Matrisi (Hangi is nerede calisir?)

- **API varsa:** her zaman API kanali
- **API yok, web arayuz sart:** Computer Use kanali
- **Yuksek hacim/tekrarlayan is:** API kanali
- **Tek seferlik kesif / benchmark / UI dogrulama:** Computer Use uygun

## 6) Fallback Kurallari

- Orchestrator her gorev icin `execution_mode` secimi yapar:
  - `api`
  - `computer_use`
  - `api_then_computer_use` (otomatik fallback)
- API cagrisi N kez hata verirse ve gorev tipi izinliyse Computer Use devreye girer.
- Kritik adimlarda (merge/deploy/prod) insan onayi olmadan fallback uygulanmaz.

## 7) Maliyet ve Guvenlik Politikasi

- Run basina token ve dakika butcesi tanimlanir.
- Computer Use sadece izinli domain listesinde calisir.
- Tum browser adimlari audit log'a yazilir (hangi sayfada ne yapildi).
- Butce asiminda run `blocked` durumuna cekilir ve kullanicidan onay istenir.
