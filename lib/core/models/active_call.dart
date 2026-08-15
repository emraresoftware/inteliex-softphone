enum CallPhase {
  incomingRinging,
  outgoingRinging,
  connected,
}

class ActiveCall {
  const ActiveCall({
    required this.id,
    required this.accountId,
    required this.remoteIdentity,
    required this.phase,
    required this.startedAt,
    this.connectedAt,
    this.isMuted = false,
    this.isOnHold = false,
    this.isSpeaker = false,
  });

  final String id;
  final String accountId;
  final String remoteIdentity;
  final CallPhase phase;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final bool isMuted;
  final bool isOnHold;
  final bool isSpeaker;

  bool get isIncoming => phase == CallPhase.incomingRinging;
  bool get isConnected => phase == CallPhase.connected;

  ActiveCall copyWith({
    String? id,
    String? accountId,
    String? remoteIdentity,
    CallPhase? phase,
    DateTime? startedAt,
    DateTime? connectedAt,
    bool? isMuted,
    bool? isOnHold,
    bool? isSpeaker,
    bool clearConnectedAt = false,
  }) {
    return ActiveCall(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      phase: phase ?? this.phase,
      startedAt: startedAt ?? this.startedAt,
      connectedAt: clearConnectedAt ? null : connectedAt ?? this.connectedAt,
      isMuted: isMuted ?? this.isMuted,
      isOnHold: isOnHold ?? this.isOnHold,
      isSpeaker: isSpeaker ?? this.isSpeaker,
    );
  }
}
