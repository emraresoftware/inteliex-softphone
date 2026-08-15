# DECISIONS — Run state machine ve politikalar

## Run state enum
Run durumları için sabit liste:
- `created`
- `running`
- `completed`
- `failed`
- `blocked`

Bu enum proje boyunca tek kaynak olarak kullanılacaktır. Kodda ve dokümanlarda bu anahtar kelimeler kullanılmalıdır.

## Geçiş Kuralları (State transitions)
- `created` -> `running` : bir run oluşturulduktan ve gerekli spec sağlandıktan sonra başlatılabilir.
- `running` -> `completed` : tüm stage'ler başarıyla tamamlandığında.
- `running` -> `failed` : kritik hata veya validation başarısızlığı olduğunda.
- `running` -> `blocked` : insan onayı bekleniyorsa veya dış bağımlılık başarısızsa.
- `blocked` -> `running` : insan onayı verildiğinde veya beklenen koşul sağlandığında.

Kurallar:
- Bir stage tamamlanmadan sonraki stage'e geçilemez. (Atomicity requirement)
- State geçişleri event-sourced ve audit log ile kaydedilecek.

Detaylı stage akışı (stage geçişleri)
- `spec` → `consensus` : spec dokümanı (`project_spec.md`) üretildikten ve temel parametreler belirlendikten sonra.
- `consensus` → `ide_run` : ekip onayı (PR veya Slack onayı) alındıktan sonra.
- `ide_run` → `validation` : IDE/CI üzerinde otomatik çalıştırmalar başarıyla geçtiğinde.
- `validation` → `deploy` : validation sonrası prod deploy planı hazırsa ve human approval varsa.

Her stage için tamamlanma kriterleri (tek cümle özetleri):
- spec: `project_spec.md` ve `task_backlog.json` oluşturuldu ve PR açıldı.
- consensus: Gereken ekip onayları (en az 2 onay veya proje politikası) sağlandı.
- ide_run: Local/IDE otomatik testler çalıştırıldı; smoke testler geçti.
- validation: CI testleri (unit+integration) ve smoke testleri geçti.
- deploy: Human approval verildi ve deploy checklist tamamlandı.

Bu maddeler dokümante edildi ve ilgili referans dosyalar repoda mevcuttur (`project_spec.md`, `task_backlog.json`).

## Retry / Backoff politikası
- Maksimum deneme sayısı: 3
- Backoff: üstel artan (örnek): 1s, 2s, 4s
- Uygulama: API çağrılarında transient hata alınırsa retry uygulanacak; kalıcı hatalarda retry yapılmayacak.

Retry / Backoff - detay
- Maksimum deneme sayısı: 3
- Backoff stratejisi: Exponential backoff (örnek beklemeler: 1s, 2s, 4s), jitter ile birlikte.
- Hangi hatalarda retry: HTTP 5xx, network timeout'ları; 4xx hatalarda retry uygulanmaz.

 Bu politika `DECISIONS.md` içinde kayıtlıdır ve TASKS/CI scriptlerinde kullanılmak üzere referanslanabilir.

Canonical stage list (kesin biçim):

- spec → consensus → ide_run → validation → deploy

 Lütfen bu biçimi dokümanlarda koruyun; `TALIMATLAR.md` içinde aynı ifadeyi kullanan talimatlar otomatik tanınacaktır.

## Human approval gate
- Hangi adımlarda insan onayı zorunlu: `deploy` (prod), kritik veri değişiklikleri, manuel merge to prod.
- İnsan onayı olmadan bu adımlar `blocked` durumuna geçer ve otomatik ilerleme durur.
- Onay süreci: Slack/PR/CLI onayı mekanizması (detaylar TASKS.md içinde).
