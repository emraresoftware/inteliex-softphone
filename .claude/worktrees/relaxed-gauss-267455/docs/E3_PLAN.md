# E3 PLAN - Operasyon ve Uretim Hazirlik

## 1. Amac
E3 sprintinin amaci, mevcut E1 ve E2 ciktisini uretime guvenli ve izlenebilir sekilde tasimaktir.

## 2. Hedefler
- Uretim ortami icin calisma parametrelerini netlestirmek
- Servis gozlemlenebilirligini standardize etmek
- Yayina alma ve geri alma adimlarini dokumante etmek
- Release oncesi smoke ve regresyon kalite kapisini netlestirmek

## 3. Kapsam
- Konfig/ortam degiskenleri
- Log, metrik, alarm temel seti
- Release runbook ve rollback adimlari
- Smoke/regresyon komutlari ve beklenen ciktilar

## 4. Kapsam Disi
- Yeni buyuk ozellik gelistirmesi
- Veri modeli buyuk yeniden tasarimi
- Uretimde canli trafik altinda mimari degisiklik

## 5. Riskler ve Azaltimlar
- Risk: Ortam degiskeni farklari nedeniyle runtime hata
  - Azaltim: Dev/Stage/Prod env matrisi + startup validation
- Risk: Yetersiz gozlemlenebilirlik nedeniyle gec fark edilen hata
  - Azaltim: Temel metrik seti + alarm esikleri + log standardi
- Risk: Release sonrasi hizli geri donus eksikligi
  - Azaltim: Rollback adimlarini tek komut/tek prosedur haline getirme

## 6. Gorevler ve Kabul Kriterleri

### E3-000 - Sprint planlama ve kabul kriterleri (yonetici)
Kabul kriterleri:
- E3 gorevlerinin bagimlilik zinciri net: E3-000 -> E3-001 -> E3-002 -> E3-003
- Bu dokuman (`docs/E3_PLAN.md`) tamamlanmis ve version kontrolunde
- `agents/handoffs.ndjson` icinde E3 kickoff kaydi mevcut

### E3-001 - Uretim konfigurasyonu ve ortam degiskenleri (sunucu-dev)
Kabul kriterleri:
- Dev/Stage/Prod icin env matrisi dokumante
- Eksik kritik env degiskenlerinde uygulama fail-fast veya acik uyari veriyor
- `npm start` ve gerekli run komutlari hedef ortamlarda dogrulaniyor

### E3-002 - Gozlemlenebilirlik dashboard ve alarmlar (guvenlik-dev)
Kabul kriterleri:
- En az su metrikler raporlaniyor: response time, error rate, request count, 429 count
- En az 3 alarm esigi tanimli ve dokumante
- Request log formati ekip tarafindan okunabilir ve korelasyon icin tutarli

### E3-003 - Release smoke ve regresyon paketi (test-dev)
Kabul kriterleri:
- Standart test komutu: `npm test -- --runInBand`
- Kritik endpoint smoke senaryolari tanimli ve calisir durumda
- Release oncesi kalite kapisi: test green + smoke green + rollback adimlari hazir

## 7. Dogrulama Komutlari
- `npm test -- --runInBand`
- `npm start`
- `npm run dev`

Not: `npm start` ve `npm run dev` komutlari proje dizininde calistirilmalidir.

## 8. Rollout ve Rollback
Rollout:
1. Stage dogrulama tamamlanir
2. Production deploy yapilir
3. Smoke test calistirilir
4. Metrik/alarm ilk 30 dakika izlenir

Rollback:
1. Son stabil surume don
2. Gerekirse migration rollback uygula
3. Smoke test tekrar calistir
4. Olay kaydini handoff/gunluklere isle

## 9. Cikis Kosullari
E3 sprinti, asagidaki tum kosullar saglandiginda kapanir:
- E3-001 done
- E3-002 done
- E3-003 done
- Test ve smoke kapilari green
- Rollback proseduru uygulanabilir sekilde dokumante
