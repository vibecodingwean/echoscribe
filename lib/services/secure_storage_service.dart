import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/config/prompts.dart';

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
  static const _keyDictationPrompt = 'dictation_prompt';
  static const _keyTargetLanguage = 'target_language_code';
  static const _keyDebugMode = 'debug_mode_enabled';
  static const _keyOpenAiPro = 'openai_pro_enabled';
  static const _keyOpenAiRealtime = 'openai_realtime_enabled';
  static const _keyElevenLabs = 'elevenlabs_api_key';
  static const _keyElevenLabsRealtime = 'elevenlabs_realtime_enabled';
  static const _keyGeminiPro = 'gemini_pro_enabled';
  static const _keyAnthropicPro = 'anthropic_pro_enabled';
  static const _keyAppFetchUrl = 'app_fetch_url_enabled';
  static const _keyFloatingDictation = 'floating_dictation_enabled';
  static const _keyVoiceMode = 'keyboard_voice_mode';
  static const _keyKeyboardLayout = 'keyboard_layout';
  static const _keyAutocorrectEnabled = 'keyboard_autocorrect_enabled';
  static const _keyAutoCapitalizeEnabled = 'keyboard_auto_capitalize_enabled';
  static const _keyHapticFeedbackEnabled = 'keyboard_haptic_feedback_enabled';
  static const _keySoundFeedbackEnabled = 'keyboard_sound_feedback_enabled';
  static const _keyOpticalFeedbackEnabled = 'keyboard_optical_feedback_enabled';
  static const _keyCustomTones = 'keyboard_custom_tones';
  static const _keyCustomGrammar = 'keyboard_custom_grammar';
  static const _keyCustomAssistants = 'keyboard_custom_assistants';
  static const _keyAnthropic = 'anthropic_api_key';
  static const _keyXai = 'xai_api_key';
  static const _keyXaiPro = 'xai_pro_enabled';
  static const _keyLastSharedIntentId = 'last_shared_intent_id';
  static const _keyLocalAiLlmUrl = 'local_ai_llm_url';
  static const _keyLocalAiLlmModel = 'local_ai_llm_model';
  static const _keyLocalAiWhisperUrl = 'local_ai_whisper_url';
  static const _keyLocalAiWhisperModel = 'local_ai_whisper_model';

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
        await _safeRead(_keyProvider, fallback: 'openai'),
      );

  // OpenAI Key
  Future<void> saveOpenAiKey(String key) => _safeWrite(_keyOpenAi, key);
  Future<String> readOpenAiKey() async => _safeRead(_keyOpenAi);
  Future<void> deleteOpenAiKey() => _safeDelete(_keyOpenAi);

  Future<void> saveElevenLabsKey(String key) => _safeWrite(_keyElevenLabs, key);
  Future<String> readElevenLabsKey() async => _safeRead(_keyElevenLabs);
  Future<void> deleteElevenLabsKey() => _safeDelete(_keyElevenLabs);

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

  // Dictation prompt
  Future<void> saveDictationPrompt(String prompt) =>
      _safeWrite(_keyDictationPrompt, prompt);
  Future<String> readDictationPrompt() async => _safeRead(_keyDictationPrompt);
  Future<void> deleteDictationPrompt() => _safeDelete(_keyDictationPrompt);

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

  // Realtime toggles
  Future<void> saveOpenAiRealtime(bool enabled) =>
      _safeWrite(_keyOpenAiRealtime, enabled ? '1' : '0');
  Future<bool> readOpenAiRealtime() async =>
      (await _safeRead(_keyOpenAiRealtime, fallback: '0')) == '1';

  Future<void> saveElevenLabsRealtime(bool enabled) =>
      _safeWrite(_keyElevenLabsRealtime, enabled ? '1' : '0');
  Future<bool> readElevenLabsRealtime() async =>
      (await _safeRead(_keyElevenLabsRealtime, fallback: '0')) == '1';

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

  Future<void> saveFloatingDictationEnabled(bool enabled) =>
      _safeWrite(_keyFloatingDictation, enabled ? '1' : '0');
  Future<bool> readFloatingDictationEnabled() async =>
      (await _safeRead(_keyFloatingDictation, fallback: '1')) == '1';

  Future<void> saveVoiceMode(String mode) => _safeWrite(_keyVoiceMode, mode);
  Future<String> readVoiceMode() async {
    final value = await _safeRead(_keyVoiceMode, fallback: 'google');
    return value == 'echoscribe' ? 'echoscribe' : 'google';
  }

  Future<void> saveKeyboardLayout(String layout) =>
      _safeWrite(_keyKeyboardLayout, layout);
  Future<String> readKeyboardLayout() async {
    final value = (await _safeRead(_keyKeyboardLayout)).trim().toLowerCase();
    if (value == 'qwerty' || value == 'qwertz') return value;
    return '';
  }

  Future<void> saveAutocorrectEnabled(bool enabled) =>
      _safeWrite(_keyAutocorrectEnabled, enabled ? '1' : '0');
  Future<bool> readAutocorrectEnabled() async =>
      (await _safeRead(_keyAutocorrectEnabled, fallback: '1')) == '1';

  Future<void> saveAutoCapitalizeEnabled(bool enabled) =>
      _safeWrite(_keyAutoCapitalizeEnabled, enabled ? '1' : '0');
  Future<bool> readAutoCapitalizeEnabled() async =>
      (await _safeRead(_keyAutoCapitalizeEnabled, fallback: '1')) == '1';

  Future<void> saveHapticFeedbackEnabled(bool enabled) =>
      _safeWrite(_keyHapticFeedbackEnabled, enabled ? '1' : '0');
  Future<bool> readHapticFeedbackEnabled() async =>
      (await _safeRead(_keyHapticFeedbackEnabled, fallback: '1')) == '1';

  Future<void> saveSoundFeedbackEnabled(bool enabled) =>
      _safeWrite(_keySoundFeedbackEnabled, enabled ? '1' : '0');
  Future<bool> readSoundFeedbackEnabled() async =>
      (await _safeRead(_keySoundFeedbackEnabled, fallback: '1')) == '1';

  Future<void> saveOpticalFeedbackEnabled(bool enabled) =>
      _safeWrite(_keyOpticalFeedbackEnabled, enabled ? '1' : '0');
  Future<bool> readOpticalFeedbackEnabled() async =>
      (await _safeRead(_keyOpticalFeedbackEnabled, fallback: '1')) == '1';

  Future<void> saveCustomTones(List<Map<String, String>> tones) =>
      _safeWrite(_keyCustomTones, jsonEncode(tones));
  Future<List<Map<String, String>>> readCustomTones() async {
    final raw = await _safeRead(_keyCustomTones, fallback: '[]');
    return _decodeStringMapList(raw);
  }

  Future<void> saveCustomGrammar(List<Map<String, String>> grammar) =>
      _safeWrite(_keyCustomGrammar, jsonEncode(grammar));
  Future<List<Map<String, String>>> readCustomGrammar() async {
    final raw = await _safeRead(_keyCustomGrammar, fallback: '[]');
    return _decodeStringMapList(raw);
  }

  Future<void> saveCustomAssistants(List<Map<String, String>> assistants) =>
      _safeWrite(_keyCustomAssistants, jsonEncode(assistants));
  Future<List<Map<String, String>>> readCustomAssistants() async {
    final raw = await _safeRead(_keyCustomAssistants, fallback: '[]');
    return _decodeStringMapList(raw);
  }

  List<Map<String, String>> _decodeStringMapList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
            ),
          )
          .map((item) => Map<String, String>.from(item))
          .toList();
    } catch (_) {
      return const [];
    }
  }

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

  // Local AI
  Future<void> saveLocalAiLlmUrl(String value) =>
      _safeWrite(_keyLocalAiLlmUrl, value);
  Future<String> readLocalAiLlmUrl() async =>
      _safeRead(_keyLocalAiLlmUrl, fallback: AiModelConfig.localAiLlmUrl);

  Future<void> saveLocalAiLlmModel(String value) =>
      _safeWrite(_keyLocalAiLlmModel, value);
  Future<String> readLocalAiLlmModel() async =>
      _safeRead(_keyLocalAiLlmModel, fallback: AiModelConfig.localAiLlmModel);

  Future<void> saveLocalAiWhisperUrl(String value) =>
      _safeWrite(_keyLocalAiWhisperUrl, value);
  Future<String> readLocalAiWhisperUrl() async => _safeRead(
        _keyLocalAiWhisperUrl,
        fallback: AiModelConfig.localAiWhisperUrl,
      );

  Future<void> saveLocalAiWhisperModel(String value) =>
      _safeWrite(_keyLocalAiWhisperModel, value);
  Future<String> readLocalAiWhisperModel() async => _safeRead(
        _keyLocalAiWhisperModel,
        fallback: AiModelConfig.localAiWhisperModel,
      );
}
