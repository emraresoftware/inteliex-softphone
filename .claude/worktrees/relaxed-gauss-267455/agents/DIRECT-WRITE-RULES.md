# Direct Write Kuralları (Ortak Repo)

Tüm ajanlar tek canonical repo'ya (`MODE=direct`) doğrudan yazar.

---

## 1. Temel İlke

- **Her ajan sadece kendi dosya sahiplik alanına yazar.**  
  Sahiplik haritası `backlog.json → rules.fileOwnership` içindedir.
- **Aynı dosyada paralel çalışma yoktur.**  
  Bir ajan bir dosyayı düzenliyorsa diğerleri bekler.

---

## 2. Kilit Mekanizması

Bir dosyaya başlamadan önce `handoffs.ndjson`'a `lock` satırı düşülür:

```json
{"ts":"2026-01-01T10:00:00Z","from":"integration","to":"all","type":"lock","file":"app/Services/Integration/WebhookService.php"}
```

İş bitince `unlock`:

```json
{"ts":"2026-01-01T10:30:00Z","from":"integration","to":"all","type":"unlock","file":"app/Services/Integration/WebhookService.php"}
```

---

## 3. Zorunlu Akış (Her Görev İçin)

1. Kod değişikliği  
2. İlgili testler yaz / güncelle  
3. `validate.sh` çalıştır → `Hata: 0`  
4. `handoffs.ndjson`'a `progress` satırı ekle  
5. Merge kararı → **yalnızca orchestrator**  

---

## 4. Paylaşımlı Dosyalar

Birden fazla ajanın yazdığı dosyalar (`routes/api.php`, `tests/` vb.):

- Değişiklik öncesi diğer ajanların aktif lock'u kontrol edilir.
- Çakışma olursa **dosya sahibi ajanın değişikliği** esastır.
- Gerekirse orchestrator cherry-pick ile birleştirir.

---

## 5. Orchestrator'a Saklı İşlemler

| İşlem | Kim yapabilir |
|-------|--------------|
| `validate.sh` (final) | Yalnızca orchestrator |
| `git merge / rebase` | Yalnızca orchestrator |
| `git push`, release tag | Yalnızca orchestrator |
| `backlog.json` sprint değişimi | Yalnızca orchestrator |

---

## 6. Yasaklar

- ❌ Başka ajanın dosya sahiplik alanına doğrudan yazım  
- ❌ `git push --force` veya `git reset --hard`  
- ❌ Orchestrator onayı olmadan merge  
- ❌ `backlog.json` güncellenmeden görevi `done` saymak  
- ❌ Toplu refactor (sahiplik dışı dosyalarda)  
