import "package:echoscribe/services/ai/ai_provider.dart";
import "package:echoscribe/services/whisper_service.dart";
import "package:echoscribe/services/summary_service.dart";
import "package:echoscribe/services/translation_service.dart";

class OpenAiProvider implements AiProvider {
  final WhisperService _whisper;
  final SummaryService _summary;
  final TranslationService _translation;

  OpenAiProvider({
    required WhisperService whisper,
    required SummaryService summary,
    required TranslationService translation,
  }) : _whisper = whisper,
       _summary = summary,
       _translation = translation;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
  }) {
    return _summary.summarizeOpenAI(
      apiKey: apiKey,
      text: text,
      model: model,
      targetLanguageCode: targetLanguageCode,
      summaryPrompt: summaryPrompt,
    );
  }

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
  }) {
    return _translation.translateOpenAI(
      apiKey: apiKey,
      text: text,
      targetLanguageCode: targetLanguageCode,
      model: model,
    );
  }

  @override
  Future<String> transcribe({
    required String apiKey,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String model,
  }) {
    return _whisper.transcribe(
      apiKey: apiKey,
      filePath: filePath,
      model: model,
    );
  }
}
