import 'package:flutter/foundation.dart';

import '../../core/models/sip_account.dart';
import 'abto_softphone_service.dart';
import 'softphone_sip_service.dart';

SoftphoneSipService createSoftphoneSipService() {
  if (kIsWeb) {
    return _UnsupportedSoftphoneSipService();
  }

  return AbtoSoftphoneService();
}

class _UnsupportedSoftphoneSipService implements SoftphoneSipService {
  @override
  Future<void> initialize() async {}

  @override
  Future<void> syncAccounts(Iterable<SipAccount> accounts) async {}

  @override
  Future<void> reconnectAccount(String accountId) async {}

  @override
  Future<bool> startOutgoingCall({
    required String accountId,
    required String target,
  }) async => false;

  @override
  Future<bool> answer(String callId) async => false;

  @override
  Future<void> decline(String callId) async {}

  @override
  Future<void> end(String callId) async {}

  @override
  Future<void> setMuted(String callId, bool muted) async {}

  @override
  Future<void> setHeld(String callId, bool held) async {}

  @override
  Future<void> setSpeaker(bool enabled) async {}

  @override
  Future<void> sendDtmf(String callId, String tone) async {}

  @override
  void addListener(SoftphoneSipServiceListener listener) {}

  @override
  void removeListener(SoftphoneSipServiceListener listener) {}

  @override
  Future<void> dispose() async {}
}