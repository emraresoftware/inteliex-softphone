import '../../core/models/sip_account.dart';

enum SoftphoneCallDirection {
  incoming,
  outgoing,
}

enum SoftphoneCallEventType {
  incomingRinging,
  outgoingRinging,
  progressing,
  connected,
  mutedChanged,
  holdChanged,
  ended,
  failed,
}

class SoftphoneRegistrationUpdate {
  const SoftphoneRegistrationUpdate({
    required this.accountId,
    required this.status,
    this.reason,
  });

  final String accountId;
  final RegistrationStatus status;
  final String? reason;
}

class SoftphoneCallUpdate {
  const SoftphoneCallUpdate({
    required this.accountId,
    required this.callId,
    required this.remoteIdentity,
    required this.direction,
    required this.type,
    required this.occurredAt,
    this.reason,
    this.isMuted = false,
    this.isOnHold = false,
  });

  final String accountId;
  final String callId;
  final String remoteIdentity;
  final SoftphoneCallDirection direction;
  final SoftphoneCallEventType type;
  final DateTime occurredAt;
  final String? reason;
  final bool isMuted;
  final bool isOnHold;
}

abstract class SoftphoneSipServiceListener {
  void onRegistrationUpdate(SoftphoneRegistrationUpdate update);

  void onCallUpdate(SoftphoneCallUpdate update);
}

abstract class SoftphoneSipService {
  Future<void> initialize();

  Future<void> syncAccounts(Iterable<SipAccount> accounts);

  Future<void> reconnectAccount(String accountId);

  Future<bool> startOutgoingCall({
    required String accountId,
    required String target,
  });

  Future<bool> answer(String callId);

  Future<void> decline(String callId);

  Future<void> end(String callId);

  Future<void> setMuted(String callId, bool muted);

  Future<void> setHeld(String callId, bool held);

  Future<void> setSpeaker(bool enabled);

  Future<void> sendDtmf(String callId, String tone);

  void addListener(SoftphoneSipServiceListener listener);

  void removeListener(SoftphoneSipServiceListener listener);

  Future<void> dispose();
}