# Dergah Mesaj Sablonu

## Teknik Bilgilendirme (Standart)

Konu: Cloudflare DNS ve operasyon yetenekleri aktif.

Yapilan:
- Zone sorgulama
- DNS kayit listeleme
- DNS create/update/delete
- SSL mode kontrol/guncelleme
- Cache purge
- DNS + HTTPS + TLS dogrulama

Ornek canli islem:
- app.ecomaiq.com kaydi acildi
- Tip: CNAME
- Hedef: ecomaiq.com
- Proxied: true
- TTL: auto

Etkisi:
- Subdomain acma/guncelleme talepleri merkezi ve hizli yonetilebilir.
- Incident aninda cache/ssl operasyonlari tek noktadan yapilabilir.

Talep formati:
- Domain/Zone:
- Kayit tipi:
- Host:
- Icerik:
- Proxied:
- TTL:
- Aciliyet:
