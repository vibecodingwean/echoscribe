import 'dart:typed_data';

import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';

/// ElevenLabs is handled by the dedicated realtime STT client and TTS service.
/// These methods fail closed so unsupported batch/LLM/image paths cannot fall
/// back to another provider with the ElevenLabs credential.
class ElevenLabsProvider implements AiProvider {
  const ElevenLabsProvider();

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) {
    throw const AppException('ElevenLabs does not support summaries.');
  }

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
    String? reasoningEffort,
  }) {
    throw const AppException(
      'ElevenLabs Realtime transcribes speech but does not translate it.',
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
    throw const AppException(
      'ElevenLabs is available for live transcription only.',
    );
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) {
    throw const AppException(
      'ElevenLabs does not support image generation.',
    );
  }
}
