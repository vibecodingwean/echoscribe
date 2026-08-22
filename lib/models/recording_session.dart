import 'package:echoscribe/models/enums.dart';

class RecordingSessionMetadata {
  const RecordingSessionMetadata({
    required this.provider,
    required this.isRealtime,
    required this.targetLanguageCode,
    required this.apiKey,
    required this.transcriptionModel,
    required this.translationModel,
    required this.summaryModel,
    required this.reasoningEffort,
    this.summaryPrompt,
    this.localAiLlmUrl,
    this.localAiWhisperUrl,
  });

  final AiProviderType provider;
  final bool isRealtime;
  final String targetLanguageCode;
  final String apiKey;
  final String transcriptionModel;
  final String translationModel;
  final String summaryModel;
  final String? reasoningEffort;
  final String? summaryPrompt;
  final String? localAiLlmUrl;
  final String? localAiWhisperUrl;
}

enum RealtimeConnectionState {
  notApplicable,
  connecting,
  connected,
  disconnected,
  stopping,
}

class ActiveRecordingSession {
  ActiveRecordingSession(this.metadata)
      : _realtimeConnectionState = metadata.isRealtime
            ? RealtimeConnectionState.connecting
            : RealtimeConnectionState.notApplicable;

  final RecordingSessionMetadata metadata;
  RealtimeConnectionState _realtimeConnectionState;

  RealtimeConnectionState get realtimeConnectionState =>
      _realtimeConnectionState;

  bool get canStreamMicrophone =>
      !metadata.isRealtime ||
      _realtimeConnectionState == RealtimeConnectionState.connected;

  void markRealtimeConnected() {
    if (metadata.isRealtime &&
        _realtimeConnectionState == RealtimeConnectionState.connecting) {
      _realtimeConnectionState = RealtimeConnectionState.connected;
    }
  }

  bool markRealtimeDisconnected() {
    if (!metadata.isRealtime) return false;
    final wasUnexpected =
        _realtimeConnectionState != RealtimeConnectionState.stopping &&
            _realtimeConnectionState != RealtimeConnectionState.disconnected;
    _realtimeConnectionState = RealtimeConnectionState.disconnected;
    return wasUnexpected;
  }

  void markStopping() {
    if (metadata.isRealtime) {
      _realtimeConnectionState = RealtimeConnectionState.stopping;
    }
  }
}

bool microphoneControlEnabled({
  required bool isRecording,
  required bool hasActiveApiKey,
  required bool providerSupportsAudio,
}) {
  return isRecording || (hasActiveApiKey && providerSupportsAudio);
}
