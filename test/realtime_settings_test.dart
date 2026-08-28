import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('model lookup follows the selected provider and pro flags', () {
    final settings = SettingsState();

    expect(settings.summaryModel, AiModelConfig.openAiSummaryFast);
    expect(settings.transcriptionModel, AiModelConfig.openAiTranscriptionFast);
    expect(settings.translationModel, AiModelConfig.openAiTranslationFast);
    expect(settings.reasoningEffort, AiModelConfig.openAiReasoningEffortFast);
    expect(settings.imageModel, AiModelConfig.openAiImagePro);
    expect(settings.ttsVoice, 'alloy');

    settings.setOpenAiPro(true);
    expect(settings.summaryModel, AiModelConfig.openAiSummaryPro);
    expect(settings.transcriptionModel, AiModelConfig.openAiTranscriptionPro);

    settings.setProvider(AiProviderType.elevenLabs);
    expect(settings.summaryModel, isEmpty);
    expect(
      settings.transcriptionModel,
      AiModelConfig.elevenLabsTranscription,
    );
    expect(settings.ttsVoice, AiModelConfig.elevenLabsTtsVoice);

    settings
      ..setProvider(AiProviderType.gemini)
      ..setGeminiPro(false);
    expect(settings.summaryModel, AiModelConfig.geminiSummaryFast);
    expect(
      settings.transcriptionModel,
      AiModelConfig.geminiTranscriptionFast,
    );
    expect(settings.transcriptionModel, 'gemini-3.5-transcribe');
    expect(settings.reasoningEffort, isNull);
    expect(settings.imageModel, AiModelConfig.geminiImagePro);
    expect(settings.ttsVoice, 'Zephyr');
  });

  test('realtime mode is scoped to the selected provider', () {
    final settings = SettingsState();

    settings.setOpenAiRealtime(true);
    expect(settings.openAiRealtime, isTrue);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.gemini);
    expect(settings.openAiRealtime, isTrue);
    expect(settings.realtimeEnabled, isFalse);
    expect(settings.geminiRealtime, isFalse);
    settings.setGeminiRealtime(true);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.elevenLabs);
    expect(settings.realtimeEnabled, isFalse);
    settings.setElevenLabsRealtime(true);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.openai);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.gemini);
    expect(settings.realtimeEnabled, isTrue);
  });

  test('Gemini supports realtime transcription capability', () {
    expect(AiProviderType.gemini.supportsRealtimeTranscription, isTrue);
  });
}
