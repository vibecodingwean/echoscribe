import 'dart:convert';

import 'package:echoscribe/services/xai_speech_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('xAI batch transcription sends the selected model', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'text': 'Erkannt'}), 200);
    });
    final result = await XaiSpeechService(client: client).transcribe(
      apiKey: 'unit-test-key',
      model: 'grok-voice-transcribe-2.0',
      fileBytes: <int>[1, 2, 3],
      fileName: 'synthetic.wav',
    );
    expect(result, 'Erkannt');
    expect(captured.url.toString(), 'https://api.x.ai/v1/stt');
    expect(captured.body, contains('name="model"'));
    expect(captured.body, contains('grok-voice-transcribe-2.0'));
    expect(captured.body, contains('name="format"'));
    expect(captured.body, contains('false'));
  });
}
