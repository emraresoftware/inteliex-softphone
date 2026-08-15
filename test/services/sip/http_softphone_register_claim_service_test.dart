import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inteliex_softphone/services/sip/http_softphone_register_claim_service.dart';
import 'package:inteliex_softphone/services/sip/softphone_register_claim_service.dart';

void main() {
  group('HttpSoftphoneRegisterClaimService', () {
    test('checkDeviceClaim request atar ve response parse eder', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          '{"decision":"reject","reasonCode":"ALREADY_CLAIMED","message":"aktif"}',
          200,
        );
      });

      final service = HttpSoftphoneRegisterClaimService(
        baseUrl: 'https://api.example.com',
        checkPath: '/softphone/device-claim/check',
        apiKey: 'token-1',
        client: client,
        maxAttempts: 1,
      );

      final response = await service.checkDeviceClaim(
        const DeviceClaimCheckRequest(
          tenantId: 'demo1.sesdata.com',
          extension: '205',
          deviceId: 'sp-1',
          platform: 'android',
          appVersion: '1.0.0',
          requestId: 'req-1',
        ),
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://api.example.com/softphone/device-claim/check');
      expect(captured.headers['X-Idempotency-Key'], 'req-1');
      expect(captured.headers['Authorization'], 'Bearer token-1');
      expect(body['extension'], '205');
      expect(response.decision, DeviceClaimDecision.reject);
      expect(response.reasonCode, 'ALREADY_CLAIMED');
    });

    test('postRegisterEvent 5xx durumda retry yapar', () async {
      var attempt = 0;
      final client = MockClient((_) async {
        attempt += 1;
        if (attempt == 1) {
          return http.Response('temporary', 500);
        }
        return http.Response('', 204);
      });

      final service = HttpSoftphoneRegisterClaimService(
        baseUrl: 'https://api.example.com',
        eventPath: '/softphone/register/event',
        client: client,
        maxAttempts: 2,
      );

      await service.postRegisterEvent(
        RegisterEventRequest(
          tenantId: 'demo1.sesdata.com',
          extension: '205',
          deviceId: 'sp-1',
          status: RegisterEventStatus.started,
          requestId: 'req-2',
          occurredAt: DateTime.now(),
        ),
      );

      expect(attempt, 2);
    });

    test('client exception durumunda service exception firlatir', () async {
      final client = MockClient((_) async {
        throw http.ClientException('network down');
      });

      final service = HttpSoftphoneRegisterClaimService(
        baseUrl: 'https://api.example.com',
        checkPath: '/softphone/device-claim/check',
        client: client,
        maxAttempts: 1,
      );

      expect(
        () => service.checkDeviceClaim(
          const DeviceClaimCheckRequest(
            tenantId: 'demo1.sesdata.com',
            extension: '205',
            deviceId: 'sp-1',
            platform: 'android',
            appVersion: '1.0.0',
            requestId: 'req-3',
          ),
        ),
        throwsA(isA<SoftphoneRegisterClaimServiceException>()),
      );
    });

    test('upsertDevice query-string devices pathine gider', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      });

      final service = HttpSoftphoneRegisterClaimService(
        baseUrl: 'https://demo1.sesdata.com',
        devicesPath: '/api/v2/index.php?_path=devices',
        client: client,
        maxAttempts: 1,
      );

      await service.upsertDevice(
        const DeviceUpsertRequest(
          tenantId: 'demo1.sesdata.com',
          extension: '205',
          deviceId: 'sp-1',
          platform: 'android',
          appVersion: '1.0.0',
          requestId: 'req-4',
          pushToken: 'fcm-1',
        ),
      );

      expect(
        captured.url.toString(),
        'https://demo1.sesdata.com/api/v2/index.php?_path=devices',
      );
    });
  });
}