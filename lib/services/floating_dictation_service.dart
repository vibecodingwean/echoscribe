import 'dart:async';

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
  static const MethodChannel _channel = MethodChannel(
    'com.echoscribe.app/floating_dictation',
  );

  static bool get isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  static Future<FloatingDictationStatus> getStatus() async {
    if (!isAndroid) return FloatingDictationStatus.unavailable();
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('getStatus')
          .timeout(const Duration(seconds: 1));
      return FloatingDictationStatus.fromMap(result ?? const {});
    } on MissingPluginException {
      return FloatingDictationStatus.unavailable();
    } catch (_) {
      return FloatingDictationStatus.unavailable();
    }
  }

  static Future<void> openOverlaySettings() => _invoke('openOverlaySettings');
  static Future<void> openAccessibilitySettings() =>
      _invoke('openAccessibilitySettings');
  static Future<void> openAppSettings() => _invoke('openAppSettings');

  static Map<String, dynamic> buildConfigPayload(SettingsState settings) {
    final provider = settings.provider;
    final supported = provider.supportsFloatingDictation;
    return <String, dynamic>{
      'provider': provider.name,
      'floatingEnabled': supported && settings.floatingDictationEnabled,
      'brandName': provider.brandName,
      'apiKey': supported ? settings.activeApiKey : '',
      'targetLanguageCode': settings.targetLanguageCode,
      'dictationPrompt': settings.dictationPrompt.trim().isNotEmpty
          ? settings.dictationPrompt.trim()
          : kDefaultDictationPrompt,
      'transcriptionModel': supported ? settings.transcriptionModel : '',
      'formattingModel': supported ? settings.summaryModel : '',
      'reasoningEffort':
          supported ? (settings.reasoningEffort ?? '') : '',
      'localAiLlmUrl': supported && provider == AiProviderType.localAi
          ? settings.localAiLlmUrl
          : '',
      'localAiWhisperUrl': supported && provider == AiProviderType.localAi
          ? settings.localAiWhisperUrl
          : '',
      'supportsDictation': supported,
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
}
