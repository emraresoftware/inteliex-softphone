import '../models/contact_entry.dart';
import '../models/sip_account.dart';

/// Sağlayıcıdan bağımsız rehber çekme arayüzü.
///
/// Inteliex Mobile API gibi backend'li sağlayıcılar bu arayüzü uygular;
/// herhangi bir SIP sağlayıcısıyla manuel kullanılan hesaplar için
/// [NoopContactDirectoryProvider] kullanılır.
abstract class ContactDirectoryProvider {
  /// [account] için bu sağlayıcının rehber çekebilir olup olmadığını döner.
  bool supports(SipAccount account);

  /// Rehber kayıtlarını sağlayıcıdan çeker.
  ///
  /// [supports] false dönen hesaplar için çağrılırsa
  /// [ContactDirectoryFailure.unsupported] fırlatır.
  Future<ContactDirectoryResult> fetchForAccount(SipAccount account);

  /// Sağlayıcının açık tuttuğu kaynakları (HTTP istemcisi vb.) kapatır.
  Future<void> close();
}

/// Sağlayıcıdan dönen rehber sonucu.
class ContactDirectoryResult {
  const ContactDirectoryResult({
    this.extensionContacts = const <ContactEntry>[],
    this.sharedContacts = const <ContactEntry>[],
    this.personalContacts = const <ContactEntry>[],
  });

  final List<ContactEntry> extensionContacts;
  final List<ContactEntry> sharedContacts;
  final List<ContactEntry> personalContacts;

  bool get isEmpty =>
      extensionContacts.isEmpty &&
      sharedContacts.isEmpty &&
      personalContacts.isEmpty;
}

/// Rehber çekme sırasında oluşan tipli hata.
class ContactDirectoryException implements Exception {
  const ContactDirectoryException(
    this.message, {
    this.failure = ContactDirectoryFailure.unknown,
  });

  final String message;
  final ContactDirectoryFailure failure;

  @override
  String toString() {
    return 'ContactDirectoryException(message: $message, failure: $failure)';
  }
}

/// Sağlayıcıdan bağımsız rehber hata türleri.
enum ContactDirectoryFailure {
  /// Sağlayıcı bu hesap için rehber sağlamıyor (manuel SIP hesabı vb.).
  unsupported,

  /// Sağlayıcıya kimlik doğrulama başarısız oldu.
  authFailed,

  /// İstenen kullanıcı/hesap sağlayıcıda bulunamadı.
  notFound,

  /// İstek eksik/geçersiz alanlar nedeniyle reddedildi.
  invalidRequest,

  /// Ağ veya sınıflandırılamayan diğer hata.
  unknown,
}

/// Hiçbir hesap için rehber sağlamayan varsayılan sağlayıcı.
///
/// Manuel SIP hesaplarıyla çalışan generic kullanım için varsayılandır.
class NoopContactDirectoryProvider implements ContactDirectoryProvider {
  const NoopContactDirectoryProvider();

  @override
  bool supports(SipAccount account) => false;

  @override
  Future<ContactDirectoryResult> fetchForAccount(SipAccount account) async {
    throw const ContactDirectoryException(
      'Bu hesap için rehber sağlayıcısı yapılandırılmadı.',
      failure: ContactDirectoryFailure.unsupported,
    );
  }

  @override
  Future<void> close() async {}
}
