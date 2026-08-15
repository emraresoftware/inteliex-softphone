# TALIMATLAR — test-dev

Bu dosyadaki `- [ ]` maddeleri Copilot Agent ile uygulayın.
Uyguladıktan sonra her maddeyi `- [x]` ile işaretleyin.

## E1-005 — Test yazimi ve kalite kontrolu
> sprint: E1 | durum: completed | ajan: test-dev

- [x] `tests/unit/` — model ve service katmanları için unit testler
- [x] `tests/integration/` veya `tests/e2e/` altinda root (`/`) icin HTML smoke testi eklenir
- [x] `GET /` icinde musteri arayuzu basligi ve CTA varligi dogrulanir
- [x] `GET /styles.css` 200 doner ve temel stil icerigi dogrulanir
- [x] `npm test -- --runInBand` tekrar green calisir

## E3-102 — Test artifact kaydi
> sprint: E3 | durum: completed | ajan: test-dev

- [x] `regression_report.txt` dosyasini olustur; icinde `GET / title ok`, `GET /styles.css ok`, `npm test -- --runInBand ok` satirlari yer alsin
## E4-002 — Test kapsam raporu
> sprint: E4 | durum: completed

- [x] `projects/emarecloud_ceyiz` icinde `npm test -- --coverage --runInBand` komutunu calistir
- [x] `coverage_report.txt` dosyasina su ozet satirlarini yaz: `npm test -- --coverage --runInBand tamam`, `statements 72.27`, `branches 61.11`, `functions 71.76`, `lines 73.03`, `global threshold 80 altinda`

## E5-001 — Middleware ve app coverage aciklarini kapat
> sprint: E5 | durum: completed | ajan: test-dev

- [x] E5-001: Middleware ve app coverage aciklarini kapat
- [x] Sonucu `coverage_phase1_report.txt` dosyasına yaz

## E6-002 — Services-storage-observability coverage aciklarini kapat
> sprint: E6 | durum: completed

- [x] E6-002: Services-storage-observability coverage aciklarini kapat
- [x] Sonucu `coverage_phase2_report.txt` dosyasına yaz
