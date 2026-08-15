enum CallDirection {
  incoming,
  outgoing,
}

enum CallDisposition {
  ringing,
  answered,
  declined,
  missed,
  ended,
}

CallDirection callDirectionFromName(String? value) {
  return CallDirection.values.firstWhere(
    (direction) => direction.name == value,
    orElse: () => CallDirection.outgoing,
  );
}

CallDisposition callDispositionFromName(String? value) {
  return CallDisposition.values.firstWhere(
    (disposition) => disposition.name == value,
    orElse: () => CallDisposition.ended,
  );
}

class CallLogEntry {
  const CallLogEntry({
    required this.sessionId,
    required this.accountLabel,
    required this.remoteIdentity,
    required this.direction,
    required this.disposition,
    required this.startedAt,
    this.connectedAt,
    this.endedAt,
  });

  final String sessionId;
  final String accountLabel;
  final String remoteIdentity;
  final CallDirection direction;
  final CallDisposition disposition;
  final DateTime startedAt;

  /// Medyanin baglandigi an; cevapsiz/reddedilen cagrilarda null kalir.
  final DateTime? connectedAt;
  final DateTime? endedAt;

  /// Konusma suresi. Cagri hic baglanmadiysa 0 doner; connectedAt olmayan
  /// eski kayitlarda cevaplanmis cagrilar icin startedAt'e geri duser.
  Duration get duration {
    final end = endedAt;
    if (end == null) {
      return Duration.zero;
    }

    final connected = connectedAt;
    if (connected != null) {
      final elapsed = end.difference(connected);
      return elapsed.isNegative ? Duration.zero : elapsed;
    }

    if (disposition == CallDisposition.answered ||
        disposition == CallDisposition.ended) {
      return end.difference(startedAt);
    }

    return Duration.zero;
  }

  Map<String, Object?> toStorageJson() {
    return {
      'sessionId': sessionId,
      'accountLabel': accountLabel,
      'remoteIdentity': remoteIdentity,
      'direction': direction.name,
      'disposition': disposition.name,
      'startedAt': startedAt.toIso8601String(),
      'connectedAt': connectedAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
    };
  }

  factory CallLogEntry.fromStorageJson(Map<String, dynamic> json) {
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '');
    final connectedAt =
        DateTime.tryParse(json['connectedAt']?.toString() ?? '');
    final endedAt = DateTime.tryParse(json['endedAt']?.toString() ?? '');

    return CallLogEntry(
      sessionId: json['sessionId']?.toString() ?? '',
      accountLabel: json['accountLabel']?.toString() ?? '',
      remoteIdentity: json['remoteIdentity']?.toString() ?? '',
      direction: callDirectionFromName(json['direction']?.toString()),
      disposition: callDispositionFromName(json['disposition']?.toString()),
      startedAt: startedAt ?? DateTime.now(),
      connectedAt: connectedAt,
      endedAt: endedAt,
    );
  }

  CallLogEntry copyWith({
    String? sessionId,
    String? accountLabel,
    String? remoteIdentity,
    CallDirection? direction,
    CallDisposition? disposition,
    DateTime? startedAt,
    DateTime? connectedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
  }) {
    return CallLogEntry(
      sessionId: sessionId ?? this.sessionId,
      accountLabel: accountLabel ?? this.accountLabel,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      direction: direction ?? this.direction,
      disposition: disposition ?? this.disposition,
      startedAt: startedAt ?? this.startedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
    );
  }
}
