# iOS ve Android Checklist

Bu proje yalnizca mobil hedef icin tasarlaniyor: iOS ve Android.

Su anki repo durumu:

- Flutter kaynaklari hazir.
- android ve ios klasorleri henuz uretilmedi.
- Bu klasorler Flutter kurulduktan sonra repo kokunde flutter create . ile olusturulacak.

## 1. Ortak Mobil Hedef

- SIP sinyallesme: WSS uzerinden sip_ua
- Medya: flutter_webrtc
- Kimlik bilgisi saklama: flutter_secure_storage
- Cagri gecmisi: drift veya benzeri yerel veritabani

## 2. iOS Gereksinimleri

Ilk canlandirilacak basliklar:

- Mikrofon izni
- Bluetooth ses rotasi testleri
- AVAudioSession kategorisi ve interruption yonetimi
- TLS sertifika zincirinin iOS tarafinda guvenilir olmasi

Ileri faz zorunluluklari:

- CallKit ile sistem cagri arayuzu
- PushKit ile kapali veya arka plan senaryosunda uyandirma
- Arka plan modlarinin dogru tanimlanmasi

Native klasorler olustuktan sonra kontrol edilmesi gerekenler:

- ios/Runner/Info.plist icinde mikrofon aciklamasi
- Video dusunulurse kamera aciklamasi
- Push kullanilacaksa capability ve entitlement tanimlari
- CallKit akisina baglanacak MethodChannel handler'lari

## 3. Android Gereksinimleri

Ilk canlandirilacak basliklar:

- Internet ve mikrofon izinleri
- Bluetooth kulaklik testleri
- Echo cancellation ve ses rotasi davranisi
- Farkli Android surumlerinde arka plan sinirlarinin testi

Ileri faz zorunluluklari:

- ConnectionService veya Telecom entegrasyonu
- Foreground service ile aktif cagri yasam dongusu
- Push tabanli gelen cagri uyandirma
- Battery optimization etkilerinin test edilmesi

Native klasorler olustuktan sonra kontrol edilmesi gerekenler:

- android/app/src/main/AndroidManifest.xml izinleri
- Android 13+ bildirim izni gerekiyorsa eklenmesi
- Foreground service ve tam ekran gelen cagri akisi
- MethodChannel ile native cagri durumunun Flutter'a aktarimi

## 4. Bu Repodaki Hazir Kanca Noktalari

Platform entegrasyonu icin asagidaki dosyalar hazirlandi:

- lib/platform/voip/voip_platform_bridge.dart
- lib/platform/voip/method_channel_voip_platform_bridge.dart
- lib/platform/voip/create_voip_platform_bridge.dart

Bu katman, ileride:

- iOS tarafinda CallKit ve PushKit
- Android tarafinda ConnectionService ve foreground service

icin Flutter ile native kod arasinda kopru gorecek.

Not:

- Flutter katmaninda `sip_ua` tabanli registration ve cagri dinleyicisi artik eklendi.
- Native izinler, ses rotasi ve arka plan davranisi halen platform klasorleri uretildikten sonra tamamlanacak.

## 5. Bugun Icin Gercekci Hedef

MVP hedefi:

- Uygulama acikken iOS ve Android'de stabil SIP registration
- Uygulama acikken gelen ve giden sesli cagri
- Mute, hold, DTMF, cagri gecmisi ve coklu hesap

Zoiper benzeri arka plan guvenilirligi sonraki fazdir.
