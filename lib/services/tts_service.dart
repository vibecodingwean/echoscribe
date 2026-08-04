import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';

import 'package:echoscribe/config/prompts.dart';

class TtsService {
  final http.Client _client;

  TtsService({http.Client? client}) : _client = client ?? http.Client();

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
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'OpenAI TTS');
    final res = await _client.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }

    // Try to extract error message
    String reason = 'OpenAI TTS failed (${res.statusCode})';
    try {
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'Gemini TTS');
    // Keep request body logging out to prevent panel spam; rely on concise lines
    final res = await _client.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // streamGenerateContent returns multiple JSON chunks. Concatenate every
      // inline audio block in response order before adding the WAV header.
      final bodyStr = utf8.decode(res.bodyBytes);
      List<int>? pcmBytes;
      // Try strict JSON first
      try {
        pcmBytes = _extractInlineAudioBytes(json.decode(bodyStr));
      } catch (_) {
        // Fallback for newline-delimited/otherwise non-standard streaming JSON.
        final reg = RegExp(r'"inlineData"\s*:\s*\{[^}]*"data"\s*:\s*"([^"]+)"',
            multiLine: true);
        final matches = reg.allMatches(bodyStr);
        final chunks = <int>[];
        for (final match in matches) {
          final encoded = match.group(1);
          if (encoded != null && encoded.isNotEmpty) {
            chunks.addAll(base64.decode(encoded));
          }
        }
        if (chunks.isNotEmpty) pcmBytes = chunks;
      }
      if (pcmBytes == null || pcmBytes.isEmpty) {
        debugPrint(
            'Gemini TTS: inlineData not found; response length=${bodyStr.length}');
        throw Exception('No audio data in Gemini response');
      }
      final wav = _addWavHeader(pcmBytes,
          sampleRate: 24000, numChannels: 1, bitsPerSample: 16);
      return Uint8List.fromList(wav);
    }

    String reason = 'Gemini TTS failed (${res.statusCode})';
    try {
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg is String && msg.isNotEmpty) reason = msg;
    } catch (_) {}
    throw Exception(reason);
  }

  // xAI TTS: returns MP3 bytes (beta endpoint)
  Future<Uint8List> generateSpeechXai({
    required String apiKey,
    required String text,
    String voice = 'eve',
    String language = 'en',
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
      'voice_id': voice.toLowerCase(),
      'language': language,
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'xAI TTS');
    final res = await _client.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }

    String reason = 'xAI TTS failed (${res.statusCode})';
    try {
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = data['error']?['message'];
      if (msg is String && msg.isNotEmpty) reason = msg;
    } catch (_) {}
    throw Exception(reason);
  }

  // ElevenLabs TTS: returns MP3 bytes.
  Future<Uint8List> generateSpeechElevenLabs({
    required String apiKey,
    required String text,
    String model = AiModelConfig.elevenLabsTts,
    String voiceId = AiModelConfig.elevenLabsTtsVoice,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);

    final uri = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/${Uri.encodeComponent(voiceId)}',
    ).replace(queryParameters: const {'output_format': 'mp3_44100_128'});
    final headers = {
      'xi-api-key': apiKey,
      'accept': 'audio/mpeg',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'text': trimmed,
      'model_id': model,
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'ElevenLabs TTS',
    );
    final res = await _client.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return Uint8List.fromList(res.bodyBytes);
    }

    String reason = 'ElevenLabs TTS failed (${res.statusCode})';
    try {
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final detail = data['detail'];
      if (detail is Map<String, dynamic>) {
        final message = detail['message'];
        if (message is String && message.isNotEmpty) reason = message;
      } else if (detail is List) {
        final messages = detail
            .whereType<Map>()
            .map((entry) => entry['msg'])
            .whereType<String>()
            .where((message) => message.isNotEmpty)
            .toList();
        if (messages.isNotEmpty) reason = messages.join('; ');
      } else if (detail is String && detail.isNotEmpty) {
        reason = detail;
      }
    } catch (_) {}
    throw Exception(reason);
  }

  // Build a minimal WAV header for PCM L16 data
  List<int> _addWavHeader(
    List<int> pcmData, {
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
  List<int> _le32(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  List<int>? _extractInlineAudioBytes(dynamic root) {
    final chunks = <int>[];

    void visit(dynamic node) {
      if (node is Map<String, dynamic>) {
        final inline = node['inlineData'] ?? node['inline_data'];
        if (inline is Map<String, dynamic>) {
          final data = inline['data'];
          if (data is String && data.isNotEmpty) {
            chunks.addAll(base64.decode(data));
          }
        }
        for (final value in node.values) {
          visit(value);
        }
      } else if (node is List<dynamic>) {
        for (final value in node) {
          visit(value);
        }
      }
    }

    visit(root);
    return chunks.isEmpty ? null : chunks;
  }
}
