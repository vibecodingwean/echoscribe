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
  String _localAiLlmUrl = AiModelConfig.localAiLlmUrl;
  String _localAiLlmModel = AiModelConfig.localAiLlmModel;
  String _localAiWhisperUrl = AiModelConfig.localAiWhisperUrl;
  String _localAiWhisperModel = AiModelConfig.localAiWhisperModel;
  bool _openAiPro = false;
  bool _openAiRealtime = false;
  bool _geminiPro = false;
  bool _anthropicPro = false;
  bool _xaiPro = false;
  bool _appFetchUrl = true;
  bool _floatingDictationEnabled = true;
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
    notifyListeners();
  }

  String get openAiKey => _openAiKey;
  String get geminiKey => _geminiKey;
  String get anthropicKey => _anthropicKey;
  String get xaiKey => _xaiKey;
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
  bool get geminiPro => _geminiPro;
  bool get anthropicPro => _anthropicPro;
  bool get xaiPro => _xaiPro;

  void setOpenAiPro(bool enabled) {
    _openAiPro = enabled;
    notifyListeners();
  }

  void setOpenAiRealtime(bool enabled) {
    _openAiRealtime = enabled;
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

  String get targetLanguageCode => _targetLanguageCode;
  void setTargetLanguageCode(String code) {
    _targetLanguageCode = code;
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
