import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/local_ai_response_parser.dart';
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
    Duration timeout = const Duration(seconds: 4),
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
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = _parseEndpoint(endpoint, 'Local AI LLM');
    final headers = {
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model.trim().isEmpty ? 'qwen2.5:3b' : model.trim(),
      'stream': false,
      'options': {
        'num_predict': 8,
        'temperature': 0,
      },
      'messages': [
        {'role': 'user', 'content': 'Reply with exactly: ok'},
      ],
    });

    try {
      final response =
          await http.post(uri, headers: headers, body: body).timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final text = LocalAiResponseParser.ollamaMessageContent(response.body);
        return LocalAiCheckResult(
          message: text.trim().isEmpty
              ? 'Local AI LLM reachable'
              : 'Local AI LLM reachable',
          statusCode: response.statusCode,
        );
      }
      throw AppException.fromHttp(
        response.statusCode,
        apiMessage: _apiMessage(response.body),
        fallback: 'Local AI LLM test failed',
      );
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const NetworkException('Local AI LLM test timed out');
    } catch (e) {
      throw NetworkException(
          'Local AI LLM is not reachable: ${_compactError(e)}');
    }
  }

  static Future<LocalAiCheckResult> checkWhisper({
    required String endpoint,
    required String model,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final uri = _parseEndpoint(endpoint, 'Local AI Whisper');
    final request = http.MultipartRequest('POST', uri);
    request.fields['model'] = model.trim().isEmpty ? 'whisper-1' : model.trim();
    request.fields['response_format'] = 'json';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      _silentWav(),
      filename: 'echoscribe-local-ai-test.wav',
    ));

    try {
      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          LocalAiResponseParser.whisperText(response.body);
        } on EmptyResultException {
          // Silence can legitimately transcribe to empty text; the endpoint is usable.
        }
        return LocalAiCheckResult(
          message: 'Local AI Whisper reachable',
          statusCode: response.statusCode,
        );
      }
      throw AppException.fromHttp(
        response.statusCode,
        apiMessage: _apiMessage(response.body),
        fallback: 'Local AI Whisper test failed',
      );
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const NetworkException('Local AI Whisper test timed out');
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

  static Uint8List _silentWav() {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    const samples = sampleRate ~/ 4;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    const dataSize = samples * blockAlign;
    const fileSizeMinus8 = 36 + dataSize;

    final bytes = Uint8List(44 + dataSize);
    final data = ByteData.view(bytes.buffer);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, fileSizeMinus8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    return bytes;
  }
}
