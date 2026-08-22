import 'package:echoscribe/config/prompts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AI model defaults', () {
    test('OpenAI preserves fast and pro reasoning roles', () {
      expect(AiModelConfig.openAiSummary(pro: false), 'gpt-5.6-terra');
      expect(AiModelConfig.openAiSummary(pro: true), 'gpt-5.6-sol');
      expect(
        AiModelConfig.openAiTranscription(pro: false),
        'gpt-4o-mini-transcribe',
      );
      expect(AiModelConfig.openAiTranscription(pro: true), 'gpt-transcribe');
      expect(AiModelConfig.openAiRealtimeTranscription, 'gpt-live-transcribe');
      expect(
        AiModelConfig.openAiRealtimeTranslation,
        'gpt-realtime-translate',
      );
      expect(AiModelConfig.elevenLabsTranscription, 'scribe_v2');
      expect(
        AiModelConfig.elevenLabsRealtimeTranscription,
        'scribe_v2_realtime',
      );
      expect(
        AiModelConfig.elevenLabsVoiceLibraryUrl,
        'https://elevenlabs.io/app/voice-library',
      );
      expect(AiModelConfig.elevenLabsTts, 'eleven_flash_v2_5');
      expect(AiModelConfig.elevenLabsTtsVoice, 'JBFqnCBsd6RMkjVDRZzb');
      expect(AiModelConfig.openAiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.openAiReasoningEffort(pro: true), 'medium');
    });

    test('Gemini and Anthropic preserve fast and pro roles', () {
      expect(AiModelConfig.geminiSummary(pro: false), 'gemini-3.7-flash');
      expect(AiModelConfig.geminiTranslation(pro: false), 'gemini-3.7-flash');
      expect(
        AiModelConfig.geminiTranscription(pro: false),
        'gemini-3.7-flash',
      );
      expect(AiModelConfig.anthropicSummary(pro: false), 'claude-sonnet-5');
      expect(AiModelConfig.anthropicSummary(pro: true), 'claude-opus-5');
      expect(
        AiModelConfig.anthropicTranslation(pro: false),
        'claude-sonnet-5',
      );
      expect(AiModelConfig.anthropicTranslation(pro: true), 'claude-opus-5');
    });

    test('xAI keeps distinct fast and pro tiers', () {
      expect(AiModelConfig.xaiSummary(pro: false), 'grok-4.3');
      expect(AiModelConfig.xaiSummary(pro: true), 'grok-4.6');
      expect(AiModelConfig.xaiImage(pro: false), 'grok-imagine-image');
      expect(AiModelConfig.xaiImage(pro: true), 'grok-imagine-image-2.0');
      expect(AiModelConfig.xaiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.xaiReasoningEffort(pro: true), 'medium');
    });
  });
}
