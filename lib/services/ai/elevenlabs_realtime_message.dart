const Set<String> elevenLabsRealtimeErrorMessageTypes = <String>{
  'error',
  'auth_error',
  'quota_exceeded',
  'rate_limited',
  'commit_throttled',
  'unaccepted_terms',
  'queue_overflow',
  'resource_exhausted',
  'session_time_limit_exceeded',
  'input_error',
  'chunk_size_exceeded',
  'insufficient_audio_activity',
  'transcriber_error',
};

class ElevenLabsRealtimeError {
  const ElevenLabsRealtimeError({
    required this.messageType,
    required this.message,
  });

  final String messageType;
  final String message;
}

ElevenLabsRealtimeError? classifyElevenLabsRealtimeError(
  Map<String, dynamic> event,
) {
  final messageType = event['message_type'];
  if (messageType is! String ||
      !elevenLabsRealtimeErrorMessageTypes.contains(messageType)) {
    return null;
  }

  final details = event['error'] ?? event['message'];
  return ElevenLabsRealtimeError(
    messageType: messageType,
    message: details?.toString() ?? messageType,
  );
}
