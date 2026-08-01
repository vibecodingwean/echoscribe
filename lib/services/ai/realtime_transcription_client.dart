import 'package:flutter/foundation.dart';

abstract class RealtimeTranscriptionClient {
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
