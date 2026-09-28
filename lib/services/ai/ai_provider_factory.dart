import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/ai/consent_aware_provider.dart';
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
import 'package:echoscribe/services/provider_consent_service.dart';

class AiProviderFactory {
  final WhisperService whisper;
  final GeminiService gemini;
  final SummaryService summary;
  final TranslationService translation;
  final ImageService image;
  final XaiSpeechService xaiSpeech;
  final ProviderConsentService? consent;

  AiProviderFactory({
    required this.whisper,
    required this.gemini,
    required this.summary,
    required this.translation,
    required this.image,
    required this.xaiSpeech,
    this.consent,
  });

  AiProvider create(
    AiProviderType provider, {
    SettingsState? settings,
    String? localAiLlmUrl,
    String? localAiWhisperUrl,
  }) {
    final AiProvider delegate;
    switch (provider) {
      case AiProviderType.gemini:
        delegate = GeminiProvider(
          gemini: gemini,
          summary: summary,
          translation: translation,
          image: image,
        );
      case AiProviderType.anthropic:
        delegate = AnthropicProvider(summary: summary, translation: translation);
      case AiProviderType.xai:
        delegate = XaiProvider(
          summary: summary,
          translation: translation,
          image: image,
          speech: xaiSpeech,
        );
      case AiProviderType.localAi:
        delegate = LocalAiProvider(
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
        delegate = ElevenLabsProvider();
      case AiProviderType.openai:
        delegate = OpenAiProvider(
          whisper: whisper,
          summary: summary,
          translation: translation,
          image: image,
        );
    }
    final guard = consent;
    if (guard == null) return delegate;
    final localEndpoint = provider == AiProviderType.localAi
        ? '${localAiLlmUrl ?? settings?.localAiLlmUrl ?? AiModelConfig.localAiLlmUrl}|'
            '${localAiWhisperUrl ?? settings?.localAiWhisperUrl ?? AiModelConfig.localAiWhisperUrl}'
        : null;
    return ConsentAwareProvider(
      provider: provider,
      delegate: delegate,
      consent: guard,
      localEndpoint: localEndpoint,
    );
  }
}
