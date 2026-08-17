import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/directory/contact_directory_provider.dart';
import '../../core/directory/inteliex_contact_directory_provider.dart';
import '../../core/inteliex_api/inteliex_mobile_api_client.dart';
import '../../core/models/active_call.dart';
import '../../core/models/call_log_entry.dart';
import '../../core/models/contact_entry.dart';
import '../../core/config/app_environment.dart';
import '../../core/models/sip_account.dart';
import '../../core/storage/softphone_persistence.dart';
import '../../platform/voip/create_voip_platform_bridge.dart';
import '../../platform/voip/voip_platform_bridge.dart';
import '../provisioning/claim_provisioning.dart';
import '../remote_diagnostics_service.dart';
import 'abto_softphone_service.dart';
import 'create_softphone_register_claim_service.dart';
import 'sip_device_identity_service.dart';
import 'create_softphone_sip_service.dart';
import 'sip_foreground_service.dart';
import 'sip_push_token_service.dart';
import 'softphone_register_claim_service.dart';
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
    required SoftphoneRegisterClaimService registerClaimService,
    required SipDeviceIdentityService deviceIdentityService,
    required SoftphonePersistence persistence,
    required SipForegroundService foregroundService,
    String? initialSelectedAccountId,
  })  : _accounts = List<SipAccount>.of(seedAccounts),
        _contacts = List<ContactEntry>.of(seedContacts),
        _callLogs = List<CallLogEntry>.of(seedHistory),
        _directoryProvider = directoryProvider,
        _platformBridge = platformBridge,
        _sipService = sipService,
        _registerClaimService = registerClaimService,
        _deviceIdentityService = deviceIdentityService,
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
      // ÖNEMLİ: .map LAZY iterable döner. _replaceAccounts önce clear() yapıp
      // sonra addAll yaparsa, lazy map zaten boş listeyi okur. .toList() ile
      // önceden materialize ediyoruz.
      _replaceAccounts(
        _accounts
            .map(
              (account) => account.copyWith(
                isPrimary: account.id == preferredAccount.id,
                registrationStatus: account.password.trim().isEmpty
                    ? RegistrationStatus.failed
                    : account.id == preferredAccount.id
                        ? RegistrationStatus.connecting
                        : RegistrationStatus.disconnected,
              ),
            )
            .toList(growable: false),
      );

      // Cold-start "Hatalı flicker"ı önlemek için: tüm hesaplar için
      // `lastConfirmed` zamanını şimdi olarak kabul et. Native register
      // gerçekten başarısız olsa bile ilk 8 sn'lik failure'ı UI'a yansıtmıyoruz
      // (bkz. onRegistrationUpdate içindeki recentlyConfirmed debounce'u).
      final now = DateTime.now();
      if (preferredAccount.password.trim().isNotEmpty) {
        _registrationConfirmedAt[preferredAccount.id] = now;
      }
    }

    _statusLine = _accounts.any((account) => account.password.trim().isEmpty)
        ? 'Bazi hesaplarin SIP sifresi Android secure storage icinden yuklenemedi. Hesabi duzenleyip sifreyi tekrar girin.'
        : 'SIP hesaplari hazirlaniyor.';

    _sipService.addListener(this);
    unawaited(_platformBridge.initialize());
    unawaited(_initializeSipService());
    unawaited(_syncPlatformRegistration());
    unawaited(refreshContactDirectory());
  }

  static Future<SoftphoneController> bootstrap({
    ContactDirectoryProvider? directoryProvider,
    SipForegroundService? foregroundService,
  }) async {
    final persistence = DeviceSoftphonePersistence();
    final persistedState = await persistence.load();
    final autoSeedAccounts = await _buildSeedAccounts();
    final useBuiltInSeeds =
        AppEnvironment.hasConfiguredSipSeed && autoSeedAccounts.isNotEmpty;
    final rawAccounts = useBuiltInSeeds
        ? autoSeedAccounts
        : persistedState.accounts.isNotEmpty
            ? persistedState.accounts
            : autoSeedAccounts;
    final seedAccounts =
        rawAccounts.map(_migrateRuntimeAccount).toList(growable: false);
    final selectedAccountId = useBuiltInSeeds
        ? autoSeedAccounts.first.id
        : persistedState.accounts.isNotEmpty
            ? persistedState.selectedAccountId
            : autoSeedAccounts.isNotEmpty
                ? autoSeedAccounts.first.id
                : persistedState.selectedAccountId;

    if (persistedState.hasStoredAccounts &&
        _accountsDifferByMigration(persistedState.accounts, seedAccounts)) {
      await persistence.saveAccounts(
        accounts: seedAccounts,
        selectedAccountId: selectedAccountId,
      );
      debugPrint(
        'Softphone bootstrap: migrated legacy host/IP accounts persisted.',
      );
    }

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
      registerClaimService: createSoftphoneRegisterClaimService(),
      deviceIdentityService: SipDeviceIdentityService(),
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
  final Map<String, DateTime> _registrationConfirmedAt = <String, DateTime>{};
  final VoipPlatformBridge _platformBridge;
  final SoftphoneSipService _sipService;
  final SoftphoneRegisterClaimService _registerClaimService;
  final SipDeviceIdentityService _deviceIdentityService;
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
      selectedAccount!.registrationStatus == RegistrationStatus.registered &&
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
      final directory = await _directoryProvider.fetchForAccount(account);
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
    int registrationExpireSeconds = SipAccount.defaultRegistrationExpireSeconds,
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

  /// QR / deeplink ile gelen [ClaimConfig]'ten SIP hesabi ekler.
  ///
  /// Mobil ABTO SDK WebSocket desteklemedigi icin transport HER ZAMAN UDP'dir.
  /// Sinyalizasyon adresi olarak config'in proxy'si (host:port) veya
  /// domain:sip_port kullanilir. addAccount sonrasi mevcut register + push
  /// zinciri (_syncSipAccounts / _checkRegisterPrecondition) otomatik tetiklenir.
  ///
  /// Basarisizsa [ArgumentError] atar (cagiran katman kullaniciya gosterir).
  Future<void> provisionFromClaim(ClaimConfig cfg) async {
    if (!cfg.isValid) {
      throw ArgumentError(
        'Sunucudan gelen SIP bilgileri eksik (kullanici / sifre / domain).',
      );
    }

    final signaling = cfg.signalingAddress;
    if (signaling.isEmpty) {
      throw ArgumentError(
        'Baglanti adresi olusturulamadi (domain / proxy bos).',
      );
    }

    final displayName = cfg.name.trim().isNotEmpty
        ? cfg.name.trim()
        : (cfg.user.trim().isNotEmpty ? cfg.user.trim() : cfg.ext.trim());

    final username = cfg.user.trim().isNotEmpty ? cfg.user.trim() : cfg.ext.trim();
    // ext ile user farkli ise auth user olarak user'i kullan; yoksa ext.
    final authUser = username;

    final added = await addAccount(
      displayName: displayName,
      username: username,
      authorizationUser: authUser,
      password: cfg.secret.trim(),
      domain: cfg.domain.trim(),
      signalingAddress: signaling,
      transport: SipTransport.udp,
      // UDP'de TLS yok; gecersiz sertifika izni anlamsizdir.
      allowBadCertificate: false,
      // proxy verildiyse addAccount signalingAddress zaten ayni; ekstra
      // outbound proxy'yi de dolduralim ki UDP INVITE'lari proxy'ye gitsin.
      outboundProxy: cfg.proxy.trim(),
    );

    if (!added) {
      // addAccount statusLine'i zaten set etti; cagirana bir istisna dondur.
      throw ArgumentError(
        _statusLine.isNotEmpty
            ? _statusLine
            : 'Hesap eklenemedi. Bilgileri kontrol edin.',
      );
    }
  }

  /// Claim istegi icin cihaz adini uretir (device= parametresi).
  /// Native uretici/model bilgisi varsa onu, yoksa sabit "mobil" doner.
  Future<String> resolveProvisionDeviceName() async {
    try {
      const channel = MethodChannel('inteliex_softphone/foreground');
      final manufacturer =
          (await channel.invokeMethod<String>('getDeviceManufacturer'))?.trim();
      if (manufacturer != null && manufacturer.isNotEmpty) {
        return manufacturer;
      }
    } catch (_) {
      // Native kanal yoksa ya da hata olursa sabit ada dus.
    }
    try {
      final id = await _deviceIdentityService.getOrCreateDeviceId();
      if (id.trim().isNotEmpty) {
        return 'mobil-${id.trim()}';
      }
    } catch (_) {}
    return 'mobil';
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
    int registrationExpireSeconds = SipAccount.defaultRegistrationExpireSeconds,
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
    if (_selectedAccountId == accountId) {
      return;
    }
    _selectedAccountId = accountId;
    _replaceAccounts(
      _accounts.map(
        (account) => account.copyWith(
          isPrimary: account.id == accountId,
          registrationStatus: account.id == accountId
              ? RegistrationStatus.connecting
              : RegistrationStatus.disconnected,
        ),
      ),
    );

    final account = selectedAccount;
    _statusLine = account == null
        ? 'Aktif hesap secilemedi.'
        : '${account.displayName} aktif hesap oldu.';
    unawaited(_persistAccounts());
    // ABTO tek aktif hesap ile calisir; secilen hesabi native tarafta da aktiflestir.
    unawaited(_reconnectWithPreCheck(accountId));
    unawaited(refreshContactDirectory());
    notifyListeners();
  }

  void reconnectAccount(String accountId) {
    final account = _findAccount(accountId);
    if (account == null) {
      return;
    }
    if (account.password.trim().isEmpty) {
      _statusLine =
          '${account.displayName} icin SIP sifresi eksik. Hesabi duzenleyip sifreyi tekrar girin.';
      notifyListeners();
      return;
    }

    if (account.registrationStatus != RegistrationStatus.registered) {
      _replaceAccount(
        account.copyWith(registrationStatus: RegistrationStatus.connecting),
      );
    }
    _statusLine = '${account.displayName} yeniden kayitlaniyor.';
    unawaited(_reconnectWithPreCheck(accountId));
    notifyListeners();
  }

  Future<void> _reconnectWithPreCheck(String accountId) async {
    final account = _findAccount(accountId);
    if (account == null) {
      return;
    }

    final allowed = await _checkRegisterPrecondition(
      account,
      source: 'manual_reconnect',
    );
    if (!allowed) {
      await _syncPlatformRegistration();
      return;
    }

    unawaited(
      _postRegisterEvent(
        account,
        status: RegisterEventStatus.started,
        reason: 'manual_reconnect',
      ),
    );
    await _sipService.reconnectAccount(accountId);
    await _syncPlatformRegistration();
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
    _statusLine = '$number icin SIP baglantisi hazirlaniyor...';
    notifyListeners();
    unawaited(_startOutgoingCallWithService(account.id, number));
  }

  void answerCall() {
    final call = _activeCall;
    if (call == null) {
      return;
    }

    unawaited(RemoteDiagnosticsService.instance.record(
      'call_action',
      details: <String, Object?>{
        'action': 'answer',
        'callId': call.id,
        'remote': call.remoteIdentity,
        'phase': call.phase.name,
      },
    ));

    if (isServiceManagedCall(call.id)) {
      _statusLine = '${call.remoteIdentity} cevaplaniyor...';
      notifyListeners();
      unawaited(_answerServiceCall(call.id));
      return;
    }

    _markActiveCallConnected();
  }

  void declineCall() {
    if (_activeCall == null) {
      return;
    }

    final call = _activeCall!;
    unawaited(RemoteDiagnosticsService.instance.record(
      'call_action',
      details: <String, Object?>{
        'action': 'decline',
        'callId': call.id,
        'remote': call.remoteIdentity,
        'phase': call.phase.name,
      },
    ));
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

  void toggleSpeaker() {
    final call = _activeCall;
    if (call == null) return;

    final nextSpeaker = !call.isSpeaker;
    _activeCall = call.copyWith(isSpeaker: nextSpeaker);
    _statusLine = nextSpeaker ? 'Hoparlor acildi.' : 'Hoparlor kapatildi.';
    notifyListeners();
    unawaited(_sipService.setSpeaker(nextSpeaker));
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

    final now = DateTime.now();
    final confirmedAt = _registrationConfirmedAt[update.accountId];
    final recentlyConfirmed = confirmedAt != null &&
        now.difference(confirmedAt) < const Duration(seconds: 8);

    final resolvedStatus = switch (update.status) {
      RegistrationStatus.connecting
          when account.registrationStatus == RegistrationStatus.registered =>
        RegistrationStatus.registered,
      RegistrationStatus.failed when recentlyConfirmed =>
        RegistrationStatus.registered,
      RegistrationStatus.disconnected when recentlyConfirmed =>
        RegistrationStatus.registered,
      _ => update.status,
    };

    unawaited(RemoteDiagnosticsService.instance.record(
      'sip_registration',
      details: <String, Object?>{
        'account': account.username,
        'domain': account.domain,
        'transport': account.transport.name,
        'status': resolvedStatus.name,
        'reason': update.reason ?? '',
      },
    ));

    if (resolvedStatus == RegistrationStatus.registered) {
      _registrationConfirmedAt[update.accountId] = now;
      // ABTO SDK tek aktif SIP hesabı destekler. Native hesap değiştiğinde
      // önceki hesapları kayıtlı göstermemeliyiz; aksi halde UI gerçekte
      // aktif olmayan hesaptan arama başlatmaya çalışır.
      _replaceAccounts(
        _accounts.map(
          (candidate) => candidate.id == update.accountId
              ? candidate
              : candidate.copyWith(
                  registrationStatus: RegistrationStatus.disconnected,
                ),
        ),
      );
    } else if (resolvedStatus == RegistrationStatus.failed ||
        resolvedStatus == RegistrationStatus.disconnected) {
      _registrationConfirmedAt.remove(update.accountId);
    }

    _replaceAccount(account.copyWith(registrationStatus: resolvedStatus));
    if (resolvedStatus == RegistrationStatus.failed &&
        update.reason != null &&
        update.reason!.trim().isNotEmpty) {
      _registrationReasons[update.accountId] = update.reason!.trim();
    } else if (resolvedStatus == RegistrationStatus.registered ||
        resolvedStatus == RegistrationStatus.connecting) {
      _registrationReasons.remove(update.accountId);
    }
    _statusLine = switch (resolvedStatus) {
      RegistrationStatus.registered => '${account.displayName} kayitli.',
      RegistrationStatus.connecting => '${account.displayName} baglaniyor...',
      RegistrationStatus.failed =>
        '${account.displayName} kaydi basarisiz: ${update.reason ?? 'neden yok'}',
      RegistrationStatus.disconnected => '${account.displayName} ayrildi.',
    };

    final eventStatus = switch (resolvedStatus) {
      RegistrationStatus.registered => RegisterEventStatus.success,
      RegistrationStatus.connecting => RegisterEventStatus.started,
      RegistrationStatus.failed => RegisterEventStatus.failed,
      RegistrationStatus.disconnected => RegisterEventStatus.unregistered,
    };
    unawaited(
      _postRegisterEvent(
        account,
        status: eventStatus,
        reason: update.reason,
      ),
    );

    unawaited(_syncPlatformRegistration());
    notifyListeners();
  }

  @override
  void onCallUpdate(SoftphoneCallUpdate update) {
    final diagnosticAccount = _findAccount(update.accountId);
    unawaited(RemoteDiagnosticsService.instance.record(
      'sip_call',
      details: <String, Object?>{
        'callId': update.callId,
        'account': diagnosticAccount?.username ?? update.accountId,
        'domain': diagnosticAccount?.domain ?? '',
        'remote': update.remoteIdentity,
        'direction': update.direction.name,
        'event': update.type.name,
        'muted': update.isMuted,
        'held': update.isOnHold,
        'reason': update.reason ?? '',
      },
    ));
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

    final connectedAt = DateTime.now();
    _activeCall = call.copyWith(
      phase: CallPhase.connected,
      connectedAt: connectedAt,
    );
    _updateCallLog(
      call.id,
      disposition: CallDisposition.answered,
      connectedAt: connectedAt,
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
    await _consumePendingIncomingCallIfAny();
  }

  /// Native taraf (MainActivity) bir incoming call intent ile uyandırdıysa,
  /// Flutter cold-start sırasında onIncomingCall event'i kaybolmuş olabilir.
  /// SharedPreferences'a yazılan pending call'u okuyup ActiveCall'u sentezler.
  Future<void> _consumePendingIncomingCallIfAny() async {
    try {
      final pending = await SipPushTokenService().consumePendingIncomingCall();
      if (pending == null) return;
      final remote = pending['remoteContact']?.toString() ?? '';
      final isVideo = pending['isVideo'] == true;
      if (_sipService case final AbtoSoftphoneService abtoService) {
        abtoService.injectIncomingCallFromIntent(remote, isVideo);
      }
    } catch (error) {
      debugPrint('consumePendingIncomingCall failed: $error');
    }
  }

  static bool _accountsDifferByMigration(
    List<SipAccount> before,
    List<SipAccount> after,
  ) {
    if (before.length != after.length) {
      return true;
    }

    for (var index = 0; index < before.length; index++) {
      final previous = before[index];
      final next = after[index];
      if (previous.id != next.id) {
        return true;
      }
      if (previous.domain != next.domain ||
          previous.stunServer != next.stunServer ||
          previous.websocketUrl != next.websocketUrl ||
          previous.outboundProxy != next.outboundProxy ||
          previous.transport != next.transport) {
        return true;
      }
    }

    return false;
  }

  static SipAccount _migrateRuntimeAccount(SipAccount account) {
    var migrated = account;

    final stun = account.stunServer.trim().toLowerCase();
    final usesBlockedMobileStun = stun.contains('google.com') ||
        stun.endsWith(':3478') ||
        stun.endsWith(':19302');

    if (usesBlockedMobileStun) {
      debugPrint(
        'Softphone account migration: clearing blocked STUN for ${account.aor}',
      );
      migrated = migrated.copyWith(stunServer: '');
    }

    final normalizedDomain = AppEnvironment.normalizeHost(account.domain);
    if (normalizedDomain != account.domain.trim()) {
      debugPrint(
        'Softphone account migration: domain ${account.domain} -> $normalizedDomain',
      );
      migrated = migrated.copyWith(domain: normalizedDomain);
    }

    final signalingHost = migrated.websocketUrl.split(':').first.trim();
    if (migrated.websocketUrl.trim().isNotEmpty &&
        AppEnvironment.isLegacyHost(signalingHost)) {
      migrated = migrated.copyWith(websocketUrl: normalizedDomain);
    }

    final proxyHost = migrated.outboundProxy.split(':').first.trim();
    if (migrated.outboundProxy.trim().isNotEmpty &&
        AppEnvironment.isLegacyHost(proxyHost)) {
      migrated = migrated.copyWith(outboundProxy: '');
    }

    if ((migrated.transport == SipTransport.udp ||
            migrated.transport == SipTransport.tcp) &&
        migrated.outboundProxy.trim().isEmpty) {
      final host = migrated.domain.split(':').first.trim();
      if (host.isNotEmpty) {
        migrated = migrated.copyWith(outboundProxy: '$host:5060');
      }
    }

    // demo1.sesdata.com: mobil agda UDP 5060 bloklanirsa TCP dene (408 sonrasi fallback icin).
    // Not: registerTimeout (ms) ile SIP Expires (sn) karistirilmamali — bkz. abto_softphone_service.

    return migrated;
  }

  Future<void> _syncSipAccounts() {
    final selectedId = _selectedAccountId;
    final candidates = _accounts
        .where((account) => account.password.trim().isNotEmpty)
        .toList(growable: false);

    if (selectedId == null || candidates.length < 2) {
      return _syncSipAccountsWithPreCheck(candidates, source: 'sync_simple');
    }

    final selectedIndex = candidates.indexWhere(
      (account) => account.id == selectedId,
    );
    if (selectedIndex <= 0) {
      return _syncSipAccountsWithPreCheck(candidates, source: 'sync_direct');
    }

    final selected = candidates[selectedIndex];
    final ordered = <SipAccount>[
      selected,
      ...candidates.where((account) => account.id != selected.id),
    ];
    return _syncSipAccountsWithPreCheck(ordered, source: 'sync_ordered');
  }

  Future<void> _syncSipAccountsWithPreCheck(
    List<SipAccount> orderedCandidates, {
    required String source,
  }) async {
    if (orderedCandidates.isEmpty) {
      await _sipService.syncAccounts(const <SipAccount>[]);
      return;
    }

    final primary = orderedCandidates.first;
    final allowed = await _checkRegisterPrecondition(primary, source: source);
    if (!allowed) {
      await _sipService.syncAccounts(const <SipAccount>[]);
      return;
    }

    unawaited(
      _postRegisterEvent(
        primary,
        status: RegisterEventStatus.started,
        reason: source,
      ),
    );
    await _sipService.syncAccounts(orderedCandidates);
  }

  Future<bool> _checkRegisterPrecondition(
    SipAccount account, {
    required String source,
  }) async {
    final deviceId = await _deviceIdentityService.getOrCreateDeviceId();
    final pushToken = await SipPushTokenService().getFcmToken();
    final extension = account.authorizationUser.trim().isNotEmpty
        ? account.authorizationUser.trim()
        : account.username.trim();
    final tenantId =
        account.domain.trim().isNotEmpty ? account.domain.trim() : 'default';

    final baseRequestId =
        '${account.id}-$source-${DateTime.now().microsecondsSinceEpoch}';

    await _upsertDeviceClaimRegistration(
      tenantId: tenantId,
      extension: extension,
      deviceId: deviceId,
      pushToken: pushToken,
      requestId: '$baseRequestId-upsert',
    );
    await _registerPushDevice(
      account: account,
      deviceId: deviceId,
      pushToken: pushToken,
    );

    if (!_claimEnforced) {
      _registrationReasons.remove(account.id);
      return true;
    }

    try {
      final response = await _registerClaimService.checkDeviceClaim(
        DeviceClaimCheckRequest(
          tenantId: tenantId,
          extension: extension,
          deviceId: deviceId,
          platform: _platformName,
          appVersion: _appVersion,
          requestId: '$baseRequestId-check',
          pushToken: pushToken,
        ),
      );

      if (response.isAllowed) {
        debugPrint(
          'Device claim allowed: account=${account.id} source=$source reasonCode=${response.reasonCode ?? '-'}',
        );
        _registrationReasons.remove(account.id);
        return true;
      }

      final rejectionReason = _buildClaimRejectedMessage(response);
      debugPrint(
        'Device claim rejected: account=${account.id} source=$source reasonCode=${response.reasonCode ?? '-'}',
      );

      _registrationReasons[account.id] = rejectionReason;
      _replaceAccount(
        account.copyWith(registrationStatus: RegistrationStatus.failed),
      );
      _statusLine = rejectionReason;
      notifyListeners();
      return false;
    } on SoftphoneRegisterClaimServiceException catch (error, stackTrace) {
      final failOpen = _shouldFailOpenForClaimError(error);
      debugPrint(
        'Device claim pre-check service error: status=${error.statusCode} failOpen=$failOpen error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (failOpen) {
        return true;
      }

      final reason =
          'Kimlik dogrulama servisine erisilemedigi icin baglanti guvenlik nedeniyle durduruldu.';
      _registrationReasons[account.id] = reason;
      _replaceAccount(
        account.copyWith(registrationStatus: RegistrationStatus.failed),
      );
      _statusLine = reason;
      notifyListeners();
      return false;
    } catch (error, stackTrace) {
      debugPrint('Device claim pre-check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return true;
    }
  }

  Future<void> _upsertDeviceClaimRegistration({
    required String tenantId,
    required String extension,
    required String deviceId,
    required String? pushToken,
    required String requestId,
  }) async {
    try {
      await _registerClaimService.upsertDevice(
        DeviceUpsertRequest(
          tenantId: tenantId,
          extension: extension,
          deviceId: deviceId,
          platform: _platformName,
          appVersion: _appVersion,
          requestId: requestId,
          pushToken: pushToken,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Device claim upsert failed (fail-open): $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _registerPushDevice({
    required SipAccount account,
    required String deviceId,
    required String? pushToken,
  }) async {
    final token = pushToken?.trim() ?? '';
    if (token.isEmpty) {
      unawaited(RemoteDiagnosticsService.instance.record(
        'push_registration',
        details: const {'result': 'skipped_no_registration_id'},
      ));
      return;
    }
    final client = InteliexMobileApiClient();
    try {
      final result = await client.registerPushDevice(
        account: account,
        fcmToken: token,
        deviceId: deviceId,
        platform: _platformName,
        appVersion: _appVersion,
      );
      unawaited(RemoteDiagnosticsService.instance.record(
        'push_registration',
        details: {
          'result': 'success',
          'account': account.username,
          'loginStatus': result.loginStatusCode,
          'deviceStatus': result.deviceStatusCode,
        },
      ));
    } on InteliexMobileApiException catch (error) {
      debugPrint('Push device registration failed: ${error.message}');
      unawaited(RemoteDiagnosticsService.instance.record(
        'push_registration',
        details: {
          'result': 'failed',
          'account': account.username,
          'status': error.statusCode ?? 0,
          'stage': error.message.contains('oturum') ? 'login' : 'device',
        },
      ));
    } catch (error, stackTrace) {
      debugPrint('Push device registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      unawaited(RemoteDiagnosticsService.instance.record(
        'push_registration',
        details: {
          'result': 'failed',
          'account': account.username,
          'status': 0,
          'stage': 'network',
        },
      ));
    } finally {
      await client.close();
    }
  }

  bool _shouldFailOpenForClaimError(
    SoftphoneRegisterClaimServiceException error,
  ) {
    final status = error.statusCode;
    if (status == null) {
      return _claimFailOpenOnNetworkError;
    }

    return _claimFailOpenStatusCodes.contains(status);
  }

  Future<void> _postRegisterEvent(
    SipAccount account, {
    required RegisterEventStatus status,
    String? reason,
  }) async {
    try {
      final deviceId = await _deviceIdentityService.getOrCreateDeviceId();
      final extension = account.authorizationUser.trim().isNotEmpty
          ? account.authorizationUser.trim()
          : account.username.trim();
      final tenantId =
          account.domain.trim().isNotEmpty ? account.domain.trim() : 'default';
      final sipCode = extractSipCode(reason);

      await _registerClaimService.postRegisterEvent(
        RegisterEventRequest(
          tenantId: tenantId,
          extension: extension,
          deviceId: deviceId,
          status: status,
          requestId:
              '${account.id}-${status.name}-${DateTime.now().microsecondsSinceEpoch}',
          occurredAt: DateTime.now(),
          sipCode: sipCode,
          reason: reason,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Register event post failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static int? extractSipCode(String? reason) {
    if (reason == null || reason.trim().isEmpty) {
      return null;
    }

    final match = RegExp(r'SIP\s+(\d{3})(?!\d)').firstMatch(reason);
    if (match == null) {
      return null;
    }

    return int.tryParse(match.group(1) ?? '');
  }

  String _buildClaimRejectedMessage(DeviceClaimCheckResponse response) {
    final backendMessage = response.message?.trim();
    if (backendMessage != null && backendMessage.isNotEmpty) {
      return backendMessage;
    }

    return switch (response.reasonCode?.trim().toUpperCase()) {
      'ALREADY_CLAIMED' =>
        'Bu dahili baska bir cihazda aktif. Yonetici cihaz kaydini silmeden baglanamazsiniz.',
      'DISABLED' => 'Bu dahili kullanima kapali gorunuyor.',
      'DEVICE_BLOCKED' => 'Bu cihaz engellendigi icin baglanti reddedildi.',
      _ => 'Bu dahili baska bir cihazda aktif gorunuyor.',
    };
  }

  static const String _appVersion = String.fromEnvironment(
    'INTELIEX_APP_VERSION',
    defaultValue: 'dev',
  );
  static const bool _claimEnforced = bool.fromEnvironment(
    'INTELIEX_CLAIM_ENFORCED',
    defaultValue: false,
  );
  static const String _claimFailOpenStatusCodesRaw = String.fromEnvironment(
    'INTELIEX_CLAIM_FAIL_OPEN_STATUS_CODES',
    defaultValue: '429,500,502,503',
  );
  static const bool _claimFailOpenOnNetworkError = bool.fromEnvironment(
    'INTELIEX_CLAIM_FAIL_OPEN_ON_NETWORK_ERROR',
    defaultValue: true,
  );

  static final Set<int> _claimFailOpenStatusCodes =
      _parseStatusCodes(_claimFailOpenStatusCodesRaw);

  static Set<int> _parseStatusCodes(String raw) {
    return raw
        .split(',')
        .map((item) => int.tryParse(item.trim()))
        .whereType<int>()
        .toSet();
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.fuchsia => 'fuchsia',
      TargetPlatform.linux => 'linux',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
    };
  }

  Future<void> _persistAccounts() {
    final accountsSnapshot = List<SipAccount>.of(_accounts);
    final selectedSnapshot = _selectedAccountId;
    return _persistence.saveAccounts(
      accounts: accountsSnapshot,
      selectedAccountId: selectedSnapshot,
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
      _statusLine =
          '$number icin cagri baslatilamadi. Birkaç saniye bekleyip tekrar deneyin '
          'veya Ayarlar > Yeniden kayitlan.';
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
    var call = _activeCall;
    // Cevapla bildirimden basıldığında incomingRinging event'i Flutter
    // engine paused olduğu için kaybolmuş olabilir. _activeCall null veya
    // farklı callId ise, şimdi sentezle ki UI çağrıyı görsün.
    if (call == null || call.id != update.callId) {
      call = ActiveCall(
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
      _activeCall = call;
    }

    _activeCall = call.copyWith(
      phase: CallPhase.connected,
      connectedAt: update.occurredAt,
      isMuted: update.isMuted,
      isOnHold: update.isOnHold,
    );
    // Cevapla'dan gelindiğinde kullanıcı dialer'ı görmeli.
    _currentTabIndex = 0;
    _updateCallLog(
      update.callId,
      disposition: CallDisposition.answered,
      connectedAt: update.occurredAt,
    );
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
    final wasOutgoingBeforeConnect = call != null &&
        call.id == update.callId &&
        call.phase == CallPhase.outgoingRinging;
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
          : wasOutgoingBeforeConnect
              ? '${update.remoteIdentity} cagriya yanit vermedi veya cagri iptal edildi.'
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
    // `accounts` çoğu çağrıda `_accounts.map(...)` ile oluşturulan lazy bir
    // Iterable'dır. Kaynak listeyi önce clear edersek iterable da boşalır ve
    // tüm hesaplar yanlışlıkla silinir. Her zaman temizlemeden önce snapshot al.
    final snapshot = accounts.toList(growable: false);
    _accounts
      ..clear()
      ..addAll(snapshot);
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
    DateTime? connectedAt,
    DateTime? endedAt,
  }) {
    final index = _callLogs.indexWhere((entry) => entry.sessionId == sessionId);
    if (index == -1) {
      return;
    }

    _callLogs[index] = _callLogs[index].copyWith(
      disposition: disposition,
      connectedAt: connectedAt,
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
    final configuredDomain = AppEnvironment.sipDomain.trim();
    final seeds = <SipAccount>[];

    void addConfiguredSeed({
      required String username,
      required String password,
      required bool isPrimary,
    }) {
      final trimmedUsername = username.trim();
      final trimmedPassword = password;
      if (trimmedUsername.isEmpty ||
          trimmedPassword.isEmpty ||
          configuredDomain.isEmpty) {
        return;
      }

      final signaling = configuredDomain.contains(':')
          ? configuredDomain
          : '$configuredDomain:5060';

      seeds.add(
        SipAccount(
          id: 'account-seed-$trimmedUsername',
          displayName: trimmedUsername,
          username: trimmedUsername,
          authorizationUser: '',
          password: trimmedPassword,
          domain: configuredDomain,
          websocketUrl: signaling,
          outboundProxy: signaling,
          registrationStatus: RegistrationStatus.disconnected,
          transport: SipTransport.udp,
          registrationExpireSeconds: 300,
          isPrimary: isPrimary,
        ),
      );
    }

    addConfiguredSeed(
      username: AppEnvironment.sipSeedUsername,
      password: AppEnvironment.sipSeedPassword,
      isPrimary: true,
    );
    addConfiguredSeed(
      username: AppEnvironment.sipSeedUsername2,
      password: AppEnvironment.sipSeedPassword2,
      isPrimary: seeds.isEmpty,
    );

    if (seeds.isNotEmpty) {
      debugPrint(
        'Softphone configured seeds: ${seeds.map((a) => a.username).join(', ')} '
        'domain=$configuredDomain',
      );
      return seeds;
    }

    // Release musteri APK: hesap gomme yok; kullanici Hesaplar'dan ekler.
    if (!kDebugMode) {
      return const <SipAccount>[];
    }

    const channel = MethodChannel('inteliex_softphone/foreground');
    String manufacturer = '';
    try {
      manufacturer =
          (await channel.invokeMethod<String>('getDeviceManufacturer')) ?? '';
    } catch (_) {}

    final isOnePlus = manufacturer.toLowerCase().contains('oneplus');
    final username = isOnePlus ? '2000' : '2001';
    final password = '3673';
    // Parametrik: sabit santral IP'si YOK. Domain, derleme-zamani
    // INTELIEX_SIP_DOMAIN define'indan gelir (her santral kendi hostname/IP'sini
    // verir). Boylece debug seed de tek bir kuruluma cakili kalmaz.
    final domain = AppEnvironment.sipDomain;
    final signaling = '$domain:5060';

    debugPrint(
      'Softphone custom seed: manufacturer=$manufacturer username=$username domain=$domain',
    );

    return <SipAccount>[
      SipAccount(
        id: 'account-seed-$username',
        displayName: 'Dahili $username',
        username: username,
        authorizationUser: username,
        password: password,
        domain: domain,
        websocketUrl: signaling,
        outboundProxy: signaling,
        registrationStatus: RegistrationStatus.disconnected,
        transport: SipTransport.udp,
        registrationExpireSeconds: 300,
        isPrimary: true,
      ),
    ];
  }

  static List<ContactEntry> _buildSeedContacts() {
    if (!kDebugMode && !AppEnvironment.hasConfiguredSipSeed) {
      return const <ContactEntry>[];
    }

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
    if (!kDebugMode && !AppEnvironment.hasConfiguredSipSeed) {
      return const <CallLogEntry>[];
    }

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
