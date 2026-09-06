import 'package:echoscribe/services/gemini_content_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skips thought parts and keeps later summary text', () {
    final text = GeminiContentText.extract({
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'thought': true, 'text': 'internal reasoning'},
              {'text': 'Kurze Zusammenfassung auf Deutsch.'},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      'usageMetadata': {
        'thoughtsTokenCount': 276,
      },
      'modelVersion': 'gemini-3.7-flash',
    });
    expect(text, 'Kurze Zusammenfassung auf Deutsch.');
  });

  test('does not use first thought-only part as the summary', () {
    final text = GeminiContentText.extract({
      'candidates': [
        {
          'content': {
            'parts': [
              {'thought': true, 'inlineData': {'data': 'AAAA'}},
              {'text': 'Hello summary'},
            ],
          },
        },
      ],
    });
    expect(text, 'Hello summary');
  });

  test('rejects dumped generateContent envelopes', () {
    const dumped = '''
"finishReason": "STOP",
"usageMetadata": {"thoughtsTokenCount": 276},
"modelVersion": "gemini-3.7-flash"
''';
    expect(GeminiContentText.looksLikeApiEnvelope(dumped), isTrue);
    expect(
      GeminiContentText.extract({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': dumped},
              ],
            },
          },
        ],
      }),
      isEmpty,
    );
  });
}
