import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/provider_consent_service.dart';

import 'package:echoscribe/config/prompts.dart';

class TtsService {
  static const _shortOpenAiMaxCharacters = 200;

  final http.Client _client;
  final ProviderConsentService? _consent;
  final Duration requestTimeout;
  final Duration shortOpenAiRequestTimeout;

  TtsService({
    http.Client? client,
    ProviderConsentService? consent,
    this.requestTimeout = const Duration(seconds: 120),
    this.shortOpenAiRequestTimeout = const Duration(seconds: 15),
  })  : _client = client ?? http.Client(),
        _consent = consent;

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
    Duration? timeout,
  }) async {
    final effectiveTimeout =
        timeout != null && timeout < requestTimeout ? timeout : requestTimeout;
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      'POST',
      uri,
      abortTrigger: abort.future,
    )
      ..headers.addAll(headers)
      ..body = body;
    try {
      return await (() async {
        final response = await _client.send(request);
        return http.Response.fromStream(response);
      })()
          .timeout(effectiveTimeout);
    } on TimeoutException {
      abort.complete();
      throw const NetworkException(
          'Speech service did not respond in time. Please try again.');
    }
  }

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
    await _consent?.ensure(AiProviderType.openai,
        dataType: 'text from a transcript or summary',
        purpose: 'speech generation');

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
    final res = await _post(
      uri,
      headers: headers,
      body: body,
      timeout: trimmed.runes.length <= _shortOpenAiMaxCharacters
          ? shortOpenAiRequestTimeout
          : null,
    );
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

  Future<Uint8List> generateSpeechGemini({
    required String apiKey,
    required String text,
    String model = AiModelConfig.geminiTts,
    String voice = 'Zephyr',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);
    await _consent?.ensure(AiProviderType.gemini,
        dataType: 'text from a transcript or summary',
        purpose: 'speech generation');

    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/interactions');
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };
    final body = json.encode({
      'model': model,
      'store': false,
      'input': [
        {
          'type': 'user_input',
          'content': [
            {'type': 'text', 'text': trimmed}
          ]
        }
      ],
      'response_format': {'type': 'audio'},
      'generation_config': {
        'speech_config': [
          {'voice': voice}
        ]
      }
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'Gemini TTS');
    // Keep request body logging out to prevent panel spam; rely on concise lines
    final res = await _post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final payload =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final steps = payload['steps'] as List<dynamic>? ?? [];
      for (final step in steps.reversed) {
        if (step is! Map<String, dynamic> || step['type'] != 'model_output') {
          continue;
        }
        final content = step['content'] as List<dynamic>? ?? [];
        for (final block in content.reversed) {
          if (block is Map<String, dynamic> && block['type'] == 'audio') {
            final encoded = block['data'];
            if (encoded is String && encoded.isNotEmpty) {
              return base64.decode(encoded);
            }
          }
        }
      }
      throw Exception('No audio data in Gemini response');
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
    await _consent?.ensure(AiProviderType.xai,
        dataType: 'text from a transcript or summary',
        purpose: 'speech generation');

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
    final res = await _post(uri, headers: headers, body: body);
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
    String? model,
    String voiceId = '',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Uint8List(0);
    final customVoiceId = voiceId.trim();
    final usesTutorialVoice = customVoiceId.isEmpty;
    final resolvedVoiceId =
        usesTutorialVoice ? AiModelConfig.elevenLabsTtsVoice : customVoiceId;
    await _consent?.ensure(AiProviderType.elevenLabs,
        dataType: 'text from a transcript or summary',
        purpose: 'speech generation');

    final uri = Uri.parse(
      'https://api.elevenlabs.io/v1/text-to-speech/${Uri.encodeComponent(resolvedVoiceId)}',
    ).replace(queryParameters: const {'output_format': 'mp3_44100_128'});
    final headers = {
      'xi-api-key': apiKey,
      'accept': 'audio/mpeg',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'text': trimmed,
      'model_id': model ??
          (usesTutorialVoice
              ? AiModelConfig.elevenLabsTts
              : AiModelConfig.elevenLabsCustomTts),
      if (usesTutorialVoice && model == null)
        'voice_settings': {
          'stability': 0.45,
          'similarity_boost': 0.8,
          'style': 0,
          'use_speaker_boost': true,
        },
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'ElevenLabs TTS',
    );
    final res = await _post(uri, headers: headers, body: body);
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
    if (res.statusCode == 404 ||
        ((res.statusCode == 403 || res.statusCode == 422) &&
            reason.toLowerCase().contains('voice'))) {
      throw AppException(
        '$reason. This Voice ID may not be available to your ElevenLabs account. '
        'Add it from the Voice Library or choose a different TTS Voice ID in Settings.',
      );
    }
    throw Exception(reason);
  }
}
