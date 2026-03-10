import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:echoscribe/utils/cross_file_reader.dart';
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/app_exception.dart';

class GeminiService {
  static const String _uploadEndpoint = 'https://generativelanguage.googleapis.com/upload/v1beta/files';
  static const String _modelsEndpoint = 'https://generativelanguage.googleapis.com/v1beta/models';

  // Upload audio bytes as raw media (no base64) using the official upload endpoint,
  // then request transcription with Gemini. Works on web and mobile and supports >20MB.
  Future<String> transcribe({
    required String apiKey,
    String? filePath,
    List<int>? fileBytes,
    String fileName = 'audio.m4a',
    String mimeType = 'audio/m4a',
    String model = AiModelConfig.geminiTranscriptionFast,
  }) async {
    if ((filePath == null || filePath.isEmpty) && (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception('No audio file provided');
    }

    // Obtain bytes cross-platform
    final bytes = fileBytes ?? await readAllBytesCross(filePath!);

    // 1) Upload the file as raw bytes (no multipart, no base64)
    final fileObj = await _uploadFileRaw(apiKey: apiKey, fileName: fileName, mimeType: mimeType, bytes: bytes);

    // 2) Ask Gemini to transcribe the uploaded file
    final uri = Uri.parse('$_modelsEndpoint/$model:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': 'Transcribe the following audio accurately. Auto-detect the spoken language and return only the raw transcript text without any extra words.'
            },
            {
              'fileData': {
                'fileUri': fileObj['uri'],
                'mimeType': mimeType,
              }
            }
          ]
        }
      ]
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'Gemini generateContent');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (Gemini transcribe)');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw const EmptyResultException('No transcription candidates');
      }
      final parts = (candidates.first['content']?['parts'] as List<dynamic>?) ?? const [];
      final text = parts.isNotEmpty ? (parts.first['text'] ?? '').toString() : '';
      if (text.trim().isEmpty) {
        throw const EmptyResultException('Empty transcription result');
      }
      return text.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'Gemini transcription failed');
  }

  // Simple text translation using Gemini when OpenAI is not selected.
  Future<String> translateText({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    String model = AiModelConfig.geminiTranslationFast,
  }) async {
    if (text.trim().isEmpty) return text;
    final uri = Uri.parse('$_modelsEndpoint/$model:generateContent?key=$apiKey');
    final prompt = 'Translate the following text to $targetLanguageCode. Return only the translated text.\n\n$text';
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    });
    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'Gemini translate');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (Gemini translate)');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      final parts = (candidates != null && candidates.isNotEmpty)
          ? (candidates.first['content']?['parts'] as List<dynamic>?)
          : const [];
      final out = (parts != null && parts.isNotEmpty) ? (parts.first['text'] ?? '').toString() : '';
      if (out.trim().isEmpty) throw const EmptyResultException('Empty translation result');
      return out.trim();
    }
    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'Gemini translation failed');
  }

  Future<Map<String, dynamic>> _uploadFileRaw({
    required String apiKey,
    required String fileName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    final uri = Uri.parse('$_uploadEndpoint?key=$apiKey');

    final headers = {
      'Content-Type': mimeType,
      'X-Goog-Upload-Protocol': 'raw',
      'X-Goog-Upload-File-Name': fileName,
    };

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: bytes.length, note: 'Gemini file upload');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, binaryBytes: bytes.length);
    final res = await http.post(
      uri,
      headers: headers,
      body: bytes,
    );
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (Gemini upload)');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final root = json.decode(res.body) as Map<String, dynamic>;
      // Responses from upload API are usually wrapped like {"file": {...}}
      final file = (root['file'] is Map<String, dynamic>) ? (root['file'] as Map<String, dynamic>) : root;
      if (file['uri'] == null) {
        final name = file['name']?.toString(); // e.g., files/abc123
        if (name != null && name.isNotEmpty) {
          file['uri'] = 'https://generativelanguage.googleapis.com/v1beta/$name';
        }
      }
      return file;
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'File upload failed');
  }
}
