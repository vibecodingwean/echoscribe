import "package:flutter/material.dart";
import "package:echoscribe/config/prompts.dart";
import "package:echoscribe/models/enums.dart";

class SettingsState extends ChangeNotifier {
  bool _debugMode = false;
  AiProviderType _provider = AiProviderType.openai;
  String _openAiKey = "";
  String _geminiKey = "";
  String _anthropicKey = "";
  String _xaiKey = "";
  String _elevenLabsKey = "";
  String _elevenLabsVoiceId = "";
  String _localAiLlmUrl = AiModelConfig.localAiLlmUrl;
  String _localAiLlmModel = AiModelConfig.localAiLlmModel;
  String _localAiWhisperUrl = AiModelConfig.localAiWhisperUrl;
  String _localAiWhisperModel = AiModelConfig.localAiWhisperModel;
  bool _openAiPro = false;
  bool _openAiRealtime = false;
  bool _elevenLabsRealtime = false;

  bool _geminiPro = false;
  bool _anthropicPro = false;
  bool _xaiPro = false;
  bool _appFetchUrl = true;
  bool _floatingDictationEnabled = true;
  String _voiceMode = "google";
  String _keyboardLayout = "qwertz";
  bool _autocorrectEnabled = true;
  bool _autoCapitalizeEnabled = true;
  bool _hapticFeedbackEnabled = true;
  bool _soundFeedbackEnabled = true;
  bool _opticalFeedbackEnabled = true;
  List<Map<String, String>> _customTones = const [];
  List<Map<String, String>> _customGrammar = const [];
  List<Map<String, String>> _customAssistants = const [];
  String _targetLanguageCode = "auto";
  String _summaryPrompt = kDefaultSummaryPrompt;
  String _urlSummaryPrompt = kDefaultUrlSummaryPrompt;
  String _dictationPrompt = kDefaultDictationPrompt;
  String _lastSharedIntentId = "";

  bool get debugMode => _debugMode;
  void setDebugMode(bool enabled) {
    _debugMode = enabled;
    notifyListeners();
  }

  AiProviderType get provider => _provider;
  void setProvider(AiProviderType p) {
    _provider = p;
    if (!p.supportsTranslation) _targetLanguageCode = 'auto';
    notifyListeners();
  }

  String get openAiKey => _openAiKey;
  String get geminiKey => _geminiKey;
  String get anthropicKey => _anthropicKey;
  String get xaiKey => _xaiKey;
  String get elevenLabsKey => _elevenLabsKey;
  String get elevenLabsVoiceId => _elevenLabsVoiceId;
  String get localAiLlmUrl => _localAiLlmUrl;
  String get localAiLlmModel => _localAiLlmModel;
  String get localAiWhisperUrl => _localAiWhisperUrl;
  String get localAiWhisperModel => _localAiWhisperModel;

  void setOpenAiKey(String key) {
    _openAiKey = key.trim();
    notifyListeners();
  }

  void setGeminiKey(String key) {
    _geminiKey = key.trim();
    notifyListeners();
  }

  void setAnthropicKey(String key) {
    _anthropicKey = key.trim();
    notifyListeners();
  }

  void setXaiKey(String key) {
    _xaiKey = key.trim();
    notifyListeners();
  }

  void setElevenLabsKey(String key) {
    _elevenLabsKey = key.trim();
    notifyListeners();
  }

  void setElevenLabsVoiceId(String voiceId) {
    _elevenLabsVoiceId = voiceId.trim();
    notifyListeners();
  }

  void setLocalAiLlmUrl(String value) {
    _localAiLlmUrl = value.trim();
    notifyListeners();
  }

  void setLocalAiLlmModel(String value) {
    final trimmed = value.trim();
    _localAiLlmModel = trimmed.isEmpty || trimmed == 'qwen3'
        ? AiModelConfig.localAiLlmModel
        : trimmed;
    notifyListeners();
  }

  void setLocalAiWhisperUrl(String value) {
    _localAiWhisperUrl = value.trim();
    notifyListeners();
  }

  void setLocalAiWhisperModel(String value) {
    _localAiWhisperModel =
        value.trim().isEmpty ? AiModelConfig.localAiWhisperModel : value.trim();
    notifyListeners();
  }

  String get activeApiKey {
    if (_provider == AiProviderType.localAi) return "";
    if (_provider == AiProviderType.elevenLabs) return _elevenLabsKey;
    if (_provider == AiProviderType.gemini) return _geminiKey;
    if (_provider == AiProviderType.anthropic) return _anthropicKey;
    if (_provider == AiProviderType.xai) return _xaiKey;
    return _openAiKey;
  }

  bool get hasActiveApiKey {
    if (_provider == AiProviderType.localAi) {
      return _localAiLlmUrl.trim().isNotEmpty &&
          _localAiWhisperUrl.trim().isNotEmpty;
    }
    return activeApiKey.isNotEmpty;
  }

  String get missingProviderConfigMessage {
    if (_provider == AiProviderType.localAi) {
      return 'Configure Local AI endpoints first';
    }
    return 'Add your API key first';
  }

  bool get hasOpenAiKey => _openAiKey.isNotEmpty;
  bool get hasGeminiKey => _geminiKey.isNotEmpty;
  bool get hasAnthropicKey => _anthropicKey.isNotEmpty;
  bool get hasXaiKey => _xaiKey.isNotEmpty;

  bool get openAiPro => _openAiPro;
  bool get openAiRealtime => _openAiRealtime;
  bool get elevenLabsRealtime => _elevenLabsRealtime;
  bool get realtimeEnabled =>
      (_provider == AiProviderType.openai && _openAiRealtime) ||
      (_provider == AiProviderType.elevenLabs && _elevenLabsRealtime);
  bool get geminiPro => _geminiPro;
  bool get anthropicPro => _anthropicPro;
  bool get xaiPro => _xaiPro;

  String get summaryModel {
    switch (_provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiSummary(pro: _geminiPro);
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicSummary(pro: _anthropicPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiSummary(pro: _xaiPro);
      case AiProviderType.localAi:
        return _localAiLlmModel;
      case AiProviderType.openai:
        return AiModelConfig.openAiSummary(pro: _openAiPro);
      case AiProviderType.elevenLabs:
        return '';
    }
  }

  String get transcriptionModel {
    switch (_provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiTranscription(pro: _geminiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiTranscription(pro: _xaiPro);
      case AiProviderType.localAi:
        return _localAiWhisperModel;
      case AiProviderType.openai:
      case AiProviderType.anthropic:
        return AiModelConfig.openAiTranscription(pro: _openAiPro);
      case AiProviderType.elevenLabs:
        return AiModelConfig.elevenLabsTranscription;
    }
  }

  String get translationModel {
    switch (_provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiTranslation(pro: _geminiPro);
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicTranslation(pro: _anthropicPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiTranslation(pro: _xaiPro);
      case AiProviderType.localAi:
        return _localAiLlmModel;
      case AiProviderType.openai:
        return AiModelConfig.openAiTranslation(pro: _openAiPro);
      case AiProviderType.elevenLabs:
        return '';
    }
  }

  String? get reasoningEffort {
    switch (_provider) {
      case AiProviderType.openai:
        return AiModelConfig.openAiReasoningEffort(pro: _openAiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiReasoningEffort(pro: _xaiPro);
      case AiProviderType.gemini:
      case AiProviderType.anthropic:
      case AiProviderType.localAi:
      case AiProviderType.elevenLabs:
        return null;
    }
  }

  String get imageModel {
    switch (_provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiImage(pro: true);
      case AiProviderType.xai:
        return AiModelConfig.xaiImage(pro: true);
      case AiProviderType.openai:
        return AiModelConfig.openAiImage(pro: true);
      case AiProviderType.localAi:
      case AiProviderType.anthropic:
      case AiProviderType.elevenLabs:
        return '';
    }
  }

  String get ttsVoice {
    switch (_provider) {
      case AiProviderType.gemini:
        return 'Zephyr';
      case AiProviderType.xai:
        return 'eve';
      case AiProviderType.elevenLabs:
        return _elevenLabsVoiceId.isEmpty
            ? AiModelConfig.elevenLabsTtsVoice
            : _elevenLabsVoiceId;
      default:
        return 'alloy';
    }
  }

  void setOpenAiPro(bool enabled) {
    _openAiPro = enabled;
    notifyListeners();
  }

  void setOpenAiRealtime(bool enabled) {
    _openAiRealtime = enabled;
    notifyListeners();
  }

  void setElevenLabsRealtime(bool enabled) {
    _elevenLabsRealtime = enabled;
    notifyListeners();
  }

  void setGeminiPro(bool enabled) {
    _geminiPro = enabled;
    notifyListeners();
  }

  void setAnthropicPro(bool enabled) {
    _anthropicPro = enabled;
    notifyListeners();
  }

  void setXaiPro(bool enabled) {
    _xaiPro = enabled;
    notifyListeners();
  }

  bool get appFetchUrl => _appFetchUrl;
  void setAppFetchUrl(bool enabled) {
    _appFetchUrl = enabled;
    notifyListeners();
  }

  bool get floatingDictationEnabled => _floatingDictationEnabled;
  void setFloatingDictationEnabled(bool enabled) {
    _floatingDictationEnabled = enabled;
    notifyListeners();
  }

  String get voiceMode => _voiceMode;
  void setVoiceMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    _voiceMode = normalized == 'echoscribe' ? 'echoscribe' : 'google';
    notifyListeners();
  }

  String get keyboardLayout => _keyboardLayout;
  void setKeyboardLayout(String layout) {
    final normalized = layout.trim().toLowerCase();
    _keyboardLayout = normalized == 'qwerty' ? 'qwerty' : 'qwertz';
    notifyListeners();
  }

  bool get autocorrectEnabled => _autocorrectEnabled;
  void setAutocorrectEnabled(bool enabled) {
    _autocorrectEnabled = enabled;
    notifyListeners();
  }

  bool get autoCapitalizeEnabled => _autoCapitalizeEnabled;
  void setAutoCapitalizeEnabled(bool enabled) {
    _autoCapitalizeEnabled = enabled;
    notifyListeners();
  }

  bool get hapticFeedbackEnabled => _hapticFeedbackEnabled;
  void setHapticFeedbackEnabled(bool enabled) {
    _hapticFeedbackEnabled = enabled;
    notifyListeners();
  }

  bool get soundFeedbackEnabled => _soundFeedbackEnabled;
  void setSoundFeedbackEnabled(bool enabled) {
    _soundFeedbackEnabled = enabled;
    notifyListeners();
  }

  bool get opticalFeedbackEnabled => _opticalFeedbackEnabled;
  void setOpticalFeedbackEnabled(bool enabled) {
    _opticalFeedbackEnabled = enabled;
    notifyListeners();
  }

  List<Map<String, String>> get customTones =>
      List<Map<String, String>>.unmodifiable(
        _customTones.map(Map<String, String>.from),
      );
  void setCustomTones(List<Map<String, String>> tones) {
    _customTones = tones.map(Map<String, String>.from).toList();
    notifyListeners();
  }

  List<Map<String, String>> get customGrammar =>
      List<Map<String, String>>.unmodifiable(
        _customGrammar.map(Map<String, String>.from),
      );
  void setCustomGrammar(List<Map<String, String>> grammar) {
    _customGrammar = grammar.map(Map<String, String>.from).toList();
    notifyListeners();
  }

  List<Map<String, String>> get customAssistants =>
      List<Map<String, String>>.unmodifiable(
        _customAssistants.map(Map<String, String>.from),
      );
  void setCustomAssistants(List<Map<String, String>> assistants) {
    _customAssistants = assistants.map(Map<String, String>.from).toList();
    notifyListeners();
  }

  String get targetLanguageCode => _targetLanguageCode;
  void setTargetLanguageCode(String code) {
    _targetLanguageCode = _provider.supportsTranslation ? code : 'auto';
    notifyListeners();
  }

  String get summaryPrompt => _summaryPrompt;
  void setSummaryPrompt(String prompt) {
    _summaryPrompt = prompt.trim();
    notifyListeners();
  }

  String get urlSummaryPrompt => _urlSummaryPrompt;
  void setUrlSummaryPrompt(String prompt) {
    _urlSummaryPrompt = prompt.trim();
    notifyListeners();
  }

  String get dictationPrompt => _dictationPrompt;
  void setDictationPrompt(String prompt) {
    _dictationPrompt = prompt.trim();
    notifyListeners();
  }

  String get lastSharedIntentId => _lastSharedIntentId;
  void setLastSharedIntentId(String id) {
    _lastSharedIntentId = id;
    notifyListeners();
  }
}
