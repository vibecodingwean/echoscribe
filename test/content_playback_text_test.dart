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

  test('transcript playback omits web addresses but keeps spoken words', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setCurrentTranscript(
      'Mehr dazu auf https://example.com/article?q=1. Morgen sprechen wir weiter.',
    );

    expect(content.currentPlaybackText,
        'Mehr dazu auf. Morgen sprechen wir weiter.');
    content.setCurrentTranscript('https://example.com/article');
    expect(content.currentPlaybackText, isEmpty);
    expect(content.canPlayTts(AiProviderType.openai), isFalse);
  });

  test('plain transcript preserves dates and comparisons', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setCurrentTranscript(
      '10. Oktober 2026 war ein guter Tag. Der Wert ist <b und >a.',
    );
    expect(content.currentPlaybackText,
        '10. Oktober 2026 war ein guter Tag. Der Wert ist <b und >a.');
  });

  test('full bracketed URL is omitted from transcript playback', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setCurrentTranscript(
      'Siehe https://example.com/search?filter[year]=2026&token=secret.',
    );
    expect(content.currentPlaybackText, 'Siehe.');
    content.setCurrentTranscript('https://[2001:db8::1]/article?token=secret');
    expect(content.currentPlaybackText, isEmpty);
    expect(content.canPlayTts(AiProviderType.openai), isFalse);
    content.setCurrentTranscript('https://example.com/article.');
    expect(content.currentPlaybackText, isEmpty);
    expect(content.canPlayTts(AiProviderType.openai), isFalse);
  });

  test('plain summary preserves dates and comparisons', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setOutputMode(OutputMode.summary);
    content.setCurrentSummary(
      '10. Oktober 2026 war ein guter Tag. Der Wert ist <b und >a.',
    );
    expect(content.currentPlaybackText,
        '10. Oktober 2026 war ein guter Tag. Der Wert ist <b und >a.');
  });

  test('summary playback speaks headings and content without markup', () {
    final content = ContentState(historyWriter: (_) async {});
    addTearDown(content.dispose);
    content.setOutputMode(OutputMode.summary);
    content.setCurrentSummary('''## 🏠 Hausaufgaben
**Mathe:** Aufgaben 1–3. 10. Oktober bleibt. Der Wert ist <b und >a.

<h2>Weitere Schritte</h2>
Besuche [die Kursseite](https://example.com/course) für Details.''');

    expect(content.currentPlaybackText,
        '🏠 Hausaufgaben Mathe: Aufgaben 1–3. 10. Oktober bleibt. Der Wert ist <b und >a. Weitere Schritte Besuche die Kursseite für Details.');
  });
}
