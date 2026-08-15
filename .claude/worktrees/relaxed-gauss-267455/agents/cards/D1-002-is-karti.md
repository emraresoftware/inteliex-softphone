# D1-002 — Core panel durum senkronu

**Ajan:** core  
**Sprint:** D1  
**Durum:** todo  
**Bagimliliklar:** —

---

## Kapsam

`dervis_core` ile panel arasinda durum aktariminin netlestirilmesi. Ozellikle son durumun bellek/yazi kaynagi ile panel gosterimi arasinda tutarlilik saglanacak. Durum payload alanlari standardize edilecek.

## Teslim Kriterleri (Definition of Done)

- [ ] Core tarafinda durum payload standardi net
- [ ] Panel tarafinda ayni schema okunuyor
- [ ] En az bir smoke senaryosu gecti
- [ ] `agents/validate.sh` kalite kapisi geciyor
- [ ] handoff girdisi eklendi

## Zorunlu Dosyalar

| Dosya | Aciklama |
|-------|----------|
| `scripts/dervis_core.py` | Core durum uretimi |
| `scripts/dervis_panel.py` | Panelde durum gosterimi |
| `data/chat_memory/panel_latest.json` | Panel son durum verisi |

## Test/Senaryo

```bash
python3.14 scripts/dervis_panel.py
python3.14 -m py_compile scripts/dervis_core.py scripts/dervis_panel.py
```

## Notlar

- UI/Panel degisikligi minimal, veri uyumu oncelikli.
