import "package:flutter/material.dart";
import "package:echoscribe/config/prompts.dart";
import "package:echoscribe/models/enums.dart";

class SettingsState extends ChangeNotifier {
  bool _debugMode = false;
  AiProviderType _provider = AiProviderType.openai;
  String _openAiKey = "";
  String _geminiKey = "";
  String _anthropicKey = "";
  bool _openAiPro = false;
  bool _geminiPro = false;
  bool _anthropicPro = false;
  bool _appFetchUrl = false;
  String _targetLanguageCode = "auto";
  String _summaryPrompt = kDefaultSummaryPrompt;
  String _urlSummaryPrompt = kDefaultUrlSummaryPrompt;

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
  
  void setOpenAiKey(String key) { _openAiKey = key.trim(); notifyListeners(); }
  void setGeminiKey(String key) { _geminiKey = key.trim(); notifyListeners(); }
  void setAnthropicKey(String key) { _anthropicKey = key.trim(); notifyListeners(); }

  String get activeApiKey {
    if (_provider == AiProviderType.gemini) return _geminiKey;
    if (_provider == AiProviderType.anthropic) return _anthropicKey;
    return _openAiKey;
  }
  bool get hasActiveApiKey => activeApiKey.isNotEmpty;
  bool get hasOpenAiKey => _openAiKey.isNotEmpty;
  bool get hasGeminiKey => _geminiKey.isNotEmpty;
  bool get hasAnthropicKey => _anthropicKey.isNotEmpty;

  bool get openAiPro => _openAiPro;
  bool get geminiPro => _geminiPro;
  bool get anthropicPro => _anthropicPro;
  
  void setOpenAiPro(bool enabled) { _openAiPro = enabled; notifyListeners(); }
  void setGeminiPro(bool enabled) { _geminiPro = enabled; notifyListeners(); }
  void setAnthropicPro(bool enabled) { _anthropicPro = enabled; notifyListeners(); }

  bool get appFetchUrl => _appFetchUrl;
  void setAppFetchUrl(bool enabled) { _appFetchUrl = enabled; notifyListeners(); }

  String get targetLanguageCode => _targetLanguageCode;
  void setTargetLanguageCode(String code) { _targetLanguageCode = code; notifyListeners(); }

  String get summaryPrompt => _summaryPrompt;
  void setSummaryPrompt(String prompt) { _summaryPrompt = prompt.trim(); notifyListeners(); }

  String get urlSummaryPrompt => _urlSummaryPrompt;
  void setUrlSummaryPrompt(String prompt) { _urlSummaryPrompt = prompt.trim(); notifyListeners(); }
}
