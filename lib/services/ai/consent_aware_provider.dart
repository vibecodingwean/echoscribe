import 'dart:typed_data';

import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/provider_consent_service.dart';

/// Enforces consent at the common boundary for batch AI requests.
class ConsentAwareProvider implements AiProvider {
  ConsentAwareProvider({
    required this.provider,
    required this.delegate,
    required this.consent,
    this.localEndpoint,
  });

  final AiProviderType provider;
  final AiProvider delegate;
  final ProviderConsentService consent;
  final String? localEndpoint;

  Future<void> _ensure(String dataType, String purpose) => consent.ensure(
        provider,
        dataType: dataType,
        purpose: purpose,
        localEndpoint: localEndpoint,
      );

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) async {
    await _ensure('text, URL or webpage content and custom prompts', 'a summary');
    return delegate.summarize(
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
  }) async {
    await _ensure('text and custom prompts', 'translation');
    return delegate.translate(
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
  }) async {
    await _ensure('an audio file and its filename', 'transcription');
    return delegate.transcribe(
      apiKey: apiKey,
      filePath: filePath,
      fileName: fileName,
      mimeType: mimeType,
      model: model,
    );
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) async {
    await _ensure('a text prompt derived from your content', 'image generation');
    return delegate.generateImage(
      apiKey: apiKey,
      prompt: prompt,
      model: model,
    );
  }
}
