import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/anthropic_service.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/app_exception.dart';

class TranslationService {
  // Master translate method that routes to the correct provider
  Future<String> translate({
    required AiProviderType provider,
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required bool pro,
  }) async {
    switch (provider) {
      case AiProviderType.gemini:
        return await translateGemini(
          apiKey: apiKey, text: text, targetLanguageCode: targetLanguageCode,
          model: AiModelConfig.geminiTranslation(pro: pro),
        );
      case AiProviderType.anthropic:
        return await translateAnthropic(
          apiKey: apiKey, text: text, targetLanguageCode: targetLanguageCode,
          model: AiModelConfig.anthropicTranslation(pro: pro),
        );
      case AiProviderType.xai:
        return await translateXai(
          apiKey: apiKey, text: text, targetLanguageCode: targetLanguageCode,
          model: AiModelConfig.xaiTranslation(pro: pro),
        );
      case AiProviderType.openai:
        return await translateOpenAI(
          apiKey: apiKey, text: text, targetLanguageCode: targetLanguageCode,
          model: AiModelConfig.openAiTranslation(pro: pro),
        );
    }
  }

  // Uses OpenAI Chat Completions to translate text to a target language.
  Future<String> translateOpenAI({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    String model = AiModelConfig.openAiTranslationFast,
  }) async {
    if (text.trim().isEmpty) return text;

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    // Simple, direct translation prompt. We ask for only the translated text.
    final body = json.encode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a precise translation engine. Output only the translated text without additional commentary.'
        },
        {
          'role': 'user',
          'content': 'Translate the following text to ${_codeToHuman(targetLanguageCode)}. Keep tone and meaning. Text:\n\n$text'
        }
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'OpenAI translate');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (OpenAI translate)');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      final content = choices != null && choices.isNotEmpty
          ? (choices.first['message']?['content'] ?? '').toString()
          : '';
      if (content.trim().isEmpty) {
        throw const EmptyResultException('Empty translation result');
      }
      return content.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'Translation failed');
  }

  Future<String> translateGemini({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    String model = AiModelConfig.geminiTranslationFast,
  }) async {
    if (text.trim().isEmpty) return text;

    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
    final headers = {'Content-Type': 'application/json'};
    final body = json.encode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Translate the following text to ${_codeToHuman(targetLanguageCode)}. Output only the translated text. Text:\n\n$text'}
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
    throw AppException.fromHttp(res.statusCode, fallback: 'Gemini translation failed');
  }

  // xAI (Grok) translation via OpenAI-compatible Chat Completions
  Future<String> translateXai({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    String model = AiModelConfig.xaiTranslationFast,
  }) async {
    if (text.trim().isEmpty) return text;

    final uri = Uri.parse('https://api.x.ai/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': 'You are a precise translation engine. Output only the translated text without additional commentary.'
        },
        {
          'role': 'user',
          'content': 'Translate the following text to ${_codeToHuman(targetLanguageCode)}. Keep tone and meaning. Text:\n\n$text'
        }
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'xAI translate');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (xAI translate)');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      final content = choices != null && choices.isNotEmpty
          ? (choices.first['message']?['content'] ?? '').toString()
          : '';
      if (content.trim().isEmpty) throw const EmptyResultException('Empty translation result');
      return content.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'xAI translation failed');
  }

  Future<String> translateAnthropic({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    String model = AiModelConfig.anthropicTranslationFast,
  }) async {
    if (text.trim().isEmpty) return text;

    final anthropic = AnthropicService();
    return await anthropic.generateText(
      apiKey: apiKey,
      model: model,
      prompt: 'Translate the following text to ${_codeToHuman(targetLanguageCode)}. Keep tone and meaning. Text:\n\n$text',
      systemPrompt: 'You are a precise translation engine. Output only the translated text without additional commentary.',
    );
  }

  String _codeToHuman(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'zh':
        return 'Chinese (Simplified)';
      case 'hi':
        return 'Hindi';
      case 'es':
        return 'Spanish';
      case 'fr':
        return 'French';
      case 'ar':
        return 'Arabic';
      case 'bn':
        return 'Bengali';
      case 'pt':
        return 'Portuguese';
      case 'ru':
        return 'Russian';
      case 'ur':
        return 'Urdu';
      case 'id':
        return 'Indonesian';
      case 'de':
        return 'German';
      case 'ja':
        return 'Japanese';
      case 'sw':
        return 'Swahili';
      case 'mr':
        return 'Marathi';
      case 'te':
        return 'Telugu';
      case 'tr':
        return 'Turkish';
      case 'ta':
        return 'Tamil';
      case 'vi':
        return 'Vietnamese';
      case 'ko':
        return 'Korean';
      default:
        return code;
    }
  }
}
