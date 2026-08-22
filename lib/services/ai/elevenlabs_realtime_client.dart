import 'elevenlabs_realtime_client_io.dart';
import 'realtime_transcription_client.dart';

abstract class ElevenLabsRealtimeClient implements RealtimeTranscriptionClient {
  factory ElevenLabsRealtimeClient() => getElevenLabsRealtimeClient();
}
