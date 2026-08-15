import 'voip_platform_bridge.dart';

class NoOpVoipPlatformBridge implements VoipPlatformBridge {
  const NoOpVoipPlatformBridge();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reportCallConnected({
    required String callId,
    required String handle,
  }) async {}

  @override
  Future<void> reportCallEnded({
    required String callId,
    required String reason,
  }) async {}

  @override
  Future<void> reportIncomingCall({
    required String callId,
    required String handle,
    required String displayName,
  }) async {}

  @override
  Future<void> reportOutgoingCall({
    required String callId,
    required String handle,
    required String displayName,
  }) async {}

  @override
  Future<void> syncRegistration({
    required String? activeAccountAor,
    required int registeredAccounts,
    required int totalAccounts,
  }) async {}
}
