import 'dart:typed_data';
import "package:echoscribe/services/ai/ai_provider.dart";
import "package:echoscribe/services/summary_service.dart";
import "package:echoscribe/services/translation_service.dart";
import "package:echoscribe/services/image_service.dart";
import "package:echoscribe/services/xai_speech_service.dart";

class XaiProvider implements AiProvider {
  final SummaryService _summary;
  final TranslationService _translation;
  final ImageService _image;
  final XaiSpeechService _speech;

  XaiProvider({
    required SummaryService summary,
    required TranslationService translation,
    required ImageService image,
    required XaiSpeechService speech,
  })  : _summary = summary,
        _translation = translation,
        _image = image,
        _speech = speech;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) {
    return _summary.summarizeXai(
      apiKey: apiKey,
      text: text,
      model: model,
      targetLanguageCode: targetLanguageCode,
      summaryPrompt: summaryPrompt,
      reasoningEffort: reasoningEffort,
    );
  }

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
    String? reasoningEffort,
  }) {
    return _translation.translateXai(
      apiKey: apiKey,
      text: text,
      targetLanguageCode: targetLanguageCode,
      model: model,
      reasoningEffort: reasoningEffort,
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
    return _speech.transcribe(
      apiKey: apiKey,
      filePath: filePath,
      fileName: fileName,
    );
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
