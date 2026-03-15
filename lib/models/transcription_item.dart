

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

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (language != null) 'language': language,
    if (transcript != null) 'transcript': transcript,
    if (summary != null) 'summary': summary,
    if (mode != null) 'mode': mode,
  };

  factory TranscriptionItem.fromJson(Map<String, dynamic> json) => TranscriptionItem(
    id: json['id'] as String,
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    duration: json['durationMs'] != null ? Duration(milliseconds: json['durationMs'] as int) : null,
    language: json['language'] as String?,
    transcript: json['transcript'] as String?,
    summary: json['summary'] as String?,
    mode: json['mode'] as String?,
  );
}
