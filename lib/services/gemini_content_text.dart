import 'dart:convert';

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

  static String sanitizeResponseForDebug(String body) {
    try {
      final data = json.decode(body);
      if (data is! Map) return '[Gemini response body omitted]';
      return json.encode(_withoutThoughts(data));
    } catch (_) {
      return '[Gemini response body omitted]';
    }
  }

  static dynamic _withoutThoughts(dynamic value) {
    if (value is Map) {
      if (value['thought'] == true) return null;
      return value.map((key, entry) => MapEntry(key, _withoutThoughts(entry)));
    }
    if (value is List) {
      return value
          .where((entry) => entry is! Map || entry['thought'] != true)
          .map(_withoutThoughts)
          .toList();
    }
    return value;
  }

  static bool looksLikeApiEnvelope(String text) {
    return text.contains('"finishReason"') && text.contains('"usageMetadata"');
  }

  static Map<String, dynamic> thinkingOffConfig() {
    return {
      'thinkingConfig': {
        'thinkingBudget': 0,
      },
    };
  }

  static Map<String, dynamic> generationConfigForModel(String model) =>
      model == 'gemini-3.1-pro-preview'
          ? <String, dynamic>{}
          : {'generationConfig': thinkingOffConfig()};
}
