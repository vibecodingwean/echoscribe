import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls iOS disclosure before sending user content to an AI destination.
/// The grant is provider-wide, but Local AI grants are tied to its endpoints.
class ProviderConsentService extends ChangeNotifier {
  ProviderConsentService({
    Future<SharedPreferences> Function()? preferences,
    Future<bool> Function(ProviderConsentRequest)? requestPermission,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _requestPermission = requestPermission;

  static const disclosureVersion = '1';
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Future<SharedPreferences> Function() _preferences;
  final Future<bool> Function(ProviderConsentRequest)? _requestPermission;
  final Map<String, Future<void>> _pending = {};
  final Map<AiProviderType, int> _generation = {};
  final Set<AiProviderType> _revoked = {};
  final Set<String> _authorized = {};

  bool get isRequired => defaultTargetPlatform == TargetPlatform.iOS;

  static String _storageKey(AiProviderType provider) =>
      'ai_provider_consent_v1_${provider.name}';

  static String _scope(AiProviderType provider, {String? localEndpoint}) {
    if (provider == AiProviderType.gemini) {
      return '$disclosureVersion:gemini-adult-paid-2026-03';
    }
    if (provider != AiProviderType.localAi) return disclosureVersion;
    final endpoint = (localEndpoint ?? '').trim();
    return '$disclosureVersion:${sha256.convert(utf8.encode(endpoint))}';
  }

  static String _authorizationKey(AiProviderType provider, String scope) =>
      '${provider.name}:$scope';

  bool canTransferNow(AiProviderType provider, {String? localEndpoint}) {
    if (!isRequired) return true;
    if (_revoked.contains(provider)) return false;
    return _authorized.contains(
      _authorizationKey(provider, _scope(provider, localEndpoint: localEndpoint)),
    );
  }

  Future<bool> hasGrant(AiProviderType provider, {String? localEndpoint}) async {
    if (!isRequired) return true;
    if (_revoked.contains(provider)) return false;
    try {
      final preferences = await _preferences();
      return preferences.getString(_storageKey(provider)) ==
          _scope(provider, localEndpoint: localEndpoint);
    } catch (_) {
      return false;
    }
  }

  Future<void> ensure(
    AiProviderType provider, {
    required String dataType,
    required String purpose,
    String? localEndpoint,
  }) async {
    if (!isRequired) return;
    final scope = _scope(provider, localEndpoint: localEndpoint);
    final requestKey = _authorizationKey(provider, scope);
    final existing = _pending[requestKey];
    if (existing != null) return existing;
    final pending = _ensureOnce(
      provider,
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
        preferences.getString(_storageKey(provider)) == scope) {
      _authorized.add(requestKey);
      return;
    }

    final request = ProviderConsentRequest(
      provider: provider,
      destination: _destination(provider, localEndpoint),
      dataType: dataType,
      purpose: purpose,
      disclosure: _disclosure(provider),
    );
    final approved = await (_requestPermission?.call(request) ?? _showDialog(request));
    if (!approved) {
      throw const AppException('AI sharing permission was not granted.');
    }
    if ((_generation[provider] ?? 0) != generation) {
      throw const AppException('AI sharing permission was withdrawn.');
    }
    try {
      final saved = await preferences.setString(_storageKey(provider), scope);
      if (!saved) throw StateError('Consent was not saved');
      if ((_generation[provider] ?? 0) != generation) {
        await preferences.remove(_storageKey(provider));
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
      final removed = await preferences.remove(_storageKey(provider));
      if (!removed) throw StateError('Consent was not removed');
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
                    title: Text('Share with ${request.destination}?'),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'For this request, EchoScribe will send ${request.dataType} '
                            'to ${request.destination} for ${request.purpose}.\n\n'
                            '${request.disclosure}\n\n'
                            'If you allow this provider, EchoScribe will remember your choice. '
                            'You can withdraw it in Settings before future requests. '
                            'Withdrawal cannot recall content already sent.',
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
        AiProviderType.gemini => 'Google Gemini (generativelanguage.googleapis.com)',
        AiProviderType.anthropic => 'Anthropic (api.anthropic.com)',
        AiProviderType.xai => 'xAI (api.x.ai)',
        AiProviderType.elevenLabs => 'ElevenLabs (api.elevenlabs.io)',
        AiProviderType.localAi => 'your Local AI server (${localEndpoint ?? 'configured endpoint'})',
      };

  static String _disclosure(AiProviderType provider) {
    final parts = <String>[];
    if (provider.supportsAudio) {
      parts.add('microphone and imported audio for transcription');
    }
    if (provider.supportsSummary || provider.supportsTranslation) {
      parts.add('text, URLs, extracted webpage content and custom prompts for summaries or translation');
    }
    if (provider.supportsTts) {
      parts.add('transcripts or summaries for speech generation');
    }
    if (provider.supportsImage) {
      parts.add('text prompts derived from your content for image generation');
    }
    return 'Future requests to this provider may include ${parts.join('; ')}. '
        'Your API key is used to make the request directly from this device.';
  }
}

class ProviderConsentRequest {
  const ProviderConsentRequest({
    required this.provider,
    required this.destination,
    required this.dataType,
    required this.purpose,
    required this.disclosure,
  });

  final AiProviderType provider;
  final String destination;
  final String dataType;
  final String purpose;
  final String disclosure;
}
