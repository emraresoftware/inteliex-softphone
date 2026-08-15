# Exo Kurulum Notlari (Bu Makine)

Tarih: 28 Mart 2026

## Durum Ozeti

- Exo resmi install scripti (exolabs.net/install.sh) bu sistemde nix-darwin satirinda hata verdi.
- Kaynaktan kurulum denendi: /Users/emre/exo icinde uv run exo.
- Derleme asamasinda MLX build metal toolchain hatasi ile durdu.
- Belirti: `xcrun -f metallib` komutu `unable to find utility "metallib"` donuyor.
- `xcodebuild -downloadComponent MetalToolchain` ile `metal/metallib` geldi, Exo API 52415 acildi.
- Ancak model inference adiminda MLX metal kernel derleme hatalari goruldu (`bfloat16_t`, `complex64_t` vb.), chat endpoint timeout oluyor.

## Hizli Kontrol

- xcrun -f metal
- xcrun -f metallib
- curl http://127.0.0.1:52415/models

Beklenen:
- metal ve metallib bulunmali
- Exo aciksa 52415 cevap vermeli

## Cozum Adimlari

1) Xcode gelistirici araclarini tamamla/guncelle
- Xcode'u ac, varsa ek komponent kurulumunu tamamla.
- Gerekirse Command Line Tools yeniden kur.

2) Secili developer path dogrula
- sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

3) Lisans/ilk acilis adimlarini tamamla
- sudo xcodebuild -license accept
- sudo xcodebuild -runFirstLaunch

4) Tekrar metallib kontrolu
- xcrun -f metallib

5) Exo tekrar baslat
- cd /Users/emre/exo
- uv run exo

6) API dogrula
- curl http://127.0.0.1:52415/models

## Dergah Entegrasyon Notu

Exo hazir olduktan sonra env dosyalari zaten doldurulmus durumda:
- .env.m5-orchestrator.example
- .env.worker1.example
- .env.worker2.example

Panel baslatma:
- scripts/start_node.sh orchestrator panel

## Mevcut Blokaj (28 Mart 2026)

- API katmani acik: `http://127.0.0.1:52415`.
- Model listesi geliyor (`/models`, `/v1/models`, `/ollama/api/tags`).
- Fakat inference endpointleri (`/v1/chat/completions`, `/ollama/api/chat`) timeout veriyor.
- Exo logunda runner tarafinda MLX metal kernel derleme hatalari var.

## Gecici Cozum Onerisi

1) Exo macOS App (DMG) ile calistirip tekrar test et.
2) Veya exo/mlx tarafinda Xcode 26.4 ile uyumlu guncel build bekle.
3) Bu surecte Dergah tarafinda `DERGAH_LLM_PROVIDER=ollama` fallback kullan.
