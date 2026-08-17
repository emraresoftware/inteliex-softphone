import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/config/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/provisioning/presentation/claim_provisioning_flow.dart';
import '../services/sip/softphone_controller.dart';
import 'app_state_scope.dart';
import 'home_shell.dart';

class InteliexSoftphoneApp extends StatefulWidget {
  const InteliexSoftphoneApp({
    super.key,
    required this.controller,
  });

  final SoftphoneController controller;

  @override
  State<InteliexSoftphoneApp> createState() => _InteliexSoftphoneAppState();
}

class _InteliexSoftphoneAppState extends State<InteliexSoftphoneApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  bool _initialLinkHandled = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Soguk baslatma: uygulama bir deeplink ile aciddiysa ilk URI'yi al.
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (error) {
      debugPrint('Deeplink getInitialLink failed: $error');
    }

    // Acik uygulama: sonraki deeplink'leri dinle.
    _linkSub = _appLinks.uriLinkStream.listen(
      _handleIncomingUri,
      onError: (Object error) {
        debugPrint('Deeplink stream error: $error');
      },
    );
  }

  void _handleIncomingUri(Uri uri) {
    // Sadece provisioning deeplink'lerini isle.
    final isProvision = uri.scheme == 'inteliexphone' || uri.host == 'provision';
    if (!isProvision) {
      return;
    }

    if (_initialLinkHandled &&
        _lastHandledUri != null &&
        _lastHandledUri.toString() == uri.toString()) {
      // Ayni URI tekrar gelirse (cold-start + stream) iki kez isleme.
      return;
    }
    _initialLinkHandled = true;
    _lastHandledUri = uri;

    // Navigator hazir olana kadar bir frame bekle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navContext = _navigatorKey.currentContext;
      if (navContext == null) {
        return;
      }
      ClaimProvisioningFlow.handleProvisionString(
        navContext,
        widget.controller,
        uri.toString(),
      );
    });
  }

  Uri? _lastHandledUri;

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      controller: widget.controller,
      child: MaterialApp(
        title: AppConstants.appName,
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomeShell(),
      ),
    );
  }
}
