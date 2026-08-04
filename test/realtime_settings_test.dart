import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime mode is scoped to the selected provider', () {
    final settings = SettingsState();

    settings.setOpenAiRealtime(true);
    expect(settings.openAiRealtime, isTrue);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.gemini);
    expect(settings.openAiRealtime, isTrue);
    expect(settings.realtimeEnabled, isFalse);

    settings.setProvider(AiProviderType.elevenLabs);
    expect(settings.elevenLabsRealtime, isTrue);
    expect(settings.realtimeEnabled, isTrue);

    settings.setProvider(AiProviderType.openai);
    expect(settings.realtimeEnabled, isTrue);
  });
}
