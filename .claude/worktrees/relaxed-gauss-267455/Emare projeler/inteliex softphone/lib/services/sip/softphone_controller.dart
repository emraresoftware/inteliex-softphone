import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/directory/contact_directory_provider.dart';
import '../../core/directory/inteliex_contact_directory_provider.dart';
import '../../core/models/active_call.dart';
import '../../core/models/call_log_entry.dart';
import '../../core/models/contact_entry.dart';
import '../../core/models/sip_account.dart';
import '../../core/storage/softphone_persistence.dart';
import '../../platform/voip/create_voip_platform_bridge.dart';
import '../../platform/voip/voip_platform_bridge.dart';
import 'sip_device_profile_service.dart';
import 'create_softphone_sip_service.dart';
import 'sip_foreground_service.dart';
import 'softphone_sip_service.dart';

class SoftphoneController extends ChangeNotifier
    implements SoftphoneSipServiceListener {
  SoftphoneController._({
    required List<SipAccount> seedAccounts,
    required List<ContactEntry> seedContacts,
    required List<CallLogEntry> seedHistory,
    required ContactDirectoryProvider directoryProvider,
    required VoipPlatformBridge platformBridge,
    required SoftphoneSipService sipService,
    required SoftphonePersistence persistence,
    required SipForegroundService foregroundService,
    String? initialSelectedAccountId,
  })  : _accounts = List<SipAccount>.of(seedAccounts),
        _contacts = List<ContactEntry>.of(seedContacts),
        _callLogs = List<CallLogEntry>.of(seedHistory),
        _directoryProvider = directoryProvider,
        _platformBridge = platformBridge,
        _sipService = sipService,
        _persistence = persistence,
        _foregroundService = foregroundService {
    _applyContactDirectory(
      extensionContacts: seedContacts,
      sharedContacts: const <ContactEntry>[],
      personalContacts: const <ContactEntry>[],
      directoryStatus: 'Ornek rehber kayitlari gosteriliyor.',
    );

    if (_accounts.isNotEmpty) {
      final preferredAccount = _accounts.any(
        (account) => account.id == initialSelectedAccountId,
      )
          ? _accounts.firstWhere(
              (account) => account.id == initialSelectedAccountId,
            )
          : _accounts.firstWhere(
              (account) => account.isPrimary,
              orElse: () => _accounts.first,
            );

      _selectedAccountId = preferredAccount.id;
      _replaceAccounts(
        _accounts.map(
          (account) =>
              account.copyWith(isPrimary: account.id == preferredAccount.id),
        ),
      );
    }

    _statusLine = _accounts.any((account) => account.password.trim().isEmpty)
        ? 'Bazi hesaplarin SIP sifresi Android secure storage icinden yuklenemedi. Hesabi duzenleyip sifreyi tekrar girin.'
        : 'SIP hesaplari hazirlaniyor.';

    _sipService.addListener(this);
    unawaited(_platformBridge.initialize());
    unawaited(_initializeSipService());
    unawaited(_syncPlatformRegistration());
    unawaited(_rehydratePersistedAccounts());
    unawaited(_ensureDebugSeedAccount());
    unawaited(refreshContactDirectory());
  }

  static Future<SoftphoneController> bootstrap({
    ContactDirectoryProvider? directoryProvider,
    SipForegroundService? foregroundService,
  }) async {
    final persistence = DeviceSoftphonePersistence();
    final persistedState = await persistence.load();
    final autoSeedAccounts = await _buildSeedAccounts();
    final seedAccounts = persistedState.accounts.isNotEmpty
        ? persistedState.accounts
        : autoSeedAccounts;
    final selectedAccountId = persistedState.accounts.isNotEmpty
        ? persistedState.selectedAccountId
        : autoSeedAccounts.isNotEmpty
            ? autoSeedAccounts.first.id
            : persistedState.selectedAccountId;

    debugPrint(
      'Softphone bootstrap: hasStoredAccounts=${persistedState.hasStoredAccounts} loadedAccounts=${persistedState.accounts.length} seededAccounts=${autoSeedAccounts.length} selected=$selectedAccountId',
    );

    return SoftphoneController._(
      seedAccounts: seedAccounts,
      seedContacts: _buildSeedContacts(),
      seedHistory: persistedState.callLogs.isEmpty
          ? _buildSeedHistory()
          : persistedState.callLogs,
      initialSelectedAccountId: selectedAccountId,
      directoryProvider:
          directoryProvider ?? InteliexContactDirectoryProvider(),
      platformBridge: createVoipPlatformBridge(),
      sipService: createSoftphoneSipService(),
      persistence: persistence,
      foregroundService: foregroundService ?? SipForegroundService(),
    );
  }

  final List<SipAccount> _accounts;
  final List<ContactEntry> _extensionContacts = <ContactEntry>[];
  final List<ContactEntry> _sharedContacts = <ContactEntry>[];
  final List<ContactEntry> _personalContacts = <ContactEntry>[];
  final List<ContactEntry> _contacts;
  final List<CallLogEntry> _callLogs;
  final ContactDirectoryProvider _directoryProvider;
  final Map<String, String?> _registrationReasons = <String, String?>{};
  final VoipPlatformBridge _platformBridge;
  final SoftphoneSipService _sipService;
  final SoftphonePersistence _persistence;
  final SipForegroundService _foregroundService;

  ActiveCall? _activeCall;
  String _dialedNumber = '';
  String _directoryStatus = 'Ornek rehber kayitlari gosteriliyor.';
  String _statusLine = '';
  int _currentTabIndex = 0;
  String? _selectedAccountId;
  bool _isLoadingDirectory = false;
  final Set<String> _serviceManagedCallIds = <String>{};
  final Map<String, CallDisposition> _pendingServiceDispositions =
      <String, CallDisposition>{};

  List<SipAccount> get accounts => List.unmodifiable(_accounts);
  List<ContactEntry> get extensionContacts =>
      List.unmodifiable(_extensionContacts);
  List<ContactEntry> get sharedContacts => List.unmodifiable(_sharedContacts);
  List<ContactEntry> get personalContacts =>
      List.unmodifiable(_personalContacts);
  List<ContactEntry> get contacts => List.unmodifiable(_contacts);
  List<CallLogEntry> get callLogs => List.unmodifiable(_callLogs);
  ActiveCall? get activeCall => _activeCall;
  String get dialedNumber => _dialedNumber;
  String get directoryStatus => _directoryStatus;
  bool get isLoadingDirectory => _isLoadingDirectory;
  String get statusLine => _statusLine;
  int get currentTabIndex => _currentTabIndex;

  SipAccount? get selectedAccount {
    if (_selectedAccountId == null) {
      return _accounts.isEmpty ? null : _accounts.first;
    }

    for (final account in _accounts) {
      if (account.id == _selectedAccountId) {
        return account;
      }
    }

    return _accounts.isEmpty ? null : _accounts.first;
  }

  String get registrationSummary {
    final registeredCount = _accounts
        .where((account) =>
            account.registrationStatus == RegistrationStatus.registered)
        .length;

    return '$registeredCount/${_accounts.length} kayitli';
  }

  bool get canDial =>
      selectedAccount != null &&
      _dialedNumber.isNotEmpty &&
      _activeCall == null;

  bool isServiceManagedCall(String callId) =>
      _serviceManagedCallIds.contains(callId);

  SipAccount? accountById(String accountId) => _findAccount(accountId);

  String? registrationReasonFor(String accountId) {
    final reason = _registrationReasons[accountId]?.trim();
    if (reason == null || reason.isEmpty) {
      return null;
    }

    return reason;
  }

  @override
  void dispose() {
    _sipService.removeListener(this);
    unawaited(_directoryProvider.close());
    unawaited(_sipService.dispose());
    unawaited(_platformBridge.dispose());
    unawaited(_foregroundService.stop());
    super.dispose();
  }

  void setCurrentTab(int index) {
    if (_currentTabIndex == index) {
      return;
    }

    _currentTabIndex = index;
    notifyListeners();
  }

  void appendDigit(String digit) {
    if (digit.isEmpty) {
      return;
    }

    _dialedNumber = '$_dialedNumber$digit';
    notifyListeners();
  }

  void clearLastDigit() {
    if (_dialedNumber.isEmpty) {
      return;
    }

    _dialedNumber = _dialedNumber.substring(0, _dialedNumber.length - 1);
    notifyListeners();
  }

  void fillDialedNumber(String value) {
    _dialedNumber = value;
    _currentTabIndex = 0;
    _statusLine = '$value hazirlandi';
    notifyListeners();
  }

  Future<void> refreshContactDirectory() async {
    final selected = selectedAccount;
    if (!_canLoadDirectory(selected)) {
      _isLoadingDirectory = false;
      _applySeedContacts(
        directoryStatus: selected == null
            ? 'Rehber icin once bir SIP hesabi secin.'
            : 'Bu hesap icin sunucu rehberi tanimli degil. Ornek kayitlar gosteriliyor.',
      );
      notifyListeners();
      return;
    }

    final account = selected!;

    _isLoadingDirectory = true;
    _directoryStatus = 'Sunucu rehberi yukleniyor...';
    notifyListeners();

    try {
      final directory =
          await _directoryProvider.fetchForAccount(account);
      if (!_isSameSelectedAccount(account.id)) {
        return;
      }

      _applyContactDirectory(
        extensionContacts: directory.extensionContacts,
        sharedContacts: directory.sharedContacts,
        personalContacts: directory.personalContacts,
        directoryStatus: directory.isEmpty
            ? 'Sunucu rehberinde kayit bulunamadi.'
            : 'Sunucu rehberi guncellendi.',
      );
      _statusLine = directory.isEmpty
          ? 'Sunucu rehberinde kayit bulunamadi.'
          : '${directory.extensionContacts.length} dahili, ${directory.sharedContacts.length} genel rehber ve ${directory.personalContacts.length} kisisel rehber kaydi yuklendi.';
    } on ContactDirectoryException catch (error) {
      if (!_isSameSelectedAccount(account.id)) {
        return;
      }

      _applySeedContacts(
        directoryStatus:
            'Sunucu rehberi yuklenemedi. Ornek kayitlar gosteriliyor.',
      );
      _statusLine = _directoryFailureMessage(error.failure);
    } catch (_) {
      if (!_isSameSelectedAccount(account.id)) {
        return;
      }

      _applySeedContacts(
        directoryStatus:
            'Sunucu rehberi yuklenemedi. Ornek kayitlar gosteriliyor.',
      );
      _statusLine = 'Sunucu rehberine baglanilamadi.';
    } finally {
      if (_isSameSelectedAccount(account.id)) {
        _isLoadingDirectory = false;
        notifyListeners();
      }
    }
  }

  Future<bool> addAccount({
    required String displayName,
    required String username,
    String? authorizationUser,
    required String password,
    required String domain,
    required String signalingAddress,
    SipTransport transport = SipTransport.wss,
    bool allowBadCertificate = false,
    String outboundProxy = '',
    String stunServer = '',
    int registrationExpireSeconds =
        SipAccount.defaultRegistrationExpireSeconds,
  }) async {
    final trimmedDisplayName = displayName.trim();
    final trimmedUsername = username.trim();
    final trimmedAuthorizationUser = (authorizationUser ?? username).trim();
    final trimmedPassword = password.trim();
    final trimmedDomain = domain.trim();
    final trimmedSignalingAddress = signalingAddress.trim();
    final trimmedOutboundProxy = outboundProxy.trim();
    final trimmedStunServer = stunServer.trim();
    final normalizedExpire = _normalizeExpireSeconds(
      registrationExpireSeconds,
    );

    if (trimmedDisplayName.isEmpty ||
        trimmedUsername.isEmpty ||
        trimmedAuthorizationUser.isEmpty ||
        trimmedPassword.isEmpty ||
        trimmedDomain.isEmpty) {
      _statusLine = 'Tum hesap alanlarini doldurun.';
      notifyListeners();
      return false;
    }

    final signalingAddressError = _validateSignalingAddress(
      trimmedSignalingAddress,
      transport,
    );
    if (signalingAddressError != null) {
      _statusLine = signalingAddressError;
      notifyListeners();
      return false;
    }

    final accountId = 'account-${DateTime.now().microsecondsSinceEpoch}';
    final shouldBePrimary = _accounts.isEmpty;

    _accounts.insert(
      0,
      SipAccount(
        id: accountId,
        displayName: trimmedDisplayName,
        username: trimmedUsername,
        authorizationUser: trimmedAuthorizationUser,
        password: trimmedPassword,
        domain: trimmedDomain,
        websocketUrl: trimmedSignalingAddress,
        registrationStatus: RegistrationStatus.connecting,
        transport: transport,
        allowBadCertificate: allowBadCertificate,
        isPrimary: shouldBePrimary,
        outboundProxy: trimmedOutboundProxy,
        stunServer: trimmedStunServer,
        registrationExpireSeconds: normalizedExpire,
      ),
    );

    if (shouldBePrimary) {
      _selectedAccountId = accountId;
    }

    _statusLine = '$trimmedDisplayName hesabi eklendi.';
    notifyListeners();
    await _persistAccounts();
    unawaited(_syncSipAccounts());
    unawaited(_syncPlatformRegistration());
    if (shouldBePrimary) {
      unawaited(refreshContactDirectory());
    }
    return true;
  }

  Future<bool> updateAccount({
    required String accountId,
    required String displayName,
    required String username,
    String? authorizationUser,
    required String password,
    required String domain,
    required String signalingAddress,
    SipTransport transport = SipTransport.wss,
    bool allowBadCertificate = false,
    String outboundProxy = '',
    String stunServer = '',
    int registrationExpireSeconds =
        SipAccount.defaultRegistrationExpireSeconds,
  }) async {
    final currentAccount = _findAccount(accountId);
    if (currentAccount == null) {
      _statusLine = 'Duzenlenecek hesap bulunamadi.';
      notifyListeners();
      return false;
    }

    final activeCall = _activeCall;
    if (activeCall != null && activeCall.accountId == accountId) {
      _statusLine = 'Aktif cagri varken bu hesap duzenlenemez.';
      notifyListeners();
      return false;
    }

    final trimmedDisplayName = displayName.trim();
    final trimmedUsername = username.trim();
    final trimmedAuthorizationUser = (authorizationUser ?? username).trim();
    final trimmedPassword = password.trim();
    final trimmedDomain = domain.trim();
    final trimmedSignalingAddress = signalingAddress.trim();
    final trimmedOutboundProxy = outboundProxy.trim();
    final trimmedStunServer = stunServer.trim();
    final normalizedExpire = _normalizeExpireSeconds(
      registrationExpireSeconds,
    );

    if (trimmedDisplayName.isEmpty ||
        trimmedUsername.isEmpty ||
        trimmedAuthorizationUser.isEmpty ||
        trimmedPassword.isEmpty ||
        trimmedDomain.isEmpty) {
      _statusLine = 'Tum hesap alanlarini doldurun.';
      notifyListeners();
      return false;
    }

    final signalingAddressError = _validateSignalingAddress(
      trimmedSignalingAddress,
      transport,
    );
    if (signalingAddressError != null) {
      _statusLine = signalingAddressError;
      notifyListeners();
      return false;
    }

    _replaceAccount(
      currentAccount.copyWith(
        displayName: trimmedDisplayName,
        username: trimmedUsername,
        authorizationUser: trimmedAuthorizationUser,
        password: trimmedPassword,
        domain: trimmedDomain,
        websocketUrl: trimmedSignalingAddress,
        registrationStatus: RegistrationStatus.connecting,
        transport: transport,
        allowBadCertificate: allowBadCertificate,
        outboundProxy: trimmedOutboundProxy,
        stunServer: trimmedStunServer,
        registrationExpireSeconds: normalizedExpire,
      ),
    );

    _statusLine = '$trimmedDisplayName hesabi guncellendi.';
    notifyListeners();
    await _persistAccounts();
    unawaited(_syncSipAccounts());
    unawaited(_syncPlatformRegistration());
    if (_selectedAccountId == accountId) {
      unawaited(refreshContactDirectory());
    }
    return true;
  }

  Future<bool> deleteAccount(String accountId) async {
    final currentAccount = _findAccount(accountId);
    if (currentAccount == null) {
      _statusLine = 'Silinecek hesap bulunamadi.';
      notifyListeners();
      return false;
    }

    final activeCall = _activeCall;
    if (activeCall != null && activeCall.accountId == accountId) {
      _statusLine = 'Aktif cagri varken bu hesap silinemez.';
      notifyListeners();
      return false;
    }

    final remainingAccounts = _accounts
        .where((account) => account.id != accountId)
        .toList(growable: false);

    String? nextSelectedAccountId;
    if (remainingAccounts.isNotEmpty) {
      final keepCurrentSelection = _selectedAccountId != null &&
          _selectedAccountId != accountId &&
          remainingAccounts.any(
            (account) => account.id == _selectedAccountId,
          );

      if (keepCurrentSelection) {
        nextSelectedAccountId = _selectedAccountId;
      } else {
        nextSelectedAccountId = remainingAccounts
            .firstWhere(
              (account) => account.isPrimary,
              orElse: () => remainingAccounts.first,
            )
            .id;
      }
    }

    _selectedAccountId = nextSelectedAccountId;
    _replaceAccounts(
      remainingAccounts.map(
        (account) =>
            account.copyWith(isPrimary: account.id == nextSelectedAccountId),
      ),
    );

    _statusLine = remainingAccounts.isEmpty
        ? '${currentAccount.displayName} hesabi silindi. Kayitli hesap kalmadi.'
        : '${currentAccount.displayName} hesabi silindi.';
    notifyListeners();
    await _persistAccounts();
    unawaited(_syncSipAccounts());
    unawaited(_syncPlatformRegistration());
    unawaited(refreshContactDirectory());
    return true;
  }

  void selectAccount(String accountId) {
    _selectedAccountId = accountId;
    _replaceAccounts(
      _accounts.map(
        (account) => account.copyWith(isPrimary: account.id == accountId),
      ),
    );

    final account = selectedAccount;
    _statusLine = account == null
        ? 'Aktif hesap secilemedi.'
        : '${account.displayName} aktif hesap oldu.';
    unawaited(_persistAccounts());
    unawaited(_syncPlatformRegistration());
    unawaited(refreshContactDirectory());
    notifyListeners();
  }

  void reconnectAccount(String accountId) {
    final account = _findAccount(accountId);
    if (account == null) {
      return;
    }

    _replaceAccount(
      account.copyWith(registrationStatus: RegistrationStatus.connecting),
    );
    _statusLine = '${account.displayName} yeniden kayitlaniyor.';
    unawaited(_sipService.reconnectAccount(accountId));
    unawaited(_syncPlatformRegistration());
    notifyListeners();
  }

  void startOutgoingCall([String? target]) {
    if (_activeCall != null) {
      _statusLine = 'Yeni arama icin once aktif cagrayi kapatin.';
      notifyListeners();
      return;
    }

    final account = selectedAccount;
    final number = (target ?? _dialedNumber).trim();

    if (account == null) {
      _statusLine = 'Arama icin once bir SIP hesabi secin.';
      notifyListeners();
      return;
    }

    if (number.isEmpty) {
      _statusLine = 'Arama numarasi bos olamaz.';
      notifyListeners();
      return;
    }

    if (account.registrationStatus != RegistrationStatus.registered) {
      _statusLine = '${account.displayName} henuz kayitli degil.';
      notifyListeners();
      return;
    }

    _currentTabIndex = 0;
    _dialedNumber = number;
    _statusLine = '$number icin SIP INVITE gonderiliyor...';
    notifyListeners();
    unawaited(_startOutgoingCallWithService(account.id, number));
  }

  void simulateIncomingCall([String from = '1001']) {
    if (_activeCall != null) {
      _statusLine = 'Zaten aktif veya bekleyen bir cagri var.';
      notifyListeners();
      return;
    }

    final account = selectedAccount;
    if (account == null) {
      _statusLine = 'Gelen cagri testi icin once hesap secin.';
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final sessionId = 'call-${now.microsecondsSinceEpoch}';

    _activeCall = ActiveCall(
      id: sessionId,
      accountId: account.id,
      remoteIdentity: from,
      phase: CallPhase.incomingRinging,
      startedAt: now,
    );

    _statusLine = '$from numarasindan gelen cagri var.';
    _callLogs.insert(
      0,
      CallLogEntry(
        sessionId: sessionId,
        accountLabel: account.aor,
        remoteIdentity: from,
        direction: CallDirection.incoming,
        disposition: CallDisposition.ringing,
        startedAt: now,
      ),
    );
    unawaited(_persistCallLogs());
    unawaited(
      _platformBridge.reportIncomingCall(
        callId: sessionId,
        handle: from,
        displayName: account.displayName,
      ),
    );
    notifyListeners();
  }

  void answerCall() {
    final call = _activeCall;
    if (call == null) {
      return;
    }

    if (isServiceManagedCall(call.id)) {
      _statusLine = '${call.remoteIdentity} cevaplaniyor...';
      notifyListeners();
      unawaited(_answerServiceCall(call.id));
      return;
    }

    _markActiveCallConnected();
  }

  void connectActiveCall() {
    final call = _activeCall;
    if (call == null) {
      return;
    }

    if (isServiceManagedCall(call.id)) {
      _statusLine =
          'Gercek SIP cagrilarinda baglanti karsi tarafin cevabiyla ilerler.';
      notifyListeners();
      return;
    }

    _markActiveCallConnected();
  }

  void declineCall() {
    if (_activeCall == null) {
      return;
    }

    final call = _activeCall!;
    if (isServiceManagedCall(call.id)) {
      _pendingServiceDispositions[call.id] = CallDisposition.declined;
      _statusLine = '${call.remoteIdentity} reddediliyor.';
      notifyListeners();
      unawaited(_sipService.decline(call.id));
      return;
    }

    _updateCallLog(
      call.id,
      disposition:
          call.isIncoming ? CallDisposition.declined : CallDisposition.ended,
      endedAt: DateTime.now(),
    );

    _statusLine = '${call.remoteIdentity} cagri kapatildi.';
    _activeCall = null;
    unawaited(
      _platformBridge.reportCallEnded(
        callId: call.id,
        reason: 'declined',
      ),
    );
    notifyListeners();
  }

  void endCall() {
    if (_activeCall == null) {
      return;
    }

    final call = _activeCall!;
    if (isServiceManagedCall(call.id)) {
      _pendingServiceDispositions[call.id] = call.isConnected
          ? CallDisposition.ended
          : call.phase == CallPhase.incomingRinging
              ? CallDisposition.missed
              : CallDisposition.ended;
      _statusLine = '${call.remoteIdentity} gorusmesi sonlandiriliyor.';
      notifyListeners();
      unawaited(_sipService.end(call.id));
      return;
    }

    _updateCallLog(
      call.id,
      disposition: call.isConnected
          ? CallDisposition.ended
          : call.isIncoming
              ? CallDisposition.missed
              : CallDisposition.ended,
      endedAt: DateTime.now(),
    );

    _statusLine = '${call.remoteIdentity} gorusmesi sonlandirildi.';
    _activeCall = null;
    unawaited(
      _platformBridge.reportCallEnded(
        callId: call.id,
        reason: 'ended',
      ),
    );
    notifyListeners();
  }

  void toggleMute() {
    final call = _activeCall;
    if (call == null || !call.isConnected) {
      _statusLine = 'Mute icin bagli cagri gerekir.';
      notifyListeners();
      return;
    }

    if (isServiceManagedCall(call.id)) {
      final nextMuted = !call.isMuted;
      _activeCall = call.copyWith(isMuted: nextMuted);
      _statusLine = nextMuted ? 'Mikrofon kapatiliyor.' : 'Mikrofon aciliyor.';
      notifyListeners();
      unawaited(_sipService.setMuted(call.id, nextMuted));
      return;
    }

    _activeCall = call.copyWith(isMuted: !call.isMuted);
    _statusLine = call.isMuted ? 'Mikrofon acildi.' : 'Mikrofon kapatildi.';
    notifyListeners();
  }

  void toggleHold() {
    final call = _activeCall;
    if (call == null || !call.isConnected) {
      _statusLine = 'Hold icin bagli cagri gerekir.';
      notifyListeners();
      return;
    }

    if (isServiceManagedCall(call.id)) {
      final nextHold = !call.isOnHold;
      _activeCall = call.copyWith(isOnHold: nextHold);
      _statusLine = nextHold
          ? 'Cagri hold durumuna aliniyor.'
          : 'Cagri hold durumundan cikiyor.';
      notifyListeners();
      unawaited(_sipService.setHeld(call.id, nextHold));
      return;
    }

    _activeCall = call.copyWith(isOnHold: !call.isOnHold);
    _statusLine = call.isOnHold
        ? 'Cagri hold durumundan cikti.'
        : 'Cagri hold durumuna alindi.';
    notifyListeners();
  }

  void sendDtmf(String tone) {
    final call = _activeCall;
    if (call == null || !call.isConnected) {
      _statusLine = 'DTMF icin bagli cagri gerekir.';
      notifyListeners();
      return;
    }

    if (isServiceManagedCall(call.id)) {
      _statusLine = '$tone tonu gonderiliyor.';
      notifyListeners();
      unawaited(_sipService.sendDtmf(call.id, tone));
      return;
    }

    _statusLine = '$tone tonu gonderildi.';
    notifyListeners();
  }

  @override
  void onRegistrationUpdate(SoftphoneRegistrationUpdate update) {
    final account = _findAccount(update.accountId);
    if (account == null) {
      return;
    }

    _replaceAccount(account.copyWith(registrationStatus: update.status));
    if (update.status == RegistrationStatus.failed &&
        update.reason != null &&
        update.reason!.trim().isNotEmpty) {
      _registrationReasons[update.accountId] = update.reason!.trim();
    } else if (update.status == RegistrationStatus.registered ||
        update.status == RegistrationStatus.connecting) {
      _registrationReasons.remove(update.accountId);
    }
    _statusLine = switch (update.status) {
      RegistrationStatus.registered => '${account.displayName} kayitli.',
      RegistrationStatus.connecting => '${account.displayName} baglaniyor...',
      RegistrationStatus.failed =>
        '${account.displayName} kaydi basarisiz: ${update.reason ?? 'neden yok'}',
      RegistrationStatus.disconnected => '${account.displayName} ayrildi.',
    };

    unawaited(_syncPlatformRegistration());
    notifyListeners();
  }

  @override
  void onCallUpdate(SoftphoneCallUpdate update) {
    final existingActiveCall = _activeCall;
    final isNewCall =
        existingActiveCall != null && existingActiveCall.id != update.callId;
    if (isNewCall &&
        (update.type == SoftphoneCallEventType.incomingRinging ||
            update.type == SoftphoneCallEventType.outgoingRinging)) {
      _statusLine =
          'Tek aktif cagri destekleniyor; yeni cagri beklemeye alinamadi.';
      notifyListeners();
      return;
    }

    _serviceManagedCallIds.add(update.callId);

    switch (update.type) {
      case SoftphoneCallEventType.incomingRinging:
      case SoftphoneCallEventType.outgoingRinging:
        _beginServiceManagedCall(update);
        break;
      case SoftphoneCallEventType.progressing:
        _statusLine = '${update.remoteIdentity} caliyor...';
        break;
      case SoftphoneCallEventType.connected:
        _markServiceCallConnected(update);
        break;
      case SoftphoneCallEventType.mutedChanged:
        _updateServiceCallFlags(update, muted: true);
        break;
      case SoftphoneCallEventType.holdChanged:
        _updateServiceCallFlags(update, muted: false);
        break;
      case SoftphoneCallEventType.ended:
      case SoftphoneCallEventType.failed:
        _finishServiceCall(update);
        break;
    }

    notifyListeners();
  }

  void _markActiveCallConnected() {
    final call = _activeCall;
    if (call == null) {
      return;
    }

    _activeCall = call.copyWith(
      phase: CallPhase.connected,
      connectedAt: DateTime.now(),
    );
    _updateCallLog(
      call.id,
      disposition: CallDisposition.answered,
    );
    _statusLine = '${call.remoteIdentity} ile medya akisi basladi.';
    unawaited(
      _platformBridge.reportCallConnected(
        callId: call.id,
        handle: call.remoteIdentity,
      ),
    );
    notifyListeners();
  }

  Future<void> _syncPlatformRegistration() {
    final activeAccount = selectedAccount;
    final registeredCount = _accounts
        .where((account) =>
            account.registrationStatus == RegistrationStatus.registered)
        .length;

    unawaited(_syncForegroundService(
      registeredCount: registeredCount,
      activeAccount: activeAccount,
    ));

    return _platformBridge.syncRegistration(
      activeAccountAor: activeAccount?.aor,
      registeredAccounts: registeredCount,
      totalAccounts: _accounts.length,
    );
  }

  Future<void> _syncForegroundService({
    required int registeredCount,
    required SipAccount? activeAccount,
  }) async {
    if (_accounts.isEmpty) {
      await _foregroundService.stop();
      return;
    }

    final label = activeAccount?.displayName.trim();
    final aor = activeAccount?.aor;
    final text = registeredCount > 0
        ? (label != null && label.isNotEmpty)
            ? '$label kayitli ($registeredCount/${_accounts.length})'
            : aor != null
                ? '$aor kayitli ($registeredCount/${_accounts.length})'
                : '$registeredCount/${_accounts.length} hesap kayitli'
        : '${_accounts.length} hesap baglanti deniyor';

    await _foregroundService.start(
      title: 'Softphone etkin',
      text: text,
    );
  }

  Future<void> _initializeSipService() async {
    await _sipService.initialize();
    await _syncSipAccounts();
  }

  Future<void> _rehydratePersistedAccounts() async {
    final persistedState = await _persistence.load();
    if (!persistedState.hasStoredAccounts) {
      return;
    }

    if (persistedState.accounts.isEmpty) {
      if (_accounts.isEmpty) {
        _statusLine =
            'Kayitli hesap verisi bulundu ama acilista geri yuklenemedi. Hesabi duzenleyip tekrar kaydedin.';
        notifyListeners();
        unawaited(_ensureDebugSeedAccount());
      }
      return;
    }

    final persistedIds =
        persistedState.accounts.map((account) => account.id).toSet();
    final currentIds = _accounts.map((account) => account.id).toSet();
    final usingSeedFallback = currentIds.contains('account-primary') &&
        currentIds.contains('account-sales');
    final shouldReplaceAccounts = _accounts.isEmpty ||
        usingSeedFallback ||
        currentIds.length != persistedIds.length ||
        !currentIds.containsAll(persistedIds);

    if (!shouldReplaceAccounts) {
      return;
    }

    final preferredAccount = persistedState.accounts.any(
      (account) => account.id == persistedState.selectedAccountId,
    )
        ? persistedState.accounts.firstWhere(
            (account) => account.id == persistedState.selectedAccountId,
          )
        : persistedState.accounts.firstWhere(
            (account) => account.isPrimary,
            orElse: () => persistedState.accounts.first,
          );

    _selectedAccountId = preferredAccount.id;
    _replaceAccounts(
      persistedState.accounts.map(
        (account) =>
            account.copyWith(isPrimary: account.id == preferredAccount.id),
      ),
    );

    _statusLine = persistedState.hasMissingSecrets
        ? 'Bazi hesaplarin SIP sifresi Android secure storage icinden yuklenemedi. Hesabi duzenleyip sifreyi tekrar girin.'
        : '${_accounts.length} hesap cihazdan geri yuklendi.';

    await _syncSipAccounts();
    await _syncPlatformRegistration();
    await refreshContactDirectory();
    notifyListeners();
  }

  Future<void> _ensureDebugSeedAccount() async {
    if (!kDebugMode || _accounts.isNotEmpty) {
      return;
    }

    final seeds = await _buildSeedAccounts();
    if (seeds.isEmpty || _accounts.isNotEmpty) {
      return;
    }

    final preferred = seeds.first;
    _selectedAccountId = preferred.id;
    _replaceAccounts(
      seeds.map(
        (account) => account.copyWith(isPrimary: account.id == preferred.id),
      ),
    );

    _statusLine = '${preferred.displayName} debug hesabi otomatik eklendi.';
    notifyListeners();

    await _persistAccounts();
    await _syncSipAccounts();
    await _syncPlatformRegistration();
    await refreshContactDirectory();
  }

  Future<void> _syncSipAccounts() {
    return _sipService.syncAccounts(
      _accounts.where((account) => account.password.trim().isNotEmpty),
    );
  }

  Future<void> _persistAccounts() {
    return _persistence.saveAccounts(
      accounts: _accounts,
      selectedAccountId: _selectedAccountId,
    );
  }

  Future<void> _persistCallLogs() {
    return _persistence.saveCallLogs(_callLogs);
  }

  Future<void> _startOutgoingCallWithService(
      String accountId, String number) async {
    final started = await _sipService.startOutgoingCall(
      accountId: accountId,
      target: number,
    );

    if (!started) {
      _statusLine = '$number icin SIP INVITE baslatilamadi.';
      notifyListeners();
    }
  }

  Future<void> _answerServiceCall(String callId) async {
    final answered = await _sipService.answer(callId);
    if (!answered) {
      _statusLine = 'Cagri cevaplanamadi.';
      notifyListeners();
    }
  }

  void _beginServiceManagedCall(SoftphoneCallUpdate update) {
    final account = _findAccount(update.accountId);
    if (account == null) {
      return;
    }

    _dialedNumber = update.remoteIdentity;
    _activeCall = ActiveCall(
      id: update.callId,
      accountId: update.accountId,
      remoteIdentity: update.remoteIdentity,
      phase: update.direction == SoftphoneCallDirection.incoming
          ? CallPhase.incomingRinging
          : CallPhase.outgoingRinging,
      startedAt: update.occurredAt,
      isMuted: update.isMuted,
      isOnHold: update.isOnHold,
    );
    _currentTabIndex = 0;

    if (_callLogs.indexWhere((entry) => entry.sessionId == update.callId) ==
        -1) {
      _callLogs.insert(
        0,
        CallLogEntry(
          sessionId: update.callId,
          accountLabel: account.aor,
          remoteIdentity: update.remoteIdentity,
          direction: update.direction == SoftphoneCallDirection.incoming
              ? CallDirection.incoming
              : CallDirection.outgoing,
          disposition: CallDisposition.ringing,
          startedAt: update.occurredAt,
        ),
      );
      unawaited(_persistCallLogs());
    }

    if (update.direction == SoftphoneCallDirection.incoming) {
      _statusLine = '${update.remoteIdentity} numarasindan gelen cagri var.';
      unawaited(
        _platformBridge.reportIncomingCall(
          callId: update.callId,
          handle: update.remoteIdentity,
          displayName: account.displayName,
        ),
      );
      return;
    }

    _statusLine = '${update.remoteIdentity} araniyor...';
    unawaited(
      _platformBridge.reportOutgoingCall(
        callId: update.callId,
        handle: update.remoteIdentity,
        displayName: account.displayName,
      ),
    );
  }

  void _markServiceCallConnected(SoftphoneCallUpdate update) {
    final call = _activeCall;
    if (call == null || call.id != update.callId) {
      return;
    }

    _activeCall = call.copyWith(
      phase: CallPhase.connected,
      connectedAt: update.occurredAt,
      isMuted: update.isMuted,
      isOnHold: update.isOnHold,
    );
    _updateCallLog(update.callId, disposition: CallDisposition.answered);
    _statusLine = '${update.remoteIdentity} ile medya akisi basladi.';
    unawaited(
      _platformBridge.reportCallConnected(
        callId: update.callId,
        handle: update.remoteIdentity,
      ),
    );
  }

  void _updateServiceCallFlags(SoftphoneCallUpdate update,
      {required bool muted}) {
    final call = _activeCall;
    if (call == null || call.id != update.callId) {
      return;
    }

    _activeCall = call.copyWith(
      isMuted: update.isMuted,
      isOnHold: update.isOnHold,
    );

    if (muted) {
      _statusLine = update.isMuted ? 'Mikrofon kapatildi.' : 'Mikrofon acildi.';
      return;
    }

    _statusLine = update.isOnHold
        ? 'Cagri hold durumuna alindi.'
        : 'Cagri hold durumundan cikti.';
  }

  void _finishServiceCall(SoftphoneCallUpdate update) {
    final call = _activeCall;
    final finalDisposition =
        _pendingServiceDispositions.remove(update.callId) ??
            _inferDisposition(call, update);

    _updateCallLog(
      update.callId,
      disposition: finalDisposition,
      endedAt: update.occurredAt,
    );

    if (call != null && call.id == update.callId) {
      _activeCall = null;
      _statusLine = update.type == SoftphoneCallEventType.failed
          ? '${update.remoteIdentity} cagri hatasi: ${update.reason ?? 'neden yok'}'
          : '${update.remoteIdentity} gorusmesi sonlandirildi.';
    }

    _serviceManagedCallIds.remove(update.callId);
    unawaited(
      _platformBridge.reportCallEnded(
        callId: update.callId,
        reason: update.reason ?? 'ended',
      ),
    );
  }

  CallDisposition _inferDisposition(
      ActiveCall? call, SoftphoneCallUpdate update) {
    if (call == null) {
      return update.direction == SoftphoneCallDirection.incoming
          ? CallDisposition.missed
          : CallDisposition.ended;
    }

    if (call.isConnected) {
      return CallDisposition.ended;
    }

    if (call.phase == CallPhase.incomingRinging) {
      return CallDisposition.missed;
    }

    return CallDisposition.ended;
  }

  SipAccount? _findAccount(String accountId) {
    for (final account in _accounts) {
      if (account.id == accountId) {
        return account;
      }
    }

    return null;
  }

  void _replaceAccount(SipAccount updatedAccount) {
    final index =
        _accounts.indexWhere((account) => account.id == updatedAccount.id);
    if (index == -1) {
      return;
    }

    _accounts[index] = updatedAccount;
  }

  void _replaceAccounts(Iterable<SipAccount> accounts) {
    _accounts
      ..clear()
      ..addAll(accounts);
  }

  void _applySeedContacts({required String directoryStatus}) {
    _applyContactDirectory(
      extensionContacts: _buildSeedContacts(),
      sharedContacts: const <ContactEntry>[],
      personalContacts: const <ContactEntry>[],
      directoryStatus: directoryStatus,
    );
  }

  void _applyContactDirectory({
    required Iterable<ContactEntry> extensionContacts,
    required Iterable<ContactEntry> sharedContacts,
    required Iterable<ContactEntry> personalContacts,
    required String directoryStatus,
  }) {
    _extensionContacts
      ..clear()
      ..addAll(extensionContacts);
    _sharedContacts
      ..clear()
      ..addAll(sharedContacts);
    _personalContacts
      ..clear()
      ..addAll(personalContacts);
    _contacts
      ..clear()
      ..addAll(_extensionContacts)
      ..addAll(_sharedContacts)
      ..addAll(_personalContacts);
    _directoryStatus = directoryStatus;
  }

  bool _canLoadDirectory(SipAccount? account) {
    if (account == null || account.password.trim().isEmpty) {
      return false;
    }
    if (_isSeedAccount(account)) {
      return false;
    }
    return _directoryProvider.supports(account);
  }

  bool _isSeedAccount(SipAccount account) {
    return account.id == 'account-primary' || account.id == 'account-sales';
  }

  bool _isSameSelectedAccount(String accountId) {
    return selectedAccount?.id == accountId;
  }

  String _directoryFailureMessage(ContactDirectoryFailure failure) {
    switch (failure) {
      case ContactDirectoryFailure.authFailed:
        return 'Sunucu rehberi icin kimlik dogrulama basarisiz.';
      case ContactDirectoryFailure.notFound:
        return 'Sunucu rehberi kullaniciyi bulamadi.';
      case ContactDirectoryFailure.invalidRequest:
        return 'Sunucu rehberi istegi eksik alan nedeniyle reddedildi.';
      case ContactDirectoryFailure.unsupported:
        return 'Bu hesap icin sunucu rehberi desteklenmiyor.';
      case ContactDirectoryFailure.unknown:
        return 'Sunucu rehberine baglanilamadi.';
    }
  }

  void _updateCallLog(
    String sessionId, {
    CallDisposition? disposition,
    DateTime? endedAt,
  }) {
    final index = _callLogs.indexWhere((entry) => entry.sessionId == sessionId);
    if (index == -1) {
      return;
    }

    _callLogs[index] = _callLogs[index].copyWith(
      disposition: disposition,
      endedAt: endedAt,
    );
    unawaited(_persistCallLogs());
  }

  static int _normalizeExpireSeconds(int value) {
    if (value < SipAccount.minRegistrationExpireSeconds) {
      return SipAccount.minRegistrationExpireSeconds;
    }
    if (value > SipAccount.maxRegistrationExpireSeconds) {
      return SipAccount.maxRegistrationExpireSeconds;
    }
    return value;
  }

  static String? _validateSignalingAddress(
    String value,
    SipTransport transport,
  ) {
    if (value.isEmpty) {
      return 'Baglanti adresini girin.';
    }

    if (transport == SipTransport.tcp || transport == SipTransport.udp) {
      final uri = value.contains('://')
          ? Uri.tryParse(value)
          : Uri.tryParse('${transport.name}://$value');
      if (uri == null || uri.host.trim().isEmpty) {
        final label = transport == SipTransport.udp ? 'UDP' : 'TCP';
        return '$label icin host:port girin. Ornek: pbx.example.com:5060';
      }

      return null;
    }

    final uri = Uri.tryParse(value);
    final expectedScheme = transport == SipTransport.ws ? 'ws' : 'wss';
    if (uri == null ||
        uri.host.trim().isEmpty ||
        uri.scheme != expectedScheme) {
      return '${expectedScheme.toUpperCase()} adresi $expectedScheme:// ile baslamali.';
    }

    return null;
  }

  static Future<List<SipAccount>> _buildSeedAccounts() async {
    if (!kDebugMode) {
      return const <SipAccount>[];
    }

    final detectedProfile = await SipDeviceProfileService().getDeviceProfile();
    final profile = switch (detectedProfile) {
      'emulator' => 'emulator',
      'physical' => 'physical',
      _ => defaultTargetPlatform == TargetPlatform.android
          ? 'physical'
          : 'unknown',
    };

    if (profile == 'unknown') {
      return const <SipAccount>[];
    }

    if (detectedProfile != profile) {
      debugPrint(
        'Softphone debug auto-seed profile fallback: detected=$detectedProfile effective=$profile',
      );
    }

    final username = profile == 'emulator' ? 'elk-650-ext' : 'elk-600-ext';
    debugPrint(
      'Softphone debug auto-seed profile=$profile username=$username domain=demo1.sesdata.com',
    );
    final now = DateTime.now().microsecondsSinceEpoch;

    return <SipAccount>[
      SipAccount(
        id: 'account-debug-$profile-$now',
        displayName: username,
        username: username,
        authorizationUser: username,
        password: 'sesdata2025*',
        domain: 'demo1.sesdata.com',
        websocketUrl: 'demo1.sesdata.com:5060',
        registrationStatus: RegistrationStatus.connecting,
        transport: SipTransport.udp,
        allowBadCertificate: false,
        isPrimary: true,
      ),
    ];
  }

  static List<ContactEntry> _buildSeedContacts() {
    return const [
      ContactEntry(
        id: 'contact-1',
        displayName: 'Operasyon Desk',
        primaryNumber: '1001',
        department: 'Operasyon',
      ),
      ContactEntry(
        id: 'contact-2',
        displayName: 'Satis Ekibi',
        primaryNumber: '1002',
        department: 'Satis',
      ),
      ContactEntry(
        id: 'contact-3',
        displayName: 'Destek Masasi',
        primaryNumber: '1003',
        department: 'Teknik Destek',
      ),
    ];
  }

  static List<CallLogEntry> _buildSeedHistory() {
    final now = DateTime.now();

    return [
      CallLogEntry(
        sessionId: 'history-1',
        accountLabel: '101@pbx.inteliex.local',
        remoteIdentity: '1003',
        direction: CallDirection.outgoing,
        disposition: CallDisposition.ended,
        startedAt: now.subtract(const Duration(minutes: 16)),
        endedAt: now.subtract(const Duration(minutes: 11)),
      ),
      CallLogEntry(
        sessionId: 'history-2',
        accountLabel: '101@pbx.inteliex.local',
        remoteIdentity: '1002',
        direction: CallDirection.incoming,
        disposition: CallDisposition.missed,
        startedAt: now.subtract(const Duration(hours: 2, minutes: 8)),
        endedAt: now.subtract(const Duration(hours: 2, minutes: 8)),
      ),
    ];
  }
}
