import 'dart:convert';

import 'package:echoscribe/services/ai/gemini_realtime_client.dart';
import 'package:echoscribe/services/gemini_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Gemini dedicated file STT request', () {
    test('omits language_hints and uses official transcription_config', () {
      final body = GeminiService.buildDedicatedTranscriptionRequest(
        model: 'gemini-3.5-transcribe',
        audioInput: {
          'type': 'audio',
          'uri': 'https://example.invalid/file',
          'mime_type': 'audio/mp4',
        },
      );

      final config = body['generation_config']['transcription_config']
          as Map<String, dynamic>;
      expect(config.containsKey('language_hints'), isFalse);
      expect(config.containsKey('language_codes'), isFalse);
      expect(config['mode'], {
        'type': 'verbatim',
        'diarization_mode': 'speaker',
      });
      expect(body['model'], 'gemini-3.5-transcribe');
      expect((body['input'] as List).single['type'], 'audio');
    });

    test('adds BCP-47 language_codes only when a language is known', () {
      final body = GeminiService.buildDedicatedTranscriptionRequest(
        model: 'gemini-3.5-transcribe',
        audioInput: {'type': 'audio', 'data': 'AAA=', 'mime_type': 'audio/wav'},
        languageCodes: const ['de-DE'],
      );
      final config = body['generation_config']['transcription_config']
          as Map<String, dynamic>;
      expect(config['language_codes'], ['de-DE']);
      expect(config.containsKey('language_hints'), isFalse);
    });
  });

  group('Gemini live setup', () {
    test('uses VERBATIM mode and omits auto language fields', () {
      final setup = GeminiRealtimeClient.buildSetupMessage(
        model: 'gemini-3.5-transcribe-live',
        targetLanguageCode: 'auto',
      )['setup'] as Map<String, dynamic>;

      final transcription =
          setup['inputAudioTranscription'] as Map<String, dynamic>;
      expect(setup['model'], 'models/gemini-3.5-transcribe-live');
      expect(transcription['mode'], 'VERBATIM');
      expect(transcription.containsKey('languageCodes'), isFalse);
      expect(transcription.containsKey('language_hints'), isFalse);
      expect(setup.containsKey('generationConfig'), isFalse);
    });

    test('adds languageCodes only for an explicit BCP-47 language', () {
      final setup = GeminiRealtimeClient.buildSetupMessage(
        model: 'models/gemini-3.5-transcribe-live',
        targetLanguageCode: 'de-DE',
      )['setup'] as Map<String, dynamic>;
      final transcription =
          setup['inputAudioTranscription'] as Map<String, dynamic>;
      expect(transcription['languageCodes'], ['de-DE']);
      expect(transcription['mode'], 'VERBATIM');
    });
  });

  group('Gemini live socket frames', () {
    test('decodes text JSON frames', () {
      final event = GeminiRealtimeClient.decodeSocketEvent(
        '{"setupComplete":{}}',
      );
      expect(event, contains('setupComplete'));
    });

    test('decodes binary JSON frames used by Gemini Live', () {
      final event = GeminiRealtimeClient.decodeSocketEvent(
        utf8.encode('{"setupComplete":{}}'),
      );
      expect(event, contains('setupComplete'));
    });
  });
}
