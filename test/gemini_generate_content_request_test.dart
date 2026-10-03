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
        ? <String, dynamic>{}
        : <String, dynamic>{
            'generationConfig': {'thinkingConfig': {'thinkingBudget': 0}},
          };

    test('summary sends exact Gemini $model generateContent JSON', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({
          'candidates': [
            {'content': {'parts': [{'text': 'Summary'}]}}
          ],
        }), 200);
      });
      final result = await http.runWithClient(
        () => SummaryService().summarizeGemini(
          apiKey: 'unit-key', model: model, text: 'Source text',
          targetLanguageCode: 'de', summaryPrompt: 'Summarize.',
        ),
        () => client,
      );
      expect(result, 'Summary');
      expect(captured.url.path, '/v1beta/models/$model:generateContent');
      expect(jsonDecode(captured.body), {
        'contents': [
          {'role': 'user', 'parts': [
            {'text': 'Summarize.\n\nLanguage rule: Output MUST be in German '
                '("de"). Do not use any other language.\n\nText:\nSource text'},
          ]},
        ],
        ...config,
      });
    });

    test('translation sends exact Gemini $model generateContent JSON', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({
          'candidates': [
            {'content': {'parts': [{'text': 'Übersetzung'}]}}
          ],
        }), 200);
      });
      final result = await http.runWithClient(
        () => TranslationService().translateGemini(
          apiKey: 'unit-key', model: model, text: 'Source text',
          targetLanguageCode: 'de',
        ),
        () => client,
      );
      expect(result, 'Übersetzung');
      expect(captured.url.path, '/v1beta/models/$model:generateContent');
      expect(jsonDecode(captured.body), {
        'contents': [
          {'role': 'user', 'parts': [
            {'text': 'Translate the following text to German. Output only '
                'the translated text. Text:\n\nSource text'},
          ]},
        ],
        ...config,
      });
    });
  }
}
