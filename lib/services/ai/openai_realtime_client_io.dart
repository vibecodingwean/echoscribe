import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'openai_realtime_client.dart';

class OpenAiRealtimeClientImpl implements OpenAiRealtimeClient {
  WebSocket? _ws;
  StreamSubscription? _sub;
  final StringBuffer _finalizedTextBuffer = StringBuffer();
  String _appendEventType = 'input_audio_buffer.append';
  bool _isTranslation = false;

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
      _finalizedTextBuffer.clear();
      _isTranslation = targetLanguageCode != 'auto';
      _appendEventType = _isTranslation
          ? 'session.input_audio_buffer.append'
          : 'input_audio_buffer.append';
      final uri = Uri.parse(_isTranslation
          ? 'wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate'
          : 'wss://api.openai.com/v1/realtime?intent=transcription');

      _ws = await WebSocket.connect(
        uri.toString(),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 10));

      onConnected();

      final sessionUpdate = _isTranslation
          ? {
              'type': 'session.update',
              'session': {
                'audio': {
                  'input': {
                    'transcription': {'model': 'gpt-realtime-whisper'},
                    'noise_reduction': {'type': 'near_field'},
                  },
                  'output': {'language': targetLanguageCode},
                },
              },
            }
          : {
              'type': 'session.update',
              'session': {
                'type': 'transcription',
                'audio': {
                  'input': {
                    'format': {'type': 'audio/pcm', 'rate': 24000},
                    'transcription': {'model': 'gpt-realtime-whisper'},
                    'turn_detection': null,
                  },
                },
              },
            };

      _ws!.add(json.encode(sessionUpdate));

      _sub = _ws!.listen((data) {
        if (data is String) {
          final event = json.decode(data) as Map<String, dynamic>;
          final type = event['type'];

          if (!_isTranslation) {
            if (type == 'conversation.item.input_audio_transcription.delta') {
              final delta = event['delta'] as String?;
              if (delta != null) {
                onTranscriptDelta(delta);
              }
            } else if (type ==
                'conversation.item.input_audio_transcription.completed') {
              final transcript = event['transcript'] as String?;
              if (transcript != null && transcript.trim().isNotEmpty) {
                _finalizedTextBuffer.write('${transcript.trim()} ');
                onTranscriptCompleted(_finalizedTextBuffer.toString().trim());
              }
            }
          } else {
            if (type == 'session.output_transcript.delta') {
              final delta = event['delta'] as String?;
              if (delta != null) {
                _finalizedTextBuffer.write(delta);
                onTranscriptDelta(delta);
              }
            } else if (type == 'session.output_transcript.done') {
              final text = (event['text'] as String?) ??
                  (event['transcript'] as String?);
              if (text != null && text.trim().isNotEmpty) {
                _finalizedTextBuffer
                  ..clear()
                  ..write(text.trim());
                onTranscriptCompleted(text.trim());
              }
            }
          }

          if (type == 'error') {
            final err = event['error'] as Map<String, dynamic>?;
            final msg = err?['message'] as String? ?? 'Unknown error';
            onError(msg);
          }
        }
      }, onDone: () {
        onDisconnected();
      }, onError: (e) {
        onError(e.toString());
        onDisconnected();
      });
    } catch (e) {
      onError(e.toString());
      onDisconnected();
    }
  }

  @override
  void sendAudioChunk(List<int> chunk) {
    if (_ws != null && _ws!.readyState == WebSocket.open) {
      final base64Audio = base64Encode(chunk);
      final event = {
        'type': _appendEventType,
        'audio': base64Audio,
      };
      _ws!.add(json.encode(event));
    }
  }

  @override
  Future<void> finishAudio() async {
    if (_ws == null || _ws!.readyState != WebSocket.open) return;
    if (_isTranslation) {
      final silence = List<int>.filled(24000 * 2 * 2, 0);
      _ws!.add(json.encode({
        'type': _appendEventType,
        'audio': base64Encode(silence),
      }));
    } else {
      _ws!.add(json.encode({'type': 'input_audio_buffer.commit'}));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.close();
    _ws = null;
  }
}

OpenAiRealtimeClient getRealtimeClient() => OpenAiRealtimeClientImpl();
