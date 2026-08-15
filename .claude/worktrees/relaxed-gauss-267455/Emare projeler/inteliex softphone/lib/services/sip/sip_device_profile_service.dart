import 'package:flutter/services.dart';

class SipDeviceProfileService {
  SipDeviceProfileService()
      : _channel = const MethodChannel('inteliex_softphone/foreground');

  final MethodChannel _channel;

  Future<String> getDeviceProfile() async {
    try {
      final profile = await _channel.invokeMethod<String>('getDeviceProfile');
      if (profile == 'emulator' || profile == 'physical') {
        return profile!;
      }
    } on MissingPluginException {
      // Non-Android or channel unavailable.
    } on PlatformException {
      // Fallback to unknown on platform errors.
    }

    return 'unknown';
  }
}
