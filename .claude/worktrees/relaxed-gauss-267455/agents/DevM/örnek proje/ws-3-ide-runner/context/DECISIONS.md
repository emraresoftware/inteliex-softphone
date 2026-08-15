# DECISIONS — ws-3-ide-runner

Bu workspace IDE ajan çalıştırma katmanına odaklanır.

## Process / bridge (taslak)
- IDE ajanı: belirli prompt + workspace path ile tetiklenir.
- Consensus çıktısı → markdown talimat dosyası + workspace yolu.

## Result toplama
- stdout, stderr, değişen dosya listesi, exit code → run klasörü / logs.

Bu dosya TALIMATLAR.md maddeleri tamamlandıkça güncellenir.
