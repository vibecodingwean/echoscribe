import 'package:echoscribe/config/prompts.dart';

import 'speaker_models.dart';

const String kNativeSpeakerSummaryPrompt =
    'Summarize the following transcript into a structured, concise, and neutral summary.\n'
    '\n'
    'Guidelines:\n'
    '- The transcript already contains native speaker labels in the form "Speaker N:".\n'
    '- PRESERVE those exact Speaker N labels when attributing viewpoints, questions, and decisions.\n'
    '- Do NOT invent extra speakers or rename existing ones (no Speaker A/B unless already present).\n'
    '- Capture key outcomes, actions, or follow-ups if discussed.\n'
    '- If the text appears to be a personal note or monologue, focus only on the core ideas, insights, or intentions.\n'
    '- Skip filler words, small talk, and redundant statements.\n'
    '\n'
    'Formatting:\n'
    '- Do not start with meta-phrases like "This transcript..." or "The text says...".\n'
    '- Return only the summary content.';

const String kNativeSpeakerInstruction =
    'The transcript already uses native "Speaker N:" labels. Preserve those labels; '
    'do not invent extra speakers or rename them.';

class SpeakerAwareSummary {
  static final RegExp nativeSpeakerLine =
      RegExp(r'^Speaker \d+:', multiLine: true);

  static bool hasNativeSpeakerLabels(String text) =>
      nativeSpeakerLine.hasMatch(text);

  /// Picks the summary prompt based on native speaker labels / source.
  ///
  /// - Default prompt + native labels → dedicated preserve-labels prompt
  /// - Custom prompt + native labels → append a short native-speaker instruction
  /// - Otherwise keep existing default / custom behavior unchanged
  static String resolvePrompt({
    required String text,
    String? summaryPrompt,
    SpeakerSource source = SpeakerSource.none,
  }) {
    final trimmed = summaryPrompt?.trim() ?? '';
    final usingDefault =
        trimmed.isEmpty || trimmed == kDefaultSummaryPrompt;
    final hasNative = source == SpeakerSource.nativeApi ||
        hasNativeSpeakerLabels(text);

    if (!hasNative) {
      return usingDefault ? kDefaultSummaryPrompt : trimmed;
    }

    if (usingDefault) return kNativeSpeakerSummaryPrompt;
    return '$trimmed\n\n$kNativeSpeakerInstruction';
  }
}
