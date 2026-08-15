import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app_state_scope.dart';
import '../../../core/config/app_constants.dart';
import '../../../services/sip/softphone_controller.dart';
import '../../../services/update_service.dart';

const _platformChannel = MethodChannel('inteliex_softphone/foreground');

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final selectedAccount = controller.selectedAccount;
        final diagnosticsText = _buildDiagnosticsText(controller);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Genel ayarlar',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Uygulama genel durumu, tanilama ve hizli destek islemleri.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF51625C),
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Baglanti durumu',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Uygulama',
                      value: AppConstants.appName,
                    ),
                    const _AppVersionRow(),
                    _InfoRow(
                      label: 'Aktif hesap',
                      value: selectedAccount?.aor ?? 'Secili hesap yok',
                    ),
                    _InfoRow(
                      label: 'Kayit ozeti',
                      value: controller.registrationSummary,
                    ),
                    _InfoRow(
                      label: 'Durum satiri',
                      value: controller.statusLine,
                    ),
                    if (selectedAccount != null) ...[
                      _InfoRow(
                        label: 'Transport',
                        value: selectedAccount.transport.name.toUpperCase(),
                      ),
                      _InfoRow(
                        label: 'Sunucu',
                        value: selectedAccount.domain,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hizli islemler',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: selectedAccount == null
                              ? null
                              : () => controller.reconnectAccount(
                                    selectedAccount.id,
                                  ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Yeniden kayitlan'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await controller.refreshContactDirectory();
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Rehber yenileme tetiklendi.'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.contacts_rounded),
                          label: const Text('Rehberi yenile'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final result =
                                await UpdateService.checkForUpdates(context);
                            final message = switch (result) {
                              UpdateCheckResult.updateAvailable => null,
                              UpdateCheckResult.upToDate =>
                                'Uygulama guncel; yeni surum yok.',
                              UpdateCheckResult.failed =>
                                'Guncelleme sunucusuna ulasilamadi.',
                              UpdateCheckResult.unsupported =>
                                'Guncelleme denetimi yalnizca Android icin gecerli.',
                            };
                            if (message != null) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(message)),
                              );
                            }
                          },
                          icon: const Icon(Icons.system_update_alt_rounded),
                          label: const Text('Guncellemeleri denetle'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: diagnosticsText),
                            );
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Tanilama bilgisi kopyalandi.'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_all_rounded),
                          label: const Text('Tanilamayi kopyala'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _SystemSettingsCard(),
          ],
        );
      },
    );
  }
}

String _buildDiagnosticsText(SoftphoneController controller) {
  final selectedAccount = controller.selectedAccount;
  final accountPart = selectedAccount == null
      ? 'hesap=none'
      : 'hesap=${selectedAccount.aor}, transport=${selectedAccount.transport.name.toUpperCase()}, domain=${selectedAccount.domain}, stun=${selectedAccount.stunServer.isEmpty ? 'kapali' : selectedAccount.stunServer}';
  return 'durum=${controller.statusLine}\n'
      'kayit=${controller.registrationSummary}\n'
      '$accountPart';
}

class _AppVersionRow extends StatelessWidget {
  const _AppVersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final value = info == null
            ? '...'
            : 'v${info.version} (build ${info.buildNumber})';
        return _InfoRow(label: 'Surum', value: value);
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF51625C),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _SystemSettingsCard extends StatefulWidget {
  const _SystemSettingsCard();

  @override
  State<_SystemSettingsCard> createState() => _SystemSettingsCardState();
}

class _SystemSettingsCardState extends State<_SystemSettingsCard> {
  bool _loading = true;
  bool _notificationGranted = false;
  bool _microphoneGranted = false;
  bool _batteryOptimizationIgnored = false;

  @override
  void initState() {
    super.initState();
    _refreshSystemState();
  }

  Future<void> _refreshSystemState() async {
    bool notificationGranted = false;
    bool microphoneGranted = false;
    bool batteryOptimizationIgnored = false;

    try {
      notificationGranted = await _platformChannel.invokeMethod<bool>(
            'isNotificationPermissionGranted',
          ) ??
          false;
      microphoneGranted = await _platformChannel.invokeMethod<bool>(
            'isMicrophonePermissionGranted',
          ) ??
          false;
      batteryOptimizationIgnored = await _platformChannel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      // Not available on this platform.
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _notificationGranted = notificationGranted;
      _microphoneGranted = microphoneGranted;
      _batteryOptimizationIgnored = batteryOptimizationIgnored;
      _loading = false;
    });
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      await _platformChannel.invokeMethod<bool>('requestMicrophonePermission');
      await _refreshSystemState();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mikrofon izni istenemedi.')),
      );
    }
  }

  Future<void> _openAppPermissionSettings() async {
    try {
      await _platformChannel.invokeMethod<bool>('openAppPermissionSettings');
      await _refreshSystemState();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uygulama izin ayari acilamadi.')),
      );
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _platformChannel.invokeMethod<bool>('openNotificationSettings');
      await _refreshSystemState();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim ayari acilamadi.')),
      );
    }
  }

  Future<void> _openBatterySettings() async {
    try {
      await _platformChannel.invokeMethod<bool>('openBatteryOptimizationSettings');
      await _refreshSystemState();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pil ayari acilamadi.')),
      );
    }
  }

  Future<void> _openOemAutostartSettings() async {
    try {
      await _platformChannel.invokeMethod<bool>('openOemAutostartSettings');
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Otomatik baslatma ayari acilamadi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sistem ayarlari',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Bildirim izni',
              value: _loading
                  ? 'Kontrol ediliyor...'
                  : (_notificationGranted ? 'Acik' : 'Kapali'),
            ),
            _InfoRow(
              label: 'Mikrofon izni',
              value: _loading
                  ? 'Kontrol ediliyor...'
                  : (_microphoneGranted ? 'Acik' : 'Kapali'),
            ),
            _InfoRow(
              label: 'Pil optimizasyonu',
              value: _loading
                  ? 'Kontrol ediliyor...'
                  : (_batteryOptimizationIgnored
                       ? 'Muaf (onerilen)'
                       : 'Kisitli'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _requestMicrophonePermission,
                  icon: const Icon(Icons.mic_none_rounded),
                  label: const Text('Mikrofon izni iste'),
                ),
                OutlinedButton.icon(
                  onPressed: _openNotificationSettings,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Bildirim ayarini ac'),
                ),
                OutlinedButton.icon(
                  onPressed: _openBatterySettings,
                  icon: const Icon(Icons.battery_alert_outlined),
                  label: const Text('Pil optimizasyon ayari'),
                ),
                OutlinedButton.icon(
                  onPressed: _openOemAutostartSettings,
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('Otomatik baslatma ayari'),
                ),
                TextButton.icon(
                  onPressed: _openAppPermissionSettings,
                  icon: const Icon(Icons.settings_applications_outlined),
                  label: const Text('Uygulama izinleri'),
                ),
                TextButton.icon(
                  onPressed: _refreshSystemState,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Durumu yenile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
