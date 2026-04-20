import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:echoscribe/models/enums.dart';

class SecureStorageService {
  // 1. Implement Singleton Pattern
  static final SecureStorageService _instance =
      SecureStorageService._internal();

  factory SecureStorageService() {
    return _instance;
  }

  SecureStorageService._internal();

  static const _keyProvider = 'ai_provider';
  static const _keyOpenAi = 'openai_api_key';
  static const _keyGemini = 'gemini_api_key';
  static const _keySummaryPrompt = 'summary_prompt';
  static const _keyUrlSummaryPrompt = 'url_summary_prompt';
  static const _keyTargetLanguage = 'target_language_code';
  static const _keyDebugMode = 'debug_mode_enabled';
  static const _keyOpenAiPro = 'openai_pro_enabled';
  static const _keyGeminiPro = 'gemini_pro_enabled';
  static const _keyAnthropicPro = 'anthropic_pro_enabled';
  static const _keyAppFetchUrl = 'app_fetch_url_enabled';
  static const _keyAnthropic = 'anthropic_api_key';
  static const _keyXai = 'xai_api_key';
  static const _keyXaiPro = 'xai_pro_enabled';
  static const _keyLastSharedIntentId = 'last_shared_intent_id';

  // 2. IMPORTANT: resetOnError: true prevents permanent crashes/empty data on key problems
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: true,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: _androidOptions,
  );

  Map<String, String>? _cache;
  Future<Map<String, String>>? _loading;

  Future<Map<String, String>> _safeReadAll() async {
    try {
      final all = await _storage.readAll();
      return Map<String, String>.from(all);
    } catch (e) {
      // If readAll fails (despite resetOnError), return an empty Map,
      // but the error was likely fixed by resetOnError for the next start.
      return <String, String>{};
    }
  }

  Future<void> _ensureCache() async {
    if (_cache != null) return;

    // Prevent multiple parallel loads
    if (_loading != null) {
      _cache = await _loading!;
      return;
    }

    _loading = _safeReadAll();
    _cache = await _loading!;
    _loading = null;
  }

  Future<String> _safeRead(String key, {String fallback = ''}) async {
    await _ensureCache();
    return _cache![key] ?? fallback;
  }

  Future<void> _safeWrite(String key, String? value) async {
    await _ensureCache(); // Ensure cache exists before update
    try {
      if (value == null) {
        await _storage.delete(key: key);
        _cache!.remove(key);
      } else {
        await _storage.write(key: key, value: value);
        _cache![key] = value;
      }
    } catch (_) {
      // Ignore in release, but cache was updated locally
    }
  }

  Future<void> _safeDelete(String key) async {
    await _ensureCache();
    try {
      await _storage.delete(key: key);
      _cache!.remove(key);
    } catch (_) {}
  }

  Future<void> warmUp() async {
    await _ensureCache();
  }

  // --- Getter & Setter ---

  // Provider
  Future<void> saveProvider(AiProviderType provider) =>
      _safeWrite(_keyProvider, provider.name);
  Future<AiProviderType> readProvider() async => AiProviderType.fromString(
      await _safeRead(_keyProvider, fallback: 'openai'));

  // OpenAI Key
  Future<void> saveOpenAiKey(String key) => _safeWrite(_keyOpenAi, key);
  Future<String> readOpenAiKey() async => _safeRead(_keyOpenAi);
  Future<void> deleteOpenAiKey() => _safeDelete(_keyOpenAi);

  // Gemini Key
  Future<void> saveGeminiKey(String key) => _safeWrite(_keyGemini, key);
  Future<String> readGeminiKey() async => _safeRead(_keyGemini);
  Future<void> deleteGeminiKey() => _safeDelete(_keyGemini);

  // Anthropic Key
  Future<void> saveAnthropicKey(String key) => _safeWrite(_keyAnthropic, key);
  Future<String> readAnthropicKey() async => _safeRead(_keyAnthropic);
  Future<void> deleteAnthropicKey() => _safeDelete(_keyAnthropic);

  // Summary prompt
  Future<void> saveSummaryPrompt(String prompt) =>
      _safeWrite(_keySummaryPrompt, prompt);
  Future<String> readSummaryPrompt() async => _safeRead(_keySummaryPrompt);
  Future<void> deleteSummaryPrompt() => _safeDelete(_keySummaryPrompt);

  // URL Summary prompt
  Future<void> saveUrlSummaryPrompt(String prompt) =>
      _safeWrite(_keyUrlSummaryPrompt, prompt);
  Future<String> readUrlSummaryPrompt() async =>
      _safeRead(_keyUrlSummaryPrompt);
  Future<void> deleteUrlSummaryPrompt() => _safeDelete(_keyUrlSummaryPrompt);

  // Target language
  Future<void> saveTargetLanguageCode(String code) =>
      _safeWrite(_keyTargetLanguage, code);
  Future<String> readTargetLanguageCode() async =>
      _safeRead(_keyTargetLanguage, fallback: 'auto');

  // Debug mode
  Future<void> saveDebugMode(bool enabled) =>
      _safeWrite(_keyDebugMode, enabled ? '1' : '0');
  Future<bool> readDebugMode() async =>
      (await _safeRead(_keyDebugMode, fallback: '0')) == '1';

  // Pro toggles
  Future<void> saveOpenAiPro(bool enabled) =>
      _safeWrite(_keyOpenAiPro, enabled ? '1' : '0');
  Future<bool> readOpenAiPro() async =>
      (await _safeRead(_keyOpenAiPro, fallback: '0')) == '1';

  Future<void> saveGeminiPro(bool enabled) =>
      _safeWrite(_keyGeminiPro, enabled ? '1' : '0');
  Future<bool> readGeminiPro() async =>
      (await _safeRead(_keyGeminiPro, fallback: '0')) == '1';

  Future<void> saveAnthropicPro(bool enabled) =>
      _safeWrite(_keyAnthropicPro, enabled ? '1' : '0');
  Future<bool> readAnthropicPro() async =>
      (await _safeRead(_keyAnthropicPro, fallback: '0')) == '1';

  Future<void> saveAppFetchUrl(bool enabled) =>
      _safeWrite(_keyAppFetchUrl, enabled ? '1' : '0');
  Future<bool> readAppFetchUrl() async =>
      (await _safeRead(_keyAppFetchUrl, fallback: '1')) == '1';

  // xAI Key
  Future<void> saveXaiKey(String key) => _safeWrite(_keyXai, key);
  Future<String> readXaiKey() async => _safeRead(_keyXai);
  Future<void> deleteXaiKey() => _safeDelete(_keyXai);

  // xAI Pro
  Future<void> saveXaiPro(bool enabled) =>
      _safeWrite(_keyXaiPro, enabled ? '1' : '0');
  Future<bool> readXaiPro() async =>
      (await _safeRead(_keyXaiPro, fallback: '0')) == '1';

  // Last shared intent ID
  Future<void> saveLastSharedIntentId(String id) =>
      _safeWrite(_keyLastSharedIntentId, id);
  Future<String> readLastSharedIntentId() async =>
      _safeRead(_keyLastSharedIntentId);
}
