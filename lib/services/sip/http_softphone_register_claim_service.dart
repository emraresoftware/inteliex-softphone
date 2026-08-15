import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'softphone_register_claim_service.dart';

class HttpSoftphoneRegisterClaimService
    implements SoftphoneRegisterClaimService {
  HttpSoftphoneRegisterClaimService({
    required String baseUrl,
    String devicesPath = '/api/v2/index.php?_path=devices',
    String? checkPath,
    String? eventPath,
    this.apiKey,
    this.client,
    this.timeout = const Duration(seconds: 4),
    this.maxAttempts = 2,
  })  : _baseUri = Uri.parse(baseUrl),
        _devicesPath = devicesPath.trim(),
        _checkPath = checkPath?.trim() ?? '',
        _eventPath = eventPath?.trim() ?? '';

  final Uri _baseUri;
  final String _devicesPath;
  final String _checkPath;
  final String _eventPath;
  final String? apiKey;
  final http.Client? client;
  final Duration timeout;
  final int maxAttempts;

  http.Client get _client => client ?? _defaultClient;
  final http.Client _defaultClient = http.Client();

  @override
  Future<void> upsertDevice(DeviceUpsertRequest request) async {
    await _sendWithRetry(
      path: _devicesPath,
      payload: request.toJson(),
      requestId: request.requestId,
      operation: 'device-upsert',
    );
  }

  @override
  Future<DeviceClaimCheckResponse> checkDeviceClaim(
    DeviceClaimCheckRequest request,
  ) async {
    if (_checkPath.isEmpty) {
      debugPrint('Claim check endpoint disabled; default allow will be used.');
      return const DeviceClaimCheckResponse(
        decision: DeviceClaimDecision.allow,
      );
    }

    final response = await _sendWithRetry(
      path: _checkPath,
      payload: request.toJson(),
      requestId: request.requestId,
      operation: 'device-claim-check',
    );

    final json = _decodeJson(response.body);
    return DeviceClaimCheckResponse.fromJson(json);
  }

  @override
  Future<void> postRegisterEvent(RegisterEventRequest request) async {
    if (_eventPath.isEmpty) {
      debugPrint('Register event endpoint disabled; event post skipped.');
      return;
    }

    await _sendWithRetry(
      path: _eventPath,
      payload: request.toJson(),
      requestId: request.requestId,
      operation: 'register-event',
    );
  }

  Future<http.Response> _sendWithRetry({
    required String path,
    required Map<String, dynamic> payload,
    required String requestId,
    required String operation,
  }) async {
    var attempt = 0;
    Object? lastError;

    while (attempt < maxAttempts) {
      attempt += 1;
      try {
        final uri = _baseUri.resolve(path);
        final startedAt = DateTime.now();
        debugPrint(
          'Claim service request: op=$operation attempt=$attempt requestId=$requestId uri=$uri',
        );
        final response = await _client
            .post(
              uri,
              headers: _buildHeaders(requestId),
              body: jsonEncode(payload),
            )
            .timeout(timeout);

        final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint(
            'Claim service success: op=$operation status=${response.statusCode} elapsedMs=$elapsed requestId=$requestId',
          );
          return response;
        }

        debugPrint(
          'Claim service non-2xx: op=$operation status=${response.statusCode} elapsedMs=$elapsed requestId=$requestId',
        );

        if (_shouldRetryStatus(response.statusCode) && attempt < maxAttempts) {
          debugPrint(
            'Claim service retrying: op=$operation nextAttempt=${attempt + 1} requestId=$requestId',
          );
          await Future<void>.delayed(_retryBackoff(attempt));
          continue;
        }

        throw SoftphoneRegisterClaimServiceException(
          'Claim service $operation failed with status ${response.statusCode} '
          '(attempt=$attempt, elapsedMs=$elapsed, requestId=$requestId)',
          statusCode: response.statusCode,
        );
      } on TimeoutException catch (error) {
        debugPrint(
          'Claim service timeout: op=$operation attempt=$attempt requestId=$requestId error=$error',
        );
        lastError = error;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(_retryBackoff(attempt));
          continue;
        }
      } on http.ClientException catch (error) {
        debugPrint(
          'Claim service client error: op=$operation attempt=$attempt requestId=$requestId error=$error',
        );
        lastError = error;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(_retryBackoff(attempt));
          continue;
        }
      }
    }

    throw SoftphoneRegisterClaimServiceException(
      'Claim service $operation failed after $maxAttempts attempts '
      '(requestId=$requestId, error=$lastError)',
    );
  }

  Duration _retryBackoff(int attempt) {
    final millis = switch (attempt) {
      1 => 250,
      2 => 600,
      _ => 1000,
    };
    return Duration(milliseconds: millis);
  }

  bool _shouldRetryStatus(int statusCode) {
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Map<String, String> _buildHeaders(String requestId) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Idempotency-Key': requestId,
      'X-Request-Id': requestId,
    };

    final key = apiKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['Authorization'] = 'Bearer $key';
    }

    return headers;
  }

  Map<String, dynamic> _decodeJson(String payload) {
    if (payload.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw const SoftphoneRegisterClaimServiceException(
      'Claim service response is not a JSON object.',
    );
  }
}