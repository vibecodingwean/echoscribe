import "package:echoscribe/services/ai/ai_provider.dart";
import "package:echoscribe/services/gemini_service.dart";
import "package:echoscribe/services/summary_service.dart";
import "package:echoscribe/services/translation_service.dart";

class GeminiProvider implements AiProvider {
  final GeminiService _gemini;
  final SummaryService _summary;
  final TranslationService _translation;

  GeminiProvider({
    required GeminiService gemini,
    required SummaryService summary,
    required TranslationService translation,
  }) : _gemini = gemini,
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
    return _summary.summarizeGemini(
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
    return _translation.translateGemini(
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
    return _gemini.transcribe(
      apiKey: apiKey,
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
      model: model,
    );
  }
}
