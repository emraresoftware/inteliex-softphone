import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SipPushTokenService {
  SipPushTokenService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'inteliex_softphone/foreground';

  final MethodChannel _channel;

  bool get _isSupported => !kIsWeb && Platform.isAndroid;

  Future<String?> getFcmToken() async {
    if (!_isSupported) {
      return null;
    }
    try {
      final token = await _channel.invokeMethod<String>('getFcmToken');
      final trimmed = token?.trim();
      if (trimmed == null || trimmed.isEmpty) {
        return null;
      }
      return trimmed;
    } on PlatformException catch (error, stack) {
      debugPrint('SipPushTokenService.getFcmToken failed: $error');
      debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Native taraf bir incoming call intent ile MainActivity'i açtığında
  /// SharedPreferences'a yazdığı çağrı bilgisini bir kez okur ve temizler.
  /// Flutter cold-start sırasında kaybolan onIncomingCall event'i yerine
  /// kullanılır.
  Future<Map<String, dynamic>?> consumePendingIncomingCall() async {
    if (!_isSupported) return null;
    try {
      final result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('consumePendingIncomingCall');
      if (result == null) return null;
      return result.map((key, value) => MapEntry(key.toString(), value));
    } on PlatformException catch (error) {
      debugPrint('consumePendingIncomingCall failed: $error');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> consumePushDiagnostics() async {
    if (!_isSupported) return const <Map<String, dynamic>>[];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'consumePushDiagnostics',
      );
      return (result ?? const <dynamic>[])
          .whereType<Map<dynamic, dynamic>>()
          .map((item) => item.map(
                (key, value) => MapEntry(key.toString(), value),
              ))
          .toList(growable: false);
    } on PlatformException catch (error) {
      debugPrint('consumePushDiagnostics failed: $error');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> getPushEnvironment() async {
    if (!_isSupported) return const <String, dynamic>{};
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPushEnvironment',
      );
      return (result ?? const <dynamic, dynamic>{}).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } on PlatformException catch (error) {
      debugPrint('getPushEnvironment failed: $error');
      return const <String, dynamic>{};
    }
  }
}
