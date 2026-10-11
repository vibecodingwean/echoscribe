import 'dart:convert';

import 'package:echoscribe/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('empty Voice ID uses the published tutorial narrator profile', () async {
    late http.Request captured;
    final service = TtsService(client: MockClient((request) async {
      captured = request;
      return http.Response.bytes(<int>[1], 200);
    }));

    await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: '  Hello there  ',
      voiceId: '',
    );

    expect(captured.url.path, '/v1/text-to-speech/vChnJZ1Cu89g2XXumPfT');
    expect(jsonDecode(captured.body), {
      'text': 'Hello there',
      'model_id': 'eleven_multilingual_v2',
      'voice_settings': {
        'stability': 0.45,
        'similarity_boost': 0.8,
        'style': 0,
        'use_speaker_boost': true,
      },
    });
    expect(captured.body, isNot(contains('speed')));
  });

  test('saved custom Voice ID keeps Flash and no narrator settings', () async {
    late http.Request captured;
    final service = TtsService(client: MockClient((request) async {
      captured = request;
      return http.Response.bytes(<int>[1], 200);
    }));

    await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: 'Hello',
      voiceId: 'JBFqnCBsd6RMkjVDRZzb',
    );

    expect(captured.url.path, '/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb');
    expect(jsonDecode(captured.body), {
      'text': 'Hello',
      'model_id': 'eleven_flash_v2_5',
    });
  });

  test('explicit tutorial Voice ID preserves its saved custom profile',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final service = TtsService(client: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response.bytes(<int>[1], 200);
    }));

    await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: 'Hello',
      voiceId: '',
    );
    await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: 'Hello',
      voiceId: 'vChnJZ1Cu89g2XXumPfT',
    );

    expect(bodies, hasLength(2));
    expect(bodies[0]['model_id'], 'eleven_multilingual_v2');
    expect(bodies[0], contains('voice_settings'));
    expect(bodies[1], {'text': 'Hello', 'model_id': 'eleven_flash_v2_5'});
  });

  test('explicit model override is honored without narrator settings',
      () async {
    late http.Request captured;
    final service = TtsService(client: MockClient((request) async {
      captured = request;
      return http.Response.bytes(<int>[1], 200);
    }));

    await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: 'Hello',
      model: 'eleven_turbo_v2_5',
    );

    expect(captured.url.path, '/v1/text-to-speech/vChnJZ1Cu89g2XXumPfT');
    expect(jsonDecode(captured.body), {
      'text': 'Hello',
      'model_id': 'eleven_turbo_v2_5',
    });
  });

  test('ElevenLabs TTS uses query output format and xi-api-key', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(<int>[1, 2, 3], 200);
    });
    final service = TtsService(client: client);

    final bytes = await service.generateSpeechElevenLabs(
      apiKey: 'unit-test-token',
      text: 'Hello there',
      voiceId: 'voice-id',
      model: 'eleven_flash_v2_5',
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(
      captured.url.toString(),
      'https://api.elevenlabs.io/v1/text-to-speech/voice-id?output_format=mp3_44100_128',
    );
    expect(captured.headers['xi-api-key'], 'unit-test-token');
    expect(captured.headers['accept'], 'audio/mpeg');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['text'], 'Hello there');
    expect(body['model_id'], 'eleven_flash_v2_5');
    expect(body, isNot(contains('output_format')));
  });

  test('ElevenLabs TTS surfaces list-shaped validation errors', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'detail': [
              {'msg': 'voice_id is invalid'}
            ]
          }),
          422,
          headers: {'content-type': 'application/json'},
        ));
    final service = TtsService(client: client);

    expect(
      () => service.generateSpeechElevenLabs(
        apiKey: 'unit-test-token',
        text: 'Hello',
        voiceId: 'invalid',
      ),
      throwsA(
        predicate<Object>(
            (error) => error.toString().contains('voice_id is invalid')),
      ),
    );
  });

  test('inaccessible narrator explains how to choose another Voice ID',
      () async {
    final service = TtsService(
        client: MockClient((request) async =>
            http.Response(jsonEncode({'detail': 'Voice not found'}), 404)));

    expect(
      () => service.generateSpeechElevenLabs(
        apiKey: 'unit-test-token',
        text: 'Hello',
      ),
      throwsA(predicate<Object>((error) =>
          error.toString().contains('Voice not found') &&
          error.toString().contains('TTS Voice ID in Settings'))),
    );
  });
}
