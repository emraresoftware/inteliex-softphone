import '../inteliex_api/inteliex_mobile_api_client.dart';
import '../inteliex_api/inteliex_mobile_api_models.dart';
import '../models/sip_account.dart';
import '../../services/sip/sip_push_token_service.dart';
import 'contact_directory_provider.dart';

/// Inteliex Mobile API'yi [ContactDirectoryProvider] arayüzünün arkasına alır.
///
/// Sadece API endpoint'i hesap verisinden türetilebilen hesaplar için
/// [supports] true döner; manuel/generic SIP hesapları otomatik olarak
/// dışarıda kalır.
class InteliexContactDirectoryProvider implements ContactDirectoryProvider {
  InteliexContactDirectoryProvider({
    InteliexMobileApiClient? client,
    SipPushTokenService? pushTokenService,
  })  : _client = client ?? InteliexMobileApiClient(),
        _pushTokenService = pushTokenService ?? SipPushTokenService();

  final InteliexMobileApiClient _client;
  final SipPushTokenService _pushTokenService;

  @override
  bool supports(SipAccount account) {
    if (account.password.trim().isEmpty) {
      return false;
    }
    return inteliexMobileApiEndpointFromAccount(account) != null;
  }

  @override
  Future<ContactDirectoryResult> fetchForAccount(SipAccount account) async {
    if (!supports(account)) {
      throw const ContactDirectoryException(
        'Hesap Inteliex Mobile API ile uyumlu değil.',
        failure: ContactDirectoryFailure.unsupported,
      );
    }

    try {
      final token = await _pushTokenService.getFcmToken();
      final directory = await _client.fetchDirectoryForAccount(
        account,
        fcmToken: token,
      );
      return ContactDirectoryResult(
        extensionContacts: directory.extensionContacts,
        sharedContacts: directory.sharedContacts,
        personalContacts: directory.personalContacts,
      );
    } on InteliexMobileApiException catch (error) {
      // Sahada teshis icin HTTP kodu mesaja eklenir (401 = panel oturum kapisi,
      // 403 = sunucu bu yolu disariya kapatmis, 301 = HTTP->HTTPS yonlendirmesi).
      throw ContactDirectoryException(
        error.statusCode == null
            ? error.message
            : '${error.message} (HTTP ${error.statusCode})',
        failure: _mapFailure(error.failure),
      );
    }
  }

  @override
  Future<void> close() => _client.close();

  ContactDirectoryFailure _mapFailure(InteliexMobileApiFailure? failure) {
    return switch (failure) {
      InteliexMobileApiFailure.authFail => ContactDirectoryFailure.authFailed,
      InteliexMobileApiFailure.userNotFound => ContactDirectoryFailure.notFound,
      InteliexMobileApiFailure.requiredFields =>
        ContactDirectoryFailure.invalidRequest,
      InteliexMobileApiFailure.unknown => ContactDirectoryFailure.unknown,
      null => ContactDirectoryFailure.unknown,
    };
  }
}
