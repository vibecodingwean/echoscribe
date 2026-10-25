import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'retained Gemini Pro flag selects Argon without changing dedicated models',
      () {
    final settings = SettingsState()
      ..setProvider(AiProviderType.gemini)
      ..setGeminiPro(true);
    expect(settings.summaryModel, 'gemini-4-argon');
    expect(settings.translationModel, 'gemini-4-argon');
    expect(settings.transcriptionModel, 'gemini-3.5-transcribe');
    settings.setGeminiPro(false);
    expect(settings.summaryModel, 'gemini-3.8-flash');
    expect(settings.translationModel, 'gemini-3.8-flash');
  });
  group('AI model defaults', () {
    test('OpenAI preserves fast and pro reasoning roles', () {
      expect(AiModelConfig.openAiSummary(pro: false), 'gpt-6-luna');
      expect(AiModelConfig.openAiSummary(pro: true), 'gpt-6-astra');
      expect(AiModelConfig.openAiTranslation(pro: true), 'gpt-6-astra');
      expect(
        AiModelConfig.openAiTranscription(pro: false),
        'gpt-transcribe',
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
      expect(AiModelConfig.elevenLabsTts, 'eleven_multilingual_v2');
      expect(AiModelConfig.elevenLabsTtsVoice, 'vChnJZ1Cu89g2XXumPfT');
      expect(AiModelConfig.openAiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.openAiReasoningEffort(pro: true), 'medium');
    });

    test('Gemini and Anthropic preserve fast and pro roles', () {
      expect(AiModelConfig.geminiSummary(pro: true), 'gemini-4-argon');
      expect(AiModelConfig.geminiTranslation(pro: true), 'gemini-4-argon');
      expect(AiModelConfig.geminiSummary(pro: false), 'gemini-3.8-flash');
      expect(AiModelConfig.geminiTranslation(pro: false), 'gemini-3.8-flash');
      expect(
        AiModelConfig.geminiTranscription(pro: false),
        'gemini-3.5-transcribe',
      );
      expect(
        AiModelConfig.geminiTranscription(pro: true),
        'gemini-3.5-transcribe',
      );
      expect(
        AiModelConfig.geminiRealtimeTranscription,
        'gemini-3.5-transcribe-live',
      );
      expect(AiModelConfig.geminiTts, 'gemini-3.8-flash-tts');
      expect(AiModelConfig.anthropicSummary(pro: false), 'claude-haiku-5-5');
      expect(AiModelConfig.anthropicSummary(pro: true), 'claude-opus-5-5');
      expect(
        AiModelConfig.anthropicTranslation(pro: false),
        'claude-haiku-5-5',
      );
      expect(AiModelConfig.anthropicTranslation(pro: true), 'claude-opus-5-5');
    });

    test('xAI keeps distinct fast and pro tiers', () {
      expect(AiModelConfig.xaiSummary(pro: false), 'grok-4.3');
      expect(AiModelConfig.xaiSummary(pro: true), 'grok-4.6');
      expect(AiModelConfig.xaiImage(pro: false), 'grok-imagine-image');
      expect(AiModelConfig.xaiImage(pro: true), 'grok-imagine-image-2.0');
      expect(AiModelConfig.xaiTranscription(pro: false),
          'grok-voice-transcribe-2.0');
      expect(AiModelConfig.xaiTranscription(pro: true),
          'grok-voice-transcribe-2.0');
      expect(AiModelConfig.xaiReasoningEffort(pro: false), 'none');
      expect(AiModelConfig.xaiReasoningEffort(pro: true), 'medium');
    });
  });
}
