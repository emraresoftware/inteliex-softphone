import 'dart:async';
import 'dart:io' show Platform;

import 'package:abto_voip_sdk/abto_phone_cfg.dart';
import 'package:abto_voip_sdk/sip_wrapper.dart';
import 'package:flutter/foundation.dart';

import '../../core/models/sip_account.dart';
import 'sip_device_profile_service.dart';
import 'softphone_sip_service.dart';

class AbtoSoftphoneService implements SoftphoneSipService {
  static const String _defaultTrialAndroidLicenseId =
      '{Trial_Flutter_Android-DB6F-BAE6-AE3AB24E-A131-4594-A0C7-2E77FF67701E}';
  static const String _defaultTrialAndroidLicenseKey =
      '{mKqEzp2Ls7kOGxS2Q5Y1kLC/NtGKzvLR9iWko42FieSHthfZXAchnUurKxaI0wsC5wdptO6/oxVIcOUS2tD/fA==}';

  // ABTO deneme lisanslari platforma ozeldir; Android anahtari iOS'ta
  // "Invalid key" hatasi verip SDK'nin kayit atmasini engelliyordu.
  static const String _defaultTrialIosLicenseId =
      '{Trial_Flutter_iOS-DB6F-78E2-B977C719-E140-48AB-A099-47F2B6DF801E}';
  static const String _defaultTrialIosLicenseKey =
      '{vcrgvw+N09sgb4mrVyVGrFxSOdICZo2MKBpufQiG4GXZxSNcLmwK2U5Xb/WLQX/IP7gdYEGoT+EbbYNdV4PDMQ==}';

  final Set<SoftphoneSipServiceListener> _listeners =
      <SoftphoneSipServiceListener>{};
  final Map<String, SipAccount> _accounts = <String, SipAccount>{};

  bool _initialized = false;
  String? _activeAccountId;
  _AbtoCallBinding? _activeCall;
  int _callSequence = 0;
  Timer? _registrationWatchdog;
  Timer? _registrationProbe;
  Timer? _outgoingCallWatchdog;
  int _registrationAttempt = 0;
  bool _isEmulatorDevice = false;
  bool _pendingSpeakerEnabled =
      false; // hoparlör bağlanmadan önce basılırsa beklet
  // Hesap değişiminde eski hesabın unregister callback'i asenkron gelir;
  // o sırada _activeAccountId yeni hesaba işaret ettiğinden "disconnected"
  // olayı yanlış hesaba yazılırdı. Bu bayrak o tek olayı yutar.
  bool _suppressNextUnregisterEvent = false;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // Android 14+ (targetSDK 34+) cihazlarda, 'microphone' tipindeki Foreground Service'in
    // uygulama henüz tam açılıp odağa (focus) girmeden başlatılmasını (SecurityException) engellemek için gecikme ekliyoruz.
    await Future<void>.delayed(const Duration(seconds: 2));

    SipWrapper.wrapper.init();

    final isIos = !kIsWeb && Platform.isIOS;
    final defaultLicenseId =
        isIos ? _defaultTrialIosLicenseId : _defaultTrialAndroidLicenseId;
    final defaultLicenseKey =
        isIos ? _defaultTrialIosLicenseKey : _defaultTrialAndroidLicenseKey;

    final licenseId = const String.fromEnvironment('ABTO_LICENSE_ID');
    final licenseKey = const String.fromEnvironment('ABTO_LICENSE_KEY');
    SipWrapper.wrapper.setLicense(
      licenseId.isNotEmpty ? licenseId : defaultLicenseId,
      licenseKey.isNotEmpty ? licenseKey : defaultLicenseKey,
    );

    SipWrapper.wrapper.registerListener = RegisterListener(
      onRegistered: _onRegistered,
      onRegistrationFailed: _onRegistrationFailed,
      onUnregistered: _onUnregistered,
    );
    SipWrapper.wrapper.callListener = CallListener(
      callConnected: _onCallConnected,
      callDisconnected: _onCallDisconnected,
    );
    SipWrapper.wrapper.incomingCallListener = IncomingCallListener(
      onIncomingCall: _onIncomingCall,
    );
    SipWrapper.wrapper.holdStateListener = HoldStateListener(
      onHoldState: _onHoldState,
    );

    await _resolveDeviceProfile();

    _initialized = true;
  }

  Future<void> _resolveDeviceProfile() async {
    try {
      final profile = await SipDeviceProfileService().getDeviceProfile();
      _isEmulatorDevice = profile == 'emulator';
      debugPrint('ABTO device profile resolved: $profile');
    } catch (error) {
      _isEmulatorDevice = false;
      debugPrint('ABTO device profile detect failed: $error');
    }
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

    // Mevcut aktif hesabı _accounts güncellenmeden ÖNCE al.
    final currentActive =
        _activeAccountId == null ? null : _accounts[_activeAccountId!];

    _accounts
      ..clear()
      ..addEntries(accounts.map((account) => MapEntry(account.id, account)));

    final nextActiveAccount = accounts.isEmpty ? null : accounts.first;

    if (nextActiveAccount == null) {
      _activeAccountId = null;
      SipWrapper.wrapper.unregister();
      return;
    }

    if (currentActive != null &&
        _sameConfig(currentActive, nextActiveAccount)) {
      if (SipWrapper.wrapper.isRegistered) {
        _emitRegistrationUpdate(
          SoftphoneRegistrationUpdate(
            accountId: nextActiveAccount.id,
            status: RegistrationStatus.registered,
          ),
        );
      }
      return;
    }

    // currentActive null ise (uygulama arka plandan yeniden başladı) ama ABTO
    // zaten kayıtlıysa, aynı hesap için gereksiz yeniden kayıt yapma.
    if (currentActive == null && SipWrapper.wrapper.isRegistered) {
      _activeAccountId = nextActiveAccount.id;
      _emitRegistrationUpdate(
        SoftphoneRegistrationUpdate(
          accountId: nextActiveAccount.id,
          status: RegistrationStatus.registered,
        ),
      );
      return;
    }

    // Hesap değiştiyse önce eski kaydı sil, sonra yenisini kayıt et.
    if (currentActive != null) {
      _suppressNextUnregisterEvent = true;
      SipWrapper.wrapper.unregister();
    }

    _activeAccountId = nextActiveAccount.id;
    await _register(nextActiveAccount);
  }

  @override
  Future<void> reconnectAccount(String accountId) async {
    final account = _accounts[accountId];
    if (account == null) {
      return;
    }

    _activeAccountId = accountId;
    await _register(account);
  }

  @override
  Future<bool> startOutgoingCall({
    required String accountId,
    required String target,
  }) async {
    if (_activeCall != null) {
      return false;
    }

    final account = _accounts[accountId];
    if (account == null) {
      return false;
    }

    final callId = _nextCallId();
    final now = DateTime.now();
    final remoteIdentity = _compactRemoteIdentity(target);
    _activeCall = _AbtoCallBinding(
      accountId: account.id,
      callId: callId,
      direction: SoftphoneCallDirection.outgoing,
      remoteIdentity: remoteIdentity,
      isOnHold: false,
      isMuted: false,
    );

    // Arama hazırlığını hemen UI'a bildir. Böylece kullanıcı kayıt beklenirken
    // de Kapat'a basabilir ve gecikmiş native startCall iptal edilir.
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: account.id,
        callId: callId,
        remoteIdentity: remoteIdentity,
        direction: SoftphoneCallDirection.outgoing,
        type: SoftphoneCallEventType.outgoingRinging,
        occurredAt: now,
      ),
    );

    // Hesap secimi uygulama tarafinda degisse bile ABTO tek aktif hesaba
    // bagli oldugundan, arama oncesi native aktif hesabi senkronla.
    if (_activeAccountId != accountId) {
      _activeAccountId = accountId;
      final registered = await _waitForRegistrationBeforeCall(
        account,
        callId: callId,
      );
      if (!registered) {
        return false;
      }
    } else if (!SipWrapper.wrapper.isRegistered) {
      final registered = await _waitForRegistrationBeforeCall(
        account,
        callId: callId,
      );
      if (!registered) {
        return false;
      }
    }

    final pendingCall = _activeCall;
    if (pendingCall == null || pendingCall.callId != callId) {
      debugPrint('ABTO outgoing call cancelled before native start: $callId');
      return false;
    }

    SipWrapper.wrapper.startCall(target, false);
    _activeCall = pendingCall.copyWith(nativeCallStarted: true);
    _scheduleOutgoingCallWatchdog(callId);
    return true;
  }

  @override
  Future<bool> answer(String callId) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return false;
    }

    SipWrapper.wrapper.pickUpCall(false);
    // Bazı Android/ABTO kombinasyonlarında karşı taraf 200 OK alıp çağrıyı
    // connected görürken yerel callConnected callback'i kayboluyor. Bu durumda
    // cevap butonu ekranda kalıyor ve kullanıcı tekrar tekrar basıyor. Native
    // cevaplamaya kısa süre tanıdıktan sonra yalnızca aynı çağrı hâlâ ringing
    // ise UI/medya durumunu bağlı olarak sentezle. Gerçek disconnect callback'i
    // yine çağrıyı normal biçimde kapatır.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 900), () {
      final current = _activeCall;
      if (current == null || current.callId != callId || current.wasConnected) {
        return;
      }
      debugPrint('ABTO answer fallback: synthesizing connected event');
      _onCallConnected(current.remoteIdentity);
    }));
    return true;
  }

  @override
  Future<void> decline(String callId) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return;
    }

    SipWrapper.wrapper.rejectCall();
  }

  @override
  Future<void> end(String callId) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return;
    }

    if (call.nativeCallStarted) {
      SipWrapper.wrapper.endCall();
      return;
    }

    // Native çağrı henüz başlamadıysa kayıt bekleyişini iptal et. Bekleyen
    // akış callId eşleşmesini kaybedip daha sonra startCall çalıştıramaz.
    _activeCall = null;
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: call.accountId,
        callId: call.callId,
        remoteIdentity: call.remoteIdentity,
        direction: call.direction,
        type: SoftphoneCallEventType.ended,
        occurredAt: DateTime.now(),
        isMuted: call.isMuted,
        isOnHold: call.isOnHold,
      ),
    );
  }

  @override
  Future<void> setMuted(String callId, bool muted) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return;
    }

    SipWrapper.wrapper.mute(muted);
    _activeCall = call.copyWith(isMuted: muted);
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: call.accountId,
        callId: call.callId,
        remoteIdentity: call.remoteIdentity,
        direction: call.direction,
        type: SoftphoneCallEventType.mutedChanged,
        occurredAt: DateTime.now(),
        isMuted: muted,
        isOnHold: call.isOnHold,
      ),
    );
  }

  @override
  Future<void> setHeld(String callId, bool held) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return;
    }
    if (held == call.isOnHold) {
      return;
    }

    SipWrapper.wrapper.hold();
  }

  @override
  Future<void> setSpeaker(bool enabled) async {
    _pendingSpeakerEnabled = enabled;
    SipWrapper.wrapper.enableSpeaker(enabled);
  }

  @override
  Future<void> sendDtmf(String callId, String tone) async {
    final call = _activeCall;
    if (call == null || call.callId != callId) {
      return;
    }

    SipWrapper.wrapper.sendDtmf(tone);
  }

  @override
  Future<void> dispose() async {
    _registrationWatchdog?.cancel();
    _registrationWatchdog = null;
    _registrationProbe?.cancel();
    _registrationProbe = null;
    _outgoingCallWatchdog?.cancel();
    _outgoingCallWatchdog = null;
    SipWrapper.wrapper.unregister();
    SipWrapper.wrapper.registerListener = null;
    SipWrapper.wrapper.callListener = null;
    SipWrapper.wrapper.incomingCallListener = null;
    SipWrapper.wrapper.holdStateListener = null;
    SipWrapper.wrapper.destroy();
    _listeners.clear();
    _accounts.clear();
    _activeCall = null;
    _activeAccountId = null;
    _pendingSpeakerEnabled = false;
    _suppressNextUnregisterEvent = false;
    _initialized = false;
  }

  Future<void> _register(SipAccount account) async {
    final cfg = await SipWrapper.wrapper.getConfigs();
    cfg.signalingTransport = switch (account.transport) {
      SipTransport.tcp => AbtoPhoneCfg.SIGNALING_TRANSPORT_TCP,
      SipTransport.udp => AbtoPhoneCfg.SIGNALING_TRANSPORT_UDP,
      _ => AbtoPhoneCfg.SIGNALING_TRANSPORT_UDP,
    };
    // ABTO registerTimeout ms cinsinden; SIP Expires (registrationExpireSeconds) ile karistirma.
    cfg.registerTimeout = 15000;
    cfg.keepAliveInterval = 15;

    _applyMediaNatConfig(cfg, account);
    _applyAudioCodecConfig(cfg);
    SipWrapper.wrapper.setConfigs(cfg);

    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: account.id,
        status: RegistrationStatus.connecting,
      ),
    );

    _scheduleRegistrationWatchdog(account.id);

    final registerDomain = _registerDomain(account);
    final registerProxy = _registerProxy(account);
    final authId = _registerAuthId(account);

    debugPrint(
      'ABTO register: domain=$registerDomain proxy=$registerProxy '
      'user=${account.username.trim()} authId=${authId.isEmpty ? '(auto)' : authId}',
    );

    SipWrapper.wrapper.register(
      registerDomain,
      registerProxy,
      account.username.trim(),
      account.password,
      authId,
      account.displayName.trim(),
      account.registrationExpireSeconds,
    );
  }

  /// ABTO/PJSIP bazen REGISTER URI'ye `;transport=udp;lr` ekler; digest URI
  /// uyusmazligi Asterisk'te 403 Forbidden uretir. Outbound proxy ile duz URI kullan.
  static String _registerDomain(SipAccount account) {
    final raw = account.domain.trim();
    if (raw.isEmpty) {
      return raw;
    }
    final host = raw.split(':').first.trim();
    return host.isEmpty ? raw : host;
  }

  static String _registerProxy(SipAccount account) {
    final explicit = account.outboundProxy.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }

    if (account.transport != SipTransport.udp &&
        account.transport != SipTransport.tcp) {
      return '';
    }

    final host = _registerDomain(account);
    if (host.isEmpty) {
      return '';
    }

    return '$host:5060';
  }

  static String _registerAuthId(SipAccount account) {
    final username = account.username.trim();
    final authorizationUser = account.authorizationUser.trim();
    if (authorizationUser.isEmpty || authorizationUser == username) {
      return '';
    }
    return authorizationUser;
  }

  void _onRegistered() {
    // Yeni hesap kayıtlandıysa hesap değişimi tamamlanmıştır; bundan sonraki
    // unregister olayları gerçektir, bastırma bayrağını temizle.
    _suppressNextUnregisterEvent = false;
    _registrationWatchdog?.cancel();
    _registrationWatchdog = null;
    _registrationProbe?.cancel();
    _registrationProbe = null;
    final accountId = _activeAccountId;
    if (accountId == null) {
      return;
    }
    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: accountId,
        status: RegistrationStatus.registered,
      ),
    );
  }

  void _onRegistrationFailed() {
    _suppressNextUnregisterEvent = false;
    _registrationWatchdog?.cancel();
    _registrationWatchdog = null;
    _registrationProbe?.cancel();
    _registrationProbe = null;
    final accountId = _activeAccountId;
    if (accountId == null) {
      return;
    }
    final code = SipWrapper.wrapper.lastRegistrationFailureCode;
    final text = SipWrapper.wrapper.lastRegistrationFailureText;
    final reason = (code != null || (text?.trim().isNotEmpty ?? false))
        ? 'SIP ${code ?? '?'} ${text?.trim() ?? ''}'.trim()
        : null;
    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: accountId,
        status: RegistrationStatus.failed,
        reason: reason,
      ),
    );
  }

  void _onUnregistered() {
    if (_suppressNextUnregisterEvent) {
      _suppressNextUnregisterEvent = false;
      debugPrint('ABTO unregister event suppressed (account switch)');
      return;
    }
    _registrationWatchdog?.cancel();
    _registrationWatchdog = null;
    _registrationProbe?.cancel();
    _registrationProbe = null;
    final accountId = _activeAccountId;
    if (accountId == null) {
      return;
    }
    _emitRegistrationUpdate(
      SoftphoneRegistrationUpdate(
        accountId: accountId,
        status: RegistrationStatus.disconnected,
      ),
    );
  }

  /// Cold-start senaryosunda Flutter engine paused iken native'den gelen
  /// onIncomingCall event'i kaybolduysa, MainActivity'in SharedPreferences'a
  /// yazdığı pending call info'sunu bootstrap'ta enjekte etmek için.
  void injectIncomingCallFromIntent(String remoteContact, bool isVideo) {
    if (_activeCall != null) return; // zaten biliyoruz
    _onIncomingCall(remoteContact, isVideo);
  }

  void _onIncomingCall(String number, bool isVideoCall) {
    // ABTO tek çağrı destekler; süren bir çağrı varken gelen ikinci çağrı
    // binding'i ezerse aktif çağrı kontrol edilemez hale gelir (end/mute
    // callId eşleşmez). Mevcut çağrıyı koru, yeni çağrıyı yok say.
    if (_activeCall != null) {
      debugPrint(
        'ABTO incoming call ignored: another call is already active '
        '(${_activeCall!.callId})',
      );
      return;
    }

    final accountId = _resolveAccountId();
    if (accountId == null) {
      return;
    }

    final callId = _nextCallId();
    final remoteIdentity = _compactRemoteIdentity(number);
    _activeCall = _AbtoCallBinding(
      accountId: accountId,
      callId: callId,
      direction: SoftphoneCallDirection.incoming,
      remoteIdentity: remoteIdentity,
      isOnHold: false,
      isMuted: false,
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
  }

  String? _resolveAccountId() {
    if (_activeAccountId != null) return _activeAccountId;
    if (_accounts.isEmpty) return null;
    final fallback = _accounts.keys.first;
    _activeAccountId = fallback;
    return fallback;
  }

  void _onCallConnected(String number) {
    _outgoingCallWatchdog?.cancel();
    _outgoingCallWatchdog = null;
    // ABTO may preserve its native microphone mute state between calls,
    // especially when an incoming call is answered from the Android
    // notification before Flutter handles it. Android can keep AudioRecord
    // active in that state while the SIP stack sends no RTP packets.
    // Every new call starts unmuted in our model, so reset the native state
    // once media is connected.
    SipWrapper.wrapper.mute(false);
    // Bazı cihazlarda (özellikle Casper 2004) otomatik RTP bayrağı config'de
    // açık olsa da aktif çağrının mikrofon RTP akışı başlamıyor. ABTO'nun çağrı
    // bazlı API'si ile gönderimi açıkça başlat.
    SipWrapper.wrapper.setSendingRtpAudio(true);

    var call = _activeCall;
    if (call == null) {
      // _onIncomingCall event'i (Flutter engine paused iken native'den gelen
      // mesaj kaybolduysa) hiç tetiklenmemiş olabilir; bu durumda çağrıyı
      // şimdi sentezle ki UI doğru göstersin.
      final accountId = _resolveAccountId();
      if (accountId == null) return;
      final remoteIdentity = _compactRemoteIdentity(number);
      call = _AbtoCallBinding(
        accountId: accountId,
        callId: _nextCallId(),
        direction: SoftphoneCallDirection.incoming,
        remoteIdentity: remoteIdentity,
        isOnHold: false,
        isMuted: false,
      );
      _activeCall = call;
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: call.accountId,
          callId: call.callId,
          remoteIdentity: remoteIdentity,
          direction: SoftphoneCallDirection.incoming,
          type: SoftphoneCallEventType.incomingRinging,
          occurredAt: DateTime.now(),
        ),
      );
      // Ekran donmasını önlemek için connected event'i bir sonraki microtask'ta gönder.
      final capturedCall = call;
      Future<void>.microtask(
          () => _emitSynthesizedConnected(capturedCall, number));
      return;
    }

    final updated = call.copyWith(
      remoteIdentity: _compactRemoteIdentity(number),
      wasConnected: true,
    );
    _activeCall = updated;

    if (_isEmulatorDevice) {
      SipWrapper.wrapper.enableSpeaker(true);
      debugPrint('ABTO emulator call connected: speaker route enabled');
    } else if (_pendingSpeakerEnabled) {
      // Arama bağlanmadan önce hoparlör butonu basılmışsa şimdi uygula
      SipWrapper.wrapper.enableSpeaker(true);
      debugPrint('ABTO call connected: applying pending speaker enable');
    }

    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: updated.accountId,
        callId: updated.callId,
        remoteIdentity: updated.remoteIdentity,
        direction: updated.direction,
        type: SoftphoneCallEventType.connected,
        occurredAt: DateTime.now(),
        isMuted: updated.isMuted,
        isOnHold: updated.isOnHold,
      ),
    );
  }

  void _emitSynthesizedConnected(_AbtoCallBinding call, String number) {
    final updated = call.copyWith(
      remoteIdentity: _compactRemoteIdentity(number),
      wasConnected: true,
    );
    _activeCall = updated;
    SipWrapper.wrapper.mute(false);
    SipWrapper.wrapper.setSendingRtpAudio(true);

    if (_isEmulatorDevice) {
      SipWrapper.wrapper.enableSpeaker(true);
    } else if (_pendingSpeakerEnabled) {
      SipWrapper.wrapper.enableSpeaker(true);
      debugPrint(
          'ABTO synthesized call connected: applying pending speaker enable');
    }

    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: updated.accountId,
        callId: updated.callId,
        remoteIdentity: updated.remoteIdentity,
        direction: updated.direction,
        type: SoftphoneCallEventType.connected,
        occurredAt: DateTime.now(),
        isMuted: updated.isMuted,
        isOnHold: updated.isOnHold,
      ),
    );
  }

  void _onCallDisconnected() {
    _outgoingCallWatchdog?.cancel();
    _outgoingCallWatchdog = null;
    final call = _activeCall;
    if (call == null) {
      return;
    }

    final failedBeforeConnect =
        !call.wasConnected && call.direction == SoftphoneCallDirection.outgoing;
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: call.accountId,
        callId: call.callId,
        remoteIdentity: call.remoteIdentity,
        direction: call.direction,
        type: failedBeforeConnect
            ? SoftphoneCallEventType.failed
            : SoftphoneCallEventType.ended,
        occurredAt: DateTime.now(),
        reason: failedBeforeConnect
            ? 'Medya yolu kurulamadi. STUN/ICE devre disi birakildi; '
                'sunucuda rtp_symmetric=yes ayarini kontrol edin.'
            : null,
        isMuted: call.isMuted,
        isOnHold: call.isOnHold,
      ),
    );
    _activeCall = null;
    // Sonraki çağrı hoparlör kapalı (kulaklık) olarak başlamalı; aksi halde
    // önceki çağrıda açılan hoparlör bağlantı anında sessizce geri açılır.
    _pendingSpeakerEnabled = false;
  }

  Future<bool> _waitForRegistrationBeforeCall(
    SipAccount account, {
    required String callId,
  }) async {
    if (SipWrapper.wrapper.isRegistered) {
      return true;
    }

    debugPrint('ABTO call prep: SIP registration pending, waiting...');
    await _register(account);

    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      final call = _activeCall;
      if (call == null || call.callId != callId) {
        return false;
      }
      if (SipWrapper.wrapper.isRegistered) {
        debugPrint('ABTO call prep: registration confirmed');
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final call = _activeCall;
    if (call != null && call.callId == callId) {
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: call.accountId,
          callId: call.callId,
          remoteIdentity: call.remoteIdentity,
          direction: call.direction,
          type: SoftphoneCallEventType.failed,
          occurredAt: DateTime.now(),
          reason: 'SIP kaydi arama oncesinde tamamlanamadi.',
          isMuted: call.isMuted,
          isOnHold: call.isOnHold,
        ),
      );
      _activeCall = null;
    }
    debugPrint(
      'ABTO call prep: registration wait timed out; call cancelled',
    );
    return false;
  }

  static void _applyMediaNatConfig(AbtoPhoneCfg cfg, SipAccount account) {
    final stunServer = _normalizeStunServer(account.stunServer);
    if (stunServer.isEmpty) {
      // UDP + mobil/Wi-Fi NAT'ta STUN kapalıyken karşı PBX RTP adresini ancak
      // symmetric RTP öğrenmesinden sonra buluyor (ölçülen gecikme 23-25 sn).
      // TCP/WSS hesaplarda eski davranışı koru; UDP hesaplara güvenli bir STUN
      // varsayılanı ver. Hesapta özel STUN varsa aşağıdaki dal onu kullanır.
      final needsUdpNatTraversal = account.transport == SipTransport.udp;
      cfg.isSTUNEnabled = needsUdpNatTraversal;
      cfg.stunServer = needsUdpNatTraversal ? 'stun.l.google.com:19302' : '';
      cfg.isICEEnabled = false;
      debugPrint(
        needsUdpNatTraversal
            ? 'ABTO media config: UDP default STUN enabled, ICE disabled'
            : 'ABTO media config: STUN/ICE disabled',
      );
      return;
    }

    cfg.isSTUNEnabled = true;
    cfg.stunServer = stunServer;
    cfg.isICEEnabled = false;
    debugPrint('ABTO media config: STUN=$stunServer ICE disabled');
  }

  static void _applyAudioCodecConfig(AbtoPhoneCfg cfg) {
    // Dar ve lisanssız profil: farklı santrallerde G729/G723 seçiminin neden
    // olduğu sessiz/gecikmeli medya başlangıcını engelle. G.711 A/u-law tüm
    // hedef santrallerin ortak codec'idir.
    cfg.audioCodecs = <AudioCodec, int>{
      AudioCodec.PCMU: 250,
      AudioCodec.PCMA: 249,
      AudioCodec.G729: 0,
      AudioCodec.GSM: 0,
      AudioCodec.G723: 0,
      AudioCodec.ILBC: 0,
      AudioCodec.SPEEDX: 0,
      AudioCodec.G722: 0,
      AudioCodec.G722_1: 0,
      AudioCodec.AMR: 0,
      AudioCodec.SILK: 0,
      AudioCodec.OPUS: 0,
    };
    debugPrint('ABTO media config: PCMU/PCMA-only codec profile applied');
  }

  static String _normalizeStunServer(String raw) {
    var value = raw.trim();
    if (value.isEmpty) {
      return '';
    }

    for (final prefix in const ['stun:', 'stuns:']) {
      if (value.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
      }
    }

    return value;
  }

  void _onHoldState(HoldState state) {
    final call = _activeCall;
    if (call == null) {
      return;
    }

    final isOnHold = state != HoldState.ACTIVE;
    if (isOnHold == call.isOnHold) {
      return;
    }

    final updated = call.copyWith(isOnHold: isOnHold);
    _activeCall = updated;
    _emitCallUpdate(
      SoftphoneCallUpdate(
        accountId: updated.accountId,
        callId: updated.callId,
        remoteIdentity: updated.remoteIdentity,
        direction: updated.direction,
        type: SoftphoneCallEventType.holdChanged,
        occurredAt: DateTime.now(),
        isMuted: updated.isMuted,
        isOnHold: updated.isOnHold,
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

  void _scheduleRegistrationWatchdog(String accountId) {
    _registrationWatchdog?.cancel();
    _registrationProbe?.cancel();
    _registrationAttempt += 1;
    final attempt = _registrationAttempt;
    var probeCount = 0;
    _registrationProbe = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_activeAccountId != accountId || _registrationAttempt != attempt) {
        timer.cancel();
        return;
      }
      probeCount += 1;
      if (SipWrapper.wrapper.isRegistered) {
        timer.cancel();
        _emitRegistrationUpdate(
          SoftphoneRegistrationUpdate(
            accountId: accountId,
            status: RegistrationStatus.registered,
          ),
        );
        return;
      }
      if (probeCount >= 18) {
        timer.cancel();
      }
    });

    _registrationWatchdog = Timer(const Duration(seconds: 35), () {
      if (_activeAccountId != accountId || _registrationAttempt != attempt) {
        return;
      }
      if (SipWrapper.wrapper.isRegistered) {
        _emitRegistrationUpdate(
          SoftphoneRegistrationUpdate(
            accountId: accountId,
            status: RegistrationStatus.registered,
          ),
        );
        return;
      }
      _emitRegistrationUpdate(
        SoftphoneRegistrationUpdate(
          accountId: accountId,
          status: RegistrationStatus.failed,
          reason: 'REGISTER timeout (35s)',
        ),
      );
    });
  }

  void _scheduleOutgoingCallWatchdog(String callId) {
    _outgoingCallWatchdog?.cancel();
    _outgoingCallWatchdog = Timer(const Duration(seconds: 45), () {
      final call = _activeCall;
      if (call == null || call.callId != callId || call.wasConnected) {
        return;
      }

      debugPrint('ABTO outgoing call timed out before connecting: $callId');
      _emitCallUpdate(
        SoftphoneCallUpdate(
          accountId: call.accountId,
          callId: call.callId,
          remoteIdentity: call.remoteIdentity,
          direction: call.direction,
          type: SoftphoneCallEventType.failed,
          occurredAt: DateTime.now(),
          reason: 'Arama baslatilamadi veya zaman asimina ugradi.',
          isMuted: call.isMuted,
          isOnHold: call.isOnHold,
        ),
      );
      _activeCall = null;
      _pendingSpeakerEnabled = false;
    });
  }

  String _nextCallId() {
    _callSequence += 1;
    return 'abto-$_callSequence';
  }

  static bool _sameConfig(SipAccount current, SipAccount next) {
    return current.displayName == next.displayName &&
        current.username == next.username &&
        current.authorizationUser == next.authorizationUser &&
        current.password == next.password &&
        current.domain == next.domain &&
        current.transport == next.transport &&
        current.outboundProxy == next.outboundProxy &&
        current.stunServer == next.stunServer &&
        current.registrationExpireSeconds == next.registrationExpireSeconds;
  }

  static String _compactRemoteIdentity(String value) {
    final minified = StringUtil.minifySipContact(value);
    if (minified.isNotEmpty) {
      return minified;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }
}

class _AbtoCallBinding {
  const _AbtoCallBinding({
    required this.accountId,
    required this.callId,
    required this.direction,
    required this.remoteIdentity,
    required this.isOnHold,
    required this.isMuted,
    this.wasConnected = false,
    this.nativeCallStarted = false,
  });

  final String accountId;
  final String callId;
  final SoftphoneCallDirection direction;
  final String remoteIdentity;
  final bool isOnHold;
  final bool isMuted;
  final bool wasConnected;
  final bool nativeCallStarted;

  _AbtoCallBinding copyWith({
    String? remoteIdentity,
    bool? isOnHold,
    bool? isMuted,
    bool? wasConnected,
    bool? nativeCallStarted,
  }) {
    return _AbtoCallBinding(
      accountId: accountId,
      callId: callId,
      direction: direction,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
      isOnHold: isOnHold ?? this.isOnHold,
      isMuted: isMuted ?? this.isMuted,
      wasConnected: wasConnected ?? this.wasConnected,
      nativeCallStarted: nativeCallStarted ?? this.nativeCallStarted,
    );
  }
}
