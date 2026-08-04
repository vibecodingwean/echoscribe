import 'package:echoscribe/services/ai/elevenlabs_realtime_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classifies every documented ElevenLabs realtime error message type',
      () {
    const documentedErrorTypes = <String>{
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

    for (final messageType in documentedErrorTypes) {
      final classified = classifyElevenLabsRealtimeError(<String, dynamic>{
        'message_type': messageType,
        'message': 'failure for $messageType',
      });

      expect(classified, isNotNull, reason: messageType);
      expect(classified!.messageType, messageType);
      expect(classified.message, 'failure for $messageType');
    }
  });

  test('does not classify non-error realtime messages', () {
    expect(
      classifyElevenLabsRealtimeError(<String, dynamic>{
        'message_type': 'partial_transcript',
        'text': 'hello',
      }),
      isNull,
    );
  });

  test('falls back to the documented error type when details are absent', () {
    final classified = classifyElevenLabsRealtimeError(<String, dynamic>{
      'message_type': 'queue_overflow',
    });

    expect(classified?.message, 'queue_overflow');
  });
}
