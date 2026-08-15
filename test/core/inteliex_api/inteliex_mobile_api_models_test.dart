import 'package:flutter_test/flutter_test.dart';

import 'package:inteliex_softphone/core/inteliex_api/inteliex_mobile_api_models.dart';

void main() {
  group('Inteliex request models', () {
    test('search request serializes with seach typo and offset page key', () {
      const envelope = InteliexMobileApiRequestEnvelope(
        auth: InteliexMobileApiAuth(
          user: 'elk-251-ext',
          password: 'secret',
          fcmToken: 'fcm-123',
        ),
        request: InteliexPersonalPhoneBookSearchRequest(
          query: 'test',
          offset: 50,
          recordPerPage: 25,
        ),
      );

      expect(envelope.toJson(), {
        'auth': {
          'user': 'elk-251-ext',
          'password': 'secret',
          'fcmtoken': 'fcm-123',
        },
        'request': {
          'action': 'personal_phone_book_search',
          'page': 50,
          'record_per_page': 25,
          'seach': 'test',
        },
      });
    });

    test('phone book add request uses documented wire keys', () {
      const envelope = InteliexMobileApiRequestEnvelope(
        auth: InteliexMobileApiAuth(user: '251', password: 'secret'),
        request: InteliexPersonalPhoneBookAddRequest(
          entry: InteliexPhoneBookDraft(
            nameCompany: 'Acme',
            registerName: 'Ayse',
            phoneNumber: '02121234567',
            mobilePhone: '05321234567',
            comment: 'Onemli musteri',
          ),
        ),
      );

      expect(envelope.toJson()['request'], {
        'action': 'personal_phone_book_add',
        'name_company': 'Acme',
        'register_name': 'Ayse',
        'phone_number': '02121234567',
        'phone_number2': '',
        'phone_number3': '',
        'mobile_phone': '05321234567',
        'mobile_phone2': '',
        'fax_number': '',
        'comment': 'Onemli musteri',
        'email': '',
        'email2': '',
        'address': '',
      });
    });

    test('phone book update request carries recordid', () {
      const request = InteliexPersonalPhoneBookUpdateRequest(
        recordId: '6300',
        entry: InteliexPhoneBookDraft(
          nameCompany: 'Acme',
          registerName: 'Ayse',
        ),
      );

      expect(request.toJson()['recordid'], '6300');
      expect(request.toJson()['action'], 'personal_phone_book_update');
    });
  });

  group('Inteliex response models', () {
    test('phone book response normalizes legacy field names', () {
      final response = InteliexPhoneBookResponse.fromJson({
        'status': 'ok-phone_book',
        'page_count': '3',
        'results': [
          {
            'name_company': 'ABC Sirketi',
            'mobilephone': '05321234567',
            'mobilephone2': '05329876543',
            'comment': '',
            'speed_dial': '701',
          },
        ],
      });

      expect(response.isSuccess, isTrue);
      expect(response.pageCount, 3);
      expect(response.results.single.mobilePhone, '05321234567');
      expect(response.results.single.mobilePhone2, '05329876543');
      expect(response.results.single.speedDial, '701');
    });

    test('personal phone book response reads coment typo and numeric record id', () {
      final response = InteliexPersonalPhoneBookResponse.fromJson({
        'status': 'ok-personal_phone_book',
        'page_count': 1,
        'results': [
          {
            'recordid': 15,
            'name_company': 'XYZ Ltd.',
            'mobile_phone': '05329876543',
            'coment': 'Musteri notlari',
          },
        ],
      });

      expect(response.results.single.recordId, '15');
      expect(response.results.single.mobilePhone, '05329876543');
      expect(response.results.single.comment, 'Musteri notlari');
    });

    test('voice mail response parses duration and date label', () {
      final response = InteliexVoiceMailResponse.fromJson({
        'status': 'ok-voice_mail',
        'results': [
          {
            'caller': '05321234567',
            'date': '2025-10-15 14:30',
            'duration': '25',
            'audio_url': 'http://example.com/msg0001.mp3',
            'recordid': 'msg0001',
          },
        ],
      });

      expect(response.results.single.durationSeconds, 25);
      expect(response.results.single.recordId, 'msg0001');
      expect(response.results.single.recordedAt, DateTime(2025, 10, 15, 14, 30));
    });

    test('mutation response exposes typed failures', () {
      final response = InteliexMutationResponse.fromJson(
        {'status': 'required_fields'},
        expectedAction: InteliexMobileApiAction.personalPhoneBookAdd,
      );

      expect(response.isSuccess, isFalse);
      expect(response.failure, InteliexMobileApiFailure.requiredFields);
      expect(response.isExpectedSuccess, isFalse);
    });

    test('short codes response maps result object', () {
      final response = InteliexShortCodesResponse.fromJson({
        'status': 'ok-short_codes',
        'results': {
          'outbound_prefix': '9',
          'pickup_exten': '*8',
          'blindxfer': '#1',
        },
      });

      expect(response.shortCodes.outboundPrefix, '9');
      expect(response.shortCodes.pickupExtension, '*8');
      expect(response.shortCodes.blindTransfer, '#1');
    });
  });
}