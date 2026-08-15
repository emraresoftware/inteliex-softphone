import 'package:flutter_test/flutter_test.dart';
import 'package:inteliex_softphone/services/sip/softphone_controller.dart';
import 'package:inteliex_softphone/services/sip/softphone_register_claim_service.dart';

void main() {
  group('DeviceClaimCheckResponse', () {
    test('reject kararini ve mesaji parse eder', () {
      final response = DeviceClaimCheckResponse.fromJson(
        const <String, dynamic>{
          'decision': 'reject',
          'reasonCode': 'ALREADY_CLAIMED',
          'message': 'Bu dahili aktif.',
        },
      );

      expect(response.decision, DeviceClaimDecision.reject);
      expect(response.isAllowed, isFalse);
      expect(response.reasonCode, 'ALREADY_CLAIMED');
      expect(response.message, 'Bu dahili aktif.');
    });

    test('bilinmeyen karar degerini allow varsayar', () {
      final response = DeviceClaimCheckResponse.fromJson(
        const <String, dynamic>{
          'decision': 'unexpected-value',
        },
      );

      expect(response.decision, DeviceClaimDecision.allow);
      expect(response.isAllowed, isTrue);
    });
  });

  group('DTO serialization', () {
    test('DeviceClaimCheckRequest bos pushToken alanini yazmaz', () {
      const request = DeviceClaimCheckRequest(
        tenantId: 'demo1.sesdata.com',
        extension: '205',
        deviceId: 'sp-abc',
        platform: 'android',
        appVersion: '0.1.0+1',
        requestId: 'req-1',
        pushToken: '   ',
      );

      final json = request.toJson();
      expect(json['tenantId'], 'demo1.sesdata.com');
      expect(json.containsKey('pushToken'), isFalse);
    });

    test('RegisterEventRequest UTC tarih yazar', () {
      final request = RegisterEventRequest(
        tenantId: 'demo1.sesdata.com',
        extension: '205',
        deviceId: 'sp-abc',
        status: RegisterEventStatus.success,
        requestId: 'req-2',
        occurredAt: DateTime.parse('2026-05-20T12:00:00+03:00'),
        sipCode: 200,
      );

      final json = request.toJson();
      expect(json['status'], 'success');
      expect(json['sipCode'], 200);
      expect(json['occurredAt'], '2026-05-20T09:00:00.000Z');
    });
  });

  group('SoftphoneController.extractSipCode', () {
    test('extracts SIP code from reason strings', () {
      expect(SoftphoneController.extractSipCode('SIP 403 Forbidden'), 403);
      expect(SoftphoneController.extractSipCode('SIP 200 OK'), 200);
      expect(SoftphoneController.extractSipCode('SIP 408 Timeout'), 408);
      expect(SoftphoneController.extractSipCode('Failed with SIP 503 Service Unavailable'), 503);
    });

    test('returns null for invalid or missing SIP codes', () {
      expect(SoftphoneController.extractSipCode(null), isNull);
      expect(SoftphoneController.extractSipCode(''), isNull);
      expect(SoftphoneController.extractSipCode('Forbidden error'), isNull);
      expect(SoftphoneController.extractSipCode('SIP 40 Forbidden'), isNull); // only 2 digits
      expect(SoftphoneController.extractSipCode('SIP 4034 Too Long'), isNull); // 4 digits
    });
  });
}
