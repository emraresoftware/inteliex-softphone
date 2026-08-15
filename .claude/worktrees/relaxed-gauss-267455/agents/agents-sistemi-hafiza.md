# Agents Sistemi - Kalici Hafiza (28 Mart 2026)

## Genel Mimari
- Ana proje: /Users/emre/Desktop/Emare/emarecrm/emare-crm
- Ajan altyapisi: /Users/emre/Desktop/Emare/emarecrm/.agents
- Calisma modeli: cok ajan, tek canonical repo
- Mod: MODE=direct (worktree/copy yerine ortak repoya dogrudan yazim)

## Ajan Roller
- orchestrator: planlama, merge-gate, release, final validate
- domain: PR/PO, workflow-engine, is kurallari
- finance: banka mutabakati, muhasebe, para birimi/finans akislar
- integration: webhook, outbox, idempotency, API guvenligi
- quality: feature/contract/smoke testleri, kalite kapisi
- ui: portal ekranlari, dashboard, UI akislar

## Kritik Dosyalar (.agents)
- runtime.env: aktif mod ve REPO_DIR
- agents.json: ajan tanimlari, branch/path/focus
- backlog.json: sprint gorevleri + rules + fileOwnership
- DIRECT-WRITE-RULES.md: ayni dosyada paralel yazim, kilit, merge kurallari
- handoffs.ndjson: ajanlar arasi devir teslim/event log (append-only)
- cards/: is kartlari, checklistler, kapanis notlari

## Direct-Write Kurallari
- Tek dosyaya ayni anda tek ajan yazar
- Sahiplik disi dosyalara yazim yasak
- lock/unlock mantigi handoff kaydi ile yurur
- final validate/merge/release sadece orchestrator
- force push/hard reset gibi destruktif aksiyonlar yasak

## Tools/Agents Scriptleri
- tools/agents/init.sh: sistemi baslatir (worktree/copy/direct baglamina gore)
- tools/agents/status.sh: ajan durumlarini gosterir
- tools/agents/intake.sh: copy modunda guncel dosyalari dagitir
- tools/agents/sync.sh: senkron adimlari
- tools/agents/merge.sh: merge oncesi/uygulama akisi
- tools/agents/validate.sh: kalite kapisi

## validate.sh Ozet Kontroller
- PHP syntax taramasi
- Pint stili (ortam/TTY durumuna gore)
- PHPStan (varsa)
- CDN yasagi kontrolleri
- guvenlik/mass assignment kontrolleri
- test/migration/route uyum kontrolleri
- bilinen cikti: "Gecti: 6, Hata: 0" (uyari sayisi olabilir)

## Sprint S1 Durum Ozet
- S1-003 done: Banka mutabakat API + servis + testler (PASS)
- S1-004 done: Webhook HMAC + retry + idempotency + DLQ + testler (PASS)
- S1-005 done: CRM-Finance contract testleri (PASS)
- S1-006 done: Musteri portal API/service + testler (PASS)
- S1-001 in_progress: PR/PO satin alma akisi (domain ajan aktif)
- S1-002 todo: Approval engine/SoD (S1-001 bagimli)

## S1-001 Teknik Hedef (Domain)
- Satinalma talebi olustur/guncelle
- Durum gecisleri: taslak -> onay_bekliyor -> onaylandi -> siparis_olusturuldu (+ iptal)
- Talep kalem toplam hesaplama
- Talep -> siparis donusumu
- API Controller + route + feature testler

## Repo Icinde Mevcut Satin Alma Varliklari
- app/Services/SatinalmaService.php mevcut
- app/Models/SatinalmaTalebi.php mevcut
- app/Models/SatinalmaSiparisi.php mevcut
- migration 2025_01_15_000007_create_satinalma_tables.php mevcut
- Livewire satin alma talep ekranlari mevcut
- API tarafi S1-001 kapsaminda tamamlanacak

## Agents Referans Paket (Genel Kullanim)
- /Users/emre/Desktop/erp analiz/agents klasoru hazirlandi
- Icerik: scriptler + agents.json + runtime.env + backlog.json + DIRECT-WRITE-RULES.md + README.md + handoffs.ndjson + cards template
- Bu klasor yeni projelere kopyalanip sadece yol/proje/task bilgileri ozellestirilir

## GitHub Tabanli Dervis Haberlesme Notu
- emarecloud icinde emare_messenger.py var
- Haberlesme modeli GitHub Issues tabanli
- Repo: emraresoftware/emare-ortak-calisma
- Label ornekleri: dervis-mesaj, duyuru, acil, alici:*, gonderen:*
- Bu sistem emarecrm ajan surecine entegre edilebilir (opsiyonel)

## Operasyon Notlari
- Terminalde validate bazen exit 2 gorunse de piping ile gercek sonuc 0 gelebilir
- TERM=dumb ile Pint ciktilari sade/kararli okunur
- Ortak repo modunda ajanlarin ayni dosyada paralel calismasi cakismanin ana kaynagidir
- En guvenli akis: ownership -> lock -> edit -> test -> validate -> handoff
