import 'dart:async';
import 'dart:convert';

import 'package:echoscribe/models/app_exception.dart';
import 'package:http/http.dart' as http;

class LocalAiCheckResult {
  final String message;
  final int? statusCode;

  const LocalAiCheckResult({required this.message, this.statusCode});
}

class LocalAiHealthService {
  const LocalAiHealthService._();

  static Future<LocalAiCheckResult> checkHttpReachable({
    required String endpoint,
    required String label,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final uri = _parseEndpoint(endpoint, label);
    final client = http.Client();
    try {
      final request = http.Request('HEAD', uri);
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw AppException.fromHttp(response.statusCode,
            fallback: '$label authentication failed');
      }
      if (response.statusCode >= 500) {
        throw ServerException('$label returned HTTP ${response.statusCode}');
      }
      return LocalAiCheckResult(
        message: '$label endpoint reachable (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw NetworkException(
          '$label did not respond within ${timeout.inSeconds}s');
    } catch (e) {
      throw NetworkException('$label is not reachable: ${_compactError(e)}');
    } finally {
      client.close();
    }
  }

  static Future<LocalAiCheckResult> checkLlm({
    required String endpoint,
    required String model,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final uri = _parseEndpoint(endpoint, 'Local AI LLM');
    final tagsUri = _ollamaTagsUri(uri);
    final expectedModel = model.trim();

    try {
      final response = await http.get(tagsUri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (expectedModel.isNotEmpty &&
            !_ollamaModelExists(response.body, expectedModel)) {
          throw AppException(
            'Local AI model "$expectedModel" was not found in Ollama. Pull it or change the model.',
          );
        }
        return LocalAiCheckResult(
          message: expectedModel.isEmpty
              ? 'Local AI LLM reachable'
              : 'Local AI LLM reachable ($expectedModel available)',
          statusCode: response.statusCode,
        );
      }
      throw AppException.fromHttp(
        response.statusCode,
        apiMessage: _apiMessage(response.body),
        fallback: 'Local AI LLM is not reachable',
      );
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw NetworkException(
        'Local AI LLM did not respond within ${_formatTimeout(timeout)}',
      );
    } catch (e) {
      throw NetworkException(
          'Local AI LLM is not reachable: ${_compactError(e)}');
    }
  }

  static Future<LocalAiCheckResult> checkWhisper({
    required String endpoint,
    required String model,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final uri = _parseEndpoint(endpoint, 'Local AI Whisper');
    final healthUri = _originUri(uri, '/health');
    try {
      final response = await http.get(healthUri).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return LocalAiCheckResult(
          message: 'Local AI Whisper reachable',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode != 404 && response.statusCode != 405) {
        throw AppException.fromHttp(
          response.statusCode,
          apiMessage: _apiMessage(response.body),
          fallback: 'Local AI Whisper health check failed',
        );
      }
      return await checkHttpReachable(
        endpoint: endpoint,
        label: 'Local AI Whisper',
        timeout: timeout,
      );
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw NetworkException(
        'Local AI Whisper did not respond within ${_formatTimeout(timeout)}',
      );
    } catch (e) {
      throw NetworkException(
          'Local AI Whisper is not reachable: ${_compactError(e)}');
    }
  }

  static Uri _parseEndpoint(String endpoint, String label) {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme.isEmpty ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw AppException('$label URL is invalid.');
    }
    return uri;
  }

  static Uri _originUri(Uri uri, String path) {
    return uri.replace(path: path, query: null, fragment: null);
  }

  static Uri _ollamaTagsUri(Uri uri) {
    return _originUri(uri, '/api/tags');
  }

  static bool _ollamaModelExists(String body, String expectedModel) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) return false;
      final models = decoded['models'];
      if (models is! List) return false;
      for (final item in models) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        final model = item['model']?.toString() ?? '';
        if (name == expectedModel || model == expectedModel) return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  static String? _apiMessage(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        final message = decoded['message'];
        if (message is String) return message;
      }
    } catch (_) {}
    return null;
  }

  static String _compactError(Object error) {
    final text = error.toString().replaceAll('\n', ' ').trim();
    return text.length > 160 ? '${text.substring(0, 160)}...' : text;
  }

  static String _formatTimeout(Duration timeout) {
    final ms = timeout.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    final seconds = ms / 1000;
    return '${seconds.toStringAsFixed(seconds.truncateToDouble() == seconds ? 0 : 1)}s';
  }
}
