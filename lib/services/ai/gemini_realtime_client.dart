import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:echoscribe/models/app_exception.dart';
import 'package:flutter/foundation.dart';

import 'realtime_transcription_client.dart';

typedef GeminiWebSocketConnector = Future<WebSocket> Function(
  String url, {
  Map<String, dynamic>? headers,
});

class GeminiRealtimeClient implements RealtimeTranscriptionClient {
  GeminiRealtimeClient({
    GeminiWebSocketConnector? connector,
    Duration connectionTimeout = const Duration(seconds: 10),
  })  : _connector = connector ?? WebSocket.connect,
        _connectionTimeout = connectionTimeout;

  /// Live API setup for `gemini-3.5-transcribe-live`.
  /// Official live `mode` is `VERBATIM` / `SMART`, not file-STT `verbatim`.
  static Map<String, dynamic> buildSetupMessage({
    required String model,
    required String targetLanguageCode,
  }) {
    final modelName = model.startsWith('models/') ? model : 'models/$model';
    final transcription = <String, dynamic>{
      'mode': 'VERBATIM',
    };
    if (targetLanguageCode != 'auto' && targetLanguageCode.trim().isNotEmpty) {
      transcription['languageCodes'] = [targetLanguageCode];
    }
    return {
      'setup': {
        'model': modelName,
        'inputAudioTranscription': transcription,
      },
    };
  }

  static Map<String, dynamic>? decodeSocketEvent(dynamic data) {
    final String text;
    if (data is String) {
      text = data;
    } else if (data is List<int>) {
      text = utf8.decode(data);
    } else {
      return null;
    }
    if (text.isEmpty) return null;
    try {
      final decoded = json.decode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  final GeminiWebSocketConnector _connector;
  final Duration _connectionTimeout;
  _ConnectionAttempt? _activeAttempt;
  _ConnectionResources? _resources;
  String _lastPartial = '';
  final StringBuffer _finalizedText = StringBuffer();
  bool _setupComplete = false;

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
            AppException('Gemini Realtime connection failed: $message'),
          );
        }
        return;
      }
      onError(message);
    }

    try {
      await previousResources?.close();
      _throwIfCancelled(attempt);

      _lastPartial = '';
      _finalizedText.clear();
      _setupComplete = false;

      final modelName = model.startsWith('models/') ? model : 'models/$model';
      final uri = Uri.parse(
        'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$apiKey',
      );
      final socketFuture = _connector(uri.toString());
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
          try {
            final event = decodeSocketEvent(data);
            if (event == null) return;
            if (event.containsKey('setupComplete') ||
                event.containsKey('setup_complete')) {
              if (!ready.isCompleted) {
                connected = true;
                _setupComplete = true;
                ready.complete();
                onConnected();
              }
              return;
            }

            final error = event['error'];
            if (error is Map) {
              final message =
                  (error['message'] ?? error.toString()).toString();
              reportError(message);
              unawaited(close());
              return;
            }

            final serverContent =
                event['serverContent'] ?? event['server_content'];
            if (serverContent is! Map) return;

            final interim = serverContent['interimInputTranscription'] ??
                serverContent['interim_input_transcription'];
            if (interim is Map) {
              final partial = (interim['text'] as String?) ?? '';
              if (partial.startsWith(_lastPartial)) {
                final delta = partial.substring(_lastPartial.length);
                if (delta.isNotEmpty) onTranscriptDelta(delta);
              } else if (partial.isNotEmpty) {
                final prefix = _finalizedText.toString();
                onTranscriptCompleted(
                  prefix.isEmpty ? partial : '$prefix $partial',
                );
              }
              _lastPartial = partial;
            }

            final finalSeg = serverContent['inputTranscription'] ??
                serverContent['input_transcription'];
            if (finalSeg is Map) {
              final text = ((finalSeg['text'] as String?) ?? '').trim();
              if (text.isNotEmpty) {
                if (_finalizedText.isNotEmpty) _finalizedText.write(' ');
                _finalizedText.write(text);
                _lastPartial = '';
                onTranscriptCompleted(_finalizedText.toString());
              }
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
                'Gemini Realtime connection closed before setup completed.',
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

      // Do NOT set generationConfig.responseModalities TEXT — that can suppress
      // final inputTranscription segments for the dedicated live STT model.
      socket.add(
        json.encode(
          buildSetupMessage(
            model: modelName,
            targetLanguageCode: targetLanguageCode,
          ),
        ),
      );

      await Future.any<void>([
        ready.future,
        attempt.cancelled.then<void>((_) => _throwIfCancelled(attempt)),
      ]).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw const AppException(
          'Gemini Realtime did not confirm setup in time.',
        ),
      );
    } catch (error, stackTrace) {
      attempt.cancel();
      if (identical(_activeAttempt, attempt)) {
        _activeAttempt = null;
        _lastPartial = '';
        _finalizedText.clear();
        _setupComplete = false;
      }
      if (identical(_resources, attemptResources)) {
        _resources = null;
      }
      try {
        await attemptResources?.close();
      } catch (_) {}
      try {
        reportDisconnected();
      } catch (_) {}
      if (error is AppException) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      Error.throwWithStackTrace(
        AppException('Gemini Realtime connection failed: $error'),
        stackTrace,
      );
    }
  }

  Future<void> _closeLateSocket(Future<WebSocket> socketFuture) async {
    try {
      final socket = await socketFuture;
      try {
        await socket.close();
      } catch (_) {}
    } catch (_) {}
  }

  void _throwIfCancelled(_ConnectionAttempt attempt) {
    if (!identical(_activeAttempt, attempt) || attempt.isCancelled) {
      throw const AppException('Gemini Realtime connection was cancelled.');
    }
  }

  @override
  void sendAudioChunk(List<int> chunk) {
    final socket = _resources?.socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    if (!_setupComplete) return;
    socket.add(
      json.encode({
        'realtimeInput': {
          'audio': {
            'data': base64Encode(chunk),
            'mimeType': 'audio/pcm;rate=16000',
          },
        },
      }),
    );
  }

  @override
  Future<void> finishAudio() async {
    final socket = _resources?.socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    if (!_setupComplete) return;
    socket.add(
      json.encode({
        'realtimeInput': {
          'audioStreamEnd': true,
        },
      }),
    );
  }

  @override
  Future<void> close() async {
    final attempt = _activeAttempt;
    _activeAttempt = null;
    attempt?.cancel();
    final resources = _resources;
    _resources = null;
    _lastPartial = '';
    _finalizedText.clear();
    _setupComplete = false;
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
