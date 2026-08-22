import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/debug_console.dart';

class XaiSpeechService {
  static const String endpoint = 'https://api.x.ai/v1/stt';

  static const Set<String> _allowedExts = {
    'm4a',
    'mp3',
    'wav',
    'webm',
    'ogg',
    'oga',
    'opus',
  };

  String _patchFilename(String original) {
    if (original.isEmpty) return 'audio.m4a';
    final lower = original.toLowerCase();
    final dot = lower.lastIndexOf('.');
    final ext =
        (dot >= 0 && dot < lower.length - 1) ? lower.substring(dot + 1) : '';
    if (ext.isEmpty || !_allowedExts.contains(ext)) {
      final base = dot > 0 ? original.substring(0, dot) : original;
      return '$base.m4a';
    }
    return original;
  }

  Future<String> transcribe({
    required String apiKey,
    String? filePath,
    List<int>? fileBytes,
    String fileName = 'audio.m4a',
  }) async {
    if ((filePath == null || filePath.isEmpty) &&
        (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception('No audio file provided');
    }

    final bytes = fileBytes ?? await File(filePath!).readAsBytes();
    final patchedName = _patchFilename(fileName);
    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['format'] = 'false';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: patchedName),
    );

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: bytes.length,
      note: 'xAI STT',
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
          'contentType': 'auto',
        }
      ],
    );

    final streamed = await request.send();
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
      title: 'API response (xAI STT)',
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        throw const EmptyResultException('Transcription returned empty text');
      }
      return text;
    }

    String? apiMessage;
    try {
      final err = json.decode(response.body) as Map<String, dynamic>;
      final msg = err['error']?['message'] ?? err['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(response.statusCode,
        apiMessage: apiMessage, fallback: 'xAI transcription failed');
  }
}
