import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:echoscribe/models/app_exception.dart';
import 'package:flutter/foundation.dart';

import 'elevenlabs_realtime_message.dart';
import 'realtime_transcription_client.dart';

typedef ElevenLabsWebSocketConnector = Future<WebSocket> Function(
  String url, {
  Map<String, dynamic>? headers,
});

class ElevenLabsRealtimeClient implements RealtimeTranscriptionClient {
  ElevenLabsRealtimeClient({
    ElevenLabsWebSocketConnector? connector,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _connector = connector ?? WebSocket.connect,
        _connectionTimeout = connectionTimeout;

  final ElevenLabsWebSocketConnector _connector;
  final Duration _connectionTimeout;
  _ConnectionAttempt? _activeAttempt;
  _ConnectionResources? _resources;
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
    final attempt = _ConnectionAttempt();
    _activeAttempt?.cancel();
    _activeAttempt = attempt;
    final previousResources = _resources;
    _resources = null;

    final ready = Completer<void>();
    var connected = false;
    var disconnectedReported = false;
    _ConnectionResources? attemptResources;

    void reportDisconnected() {
      if (disconnectedReported) return;
      disconnectedReported = true;
      onDisconnected();
    }

    void reportError(Object error) {
      final message = error.toString();
      if (!connected) {
        if (!ready.isCompleted) {
          ready.completeError(
            AppException('ElevenLabs Realtime connection failed: $message'),
          );
        }
        return;
      }
      onError(message);
    }

    try {
      await previousResources?.close();
      _throwIfCancelled(attempt);

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
      final socketFuture = _connector(
        uri.toString(),
        headers: {'xi-api-key': apiKey},
      );
      late WebSocket socket;
      try {
        socket = await socketFuture.timeout(_connectionTimeout);
      } on TimeoutException {
        unawaited(_closeLateSocket(socketFuture));
        rethrow;
      }
      attemptResources = _ConnectionResources(socket);
      _throwIfCancelled(attempt);

      attemptResources.subscription = socket.listen(
        (data) {
          if (!identical(_activeAttempt, attempt)) return;
          if (data is! String) return;
          try {
            final event = json.decode(data) as Map<String, dynamic>;
            final type = event['message_type'] as String?;
            if (type == 'session_started') {
              if (!ready.isCompleted) {
                connected = true;
                ready.complete();
                onConnected();
              }
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
            final realtimeError = classifyElevenLabsRealtimeError(event);
            if (realtimeError != null) {
              reportError(realtimeError.message);
              unawaited(close());
            }
          } catch (error) {
            reportError(error);
            unawaited(close());
          }
        },
        onDone: () {
          if (!identical(_activeAttempt, attempt)) return;
          if (!connected && !ready.isCompleted) {
            ready.completeError(
              const AppException(
                'ElevenLabs Realtime connection closed before authentication completed.',
              ),
            );
          }
          reportDisconnected();
        },
        onError: (Object error) {
          if (!identical(_activeAttempt, attempt)) return;
          reportError(error);
          reportDisconnected();
        },
      );
      _resources = attemptResources;

      await Future.any<void>([
        ready.future,
        attempt.cancelled.then<void>((_) => _throwIfCancelled(attempt)),
      ]).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const AppException(
          'ElevenLabs Realtime did not confirm the session in time.',
        ),
      );
    } catch (error, stackTrace) {
      attempt.cancel();
      if (identical(_activeAttempt, attempt)) {
        _activeAttempt = null;
        _pendingChunk = null;
        _lastPartial = '';
        _finalizedText.clear();
      }
      if (identical(_resources, attemptResources)) {
        _resources = null;
      }
      try {
        await attemptResources?.close();
      } catch (_) {
        // Preserve the connection failure after best-effort cleanup.
      }
      try {
        reportDisconnected();
      } catch (_) {
        // A callback failure must not replace the connection failure.
      }
      if (error is AppException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        AppException('ElevenLabs Realtime connection failed: $error'),
        stackTrace,
      );
    }
  }

  Future<void> _closeLateSocket(Future<WebSocket> socketFuture) async {
    try {
      final socket = await socketFuture;
      try {
        await socket.close();
      } catch (_) {
        // A timed-out socket is detached; cleanup remains best-effort.
      }
    } catch (_) {
      // The original connect call already reports the timeout.
    }
  }

  void _throwIfCancelled(_ConnectionAttempt attempt) {
    if (!identical(_activeAttempt, attempt) || attempt.isCancelled) {
      throw const AppException('ElevenLabs Realtime connection was cancelled.');
    }
  }

  void _sendChunk(List<int> chunk, {required bool commit}) {
    final socket = _resources?.socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    socket.add(
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
    final attempt = _activeAttempt;
    _activeAttempt = null;
    attempt?.cancel();
    final resources = _resources;
    _resources = null;
    _pendingChunk = null;
    _lastPartial = '';
    _finalizedText.clear();
    await resources?.close();
  }
}

class _ConnectionAttempt {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class _ConnectionResources {
  _ConnectionResources(this.socket);

  final WebSocket socket;
  StreamSubscription? subscription;
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final currentSubscription = subscription;
    subscription = null;
    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await currentSubscription?.cancel();
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    try {
      await socket.close();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }
}
