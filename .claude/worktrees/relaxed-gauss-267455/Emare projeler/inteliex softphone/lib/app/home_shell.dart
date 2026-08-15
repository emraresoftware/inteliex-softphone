import 'package:flutter/material.dart';

import '../core/config/app_constants.dart';
import '../core/models/active_call.dart';
import '../features/accounts/presentation/accounts_page.dart';
import '../features/contacts/presentation/contacts_page.dart';
import '../features/dialer/presentation/dialer_page.dart';
import '../features/history/presentation/history_page.dart';
import '../services/sip/softphone_controller.dart';
import 'app_state_scope.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);

    const pages = <Widget>[
      DialerPage(),
      AccountsPage(),
      ContactsPage(),
      HistoryPage(),
    ];

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final currentTabIndex = controller.currentTabIndex.clamp(0, pages.length - 1);
        final showTopBanner = currentTabIndex != 0;

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
                if (controller.activeCall != null)
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
