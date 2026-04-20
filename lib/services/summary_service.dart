import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/services/anthropic_service.dart';
import 'package:echoscribe/models/app_exception.dart';

class SummaryService {
  String _summarySystemPrompt(String langHint) {
    return 'You are a precise summarizer. Follow the language rule strictly.\n'
        '$langHint\n'
        'If no explicit target language is given, preserve the input language exactly.\n'
        'Output only the summary, with no preface or labels.';
  }

  String _languageDirective(String code) {
    // If a manual target is set, instruct explicit language; otherwise mirror input language.
    if (code.isNotEmpty && code != 'auto') {
      final name = _languageName(code);
      return 'Language rule: Output MUST be in $name ("$code"). Do not use any other language.';
    }
    return 'Language rule: Detect the input language and write the summary strictly in that same language. If the input is German, output German; if Spanish, output Spanish. Never switch languages.';
  }

  String _languageName(String code) {
    const map = {
      'en': 'English',
      'zh': 'Chinese (Simplified)',
      'hi': 'Hindi',
      'es': 'Spanish',
      'fr': 'French',
      'ar': 'Arabic',
      'bn': 'Bengali',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ur': 'Urdu',
      'id': 'Indonesian',
      'de': 'German',
      'ja': 'Japanese',
      'sw': 'Swahili',
      'mr': 'Marathi',
      'te': 'Telugu',
      'tr': 'Turkish',
      'ta': 'Tamil',
      'vi': 'Vietnamese',
      'ko': 'Korean',
    };
    return map[code] ?? code;
  }

  String _buildPrompt(
      {required String basePrompt,
      required String langHint,
      required String text}) {
    return '$basePrompt\n\n$langHint\n\nText:\n$text';
  }

  // OpenAI summary via Chat Completions
  Future<String> summarizeOpenAI({
    required String apiKey,
    required String text,
    String model = AiModelConfig.openAiSummaryFast,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt =
        _buildPrompt(basePrompt: basePrompt, langHint: langHint, text: trimmed);

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'messages': [
        {
          'role': 'system',
          'content': _summarySystemPrompt(langHint),
        },
        {
          'role': 'user',
          'content': prompt,
        }
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'OpenAI summary');
    DebugConsole.logApiRequest(
        method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(
        status: res.statusCode,
        headers: res.headers,
        body: res.body,
        title: 'API response (OpenAI summary)');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      final content = choices != null && choices.isNotEmpty
          ? (choices.first['message']?['content'] ?? '').toString()
          : '';
      if (content.trim().isEmpty) {
        throw const EmptyResultException('Empty summary result');
      }
      return content.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode,
        apiMessage: apiMessage, fallback: 'Summary failed');
  }

  // Gemini summary via generateContent (with URL-safe fallback)
  Future<String> summarizeGemini({
    required String apiKey,
    required String text,
    String model = AiModelConfig.geminiSummaryFast,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    bool looksLikeUrl(String s) {
      final t = s.trim();
      if (t.isEmpty) return false;
      if (t.contains(' ') || t.contains('\n') || t.contains('\t')) return false;
      final uri = Uri.tryParse(t);
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          (uri.host.isNotEmpty);
    }

    Future<String> callGemini(String prompt) async {
      final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
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
      DebugConsole.logApiStart(
          method: 'POST',
          url: uri,
          requestBytes: utf8.encode(body).length,
          note: 'Gemini summary');
      DebugConsole.logApiRequest(
          method: 'POST', url: uri, headers: headers, body: body);
      final res = await http.post(uri, headers: headers, body: body);
      sw.stop();
      DebugConsole.logApiEnd(
          status: res.statusCode,
          elapsedMs: sw.elapsedMilliseconds,
          responseBytes: res.bodyBytes.length);
      DebugConsole.logApiResponse(
          status: res.statusCode,
          headers: res.headers,
          body: res.body,
          title: 'API response (Gemini summary)');
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        final parts = (candidates != null && candidates.isNotEmpty)
            ? (candidates.first['content']?['parts'] as List<dynamic>?)
            : const [];
        final out = (parts != null && parts.isNotEmpty)
            ? (parts.first['text'] ?? '').toString()
            : '';
        if (out.trim().isEmpty) {
          throw const EmptyResultException('Empty summary result');
        }
        return out.trim();
      }
      String? apiMessage;
      try {
        final err = json.decode(res.body) as Map<String, dynamic>;
        final msg = err['error']?['message'];
        if (msg is String && msg.isNotEmpty) apiMessage = msg;
      } catch (_) {}
      throw AppException.fromHttp(res.statusCode,
          apiMessage: apiMessage, fallback: 'Gemini summary failed');
    }

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt =
        _buildPrompt(basePrompt: basePrompt, langHint: langHint, text: trimmed);

    try {
      return await callGemini(prompt);
    } catch (e) {
      // If the input is a URL, retry with a URL-safe best-effort prompt (no external fetching implied)
      if (looksLikeUrl(trimmed)) {
        final urlOnlyPrompt = _buildPrompt(
          basePrompt: kDefaultUrlSummaryPrompt,
          langHint: langHint,
          text: trimmed,
        );
        try {
          return await callGemini(urlOnlyPrompt);
        } catch (_) {
          // fall through
        }
      }
      rethrow;
    }
  }

  // xAI (Grok) summary via OpenAI-compatible Chat Completions
  Future<String> summarizeXai({
    required String apiKey,
    required String text,
    String model = AiModelConfig.xaiSummaryFast,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt =
        _buildPrompt(basePrompt: basePrompt, langHint: langHint, text: trimmed);

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
          'content': _summarySystemPrompt(langHint),
        },
        {
          'role': 'user',
          'content': prompt,
        }
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'xAI summary');
    DebugConsole.logApiRequest(
        method: 'POST', url: uri, headers: headers, body: body);
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(
        status: res.statusCode,
        headers: res.headers,
        body: res.body,
        title: 'API response (xAI summary)');
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      final content = choices != null && choices.isNotEmpty
          ? (choices.first['message']?['content'] ?? '').toString()
          : '';
      if (content.trim().isEmpty) {
        throw const EmptyResultException('Empty summary result');
      }
      return content.trim();
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode,
        apiMessage: apiMessage, fallback: 'xAI summary failed');
  }

  Future<String> summarizeAnthropic({
    required String apiKey,
    required String text,
    String model = AiModelConfig.anthropicSummaryFast,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt =
        _buildPrompt(basePrompt: basePrompt, langHint: langHint, text: trimmed);

    final anthropic = AnthropicService();
    return await anthropic.generateText(
      apiKey: apiKey,
      model: model,
      prompt: prompt,
      systemPrompt:
          'You are a precise summarizer. Follow the language rule strictly. Output only the summary, no preface or labels.',
    );
  }
}
