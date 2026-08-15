import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voip_platform_bridge.dart';

class MethodChannelVoipPlatformBridge implements VoipPlatformBridge {
  MethodChannelVoipPlatformBridge()
      : _channel = const MethodChannel('inteliex_softphone/voip');

  final MethodChannel _channel;
  bool _channelAvailable = true;

  @override
  Future<void> initialize() => _invoke('initialize');

  @override
  Future<void> syncRegistration({
    required String? activeAccountAor,
    required int registeredAccounts,
    required int totalAccounts,
  }) {
    return _invoke('syncRegistration', {
      'activeAccountAor': activeAccountAor,
      'registeredAccounts': registeredAccounts,
      'totalAccounts': totalAccounts,
    });
  }

  @override
  Future<void> reportIncomingCall({
    required String callId,
    required String handle,
    required String displayName,
  }) {
    return _invoke('reportIncomingCall', {
      'callId': callId,
      'handle': handle,
      'displayName': displayName,
    });
  }

  @override
  Future<void> reportOutgoingCall({
    required String callId,
    required String handle,
    required String displayName,
  }) {
    return _invoke('reportOutgoingCall', {
      'callId': callId,
      'handle': handle,
      'displayName': displayName,
    });
  }

  @override
  Future<void> reportCallConnected({
    required String callId,
    required String handle,
  }) {
    return _invoke('reportCallConnected', {
      'callId': callId,
      'handle': handle,
    });
  }

  @override
  Future<void> reportCallEnded({
    required String callId,
    required String reason,
  }) {
    return _invoke('reportCallEnded', {
      'callId': callId,
      'reason': reason,
    });
  }

  @override
  Future<void> dispose() {
    return _invoke('dispose');
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (!_channelAvailable) {
      return;
    }

    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _channelAvailable = false;
      debugPrint(
        'VoIP platform bridge is not implemented on this build; falling back to no-op calls.',
      );
    }
  }
}
