import 'http_softphone_register_claim_service.dart';
import 'softphone_register_claim_service.dart';

SoftphoneRegisterClaimService createSoftphoneRegisterClaimService() {
  const configuredBaseUrl = String.fromEnvironment(
    'INTELIEX_CLAIM_BASE_URL',
    defaultValue: '',
  );
  final baseUrl = configuredBaseUrl.trim();
  if (baseUrl.isNotEmpty) {
    const apiKey = String.fromEnvironment(
      'INTELIEX_CLAIM_API_KEY',
      defaultValue: '',
    );
    const devicesPath = String.fromEnvironment(
      'INTELIEX_CLAIM_DEVICES_PATH',
      defaultValue: '/api/v2/index.php?_path=devices',
    );
    const checkPath = String.fromEnvironment(
      'INTELIEX_CLAIM_CHECK_PATH',
      defaultValue: '',
    );
    const eventPath = String.fromEnvironment(
      'INTELIEX_CLAIM_EVENT_PATH',
      defaultValue: '',
    );

    return HttpSoftphoneRegisterClaimService(
      baseUrl: baseUrl,
      apiKey: apiKey.trim().isEmpty ? null : apiKey,
      devicesPath: devicesPath,
      checkPath: checkPath,
      eventPath: eventPath,
    );
  }

  return _NoopSoftphoneRegisterClaimService();
}

class _NoopSoftphoneRegisterClaimService implements SoftphoneRegisterClaimService {
  @override
  Future<void> upsertDevice(DeviceUpsertRequest request) async {}

  @override
  Future<DeviceClaimCheckResponse> checkDeviceClaim(
    DeviceClaimCheckRequest request,
  ) async {
    return const DeviceClaimCheckResponse(
      decision: DeviceClaimDecision.allow,
    );
  }

  @override
  Future<void> postRegisterEvent(RegisterEventRequest request) async {}
}
