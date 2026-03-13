import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/ai/openai_provider.dart';
import 'package:echoscribe/services/ai/gemini_provider.dart';
import 'package:echoscribe/services/ai/anthropic_provider.dart';
import 'package:echoscribe/services/ai/xai_provider.dart';
import 'package:echoscribe/services/whisper_service.dart';
import 'package:echoscribe/services/gemini_service.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:echoscribe/services/image_service.dart';
import 'package:echoscribe/models/enums.dart';

class AiProviderFactory {
  final WhisperService whisper;
  final GeminiService gemini;
  final SummaryService summary;
  final TranslationService translation;
  final ImageService image;

  AiProviderFactory({
    required this.whisper,
    required this.gemini,
    required this.summary,
    required this.translation,
    required this.image,
  });

  AiProvider create(AiProviderType provider) {
    switch (provider) {
      case AiProviderType.gemini:
        return GeminiProvider(
          gemini: gemini,
          summary: summary,
          translation: translation,
          image: image,
        );
      case AiProviderType.anthropic:
        return AnthropicProvider(
          summary: summary,
          translation: translation,
        );
      case AiProviderType.xai:
        return XaiProvider(
          summary: summary,
          translation: translation,
          image: image,
        );
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
