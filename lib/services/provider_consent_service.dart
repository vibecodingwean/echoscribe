import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum AiDataUse {
  text,
  fileAudio,
  liveAudio,
  image,
  speech;

  String get label => switch (this) {
        AiDataUse.text => 'text',
        AiDataUse.fileAudio => 'audio files',
        AiDataUse.liveAudio => 'live audio',
        AiDataUse.image => 'image prompts',
        AiDataUse.speech => 'speech text',
      };
}

/// Controls mobile disclosure for each destination and kind of data use.
class ProviderConsentService extends ChangeNotifier {
  ProviderConsentService({
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function(ProviderConsentRequest)? requestPermission,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _requestPermission = requestPermission;

  static const disclosureVersion = '2';
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function(ProviderConsentRequest)? _requestPermission;
  final Map<String, Future<void>> _pending = {};
  final Map<AiProviderType, int> _generation = {};
  final Set<AiProviderType> _revoked = {};
  final Set<String> _authorized = {};

  bool get isRequired =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static String _storageKey(AiProviderType provider, AiDataUse use) =>
      'ai_provider_consent_v2_${provider.name}_${use.name}';

  static String _scope(AiProviderType provider, {String? localEndpoint}) {
    if (provider == AiProviderType.gemini) {
      return '$disclosureVersion:gemini-adult-paid-2026-03';
    }
    if (provider != AiProviderType.localAi) return disclosureVersion;
    final endpoint = (localEndpoint ?? '').trim();
    return '$disclosureVersion:${sha256.convert(utf8.encode(endpoint))}';
  }

  static String _authorizationKey(
          AiProviderType provider, AiDataUse use, String scope) =>
      '${provider.name}:${use.name}:$scope';

  bool canTransferNow(AiProviderType provider,
      {required AiDataUse use, String? localEndpoint}) {
    if (!isRequired) return true;
    if (_revoked.contains(provider)) return false;
    return _authorized.contains(
      _authorizationKey(
          provider, use, _scope(provider, localEndpoint: localEndpoint)),
    );
  }

  Future<bool> hasGrant(AiProviderType provider,
      {required AiDataUse use, String? localEndpoint}) async {
    if (!isRequired) return true;
    if (_revoked.contains(provider)) return false;
    try {
      final preferences = await _preferences();
      return preferences.getString(_storageKey(provider, use)) ==
          _scope(provider, localEndpoint: localEndpoint);
    } catch (_) {
      return false;
    }
  }

  Future<void> ensure(
    AiProviderType provider, {
    required AiDataUse use,
    required String dataType,
    required String purpose,
    String? localEndpoint,
  }) async {
    if (!isRequired) return;
    final scope = _scope(provider, localEndpoint: localEndpoint);
    final requestKey = _authorizationKey(provider, use, scope);
    final existing = _pending[requestKey];
    if (existing != null) return existing;
    final pending = _ensureOnce(
      provider,
      use: use,
      scope: scope,
      requestKey: requestKey,
      dataType: dataType,
      purpose: purpose,
      localEndpoint: localEndpoint,
    );
    _pending[requestKey] = pending;
    try {
      await pending;
    } finally {
      if (identical(_pending[requestKey], pending)) {
        _pending.remove(requestKey);
      }
    }
  }

  Future<void> _ensureOnce(
    AiProviderType provider, {
    required AiDataUse use,
    required String scope,
    required String requestKey,
    required String dataType,
    required String purpose,
    String? localEndpoint,
  }) async {
    final generation = _generation[provider] ?? 0;
    SharedPreferences preferences;
    try {
      preferences = await _preferences();
    } catch (_) {
      throw const AppException('Could not read AI sharing permission.');
    }
    if ((_generation[provider] ?? 0) != generation) {
      throw const AppException('AI sharing permission was withdrawn.');
    }
    if (!_revoked.contains(provider) &&
        preferences.getString(_storageKey(provider, use)) == scope) {
      _authorized.add(requestKey);
      return;
    }

    final request = ProviderConsentRequest(
      provider: provider,
      use: use,
      destination: _destination(provider, localEndpoint),
      dataType: dataType,
      purpose: purpose,
      disclosure: _disclosure(use),
    );
    final approved =
        await (_requestPermission?.call(request) ?? _showDialog(request));
    if (!approved) {
      throw const AppException('AI sharing permission was not granted.');
    }
    if ((_generation[provider] ?? 0) != generation) {
      throw const AppException('AI sharing permission was withdrawn.');
    }
    try {
      final saved =
          await preferences.setString(_storageKey(provider, use), scope);
      if (!saved) throw StateError('Consent was not saved');
      if ((_generation[provider] ?? 0) != generation) {
        await preferences.remove(_storageKey(provider, use));
        throw const AppException('AI sharing permission was withdrawn.');
      }
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException('Could not save AI sharing permission.');
    }
    _revoked.remove(provider);
    _authorized.add(requestKey);
    notifyListeners();
  }

  Future<void> revoke(AiProviderType provider) async {
    if (!isRequired) return;
    _generation[provider] = (_generation[provider] ?? 0) + 1;
    _revoked.add(provider);
    _authorized.removeWhere((key) => key.startsWith('${provider.name}:'));
    notifyListeners();
    try {
      final preferences = await _preferences();
      for (final use in AiDataUse.values) {
        await preferences.remove(_storageKey(provider, use));
      }
    } catch (_) {
      throw const AppException(
        'AI sharing is blocked now, but the withdrawal could not be saved. Please try again.',
      );
    }
  }

  Future<bool> _showDialog(ProviderConsentRequest request) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      throw const AppException('AI sharing permission cannot be shown.');
    }
    var geminiEligible = false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                    title: const Text('Permission to share AI data'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Recipient: ${request.destination}\n\n'
                            'Sending now: ${request.dataType}\n'
                            'Purpose: ${request.purpose}\n\n'
                            'Allow & remember also permits future ${request.disclosure} '
                            'to this provider. Other data uses ask separately.\n\n'
                            'Requests go directly from your device using your API key. '
                            'The provider processes data under its own terms. '
                            'Withdraw in Settings to stop future requests; sent data cannot be recalled.',
                          ),
                          if (request.provider == AiProviderType.gemini)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text(
                                'I am 18 or older. If I use Gemini from the EEA, '
                                'Switzerland or the UK, my API key is for Gemini Paid Services.',
                              ),
                              value: geminiEligible,
                              onChanged: (value) => setState(() {
                                geminiEligible = value ?? false;
                              }),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse(
                              'https://app.wean.de/echoscribe/privacy.html'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Privacy policy'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Not now'),
                      ),
                      FilledButton(
                        onPressed: request.provider == AiProviderType.gemini &&
                                !geminiEligible
                            ? null
                            : () => Navigator.of(context).pop(true),
                        child: const Text('Allow & remember'),
                      ),
                    ],
                  )),
        ) ??
        false;
  }

  static String _destination(AiProviderType provider, String? localEndpoint) =>
      switch (provider) {
        AiProviderType.openai => 'OpenAI (api.openai.com)',
        AiProviderType.gemini =>
          'Google Gemini (generativelanguage.googleapis.com)',
        AiProviderType.anthropic => 'Anthropic (api.anthropic.com)',
        AiProviderType.xai => 'xAI (api.x.ai)',
        AiProviderType.elevenLabs => 'ElevenLabs (api.elevenlabs.io)',
        AiProviderType.localAi =>
          'your Local AI server (${localEndpoint ?? 'configured endpoint'})',
      };

  static String _disclosure(AiDataUse use) => switch (use) {
        AiDataUse.text =>
          'text, URLs, extracted webpage content and custom prompts for summaries, translation or rewriting',
        AiDataUse.fileAudio =>
          'recorded or imported audio files and filenames for transcription; an MP4 may also contain video tracks',
        AiDataUse.liveAudio =>
          'live microphone audio for realtime transcription',
        AiDataUse.image =>
          'text prompts derived from your content for image generation',
        AiDataUse.speech => 'transcript or summary text for speech generation',
      };
}

class ProviderConsentRequest {
  const ProviderConsentRequest({
    required this.provider,
    required this.use,
    required this.destination,
    required this.dataType,
    required this.purpose,
    required this.disclosure,
  });

  final AiProviderType provider;
  final AiDataUse use;
  final String destination;
  final String dataType;
  final String purpose;
  final String disclosure;
}
