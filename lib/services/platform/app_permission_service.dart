import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android kurulum izinleri — SIP/medya baslamadan once native taraftan istenir.
/// iOS'ta izinler kullanim aninda (mikrofon vb.) sistem tarafindan sorulur;
/// bu kanal yalnizca Android MainActivity'de implement edildigi icin diger
/// platformlarda dogrudan true donulur, aksi halde kurulum ekrani kilitlenir.
class AppPermissionService {
  AppPermissionService._();

  static const MethodChannel _channel =
      MethodChannel('inteliex_softphone/foreground');

  static bool get _hasNativePermissionChannel =>
      !kIsWeb && Platform.isAndroid;

  static Future<bool> areRequiredPermissionsGranted() async {
    if (!_hasNativePermissionChannel) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'areRequiredPermissionsGranted',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Eksik runtime izinleri tek dialogda ister. Tamami verildiyse true.
  static Future<bool> ensureRequiredPermissions() async {
    if (!_hasNativePermissionChannel) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('ensureRequiredPermissions') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> ensureBatteryOptimizationExemption() async {
    if (!_hasNativePermissionChannel) {
      return true;
    }
    try {
      final ignored = await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          true;
      if (ignored) {
        return true;
      }
      return await _channel.invokeMethod<bool>(
            'openBatteryOptimizationSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAppPermissionSettings() async {
    if (!_hasNativePermissionChannel) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('openAppPermissionSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }
}
