# Cloudflare Operasyon Paketi

Bu klasor, Dergah ekibi icin Cloudflare DNS ve ilgili operasyonel yetenekleri hizli uygulamak amaciyla hazirlandi.

## Icerik

1. `01_CLOUDFLARE_DNS_RUNBOOK.md`
   - DNS kaydi ekleme/guncelleme/silme adimlari
   - SSL ve cache islemleri
   - Dogrulama komutlari

2. `02_HIZLI_ISLEMLER.sh`
   - Hazir API komutlari
   - Zone bulma, kayit listeleme, create/update/delete

3. `03_DERGAH_MESAJ_SABLONU.md`
   - Diger dervislerle standart teknik paylasim metni

4. `04_DNS_KAYIT_FORMU.json`
   - Yeni DNS kaydi acmak icin doldurulabilir form

## Hizli Baslangic

1. Ortam degiskenlerini ayarla:

```bash
export CLOUDFLARE_API_TOKEN="TOKEN_BURAYA"
export CLOUDFLARE_ZONE_ID="ZONE_ID_BURAYA"
```

2. Scripti calistir:

```bash
bash 02_HIZLI_ISLEMLER.sh help
```

3. Yeni kayit ac:

```bash
bash 02_HIZLI_ISLEMLER.sh create CNAME app ecomaiq.com true 1
```

Not: `ttl=1` auto anlamina gelir.
