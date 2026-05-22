import 'package:flutter/foundation.dart';
import 'openai_realtime_client_stub.dart'
    if (dart.library.io) 'openai_realtime_client_io.dart'
    if (dart.library.html) 'openai_realtime_client_web.dart';

abstract class OpenAiRealtimeClient {
  factory OpenAiRealtimeClient() => getRealtimeClient();

  Future<void> connect({
    required String apiKey,
    required String model,
    required String targetLanguageCode,
    required ValueChanged<String> onTranscriptDelta,
    required ValueChanged<String> onTranscriptCompleted,
    required ValueChanged<String> onError,
    required VoidCallback onConnected,
    required VoidCallback onDisconnected,
  });

  void sendAudioChunk(List<int> chunk);

  Future<void> finishAudio();

  Future<void> close();
}
