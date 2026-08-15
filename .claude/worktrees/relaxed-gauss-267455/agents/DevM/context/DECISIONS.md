# Technical Decisions Log

Bu dosya mimari ve operasyon kararlarinin tek kaynak kaydidir.

## D-001 — API-first
- Tarih: 2026-02-25
- Karar: Model entegrasyonunda birincil kanal resmi API olacak.
- Gerekce: Stabilite, hiz, maliyet ve olceklenebilirlik.

## D-002 — Computer Use fallback
- Tarih: 2026-02-25
- Karar: Cloud Agent + Computer Use sadece API olmayan/UI zorunlu islerde fallback olarak kullanilacak.
- Gerekce: Browser otomasyonu kirilgan; kontrollu kullanilmali.

## D-003 — 3 workspace paralel gelistirme
- Tarih: 2026-02-25
- Karar: Orchestrator, Model Broker ve IDE Runner ayri workspace uzerinden gelistirilecek.
- Gerekce: Paralel calisma, daha net sorumluluk ayrimi.

## D-004 — Talimat sistemi
- Tarih: 2026-02-25
- Karar: TALIMATLAR.md + scripts + VS Code Copilot Agent modeli ile otomasyon surdurulecek.
- Guncelleme: 2026-03-29 — Cursor CLI yerine VS Code Copilot Agent secildi.
- Gerekce: Tekrarlanabilir operasyon ve oturumlar arasi sureklilik. Cursor CLI bagimliligi kaldirildi.

## D-005 — Her agent, her proje için ayrı klasör
- Tarih: 2026-02-26
- Karar: Karışıklık olmaması için **her agent sadece kendi workspace’indeki `proje/` klasörüne yazar**. Yani: ws-1-orchestrator/proje/, ws-2-model-broker/proje/, ws-3-ide-runner/proje/ — her agent yalnızca kendi `proje/` altına yazar.
- Gerekce: Ajanlar birbirinin çıktısını ezmez; her workspace kendi çıktısını içinde tutar; hangi çıktının hangi ajandan olduğu net.
