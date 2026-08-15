import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:siprix_voip_sdk/accounts_model.dart' as siprix_accounts;
import 'package:siprix_voip_sdk/calls_model.dart';
import 'package:siprix_voip_sdk/network_model.dart' as siprix_network;
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import '../../core/models/sip_account.dart';
import 'softphone_sip_service.dart';

class SiprixSoftphoneService implements SoftphoneSipService {
  final Set<SoftphoneSipServiceListener> _listeners =
      <SoftphoneSipServiceListener>{};
    static const MethodChannel _foregroundChannel =
      MethodChannel('inteliex_softphone/foreground');
  final Map<String, _SiprixAccountBinding> _accountBindings =
      <String, _SiprixAccountBinding>{};
  final Map<int, String> _appAccountIdsByNativeId = <int, String>{};
  final Map<String, _SiprixCallBinding> _callBindings =
      <String, _SiprixCallBinding>{};
  final Set<String> _pendingNotificationAccepts = <String>{};
  final Set<String> _pendingConnectedCalls = <String>{};

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    SiprixVoipSdk().accListener = AccStateListener(
      regStateChanged: _onRegistrationChanged,
    );
    SiprixVoipSdk().callListener = CallStateListener(
      proceeding: _onCallProceeding,
      incoming: _onCallIncoming,
      acceptNotif: _onCallAcceptedFromNotification,
      connected: _onCallConnected,
      terminated: _onCallTerminated,
      held: _onCallHeld,
      muted: _onCallMuted,
    );

    final initData = siprix_accounts.InitData()
      ..unregOnDestroy = false
      ..serviceClassName =
          'com.example.inteliex_softphone.InteliexCallNotifService';

    await SiprixVoipSdk().initialize(initData);
    try {
      await SiprixVoipSdk().setForegroundMode(true);
    } on PlatformException catch (error) {
      developer.log(
        'Siprix foreground mode could not start: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
    _initialized = true;
  }

  @override
  void addListener(SoftphoneSipServiceListener listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(SoftphoneSipServiceListener listener) {
    _listeners.remove(listener);
  }

  @override
  Future<void> syncAccounts(Iterable<SipAccount> accounts) async {
    if (!_initialized) {
      await initialize();
    }

    final accountList = accounts.toList(growable: false);
    final knownIds = accountList.map((account) => account.id).toSet();
    final removedIds = _accountBindings.keys
        .where((accountId) => !knownIds.contains(accountId))
        .toList(growable: false);

    for (final accountId in removedIds) {
      await _deleteBinding(accountId);
    }

    for (final account in accountList) {
      final currentBinding = _accountBindings[account.id];
      if (currentBinding != null && _sameConfig(currentBinding.account, account)) {
        continue;
      }

      if (currentBinding != null) {
        await _deleteBinding(account.id);
      }

      await _createAccount(account);
    }
  }

  @override
  Future<void> reconnectAccount(String accountId) async {
    final binding = _accountBindings[accountId];
    if (binding == null) {
      return;
    }

    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: accountId,
        status: RegistrationStatus.connecting,
      ),
    );

    try {
      await SiprixVoipSdk().registerAccount(
        binding.nativeAccountId,
        binding.account.registrationExpireSeconds,
      );
    } on PlatformException catch (error) {
      _emitRegistrationUpdate(
        SoftphoneRegistrationUpdate(
          accountId: accountId,
          status: RegistrationStatus.failed,
          reason: error.message ?? error.code,
        ),
      );
    }
  }

  @override
  Future<bool> startOutgoingCall({
    required String accountId,
    required String target,
  }) async {
    final binding = _accountBindings[accountId];
    if (binding == null) {
      return false;
    }

    try {
      final callId = await SiprixVoipSdk().invite(
        CallDestination(
          _normalizeDestination(target),
          binding.nativeAccountId,
          false,
        ),
      );
      if (callId == null) {
        return false;
      }

      final now = DateTime.now();
      _callBindings[callId.toString()] = _SiprixCallBinding(
        accountId: accountId,
        nativeCallId: callId,
        direction: SoftphoneCallDirection.outgoing,
        remoteIdentity: _compactRemoteIdentity(target),
        startedAt: now,
      );
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: accountId,
          callId: callId.toString(),
          remoteIdentity: _compactRemoteIdentity(target),
          direction: SoftphoneCallDirection.outgoing,
          type: SoftphoneCallEventType.outgoingRinging,
          occurredAt: now,
        ),
      );
      return true;
    } on PlatformException catch (error) {
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: accountId,
          callId: 'siprix-error-${DateTime.now().microsecondsSinceEpoch}',
          remoteIdentity: _compactRemoteIdentity(target),
          direction: SoftphoneCallDirection.outgoing,
          type: SoftphoneCallEventType.failed,
          occurredAt: DateTime.now(),
          reason: error.message ?? error.code,
        ),
      );
      return false;
    }
  }

  @override
  Future<bool> answer(String callId) async {
    final binding = _callBindings[callId];
    if (binding == null) {
      return false;
    }

    await SiprixVoipSdk().accept(binding.nativeCallId, false);
    return true;
  }

  @override
  Future<void> decline(String callId) async {
    final binding = _callBindings[callId];
    if (binding == null) {
      return;
    }

    await SiprixVoipSdk().reject(binding.nativeCallId, 603);
  }

  @override
  Future<void> end(String callId) async {
    final binding = _callBindings[callId];
    if (binding == null) {
      return;
    }

    await SiprixVoipSdk().bye(binding.nativeCallId);
  }

  @override
  Future<void> setMuted(String callId, bool muted) async {
    final binding = _callBindings[callId];
    if (binding == null || binding.isMuted == muted) {
      return;
    }

    await SiprixVoipSdk().muteMic(binding.nativeCallId, muted);
    _callBindings[callId] = binding.copyWith(isMuted: muted);
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: callId,
        remoteIdentity: binding.remoteIdentity,
        direction: binding.direction,
        type: SoftphoneCallEventType.mutedChanged,
        occurredAt: DateTime.now(),
        isMuted: muted,
        isOnHold: binding.isOnHold,
      ),
    );
  }

  @override
  Future<void> setHeld(String callId, bool held) async {
    final binding = _callBindings[callId];
    if (binding == null || binding.isOnHold == held) {
      return;
    }

    await SiprixVoipSdk().hold(binding.nativeCallId);
  }

  @override
  Future<void> sendDtmf(String callId, String tone) async {
    final binding = _callBindings[callId];
    if (binding == null) {
      return;
    }

    await SiprixVoipSdk().sendDtmf(binding.nativeCallId, tone, 160, 80);
  }

  @override
  Future<void> dispose() async {
    final accountIds = _accountBindings.keys.toList(growable: false);
    for (final accountId in accountIds) {
      await _deleteBinding(accountId);
    }

    SiprixVoipSdk().callListener = null;
    SiprixVoipSdk().accListener = null;
    SiprixVoipSdk().unInitialize(null);

    _listeners.clear();
    _accountBindings.clear();
    _appAccountIdsByNativeId.clear();
    _callBindings.clear();
  }

  Future<void> _createAccount(SipAccount account) async {
    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: account.id,
        status: RegistrationStatus.connecting,
      ),
    );

    final hasOutboundProxy = account.outboundProxy.trim().isNotEmpty;

    // Siprix DNS SRV lookup bug: "domain" + port concatenated without ":" separator
    // (e.g. "demo1.sesdata.com5060"). Bypass by always setting an explicit sipProxy
    // for native transports (UDP/TCP) so Siprix skips SRV and connects directly.
    final isNativeTransport = account.transport == SipTransport.udp ||
        account.transport == SipTransport.tcp;
    final String resolvedProxy;
    if (hasOutboundProxy) {
      resolvedProxy = _normalizeProxy(account.outboundProxy);
    } else if (isNativeTransport) {
      // Use domain directly — if it already includes a port (host:port) use as-is,
      // otherwise append the SIP default port so Siprix connects to a known address.
      final domain = account.domain.trim();
      resolvedProxy = domain.contains(':') ? domain : '$domain:5060';
    } else {
      resolvedProxy = _normalizeProxy(account.websocketUrl);
    }

    final nativeAccount = siprix_accounts.AccountModel()
      ..sipServer = account.domain
      ..sipExtension = account.username
      ..sipPassword = account.password
      ..sipAuthId = account.authorizationUser
      ..sipProxy = resolvedProxy
      ..forceSipProxy = hasOutboundProxy || isNativeTransport
      ..displName = account.displayName
      ..userAgent = 'Inteliex Softphone MVP'
      ..expireTime = account.registrationExpireSeconds
      // NAT ortamlarda tek yon ses sorunlarini azaltmak icin.
      ..iceEnabled = true
      ..rtcpMuxEnabled = true
      ..rewriteContactIp = true
      ..keepAliveTime = 15
      ..transport = _mapTransport(account.transport);
    final stunServer = account.stunServer.trim();
    if (stunServer.isNotEmpty) {
      nativeAccount.stunServer = stunServer;
    } else if (isNativeTransport) {
      // UDP/TCP hesaplarda NAT nedeniyle tek-yon sesi azaltmak icin varsayilan STUN.
      nativeAccount.stunServer = 'stun:stun.l.google.com:19302';
    }

    try {
      final nativeId = await SiprixVoipSdk().addAccount(nativeAccount);
      if (nativeId == null) {
        throw PlatformException(
          code: 'null-account-id',
          message: 'Native hesap olusturulamadi.',
        );
      }

      _accountBindings[account.id] = _SiprixAccountBinding(
        account: account,
        nativeAccountId: nativeId,
      );
      _appAccountIdsByNativeId[nativeId] = account.id;
    } on PlatformException catch (error) {
      // Siprix servis uygulama kapandiktan sonra arka planda calismaya devam edebilir
      // (stopWithTask=false). Uygulama yeniden basladiginda addAccount eDuplicateAccount
      // (-1021) dondurebilir; err.details icinde mevcut native hesap ID'si gelir.
      if (error.code == SiprixVoipSdk.eDuplicateAccount.toString()) {
        final existingNativeId = error.details as int?;
        if (existingNativeId != null) {
          developer.log(
            'Siprix duplicate account recovered: nativeId=$existingNativeId accountId=${account.id}',
            name: 'SiprixSoftphoneService',
          );
          _accountBindings[account.id] = _SiprixAccountBinding(
            account: account,
            nativeAccountId: existingNativeId,
          );
          _appAccountIdsByNativeId[existingNativeId] = account.id;
          _emitRegistrationUpdate(
            SoftphoneRegistrationUpdate(
              accountId: account.id,
              status: RegistrationStatus.registered,
            ),
          );
          return;
        }
      }
      _emitRegistrationUpdate(
        SoftphoneRegistrationUpdate(
          accountId: account.id,
          status: RegistrationStatus.failed,
          reason: error.message ?? error.code,
        ),
      );
    }
  }

  Future<void> _deleteBinding(String accountId) async {
    final binding = _accountBindings.remove(accountId);
    if (binding == null) {
      return;
    }

    _appAccountIdsByNativeId.remove(binding.nativeAccountId);
    _callBindings.removeWhere((_, callBinding) => callBinding.accountId == accountId);
    try {
      await SiprixVoipSdk().deleteAccount(binding.nativeAccountId);
    } on PlatformException {
      // Native side may already be cleaned.
    }
  }

  void _onRegistrationChanged(
    int nativeAccountId,
    siprix_accounts.RegState state,
    String response,
  ) {
    final accountId = _appAccountIdsByNativeId[nativeAccountId];
    if (accountId == null) {
      return;
    }

    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: accountId,
        status: switch (state) {
          siprix_accounts.RegState.success => RegistrationStatus.registered,
          siprix_accounts.RegState.failed => RegistrationStatus.failed,
          siprix_accounts.RegState.removed => RegistrationStatus.disconnected,
          siprix_accounts.RegState.inProgress => RegistrationStatus.connecting,
        },
        reason: response.isEmpty ? null : response,
      ),
    );
  }

  void _onCallProceeding(int nativeCallId, String response) {
    final binding = _callBindings[nativeCallId.toString()];
    if (binding == null) {
      return;
    }

    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: nativeCallId.toString(),
        remoteIdentity: binding.remoteIdentity,
        direction: binding.direction,
        type: SoftphoneCallEventType.progressing,
        occurredAt: DateTime.now(),
        reason: response,
        isMuted: binding.isMuted,
        isOnHold: binding.isOnHold,
      ),
    );
  }

  void _onCallIncoming(
    int nativeCallId,
    int nativeAccountId,
    bool withVideo,
    String from,
    String to,
  ) {
    final accountId = _appAccountIdsByNativeId[nativeAccountId];
    if (accountId == null) {
      return;
    }

    final callId = nativeCallId.toString();
    final remoteIdentity = _compactRemoteIdentity(from);
    _callBindings[callId] = _SiprixCallBinding(
      accountId: accountId,
      nativeCallId: nativeCallId,
      direction: SoftphoneCallDirection.incoming,
      remoteIdentity: remoteIdentity,
      startedAt: DateTime.now(),
    );
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: accountId,
        callId: callId,
        remoteIdentity: remoteIdentity,
        direction: SoftphoneCallDirection.incoming,
        type: SoftphoneCallEventType.incomingRinging,
        occurredAt: DateTime.now(),
      ),
    );

    // In cold-start/background scenarios, notif "accept" may arrive before
    // incoming binding is created. Consume queued accept once call is known.
    if (_pendingNotificationAccepts.remove(callId)) {
      developer.log(
        'Siprix deferred notif accept consumed: callId=$callId',
        name: 'SiprixSoftphoneService',
      );
      unawaited(answer(callId));
    }

    if (_pendingConnectedCalls.remove(callId)) {
      developer.log(
        'Siprix pending connected consumed after incoming: callId=$callId',
        name: 'SiprixSoftphoneService',
      );
      unawaited(_switchToCall(nativeCallId));
      unawaited(_preferSpeakerPlayout());
      unawaited(_preferBuiltInRecording());
      unawaited(_scheduleMediaDiagnostics(nativeCallId));
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: accountId,
          callId: callId,
          remoteIdentity: remoteIdentity,
          direction: SoftphoneCallDirection.incoming,
          type: SoftphoneCallEventType.connected,
          occurredAt: DateTime.now(),
          isMuted: false,
          isOnHold: false,
        ),
      );
    }

    unawaited(_consumePendingNotificationAccept(callId));
  }

  void _onCallConnected(
    int nativeCallId,
    String from,
    String to,
    bool withVideo,
  ) {
    final callId = nativeCallId.toString();
    unawaited(_switchToCall(nativeCallId));
    unawaited(_preferSpeakerPlayout());
    unawaited(_preferBuiltInRecording());
    unawaited(_scheduleMediaDiagnostics(nativeCallId));

    final binding = _callBindings[callId];
    if (binding == null) {
      _pendingConnectedCalls.add(callId);
      developer.log(
        'Siprix connected arrived before incoming binding: callId=$callId',
        name: 'SiprixSoftphoneService',
      );
      return;
    }

    final remoteIdentity = binding.direction == SoftphoneCallDirection.incoming
        ? _compactRemoteIdentity(from)
        : _compactRemoteIdentity(to);
    _callBindings[callId] = binding.copyWith(
      remoteIdentity: remoteIdentity,
    );
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: callId,
        remoteIdentity: remoteIdentity,
        direction: binding.direction,
        type: SoftphoneCallEventType.connected,
        occurredAt: DateTime.now(),
        isMuted: binding.isMuted,
        isOnHold: binding.isOnHold,
      ),
    );
  }

  void _onCallAcceptedFromNotification(int nativeCallId, bool withVideo) {
    final callId = nativeCallId.toString();
    final binding = _callBindings[callId];

    try {
      // Android notif action can arrive before Flutter-side call binding exists.
      // Answer natively right away so tapping "Yanıtla" is reliable.
      unawaited(SiprixVoipSdk().accept(nativeCallId, withVideo));
    } on PlatformException catch (error) {
      developer.log(
        'Siprix direct notif accept failed: callId=$nativeCallId err=${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }

    if (binding == null) {
      _pendingNotificationAccepts.add(callId);
      developer.log(
        'Siprix notif accept deferred until incoming event: callId=$nativeCallId withVideo=$withVideo',
        name: 'SiprixSoftphoneService',
      );
      return;
    }

    developer.log(
      'Siprix notif accept: callId=$nativeCallId withVideo=$withVideo',
      name: 'SiprixSoftphoneService',
    );
    unawaited(answer(callId));
  }

  Future<void> _consumePendingNotificationAccept(String callId) async {
    try {
      final pending = await _foregroundChannel.invokeMethod<bool>(
        'consumePendingNotifAccept',
      );
      if (pending == true) {
        developer.log(
          'Siprix consumed MainActivity pending notif accept: callId=$callId',
          name: 'SiprixSoftphoneService',
        );
        await answer(callId);
      }
    } on MissingPluginException {
      // No-op outside Android build.
    } on PlatformException catch (error) {
      developer.log(
        'Siprix consumePendingNotifAccept failed: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
  }

  void _onCallTerminated(int nativeCallId, int statusCode) {
    final binding = _callBindings.remove(nativeCallId.toString());
    if (binding == null) {
      return;
    }

    developer.log(
      'Siprix call terminated: callId=$nativeCallId status=$statusCode remote=${binding.remoteIdentity}',
      name: 'SiprixSoftphoneService',
    );

    final isFailure = statusCode >= 400 &&
        statusCode != 486 &&
        statusCode != 487 &&
        statusCode != 603;
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: nativeCallId.toString(),
        remoteIdentity: binding.remoteIdentity,
        direction: binding.direction,
        type: isFailure
            ? SoftphoneCallEventType.failed
            : SoftphoneCallEventType.ended,
        occurredAt: DateTime.now(),
        reason: statusCode == 0 ? null : 'SIP $statusCode',
        isMuted: binding.isMuted,
        isOnHold: binding.isOnHold,
      ),
    );
  }

  void _onCallHeld(int nativeCallId, HoldState state) {
    final binding = _callBindings[nativeCallId.toString()];
    if (binding == null) {
      return;
    }

    final isOnHold = state != HoldState.none;
    _callBindings[nativeCallId.toString()] = binding.copyWith(isOnHold: isOnHold);
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: nativeCallId.toString(),
        remoteIdentity: binding.remoteIdentity,
        direction: binding.direction,
        type: SoftphoneCallEventType.holdChanged,
        occurredAt: DateTime.now(),
        isMuted: binding.isMuted,
        isOnHold: isOnHold,
      ),
    );
  }

  void _onCallMuted(int nativeCallId, bool muted) {
    final binding = _callBindings[nativeCallId.toString()];
    if (binding == null) {
      return;
    }

    _callBindings[nativeCallId.toString()] = binding.copyWith(isMuted: muted);
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: binding.accountId,
        callId: nativeCallId.toString(),
        remoteIdentity: binding.remoteIdentity,
        direction: binding.direction,
        type: SoftphoneCallEventType.mutedChanged,
        occurredAt: DateTime.now(),
        isMuted: muted,
        isOnHold: binding.isOnHold,
      ),
    );
  }

  void _emitRegistrationUpdate(SoftphoneRegistrationUpdate update) {
    for (final listener in _listeners.toList(growable: false)) {
      listener.onRegistrationUpdate(update);
    }
  }

  void _emitCallUpdate(SoftphoneCallUpdate update) {
    for (final listener in _listeners.toList(growable: false)) {
      listener.onCallUpdate(update);
    }
  }

  static bool _sameConfig(SipAccount current, SipAccount next) {
    return current.displayName == next.displayName &&
        current.username == next.username &&
        current.authorizationUser == next.authorizationUser &&
        current.password == next.password &&
        current.domain == next.domain &&
        current.websocketUrl == next.websocketUrl &&
        current.transport == next.transport &&
        current.allowBadCertificate == next.allowBadCertificate &&
        current.outboundProxy == next.outboundProxy &&
        current.stunServer == next.stunServer &&
        current.registrationExpireSeconds == next.registrationExpireSeconds;
  }

  static siprix_network.SipTransport _mapTransport(SipTransport transport) {
    return switch (transport) {
      SipTransport.udp => siprix_network.SipTransport.udp,
      SipTransport.tcp => siprix_network.SipTransport.tcp,
      SipTransport.ws => siprix_network.SipTransport.tcp,
      SipTransport.wss => siprix_network.SipTransport.tls,
    };
  }

  static String _normalizeProxy(String value) {
    return value.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
  }

  static String _normalizeDestination(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('sip:')) {
      return trimmed.substring(4);
    }
    return trimmed;
  }

  static String _compactRemoteIdentity(String value) {
    final trimmed = value.trim();
    final sipMatch = RegExp(r'sip:([^@>;]+)').firstMatch(trimmed);
    if (sipMatch != null) {
      return sipMatch.group(1) ?? trimmed;
    }

    if (trimmed.contains('@')) {
      return trimmed.split('@').first.replaceAll('"', '').trim();
    }

    return trimmed;
  }

  Future<void> _switchToCall(int nativeCallId) async {
    try {
      await SiprixVoipSdk().switchToCall(nativeCallId);
    } on PlatformException catch (error) {
      developer.log(
        'Siprix switchToCall failed for $nativeCallId: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
  }

  Future<void> _preferSpeakerPlayout() async {
    try {
      final deviceCount = await SiprixVoipSdk().getPlayoutDevices() ?? 0;
      for (var index = 0; index < deviceCount; index++) {
        final device = await SiprixVoipSdk().getPlayoutDevice(index);
        final name = (device?.name ?? '').toLowerCase();
        final guid = (device?.guid ?? '').toLowerCase();
        final descriptor = '$name $guid';
        final looksLikeSpeaker = descriptor.contains('speaker') ||
            descriptor.contains('builtin_speaker') ||
            descriptor.contains('built-in speaker');
        final looksLikeEarpiece = descriptor.contains('earpiece') ||
            descriptor.contains('telephony');

        if (!looksLikeSpeaker || looksLikeEarpiece) {
          continue;
        }

        await SiprixVoipSdk().setPlayoutDevice(index);
        developer.log(
          'Siprix playout switched to speaker device: ${device?.name}',
          name: 'SiprixSoftphoneService',
        );
        return;
      }
    } on PlatformException catch (error) {
      developer.log(
        'Siprix speaker selection failed: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
  }

  Future<void> _preferBuiltInRecording() async {
    try {
      final deviceCount = await SiprixVoipSdk().getRecordingDevices() ?? 0;
      for (var index = 0; index < deviceCount; index++) {
        final device = await SiprixVoipSdk().getRecordingDevice(index);
        final name = (device?.name ?? '').toLowerCase();
        final guid = (device?.guid ?? '').toLowerCase();
        final descriptor = '$name $guid';
        final looksLikeMic = descriptor.contains('mic') ||
            descriptor.contains('microphone') ||
            descriptor.contains('builtin') ||
            descriptor.contains('built-in') ||
            descriptor.contains('handset');

        if (!looksLikeMic) {
          continue;
        }

        await SiprixVoipSdk().setRecordingDevice(index);
        developer.log(
          'Siprix recording switched to device: ${device?.name}',
          name: 'SiprixSoftphoneService',
        );
        return;
      }
    } on PlatformException catch (error) {
      developer.log(
        'Siprix recording selection failed: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
  }

  Future<void> _scheduleMediaDiagnostics(int nativeCallId) async {
    unawaited(_logCallStats(nativeCallId, 'connected+3s', const Duration(seconds: 3)));
    unawaited(_logCallStats(nativeCallId, 'connected+8s', const Duration(seconds: 8)));
  }

  Future<void> _logCallStats(int nativeCallId, String phase, Duration delay) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }

    try {
      final stats = await SiprixVoipSdk().getStats(nativeCallId);
      developer.log(
        'Siprix call stats $phase callId=$nativeCallId: ${stats ?? 'null'}',
        name: 'SiprixSoftphoneService',
      );
    } on PlatformException catch (error) {
      developer.log(
        'Siprix stats failed ($phase) for $nativeCallId: ${error.message ?? error.code}',
        name: 'SiprixSoftphoneService',
      );
    }
  }
}

class _SiprixAccountBinding {
  const _SiprixAccountBinding({
    required this.account,
    required this.nativeAccountId,
  });

  final SipAccount account;
  final int nativeAccountId;
}

class _SiprixCallBinding {
  const _SiprixCallBinding({
    required this.accountId,
    required this.nativeCallId,
    required this.direction,
    required this.remoteIdentity,
    required this.startedAt,
    this.isMuted = false,
    this.isOnHold = false,
  });

  final String accountId;
  final int nativeCallId;
  final SoftphoneCallDirection direction;
  final String remoteIdentity;
  final DateTime startedAt;
  final bool isMuted;
  final bool isOnHold;

  _SiprixCallBinding copyWith({
    String? accountId,
    int? nativeCallId,
    SoftphoneCallDirection? direction,
    String? remoteIdentity,
    DateTime? startedAt,
    bool? isMuted,
    bool? isOnHold,
  }) {
    return _SiprixCallBinding(
      accountId: accountId ?? this.accountId,
      nativeCallId: nativeCallId ?? this.nativeCallId,
      direction: direction ?? this.direction,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      startedAt: startedAt ?? this.startedAt,
      isMuted: isMuted ?? this.isMuted,
      isOnHold: isOnHold ?? this.isOnHold,
    );
  }
}