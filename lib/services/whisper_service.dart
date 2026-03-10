import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:echoscribe/utils/cross_file_reader.dart';
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/app_exception.dart';

class WhisperService {
  static const String endpoint = 'https://api.openai.com/v1/audio/transcriptions';

  static const Set<String> _allowedExts = {
    'flac', 'm4a', 'mp3', 'mp4', 'mpeg', 'mpga', 'oga', 'ogg', 'wav', 'webm'
  };

  String _patchFilename(String original) {
    if (original.isEmpty) return 'audio.webm';
    final lower = original.toLowerCase();
    // Map .opus -> .ogg explicitly
    if (lower.endsWith('.opus')) {
      return original.replaceAll(RegExp(r'\.opus$'), '.ogg');
    }
    // If no extension or unsupported, force a safe one
    final dot = lower.lastIndexOf('.');
    final ext = (dot >= 0 && dot < lower.length - 1) ? lower.substring(dot + 1) : '';
    if (ext.isEmpty || !_allowedExts.contains(ext)) {
      // Keep base name if present
      final base = dot > 0 ? original.substring(0, dot) : (original.isNotEmpty ? original : 'audio');
      return '$base.webm';
    }
    return original;
  }

  // Web-friendly API: pass a file path (mobile/desktop) OR raw bytes with a filename.
  // If language is null or 'auto', Whisper will auto-detect the spoken language.
  Future<String> transcribe({
    required String apiKey,
    String? filePath,
    List<int>? fileBytes,
    String fileName = 'audio.m4a',
    String model = AiModelConfig.openAiTranscriptionFast,
    String? language,
  }) async {
    if ((filePath == null || filePath.isEmpty) && (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception('No audio file provided');
    }

    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = model;
    request.fields['response_format'] = 'json';
    if (language != null && language != 'auto' && language.trim().isNotEmpty) {
      request.fields['language'] = language;
    }

    // Attach the audio file. Robustly normalize filename to a supported extension.
    int? audioBytesLen;
    String? audioFileName;
    if (fileBytes != null && fileBytes.isNotEmpty) {
      final patchedName = _patchFilename(fileName);
      audioBytesLen = fileBytes.length;
      audioFileName = patchedName;
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: patchedName));
    } else if (filePath != null && filePath.isNotEmpty) {
      // Read bytes cross-platform (IO and Web)
      final bytes = await readAllBytesCross(filePath);
      audioBytesLen = bytes.length;
      // Try to infer a filename from the path; blob: or content: URIs might not have an extension
      final rawName = filePath.split('/').isNotEmpty ? filePath.split('/').last : 'audio';
      final inferredName = _patchFilename(rawName);
      audioFileName = inferredName;
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: inferredName));
    }

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: audioBytesLen, note: 'OpenAI Whisper');
    DebugConsole.logApiRequestMultipart(
      method: 'POST',
      url: uri,
      headers: request.headers,
      fields: request.fields,
      files: [
        {
          'field': 'file',
          'filename': audioFileName ?? 'audio',
          'length': audioBytesLen ?? 0,
          'contentType': 'auto',
        }
      ],
    );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    sw.stop();
    DebugConsole.logApiEnd(status: response.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: response.bodyBytes.length);
    DebugConsole.logApiResponse(status: response.statusCode, headers: response.headers, body: response.body, title: 'API response (Whisper)');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final Map<String, dynamic> data = json.decode(response.body) as Map<String, dynamic>;
      final String text = (data['text'] ?? '').toString();
      if (text.isEmpty) {
        throw const EmptyResultException('Transcription returned empty text');
      }
      return text;
    } else {
      String? apiMessage;
      try {
        final Map<String, dynamic> err = json.decode(response.body) as Map<String, dynamic>;
        if (err['error'] is Map && err['error']['message'] is String) {
          apiMessage = err['error']['message'] as String;
        }
      } catch (_) {}
      throw AppException.fromHttp(response.statusCode, apiMessage: apiMessage, fallback: 'Transcription failed');
    }
  }
}
