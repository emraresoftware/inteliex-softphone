import 'package:flutter/material.dart';

import '../../../app/app_state_scope.dart';
import '../../../core/models/call_log_entry.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cagri gecmisi', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: controller.callLogs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final log = controller.callLogs[index];
                final canRedial = log.remoteIdentity.trim().isNotEmpty;

                return Card(
                  child: ListTile(
                    onTap: canRedial
                        ? () => controller.startOutgoingCall(log.remoteIdentity)
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _tileColor(log),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _directionIcon(log.direction),
                        color: Colors.white,
                      ),
                    ),
                    title: Text(log.remoteIdentity),
                    subtitle: Text(
                      '${log.accountLabel}  -  ${_dispositionLabel(log.disposition)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_formatClock(log.startedAt)),
                            const SizedBox(height: 4),
                            Text(
                              _formatDuration(log.duration),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF5B6C66),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.call_rounded,
                          color: canRedial
                              ? const Color(0xFF2E7D6D)
                              : const Color(0xFFAFBBB5),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

IconData _directionIcon(CallDirection direction) {
  return switch (direction) {
    CallDirection.incoming => Icons.call_received_rounded,
    CallDirection.outgoing => Icons.call_made_rounded,
  };
}

Color _tileColor(CallLogEntry entry) {
  return switch (entry.disposition) {
    CallDisposition.missed => const Color(0xFFC13D3D),
    CallDisposition.declined => const Color(0xFFB86B22),
    _ => const Color(0xFF2E7D6D),
  };
}

String _dispositionLabel(CallDisposition disposition) {
  return switch (disposition) {
    CallDisposition.ringing => 'Caliyor',
    CallDisposition.answered => 'Cevaplandi',
    CallDisposition.declined => 'Reddedildi',
    CallDisposition.missed => 'Kacirildi',
    CallDisposition.ended => 'Tamamlandi',
  };
}

String _formatClock(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');

  return '$hour:$minute';
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

  if (duration == Duration.zero) {
    return '00:00';
  }

  return '$minutes:$seconds';
}
