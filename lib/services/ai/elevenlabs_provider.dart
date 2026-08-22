import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/debug_console.dart';
import 'package:http/http.dart' as http;

/// ElevenLabs batch STT uses Scribe v2. Live mic stays on the realtime client.
/// Summary, translation, and image paths fail closed.
class ElevenLabsProvider implements AiProvider {
  ElevenLabsProvider({http.Client? client}) : _client = client ?? http.Client();

  static const String sttEndpoint =
      'https://api.elevenlabs.io/v1/speech-to-text';

  final http.Client _client;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) {
    throw const AppException('ElevenLabs does not support summaries.');
  }

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
    String? reasoningEffort,
  }) {
    throw const AppException(
      'ElevenLabs Realtime transcribes speech but does not translate it.',
    );
  }

  @override
  Future<String> transcribe({
    required String apiKey,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String model,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AuthException('Invalid API key');
    }
    if (filePath.trim().isEmpty) {
      throw Exception('No audio file provided');
    }

    final bytes = await File(filePath).readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('No audio file provided');
    }

    final patchedName = fileName.trim().isNotEmpty
        ? fileName.trim()
        : (filePath.split('/').isNotEmpty
            ? filePath.split('/').last
            : 'audio.wav');
    final modelId = model.trim().isEmpty
        ? AiModelConfig.elevenLabsTranscription
        : model.trim();
    final uri = Uri.parse(sttEndpoint);
    final request = http.MultipartRequest('POST', uri);
    request.headers['xi-api-key'] = apiKey.trim();
    request.fields['model_id'] = modelId;
    request.fields['tag_audio_events'] = 'false';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: patchedName),
    );

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: bytes.length,
      note: 'ElevenLabs STT',
    );
    DebugConsole.logApiRequestMultipart(
      method: 'POST',
      url: uri,
      headers: request.headers,
      fields: request.fields,
      files: [
        {
          'field': 'file',
          'filename': patchedName,
          'length': bytes.length,
          'contentType': mimeType.isEmpty ? 'auto' : mimeType,
        },
      ],
    );

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    sw.stop();
    DebugConsole.logApiEnd(
      status: response.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: response.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: response.statusCode,
      headers: response.headers,
      body: response.body,
      title: 'API response (ElevenLabs STT)',
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final payload = json.decode(response.body);
      if (payload is! Map<String, dynamic>) {
        throw const EmptyResultException('Transcription returned empty text');
      }
      final text = transcriptText(payload);
      if (text.isEmpty) {
        throw const EmptyResultException('Transcription returned empty text');
      }
      return text;
    }

    throw AppException.fromHttp(
      response.statusCode,
      apiMessage: _errorMessage(response.body),
      fallback: 'Transcription failed',
    );
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) {
    throw const AppException(
      'ElevenLabs does not support image generation.',
    );
  }

  static String transcriptText(Map<String, dynamic> payload) {
    final text = (payload['text'] ?? '').toString().trim();
    if (text.isNotEmpty) return text;
    final transcripts = payload['transcripts'];
    if (transcripts is List) {
      return transcripts
          .whereType<Map>()
          .map((item) => (item['text'] ?? '').toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    if (transcripts is Map) {
      return transcripts.values
          .whereType<Map>()
          .map((item) => (item['text'] ?? '').toString().trim())
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    return '';
  }

  static String? _errorMessage(String body) {
    try {
      final err = json.decode(body);
      if (err is! Map) return null;
      final detail = err['detail'];
      if (detail is Map) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) return message;
      } else if (detail is List) {
        final messages = detail
            .whereType<Map>()
            .map((entry) => entry['msg'])
            .whereType<String>()
            .where((message) => message.isNotEmpty)
            .toList();
        if (messages.isNotEmpty) return messages.join('; ');
      } else if (detail is String && detail.isNotEmpty) {
        return detail;
      }
      final message = err['message'];
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {}
    return null;
  }
}
