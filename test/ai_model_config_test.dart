import 'package:echoscribe/config/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI model defaults', () {
    test('OpenAI preserves fast and pro reasoning roles', () {
      expect(AiModelConfig.openAiSummary(pro: false), 'gpt-5.6-terra');
      expect(AiModelConfig.openAiSummary(pro: true), 'gpt-5.6-sol');
      expect(AiModelConfig.openAiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.openAiReasoningEffort(pro: true), 'medium');
    });

    test('Gemini and Anthropic use current fast defaults', () {
      expect(AiModelConfig.geminiSummary(pro: false), 'gemini-3.6-flash');
      expect(AiModelConfig.anthropicSummary(pro: false), 'claude-sonnet-5');
    });

    test('xAI keeps distinct fast and pro tiers', () {
      expect(AiModelConfig.xaiSummary(pro: false), 'grok-4.3');
      expect(AiModelConfig.xaiSummary(pro: true), 'grok-4.5');
      expect(AiModelConfig.xaiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.xaiReasoningEffort(pro: true), 'medium');
    });
  });
}
