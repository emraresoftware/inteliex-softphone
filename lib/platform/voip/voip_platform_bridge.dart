abstract class VoipPlatformBridge {
  Future<void> initialize();

  Future<void> syncRegistration({
    required String? activeAccountAor,
    required int registeredAccounts,
    required int totalAccounts,
  });

  Future<void> reportIncomingCall({
    required String callId,
    required String handle,
    required String displayName,
  });

  Future<void> reportOutgoingCall({
    required String callId,
    required String handle,
    required String displayName,
  });

  Future<void> reportCallConnected({
    required String callId,
    required String handle,
  });

  Future<void> reportCallEnded({
    required String callId,
    required String reason,
  });

  Future<void> dispose();
}
