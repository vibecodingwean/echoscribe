import 'dart:convert';

import 'package:echoscribe/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Gemini TTS requests Interactions audio and decodes its WAV', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
          jsonEncode({
            'steps': [
              {
                'type': 'model_output',
                'content': [
                  {
                    'type': 'audio',
                    'data': base64Encode(<int>[82, 73, 70, 70])
                  }
                ]
              }
            ]
          }),
          200);
    });
    final result = await TtsService(client: client).generateSpeechGemini(
        apiKey: 'unit-test-key', text: 'Hallo', voice: 'Kore');
    expect(result, <int>[82, 73, 70, 70]);
    expect(captured.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/interactions');
    expect(captured.headers['x-goog-api-key'], 'unit-test-key');
    expect(captured.url.query, isEmpty);
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'gemini-3.8-flash-tts');
    expect(body['store'], isFalse);
    expect(body['response_format'], {'type': 'audio'});
    expect(body['generation_config'], {
      'speech_config': [
        {'voice': 'Kore'}
      ]
    });
  });
}
