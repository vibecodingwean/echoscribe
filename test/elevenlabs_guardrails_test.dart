import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/pages/history_page.dart';
import 'package:echoscribe/services/keyboard_ime_service.dart';
import 'package:echoscribe/services/floating_dictation_service.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unsupported Keyboard STT provider exports no credential', () {
    final settings = SettingsState()
      ..setProvider(AiProviderType.elevenLabs)
      ..setElevenLabsKey('unit-test-token');

    final payload = KeyboardImeService.buildConfigPayload(settings);

    expect(payload['supportsDictation'], isFalse);
    expect(payload['enabled'], isFalse);
    expect(payload['apiKey'], '');
    expect(payload['localAiLlmUrl'], '');
    expect(payload['localAiWhisperUrl'], '');
  });

  test('unsupported Floating Dictation provider exports no credential', () {
    final settings = SettingsState()
      ..setProvider(AiProviderType.elevenLabs)
      ..setElevenLabsKey('unit-test-token')
      ..setFloatingDictationEnabled(true);

    final payload = FloatingDictationService.buildConfigPayload(settings);

    expect(payload['supportsDictation'], isFalse);
    expect(payload['floatingEnabled'], isFalse);
    expect(payload.containsKey('enabled'), isFalse);
    expect(payload['apiKey'], '');
    expect(payload['localAiLlmUrl'], '');
    expect(payload['localAiWhisperUrl'], '');
  });

  test('ElevenLabs realtime recording is available on Android', () {
    expect(
      AiProviderType.elevenLabs.supportsRealtimeTranscription,
      isTrue,
    );
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
