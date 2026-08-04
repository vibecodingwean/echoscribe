import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/ai/openai_provider.dart';
import 'package:echoscribe/services/ai/local_ai_provider.dart';
import 'package:echoscribe/services/ai/gemini_provider.dart';
import 'package:echoscribe/services/ai/anthropic_provider.dart';
import 'package:echoscribe/services/ai/xai_provider.dart';
import 'package:echoscribe/services/ai/elevenlabs_provider.dart';
import 'package:echoscribe/services/whisper_service.dart';
import 'package:echoscribe/services/gemini_service.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:echoscribe/services/image_service.dart';
import 'package:echoscribe/services/xai_speech_service.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/config/prompts.dart';

class AiProviderFactory {
  final WhisperService whisper;
  final GeminiService gemini;
  final SummaryService summary;
  final TranslationService translation;
  final ImageService image;
  final XaiSpeechService xaiSpeech;

  AiProviderFactory({
    required this.whisper,
    required this.gemini,
    required this.summary,
    required this.translation,
    required this.image,
    required this.xaiSpeech,
  });

  AiProvider create(
    AiProviderType provider, {
    SettingsState? settings,
    String? localAiLlmUrl,
    String? localAiWhisperUrl,
  }) {
    switch (provider) {
      case AiProviderType.gemini:
        return GeminiProvider(
          gemini: gemini,
          summary: summary,
          translation: translation,
          image: image,
        );
      case AiProviderType.anthropic:
        return AnthropicProvider(summary: summary, translation: translation);
      case AiProviderType.xai:
        return XaiProvider(
          summary: summary,
          translation: translation,
          image: image,
          speech: xaiSpeech,
        );
      case AiProviderType.localAi:
        return LocalAiProvider(
          whisper: whisper,
          summary: summary,
          translation: translation,
          llmUrl: localAiLlmUrl ??
              settings?.localAiLlmUrl ??
              AiModelConfig.localAiLlmUrl,
          whisperUrl: localAiWhisperUrl ??
              settings?.localAiWhisperUrl ??
              AiModelConfig.localAiWhisperUrl,
        );
      case AiProviderType.elevenLabs:
        return const ElevenLabsProvider();
      case AiProviderType.openai:
        return OpenAiProvider(
          whisper: whisper,
          summary: summary,
          translation: translation,
          image: image,
        );
    }
  }
}
