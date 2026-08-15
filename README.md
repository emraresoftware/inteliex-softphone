# Inteliex Softphone MVP

Bu proje, Asterisk / FreePBX ile calisan ve iOS ile Android'i hedefleyen mobil bir SIP softphone icin baslangic planidir.

## Hedef

Ilk surum kapsamı:

- SIP hesap kaydi
- Giden cagri baslatma
- Gelen cagri kabul / red
- Mute / hold / DTMF
- Cagri gecmisi
- Rehber / kisi listesi
- Birden fazla hesap

## Onerilen Teknoloji

MVP icin en pratik secim:

- Flutter
- sip_ua
- flutter_webrtc
- flutter_secure_storage
- drift veya sqflite

Neden:

- Tek kod tabani ile iOS ve Android cikisi alinir.
- Asterisk / FreePBX tarafinda PJSIP + WSS akisi ile hizli entegrasyon kurulur.
- UI ve cagri ekranlari React Native'e gore daha tutarli toparlanir.

Not:

Zoiper seviyesinde arka plan / uygulama kapaliyken gelen cagri deneyimi icin ilerleyen asamada native VoIP entegrasyonu gerekir.
MVP icin uygulama acikken kalici SIP kaydi ile ilerlemek daha gercekcidir.

## Mobil Platformlar

Hedef platformlar:

- iOS
- Android

Platform ozel kontrol listesi icin docs/mobile-platform-checklist.md dosyasina bakin.

## Mimari Taslak

```text
lib/
  app/
  core/
    config/
    storage/
    audio/
  features/
    accounts/
    dialer/
    call/
    history/
    contacts/
  services/
    sip/
    media/
  platform/
    voip/
```

Katmanlar:

- services/sip: SIP kaydi, yeniden baglanma, cagri olaylari
- services/media: mikrofon, hoparlor, bluetooth, ses rotasi
- features/call: aktif cagri durumu, hold, mute, DTMF
- features/accounts: coklu hesap, credential yonetimi
- features/history: cagri logu ve sure bilgisi
- platform/voip: iOS CallKit / PushKit ve Android ConnectionService entegrasyonlari

## PBX Gereksinimleri

Mobil istemci icin sunlari bastan netlestirin:

- Asterisk tarafinda PJSIP kullanimi
- TLS / WSS aktif edilmesi
- SRTP / DTLS akisi
- NAT arkasindan erisim senaryosu
- Gerekirse STUN / TURN
- Test icin ayri dahili numaralar

FreePBX kullaniyorsaniz WebRTC uyumlu extension profili ile baslamak daha dogrudur.

## Teslim Fazlari

1. Hesap ekleme ve SIP registration
2. Dialer ve giden cagri
3. Gelen cagri ekrani ve temel kontrol tuslari
4. Cagri gecmisi ve kisi listesi
5. Coklu hesap yonetimi
6. Arka plan cagri ve push entegrasyonu

## Teknik Riskler

- iOS tarafinda PushKit / CallKit olmadan uygulama kapaliyken guvenilir gelen cagri beklenmemelidir.
- Android tarafinda battery optimization ve foreground service gereksinimleri vardir.
- Sadece SIP kaydi yapmak yeterli degildir; ses rotasi, kulaklik, bluetooth ve interruption senaryolari ayrica ele alinmalidir.
- Kurumsal kullanimda SIP over TLS ve credential secure storage zorunlu kabul edilmelidir.

## Ilk Uygulama Adimlari

Flutter kurulduktan sonra:

```bash
flutter create .
flutter pub get
```

Bu repo icin not:

- Bu klasore kaynak dosyalar elle yerlestirildi.
- Flutter kuruldugunda kok dizinde once `flutter create .` calistirin.
- Bu komut android ve ios klasorlerini ureterek mevcut `lib/` ve `pubspec.yaml` dosyalarini korur.
- `pubspec.yaml` icine temel SIP bagimliliklari eklendi; sonrasinda `flutter pub get` calistirin.
- Gercek SIP registration ve cagri olaylari artik `lib/services/sip/` altinda hibrit calisir: WS/WSS hesaplar `sip_ua`, Android UDP/TCP hesaplar mobilde native ABTO SDK uzerinden yonetilir.
- Hesap meta verisi ve cagri gecmisi yerel cihaz saklamasina baglandi; SIP sifreleri secure storage uzerinden tutulur.
- ABTO lisansi `--dart-define=ABTO_LICENSE_ID=...` ve `--dart-define=ABTO_LICENSE_KEY=...` ile build asamasinda gecilebilir.
- Drift tabanli daha kapsamli veri modeli ile native CallKit / ConnectionService katmanlari halen sonraki fazdadir.

## Android Paket / Firebase / Lisans Ayarlari

60 saniye sonra dusen cagri davranisi gordugunuzde en kritik nokta, ABTO lisansi ile Android package id eslesmesidir.

### Tek noktadan package id ayari

`android/gradle.properties` dosyasinda su alanlar kullanilir:

- `inteliex.applicationId`
- `inteliex.debugSuffix`

Varsayilan degerler:

- `inteliex.applicationId=com.example.inteliex_softphone`
- `inteliex.debugSuffix=.debug`

### Build sonucunda uretilen package adlari

- Release: `${inteliex.applicationId}`
- Debug: `${inteliex.applicationId}${inteliex.debugSuffix}`

### Firebase eslesmesi zorunlu

`google-services.json` icindeki `client[].android_client_info.package_name` degerleri, yukaridaki release/debug package adlariyla birebir ayni olmalidir.

Ornek:

- `com.example.inteliex_softphone`
- `com.example.inteliex_softphone.debug`

Eger lisansli package farkliysa (ornegin `org.cnt.inteliclient`), ilgili Firebase projesinden o package icin yeni `google-services.json` alin ve app module altina koyun.

### Hizli dogrulama komutlari

```bash
cd android
./gradlew :app:processDebugGoogleServices
```

Hata yoksa package/Firebase eslesmesi dogrudur.

```bash
cd ..
flutter build apk --debug
```

Ilk ekranlar:

- Login / account add
- Dialer
- Incoming call
- Active call
- Call history

## Bir Sonraki Adim

Bu plan uzerinden ilerleyip iki yoldan birini secin:

1. Flutter iskeletini kurup temel SIP registration ve arama ekranlarini olusturmak
2. Once Asterisk / FreePBX tarafini WebRTC icin hazirlayip test extensionlarini netlestirmek