

class TranscriptionItem {
  final String id;
  // Short preview or the text shown in the list (final text at save time)
  final String text;
  final DateTime createdAt;
  final Duration? duration;
  final String? language;

  // Extended fields to support loading back into the main view
  // The full transcript text (original/full content)
  final String? transcript;
  // The generated summary text (if any)
  final String? summary;
  // Mode at the time the item was created: 'transcription' | 'summary'
  final String? mode;

  const TranscriptionItem({
    required this.id,
    required this.text,
    required this.createdAt,
    this.duration,
    this.language,
    this.transcript,
    this.summary,
    this.mode,
  });

  TranscriptionItem copyWith({
    String? id,
    String? text,
    DateTime? createdAt,
    Duration? duration,
    String? language,
    String? transcript,
    String? summary,
    String? mode,
  }) {
    return TranscriptionItem(
      id: id ?? this.id,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      duration: duration ?? this.duration,
      language: language ?? this.language,
      transcript: transcript ?? this.transcript,
      summary: summary ?? this.summary,
      mode: mode ?? this.mode,
    );
  }

  factory TranscriptionItem.sample(int i) => TranscriptionItem(
        id: 'sample_$i',
        text: 'Sample transcription #$i: The quick brown fox jumps over the lazy dog.',
        createdAt: DateTime.now().subtract(Duration(minutes: i * 5)),
        duration: Duration(seconds: 12 + i),
        language: 'en',
        transcript: 'Sample transcription #$i: The quick brown fox jumps over the lazy dog.',
        summary: null,
        mode: 'transcription',
      );
}
