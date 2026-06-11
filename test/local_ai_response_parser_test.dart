import 'package:echoscribe/services/local_ai_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Ollama chat message content', () {
    final text = LocalAiResponseParser.ollamaMessageContent(
      '{"message":{"role":"assistant","content":" summary text "},"done":true}',
    );

    expect(text, 'summary text');
  });

  test('parses OpenAI-compatible Whisper text', () {
    final text = LocalAiResponseParser.whisperText(
      '{"text":" transcribed text "}',
    );

    expect(text, 'transcribed text');
  });
}
