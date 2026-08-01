import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime transcription engines are mutually exclusive', () {
    final settings = SettingsState();

    settings.setOpenAiRealtime(true);
    expect(settings.openAiRealtime, isTrue);
    expect(settings.elevenLabsRealtime, isFalse);
    expect(settings.realtimeEnabled, isTrue);

    settings.setElevenLabsRealtime(true);
    expect(settings.openAiRealtime, isFalse);
    expect(settings.elevenLabsRealtime, isTrue);

    settings.setElevenLabsRealtime(false);
    expect(settings.realtimeEnabled, isFalse);
  });
}
