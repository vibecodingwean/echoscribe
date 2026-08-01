import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'elevenlabs_realtime_client.dart';

class ElevenLabsRealtimeClientImpl implements ElevenLabsRealtimeClient {
  WebSocket? _ws;
  StreamSubscription? _sub;
  List<int>? _pendingChunk;
  String _lastPartial = '';
  final StringBuffer _finalizedText = StringBuffer();

  @override
  Future<void> connect({
    required String apiKey,
    required String model,
    required String targetLanguageCode,
    required ValueChanged<String> onTranscriptDelta,
    required ValueChanged<String> onTranscriptCompleted,
    required ValueChanged<String> onError,
    required VoidCallback onConnected,
    required VoidCallback onDisconnected,
  }) async {
    try {
      _pendingChunk = null;
      _lastPartial = '';
      _finalizedText.clear();
      final query = <String, String>{
        'model_id': model,
        'audio_format': 'pcm_16000',
        'commit_strategy': 'manual',
        'include_timestamps': 'false',
        if (targetLanguageCode != 'auto') 'language_code': targetLanguageCode,
      };
      final uri = Uri(
        scheme: 'wss',
        host: 'api.elevenlabs.io',
        path: '/v1/speech-to-text/realtime',
        queryParameters: query,
      );
      _ws = await WebSocket.connect(
        uri.toString(),
        headers: {'xi-api-key': apiKey},
      ).timeout(const Duration(seconds: 10));

      _sub = _ws!.listen(
        (data) {
          if (data is! String) return;
          final event = json.decode(data) as Map<String, dynamic>;
          final type = event['message_type'] as String?;
          if (type == 'session_started') {
            onConnected();
            return;
          }
          if (type == 'partial_transcript') {
            final partial = (event['text'] as String?) ?? '';
            if (partial.startsWith(_lastPartial)) {
              onTranscriptDelta(partial.substring(_lastPartial.length));
            } else if (partial.isNotEmpty) {
              final prefix = _finalizedText.toString();
              onTranscriptCompleted(
                prefix.isEmpty ? partial : '$prefix $partial',
              );
            }
            _lastPartial = partial;
            return;
          }
          if (type == 'committed_transcript' ||
              type == 'committed_transcript_with_timestamps' ||
              type == 'final_transcript') {
            final text = ((event['text'] as String?) ?? '').trim();
            if (text.isNotEmpty) {
              if (_finalizedText.isNotEmpty) _finalizedText.write(' ');
              _finalizedText.write(text);
              _lastPartial = '';
              onTranscriptCompleted(_finalizedText.toString());
            }
            return;
          }
          if (type == 'error' ||
              type == 'auth_error' ||
              type == 'quota_exceeded' ||
              type == 'rate_limited') {
            onError((event['error'] ?? event['message'] ?? type).toString());
          }
        },
        onDone: onDisconnected,
        onError: (Object error) {
          onError(error.toString());
          onDisconnected();
        },
      );
    } catch (error) {
      onError(error.toString());
      onDisconnected();
    }
  }

  void _sendChunk(List<int> chunk, {required bool commit}) {
    if (_ws == null || _ws!.readyState != WebSocket.open) return;
    _ws!.add(
      json.encode({
        'message_type': 'input_audio_chunk',
        'audio_base_64': base64Encode(chunk),
        'commit': commit,
        'sample_rate': 16000,
      }),
    );
  }

  @override
  void sendAudioChunk(List<int> chunk) {
    final previous = _pendingChunk;
    if (previous != null) _sendChunk(previous, commit: false);
    _pendingChunk = List<int>.from(chunk);
  }

  @override
  Future<void> finishAudio() async {
    final last = _pendingChunk;
    _pendingChunk = null;
    if (last != null) _sendChunk(last, commit: true);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.close();
    _ws = null;
    _pendingChunk = null;
  }
}

ElevenLabsRealtimeClient getElevenLabsRealtimeClient() =>
    ElevenLabsRealtimeClientImpl();
