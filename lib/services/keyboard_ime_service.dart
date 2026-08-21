import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';

class KeyboardImeStatus {
  final bool isAndroid;
  final bool microphoneGranted;
  final bool imeEnabled;
  final String voiceMode;
  final String keyboardLayout;
  final bool configReady;
  final String provider;

  const KeyboardImeStatus({
    required this.isAndroid,
    required this.microphoneGranted,
    required this.imeEnabled,
    required this.voiceMode,
    required this.keyboardLayout,
    required this.configReady,
    required this.provider,
  });

  factory KeyboardImeStatus.unavailable() {
    return const KeyboardImeStatus(
      isAndroid: false,
      microphoneGranted: false,
      imeEnabled: false,
      voiceMode: 'google',
      keyboardLayout: '',
      configReady: false,
      provider: '',
    );
  }

  factory KeyboardImeStatus.fromMap(Map<dynamic, dynamic> map) {
    return KeyboardImeStatus(
      isAndroid: map['isAndroid'] == true,
      microphoneGranted: map['microphoneGranted'] == true,
      imeEnabled: map['imeEnabled'] == true,
      voiceMode: (map['voiceMode'] ?? 'google').toString(),
      keyboardLayout: KeyboardImeService.normalizeStoredLayout(
        (map['keyboardLayout'] ?? '').toString(),
      ),
      configReady: map['configReady'] == true,
      provider: (map['provider'] ?? '').toString(),
    );
  }

  bool get ready =>
      isAndroid && microphoneGranted && imeEnabled && configReady;
}

class KeyboardImeService {
  static const MethodChannel _channel = MethodChannel(
    'com.echoscribe.app/keyboard_ime',
  );

  static bool get isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  static Future<KeyboardImeStatus> getStatus() async {
    if (!isAndroid) return KeyboardImeStatus.unavailable();
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getStatus')
          .timeout(const Duration(seconds: 1));
      return KeyboardImeStatus.fromMap(result ?? const {});
    } on MissingPluginException {
      return KeyboardImeStatus.unavailable();
    } catch (_) {
      return KeyboardImeStatus.unavailable();
    }
  }

  static Future<void> openInputMethodSettings() =>
      _invoke('openInputMethodSettings');
  static Future<void> openAppSettings() => _invoke('openAppSettings');

  static Future<String> getVoiceMode() async {
    if (!isAndroid) return 'google';
    try {
      final result = await _channel.invokeMethod<String>('getVoiceMode');
      return result ?? 'google';
    } on MissingPluginException {
      return 'google';
    }
  }

  static Future<void> setVoiceMode(String mode) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setVoiceMode', mode);
    } on MissingPluginException {
      return;
    }
  }

  static String normalizeStoredLayout(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized == 'qwerty' || normalized == 'qwertz') return normalized;
    return '';
  }

  static String resolveLayout(
    String? preferred, {
    String? languageCode,
  }) {
    final stored = normalizeStoredLayout(preferred);
    if (stored.isNotEmpty) return stored;
    final lang = (languageCode ?? '').trim().toLowerCase();
    return lang == 'de' ? 'qwertz' : 'qwerty';
  }

  static List<Map<String, String>> mergeCustomTones({
    required List<Map<String, String>> tones,
    required List<Map<String, String>> grammar,
    required List<Map<String, String>> assistants,
  }) {
    final merged = <Map<String, String>>[];
    final seen = <String>{};
    void addAll(List<Map<String, String>> items, String promptKey) {
      for (final item in items) {
        final name = (item['name'] ?? '').trim();
        final prompt = (item['prompt'] ?? item[promptKey] ?? '').trim();
        if (name.isEmpty || prompt.isEmpty) continue;
        if (!seen.add(name.toLowerCase())) continue;
        merged.add({'name': name, 'prompt': prompt});
      }
    }

    addAll(tones, 'prompt');
    addAll(grammar, 'instruction');
    addAll(assistants, 'prompt');
    return merged;
  }

  static Future<void> setKeyboardLayout(String layout) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setKeyboardLayout', layout);
    } on MissingPluginException {
      return;
    }
  }

  static Map<String, dynamic> buildConfigPayload(SettingsState settings) {
    final provider = settings.provider;
    final supported = provider.supportsKeyboardDictation;
    return <String, dynamic>{
      'provider': provider.name,
      'enabled': supported,
      'brandName': provider.brandName,
      'apiKey': supported ? settings.activeApiKey : '',
      'targetLanguageCode': settings.targetLanguageCode,
      'dictationPrompt': settings.dictationPrompt.trim().isNotEmpty
          ? settings.dictationPrompt.trim()
          : kDefaultDictationPrompt,
      'transcriptionModel': supported ? _transcriptionModel(settings) : '',
      'formattingModel': supported ? _formattingModel(settings) : '',
      'reasoningEffort': supported ? _reasoningEffort(settings) : '',
      'localAiLlmUrl': supported && provider == AiProviderType.localAi
          ? settings.localAiLlmUrl
          : '',
      'localAiWhisperUrl': supported && provider == AiProviderType.localAi
          ? settings.localAiWhisperUrl
          : '',
      'supportsDictation': supported,
      'voiceMode': settings.voiceMode,
      'keyboardLayout': settings.keyboardLayout,
      'autocorrectEnabled': settings.autocorrectEnabled,
      'autoCapitalizeEnabled': settings.autoCapitalizeEnabled,
      'hapticFeedbackEnabled': settings.hapticFeedbackEnabled,
      'soundFeedbackEnabled': settings.soundFeedbackEnabled,
      'opticalFeedbackEnabled': settings.opticalFeedbackEnabled,
      'customTones': settings.customTones
          .map((e) => Map<String, String>.from(e))
          .toList(),
      'customGrammar': settings.customGrammar
          .map((e) => Map<String, String>.from(e))
          .toList(),
      'customAssistants': settings.customAssistants
          .map((e) => Map<String, String>.from(e))
          .toList(),
    };
  }

  static Future<void> syncSettings(SettingsState settings) async {
    if (!isAndroid) return;
    final payload = buildConfigPayload(settings);
    try {
      await _channel
          .invokeMethod<void>('syncConfig', payload)
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  static Future<void> _invoke(String method) async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      return;
    }
  }

  static String _transcriptionModel(SettingsState settings) {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiTranscription(pro: settings.geminiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiTranscription(pro: settings.xaiPro);
      case AiProviderType.localAi:
        return settings.localAiWhisperModel;
      case AiProviderType.openai:
      case AiProviderType.anthropic:
        return AiModelConfig.openAiTranscription(pro: settings.openAiPro);
      case AiProviderType.elevenLabs:
        return '';
    }
  }

  static String _formattingModel(SettingsState settings) {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiSummary(pro: settings.geminiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiSummary(pro: settings.xaiPro);
      case AiProviderType.localAi:
        return settings.localAiLlmModel;
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
      case AiProviderType.openai:
        return AiModelConfig.openAiSummary(pro: settings.openAiPro);
      case AiProviderType.elevenLabs:
        return '';
    }
  }

  static String _reasoningEffort(SettingsState settings) {
    switch (settings.provider) {
      case AiProviderType.openai:
        return AiModelConfig.openAiReasoningEffort(pro: settings.openAiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiReasoningEffort(pro: settings.xaiPro);
      case AiProviderType.gemini:
      case AiProviderType.anthropic:
      case AiProviderType.localAi:
      case AiProviderType.elevenLabs:
        return '';
    }
  }
}
