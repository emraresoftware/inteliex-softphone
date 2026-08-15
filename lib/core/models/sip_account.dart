enum RegistrationStatus {
  disconnected,
  connecting,
  registered,
  failed,
}

enum SipTransport {
  udp,
  ws,
  wss,
  tcp,
}

RegistrationStatus registrationStatusFromName(String? value) {
  return RegistrationStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => RegistrationStatus.disconnected,
  );
}

SipTransport sipTransportFromName(String? value) {
  return SipTransport.values.firstWhere(
    (transport) => transport.name == value,
    orElse: () => SipTransport.wss,
  );
}

String _readLegacyString(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return '';
}

class SipAccount {
  const SipAccount({
    required this.id,
    required this.displayName,
    required this.username,
    required this.authorizationUser,
    required this.password,
    required this.domain,
    required this.websocketUrl,
    required this.registrationStatus,
    this.transport = SipTransport.wss,
    this.allowBadCertificate = false,
    this.isPrimary = false,
    this.outboundProxy = '',
    this.stunServer = '',
    this.registrationExpireSeconds = defaultRegistrationExpireSeconds,
  });

  static const int defaultRegistrationExpireSeconds = 300;
  static const int minRegistrationExpireSeconds = 30;
  static const int maxRegistrationExpireSeconds = 3600;

  final String id;
  final String displayName;
  final String username;
  final String authorizationUser;
  final String password;
  final String domain;
  final String websocketUrl;
  final RegistrationStatus registrationStatus;
  final SipTransport transport;
  final bool allowBadCertificate;
  final bool isPrimary;

  /// İstemcinin tüm SIP isteklerini öncelikle yollayacağı outbound proxy.
  /// Boş bırakılırsa sinyalleşme adresi/domain kullanılır.
  final String outboundProxy;

  /// Opsiyonel STUN sunucusu (örn. `stun:stun.l.google.com:19302`).
  final String stunServer;

  /// REGISTER yenileme aralığı (saniye).
  final int registrationExpireSeconds;

  String get aor => '$username@$domain';
  String get sipUri => 'sip:$username@$domain';

  Map<String, Object?> toStorageJson() {
    return {
      'id': id,
      'displayName': displayName,
      'username': username,
      'authorizationUser': authorizationUser,
      'domain': domain,
      'websocketUrl': websocketUrl,
      'signalingAddress': websocketUrl,
      'transport': transport.name,
      'allowBadCertificate': allowBadCertificate,
      'isPrimary': isPrimary,
      'outboundProxy': outboundProxy,
      'stunServer': stunServer,
      'registrationExpireSeconds': registrationExpireSeconds,
    };
  }

  factory SipAccount.fromStorageJson(
    Map<String, dynamic> json, {
    required String password,
  }) {
    final username = _readLegacyString(
      json,
      const ['username', 'userName', 'sipUser'],
    );
    final authorizationUser = _readLegacyString(
      json,
      const [
        'authorizationUser',
        'authUser',
        'authUsername',
        'sipAuthId',
      ],
    );
    final signalingAddress = _readLegacyString(
      json,
      const [
        'websocketUrl',
        'signalingAddress',
        'signalAddress',
        'sipServer',
        'sipProxy',
        'proxy',
      ],
    );
    final outboundProxy = _readLegacyString(
      json,
      const ['outboundProxy', 'outbound_proxy', 'outboundProxyUrl'],
    );
    final stunServer = _readLegacyString(
      json,
      const ['stunServer', 'stun_server', 'stun'],
    );
    final rawExpire = json['registrationExpireSeconds'] ??
        json['registration_expire_seconds'] ??
        json['expireSeconds'] ??
        json['expire'];
    final expireSeconds = _parsePositiveInt(rawExpire) ??
        defaultRegistrationExpireSeconds;

    return SipAccount(
      id: json['id']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      username: username,
      authorizationUser: authorizationUser.isEmpty ? username : authorizationUser,
      password: password,
      domain: _readLegacyString(json, const ['domain', 'realm']),
      websocketUrl: signalingAddress,
      registrationStatus: registrationStatusFromName(
        json['registrationStatus']?.toString(),
      ),
      transport: sipTransportFromName(json['transport']?.toString()),
      allowBadCertificate: json['allowBadCertificate'] == true,
      isPrimary: json['isPrimary'] == true,
      outboundProxy: outboundProxy,
      stunServer: stunServer,
      registrationExpireSeconds: _clampExpireSeconds(expireSeconds),
    );
  }

  SipAccount copyWith({
    String? id,
    String? displayName,
    String? username,
    String? authorizationUser,
    String? password,
    String? domain,
    String? websocketUrl,
    RegistrationStatus? registrationStatus,
    SipTransport? transport,
    bool? allowBadCertificate,
    bool? isPrimary,
    String? outboundProxy,
    String? stunServer,
    int? registrationExpireSeconds,
  }) {
    return SipAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      authorizationUser: authorizationUser ?? this.authorizationUser,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      websocketUrl: websocketUrl ?? this.websocketUrl,
      registrationStatus: registrationStatus ?? this.registrationStatus,
      transport: transport ?? this.transport,
      allowBadCertificate: allowBadCertificate ?? this.allowBadCertificate,
      isPrimary: isPrimary ?? this.isPrimary,
      outboundProxy: outboundProxy ?? this.outboundProxy,
      stunServer: stunServer ?? this.stunServer,
      registrationExpireSeconds:
          registrationExpireSeconds ?? this.registrationExpireSeconds,
    );
  }
}

int? _parsePositiveInt(Object? value) {
  if (value is int) {
    return value > 0 ? value : null;
  }
  if (value is num) {
    final intValue = value.toInt();
    return intValue > 0 ? intValue : null;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    return (parsed != null && parsed > 0) ? parsed : null;
  }
  return null;
}

int _clampExpireSeconds(int value) {
  if (value < SipAccount.minRegistrationExpireSeconds) {
    return SipAccount.minRegistrationExpireSeconds;
  }
  if (value > SipAccount.maxRegistrationExpireSeconds) {
    return SipAccount.maxRegistrationExpireSeconds;
  }
  return value;
}

