import 'elevenlabs_realtime_client_stub.dart'
    if (dart.library.io) 'elevenlabs_realtime_client_io.dart'
    if (dart.library.html) 'elevenlabs_realtime_client_web.dart';
import 'realtime_transcription_client.dart';

abstract class ElevenLabsRealtimeClient implements RealtimeTranscriptionClient {
  factory ElevenLabsRealtimeClient() => getElevenLabsRealtimeClient();
}
