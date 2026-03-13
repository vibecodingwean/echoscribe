import 'dart:typed_data';
import "package:echoscribe/services/ai/ai_provider.dart";
import "package:echoscribe/services/summary_service.dart";
import "package:echoscribe/services/translation_service.dart";
import "package:echoscribe/services/image_service.dart";

class XaiProvider implements AiProvider {
  final SummaryService _summary;
  final TranslationService _translation;
  final ImageService _image;

  XaiProvider({
    required SummaryService summary,
    required TranslationService translation,
    required ImageService image,
  }) : _summary = summary,
       _translation = translation,
       _image = image;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
  }) {
    return _summary.summarizeXai(
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
    return _translation.translateXai(
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
    return Future.error(Exception("Grok does not support audio transcription"));
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) {
    return _image.generateImageXai(
      apiKey: apiKey,
      prompt: prompt,
      model: model,
    );
  }
}
