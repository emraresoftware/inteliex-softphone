import 'package:flutter/material.dart';

import '../services/platform/app_permission_service.dart';
import '../services/sip/softphone_controller.dart';
import 'inteliex_softphone_app.dart';

enum _SetupPhase { requestingPermissions, bootstrapping, ready, denied }

/// Ilk acilista tum runtime izinleri ister, ardindan SIP controller'i baslatir.
class SetupGate extends StatefulWidget {
  const SetupGate({super.key});

  @override
  State<SetupGate> createState() => _SetupGateState();
}

class _SetupGateState extends State<SetupGate> {
  _SetupPhase _phase = _SetupPhase.requestingPermissions;
  SoftphoneController? _controller;
  String _statusLine = 'Uygulama izinleri kontrol ediliyor...';

  @override
  void initState() {
    super.initState();
    _runSetup();
  }

  Future<void> _runSetup() async {
    setState(() {
      _phase = _SetupPhase.requestingPermissions;
      _statusLine = 'Mikrofon, kamera, bildirim ve arama izinleri isteniyor...';
    });

    final permissionsGranted =
        await AppPermissionService.ensureRequiredPermissions();
    if (!mounted) {
      return;
    }
    if (!permissionsGranted) {
      setState(() {
        _phase = _SetupPhase.denied;
        _statusLine =
            'Softphone calismasi icin gerekli izinler verilmedi. '
            'Lutfen izinleri onaylayin veya ayarlardan acin.';
      });
      return;
    }

    await AppPermissionService.ensureBatteryOptimizationExemption();

    if (!mounted) {
      return;
    }

    setState(() {
      _phase = _SetupPhase.bootstrapping;
      _statusLine = 'Hesaplar hazirlaniyor...';
    });

    final controller = await SoftphoneController.bootstrap();
    if (controller.accounts.isEmpty) {
      controller.setCurrentTab(1);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _controller = controller;
      _phase = _SetupPhase.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_phase == _SetupPhase.ready && _controller != null) {
      return InteliexSoftphoneApp(controller: _controller!);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security_rounded, size: 56),
                const SizedBox(height: 24),
                Text(
                  _phase == _SetupPhase.denied
                      ? 'Izin gerekli'
                      : 'Kurulum',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  _statusLine,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (_phase == _SetupPhase.denied) ...[
                  FilledButton(
                    onPressed: _runSetup,
                    child: const Text('Izinleri tekrar iste'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: AppPermissionService.openAppPermissionSettings,
                    child: const Text('Uygulama ayarlarini ac'),
                  ),
                ] else
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
