import 'dart:convert';

import 'package:echoscribe/services/debug_console.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const thoughtMarker = 'PRIVATE_THOUGHT_MARKER';
  late List<String> lines;

  setUp(() {
    lines = [];
    DebugConsole.configure(isEnabled: () => true, println: lines.add);
  });

  tearDown(() {
    DebugConsole.configure(isEnabled: () => false, println: (_) {});
  });

  for (final flow in ['summary', 'translation']) {
    Future<String> generate() => flow == 'summary'
        ? SummaryService().summarizeGemini(
            apiKey: 'unit-key',
            text: 'Source text',
          )
        : TranslationService().translateGemini(
            apiKey: 'unit-key',
            text: 'Source text',
            targetLanguageCode: 'de',
          );

    test('$flow logs visible text without thought parts', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'thought': true, 'text': thoughtMarker},
                    {'text': 'Visible answer'},
                  ],
                },
              },
            ],
            'usageMetadata': {'thoughtsTokenCount': 4},
          }),
          200));

      expect(
          await http.runWithClient(generate, () => client), 'Visible answer');
      expect(lines.join('\n'), contains('Visible answer'));
      expect(lines.join('\n'), isNot(contains(thoughtMarker)));
    });

    test('$flow does not log thought parts in error responses', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'message': 'Request rejected'},
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'thought': true, 'text': thoughtMarker},
                  ],
                },
              },
            ],
          }),
          400));

      await expectLater(
          http.runWithClient(generate, () => client), throwsException);
      expect(lines.join('\n'), contains('Request rejected'));
      expect(lines.join('\n'), isNot(contains(thoughtMarker)));
    });

    test('$flow omits unparseable error bodies rather than logging thoughts',
        () async {
      final client = MockClient(
        (_) async => http.Response('invalid response $thoughtMarker', 500),
      );

      await expectLater(
          http.runWithClient(generate, () => client), throwsException);
      expect(lines.join('\n'), contains('[Gemini response body omitted]'));
      expect(lines.join('\n'), isNot(contains(thoughtMarker)));
    });
  }
}
