import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';

import 'package:echoscribe/config/prompts.dart';

class TtsService {
  // OpenAI TTS: returns MP3 bytes
  Future<Uint8List> generateSpeechOpenAI({
    required String apiKey,
    required String text,
    String model = AiModelConfig.openAiTts,
    String voice = 'alloy',
    String responseFormat = 'mp3',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);

    final uri = Uri.parse('https://api.openai.com/v1/audio/speech');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'input': trimmed,
      'voice': voice,
      'response_format': responseFormat,
    });

    final sw = Stopwatch()..start();
    // Keep console noise minimal; use concise start/end log lines
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'OpenAI TTS');
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }

    // Try to extract error message
    String reason = 'OpenAI TTS failed (${res.statusCode})';
    try {
      final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg is String && msg.isNotEmpty) reason = msg;
    } catch (_) {
      // ignore
    }
    throw Exception(reason);
  }

  // Gemini TTS streaming endpoint: returns WAV bytes (44-byte header + PCM data)
  Future<Uint8List> generateSpeechGemini({
    required String apiKey,
    required String text,
    String model = AiModelConfig.geminiTts,
    String voice = 'Zephyr',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': trimmed}
          ]
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {
              'voiceName': voice,
            }
          }
        }
      }
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'Gemini TTS');
    // Keep request body logging out to prevent panel spam; rely on concise lines
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // The response may be a stream of JSON objects; attempt robust extraction of the first inlineData.data
      final bodyStr = utf8.decode(res.bodyBytes);
      String? b64;
      // Try strict JSON first
      try {
        final data = json.decode(bodyStr) as Map<String, dynamic>;
        b64 = _extractInlineDataBase64(data);
      } catch (_) {
        // Fallback: search for inlineData.data via regex across a streaming body
        final reg = RegExp(r'"inlineData"\s*:\s*\{[^}]*"data"\s*:\s*"([^"]+)"', multiLine: true);
        final m = reg.firstMatch(bodyStr);
        if (m != null && m.groupCount >= 1) {
          b64 = m.group(1);
        }
      }
      if (b64 == null || b64.isEmpty) {
        debugPrint('Gemini TTS: inlineData not found; response length=${bodyStr.length}');
        throw Exception('No audio data in Gemini response');
      }
      final pcmBytes = base64.decode(b64);
      final wav = _addWavHeader(pcmBytes, sampleRate: 24000, numChannels: 1, bitsPerSample: 16);
      return Uint8List.fromList(wav);
    }

    String reason = 'Gemini TTS failed (${res.statusCode})';
    try {
      final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg is String && msg.isNotEmpty) reason = msg;
    } catch (_) {}
    throw Exception(reason);
  }

  // xAI TTS: returns MP3 bytes (beta endpoint)
  Future<Uint8List> generateSpeechXai({
    required String apiKey,
    required String text,
    String voice = 'Eve',
    String responseFormat = 'mp3',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);

    final uri = Uri.parse('https://api.x.ai/v1/tts');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'text': trimmed,
      'voice': voice,
      'response_format': responseFormat,
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'xAI TTS');
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }

    String reason = 'xAI TTS failed (${res.statusCode})';
    try {
      final data = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg is String && msg.isNotEmpty) reason = msg;
    } catch (_) {}
    throw Exception(reason);
  }

  // Build a minimal WAV header for PCM L16 data
  List<int> _addWavHeader(List<int> pcmData, {
    required int sampleRate,
    required int numChannels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    final chunkSize = 36 + dataSize;

    final bytes = BytesBuilder();
    void writeString(String s) => bytes.add(utf8.encode(s));
    void writeUint32(int v) => bytes.add(_le32(v));
    void writeUint16(int v) => bytes.add(_le16(v));

    writeString('RIFF');
    writeUint32(chunkSize);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16); // subchunk1 size for PCM
    writeUint16(1); // audio format PCM
    writeUint16(numChannels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataSize);
    bytes.add(pcmData);

    return bytes.takeBytes();
  }

  List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  List<int> _le32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  // Helper to traverse Gemini JSON structure for inlineData.data
  String? _extractInlineDataBase64(Map<String, dynamic> root) {
    try {
      final candidates = root['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      if (content == null) return null;
      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;
      final inline = parts.firstWhere(
        (p) => p is Map<String, dynamic> && p['inlineData'] != null,
        orElse: () => null,
      );
      if (inline is Map<String, dynamic>) {
        final data = (inline['inlineData'] as Map<String, dynamic>)['data'];
        if (data is String) return data;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
