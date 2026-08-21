enum AiProviderType {
  openai,
  gemini,
  anthropic,
  xai,
  localAi,
  elevenLabs;

  /// Human-readable brand name for logs and UI.
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
      case AiProviderType.localAi:
        return 'Local AI';
      case AiProviderType.elevenLabs:
        return 'ElevenLabs';
    }
  }

  /// Whether the main microphone flow can record/transcribe with this provider.
  bool get supportsAudio {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
      case AiProviderType.localAi:
      case AiProviderType.elevenLabs:
        return true;
      case AiProviderType.anthropic:
        return false;
    }
  }

  /// Whether uploaded/shared audio files can be transcribed.
  bool get supportsBatchTranscription {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
      case AiProviderType.localAi:
        return true;
      case AiProviderType.anthropic:
      case AiProviderType.elevenLabs:
        return false;
    }
  }

  /// Whether microphone audio can be streamed as realtime transcription.
  bool get supportsRealtimeTranscription =>
      this == AiProviderType.openai || this == AiProviderType.elevenLabs;

  /// Whether this provider supports text-to-speech playback.
  bool get supportsTts {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
      case AiProviderType.elevenLabs:
        return true;
      case AiProviderType.localAi:
      case AiProviderType.anthropic:
        return false;
    }
  }

  bool get supportsSummary => this != AiProviderType.elevenLabs;

  bool get supportsTranslation => this != AiProviderType.elevenLabs;

  bool get supportsKeyboardDictation =>
      this == AiProviderType.openai ||
      this == AiProviderType.gemini ||
      this == AiProviderType.xai ||
      this == AiProviderType.localAi;

  bool get supportsFloatingDictation => supportsKeyboardDictation;

  /// Whether this provider REQUIRES local URL content extraction.
  bool get mustExtractUrl {
    switch (this) {
      case AiProviderType.anthropic:
      case AiProviderType.xai:
      case AiProviderType.localAi:
        return true;
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.elevenLabs:
        return false;
    }
  }

  /// Whether this provider supports image generation.
  bool get supportsImage {
    switch (this) {
      case AiProviderType.openai:
      case AiProviderType.gemini:
      case AiProviderType.xai:
        return true;
      case AiProviderType.localAi:
      case AiProviderType.anthropic:
      case AiProviderType.elevenLabs:
        return false;
    }
  }

  /// For SecureStorage compatibility (read/write as String).
  static AiProviderType fromString(String s) {
    switch (s) {
      case 'gemini':
        return AiProviderType.gemini;
      case 'anthropic':
        return AiProviderType.anthropic;
      case 'xai':
        return AiProviderType.xai;
      case 'localAi':
      case 'local_ai':
      case 'local-ai':
        return AiProviderType.localAi;
      case 'elevenlabs':
      case 'elevenLabs':
      case 'eleven_labs':
      case 'eleven-labs':
        return AiProviderType.elevenLabs;
      default:
        return AiProviderType.openai;
    }
  }
}

bool providerSupportsRealtimeOnPlatform(
  AiProviderType provider, {
  required bool isWeb,
}) {
  if (!provider.supportsRealtimeTranscription) return false;
  return provider != AiProviderType.elevenLabs || !isWeb;
}

enum OutputMode {
  transcription,
  summary;

  static OutputMode fromString(String s) {
    if (s == 'summary') return OutputMode.summary;
    return OutputMode.transcription;
  }
}
