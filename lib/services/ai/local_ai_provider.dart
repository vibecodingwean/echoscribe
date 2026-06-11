import 'dart:typed_data';

import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:echoscribe/services/whisper_service.dart';
import 'package:echoscribe/models/app_exception.dart';

class LocalAiProvider implements AiProvider {
  final WhisperService _whisper;
  final SummaryService _summary;
  final TranslationService _translation;
  final String llmUrl;
  final String whisperUrl;

  LocalAiProvider({
    required WhisperService whisper,
    required SummaryService summary,
    required TranslationService translation,
    required this.llmUrl,
    required this.whisperUrl,
  })  : _whisper = whisper,
        _summary = summary,
        _translation = translation;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) {
    return _summary.summarizeOllama(
      endpoint: llmUrl,
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
    String? reasoningEffort,
  }) {
    return _translation.translateOllama(
      endpoint: llmUrl,
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
    return _whisper.transcribeCompatible(
      endpoint: whisperUrl,
      filePath: filePath,
      fileName: fileName,
      model: model,
    );
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) {
    throw const AppException('Local AI does not support image generation.');
  }
}
