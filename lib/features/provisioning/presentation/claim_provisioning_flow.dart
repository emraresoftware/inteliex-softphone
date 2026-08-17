import 'package:flutter/material.dart';

import '../../../services/provisioning/claim_provisioning.dart';
import '../../../services/sip/softphone_controller.dart';
import 'qr_provision_screen.dart';

/// QR ile kurulum akisini (parse -> claim -> provisionFromClaim) yoneten
/// yardimci fonksiyonlar. Hem "QR ile Kur" butonu hem de deeplink dinleyici
/// ayni akisi kullanir; hatalar SnackBar/dialog ile kullaniciya gosterilir.
class ClaimProvisioningFlow {
  ClaimProvisioningFlow._();

  /// Kamerayi acar, QR okur ve okunan icerigi provision eder.
  /// Kullanici iptal ederse sessizce doner.
  static Future<void> startFromCamera(
    BuildContext context,
    SoftphoneController controller,
  ) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const QrProvisionScreen(),
        fullscreenDialog: true,
      ),
    );

    if (raw == null || raw.trim().isEmpty) {
      return; // kullanici iptal etti
    }

    if (!context.mounted) {
      return;
    }

    await handleProvisionString(context, controller, raw);
  }

  /// Deeplink veya QR'dan gelen ham URI/string'i uctan uca isler.
  /// Uygun bir Navigator context'i ile cagrilmalidir.
  static Future<void> handleProvisionString(
    BuildContext context,
    SoftphoneController controller,
    String raw,
  ) async {
    final ProvisionRequest request;
    try {
      request = parseProvisionString(raw);
    } on ClaimProvisioningException catch (error) {
      _showError(context, error.message);
      return;
    } catch (error) {
      _showError(context, 'QR icerigi cozumlenemedi: $error');
      return;
    }

    await handleProvisionRequest(context, controller, request);
  }

  /// Ayristirilmis [ProvisionRequest] ile claim + hesap ekleme.
  static Future<void> handleProvisionRequest(
    BuildContext context,
    SoftphoneController controller,
    ProvisionRequest request,
  ) async {
    _showProgress(context, 'Kurulum dogrulaniyor...');

    final service = ClaimProvisioningService();
    try {
      final deviceName = await controller.resolveProvisionDeviceName();
      final config = await service.claim(request, deviceName: deviceName);
      await controller.provisionFromClaim(config);

      if (!context.mounted) {
        return;
      }
      _dismissProgress(context);
      _showSuccess(
        context,
        '${config.name.isNotEmpty ? config.name : config.user} hesabi eklendi. '
        'Baglaniliyor...',
      );
    } on ClaimProvisioningException catch (error) {
      if (!context.mounted) {
        return;
      }
      _dismissProgress(context);
      _showError(context, error.message);
    } on ArgumentError catch (error) {
      if (!context.mounted) {
        return;
      }
      _dismissProgress(context);
      _showError(context, error.message?.toString() ?? 'Hesap eklenemedi.');
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      _dismissProgress(context);
      _showError(context, 'Kurulum sirasinda beklenmeyen hata: $error');
    } finally {
      service.close();
    }
  }

  static bool _progressShown = false;

  static void _showProgress(BuildContext context, String message) {
    _progressShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void _dismissProgress(BuildContext context) {
    if (!_progressShown) {
      return;
    }
    _progressShown = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  static void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
