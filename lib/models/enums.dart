enum AiProviderType {
  openai,
  gemini,
  anthropic,
  xai;

  /// Human-readable brand name for logs and UI
  String get brandName {
    switch (this) {
      case AiProviderType.openai:
        return 'GPT';
      case AiProviderType.gemini:
        return 'Gemini';
      case AiProviderType.anthropic:
        return 'Claude';
      case AiProviderType.xai:
        return 'Grok';
    }
  }

  /// Whether this provider supports audio recording/transcription
  bool get supportsAudio {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
        return true;
      case AiProviderType.anthropic:
      case AiProviderType.xai:
        return false;
    }
  }

  /// Whether this provider supports text-to-speech playback
  bool get supportsTts {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
        return true;
      case AiProviderType.anthropic:
        return false;
    }
  }

  /// Whether this provider REQUIRES local URL content extraction (cannot handle naked URLs reliably)
  bool get mustExtractUrl {
    switch (this) {
      case AiProviderType.anthropic:
      case AiProviderType.xai:
        return true;
      case AiProviderType.openai:
      case AiProviderType.gemini:
        return false;
    }
  }

  /// Whether this provider supports image generation
  bool get supportsImage {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
        return true;
      case AiProviderType.anthropic:
        return false;
    }
  }

  /// For SecureStorage compatibility (read/write as String)
  static AiProviderType fromString(String s) {
    switch (s) {
      case 'gemini':
        return AiProviderType.gemini;
      case 'anthropic':
        return AiProviderType.anthropic;
      case 'xai':
        return AiProviderType.xai;
      default:
        return AiProviderType.openai;
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
