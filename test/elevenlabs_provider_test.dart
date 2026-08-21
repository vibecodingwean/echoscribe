import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ElevenLabs provider capabilities', () {
    test('is a first-class live transcription and TTS-only provider', () {
      const provider = AiProviderType.elevenLabs;

      expect(provider.brandName, 'ElevenLabs');
      expect(provider.supportsAudio, isTrue);
      expect(provider.supportsRealtimeTranscription, isTrue);
      expect(provider.supportsBatchTranscription, isFalse);
      expect(provider.supportsTts, isTrue);
      expect(provider.supportsSummary, isFalse);
      expect(provider.supportsTranslation, isFalse);
      expect(provider.supportsImage, isFalse);
      expect(provider.supportsKeyboardDictation, isFalse);
      expect(provider.supportsFloatingDictation, isFalse);
      expect(AiProviderType.fromString('elevenlabs'), provider);
      expect(AiProviderType.fromString('elevenLabs'), provider);
    });
  });

  group('ElevenLabs provider settings', () {
    test('uses its own API key and enables realtime intrinsically', () {
      final settings = SettingsState()
        ..setOpenAiKey('open-key')
        ..setElevenLabsKey('eleven-key')
        ..setProvider(AiProviderType.elevenLabs);

      expect(settings.activeApiKey, 'eleven-key');
      expect(settings.hasActiveApiKey, isTrue);
      expect(settings.realtimeEnabled, isTrue);
      expect(settings.elevenLabsRealtime, isTrue);
    });

    test('forces auto language because realtime translation is unsupported',
        () {
      final settings = SettingsState()
        ..setTargetLanguageCode('de')
        ..setProvider(AiProviderType.elevenLabs);

      expect(settings.targetLanguageCode, 'auto');

      settings.setTargetLanguageCode('fr');
      expect(settings.targetLanguageCode, 'auto');
    });

    test('does not leak ElevenLabs realtime into other providers', () {
      final settings = SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setProvider(AiProviderType.gemini);

      expect(settings.realtimeEnabled, isFalse);
      expect(settings.elevenLabsRealtime, isFalse);

      settings
        ..setProvider(AiProviderType.openai)
        ..setOpenAiRealtime(true);
      expect(settings.realtimeEnabled, isTrue);
    });
  });
}
