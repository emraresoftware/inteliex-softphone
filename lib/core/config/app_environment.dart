/// Derleme zamaninda `--dart-define` ile override edilebilir ortam sabitleri.
class AppEnvironment {
  const AppEnvironment._();

  /// SIP realm / kayit domain (IP yerine hostname).
  static const String sipDomain = String.fromEnvironment(
    'INTELIEX_SIP_DOMAIN',
    defaultValue: 'ticket.emarecloud.tr',
  );

  /// Opsiyonel derleme zamanı seed kullanıcı adı (bos = cihaz/manufacturer seed).
  static const String sipSeedUsername = String.fromEnvironment(
    'INTELIEX_SIP_USERNAME',
    defaultValue: '',
  );

  /// Opsiyonel derleme zamanı seed sifre.
  static const String sipSeedPassword = String.fromEnvironment(
    'INTELIEX_SIP_PASSWORD',
    defaultValue: '',
  );

  /// Ikinci opsiyonel seed hesap (ornegin baska dahili).
  static const String sipSeedUsername2 = String.fromEnvironment(
    'INTELIEX_SIP_USERNAME_2',
    defaultValue: '',
  );

  static const String sipSeedPassword2 = String.fromEnvironment(
    'INTELIEX_SIP_PASSWORD_2',
    defaultValue: '',
  );

  /// Derleme zamaninda tek/ coklu seed tanimlandi mi?
  static bool get hasConfiguredSipSeed =>
      sipSeedUsername.trim().isNotEmpty && sipSeedPassword.isNotEmpty;

  /// Tum Emare mobil uygulamalari icin ortak OTA taban adresi (HTTPS).
  /// Uygulama bazli path: /api/v1/updates/{app}/version
  static const String updateBaseUrl = String.fromEnvironment(
    'INTELIEX_UPDATE_BASE_URL',
    defaultValue: 'https://update.emarecloud.tr',
  );

  /// Uzaktan tanılama yalnızca anahtar derlemeye verildiğinde etkinleşir.
  static const String diagnosticsUrl = String.fromEnvironment(
    'INTELIEX_DIAGNOSTICS_URL',
    defaultValue: 'https://update.emarecloud.tr/api/v1/diagnostics/softphone',
  );

  static const String diagnosticsToken = String.fromEnvironment(
    'INTELIEX_DIAGNOSTICS_TOKEN',
    defaultValue: '',
  );

  /// Eski IP tabanli hostlarin hostname'e otomatik tasinmasi bilerek devre
  /// disi birakildi: musteriler farkli santral IP'leri kullanabiliyor ve
  /// otomatik degisiklik calisan hesaplari bozuyordu. Yeniden etkinlestirmek
  /// gerekirse burada eski host listesiyle karsilastirma yapilmali.
  static bool isLegacyHost(String value) => false;

  static String normalizeHost(String value) {
    return value.trim();
  }
}
