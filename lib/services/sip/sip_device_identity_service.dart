import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SipDeviceIdentityService {
  static const String _deviceIdKey = 'inteliex.device_instance_id';
  static const String _deviceIdLegacyKey = 'inteliex.device_instance_id';

  SipDeviceIdentityService({
    MethodChannel? channel,
    FlutterSecureStorage? secureStorage,
  })  : _channel = channel ?? const MethodChannel('inteliex_softphone/foreground'),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final MethodChannel _channel;
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;
  String? _cachedDeviceId;

  Future<String> getOrCreateDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    final prefs = await _getPrefs();
    final nativeStableId = await _readNativeStableDeviceId();
    if (nativeStableId != null) {
      await _persistDeviceId(nativeStableId, prefs);
      return nativeStableId;
    }

    final secureStored = await _secureStorage.read(key: _deviceIdKey);
    final secureTrimmed = secureStored?.trim();
    if (secureTrimmed != null && secureTrimmed.isNotEmpty) {
      await _persistDeviceId(secureTrimmed, prefs);
      return secureTrimmed;
    }

    final legacyStored = prefs.getString(_deviceIdLegacyKey)?.trim();
    if (legacyStored != null && legacyStored.isNotEmpty) {
      await _persistDeviceId(legacyStored, prefs);
      return legacyStored;
    }

    final generated = _generateDeviceId();
    await _persistDeviceId(generated, prefs);
    return generated;
  }

  Future<String?> _readNativeStableDeviceId() async {
    try {
      final value = await _channel.invokeMethod<String>('getStableDeviceId');
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    } on MissingPluginException {
      // Non-Android platform or unavailable channel.
    } on PlatformException {
      // Fallback to storage-based IDs.
    }

    return null;
  }

  Future<void> _persistDeviceId(String value, SharedPreferences prefs) async {
    _cachedDeviceId = value;
    await _secureStorage.write(key: _deviceIdKey, value: value);
    await prefs.setString(_deviceIdLegacyKey, value);
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _generateDeviceId() {
    final randomPart = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final timePart = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return 'sp-$timePart-$randomPart';
  }
}
