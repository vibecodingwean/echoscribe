import 'dart:convert';
import 'dart:io';

import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/ai/elevenlabs_provider.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ElevenLabs provider capabilities', () {
    test('is a first-class STT and TTS provider without summaries', () {
      const provider = AiProviderType.elevenLabs;

      expect(provider.brandName, 'ElevenLabs');
      expect(provider.supportsAudio, isTrue);
      expect(provider.supportsRealtimeTranscription, isTrue);
      expect(provider.supportsBatchTranscription, isTrue);
      expect(provider.supportsTts, isTrue);
      expect(provider.supportsSummary, isFalse);
      expect(provider.supportsTranslation, isFalse);
      expect(provider.supportsImage, isFalse);
      expect(provider.supportsKeyboardDictation, isTrue);
      expect(provider.supportsFloatingDictation, isTrue);
      expect(AiProviderType.fromString('elevenlabs'), provider);
      expect(AiProviderType.fromString('elevenLabs'), provider);
    });
  });

  group('ElevenLabs provider settings', () {
    test('uses its own API key and keeps realtime off by default', () {
      final settings = SettingsState()
        ..setOpenAiKey('open-key')
        ..setElevenLabsKey('eleven-key')
        ..setProvider(AiProviderType.elevenLabs);

      expect(settings.activeApiKey, 'eleven-key');
      expect(settings.hasActiveApiKey, isTrue);
      expect(settings.elevenLabsRealtime, isFalse);
      expect(settings.realtimeEnabled, isFalse);
      expect(settings.transcriptionModel, AiModelConfig.elevenLabsTranscription);
      expect(settings.ttsVoice, AiModelConfig.elevenLabsTtsVoice);

      settings.setElevenLabsRealtime(true);
      expect(settings.realtimeEnabled, isTrue);
    });

    test('uses a custom Voice ID when set', () {
      final settings = SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setElevenLabsVoiceId('Q0Co3mt4NHZCSmKqCMMo');

      expect(settings.elevenLabsVoiceId, 'Q0Co3mt4NHZCSmKqCMMo');
      expect(settings.ttsVoice, 'Q0Co3mt4NHZCSmKqCMMo');

      settings.setElevenLabsVoiceId('  ');
      expect(settings.ttsVoice, AiModelConfig.elevenLabsTtsVoice);
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

      settings
        ..setProvider(AiProviderType.openai)
        ..setOpenAiRealtime(true);
      expect(settings.realtimeEnabled, isTrue);
    });
  });

  group('ElevenLabs batch STT', () {
    test('posts scribe_v2 with xi-api-key and returns text', () async {
      final dir = await Directory.systemTemp.createTemp('el-stt');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio.wav');
      await file.writeAsBytes(const <int>[1, 2, 3, 4]);

      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'language_code': 'deu', 'text': 'hello from scribe'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final text = await ElevenLabsProvider(client: client).transcribe(
        apiKey: 'unit-test-token',
        filePath: file.path,
        fileName: 'audio.wav',
        mimeType: 'audio/wav',
        model: AiModelConfig.elevenLabsTranscription,
      );

      expect(text, 'hello from scribe');
      expect(
        captured.url.toString(),
        'https://api.elevenlabs.io/v1/speech-to-text',
      );
      expect(captured.headers['xi-api-key'], 'unit-test-token');
      expect(captured.body, contains('scribe_v2'));
      expect(captured.body, contains('model_id'));
      expect(captured.body, contains('tag_audio_events'));
    });

    test('joins multichannel transcripts when text is absent', () async {
      final dir = await Directory.systemTemp.createTemp('el-stt-multi');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio.wav');
      await file.writeAsBytes(const <int>[1, 2, 3, 4]);

      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'transcripts': [
              {'text': 'channel one'},
              {'text': 'channel two'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      final text = await ElevenLabsProvider(client: client).transcribe(
        apiKey: 'unit-test-token',
        filePath: file.path,
        fileName: 'audio.wav',
        mimeType: 'audio/wav',
        model: 'scribe_v2',
      );

      expect(text, 'channel one\nchannel two');
    });

    test('surfaces list-shaped validation errors', () async {
      final dir = await Directory.systemTemp.createTemp('el-stt-err');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/audio.wav');
      await file.writeAsBytes(const <int>[1, 2, 3, 4]);

      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'detail': [
              {'msg': 'model_id is invalid'},
            ],
          }),
          422,
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        () => ElevenLabsProvider(client: client).transcribe(
          apiKey: 'unit-test-token',
          filePath: file.path,
          fileName: 'audio.wav',
          mimeType: 'audio/wav',
          model: 'nope',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.userMessage,
            'message',
            contains('model_id is invalid'),
          ),
        ),
      );
    });
  });
}
