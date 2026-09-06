class GeminiContentText {
  const GeminiContentText._();

  /// Visible model text from a generateContent JSON body.
  /// Skips `thought` parts used by Gemini 3.7+ thinking.
  static String extract(Map<String, dynamic> data) {
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final first = candidates.first;
    if (first is! Map) return '';
    final content = first['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) return '';

    final chunks = <String>[];
    for (final part in parts) {
      if (part is! Map) continue;
      if (part['thought'] == true) continue;
      final text = part['text'];
      if (text is String && text.trim().isNotEmpty) {
        chunks.add(text.trim());
      }
    }
    final joined = chunks.join('\n').trim();
    if (looksLikeApiEnvelope(joined)) return '';
    return joined;
  }

  static bool looksLikeApiEnvelope(String text) {
    return text.contains('"finishReason"') &&
        text.contains('"usageMetadata"');
  }

  static Map<String, dynamic> thinkingOffConfig() {
    return {
      'thinkingConfig': {
        'thinkingBudget': 0,
      },
    };
  }
}
