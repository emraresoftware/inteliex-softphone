import 'package:flutter/material.dart';

import '../../../app/app_state_scope.dart';
import '../../../core/models/active_call.dart';
import '../../../services/sip/softphone_controller.dart';

class DialerPage extends StatelessWidget {
  const DialerPage({super.key});

  static const _keyRows = <List<_DialPadEntry>>[
    [
      _DialPadEntry(digit: '1', letters: ''),
      _DialPadEntry(digit: '2', letters: 'ABC'),
      _DialPadEntry(digit: '3', letters: 'DEF'),
    ],
    [
      _DialPadEntry(digit: '4', letters: 'GHI'),
      _DialPadEntry(digit: '5', letters: 'JKL'),
      _DialPadEntry(digit: '6', letters: 'MNO'),
    ],
    [
      _DialPadEntry(digit: '7', letters: 'PQRS'),
      _DialPadEntry(digit: '8', letters: 'TUV'),
      _DialPadEntry(digit: '9', letters: 'WXYZ'),
    ],
    [
      _DialPadEntry(digit: '*', letters: ''),
      _DialPadEntry(digit: '0', letters: '+'),
      _DialPadEntry(digit: '#', letters: ''),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);
    final theme = Theme.of(context);
    final account = controller.selectedAccount;
    final hasAccount = account != null;
    final activeCall = controller.activeCall;
    final hasActiveCall = activeCall != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1016201D),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5EFE5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.settings_input_antenna_rounded,
                        size: 16,
                        color: hasAccount
                            ? const Color(0xFF2E7D6D)
                            : const Color(0xFF8A9892),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        hasAccount ? account.displayName : 'Hesap secilmedi',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: hasAccount
                              ? const Color(0xFF2E7D6D)
                              : const Color(0xFF7B8A84),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (hasActiveCall)
                  _ActiveCallHeader(call: activeCall)
                else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Numara',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: const Color(0xFF7B8A84),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 46,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Text(
                          controller.dialedNumber.isEmpty
                              ? 'Numara girin'
                              : controller.dialedNumber,
                          maxLines: 1,
                          style: controller.dialedNumber.isEmpty
                              ? theme.textTheme.headlineSmall?.copyWith(
                                  color: const Color(0xFF94A29C),
                                )
                              : theme.textTheme.headlineMedium?.copyWith(
                                  fontSize: 34,
                                  letterSpacing: 1.2,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Column(
              children: [
                for (var rowIndex = 0; rowIndex < _keyRows.length; rowIndex++) ...[
                  Expanded(
                    child: Row(
                      children: [
                        for (var columnIndex = 0;
                            columnIndex < _keyRows[rowIndex].length;
                            columnIndex++) ...[
                          Expanded(
                            child: _DialPadButton(
                              entry: _keyRows[rowIndex][columnIndex],
                              onTap: () {
                                final digit = _keyRows[rowIndex][columnIndex].digit;
                                if (activeCall?.isConnected ?? false) {
                                  controller.sendDtmf(digit);
                                  return;
                                }
                                if (!hasActiveCall) {
                                  controller.appendDigit(digit);
                                }
                              },
                            ),
                          ),
                          if (columnIndex != _keyRows[rowIndex].length - 1)
                            const SizedBox(width: 14),
                        ],
                      ],
                    ),
                  ),
                  if (rowIndex != _keyRows.length - 1) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: OutlinedButton(
                  onPressed: hasActiveCall
                      ? null
                      : controller.dialedNumber.isEmpty
                          ? null
                          : controller.clearLastDigit,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: Color(0xFFE5DDD1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                  child: Icon(
                    Icons.backspace_outlined,
                    color: controller.dialedNumber.isEmpty
                        ? const Color(0xFFAFBBB5)
                        : const Color(0xFF5E6D67),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SizedBox(
                  height: 76,
                  child: hasActiveCall
                      ? _ActiveCallActionButton(call: activeCall, controller: controller)
                      : FilledButton.icon(
                          onPressed:
                              controller.canDial ? controller.startOutgoingCall : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D6D),
                            disabledBackgroundColor: const Color(0xFFE0D9CE),
                            foregroundColor: const Color(0xFFF7F0E8),
                            disabledForegroundColor: const Color(0xFF8A9892),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          icon: const Icon(Icons.call_rounded),
                          label: Text(
                            'Ara',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: controller.canDial
                                  ? const Color(0xFFF7F0E8)
                                  : const Color(0xFF8A9892),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialPadButton extends StatelessWidget {
  const _DialPadButton({
    required this.entry,
    required this.onTap,
  });

  final _DialPadEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white,
      elevation: 0,
      shadowColor: const Color(0x1016201D),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              entry.digit,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 32,
                height: 1.0,
              ),
            ),
            if (entry.letters.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.letters,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF6C7D77),
                  letterSpacing: 1.3,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialPadEntry {
  const _DialPadEntry({
    required this.digit,
    required this.letters,
  });

  final String digit;
  final String letters;
}

class _ActiveCallHeader extends StatelessWidget {
  const _ActiveCallHeader({required this.call});

  final ActiveCall? call;

  @override
  Widget build(BuildContext context) {
    final active = call;
    if (active == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final subtitle = switch (active.phase) {
      CallPhase.incomingRinging => 'Gelen cagri',
      CallPhase.outgoingRinging => 'Araniyor...',
      CallPhase.connected => active.isOnHold ? 'Gorusme holdda' : 'Gorusme suruyor',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          subtitle,
          style: theme.textTheme.labelLarge?.copyWith(
            color: const Color(0xFF7B8A84),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          active.remoteIdentity,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 32,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _ActiveCallActionButton extends StatelessWidget {
  const _ActiveCallActionButton({
    required this.call,
    required this.controller,
  });

  final ActiveCall? call;
  final SoftphoneController controller;

  @override
  Widget build(BuildContext context) {
    final active = call;
    final theme = Theme.of(context);
    if (active == null) {
      return const SizedBox.shrink();
    }

    if (active.phase == CallPhase.incomingRinging) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: controller.declineCall,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB54747),
                foregroundColor: const Color(0xFFF7F0E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              icon: const Icon(Icons.call_end_rounded),
              label: const Text('Reddet'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: controller.answerCall,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D6D),
                foregroundColor: const Color(0xFFF7F0E8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              icon: const Icon(Icons.call_rounded),
              label: const Text('Cevapla'),
            ),
          ),
        ],
      );
    }

    return FilledButton.icon(
      onPressed: controller.endCall,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFB54747),
        foregroundColor: const Color(0xFFF7F0E8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      icon: const Icon(Icons.call_end_rounded),
      label: Text(
        active.phase == CallPhase.outgoingRinging ? 'Kapat' : 'Bitir',
        style: theme.textTheme.titleLarge?.copyWith(
          color: const Color(0xFFF7F0E8),
        ),
      ),
    );
  }
}
