import 'dart:typed_data';
import "package:echoscribe/services/ai/ai_provider.dart";
import "package:echoscribe/services/summary_service.dart";
import "package:echoscribe/services/translation_service.dart";

class AnthropicProvider implements AiProvider {
  final SummaryService _summary;
  final TranslationService _translation;

  AnthropicProvider({
    required SummaryService summary,
    required TranslationService translation,
  }) : _summary = summary,
       _translation = translation;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
  }) {
    return _summary.summarizeAnthropic(
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
    return _translation.translateAnthropic(
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
    // Claude does not support audio transcription
    return Future.error(Exception("Claude does not support audio transcription"));
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) {
    return Future.error(Exception("Claude does not support image generation"));
  }
}
