import 'dart:convert';

import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('summary reads text after thinking in a Messages response', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'content': [
              {'type': 'thinking', 'thinking': 'internal reasoning'},
              {'type': 'text', 'text': '  Concise summary.  '},
              {'type': 'text', 'text': 'More details.'},
            ],
          }),
          200);
    });

    final result = await http.runWithClient(
      () => SummaryService().summarizeAnthropic(
        apiKey: 'unit-test-key',
        model: 'claude-opus-5-5',
        text: 'Source material',
      ),
      () => client,
    );

    expect(result, 'Concise summary.\nMore details.');
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(captured.headers['x-api-key'], 'unit-test-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['system'], contains('summarizer'));
    expect(body['messages'], [
      {'role': 'user', 'content': contains('Source material')},
    ]);
  });

  test('translation reads text after thinking and ignores malformed blocks',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'content': [
              null,
              {'type': 'thinking', 'text': 'not user-facing'},
              {'type': 'text', 'text': null},
              {'type': 'text', 'text': '  Übersetzter Text.  '},
              {'type': 'tool_use', 'text': 'not a translation'},
            ],
          }),
          200);
    });

    final result = await http.runWithClient(
      () => TranslationService().translateAnthropic(
        apiKey: 'unit-test-key',
        model: 'claude-opus-5-5',
        text: 'Source material',
        targetLanguageCode: 'de',
      ),
      () => client,
    );

    expect(result, 'Übersetzter Text.');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['system'], contains('translation engine'));
    expect(body['messages'], [
      {'role': 'user', 'content': contains('Source material')},
    ]);
  });

  test('text-only Messages response still returns its text', () async {
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '  Standard response.  '},
          ],
        }),
        200));

    final result = await http.runWithClient(
      () => SummaryService().summarizeAnthropic(
        apiKey: 'unit-test-key',
        model: 'claude-opus-5-5',
        text: 'Source material',
      ),
      () => client,
    );

    expect(result, 'Standard response.');
  });
}
