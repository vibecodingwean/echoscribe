enum SpeakerSource {
  none,
  nativeApi,
  syntheticSummary,
}

class SpeakerTurn {
  const SpeakerTurn({
    required this.speaker,
    required this.text,
    this.startSec,
  });

  final String speaker;
  final String text;
  final double? startSec;
}

class SpeakerLabeledTranscript {
  const SpeakerLabeledTranscript({
    required this.text,
    required this.source,
    this.turns = const [],
  });

  final String text;
  final SpeakerSource source;
  final List<SpeakerTurn> turns;
}

/// Dedicated Gemini file STT (`gemini-3.5-transcribe`) supports native diarization.
/// Live (`-live`) may omit meeting diarization; still parse labels if present.
bool modelSupportsNativeSpeakers(String modelId) {
  final id = modelId.trim().toLowerCase();
  if (!id.contains('3.5-transcribe')) return false;
  if (id.contains('-live')) return false;
  return true;
}

bool isGeminiDedicatedTranscribeModel(String modelId) {
  final id = modelId.trim().toLowerCase();
  if (!id.contains('3.5-transcribe')) return false;
  if (id.contains('-live')) return false;
  return true;
}
