enum DeviceClaimDecision {
  allow,
  reject,
}

enum RegisterEventStatus {
  started,
  success,
  failed,
  unregistered,
}

class DeviceClaimCheckRequest {
  const DeviceClaimCheckRequest({
    required this.tenantId,
    required this.extension,
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.requestId,
    this.pushToken,
  });

  final String tenantId;
  final String extension;
  final String deviceId;
  final String platform;
  final String appVersion;
  final String requestId;
  final String? pushToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tenantId': tenantId,
      'extension': extension,
      'deviceId': deviceId,
      'platform': platform,
      'appVersion': appVersion,
      'requestId': requestId,
      if (pushToken != null && pushToken!.trim().isNotEmpty)
        'pushToken': pushToken,
    };
  }
}

class DeviceClaimCheckResponse {
  const DeviceClaimCheckResponse({
    required this.decision,
    this.reasonCode,
    this.message,
  });

  final DeviceClaimDecision decision;
  final String? reasonCode;
  final String? message;

  bool get isAllowed => decision == DeviceClaimDecision.allow;

  factory DeviceClaimCheckResponse.fromJson(Map<String, dynamic> json) {
    final rawDecision = (json['decision']?.toString() ?? '').trim().toLowerCase();
    final decision = rawDecision == 'reject'
        ? DeviceClaimDecision.reject
        : DeviceClaimDecision.allow;

    final reasonCode = json['reasonCode']?.toString().trim();
    final message = json['message']?.toString().trim();

    return DeviceClaimCheckResponse(
      decision: decision,
      reasonCode: reasonCode == null || reasonCode.isEmpty ? null : reasonCode,
      message: message == null || message.isEmpty ? null : message,
    );
  }
}

class RegisterEventRequest {
  const RegisterEventRequest({
    required this.tenantId,
    required this.extension,
    required this.deviceId,
    required this.status,
    required this.requestId,
    required this.occurredAt,
    this.sipCode,
    this.reason,
  });

  final String tenantId;
  final String extension;
  final String deviceId;
  final RegisterEventStatus status;
  final String requestId;
  final DateTime occurredAt;
  final int? sipCode;
  final String? reason;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tenantId': tenantId,
      'extension': extension,
      'deviceId': deviceId,
      'status': status.name,
      'requestId': requestId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
      if (sipCode != null) 'sipCode': sipCode,
      if (reason != null && reason!.trim().isNotEmpty) 'reason': reason,
    };
  }
}

class DeviceUpsertRequest {
  const DeviceUpsertRequest({
    required this.tenantId,
    required this.extension,
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.requestId,
    this.pushToken,
  });

  final String tenantId;
  final String extension;
  final String deviceId;
  final String platform;
  final String appVersion;
  final String requestId;
  final String? pushToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'tenantId': tenantId,
      'extension': extension,
      'deviceId': deviceId,
      'platform': platform,
      'appVersion': appVersion,
      'requestId': requestId,
      if (pushToken != null && pushToken!.trim().isNotEmpty)
        'pushToken': pushToken,
    };
  }
}

abstract class SoftphoneRegisterClaimService {
  Future<void> upsertDevice(DeviceUpsertRequest request);

  Future<DeviceClaimCheckResponse> checkDeviceClaim(
    DeviceClaimCheckRequest request,
  );

  Future<void> postRegisterEvent(RegisterEventRequest request);
}

class SoftphoneRegisterClaimServiceException implements Exception {
  const SoftphoneRegisterClaimServiceException(
    this.message, {
    this.statusCode,
  });

  final String message;
  final int? statusCode;

  @override
  String toString() {
    if (statusCode == null) {
      return 'SoftphoneRegisterClaimServiceException: $message';
    }

    return 'SoftphoneRegisterClaimServiceException(status=$statusCode): $message';
  }
}
