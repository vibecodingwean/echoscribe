import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/pages/history_page.dart';
import 'package:echoscribe/services/keyboard_ime_service.dart';
import 'package:echoscribe/services/floating_dictation_service.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ElevenLabs Keyboard STT exports Scribe v2 and the API key', () {
    final settings = SettingsState()
      ..setProvider(AiProviderType.elevenLabs)
      ..setElevenLabsKey('unit-test-token');

    final payload = KeyboardImeService.buildConfigPayload(settings);

    expect(payload['supportsDictation'], isTrue);
    expect(payload['enabled'], isTrue);
    expect(payload['apiKey'], 'unit-test-token');
    expect(payload['transcriptionModel'], 'scribe_v2');
    expect(payload['localAiLlmUrl'], '');
    expect(payload['localAiWhisperUrl'], '');
  });

  test('ElevenLabs Floating Dictation exports Scribe v2 and the API key', () {
    final settings = SettingsState()
      ..setProvider(AiProviderType.elevenLabs)
      ..setElevenLabsKey('unit-test-token')
      ..setFloatingDictationEnabled(true);

    final payload = FloatingDictationService.buildConfigPayload(settings);

    expect(payload['supportsDictation'], isTrue);
    expect(payload['floatingEnabled'], isTrue);
    expect(payload['apiKey'], 'unit-test-token');
    expect(payload['transcriptionModel'], 'scribe_v2');
    expect(payload['localAiLlmUrl'], '');
    expect(payload['localAiWhisperUrl'], '');
  });

  test('summary history loads as transcript when provider has no summaries',
      () {
    final content = ContentState();
    final settings = SettingsState()..setProvider(AiProviderType.elevenLabs);
    final item = TranscriptionItem(
      id: 'summary-1',
      text: 'Short summary',
      transcript: 'Full transcript',
      summary: 'Short summary',
      mode: OutputMode.summary.name,
      createdAt: DateTime.utc(2026, 8, 4),
    );

    loadHistoryItemForProvider(
      content: content,
      settings: settings,
      item: item,
    );

    expect(content.outputMode, OutputMode.transcription);
    expect(content.currentTranscriptValue, 'Full transcript');
    expect(content.currentSummaryValue, isEmpty);
  });
}
