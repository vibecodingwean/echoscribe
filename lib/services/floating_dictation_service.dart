import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/state/settings_state.dart';

class FloatingDictationStatus {
  final bool isAndroid;
  final bool microphoneGranted;
  final bool overlayGranted;
  final bool accessibilityEnabled;
  final bool configReady;
  final bool enabled;
  final String provider;

  const FloatingDictationStatus({
    required this.isAndroid,
    required this.microphoneGranted,
    required this.overlayGranted,
    required this.accessibilityEnabled,
    required this.configReady,
    required this.enabled,
    required this.provider,
  });

  factory FloatingDictationStatus.unavailable() {
    return const FloatingDictationStatus(
      isAndroid: false,
      microphoneGranted: false,
      overlayGranted: false,
      accessibilityEnabled: false,
      configReady: false,
      enabled: false,
      provider: '',
    );
  }

  factory FloatingDictationStatus.fromMap(Map<dynamic, dynamic> map) {
    return FloatingDictationStatus(
      isAndroid: map['isAndroid'] == true,
      microphoneGranted: map['microphoneGranted'] == true,
      overlayGranted: map['overlayGranted'] == true,
      accessibilityEnabled: map['accessibilityEnabled'] == true,
      configReady: map['configReady'] == true,
      enabled: map['enabled'] == true,
      provider: (map['provider'] ?? '').toString(),
    );
  }

  bool get ready =>
      isAndroid &&
      enabled &&
      microphoneGranted &&
      overlayGranted &&
      accessibilityEnabled &&
      configReady;
}

class FloatingDictationService {
  static const MethodChannel _channel =
      MethodChannel('com.echoscribe.app/floating_dictation');

  static bool get isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  static Future<FloatingDictationStatus> getStatus() async {
    if (!isAndroid) return FloatingDictationStatus.unavailable();
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('getStatus');
      return FloatingDictationStatus.fromMap(result ?? const {});
    } on MissingPluginException {
      return FloatingDictationStatus.unavailable();
    }
  }

  static Future<void> openOverlaySettings() => _invoke('openOverlaySettings');
  static Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');
  static Future<void> openAppSettings() => _invoke('openAppSettings');

  static Future<void> syncSettings(SettingsState settings) async {
    if (!isAndroid) return;
    final provider = settings.provider;
    final payload = <String, dynamic>{
      'provider': provider.name,
      'enabled': settings.floatingDictationEnabled,
      'brandName': provider.brandName,
      'apiKey': settings.activeApiKey,
      'targetLanguageCode': settings.targetLanguageCode,
      'dictationPrompt': settings.dictationPrompt.trim().isNotEmpty
          ? settings.dictationPrompt.trim()
          : kDefaultDictationPrompt,
      'transcriptionModel': _transcriptionModel(settings),
      'formattingModel': _formattingModel(settings),
      'reasoningEffort': _reasoningEffort(settings),
      'supportsDictation': provider == AiProviderType.openai ||
          provider == AiProviderType.gemini ||
          provider == AiProviderType.xai,
    };
    try {
      await _channel.invokeMethod<void>('syncConfig', payload);
    } on MissingPluginException {
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
      case AiProviderType.openai:
      case AiProviderType.anthropic:
        return AiModelConfig.openAiTranscription(pro: settings.openAiPro);
    }
  }

  static String _formattingModel(SettingsState settings) {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiSummary(pro: settings.geminiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiSummary(pro: settings.xaiPro);
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
      case AiProviderType.openai:
        return AiModelConfig.openAiSummary(pro: settings.openAiPro);
    }
  }

  static String _reasoningEffort(SettingsState settings) {
    if (settings.provider != AiProviderType.xai) return '';
    return AiModelConfig.xaiReasoningEffort(pro: settings.xaiPro);
  }
}
