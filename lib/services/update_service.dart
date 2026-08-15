import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_environment.dart';

enum UpdateCheckResult {
  updateAvailable,
  upToDate,
  failed,
  unsupported,
}

class UpdateService {
  static const _platform = MethodChannel('inteliex_softphone/foreground');

  /// Softphone OTA — Asistan vb. diger mobil uygulamalardan ayri endpoint.
  static const String _softphoneVersionPath =
      '/api/v1/updates/softphone/version';

  static Future<UpdateCheckResult> checkForUpdates(BuildContext context) async {
    if (!Platform.isAndroid) return UpdateCheckResult.unsupported;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installedVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      final installedPackageName = packageInfo.packageName;

      final baseUrl = AppEnvironment.updateBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final versionUri = Uri.parse('$baseUrl$_softphoneVersionPath');

      debugPrint(
        'Update check: pkg=$installedPackageName '
        'installed=$installedVersionCode url=$versionUri',
      );

      final response = await http
          .get(versionUri)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        debugPrint(
          'Softphone OTA endpoint not found (404). '
          'Sunucuda $_softphoneVersionPath yapilandirilmali.',
        );
        return UpdateCheckResult.failed;
      }

      if (response.statusCode != 200) {
        debugPrint('Update check failed: HTTP ${response.statusCode}');
        return UpdateCheckResult.failed;
      }

      final data = jsonDecode(response.body);
      if (data is! Map || data['success'] != true) {
        return UpdateCheckResult.failed;
      }

      final latestVersionCode = _readInt(data['versionCode']);
      final latestVersionName = data['versionName']?.toString() ?? '?';
      final downloadUrl = _normalizeDownloadUrl(
        data['downloadUrl']?.toString() ?? '',
        baseUrl,
      );
      final releaseNote = data['releaseNote']?.toString() ??
          data['changelog']?.toString() ?? '';

      if (latestVersionCode == null || downloadUrl.isEmpty) {
        debugPrint('Update payload incomplete');
        return UpdateCheckResult.failed;
      }

      debugPrint(
        'Update check: installed=$installedVersionCode latest=$latestVersionCode',
      );

      if (latestVersionCode <= installedVersionCode) {
        return UpdateCheckResult.upToDate;
      }

      if (context.mounted) {
        _showUpdateDialog(
          context,
          latestVersionName: latestVersionName,
          latestVersionCode: latestVersionCode,
          downloadUrl: downloadUrl,
          installedVersionCode: installedVersionCode,
          expectedPackageName: installedPackageName,
          releaseNote: releaseNote,
        );
      }
      return UpdateCheckResult.updateAvailable;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return UpdateCheckResult.failed;
    }
  }

  static String _normalizeDownloadUrl(String raw, String baseUrl) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '$baseUrl/api/v1/updates/softphone/download';
    }

    final base = Uri.parse(baseUrl);
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return '$baseUrl/api/v1/updates/softphone/download';
    }

    if (!uri.hasScheme) {
      final path = uri.path.isEmpty ? '/api/v1/updates/softphone/download' : uri.path;
      final resolvedPath = path.startsWith('/') ? path : '/$path';
      return base.replace(
        path: resolvedPath,
        query: uri.hasQuery ? uri.query : null,
      ).toString();
    }

    final path = uri.path.isEmpty ? '/api/v1/updates/softphone/download' : uri.path;
    return uri.replace(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: path,
    ).toString();
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String latestVersionName,
    required int latestVersionCode,
    required String downloadUrl,
    required int installedVersionCode,
    required String expectedPackageName,
    required String releaseNote,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        double progress = 0;
        bool downloading = false;
        String statusText = '';

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Guncelleme Mevcut'),
                  Text(
                    'v$latestVersionName ($latestVersionCode)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF2E7D6D),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (releaseNote.trim().isNotEmpty) ...[
                    const Text(
                      'Bu surumdeki yenilikler:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      releaseNote.trim(),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Yuklu surum: $installedVersionCode → Yeni surum: $latestVersionCode',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7B8A84)),
                  ),
                  if (statusText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(statusText, style: const TextStyle(fontSize: 12)),
                  ],
                  if (downloading) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text('%${(progress * 100).toStringAsFixed(0)} indiriliyor...'),
                  ],
                ],
              ),
              actions: [
                if (!downloading) ...[
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Daha Sonra'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      setState(() {
                        downloading = true;
                        statusText = 'Guncelleme indiriliyor...';
                      });

                      try {
                        final canInstall = await _platform.invokeMethod<bool>(
                              'canRequestPackageInstalls',
                            ) ??
                            false;
                        if (!canInstall) {
                          setState(() {
                            statusText =
                                'Bilinmeyen uygulama kurma izni gerekli.\n'
                                'Lutfen acilan ayar ekraninda bu uygulamaya izin verin.';
                          });
                          await _platform.invokeMethod(
                            'openInstallPermissionSettings',
                          );

                          // İzin verilene kadar bekle (max 60 saniye)
                          var granted = false;
                          for (var i = 0; i < 60; i++) {
                            await Future<void>.delayed(
                              const Duration(seconds: 1),
                            );
                            granted =
                                await _platform.invokeMethod<bool>(
                                  'canRequestPackageInstalls',
                                ) ??
                                false;
                            if (granted) break;
                          }

                          if (!granted) {
                            setState(() {
                              downloading = false;
                              statusText =
                                  'İzin verilmedi. Ayarlar > Uygulamalar > '
                                  'inteliex softphone > Bilinmeyen uygulama kur > Etkinleştir';
                            });
                            return;
                          }
                        }

                        // Android FileProvider'ın erişebildiği cache dizinini kullan.
                        // Directory.systemTemp (/data/local/tmp) FileProvider kapsamı dışında.
                        final cacheDir = await getTemporaryDirectory();
                        final apkFile =
                            File('${cacheDir.path}/inteliex-softphone-update.apk');
                        if (await apkFile.exists()) {
                          await apkFile.delete();
                        }

                        final client = http.Client();
                        try {
                          final request =
                              http.Request('GET', Uri.parse(downloadUrl));
                          final response = await client.send(request);

                          if (response.statusCode != 200) {
                            throw StateError(
                              'Indirme basarisiz (HTTP ${response.statusCode})',
                            );
                          }

                          final contentLength = response.contentLength;
                          var downloaded = 0;

                          final sink = apkFile.openWrite();
                          try {
                            await response.stream.forEach((chunk) {
                              sink.add(chunk);
                              downloaded += chunk.length;
                              // Sunucu Content-Length gondermediyse belirsiz
                              // ilerleme goster (progress > 1 olmasin).
                              if (contentLength != null && contentLength > 0) {
                                setState(() {
                                  progress = (downloaded / contentLength)
                                      .clamp(0.0, 1.0)
                                      .toDouble();
                                });
                              }
                            });
                            await sink.flush();
                          } finally {
                            await sink.close();
                          }
                        } finally {
                          client.close();
                        }

                        final apkInfo =
                            await _platform.invokeMethod<Map<Object?, Object?>>(
                          'getApkPackageInfo',
                          {'filePath': apkFile.path},
                        );

                        final apkPackage =
                            apkInfo?['packageName']?.toString() ?? '';
                        final apkVersionCode =
                            _readInt(apkInfo?['versionCode']) ?? 0;

                        if (apkPackage.isEmpty) {
                          throw StateError(
                            'APK okunamadi. Dosya bozuk veya gecersiz olabilir.',
                          );
                        }

                        if (apkPackage != expectedPackageName) {
                          setState(() {
                            downloading = false;
                            statusText =
                                'Sunucudaki paket bu uygulamaya ait degil '
                                '($apkPackage). Softphone OTA sunucu yapilandirmasi '
                                'kontrol edilmeli.';
                          });
                          return;
                        }

                        if (apkVersionCode <= installedVersionCode) {
                          setState(() {
                            downloading = false;
                            statusText =
                                'Indirilen surum ($apkVersionCode) zaten yuklu '
                                'veya daha eski ($installedVersionCode).';
                          });
                          return;
                        }

                        setState(() {
                          statusText =
                              'Indirme tamamlandi (surum $apkVersionCode). '
                              'Kurulum ekranini onaylayin.';
                        });

                        final launched = await _platform.invokeMethod<bool>(
                              'installApk',
                              {'filePath': apkFile.path},
                            ) ??
                            false;

                        if (!launched) {
                          setState(() {
                            downloading = false;
                            statusText =
                                'Kurulum baslatilamadi. APK el ile kurulabilir: '
                                '${apkFile.path}';
                          });
                          return;
                        }

                        setState(() {
                          downloading = false;
                          statusText =
                              'Kurulum ekrani acildi. Yuklemeyi onayladiktan sonra '
                              'uygulama yeni surumle acilacak.';
                        });
                      } catch (e) {
                        setState(() {
                          downloading = false;
                          statusText = 'Hata: $e';
                        });
                      }
                    },
                    child: const Text('Guncelle'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
