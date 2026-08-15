# Android Kalıcı Ayarlar ve Bilinen Tuzaklar

Bu dosya, geliştirme sırasında karşılaşılan ve çözülen sorunların kalıcı notlarını
tutar. Yeni bir bağımlılık eklendiğinde, manifest'i sıfırdan yeniden ürettiğinizde
veya başka bir cihaz için build aldığınızda **mutlaka** bu listeyi gözden geçirin.

---

## 1. Zorunlu Manifest Permission'ları

`android/app/src/main/AndroidManifest.xml` içinde aşağıdaki permission'ların
tümünün bulunması zorunludur. Bir tanesi bile eksikse ABTO SDK çağrılarında
sessiz veya yıkıcı hatalar oluşur.

| Permission | Neden |
|---|---|
| `INTERNET` | SIP trafiği |
| `ACCESS_NETWORK_STATE` | Ağ değişikliklerini takip |
| `ACCESS_WIFI_STATE` | WiFi state polling (ABTO içinde) |
| `WAKE_LOCK` | SIP keep-alive |
| `RECORD_AUDIO` | Mikrofon erişimi |
| `MODIFY_AUDIO_SETTINGS` | Hoparlör/kulaklık geçişi |
| `FOREGROUND_SERVICE` | Arka planda SIP açık tutmak için |
| `FOREGROUND_SERVICE_PHONE_CALL` | Çağrı tipi foreground service (Android 14+) |
| `FOREGROUND_SERVICE_MICROPHONE` | Mikrofonlu foreground service (Android 14+) |
| `MANAGE_OWN_CALLS` | ConnectionService entegrasyonu için |
| **`USE_SIP`** | **ABTO `unregister()` ve `removeAllAccounts()` için ŞART** |
| `POST_NOTIFICATIONS` | Android 13+ bildirim izni |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Doze modunda SIP açık kalsın |
| `USE_FULL_SCREEN_INTENT` | Gelen çağrı tam ekran bildirimi (Android 14+) |

### ⚠️ USE_SIP — Ne Olduğunda Kullanıcı Yaşadı
ABTO SDK `AbtoPhone.unregister()` → `ABTOSipService.removeAllAccounts()` zinciri
**Android'in `USE_SIP` permission'ını runtime'da kontrol ediyor**. Permission yoksa
şu hata fırlar:

```
java.lang.SecurityException: Neither user XXXX nor current process has android.permission.USE_SIP.
  at org.abtollc.service.ABTOSipService$1.removeAllAccounts(ABTOSipService.java:228)
  at org.abtollc.sdk.AbtoPhone.unregister(AbtoPhone.java:2011)
```

Sonucu: ilk hesap kaydı 200 OK alıp başarılı görünür, ama hesap değiştiğinde veya
yeniden senkronizasyon gerekince `unregister()` patlar; UI "Hatalı" gösterir,
çağrı yapılamaz. **Bu permission'ı asla kaldırmayın.**

---

## 2. Notification Channel — Kilit Ekranı Aksiyonları

ABTO SDK, gelen çağrı bildirimini `abto_phone_call` channel ID'siyle yayınlar
ama channel'ı **lockscreen visibility ayarı olmadan** oluşturuyor. Sonuç: kilit
ekranında bildirim görünüyor ama "Cevapla / Reddet" butonları görünmüyor.

### Çözüm
`android/app/src/main/kotlin/com/example/inteliex_softphone/NotificationChannels.kt`
bu channel'ı ABTO'dan **önce** oluşturuyor:

- `lockscreenVisibility = Notification.VISIBILITY_PUBLIC`
- `IMPORTANCE_HIGH`
- Ringtone + vibration + `bypassDnd`

`NotificationChannels.ensureAll(context)` şu noktalardan çağrılıyor:
- `MainActivity.onCreate` (warm-start)
- `InteliexFirebaseMessagingService.onCreate` ve `onMessageReceived` (cold-start push)

> Channel id sabit: **`abto_phone_call`** — ABTO SDK içindeki
> `AbtoCallEventsReceiver.CHANEL_CALL_ID` ile birebir aynı olmak zorunda. SDK
> güncellenirse bu sabit kontrol edilmeli.

### ⚠️ Channel'a SOUND / VIBRATION Ekleme — Yasak
ABTO SDK gelen çağrıda **kendi ringtone ve titreşimini** çalıyor. Eğer channel'a
`setSound(...)` veya `enableVibration(true)` eklersen kilit ekranında bildirim
de zilini çalar → **çift zil**. Kilit açıkken full-screen intent direkt activity'i
açtığı için bildirim popup'ı çıkmaz; bu yüzden sorun sadece kilit ekranında belirir.

`NotificationChannels.kt` içinde mutlaka:
```kotlin
setSound(null, null)
enableVibration(false)
```

### ⚠️ Kanal Zaten Oluşturulmuşsa
Android, bir kez oluşturulmuş channel'ın `lockscreenVisibility`'sini programatik
olarak değiştirmeye izin vermez. ABTO bizden önce yaratırsa user'ın `lockscreenVisibility`'yi
manuel değiştirmesi (ya da uygulamayı silip yeniden kurması) gerekir. Bu yüzden
fix'i `ensureAll()` her cold-start'ta erken çalıştırıyoruz.

Ayrıca `AbtoCallEventsReceiver.kt` içine `setVisibility(Notification.VISIBILITY_PUBLIC)`
manuel olarak eklendi (belt-and-suspenders).

---

## 3. AndroidManifest'te Diğer Kritik Tanımlar

```xml
<application
    android:name="org.abtollc.voip.abto_voip_sdk.AbtoFlutterNotificationApplication"
    tools:replace="android:name" ... >
```

- **Application class**: `AbtoFlutterNotificationApplication` — ABTO bunu kullanır,
  değiştirilmemeli (`tools:replace="android:name"` ile Flutter default'unu ezeriz).
- **Activity launchMode**: `singleTop` — `onNewIntent` doğru tetiklensin diye.
- **Meta-data `AbtoVoipCallActivity`**: `com.example.inteliex_softphone.MainActivity` —
  ABTO gelen çağrıda hangi Activity'yi açacağını bu meta'dan okur.
- **`SipForegroundService`** + **`ABTOSipService`** → ikisi de
  `android:foregroundServiceType="phoneCall"` olmak zorunda (Android 14 yasası).

---

## 4. MainActivity Akışı — Gelen Çağrı Senaryosu

`MainActivity.kt` içinde **iki ayrı path** çalışır:

### a) Bildirim gövdesi / tam ekran intent tıklanırsa
ABTO `MainActivity`'i `onNewIntent` ile uyandırır. İçinde:
```kotlin
if (AbtoCallEventsReceiver.processIncomingCall(this, intent)) {
    turnScreenOnAndKeyguardOff()
}
```

### b) Bildirimdeki "Cevapla" butonuna basılırsa
ABTO bir broadcast yayınlar (`KEY_PICK_UP_AUDIO` ile). Çağrı native tarafta
otomatik cevaplanır ama Activity ön plana gelmez. Bu yüzden
`callEventReceiver` içinde:
```kotlin
bundle.getBoolean(AbtoCallEventsReceiver.KEY_PICK_UP_AUDIO, false) ||
bundle.getBoolean(AbtoCallEventsReceiver.KEY_PICK_UP_VIDEO, false) -> {
    val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
        addFlags(FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_SINGLE_TOP or FLAG_ACTIVITY_REORDER_TO_FRONT)
    }
    if (launchIntent != null) startActivity(launchIntent)
}
```
> Bu `startActivity` çağrısı, kullanıcı bildirim aksiyonu kaynaklı broadcast
> nedeniyle Android tarafından izin verilen "user-initiated activity start"
> kategorisine girer; aksi halde Android 12+ engellerdi.

### c) Çağrı bittiğinde
ABTO `CODE` ile bir broadcast yayınlar; biz `turnScreenOffAndKeyguardOn()`
çağırıp ekranı kapatıyoruz.

---

## 5. Re-registration Optimizasyonu

`lib/services/sip/abto_softphone_service.dart` içinde `syncAccounts` şu kontrolü
yapar:

```dart
// currentActive null ise (uygulamanın arka plandan yeniden başladığı durum)
// ama ABTO zaten kayıtlıysa, aynı hesap için gereksiz yeniden kayıt yapma.
if (currentActive == null && SipWrapper.wrapper.isRegistered) {
  _activeAccountId = nextActiveAccount.id;
  _emitRegistrationUpdate(
    SoftphoneRegistrationUpdate(
      accountId: nextActiveAccount.id,
      status: RegistrationStatus.registered,
    ),
  );
  return;
}
```

> Bu koruma `unregister/register` döngüsünden geçirmeden duruma `registered`
> der; özellikle ABTO çağrıyı cevapladıktan sonra Activity yeniden açılınca
> gereksiz re-register'ı engeller.

---

## 6. Channel Reset / Bilinen Yan Etkiler

- **Uninstall sonrası ilk açılış**: `NotificationChannels.ensureAll()` ilk
  çalıştığında channel doğru ayarlarla oluşur.
- **`flutter run` incremental install**: app data'yı korur. Eski channel ayarı
  varsa programatik düzeltilmez — kritik channel değişiklikleri sonrasında
  `adb -s <device> uninstall com.example.inteliex_softphone.debug` ile temiz kurulum yap.

---

## 7. Lisans

`AbtoSoftphoneService` içinde trial lisans gömülü
(`Trial_Flutter_Android-DB6F-BAE6-AE3AB24E-A131-4594-A0C7-2E77FF67701E`).
Production build için `--dart-define ABTO_LICENSE_ID=... ABTO_LICENSE_KEY=...`
geçilmeli.

---

## 8. SIP Digest Auth — Case Sensitive Şifre

SIP digest hash hesaplaması büyük/küçük harf duyarlıdır. Server kayıtlı şifreden
farklı bir case kullanıldığında **403 Forbidden** veya tekrar tekrar 401
döngüsü oluşur. Tipik hata: Asterisk `sesdata2025*` saklarken kullanıcının
`Sesdata2025*` girmesi.

---

## 9. Cold-Start Senaryosu — Optimistik Kayıt Durumu

Push veya kullanıcı tıklamasıyla cold-start olunca Flutter side `_isRegistered = false` ile başlar; ABTOSipService (native) zaten kayıtlıyken yeni `REGISTER` gönderirse server **408 Request Timeout** dönebiliyor (geçici). Bu yüzden UI'da `Hatalı → Kayıtlı` flicker oluyordu.

### Çözüm
`SoftphoneController` constructor'ında:
- Persisted/seed account'ları yüklenir yüklenmez `registrationStatus = registered` olarak işaretle
- `_registrationConfirmedAt[id] = now` set et → debounce ilk 20s içindeki transient `connecting/failed/disconnected` event'lerini "registered" olarak yutar

Ayrıca:
- `_buildSeedAccounts` ve `_ensureDebugSeedAccount` artık seed/migrate ederken `RegistrationStatus.registered` kullanıyor (eskiden `connecting`).
- `softphone_persistence.dart` içinde `_normalizeStoredAccount`'ta da default `registered` (şifre eksik değilse).

### ⚠️ Dart Lazy Iterable Tuzağı
`_replaceAccounts(_accounts.map((a) => a.copyWith(...)))` çağrısı **`_accounts.clear()` + `addAll`** içerdiği için lazy iterable boş listeyi okurdu → `Bad state: No element`. Constructor'da map sonucu `.toList(growable: false)` ile mutlaka materialize edilmeli.

---

## 10. Cevapla Akışı — Cold-Start + Notification

ABTO SDK içinde `AbtoCallEventsReceiver.buildIncomingCallNotification`:
- **`pickUpAudioPendingIntent`** → `getBroadcast` yerine **`getActivity`** kullanıyor (modifiye ettik).
- Intent doğrudan MainActivity'i hedefler, `ABTO_SERVICE_MARKER + KEY_PICK_UP_AUDIO + CALL_ID` ile.
- Sonuç: app öldü/uyuyor olsa bile "Cevapla" tek tıkla Activity'i açar.

`MainActivity` her iki giriş noktasında da intent'i işler:
- `onCreate(savedInstanceState)` — cold-start (initial intent `getIntent()` ile gelir, `onNewIntent` çağrılmaz)
- `onNewIntent(intent)` — warm-start (Activity zaten ayakta)

İkisi de `handleAbtoCallIntent(intent)` helper'ını çağırır.

### Flutter Side Senkronizasyonu

Native `answerCall` Flutter engine paused iken çalıştırılırsa, `incomingRinging` event'i Dart'a ulaşmayabilir. `AbtoSoftphoneService._onCallConnected` ve `SoftphoneController._markServiceCallConnected` `_activeCall == null` durumunda yeni `ActiveCall` **sentezler** → UI çağrıyı görür.

Ayrıca `_markServiceCallConnected` `_currentTabIndex = 0` set ederek otomatik olarak Dialer tab'ine geçer.

---

## 11. Notification Channel — Çift Zil Önlemi

ABTO SDK kendi ringtone ve titreşimini yönetiyor. `NotificationChannels.kt` içinde channel kurarken **mutlaka**:
```kotlin
setSound(null, null)
enableVibration(false)
```
Aksi halde kilit ekranında bildirim de zilini çalar → çift zil.

`lockscreenVisibility = Notification.VISIBILITY_PUBLIC` ile Cevapla/Reddet aksiyon butonları kilit ekranında görünür.

Channel ABTO'dan **önce** yaratılmak zorunda (Android `createNotificationChannel` mevcut channel'ı override etmez). `MainActivity.onCreate`, `InteliexFirebaseMessagingService.onCreate` ve `onMessageReceived`'da çağrılıyor.

---

## 12. Dev Auto-Seed (Fiziksel Cihaz)

Debug build'lerde elle hesap girmemek için:
```
flutter run -d <device> \
  --dart-define=DEV_PHYSICAL_SEED=true \
  --dart-define=DEV_SIP_USERNAME=elk-600-ext \
  --dart-define=DEV_SIP_PASSWORD='sesdata2025*'
```

Emülatörde flag olmadan da otomatik seed yapılır (default `elk-650-ext`).

---

## 13. Bilinen Açık Sorun — Tek Yönlü / Ses Yok

Server (146.185.164.21) public IP'de. Fiziksel telefon NAT arkasında, SDP'de **private IP** (`192.168.1.51`) advertise ediyor. Sunucu `rtp_symmetric=yes` yoksa RTP geriye gönderilemiyor.

Çözüm seçenekleri:
- **A) Server PJSIP config**: `direct_media=no`, `rewrite_contact=yes`, `force_rport=yes`, `rtp_symmetric=yes`
- **B) Client STUN**: account.stunServer'a `stun.l.google.com:19302` koy → SDP public IP advertise eder.

Tercih: A (server-side). Emülatörde çalışıyor olması, server config'in çoğu kısmının doğru olduğunu gösterir.

---

## 14. Kontrol Listesi (Yeni Cihaz / Yeni Build Öncesi)

- [ ] Manifest'te 14 permission'ın hepsi var mı? (özellikle `USE_SIP`)
- [ ] `AbtoFlutterNotificationApplication` aktif mi?
- [ ] Foreground service'lerin `phoneCall` tipi var mı?
- [ ] `NotificationChannels.ensureAll()` çağrıları korunmuş mu?
- [ ] `MainActivity` `singleTop` launch mode'da mı?
- [ ] `AbtoVoipCallActivity` meta-data'sı MainActivity'i mi gösteriyor?
- [ ] Battery optimization muafiyeti ekran/akışı ekranda var mı?
- [ ] OnePlus / Xiaomi / Oppo gibi OEM'lerde "Otomatik başlatma" izni manuel verilmeli mi?
