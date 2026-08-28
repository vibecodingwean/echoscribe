import 'speaker_models.dart';

class NativeSpeakerFormatter {
  static final RegExp _spkLabel = RegExp(r'^spk[_\s-]?(\d+)$', caseSensitive: false);
  static final RegExp _speakerLabel =
      RegExp(r'^speaker\s*(\d+)$', caseSensitive: false);

  /// Formats turns as `Speaker N: ...`, merging consecutive same-speaker turns.
  static String format(List<SpeakerTurn> turns) {
    if (turns.isEmpty) return '';

    final buffer = StringBuffer();
    String? currentSpeaker;
    final currentText = StringBuffer();

    void flush() {
      final text = currentText.toString().trim();
      if (currentSpeaker == null || text.isEmpty) return;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write('$currentSpeaker: $text');
      currentText.clear();
    }

    for (final turn in turns) {
      final speaker = normalizeSpeakerLabel(turn.speaker);
      final text = turn.text.trim();
      if (text.isEmpty) continue;
      if (speaker == currentSpeaker) {
        if (currentText.isNotEmpty) currentText.write(' ');
        currentText.write(text);
      } else {
        flush();
        currentSpeaker = speaker;
        currentText.write(text);
      }
    }
    flush();
    return buffer.toString().trim();
  }

  /// Maps API labels like `spk_1` / `Speaker 1` to canonical `Speaker 1`.
  static String normalizeSpeakerLabel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Speaker 1';

    final spk = _spkLabel.firstMatch(trimmed);
    if (spk != null) return 'Speaker ${spk.group(1)}';

    final speaker = _speakerLabel.firstMatch(trimmed);
    if (speaker != null) return 'Speaker ${speaker.group(1)}';

    final digits = RegExp(r'(\d+)').firstMatch(trimmed);
    if (digits != null) return 'Speaker ${digits.group(1)}';

    return trimmed.startsWith('Speaker ') ? trimmed : 'Speaker $trimmed';
  }
}
