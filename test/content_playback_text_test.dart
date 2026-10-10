import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TTS follows the selected transcript or summary', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setCurrentTranscript('  Spoken words  ');
    content.setCurrentSummary('  Short summary  ');

    expect(content.currentPlaybackText, 'Spoken words');
    expect(content.canPlayTts(AiProviderType.openai), isTrue);
    expect(content.canPlayTts(AiProviderType.gemini), isTrue);
    expect(content.canPlayTts(AiProviderType.xai), isTrue);
    expect(content.canPlayTts(AiProviderType.elevenLabs), isTrue);
    expect(content.canPlayTts(AiProviderType.anthropic), isFalse);

    content.setOutputMode(OutputMode.summary);
    expect(content.currentPlaybackText, 'Short summary');
    expect(content.canPlayTts(AiProviderType.openai), isTrue);
    content.setCurrentSummary('  ');
    expect(content.canPlayTts(AiProviderType.openai), isFalse);
    expect(content.currentPlaybackText, isEmpty);
  });
}
