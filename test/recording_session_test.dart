import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/recording_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('active recording session', () {
    test('retains immutable provider and realtime metadata', () {
      const metadata = RecordingSessionMetadata(
        provider: AiProviderType.elevenLabs,
        isRealtime: true,
        targetLanguageCode: 'auto',
        apiKey: 'session-key',
        transcriptionModel: 'scribe_v2_realtime',
        translationModel: '',
        summaryModel: '',
        reasoningEffort: null,
      );
      final session = ActiveRecordingSession(metadata);

      expect(session.metadata.provider, AiProviderType.elevenLabs);
      expect(session.metadata.isRealtime, isTrue);
      expect(session.metadata.apiKey, 'session-key');
    });

    test('prevents microphone startup after realtime disconnect', () {
      final session = ActiveRecordingSession(
        const RecordingSessionMetadata(
          provider: AiProviderType.elevenLabs,
          isRealtime: true,
          targetLanguageCode: 'auto',
          apiKey: 'session-key',
          transcriptionModel: 'scribe_v2_realtime',
          translationModel: '',
          summaryModel: '',
          reasoningEffort: null,
        ),
      );

      session.markRealtimeConnected();
      expect(session.canStreamMicrophone, isTrue);

      expect(session.markRealtimeDisconnected(), isTrue);
      expect(session.canStreamMicrophone, isFalse);
    });

    test('does not treat disconnect during an intentional stop as a failure',
        () {
      final session = ActiveRecordingSession(
        const RecordingSessionMetadata(
          provider: AiProviderType.openai,
          isRealtime: true,
          targetLanguageCode: 'auto',
          apiKey: 'session-key',
          transcriptionModel: 'realtime-model',
          translationModel: 'translation-model',
          summaryModel: 'summary-model',
          reasoningEffort: null,
        ),
      )..markRealtimeConnected();

      session.markStopping();

      expect(session.markRealtimeDisconnected(), isFalse);
      expect(session.canStreamMicrophone, isFalse);
    });
  });

  test('recording keeps microphone control enabled despite current settings',
      () {
    expect(
      microphoneControlEnabled(
        isRecording: true,
        hasActiveApiKey: false,
        providerSupportsAudio: false,
      ),
      isTrue,
    );
    expect(
      microphoneControlEnabled(
        isRecording: false,
        hasActiveApiKey: false,
        providerSupportsAudio: true,
      ),
      isFalse,
    );
  });

  test('idle microphone needs an API key and an audio-capable provider', () {
    expect(
      microphoneControlEnabled(
        isRecording: false,
        hasActiveApiKey: true,
        providerSupportsAudio: true,
      ),
      isTrue,
    );
    expect(
      microphoneControlEnabled(
        isRecording: false,
        hasActiveApiKey: true,
        providerSupportsAudio: false,
      ),
      isFalse,
    );
  });
}
