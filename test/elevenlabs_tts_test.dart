import 'dart:convert';

import 'package:echoscribe/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
}
