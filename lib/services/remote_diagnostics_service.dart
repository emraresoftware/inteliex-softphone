import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_environment.dart';

/// Çevrimdışı çalışabilen küçük uzaktan tanılama kuyruğu.
/// Parola, yetkilendirme başlığı, rehber ve ses içeriği kabul edilmez.
class RemoteDiagnosticsService {
  RemoteDiagnosticsService._();

  static final instance = RemoteDiagnosticsService._();
  static const _queueKey = 'inteliex.remote_diagnostics.queue.v1';
  static const _channel = MethodChannel('inteliex_softphone/foreground');
  static const _maxQueuedEvents = 250;

  bool _flushing = false;
  Map<String, Object?>? _device;

  bool get enabled => AppEnvironment.diagnosticsToken.trim().isNotEmpty;

  Future<void> record(
    String type, {
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    if (!enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? <String>[];
      queue.add(jsonEncode(<String, Object?>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'type': _safe(type, 64),
        'device': await _deviceMetadata(),
        'details': _sanitize(details),
      }));
      if (queue.length > _maxQueuedEvents) {
        queue.removeRange(0, queue.length - _maxQueuedEvents);
      }
      await prefs.setStringList(_queueKey, queue);
      unawaited(flush());
    } catch (error) {
      debugPrint('Remote diagnostics enqueue failed: $error');
    }
  }

  Future<void> flush() async {
    if (!enabled || _flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawQueue = prefs.getStringList(_queueKey) ?? <String>[];
      if (rawQueue.isEmpty) return;
      final batch = rawQueue.take(40).toList(growable: false);
      final response = await http
          .post(
            Uri.parse(AppEnvironment.diagnosticsUrl),
            headers: <String, String>{
              HttpHeaders.authorizationHeader:
                  'Bearer ${AppEnvironment.diagnosticsToken}',
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'events': batch.map(jsonDecode).toList(growable: false),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final current = prefs.getStringList(_queueKey) ?? <String>[];
      final removeCount = batch.length.clamp(0, current.length);
      current.removeRange(0, removeCount);
      await prefs.setStringList(_queueKey, current);
      if (current.isNotEmpty) unawaited(flush());
    } catch (error) {
      debugPrint('Remote diagnostics flush deferred: $error');
    } finally {
      _flushing = false;
    }
  }

  Future<Map<String, Object?>> _deviceMetadata() async {
    final cached = _device;
    if (cached != null) return cached;
    final package = await PackageInfo.fromPlatform();
    String deviceId = '';
    String manufacturer = '';
    try {
      deviceId = await _channel.invokeMethod<String>('getStableDeviceId') ?? '';
      manufacturer =
          await _channel.invokeMethod<String>('getDeviceManufacturer') ?? '';
    } catch (_) {}
    return _device = <String, Object?>{
      'id': _safe(deviceId, 64),
      'manufacturer': _safe(manufacturer, 48),
      'platform': Platform.operatingSystem,
      'platformVersion': _safe(Platform.operatingSystemVersion, 120),
      'package': package.packageName,
      'version': package.version,
      'build': package.buildNumber,
    };
  }

  static Map<String, Object?> _sanitize(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries.take(40)) {
      final key = _safe(entry.key, 64);
      if (RegExp('password|secret|authorization|token', caseSensitive: false)
          .hasMatch(key)) {
        continue;
      }
      final value = entry.value;
      output[key] = switch (value) {
        null || bool() || num() => value,
        _ => _safe(value.toString(), 500),
      };
    }
    return output;
  }

  static String _safe(String value, int maxLength) {
    final clean = value.replaceAll(RegExp(r'[\r\n\x00-\x08]'), ' ').trim();
    return clean.length <= maxLength ? clean : clean.substring(0, maxLength);
  }
}
