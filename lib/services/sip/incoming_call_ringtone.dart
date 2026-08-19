import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Gelen cagri zil sesi.
///
/// ABTO SDK'nin kendi bildirim kanali (`abto_phone_call`) uygulamada
/// `setSound(null, null)` ile sessiz olusturuluyor (bkz. NotificationChannels.kt)
/// ve Android 8+'da kanal sesi olusturulduktan sonra kod ile degistirilemiyor.
/// Sonuc: cagri ekranda gorunuyor ama telefon calmiyordu. Zil sesini bu yuzden
/// uygulama kendisi calar; boylece SDK/kanal davranisindan bagimsiz olur.
///
/// Cihaz sessiz veya titresim modundaysa native taraf calmaz (titresim zaten
/// bildirim kanalindan geliyor).
class IncomingCallRingtone {
  IncomingCallRingtone._();

  static const _channel = MethodChannel('inteliex_softphone/foreground');
  static bool _ringing = false;

  static Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    try {
      await _channel.invokeMethod<void>('startRingtone');
    } catch (error) {
      _ringing = false;
      debugPrint('Zil sesi baslatilamadi: $error');
    }
  }

  static Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _channel.invokeMethod<void>('stopRingtone');
    } catch (error) {
      debugPrint('Zil sesi durdurulamadi: $error');
    }
  }
}
