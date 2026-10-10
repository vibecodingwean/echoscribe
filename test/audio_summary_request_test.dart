import 'dart:convert';

import 'package:echoscribe/services/summary_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('every audio summary provider requests a heading even for one topic',
      () async {
    final requests = <String, Map<String, String>>{};
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final host = request.url.host;
      if (host == 'generativelanguage.googleapis.com') {
        requests['Gemini'] = {
          'user': body['contents'][0]['parts'][0]['text'] as String,
        };
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
        requests['Anthropic'] = {
          'system': body['system'] as String,
          'user': body['messages'][0]['content'] as String,
        };
        return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'Summary'}
              ],
            }),
            200);
      }
      if (host == 'localhost') {
        requests['Ollama'] = {
          'system': body['messages'][0]['content'] as String,
          'user': body['messages'][1]['content'] as String,
        };
        return http.Response(
            jsonEncode({
              'message': {'content': 'Summary'},
            }),
            200);
      }
      requests[host == 'api.x.ai' ? 'xAI' : 'OpenAI'] = {
        'system': body['messages'][0]['content'] as String,
        'user': body['messages'][1]['content'] as String,
      };
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
    for (final request in requests.values) {
      final prompt = request['user']!;
      expect(prompt, contains('## <emoji> <1–3 word title>'));
      expect(prompt, contains('one topic'));
      expect(prompt, contains('one heading'));
      expect(prompt, isNot(contains('short paragraph instead')));
      expect(prompt, contains('Text:\nTranscript'));
      expect(request['system'] ?? '', isNot(contains('no preface or labels')));
      if (request['system'] != null) {
        expect(request['system'],
            contains('begin with a topic-specific Markdown'));
      }
    }
  });

  test(
      'custom summary formatting reaches providers without default heading rule',
      () async {
    final requests = <String, Map<String, String>>{};
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final host = request.url.host;
      if (host == 'generativelanguage.googleapis.com') {
        requests['Gemini'] = {
          'user': body['contents'][0]['parts'][0]['text'] as String
        };
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'OK'}
                    ]
                  }
                }
              ]
            }),
            200);
      }
      if (host == 'api.anthropic.com') {
        requests['Anthropic'] = {
          'system': body['system'] as String,
          'user': body['messages'][0]['content'] as String,
        };
        return http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'OK'}
              ]
            }),
            200);
      }
      if (host == 'localhost') {
        requests['Ollama'] = {
          'system': body['messages'][0]['content'] as String,
          'user': body['messages'][1]['content'] as String,
        };
        return http.Response(
            jsonEncode({
              'message': {'content': 'OK'}
            }),
            200);
      }
      requests[host == 'api.x.ai' ? 'xAI' : 'OpenAI'] = {
        'system': body['messages'][0]['content'] as String,
        'user': body['messages'][1]['content'] as String,
      };
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'OK'}
              }
            ]
          }),
          200);
    });

    const custom = 'Return exactly one unheaded sentence.';
    await http.runWithClient(() async {
      final service = SummaryService();
      expect(
          await service.summarizeOpenAI(
              apiKey: 'test', text: 'Transcript', summaryPrompt: custom),
          'OK');
      expect(
          await service.summarizeGemini(
              apiKey: 'test', text: 'Transcript', summaryPrompt: custom),
          'OK');
      expect(
          await service.summarizeXai(
              apiKey: 'test', text: 'Transcript', summaryPrompt: custom),
          'OK');
      expect(
          await service.summarizeAnthropic(
              apiKey: 'test', text: 'Transcript', summaryPrompt: custom),
          'OK');
      expect(
          await service.summarizeOllama(
              endpoint: 'http://localhost/api/chat',
              text: 'Transcript',
              summaryPrompt: custom),
          'OK');
    }, () => client);

    expect(requests.keys,
        containsAll(['OpenAI', 'Gemini', 'xAI', 'Anthropic', 'Ollama']));
    for (final request in requests.values) {
      expect(request['user'], startsWith(custom));
      expect(
          request['user'], isNot(contains('Every substantive summary MUST')));
      expect(request['system'] ?? '',
          isNot(contains('begin with a topic-specific Markdown')));
    }
  });
}
