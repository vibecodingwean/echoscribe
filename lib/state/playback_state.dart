import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:crypto/crypto.dart";
import "package:echoscribe/services/tts_service.dart";
import "package:echoscribe/utils/cross_audio_player.dart";
import "package:echoscribe/models/enums.dart";

class PlaybackState extends ChangeNotifier {
  final CrossAudioPlayer _audio = CrossAudioPlayer();
  bool _isPlaying = false;
  bool _isAudioLoading = false;
  bool _playbackCompleted = false;
  final Map<String, Uint8List> _audioCache = <String, Uint8List>{};
  String? _currentAudioKey;

  bool get isPlaying => _isPlaying;
  bool get isAudioLoading => _isAudioLoading;

  PlaybackState() {
    _audio.onPlayingChanged.listen((playing) {
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
    });
    _audio.onEnded.listen((_) {
      _playbackCompleted = true;
      _isPlaying = false;
      notifyListeners();
    });
  }

  bool hasCachedSummaryAudio(String text, AiProviderType provider, {String voice = "default"}) {
    final key = _audioCacheKey(text, provider, voice: voice);
    return key != null && _audioCache.containsKey(key);
  }

  String? _audioCacheKey(String text, AiProviderType provider, {String voice = "default"}) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final md5sum = md5.convert(utf8.encode(t)).toString();
    return "${provider.name}|$voice|$md5sum";
  }

  String _voiceForProvider(AiProviderType provider, {String openAiVoice = "alloy", String geminiVoice = "Zephyr", String xaiVoice = "Eve"}) {
    switch (provider) {
      case AiProviderType.gemini: return geminiVoice;
      case AiProviderType.xai: return xaiVoice;
      default: return openAiVoice;
    }
  }

  bool canResumeCurrentAudio(String text, AiProviderType provider, {String openAiVoice = "alloy", String geminiVoice = "Zephyr", String xaiVoice = "Eve"}) {
    final voice = _voiceForProvider(provider, openAiVoice: openAiVoice, geminiVoice: geminiVoice, xaiVoice: xaiVoice);
    final key = _audioCacheKey(text, provider, voice: voice);
    return key != null && key == _currentAudioKey && !_isPlaying && !_playbackCompleted;
  }

  int? cachedSummaryAudioSize(String text, AiProviderType provider, {String openAiVoice = "alloy", String geminiVoice = "Zephyr", String xaiVoice = "Eve"}) {
    final voice = _voiceForProvider(provider, openAiVoice: openAiVoice, geminiVoice: geminiVoice, xaiVoice: xaiVoice);
    final key = _audioCacheKey(text, provider, voice: voice);
    if (key == null) return null;
    final bytes = _audioCache[key];
    return bytes?.length;
  }

  Future<void> playSummary({
    required TtsService tts,
    required String text,
    required AiProviderType provider,
    required String activeApiKey,
    String openAiVoice = "alloy",
    String geminiVoice = "Zephyr",
    String xaiVoice = "Eve",
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    if (_isAudioLoading) return;
    final voice = _voiceForProvider(provider, openAiVoice: openAiVoice, geminiVoice: geminiVoice, xaiVoice: xaiVoice);
    final key = _audioCacheKey(t, provider, voice: voice);
    if (key == null) return;

    try {
      _isAudioLoading = true;
      notifyListeners();

      Uint8List? bytes = _audioCache[key];
      if (bytes == null) {
        switch (provider) {
          case AiProviderType.gemini:
            bytes = await tts.generateSpeechGemini(apiKey: activeApiKey, text: t, voice: geminiVoice);
          case AiProviderType.xai:
            bytes = await tts.generateSpeechXai(apiKey: activeApiKey, text: t, voice: xaiVoice);
          default:
            bytes = await tts.generateSpeechOpenAI(apiKey: activeApiKey, text: t, voice: openAiVoice);
        }
        _audioCache[key] = bytes;
      }

      final mime = provider == AiProviderType.gemini ? "audio/wav" : "audio/mpeg";
      await _audio.stop();
      await _audio.playBytes(bytes, mimeType: mime);
      _currentAudioKey = key;
      _isPlaying = true;
      _playbackCompleted = false;
    } catch (e) {
      rethrow;
    } finally {
      _isAudioLoading = false;
      notifyListeners();
    }
  }

  Future<void> pauseAudio() async {
    try {
      await _audio.pause();
      _isPlaying = false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> resumeAudio() async {
    try {
      await _audio.resume();
      _isPlaying = true;
      _playbackCompleted = false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> stopAudio() async {
    try {
      await _audio.stop();
      _isPlaying = false;
      _currentAudioKey = null;
      _playbackCompleted = false;
    } finally {
      notifyListeners();
    }
  }
}
