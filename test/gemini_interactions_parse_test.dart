import 'package:echoscribe/services/gemini_service.dart';
import 'package:echoscribe/services/speakers/speaker_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses interactions fixture with word_info speakers', () {
    final payload = <String, dynamic>{
      'output_text': 'Hello there Hi',
      'steps': [
        {
          'content': [
            {
              'type': 'text',
              'text': 'Hello there Hi',
              'annotations': [
                {
                  'type': 'word_info',
                  'text': 'Hello',
                  'speaker': 'spk_1',
                  'start_offset': '0.100s',
                },
                {
                  'type': 'word_info',
                  'text': 'there',
                  'speaker': 'spk_1',
                  'start_offset': '0.400s',
                },
                {
                  'type': 'word_info',
                  'text': 'Hi',
                  'speaker': 'spk_2',
                  'start_offset': '1.000s',
                },
              ],
            },
          ],
        },
      ],
    };

    final labeled = GeminiService.parseInteractionsTranscript(payload);
    expect(labeled.source, SpeakerSource.nativeApi);
    expect(labeled.text, 'Speaker 1: Hello there\nSpeaker 2: Hi');
    expect(labeled.turns, hasLength(2));
    expect(labeled.turns.first.speaker, 'Speaker 1');
    expect(labeled.turns.first.startSec, closeTo(0.1, 0.0001));
  });

  test('falls back to output_text when annotations lack speakers', () {
    final payload = <String, dynamic>{
      'output_text': 'Plain transcript only',
      'steps': [
        {
          'content': [
            {
              'text': 'Plain transcript only',
              'annotations': [
                {'type': 'word_info', 'text': 'Plain'},
              ],
            },
          ],
        },
      ],
    };

    final labeled = GeminiService.parseInteractionsTranscript(payload);
    expect(labeled.source, SpeakerSource.none);
    expect(labeled.text, 'Plain transcript only');
  });

  test('reads steps content when output_text is absent', () {
    final labeled = GeminiService.parseInteractionsTranscript({
      'status': 'completed',
      'steps': [
        {
          'type': 'text',
          'content': [
            {'type': 'text', 'text': 'Hello from steps'},
          ],
        },
      ],
    });
    expect(labeled.source, SpeakerSource.none);
    expect(labeled.text, 'Hello from steps');
  });
}
