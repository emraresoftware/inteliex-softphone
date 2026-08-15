# Translation Manager

Laravel 12 + Filament 3 tabanli bir ceviri yonetim paneli.

Bu proje; birden fazla proje/modul icin ceviri key'lerini ve dil bazli degerleri yonetir, ardindan farkli hedef formatlarda export eder:
- Laravel PHP array
- JSON (React / i18next)
- Flutter ARB

## Ozellikler

- Proje bazli ceviri organizasyonu
- Modul (namespace) bazli key yonetimi
- Coklu dil destegi ve varsayilan dil isaretleme
- Filament admin paneli ile CRUD ekranlari
- ZIP olarak toplu export:
  - `lang/{lang}/{module}.php`
  - `locales/{lang}/{module}.json`
  - `arb/{lang}/{module}.arb`

## Teknoloji

- PHP 8.2+
- Laravel 12
- Filament 3
- Vite + TailwindCSS 4
- PHPUnit 11

## Kurulum

```bash
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed
npm install
npm run build
```

Alternatif tek komut:

```bash
composer run setup
```

## Gelistirme Ortami

Tum servisleri birlikte calistirmak icin:

```bash
composer run dev
```

Bu script sunlari baslatir:
- Laravel development server
- Queue listener
- Log watcher (pail)
- Vite dev server

## Admin Panel

- URL: `/admin`
- Login gerekli (Filament auth middleware aktif)

Varsayilan seeder kullanicisi:
- Email: `test@example.com`
- Sifre: `password`

## Veri Modeli

Iliski yapisi:
- `Project` -> birden cok `TranslationNamespace`
- `TranslationNamespace` -> birden cok `TranslationKey`
- `TranslationKey` -> birden cok `Translation`
- `Language` -> birden cok `Translation`

Onemli veritabani kisitlari:
- Ayni proje icinde ayni modul adi tekrar edemez
- Ayni modul icinde ayni key tekrar edemez
- Ayni key + dil kombinasyonu tekrar edemez

## Export

Filament Projeler ekranindan proje bazli export alabilirsiniz:
- Laravel PHP Export
- JSON Export (React/i18next)
- ARB Export (Flutter)

Export dosyalari gecici olarak `storage/app/exports` altinda uretilir ve indirme sonrasi silinir.

## Test

```bash
php artisan test
```

Proje su an temel domain kisitlarini ve exporter davranisini test eden feature testler icerir.

## Dizinler

- `app/Filament/Resources`: Admin panel CRUD kaynaklari
- `app/Models`: Domain modelleri
- `app/Services/TranslationExporter.php`: Format donusumu ve ZIP export
- `database/migrations`: Veritabani semasi
- `tests/Feature`: Davranis testleri

## Notlar

- `TranslationNamespace` modeli veritabani `namespaces` tablosunu kullanir.
- Buyuk veri setlerinde export islemleri queue'ya alinacak sekilde gelistirilebilir.
