Ask modundayım, dosyayı değiştiremem. Eski içeriği (Kod Hataları ve Güvenlik Açıklarını Bulma Yöntemleri) sohbetten vereyim, siz yapıştırırsınız:

```markdown
# Kod Hataları ve Güvenlik Açıklarını Bulma Yöntemleri

## 📋 İçindekiler

1. [İnceleme Metodolojisi](#i̇nceleme-metodolojisi)
2. [Otomatik Güvenlik Araçları](#otomatik-güvenlik-araçları)
3. [AI/ML Tabanlı Yöntemler](#aiml-tabanlı-yöntemler)
4. [Manuel Test Yöntemleri](#manuel-test-yöntemleri)
5. [İzleme ve Log Analizi](#i̇zleme-ve-log-analizi)
6. [Hemen Kullanabileceğin Yöntemler](#hemen-kullanabileceğin-yöntemler)
7. [Laravel Spesifik Kontroller](#laravel-spesifik-kontroller)
8. [Otomatik Test Scripti](#otomatik-test-scripti)
9. [CI/CD Entegrasyonu](#cicd-entegrasyonu)
10. [Öneri](#öneri)

---

## 🔍 İnceleme Metodolojisi

### 1. Sistemli Kod Taraması
- **Controller Katmanı:** Auth, Customer, Product, Sale, Accounting, Firm, Cash, API controller'larını satır satır incele
- **Model Katmanı:** User, Customer, Product gibi temel modellerin fillable alanlarını ve trait kullanımlarını kontrol et
- **Migration Dosyaları:** Veritabanı şemasında tenant_id sütunlarının varlığını kontrol et
- **Route Tanımları:** CSRF bypass ve middleware konfigürasyonlarını incele

### 2. Grep Aramaları ile Desen Tespiti
```bash
# Tenant kontrolü olmayan metodları bulmak için
- destroy(), store(), update() gibi metodlarda tenant_id kontrolü ara
- BelongsToTenant trait kullanımını tara
- is_super_admin fillable alanını ara
```

### 3. Multi-Tenant Mimari Odaklı Analiz
Laravel multi-tenant uygulamalarında en kritik güvenlik açıkları:
- **Tenant Isolation:** Her controller metodunda tenant kontrolü var mı?
- **Global Scopes:** Model'lerde otomatik tenant filtresi var mı?
- **Database Schema:** Tablolarda tenant_id sütunu var mı?

### 4. Güvenlik En İyi Uygulamaları Karşılaştırması
- OWASP Top 10 kriterlerini uygula
- Laravel güvenlik best practices ile karşılaştır
- Session encryption, password policy, rate limiting gibi standartları kontrol et

### 5. Kesişimsel Analiz
- Controller → Model → Migration üçlüsünü birlikte incele
- Bir controller metodunda tenant kontrolü yoksa, ilgili model ve migration'ı da kontrol et

### 6. Önceliklendirme
Bulunan sorunları 4 seviyeye ayır:
- **CRITICAL:** Data leakage, privilege escalation
- **HIGH:** Tenant isolation eksikliği
- **MEDIUM:** Session/Password güvenliği
- **LOW:** CORS konfigürasyonu

---

## 🔧 Otomatik Güvenlik Araçları

### 1. Static Application Security Testing (SAST)
- **PHPStan / Psalm:** PHP kod analizi
- **Laravel Pint / PHP-CS-Fixer:** Kod kalitesi
- **Phan:** Tip güvenliği ve bug tespiti

### 2. Dependency Scanning
- **Composer Audit:** PHP paket güvenlik açıkları
- **Snyk / Dependabot:** Otomatik dependency güvenlik taraması
- **OWASP Dependency-Check:** Kütüphane açıkları

### 3. Dynamic Application Security Testing (DAST)
- **Burp Suite:** Web uygulama güvenlik testi
- **OWASP ZAP:** Ücretsiz güvenlik tarayıcı
- **Nuclei:** Otomatik vulnerability scanner

### 4. Laravel Spesifik Araçlar
- **Laravel Debugbar:** SQL query analizi
- **Laravel Telescope:** Request/response monitoring
- **Laravel Horizon:** Queue monitoring
- **Laravel Scout:** Search güvenliği

---

## 🤖 AI/ML Tabanlı Yöntemler

### 5. AI-Powered Code Review
- **GitHub Copilot Security:** Kod güvenliği önerileri
- **CodeQL:** Semantic code analysis
- **SonarQube:** AI destekli kod kalitesi

### 6. Pattern Matching
- Regex tabanlı güvenlik deseni taraması
- SQL injection pattern detection
- XSS pattern matching

---

## 🔬 Manuel Test Yöntemleri

### 7. Penetration Testing
- **Black Box:** Dışarıdan saldırı simülasyonu
- **White Box:** Kod bilerek test
- **Grey Box:** Kısmi bilgi ile test

### 8. Fuzzing
- Rastgele input ile crash tespiti
- Boundary value testing
- Exception handling testi

### 9. Manual Code Review
- Pair programming review
- Security-focused code walkthrough
- Threat modeling

### 10. API Security Testing
- **Postman:** API endpoint güvenlik testleri
- **Insomnia:** API testing
- **Swagger/OpenAPI:** API validation

### 11. Browser DevTools
- Network tab ile request/response analizi
- Console error monitoring
- LocalStorage/SessionStorage kontrolü

---

## 📊 İzleme ve Log Analizi

### 12. Runtime Monitoring
- **Sentry:** Hata takibi
- **New Relic:** Performance monitoring
- **Datadog:** Application monitoring

### 13. Log Analysis
- Access log analizi
- Error log pattern matching
- Anomali tespiti

### 14. Laravel Log Analizi
```bash
tail -f storage/logs/laravel.log
```
- Error pattern matching
- Exception tracking
- Slow query detection

### 15. Container Security
- Docker image scanning (Trivy, Clair)
- Container vulnerability scanning

---

## 🛠️ Hemen Kullanabileceğin Yöntemler

### 1. Laravel Debugbar (Geliştirme Ortamı)
```bash
composer require barryvdh/laravel-debugbar
```
- SQL sorgularını gör
- Request/response detayları
- Memory kullanımı
- View render süreleri

### 2. PHPStan (Static Analysis)
```bash
composer require --dev phpstan/phpstan
vendor/bin/phpstan analyse app
```
- Tip hatalarını bulur
- Undefined değişkenleri tespit eder
- Dead code'u gösterir

### 3. Laravel Pint (Kod Formatlama)
```bash
composer require --dev laravel/pint
vendor/bin/pint
```
- Kod stilini düzeltir
- Potansiyel hataları gösterir

### 4. Composer Audit (Dependency Güvenliği)
```bash
composer audit
```
- Güvenlik açıklı paketleri gösterir
- CVE raporları verir

### 5. Grep ile Desen Arama
```bash
# SQL injection riski
grep -r "DB::raw\|->whereRaw\|->selectRaw" app/

# XSS riski
grep -r "{{ \$" resources/views/

# Hardcoded secrets
grep -r "API_KEY\|SECRET\|PASSWORD" app/ .env

# Tenant kontrolü olmayan metodlar
grep -A 5 "public function destroy\|public function store\|public function update" app/Http/Controllers/
```

### 6. PHPUnit Test Yazma
```bash
php artisan make:test CustomerTest
```
- Tenant isolation testleri
- Authorization testleri
- Validation testleri

### 7. Laravel Telescope (Production Monitoring)
```bash
composer require laravel/telescope
```
- Request logları
- Exception logları
- Database query logları

---

## 🎯 Laravel Spesifik Kontroller

### 8. Route Listesi Analizi
```bash
php artisan route:list --json
```
- Hangi route'larda middleware eksik?
- CSRF koruması olmayan route'lar

### 9. Model İlişki Kontrolü
```bash
php artisan model:list
```
- BelongsToTenant trait kullanımı
- Global scope'lar

### 10. Migration Status
```bash
php artisan migrate:status
```
- Bekleyen migration'lar
- Schema değişiklikleri

### 11. Cache Management
```bash
# Cache clear
php artisan cache:clear

# Config cache
php artisan config:cache

# Route cache
php artisan route:cache

# View cache
php artisan view:clear
```

---

## 🚀 Otomatik Test Scripti

```bash
#!/bin/bash
echo "🔍 Güvenlik Taraması Başlıyor..."

# 1. Dependency audit
echo "📦 Dependency Audit..."
composer audit

# 2. PHPStan
echo "🔬 Static Analysis..."
vendor/bin/phpstan analyse app --level=5

# 3. Laravel Pint
echo "🎨 Code Style Check..."
vendor/bin/pint --test

# 4. Hardcoded secrets
echo "🔐 Secret Scan..."
grep -r "API_KEY\|SECRET\|PASSWORD" app/ .env.example

# 5. SQL injection risk
echo "💉 SQL Injection Scan..."
grep -r "DB::raw\|->whereRaw\|->selectRaw" app/

# 6. XSS risk
echo "🌐 XSS Scan..."
grep -r "{{ \$" resources/views/

echo "✅ Tarama Tamamlandı!"
```

---

## 📊 CI/CD Entegrasyonu

### GitHub Actions Örneği
```yaml
name: Security Scan
on: [push, pull_request]
jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Composer Audit
        run: composer audit
      - name: Run PHPStan
        run: vendor/bin/phpstan analyse app
      - name: Run Laravel Pint
        run: vendor/bin/pint --test
```

### GitLab CI Örneği
```yaml
security-scan:
  stage: test
  script:
    - composer audit
    - vendor/bin/phpstan analyse app
    - vendor/bin/pint --test
  only:
    - merge_requests
    - main
```

---

## 🎯 Öneri

### Hemen Başla
1. `composer audit` çalıştır
2. Laravel Debugbar kur
3. Yukarıdaki shell script'i çalıştır

### Haftalık Rutin
- PHPStan analizi
- Route listesi kontrolü
- Model trait kullanımı kontrolü
- Log dosyası analizi

### Aylık Rutin
- Manuel kod review
- Penetration test
- Dependency güncellemeleri
- Container security scan

### Çeyrek Yıllık Rutin
- Full security audit
- Performance test
- Load testing (Apache Bench, k6)
- Infrastructure review

---

## 📚 Referanslar

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Laravel Security Documentation](https://laravel.com/docs/security)
- [PHPStan Documentation](https://phpstan.org/)
- [SonarQube Documentation](https://docs.sonarqube.org/)
- [OWASP ZAP](https://www.zaproxy.org/)

---

**Son Güncelleme:** 19 Nisan 2026
```