import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/services/anthropic_service.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/local_ai_response_parser.dart';

class SummaryService {
  static const int _localAiMaxInputChars = 1200;
  static const int _localAiMaxOutputTokens = 180;
  static const Duration _localAiSummaryTimeout = Duration(seconds: 75);
  static const String _localAiSummaryPrompt =
      'Summarize the following content in 2-4 concise sentences. '
      'Use only facts present in the text. '
      'Do not add headings, labels, or meta commentary.';
  static const String _localAiFormattingRule =
      'For sectioned summaries, every heading MUST be formatted exactly as '
      '"## <emoji> <1-3 word title>". Never write a section heading without an emoji.';

  String _summarySystemPrompt(String langHint) {
    return 'You are a precise summarizer. Follow the language rule strictly.\n'
        '$langHint\n'
        'If no explicit target language is given, preserve the input language exactly.\n'
        'Output only the summary, with no preface or labels.';
  }

  String _languageDirective(String code) {
    // If a manual target is set, instruct explicit language; otherwise mirror input language.
    if (code.isNotEmpty && code != 'auto') {
      final name = targetLanguageName(code);
      return 'Language rule: Output MUST be in $name ("$code"). Do not use any other language.';
    }
    return 'Language rule: Detect the input language and write the summary strictly in that same language. If the input is German, output German; if Spanish, output Spanish. Never switch languages.';
  }

  String _buildPrompt({
    required String basePrompt,
    required String langHint,
    required String text,
  }) {
    return '$basePrompt\n\n$langHint\n\nText:\n$text';
  }

  // OpenAI summary via Chat Completions
  Future<String> summarizeOpenAI({
    required String apiKey,
    required String text,
    String model = AiModelConfig.openAiSummaryFast,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
    String? reasoningEffort = AiModelConfig.openAiReasoningEffortFast,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : _localAiSummaryPrompt;
    final prompt = _buildPrompt(
      basePrompt: basePrompt,
      langHint: langHint,
      text: trimmed,
    );

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': _summarySystemPrompt(langHint)},
        {'role': 'user', 'content': prompt},
      ],
    };
    if (reasoningEffort != null && reasoningEffort.trim().isNotEmpty) {
      payload['reasoning_effort'] = reasoningEffort.trim();
    }
    final body = json.encode(payload);

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'OpenAI summary',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      body: body,
    );
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (OpenAI summary)',
    );
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
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'Summary failed',
    );
  }

  Future<String> summarizeOllama({
    required String endpoint,
    required String text,
    String model = AiModelConfig.localAiLlmModel,
    String targetLanguageCode = 'auto',
    String? summaryPrompt,
  }) async {
    final trimmed = _limitLocalAiInput(text.trim());
    if (trimmed.isEmpty) return trimmed;
    if (endpoint.trim().isEmpty) {
      throw const AppException('Local AI LLM URL is not configured.');
    }

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    var prompt = _buildPrompt(
      basePrompt: basePrompt,
      langHint: langHint,
      text: trimmed,
    );
    prompt = '$_localAiFormattingRule\n\n$prompt';

    final uri = Uri.parse(endpoint.trim());
    final headers = {
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'stream': false,
      'think': false,
      'options': {
        'num_ctx': 2048,
        'num_predict': _localAiMaxOutputTokens,
        'temperature': 0.2,
      },
      'messages': [
        {
          'role': 'system',
          'content': '${_summarySystemPrompt(langHint)} $_localAiFormattingRule',
        },
        {'role': 'user', 'content': prompt},
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'Local AI summary',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      body: body,
    );
    late final http.Response res;
    try {
      res = await http
          .post(uri, headers: headers, body: body)
          .timeout(_localAiSummaryTimeout);
      sw.stop();
    } on TimeoutException {
      sw.stop();
      DebugConsole.logApiEnd(status: 0, elapsedMs: sw.elapsedMilliseconds);
      throw NetworkException(
        'Local AI summary timed out after ${_localAiSummaryTimeout.inSeconds}s. '
        'Use a smaller/faster local model or shorten the page content.',
      );
    }
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (Local AI summary)',
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return LocalAiResponseParser.ollamaMessageContent(res.body);
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'] ?? err['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'Local AI summary failed',
    );
  }

  String _limitLocalAiInput(String text) {
    if (text.length <= _localAiMaxInputChars) return text;
    DebugConsole.log(
      'Local AI summary input truncated from ${text.length} to '
      '$_localAiMaxInputChars chars',
    );
    return '${text.substring(0, _localAiMaxInputChars)}\n\n[Content truncated for Local AI performance.]';
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
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );
      final headers = {'Content-Type': 'application/json'};
      final body = json.encode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
      });
      final sw = Stopwatch()..start();
      DebugConsole.logApiStart(
        method: 'POST',
        url: uri,
        requestBytes: utf8.encode(body).length,
        note: 'Gemini summary',
      );
      DebugConsole.logApiRequest(
        method: 'POST',
        url: uri,
        headers: headers,
        body: body,
      );
      final res = await http.post(uri, headers: headers, body: body);
      sw.stop();
      DebugConsole.logApiEnd(
        status: res.statusCode,
        elapsedMs: sw.elapsedMilliseconds,
        responseBytes: res.bodyBytes.length,
      );
      DebugConsole.logApiResponse(
        status: res.statusCode,
        headers: res.headers,
        body: res.body,
        title: 'API response (Gemini summary)',
      );
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
      throw AppException.fromHttp(
        res.statusCode,
        apiMessage: apiMessage,
        fallback: 'Gemini summary failed',
      );
    }

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt = _buildPrompt(
      basePrompt: basePrompt,
      langHint: langHint,
      text: trimmed,
    );

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
    String? reasoningEffort,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final langHint = _languageDirective(targetLanguageCode);
    final basePrompt = summaryPrompt?.trim().isNotEmpty == true
        ? summaryPrompt!.trim()
        : kDefaultSummaryPrompt;
    final prompt = _buildPrompt(
      basePrompt: basePrompt,
      langHint: langHint,
      text: trimmed,
    );

    final uri = Uri.parse('https://api.x.ai/v1/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final payload = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': _summarySystemPrompt(langHint)},
        {'role': 'user', 'content': prompt},
      ],
    };
    if (reasoningEffort != null && reasoningEffort.trim().isNotEmpty) {
      payload['reasoning_effort'] = reasoningEffort.trim();
    }
    final body = json.encode(payload);

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(
      method: 'POST',
      url: uri,
      requestBytes: utf8.encode(body).length,
      note: 'xAI summary',
    );
    DebugConsole.logApiRequest(
      method: 'POST',
      url: uri,
      headers: headers,
      body: body,
    );
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    DebugConsole.logApiEnd(
      status: res.statusCode,
      elapsedMs: sw.elapsedMilliseconds,
      responseBytes: res.bodyBytes.length,
    );
    DebugConsole.logApiResponse(
      status: res.statusCode,
      headers: res.headers,
      body: res.body,
      title: 'API response (xAI summary)',
    );
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
    throw AppException.fromHttp(
      res.statusCode,
      apiMessage: apiMessage,
      fallback: 'xAI summary failed',
    );
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
    final prompt = _buildPrompt(
      basePrompt: basePrompt,
      langHint: langHint,
      text: trimmed,
    );

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
