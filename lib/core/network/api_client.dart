import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../error/app_exception.dart';
import '../logging/app_logger.dart';

/// Shared HTTP client for third-party catalog APIs.
///
/// * One pooled [http.Client] for connection reuse.
/// * Timeouts + jittered exponential backoff for idempotent GETs.
/// * Large JSON bodies are decoded off the UI isolate to avoid jank.
class ApiClient {
  ApiClient({http.Client? client, this.userAgent = 'Synk/1.0 (Flutter)'}) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;
  final Random _random = Random();

  static const Duration _timeout = Duration(seconds: 12);
  static const int _isolateThresholdBytes = 48 * 1024;

  Future<Object?> getJson(Uri uri, {int retries = 2, Map<String, String> headers = const {}}) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await _client
            .get(uri, headers: {'User-Agent': userAgent, 'Accept': 'application/json', ...headers})
            .timeout(_timeout);
        if (response.statusCode == 404) throw const NotFoundException();
        if (response.statusCode >= 500 || response.statusCode == 429) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        if (response.statusCode >= 400) {
          throw HttpStatusException(response.statusCode, cause: utf8.decode(response.bodyBytes, allowMalformed: true));
        }
        return _decode(response.bodyBytes);
      } on NotFoundException {
        rethrow;
      } on HttpStatusException {
        rethrow;
      } catch (e, st) {
        final retryable = e is SocketException || e is TimeoutException || e is HttpException;
        if (!retryable || attempt >= retries) {
          AppLogger.error('ApiClient', e, st);
          throw AppException.from(e);
        }
        attempt++;
        final backoffMs = 300 * pow(2, attempt).toInt() + _random.nextInt(250);
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
      }
    }
  }

  Future<Object?> _decode(List<int> bytes) {
    if (bytes.length < _isolateThresholdBytes) {
      return Future.value(jsonDecode(utf8.decode(bytes)));
    }
    return Isolate.run(() => jsonDecode(utf8.decode(bytes)));
  }

  void close() => _client.close();
}
