import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/models/app_exception.dart';

class AnthropicService {
  Future<String> generateText({
    required String apiKey,
    required String model,
    required String prompt,
    String systemPrompt = 'You are a precise assistant. Output only the requested content.',
    int maxTokens = 1024,
  }) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    };
    final body = json.encode({
      'model': model,
      'max_tokens': maxTokens,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
    });

    final sw = Stopwatch()..start();
    DebugConsole.logApiStart(method: 'POST', url: uri, requestBytes: utf8.encode(body).length, note: 'Anthropic text generation');
    DebugConsole.logApiRequest(method: 'POST', url: uri, headers: headers, body: body);
    
    final res = await http.post(uri, headers: headers, body: body);
    sw.stop();
    
    DebugConsole.logApiEnd(status: res.statusCode, elapsedMs: sw.elapsedMilliseconds, responseBytes: res.bodyBytes.length);
    DebugConsole.logApiResponse(status: res.statusCode, headers: res.headers, body: res.body, title: 'API response (Anthropic)');

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final content = data['content'] as List<dynamic>?;
      if (content != null && content.isNotEmpty) {
        return (content.first['text'] ?? '').toString().trim();
      }
      throw const EmptyResultException('Empty response from Claude');
    }

    String? apiMessage;
    try {
      final err = json.decode(res.body) as Map<String, dynamic>;
      final msg = err['error']?['message'];
      if (msg is String && msg.isNotEmpty) apiMessage = msg;
    } catch (_) {}
    throw AppException.fromHttp(res.statusCode, apiMessage: apiMessage, fallback: 'Claude request failed');
  }
}
