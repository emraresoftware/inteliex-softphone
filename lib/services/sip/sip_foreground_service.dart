import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android foreground service köprüsü.
///
/// SIP oturumunun arka planda ayakta kalabilmesi için `phoneCall` türünde bir
/// foreground service başlatır. Android dışındaki platformlarda no-op.
class SipForegroundService {
  SipForegroundService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'inteliex_softphone/foreground';

  final MethodChannel _channel;
  bool _running = false;

  bool get isRunning => _running;

  bool get _isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> start({String? title, String? text}) async {
    if (!_isSupported) return;
    try {
      await _channel.invokeMethod<void>('start', <String, Object?>{
        if (title != null) 'title': title,
        if (text != null) 'text': text,
      });
      _running = true;
    } on PlatformException catch (error, stack) {
      debugPrint('SipForegroundService.start failed: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> stop() async {
    if (!_isSupported) return;
    if (!_running) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (error, stack) {
      debugPrint('SipForegroundService.stop failed: $error');
      debugPrintStack(stackTrace: stack);
    } finally {
      _running = false;
    }
  }
}
