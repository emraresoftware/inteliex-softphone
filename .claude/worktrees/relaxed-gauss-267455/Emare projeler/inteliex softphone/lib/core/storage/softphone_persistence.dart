import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_log_entry.dart';
import '../models/sip_account.dart';

class PersistedSoftphoneState {
  const PersistedSoftphoneState({
    this.accounts = const [],
    this.callLogs = const [],
    this.selectedAccountId,
    this.hasStoredAccounts = false,
    this.hasMissingSecrets = false,
  });

  final List<SipAccount> accounts;
  final List<CallLogEntry> callLogs;
  final String? selectedAccountId;
  final bool hasStoredAccounts;
  final bool hasMissingSecrets;
}

abstract class SoftphonePersistence {
  Future<PersistedSoftphoneState> load();

  Future<void> saveAccounts({
    required List<SipAccount> accounts,
    required String? selectedAccountId,
  });

  Future<void> saveCallLogs(List<CallLogEntry> callLogs);
}

class DeviceSoftphonePersistence implements SoftphonePersistence {
  DeviceSoftphonePersistence({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _accountsKey = 'inteliex.accounts';
  static const _callLogsKey = 'inteliex.call_logs';
  static const _selectedAccountKey = 'inteliex.selected_account_id';
  static const _passwordPrefix = 'inteliex.account.password.';
  static const _passwordMirrorPrefix = 'inteliex.account.password.mirror.';
  static const _maxStoredCallLogs = 100;

  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _sharedPreferences;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<PersistedSoftphoneState> load() async {
    try {
      final prefs = await _prefs();
      final rawAccounts = prefs.getString(_accountsKey);
      final decodedAccounts = await _decodeAccounts(rawAccounts);
      final callLogs = _safeDecodeCallLogs(prefs.getString(_callLogsKey));
      final selectedAccountId = prefs.getString(_selectedAccountKey);

      debugPrint(
        'Softphone persistence load: hasStoredAccounts=${decodedAccounts.hadSerializedAccounts} accounts=${decodedAccounts.accounts.length} selected=$selectedAccountId missingSecrets=${decodedAccounts.missingSecrets} callLogs=${callLogs.length}',
      );

      return PersistedSoftphoneState(
        accounts: decodedAccounts.accounts,
        callLogs: callLogs,
        selectedAccountId: selectedAccountId,
        hasStoredAccounts: decodedAccounts.hadSerializedAccounts,
        hasMissingSecrets: decodedAccounts.missingSecrets,
      );
    } catch (error) {
      debugPrint('Softphone state load failed: $error');

      try {
        final prefs = await _prefs();
        final rawAccounts = prefs.getString(_accountsKey);
        final selectedAccountId = prefs.getString(_selectedAccountKey);
        final fallbackAccounts = _decodeAccountsWithoutSecrets(rawAccounts);
        final hasStoredAccounts = rawAccounts != null && rawAccounts.isNotEmpty;

        if (!hasStoredAccounts) {
          return const PersistedSoftphoneState();
        }

        return PersistedSoftphoneState(
          accounts: fallbackAccounts,
          callLogs: _safeDecodeCallLogs(prefs.getString(_callLogsKey)),
          selectedAccountId: selectedAccountId,
          hasStoredAccounts: true,
          hasMissingSecrets: true,
        );
      } catch (fallbackError) {
        debugPrint('Softphone fallback state load failed: $fallbackError');
        return const PersistedSoftphoneState();
      }
    }
  }

  @override
  Future<void> saveAccounts({
    required List<SipAccount> accounts,
    required String? selectedAccountId,
  }) {
    return _enqueueWrite(() async {
      debugPrint(
        'Softphone persistence saveAccounts: accounts=${accounts.length} selected=$selectedAccountId',
      );

      final prefs = await _prefs();
      final serializedAccounts = accounts
          .map((account) => account.toStorageJson())
          .toList(growable: false);

      if (serializedAccounts.isEmpty) {
        await prefs.remove(_accountsKey);
        await prefs.remove(_selectedAccountKey);
      } else {
        await prefs.setString(_accountsKey, jsonEncode(serializedAccounts));
        if (selectedAccountId == null || selectedAccountId.isEmpty) {
          await prefs.remove(_selectedAccountKey);
        } else {
          await prefs.setString(_selectedAccountKey, selectedAccountId);
        }
      }

      final activePasswordKeys = <String>{};
      final activeMirrorKeys = <String>{};
      for (final account in accounts) {
        final key = _passwordKey(account.id);
        final mirrorKey = _passwordMirrorKey(account.id);
        activePasswordKeys.add(key);
        activeMirrorKeys.add(mirrorKey);
        await _secureStorage.write(key: key, value: account.password);
        await prefs.setString(mirrorKey, account.password);
      }

      final existingValues = await _secureStorage.readAll();
      for (final key in existingValues.keys) {
        if (!key.startsWith(_passwordPrefix) || activePasswordKeys.contains(key)) {
          continue;
        }

        await _secureStorage.delete(key: key);
      }

      final mirrorKeys = prefs.getKeys();
      for (final key in mirrorKeys) {
        if (!key.startsWith(_passwordMirrorPrefix) ||
            activeMirrorKeys.contains(key)) {
          continue;
        }
        await prefs.remove(key);
      }

      debugPrint(
        'Softphone persistence saveAccounts complete: accountIds=${accounts.map((account) => account.id).join(',')}',
      );
    });
  }

  @override
  Future<void> saveCallLogs(List<CallLogEntry> callLogs) {
    return _enqueueWrite(() async {
      final prefs = await _prefs();
      final serializedLogs = callLogs
          .take(_maxStoredCallLogs)
          .map((entry) => entry.toStorageJson())
          .toList(growable: false);

      if (serializedLogs.isEmpty) {
        await prefs.remove(_callLogsKey);
        return;
      }

      await prefs.setString(_callLogsKey, jsonEncode(serializedLogs));
    });
  }

  Future<SharedPreferences> _prefs() async {
    return _sharedPreferences ??= await SharedPreferences.getInstance();
  }

  Future<_DecodedAccounts> _decodeAccounts(String? raw) async {
    final decoded = _decodeList(raw);
    if (decoded.isEmpty) {
      return const _DecodedAccounts();
    }

    final prefs = await _prefs();
    final accounts = <SipAccount>[];
    var missingSecrets = false;
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final data = Map<String, dynamic>.from(item);
      final id = data['id']?.toString() ?? '';
      if (id.isEmpty) {
        continue;
      }

      String? password;
      try {
        password = await _secureStorage.read(key: _passwordKey(id));
      } catch (error) {
        debugPrint('Softphone account secret read failed for $id: $error');
      }

      final passwordMissing = password == null || password.isEmpty;
      if (passwordMissing) {
        final mirrorPassword = prefs.getString(_passwordMirrorKey(id));
        if (mirrorPassword != null && mirrorPassword.isNotEmpty) {
          password = mirrorPassword;
        }
      }

      final normalizedPassword = password ?? '';
      final normalizedPasswordMissing = normalizedPassword.isEmpty;
      if (normalizedPasswordMissing) {
        missingSecrets = true;
        debugPrint(
          'Softphone account secret missing for $id; keeping account metadata and requiring password re-entry.',
        );
      }

      final normalizedAccount = _normalizeStoredAccount(
        data,
        password: normalizedPassword,
        passwordMissing: normalizedPasswordMissing,
      );
      if (normalizedAccount != null) {
        accounts.add(normalizedAccount);
      }
    }

    return _DecodedAccounts(
      accounts: accounts,
      hadSerializedAccounts: true,
      missingSecrets: missingSecrets,
    );
  }

  List<SipAccount> _decodeAccountsWithoutSecrets(String? raw) {
    final decoded = _decodeList(raw);
    if (decoded.isEmpty) {
      return const <SipAccount>[];
    }

    final accounts = <SipAccount>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final data = Map<String, dynamic>.from(item);
      final normalizedAccount = _normalizeStoredAccount(
        data,
        password: '',
        passwordMissing: true,
      );
      if (normalizedAccount != null) {
        accounts.add(normalizedAccount);
      }
    }

    return accounts;
  }

  SipAccount? _normalizeStoredAccount(
    Map<String, dynamic> data, {
    required String password,
    required bool passwordMissing,
  }) {
    final id = data['id']?.toString() ?? '';
    if (id.isEmpty) {
      return null;
    }

    final account = SipAccount.fromStorageJson(
      data,
      password: password,
    );

    final normalizedUsername = account.username.trim().isNotEmpty
        ? account.username.trim()
        : account.authorizationUser.trim();
    final normalizedAuthorizationUser = account.authorizationUser.trim().isNotEmpty
        ? account.authorizationUser.trim()
        : normalizedUsername;
    final normalizedDomain = account.domain.trim().isNotEmpty
        ? account.domain.trim()
        : _deriveDomainFromSignalingAddress(account.websocketUrl);
    final normalizedSignalingAddress = account.websocketUrl.trim().isNotEmpty
        ? account.websocketUrl.trim()
        : normalizedDomain;
    final normalizedDisplayName = account.displayName.trim().isNotEmpty
        ? account.displayName.trim()
        : normalizedUsername.isNotEmpty
            ? normalizedUsername
            : normalizedDomain;

    if (normalizedDisplayName.isEmpty ||
        normalizedUsername.isEmpty ||
        normalizedAuthorizationUser.isEmpty ||
        normalizedDomain.isEmpty ||
        normalizedSignalingAddress.isEmpty) {
      debugPrint(
        'Softphone account metadata incomplete for $id; account could not be recovered.',
      );
      return null;
    }

    return account.copyWith(
      displayName: normalizedDisplayName,
      username: normalizedUsername,
      authorizationUser: normalizedAuthorizationUser,
      domain: normalizedDomain,
      websocketUrl: normalizedSignalingAddress,
      registrationStatus: passwordMissing
          ? RegistrationStatus.failed
          : RegistrationStatus.disconnected,
    );
  }

  List<CallLogEntry> _decodeCallLogs(String? raw) {
    final decoded = _decodeList(raw);
    if (decoded.isEmpty) {
      return const <CallLogEntry>[];
    }

    final callLogs = <CallLogEntry>[];
    for (final item in decoded) {
      if (item is! Map) {
        continue;
      }

      final data = Map<String, dynamic>.from(item);
      final sessionId = data['sessionId']?.toString() ?? '';
      if (sessionId.isEmpty) {
        continue;
      }

      callLogs.add(CallLogEntry.fromStorageJson(data));
    }

    return callLogs;
  }

  List<CallLogEntry> _safeDecodeCallLogs(String? raw) {
    try {
      return _decodeCallLogs(raw);
    } catch (error) {
      debugPrint('Softphone call log decode failed: $error');
      return const <CallLogEntry>[];
    }
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <dynamic>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List<dynamic>) {
        return decoded;
      }
    } catch (error) {
      debugPrint('Softphone persistence decode failed: $error');
    }

    return const <dynamic>[];
  }

  String _deriveDomainFromSignalingAddress(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return '';
    }

    final uri = trimmedValue.contains('://')
        ? Uri.tryParse(trimmedValue)
        : Uri.tryParse('sip://$trimmedValue');
    if (uri != null && uri.host.trim().isNotEmpty) {
      return uri.host.trim();
    }

    final host = trimmedValue.split('/').first.split(':').first.trim();
    return host;
  }

  String _passwordKey(String accountId) => '$_passwordPrefix$accountId';

  String _passwordMirrorKey(String accountId) =>
      '$_passwordMirrorPrefix$accountId';

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    _writeQueue = _writeQueue.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('Softphone persistence save failed: $error');
      }
    });

    return _writeQueue;
  }
}

class _DecodedAccounts {
  const _DecodedAccounts({
    this.accounts = const <SipAccount>[],
    this.hadSerializedAccounts = false,
    this.missingSecrets = false,
  });

  final List<SipAccount> accounts;
  final bool hadSerializedAccounts;
  final bool missingSecrets;
}