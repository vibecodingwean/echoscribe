import 'package:flutter/foundation.dart';
import 'realtime_transcription_client.dart';
import 'openai_realtime_client_io.dart';

abstract class OpenAiRealtimeClient implements RealtimeTranscriptionClient {
  factory OpenAiRealtimeClient() => getRealtimeClient();

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
  });

  @override
  void sendAudioChunk(List<int> chunk);

  @override
  Future<void> finishAudio();

  @override
  Future<void> close();
}
