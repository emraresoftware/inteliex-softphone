import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_constants.dart';
import '../core/models/active_call.dart';
import '../features/accounts/presentation/accounts_page.dart';
import '../features/contacts/presentation/contacts_page.dart';
import '../features/dialer/presentation/dialer_page.dart';
import '../features/history/presentation/history_page.dart';
import '../features/settings/presentation/general_settings_page.dart';
import '../services/sip/softphone_controller.dart';
import '../services/update_service.dart';
import '../services/remote_diagnostics_service.dart';
import '../services/sip/sip_push_token_service.dart';
import 'app_state_scope.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  bool _checkedForUpdates = false;
  bool _checkedOemAutostart = false;

  SoftphoneController? _controller;
  bool _proximityActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(RemoteDiagnosticsService.instance.record(
      'app_lifecycle',
      details: const <String, Object?>{'state': 'started'},
    ));
    unawaited(_reportPushDiagnostics());
    // AppStateScope'a ilk frame'den once erisilmemeli.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumePendingDialNumber());
    });
  }

  /// Telefonun "bununla ara" secenegi / tel: baglantisi ile uygulama acildiysa
  /// numarayi tuslama ekranina getirir. Cagriyi kullanici baslatir.
  Future<void> _consumePendingDialNumber() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      const channel = MethodChannel('inteliex_softphone/foreground');
      final number =
          (await channel.invokeMethod<String>('consumePendingDialNumber'))
              ?.trim();
      if (number == null || number.isEmpty || !mounted) return;
      AppStateScope.of(context).fillDialedNumber(number);
    } catch (error) {
      debugPrint('Gelen numara alinamadi: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(RemoteDiagnosticsService.instance.record(
      'app_lifecycle',
      details: <String, Object?>{'state': state.name},
    ));
    if (state == AppLifecycleState.resumed) {
      unawaited(RemoteDiagnosticsService.instance.flush());
      unawaited(_reportPushDiagnostics());
      unawaited(_consumePendingDialNumber());
    }
  }

  Future<void> _reportPushDiagnostics() async {
    final push = SipPushTokenService();
    final environment = await push.getPushEnvironment();
    if (environment.isNotEmpty) {
      await RemoteDiagnosticsService.instance.record(
        'push_environment',
        details: environment.cast<String, Object?>(),
      );
    }
    final events = await push.consumePushDiagnostics();
    for (final event in events) {
      await RemoteDiagnosticsService.instance.record(
        'push_event',
        details: event.cast<String, Object?>(),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = AppStateScope.of(context);
    if (controller != _controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _setProximityLock(false);
    super.dispose();
  }

  void _onControllerChanged() {
    final call = _controller?.activeCall;
    // Yakınlık sensörü: bağlı arama varsa, hoparlör kapalıysa aktif et
    final shouldActivate = call != null &&
        call.isConnected &&
        !call.isSpeaker &&
        !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS);
    _setProximityLock(shouldActivate);
  }

  void _setProximityLock(bool active) {
    if (active == _proximityActive) return;
    _proximityActive = active;
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      // Android: PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK
      const channel = MethodChannel('inteliex_softphone/foreground');
      channel.invokeMethod<void>(
          'setProximityLock', {'active': active}).catchError((_) {});
    } else if (Platform.isIOS) {
      // iOS: UIDevice.current.isProximityMonitoringEnabled
      const channel = MethodChannel('inteliex_softphone/proximity');
      channel.invokeMethod<void>(
          'setActive', {'active': active}).catchError((_) {});
    }
  }

  Future<void> _checkAndShowOemAutostartPrompt(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyShown =
          prefs.getBool('inteliex.oem_autostart_prompt_shown') ?? false;
      if (alreadyShown) return;

      const platformChannel = MethodChannel('inteliex_softphone/foreground');
      final manufacturer =
          (await platformChannel.invokeMethod<String>('getDeviceManufacturer'))
                  ?.toLowerCase() ??
              '';

      final oemBrands = [
        'xiaomi',
        'oppo',
        'oneplus',
        'huawei',
        'realme',
        'vivo',
        'meizu'
      ];
      final isOem = oemBrands.any((brand) => manufacturer.contains(brand));

      if (isOem && context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            return AlertDialog(
              title: const Text('Arka Plan Çalışma Ayarı'),
              content: Text(
                  'Telefonunuzun markası (${manufacturer.toUpperCase()}) arka plandaki uygulamaları kısıtlamaktadır. '
                  'Ekran kapalıyken çağrıları kaçırmamak için lütfen açılacak ayarlar sayfasından '
                  'uygulamaya "Otomatik Başlatma" (Auto-start) ve "Arka Planda Çalışma" izinlerini verin.'),
              actions: [
                TextButton(
                  onPressed: () async {
                    await prefs.setBool(
                        'inteliex.oem_autostart_prompt_shown', true);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Daha Sonra'),
                ),
                FilledButton(
                  onPressed: () async {
                    await prefs.setBool(
                        'inteliex.oem_autostart_prompt_shown', true);
                    if (context.mounted) Navigator.pop(context);
                    try {
                      await platformChannel
                          .invokeMethod('openOemAutostartSettings');
                    } catch (_) {}
                  },
                  child: const Text('Ayarı Aç'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint('OEM autostart check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);

    if (!_checkedForUpdates && controller.selectedAccount != null) {
      _checkedForUpdates = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UpdateService.checkForUpdates(context);
      });
    }

    if (!_checkedOemAutostart && controller.selectedAccount != null) {
      _checkedOemAutostart = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowOemAutostartPrompt(context);
      });
    }

    const pages = <Widget>[
      DialerPage(),
      AccountsPage(),
      ContactsPage(),
      HistoryPage(),
      GeneralSettingsPage(),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final currentTabIndex =
            controller.currentTabIndex.clamp(0, pages.length - 1);
        // Dialer sekmesinde üst banner'ı gizle; dialer kendi başlığı/durumu olan
        // kompakt UI'ye sahip.
        final showTopBanner =
            currentTabIndex != 0 && controller.statusLine.trim().isNotEmpty;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (showTopBanner) _TopStatusBanner(controller: controller),
                Expanded(
                  child: IndexedStack(
                    index: currentTabIndex,
                    children: pages,
                  ),
                ),
                if (controller.activeCall != null && currentTabIndex != 0)
                  _GlobalCallBar(controller: controller),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: currentTabIndex,
            onDestinationSelected: controller.setCurrentTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dialpad_rounded),
                label: 'Dialer',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_input_antenna_rounded),
                label: 'Hesaplar',
              ),
              NavigationDestination(
                icon: Icon(Icons.badge_rounded),
                label: 'Kisiler',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                label: 'Gecmis',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_rounded),
                label: 'Ayarlar',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GlobalCallBar extends StatelessWidget {
  const _GlobalCallBar({required this.controller});

  final SoftphoneController controller;

  @override
  Widget build(BuildContext context) {
    final call = controller.activeCall;
    if (call == null) {
      return const SizedBox.shrink();
    }

    final isIncoming = call.phase == CallPhase.incomingRinging;
    final isConnected = call.phase == CallPhase.connected;
    final tone = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF203934),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => controller.setCurrentTab(0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    call.remoteIdentity,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tone.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFFF7F0E8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    isIncoming
                        ? 'Gelen cagri'
                        : isConnected
                            ? 'Gorusme suruyor'
                            : 'Araniyor...',
                    style: tone.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD3E5DE),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isIncoming) ...[
            IconButton(
              onPressed: controller.declineCall,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFB54747),
                foregroundColor: const Color(0xFFF7F0E8),
              ),
              icon: const Icon(Icons.call_end_rounded),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: controller.answerCall,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D6D),
                foregroundColor: const Color(0xFFF7F0E8),
              ),
              icon: const Icon(Icons.call_rounded),
            ),
          ] else ...[
            IconButton(
              onPressed: controller.endCall,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFB54747),
                foregroundColor: const Color(0xFFF7F0E8),
              ),
              icon: const Icon(Icons.call_end_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _TopStatusBanner extends StatelessWidget {
  const _TopStatusBanner({required this.controller});

  final SoftphoneController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = controller.selectedAccount;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11211E), Color(0xFF2A584B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.appName,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: const Color(0xFFF7F0E8),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            controller.statusLine,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFD9E6DE),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _BannerPill(
                icon: Icons.person_outline_rounded,
                label: account == null ? 'Hesap yok' : account.aor,
              ),
              _BannerPill(
                icon: Icons.wifi_tethering_rounded,
                label: controller.registrationSummary,
              ),
              if (controller.activeCall != null)
                _BannerPill(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Aktif cagri var',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerPill extends StatelessWidget {
  const _BannerPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x22F7F0E8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFF7F0E8)),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFFF7F0E8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
