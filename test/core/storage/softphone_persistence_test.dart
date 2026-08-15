import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:inteliex_softphone/core/models/sip_account.dart';
import 'package:inteliex_softphone/core/storage/softphone_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceSoftphonePersistence.load', () {
    const accountId = 'account-1';
    const selectedAccountKey = 'flutter.inteliex.selected_account_id';
    const accountsKey = 'flutter.inteliex.accounts';

    final serializedAccounts = jsonEncode([
      {
        'id': accountId,
        'displayName': 'Merkez',
        'username': '101',
        'authorizationUser': '101',
        'domain': 'pbx.example.com',
        'websocketUrl': 'wss://pbx.example.com:8089/ws',
        'signalingAddress': 'wss://pbx.example.com:8089/ws',
        'transport': 'wss',
        'allowBadCertificate': false,
        'isPrimary': true,
      },
    ]);

    setUp(() {
      SharedPreferences.setMockInitialValues({
        accountsKey: serializedAccounts,
        selectedAccountKey: accountId,
      });
    });

    test('returns stored account when secure storage succeeds', () async {
      final persistence = DeviceSoftphonePersistence(
        secureStorage: _FakeSecureStorage(
          values: {'inteliex.account.password.$accountId': 'secret101'},
        ),
      );

      final state = await persistence.load();

      expect(state.hasStoredAccounts, isTrue);
      expect(state.hasMissingSecrets, isFalse);
      expect(state.selectedAccountId, accountId);
      expect(state.accounts, hasLength(1));
      expect(state.accounts.single.id, accountId);
      expect(state.accounts.single.password, 'secret101');
      expect(
        state.accounts.single.registrationStatus,
        RegistrationStatus.registered,
      );
    });

    test('keeps account metadata when secure storage read throws', () async {
      final persistence = DeviceSoftphonePersistence(
        secureStorage: _FakeSecureStorage(throwOnRead: true),
      );

      final state = await persistence.load();

      expect(state.hasStoredAccounts, isTrue);
      expect(state.hasMissingSecrets, isTrue);
      expect(state.selectedAccountId, accountId);
      expect(state.accounts, hasLength(1));
      expect(state.accounts.single.id, accountId);
      expect(state.accounts.single.password, isEmpty);
      expect(state.accounts.single.displayName, 'Merkez');
      expect(state.accounts.single.registrationStatus, RegistrationStatus.failed);
    });
  });
}

class _FakeSecureStorage extends FlutterSecureStorage {
  _FakeSecureStorage({
    Map<String, String>? values,
    this.throwOnRead = false,
  }) : _values = Map<String, String>.from(values ?? const {});

  final Map<String, String> _values;
  final bool throwOnRead;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
      return;
    }

    _values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnRead) {
      throw PlatformException(code: 'read-failed');
    }

    return _values[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(_values);
  }
}