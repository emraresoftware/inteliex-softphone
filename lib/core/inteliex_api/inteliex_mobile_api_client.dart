import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/contact_entry.dart';
import '../models/sip_account.dart';
import 'inteliex_mobile_api_models.dart';

class InteliexMobileApiDirectoryData {
  const InteliexMobileApiDirectoryData({
    this.extensionContacts = const <ContactEntry>[],
    this.sharedContacts = const <ContactEntry>[],
    this.personalContacts = const <ContactEntry>[],
  });

  final List<ContactEntry> extensionContacts;
  final List<ContactEntry> sharedContacts;
  final List<ContactEntry> personalContacts;

  List<ContactEntry> get allContacts {
    return List<ContactEntry>.unmodifiable([
      ...extensionContacts,
      ...sharedContacts,
      ...personalContacts,
    ]);
  }

  bool get isEmpty =>
      extensionContacts.isEmpty &&
      sharedContacts.isEmpty &&
      personalContacts.isEmpty;
}

class InteliexMobileApiException implements Exception {
  const InteliexMobileApiException(this.message,
      {this.failure, this.statusCode});

  final String message;
  final InteliexMobileApiFailure? failure;
  final int? statusCode;

  @override
  String toString() {
    return 'InteliexMobileApiException(message: $message, failure: $failure, statusCode: $statusCode)';
  }
}

class InteliexDeviceRegistrationResult {
  const InteliexDeviceRegistrationResult({
    required this.loginStatusCode,
    required this.deviceStatusCode,
  });

  final int loginStatusCode;
  final int deviceStatusCode;
}

class InteliexMobileApiClient {
  InteliexMobileApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  final http.Client _httpClient;
  final bool _ownsClient;

  Future<InteliexDeviceRegistrationResult> registerPushDevice({
    required SipAccount account,
    required String fcmToken,
    required String deviceId,
    required String platform,
    required String appVersion,
  }) async {
    final token = fcmToken.trim();
    if (token.isEmpty) {
      throw const InteliexMobileApiException('FCM cihaz anahtari bos.');
    }
    final endpoint = inteliexApiV2EndpointFromAccount(account);
    if (endpoint == null) {
      throw const InteliexMobileApiException(
        'Inteliex API v2 endpoint bilgisi olusturulamadi.',
      );
    }
    final user = account.authorizationUser.trim().isNotEmpty
        ? account.authorizationUser.trim()
        : account.username.trim();
    final loginResponse = await _httpClient.post(
      endpoint.replace(queryParameters: const {'_path': 'auth/login'}),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'user': user, 'password': account.password}),
    );
    if (loginResponse.statusCode < 200 || loginResponse.statusCode >= 300) {
      throw InteliexMobileApiException(
        'Inteliex API v2 oturum acma hatasi.',
        statusCode: loginResponse.statusCode,
      );
    }
    final loginJson = _decodeBody(loginResponse.bodyBytes);
    final data = loginJson['data'];
    final attributes = data is Map ? data['attributes'] : null;
    final accessToken = attributes is Map
        ? (attributes['access_token']?.toString() ?? '').trim()
        : '';
    if (accessToken.isEmpty) {
      throw InteliexMobileApiException(
        'Inteliex API v2 oturum yanitinda erisim anahtari yok.',
        statusCode: loginResponse.statusCode,
      );
    }

    final deviceResponse = await _httpClient.post(
      endpoint.replace(queryParameters: const {'_path': 'devices'}),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'data': {
          'type': 'devices',
          'attributes': {
            'fcm_token': token,
            'platform': platform,
            'app_version': appVersion,
            'device_id': deviceId,
          },
        },
      }),
    );
    if (deviceResponse.statusCode < 200 || deviceResponse.statusCode >= 300) {
      throw InteliexMobileApiException(
        'Inteliex API v2 cihaz kaydi hatasi.',
        statusCode: deviceResponse.statusCode,
      );
    }
    return InteliexDeviceRegistrationResult(
      loginStatusCode: loginResponse.statusCode,
      deviceStatusCode: deviceResponse.statusCode,
    );
  }

  Future<InteliexMobileApiDirectoryData> fetchDirectoryForAccount(
    SipAccount account, {
    String? fcmToken,
  }) async {
    final endpoint = inteliexMobileApiEndpointFromAccount(account);
    if (endpoint == null) {
      throw const InteliexMobileApiException(
        'Inteliex API endpoint bilgisi hesap verisinden olusturulamadi.',
      );
    }

    final auth = InteliexMobileApiAuth(
      user: account.username.trim().isEmpty
          ? account.authorizationUser
          : account.username,
      password: account.password,
      fcmToken: fcmToken,
    );

    return fetchDirectory(endpoint: endpoint, auth: auth);
  }

  Future<InteliexMobileApiDirectoryData> fetchDirectory({
    required Uri endpoint,
    required InteliexMobileApiAuth auth,
    int recordPerPage = inteliexMobileApiDefaultRecordPerPage,
  }) async {
    final results = await Future.wait([
      _fetchPaginated(
        endpoint: endpoint,
        auth: auth,
        recordPerPage: recordPerPage,
        requestBuilder: ({required offset, required recordPerPage}) {
          return InteliexExtListRequest(
            offset: offset,
            recordPerPage: recordPerPage,
          );
        },
        parser: InteliexExtListResponse.fromJson,
      ),
      _fetchPaginated(
        endpoint: endpoint,
        auth: auth,
        recordPerPage: recordPerPage,
        requestBuilder: ({required offset, required recordPerPage}) {
          return InteliexPhoneBookRequest(
            offset: offset,
            recordPerPage: recordPerPage,
          );
        },
        parser: InteliexPhoneBookResponse.fromJson,
      ),
      _fetchPaginated(
        endpoint: endpoint,
        auth: auth,
        recordPerPage: recordPerPage,
        requestBuilder: ({required offset, required recordPerPage}) {
          return InteliexPersonalPhoneBookRequest(
            offset: offset,
            recordPerPage: recordPerPage,
          );
        },
        parser: InteliexPersonalPhoneBookResponse.fromJson,
      ),
    ]);

    final extensionResults = results[0].cast<InteliexExtensionEntry>();
    final sharedResults = results[1].cast<InteliexPhoneBookEntry>();
    final personalResults = results[2].cast<InteliexPhoneBookEntry>();

    return InteliexMobileApiDirectoryData(
      extensionContacts: List<ContactEntry>.unmodifiable(
        extensionResults.map(_mapExtensionContact),
      ),
      sharedContacts: List<ContactEntry>.unmodifiable(
        sharedResults
            .map((entry) =>
                _mapPhoneBookContact(entry, sourceLabel: 'Genel Rehber'))
            .whereType<ContactEntry>(),
      ),
      personalContacts: List<ContactEntry>.unmodifiable(
        personalResults
            .map((entry) =>
                _mapPhoneBookContact(entry, sourceLabel: 'Kisisel Rehber'))
            .whereType<ContactEntry>(),
      ),
    );
  }

  Future<void> close() async {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  Future<List<TItem>> _fetchPaginated<
      TResponse extends InteliexPaginatedResponse<TItem>, TItem>({
    required Uri endpoint,
    required InteliexMobileApiAuth auth,
    required int recordPerPage,
    required InteliexOffsetRequestData Function({
      required int offset,
      required int recordPerPage,
    }) requestBuilder,
    required TResponse Function(Map<String, dynamic> json) parser,
  }) async {
    final firstPage = await _post(
      endpoint: endpoint,
      body: InteliexMobileApiRequestEnvelope(
        auth: auth,
        request: requestBuilder(offset: 0, recordPerPage: recordPerPage),
      ),
      parser: parser,
    );

    final mergedResults = <TItem>[...firstPage.results];
    final totalPages = firstPage.pageCount <= 0 ? 1 : firstPage.pageCount;

    for (var pageIndex = 1; pageIndex < totalPages; pageIndex++) {
      final nextPage = await _post(
        endpoint: endpoint,
        body: InteliexMobileApiRequestEnvelope(
          auth: auth,
          request: requestBuilder(
            offset: pageIndex * recordPerPage,
            recordPerPage: recordPerPage,
          ),
        ),
        parser: parser,
      );
      mergedResults.addAll(nextPage.results);
    }

    return List<TItem>.unmodifiable(mergedResults);
  }

  Future<TResponse> _post<TResponse extends InteliexMobileApiResponseEnvelope>({
    required Uri endpoint,
    required InteliexMobileApiRequestEnvelope<InteliexMobileApiRequestData>
        body,
    required TResponse Function(Map<String, dynamic> json) parser,
  }) async {
    final response = await _httpClient.post(
      endpoint,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body.toJson()),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InteliexMobileApiException(
        'Inteliex API HTTP hatasi.',
        statusCode: response.statusCode,
      );
    }

    final decoded = _decodeBody(response.bodyBytes);
    final parsedResponse = parser(decoded);
    final failure = parsedResponse.failure;
    if (failure != null) {
      throw InteliexMobileApiException(
        'Inteliex API islem hatasi: ${parsedResponse.status}',
        failure: failure,
        statusCode: response.statusCode,
      );
    }

    if (!parsedResponse.isSuccess) {
      throw InteliexMobileApiException(
        'Inteliex API beklenmeyen durum: ${parsedResponse.status}',
        statusCode: response.statusCode,
      );
    }

    return parsedResponse;
  }

  Map<String, dynamic> _decodeBody(List<int> bodyBytes) {
    final rawBody = utf8.decode(bodyBytes, allowMalformed: true).trim();
    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map) {
      throw const InteliexMobileApiException(
        'Inteliex API JSON nesnesi donmedi.',
      );
    }

    return Map<String, dynamic>.from(decoded);
  }
}

Uri? inteliexMobileApiEndpointFromAccount(SipAccount account) {
  final websocketUrl = account.websocketUrl.trim();
  if (websocketUrl.isNotEmpty) {
    final parsedWebsocketUrl = Uri.tryParse(websocketUrl);
    if (parsedWebsocketUrl != null) {
      final directApiUri = _directApiUri(parsedWebsocketUrl);
      if (directApiUri != null) {
        return directApiUri;
      }

      if (parsedWebsocketUrl.host.trim().isNotEmpty) {
        final scheme = parsedWebsocketUrl.scheme == 'wss' ? 'https' : 'http';
        return _buildEndpoint(
          scheme: scheme,
          host: parsedWebsocketUrl.host,
        );
      }
    }
  }

  final domain = account.domain.trim();
  if (domain.isEmpty) {
    return null;
  }

  final parsedDomain = domain.contains('://')
      ? Uri.tryParse(domain)
      : Uri.tryParse(
          '${account.transport == SipTransport.wss ? 'https' : 'http'}://$domain',
        );
  if (parsedDomain == null) {
    return null;
  }

  final directApiUri = _directApiUri(parsedDomain);
  if (directApiUri != null) {
    return directApiUri;
  }

  final host = parsedDomain.host.trim().isEmpty
      ? parsedDomain.pathSegments.firstOrNull ?? ''
      : parsedDomain.host;
  if (host.trim().isEmpty) {
    return null;
  }

  return _buildEndpoint(
    scheme: parsedDomain.scheme == 'https' ? 'https' : 'http',
    host: host,
  );
}

Uri? inteliexApiV2EndpointFromAccount(SipAccount account) {
  final legacyEndpoint = inteliexMobileApiEndpointFromAccount(account);
  if (legacyEndpoint == null) return null;
  final host = legacyEndpoint.host;
  final isIpAddress = InternetAddress.tryParse(host) != null;
  return Uri(
    // Sesdata gibi SIP'i UDP/5060 ile sunan kurulumlar web API'yi HTTP'den
    // HTTPS'e 301 ile yonlendiriyor. POST govdesi bu yonlendirmede GET'e
    // donusebildigi icin alan adlarinda API v2'ye dogrudan HTTPS ile git.
    scheme: isIpAddress ? legacyEndpoint.scheme : 'https',
    host: host,
    path: '/api/v2/index.php',
  );
}

ContactEntry _mapExtensionContact(InteliexExtensionEntry entry) {
  final extensionNumber = entry.extension.trim();
  final displayName =
      entry.name.trim().isEmpty ? extensionNumber : entry.name.trim();

  return ContactEntry(
    id: 'ext-$extensionNumber',
    displayName: displayName,
    primaryNumber: extensionNumber,
    department: 'Dahili',
  );
}

ContactEntry? _mapPhoneBookContact(
  InteliexPhoneBookEntry entry, {
  required String sourceLabel,
}) {
  final primaryNumber = _pickPrimaryNumber(entry);
  if (primaryNumber.isEmpty) {
    return null;
  }

  final displayName = entry.nameCompany.trim().isNotEmpty
      ? entry.nameCompany.trim()
      : entry.registerName.trim().isNotEmpty
          ? entry.registerName.trim()
          : primaryNumber;
  final detail = entry.registerName.trim().isNotEmpty
      ? '${entry.registerName.trim()} • $sourceLabel'
      : sourceLabel;
  final recordId = entry.recordId.trim().isEmpty
      ? displayName.toLowerCase().replaceAll(' ', '-')
      : entry.recordId.trim();

  return ContactEntry(
    id: '${sourceLabel.toLowerCase().replaceAll(' ', '-')}-$recordId',
    displayName: displayName,
    primaryNumber: primaryNumber,
    department: detail,
  );
}

String _pickPrimaryNumber(InteliexPhoneBookEntry entry) {
  final candidates = [
    entry.phoneNumber,
    entry.mobilePhone,
    entry.phoneNumber2,
    entry.mobilePhone2,
    entry.phoneNumber3,
  ];

  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return '';
}

Uri? _directApiUri(Uri uri) {
  if (!uri.path.contains('inteliex-mobile-api.php')) {
    return null;
  }

  final queryParameters = Map<String, String>.from(uri.queryParameters);
  queryParameters.putIfAbsent(
      'request_type', () => inteliexMobileApiRequestType);

  return uri.replace(queryParameters: queryParameters);
}

Uri _buildEndpoint({required String scheme, required String host}) {
  return Uri(
    scheme: scheme,
    host: host,
    path: '/asteradmin/inteliex-mobile-api.php',
    queryParameters: const {'request_type': inteliexMobileApiRequestType},
  );
}
