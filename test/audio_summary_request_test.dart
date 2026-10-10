import 'dart:convert';

import 'package:echoscribe/services/summary_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('every audio summary provider receives thematic default', () async {
    final requests = <String, String>{};
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final host = request.url.host;
      if (host == 'generativelanguage.googleapis.com') {
        requests['Gemini'] = body['contents'][0]['parts'][0]['text'] as String;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Summary'}
                    ]
                  }
                }
              ],
            }),
            200);
      }
      if (host == 'api.anthropic.com') {
        requests['Anthropic'] = body['messages'][0]['content'] as String;
        return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Summary'}
              ],
            }),
            200);
      }
      if (host == 'localhost') {
        requests['Ollama'] = body['messages'][1]['content'] as String;
        return http.Response(
            jsonEncode({
              'message': {'content': 'Summary'},
            }),
            200);
      }
      requests[host == 'api.x.ai' ? 'xAI' : 'OpenAI'] =
          body['messages'][1]['content'] as String;
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'Summary'}
              }
            ],
          }),
          200);
    });

    await http.runWithClient(() async {
      final service = SummaryService();
      expect(await service.summarizeOpenAI(apiKey: 'test', text: 'Transcript'),
          'Summary');
      expect(await service.summarizeGemini(apiKey: 'test', text: 'Transcript'),
          'Summary');
      expect(await service.summarizeXai(apiKey: 'test', text: 'Transcript'),
          'Summary');
      expect(
          await service.summarizeAnthropic(apiKey: 'test', text: 'Transcript'),
          'Summary');
      expect(
          await service.summarizeOllama(
              endpoint: 'http://localhost/api/chat', text: 'Transcript'),
          'Summary');
    }, () => client);

    expect(requests.keys,
        containsAll(['OpenAI', 'Gemini', 'xAI', 'Anthropic', 'Ollama']));
    for (final prompt in requests.values) {
      expect(prompt, contains('2–4 short sections'));
      expect(prompt, contains('## <emoji> <1–3 word title>'));
      expect(prompt, contains('short paragraph'));
    }
  });
}
