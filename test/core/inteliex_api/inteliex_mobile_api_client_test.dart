import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:inteliex_softphone/core/inteliex_api/inteliex_mobile_api_client.dart';
import 'package:inteliex_softphone/core/inteliex_api/inteliex_mobile_api_models.dart';
import 'package:inteliex_softphone/core/models/sip_account.dart';

void main() {
  group('inteliexMobileApiEndpointFromAccount', () {
    test('derives https endpoint from wss signaling url host', () {
      const account = SipAccount(
        id: 'account-1',
        displayName: 'Merkez',
        username: '251',
        authorizationUser: '251',
        password: 'secret',
        domain: 'pbx.example.com',
        websocketUrl: 'wss://pbx.example.com:8089/ws',
        registrationStatus: RegistrationStatus.disconnected,
      );

      expect(
        inteliexMobileApiEndpointFromAccount(account),
        Uri.parse(
          'https://pbx.example.com/asteradmin/inteliex-mobile-api.php?request_type=$inteliexMobileApiRequestType',
        ),
      );
    });

    test('uses https directly for API v2 on a named SIP host', () {
      const account = SipAccount(
        id: 'account-1',
        displayName: 'Sesdata',
        username: '601',
        authorizationUser: 'elk-601-ext',
        password: 'secret',
        domain: 'demo1.sesdata.com',
        websocketUrl: '',
        registrationStatus: RegistrationStatus.disconnected,
      );

      expect(
        inteliexApiV2EndpointFromAccount(account),
        Uri.parse('https://demo1.sesdata.com/api/v2/index.php'),
      );
    });

    test('keeps direct api path if account already contains it', () {
      const account = SipAccount(
        id: 'account-1',
        displayName: 'Merkez',
        username: '251',
        authorizationUser: '251',
        password: 'secret',
        domain: 'pbx.example.com',
        websocketUrl:
            'http://demo1.sesdata.com/asteradmin/inteliex-mobile-api.php',
        registrationStatus: RegistrationStatus.disconnected,
      );

      expect(
        inteliexMobileApiEndpointFromAccount(account),
        Uri.parse(
          'http://demo1.sesdata.com/asteradmin/inteliex-mobile-api.php?request_type=$inteliexMobileApiRequestType',
        ),
      );
    });
  });

  group('InteliexMobileApiClient', () {
    test('fetchDirectoryForAccount merges paginated directory responses',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url,
          Uri.parse(
            'https://pbx.example.com/asteradmin/inteliex-mobile-api.php?request_type=$inteliexMobileApiRequestType',
          ),
        );

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final auth = body['auth'] as Map<String, dynamic>;
        final payload = body['request'] as Map<String, dynamic>;
        expect(auth['user'], '251');
        expect(auth['password'], 'secret');

        final action = payload['action'];
        final page = payload['page'];

        if (action == 'ext_list' && page == 0) {
          return http.Response(
            jsonEncode({
              'status': 'ok-ext_list',
              'page_count': 2,
              'results': [
                {'name': 'Operasyon', 'extens': '1001'},
              ],
            }),
            200,
          );
        }

        if (action == 'ext_list' && page == 50) {
          return http.Response(
            jsonEncode({
              'status': 'ok-ext_list',
              'page_count': 2,
              'results': [
                {'name': 'Satis', 'extens': '1002'},
              ],
            }),
            200,
          );
        }

        if (action == 'phone_book') {
          return http.Response(
            jsonEncode({
              'status': 'ok-phone_book',
              'page_count': 1,
              'results': [
                {
                  'recordid': '17',
                  'name_company': 'ABC Sirketi',
                  'register_name': 'Ali Veli',
                  'phone_number': '02121234567',
                },
              ],
            }),
            200,
          );
        }

        if (action == 'personal_phone_book') {
          return http.Response(
            jsonEncode({
              'status': 'ok-personal_phone_book',
              'page_count': 1,
              'results': [
                {
                  'recordid': 15,
                  'name_company': 'XYZ Ltd.',
                  'register_name': 'Ayse Kara',
                  'mobile_phone': '05329876543',
                },
              ],
            }),
            200,
          );
        }

        throw StateError('Beklenmeyen istek: $action/$page');
      });

      final client = InteliexMobileApiClient(httpClient: mockClient);
      const account = SipAccount(
        id: 'account-1',
        displayName: 'Merkez',
        username: '251',
        authorizationUser: '251',
        password: 'secret',
        domain: 'pbx.example.com',
        websocketUrl: 'wss://pbx.example.com:8089/ws',
        registrationStatus: RegistrationStatus.disconnected,
      );

      final directory = await client.fetchDirectoryForAccount(account);

      expect(directory.extensionContacts, hasLength(2));
      expect(directory.sharedContacts.single.displayName, 'ABC Sirketi');
      expect(
        directory.sharedContacts.single.department,
        'Ali Veli • Genel Rehber',
      );
      expect(directory.personalContacts.single.primaryNumber, '05329876543');
      expect(directory.allContacts, hasLength(4));
    });

    test('fetchDirectory throws typed auth failure on auth_fail status',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 'auth_fail'}), 200);
      });

      final client = InteliexMobileApiClient(httpClient: mockClient);

      expect(
        client.fetchDirectory(
          endpoint: Uri.parse(
            'http://demo1.sesdata.com/asteradmin/inteliex-mobile-api.php?request_type=$inteliexMobileApiRequestType',
          ),
          auth: const InteliexMobileApiAuth(user: '251', password: 'wrong'),
        ),
        throwsA(
          isA<InteliexMobileApiException>().having(
            (error) => error.failure,
            'failure',
            InteliexMobileApiFailure.authFail,
          ),
        ),
      );
    });
  });
}
