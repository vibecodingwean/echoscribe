import 'dart:convert';

import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final model in [
    AiModelConfig.geminiSummaryPro,
    AiModelConfig.geminiSummaryFast,
  ]) {
    final config = model == AiModelConfig.geminiSummaryPro
        ? <String, dynamic>{
            'generationConfig': {
              'maxOutputTokens': 32768,
              'thinkingConfig': {'thinkingLevel': 'low'}
            }
          }
        : <String, dynamic>{
            'generationConfig': {
              'thinkingConfig': {'thinkingBudget': 0}
            },
          };

    test('summary sends exact Gemini $model generateContent JSON', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'Summary'}
                    ]
                  }
                }
              ],
            }),
            200);
      });
      final result = await http.runWithClient(
        () => SummaryService().summarizeGemini(
          apiKey: 'unit-key',
          model: model,
          text: 'Source text',
          targetLanguageCode: 'de',
          summaryPrompt: 'Summarize.',
        ),
        () => client,
      );
      expect(result, 'Summary');
      expect(captured.url.path, '/v1beta/models/$model:generateContent');
      expect(jsonDecode(captured.body), {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'Summarize.\n\nLanguage rule: Output MUST be in German '
                    '("de"). Do not use any other language.\n\nText:\nSource text'
              },
            ]
          },
        ],
        ...config,
      });
    });

    test('translation sends exact Gemini $model generateContent JSON',
        () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'Übersetzung'}
                    ]
                  }
                }
              ],
            }),
            200);
      });
      final result = await http.runWithClient(
        () => TranslationService().translateGemini(
          apiKey: 'unit-key',
          model: model,
          text: 'Source text',
          targetLanguageCode: 'de',
        ),
        () => client,
      );
      expect(result, 'Übersetzung');
      expect(captured.url.path, '/v1beta/models/$model:generateContent');
      expect(jsonDecode(captured.body), {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text': 'Translate the following text to German. Output only '
                    'the translated text. Text:\n\nSource text'
              },
            ]
          },
        ],
        ...config,
      });
    });
  }
  for (final capability in ['summary', 'translation']) {
    for (final response in [
      {
        'finishReason': 'MAX_TOKENS',
        'content': {
          'parts': [
            {'text': 'Incomplete'}
          ]
        }
      },
      {
        'finishReason': 'STOP',
        'content': {
          'parts': [
            {'thought': true, 'text': 'Reasoning'}
          ]
        }
      },
      {
        'finishReason': 'SAFETY',
        'content': {
          'parts': [
            {'text': 'Blocked'}
          ]
        }
      },
      {
        'content': {
          'parts': [
            {'text': 'Missing completion status'}
          ]
        }
      },
    ]) {
      test(
          'Argon $capability rejects incomplete or non-visible response $response',
          () async {
        final client = MockClient((_) async => http.Response(
            jsonEncode({
              'candidates': [response]
            }),
            200));
        final future = http.runWithClient(
            () => capability == 'summary'
                ? SummaryService().summarizeGemini(
                    apiKey: '***',
                    model: 'gemini-4-argon',
                    text: 'Source',
                    targetLanguageCode: 'de',
                    summaryPrompt: 'Summarize.')
                : TranslationService().translateGemini(
                    apiKey: '***',
                    model: 'gemini-4-argon',
                    text: 'Source',
                    targetLanguageCode: 'en'),
            () => client);
        await expectLater(future, throwsA(isA<Exception>()));
      });
    }
  }
}
