enum AiProviderType {
  openai,
  gemini,
  anthropic;

  /// Menschenlesbarer Markenname für Logs und UI
  String get brandName {
    switch (this) {
      case AiProviderType.openai: return 'GPT';
      case AiProviderType.gemini: return 'Gemini';
      case AiProviderType.anthropic: return 'Claude';
    }
  }

  /// Für SecureStorage-Kompatibilität (lesen/schreiben als String)
  static AiProviderType fromString(String s) {
    switch (s) {
      case 'gemini': return AiProviderType.gemini;
      case 'anthropic': return AiProviderType.anthropic;
      default: return AiProviderType.openai;
    }
  }
}

enum OutputMode {
  transcription,
  summary;

  static OutputMode fromString(String s) {
    if (s == 'summary') return OutputMode.summary;
    return OutputMode.transcription;
  }
}
