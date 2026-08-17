import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// QR / deeplink ile "claim" (tek-kullanimlik) provisioning akisi.
///
/// Backend sozlesmesi:
///   Deeplink : inteliexphone://provision?v=1&mode=claim&domain=<FQDN>&ext=<ext>
///              &api=https://<FQDN>&claim=<32hex>&insecuretls=0
///   Claim GET: <api>/inteliexadmin/mobil_provision_claim.php?token=<claim>&device=<ad>
///   Basari   : 200 {"ok":true,"config":{...}}
///   Kullanilmis: 409 {"ok":false,"err":"invalid_or_claimed"}
///
/// SIP transport MOBILDE HER ZAMAN UDP'dir (ABTO SDK WebSocket desteklemez).

/// Claim endpoint'inden donen ve bir SIP hesabina donusturulecek yapilandirma.
class ClaimConfig {
  const ClaimConfig({
    required this.transport,
    required this.domain,
    required this.proxy,
    required this.sipPort,
    required this.ext,
    required this.user,
    required this.secret,
    required this.name,
    required this.api,
  });

  /// Backend her zaman "udp" gonderir; yine de alani sakliyoruz.
  final String transport;

  /// SIP realm / register domain (FQDN).
  final String domain;

  /// Outbound proxy "host:port" (ornek: pbx.example.com:5062). Bos olabilir.
  final String proxy;

  /// SIP UDP portu (varsayilan 5062).
  final int sipPort;

  /// Dahili numara (ext). Genelde user ile aynidir.
  final String ext;

  /// SIP REGISTER kullanici adi.
  final String user;

  /// SIP sifresi.
  final String secret;

  /// Gorunen ad (displayName). Bos ise ext kullanilir.
  final String name;

  /// FCM / push kayit ve rehber icin API taban adresi (https://<FQDN>).
  final String api;

  /// Bu yapilandirmadan SIP hesabi kurmak icin gereken minimum alanlar dolu mu?
  bool get isValid =>
      user.trim().isNotEmpty &&
      secret.trim().isNotEmpty &&
      domain.trim().isNotEmpty;

  /// Hesap sinyalizasyon adresi (UDP icin "host:port").
  /// proxy verilmisse onu, aksi halde domain:sipPort kullanir.
  String get signalingAddress {
    final trimmedProxy = proxy.trim();
    if (trimmedProxy.isNotEmpty) {
      return trimmedProxy;
    }
    final host = domain.trim();
    if (host.isEmpty) {
      return '';
    }
    return host.contains(':') ? host : '$host:$sipPort';
  }

  factory ClaimConfig.fromJson(Map<String, dynamic> json) {
    String readString(String key) => json[key]?.toString().trim() ?? '';

    int readPort() {
      final raw = json['sip_port'];
      if (raw is int) {
        return raw > 0 ? raw : 5062;
      }
      if (raw is num) {
        final v = raw.toInt();
        return v > 0 ? v : 5062;
      }
      final parsed = int.tryParse(raw?.toString().trim() ?? '');
      return (parsed != null && parsed > 0) ? parsed : 5062;
    }

    final transport = readString('transport');
    final ext = readString('ext');
    final user = readString('user').isNotEmpty ? readString('user') : ext;
    final name = readString('name');

    return ClaimConfig(
      transport: transport.isNotEmpty ? transport : 'udp',
      domain: readString('domain'),
      proxy: readString('proxy'),
      sipPort: readPort(),
      ext: ext,
      user: user,
      secret: readString('secret'),
      name: name.isNotEmpty ? name : (user.isNotEmpty ? user : ext),
      api: readString('api'),
    );
  }

  @override
  String toString() =>
      'ClaimConfig(user=$user, domain=$domain, proxy=$proxy, sipPort=$sipPort, '
      'transport=$transport, api=$api)';
}

/// QR/deeplink URI'sinden cikarilan claim istegi parametreleri.
class ProvisionRequest {
  const ProvisionRequest({
    required this.api,
    required this.claimToken,
    required this.domain,
    required this.ext,
    required this.insecureTls,
  });

  /// API taban adresi (ornek: https://pbx.example.com).
  final String api;

  /// 32 haneli tek-kullanimlik claim token.
  final String claimToken;

  /// Beklenen FQDN (dogrulama/gosterim icin).
  final String domain;

  /// Beklenen dahili (dogrulama/gosterim icin).
  final String ext;

  /// insecuretls=1 ise self-signed TLS'e izin verilir (varsayilan false).
  final bool insecureTls;

  @override
  String toString() =>
      'ProvisionRequest(api=$api, ext=$ext, domain=$domain, '
      'claimToken=${_maskToken(claimToken)}, insecureTls=$insecureTls)';
}

String _maskToken(String token) {
  if (token.length <= 6) {
    return '******';
  }
  return '${token.substring(0, 3)}...${token.substring(token.length - 3)}';
}

/// Provisioning akisinda kullaniciya gosterilebilecek hatalar.
class ClaimProvisioningException implements Exception {
  const ClaimProvisioningException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => statusCode == null
      ? 'ClaimProvisioningException: $message'
      : 'ClaimProvisioningException($statusCode): $message';
}

/// QR/deeplink URI'sini ayristirir.
///
/// Desteklenen bicimler:
///   1) inteliexphone://provision?v=1&mode=claim&domain=..&ext=..&api=..&claim=..&insecuretls=0
///   2) https://<host>/...?mode=claim&api=..&claim=.. (QR olarak URL basildiysa)
///
/// mode=claim degilse veya zorunlu alanlar eksikse [ClaimProvisioningException] atar.
ProvisionRequest parseProvisionUri(Uri uri) {
  final params = uri.queryParameters;

  final mode = (params['mode'] ?? '').trim().toLowerCase();
  if (mode != 'claim') {
    // custom scheme + provision host ise mode kesinlikle claim beklenir.
    final looksLikeProvision =
        uri.scheme == 'inteliexphone' || uri.host == 'provision';
    if (looksLikeProvision && mode.isEmpty) {
      throw const ClaimProvisioningException(
        'QR icerigi eksik: mode=claim parametresi yok.',
      );
    }
    throw ClaimProvisioningException(
      'Desteklenmeyen QR / baglanti bicimi (mode=${mode.isEmpty ? '-' : mode}).',
    );
  }

  final claim = (params['claim'] ?? params['token'] ?? '').trim();
  if (claim.isEmpty) {
    throw const ClaimProvisioningException(
      'QR icerigi gecersiz: claim token bulunamadi.',
    );
  }

  var api = (params['api'] ?? '').trim();
  final domain = (params['domain'] ?? '').trim();
  final ext = (params['ext'] ?? '').trim();

  // api verilmemisse domain'den turet (https varsayilir).
  if (api.isEmpty && domain.isNotEmpty) {
    api = 'https://$domain';
  }

  if (api.isEmpty) {
    throw const ClaimProvisioningException(
      'QR icerigi gecersiz: api / domain adresi bulunamadi.',
    );
  }

  // api mutlak URL degilse https ekle.
  if (!api.startsWith('http://') && !api.startsWith('https://')) {
    api = 'https://$api';
  }

  final insecureRaw = (params['insecuretls'] ?? '0').trim();
  final insecureTls = insecureRaw == '1' ||
      insecureRaw.toLowerCase() == 'true' ||
      insecureRaw.toLowerCase() == 'yes';

  return ProvisionRequest(
    api: api,
    claimToken: claim,
    domain: domain,
    ext: ext,
    insecureTls: insecureTls,
  );
}

/// Metin/URI stringinden [ProvisionRequest] cikarir (QR okuma sonucu icin).
/// Ayristirilamazsa [ClaimProvisioningException] atar.
ProvisionRequest parseProvisionString(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const ClaimProvisioningException('Bos QR icerigi.');
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    throw const ClaimProvisioningException('QR icerigi bir baglanti degil.');
  }

  return parseProvisionUri(uri);
}

/// Claim provisioning istemcisi.
class ClaimProvisioningService {
  ClaimProvisioningService({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
    this.claimPath = '/inteliexadmin/mobil_provision_claim.php',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final String claimPath;

  /// Claim endpoint'ini cagirir. Basari => [ClaimConfig].
  ///
  /// 409 / ok:false => "baska cihazda kullanilmis" anlamli hatasi.
  Future<ClaimConfig> claim(
    ProvisionRequest request, {
    required String deviceName,
  }) async {
    final base = Uri.parse(request.api);
    final device = deviceName.trim().isEmpty ? 'mobil' : deviceName.trim();

    // api tabanina claimPath'i ekle (api'de path olabilecegi icin resolve degil,
    // origin + path birlestiriyoruz).
    final uri = base.replace(
      path: claimPath,
      queryParameters: <String, String>{
        'token': request.claimToken,
        'device': device,
      },
    );

    debugPrint(
      'Claim provisioning GET: uri=${uri.replace(queryParameters: {'token': _maskToken(request.claimToken), 'device': device})}',
    );

    http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const <String, String>{'Accept': 'application/json'},
      ).timeout(timeout);
    } on TimeoutException {
      throw const ClaimProvisioningException(
        'Sunucuya zamaninda ulasilamadi. Ag baglantinizi kontrol edip tekrar deneyin.',
      );
    } catch (error) {
      throw ClaimProvisioningException(
        'Sunucuya baglanilamadi: $error',
      );
    }

    final status = response.statusCode;
    Map<String, dynamic> body;
    try {
      body = _decodeJson(response.body);
    } on FormatException {
      body = const <String, dynamic>{};
    }

    final ok = body['ok'] == true;

    if (status == 409 || (status == 200 && !ok)) {
      final err = body['err']?.toString().trim() ?? '';
      throw ClaimProvisioningException(
        _friendlyClaimError(err),
        statusCode: status,
      );
    }

    if (status == 404) {
      throw const ClaimProvisioningException(
        'Kurulum servisi bulunamadi. Sunucu adresini kontrol edin.',
        statusCode: 404,
      );
    }

    if (status < 200 || status >= 300) {
      throw ClaimProvisioningException(
        'Kurulum basarisiz oldu (sunucu kodu $status).',
        statusCode: status,
      );
    }

    if (!ok) {
      throw ClaimProvisioningException(
        _friendlyClaimError(body['err']?.toString().trim() ?? ''),
        statusCode: status,
      );
    }

    final rawConfig = body['config'];
    if (rawConfig is! Map) {
      throw const ClaimProvisioningException(
        'Sunucu yaniti gecersiz: yapilandirma verisi eksik.',
      );
    }

    final config = ClaimConfig.fromJson(
      rawConfig.map((key, value) => MapEntry(key.toString(), value)),
    );

    if (!config.isValid) {
      throw const ClaimProvisioningException(
        'Sunucudan gelen SIP bilgileri eksik (kullanici / sifre / domain).',
      );
    }

    // api alani config'te bos ise, istegin api'sini kullan.
    if (config.api.trim().isEmpty) {
      return ClaimConfig(
        transport: config.transport,
        domain: config.domain,
        proxy: config.proxy,
        sipPort: config.sipPort,
        ext: config.ext,
        user: config.user,
        secret: config.secret,
        name: config.name,
        api: request.api,
      );
    }

    return config;
  }

  String _friendlyClaimError(String err) {
    switch (err.toLowerCase()) {
      case 'invalid_or_claimed':
        return 'Bu QR kodu gecersiz veya baska bir cihazda zaten kullanilmis. '
            'Yeni bir QR olusturup tekrar deneyin.';
      case 'expired':
        return 'QR kodunun suresi dolmus. Yeni bir QR olusturun.';
      case 'not_found':
        return 'QR kodu bulunamadi. Yeni bir QR olusturun.';
      default:
        return err.isEmpty
            ? 'Kurulum reddedildi. Yeni bir QR olusturup tekrar deneyin.'
            : 'Kurulum reddedildi ($err).';
    }
  }

  Map<String, dynamic> _decodeJson(String payload) {
    if (payload.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  void close() {
    _client.close();
  }
}
