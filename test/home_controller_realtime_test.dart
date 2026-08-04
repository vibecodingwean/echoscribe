import 'dart:async';

import 'package:echoscribe/controllers/home_controller.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/ai/ai_provider_factory.dart';
import 'package:echoscribe/services/ai/realtime_transcription_client.dart';
import 'package:echoscribe/services/gemini_service.dart';
import 'package:echoscribe/services/image_service.dart';
import 'package:echoscribe/services/local_ai_health_service.dart';
import 'package:echoscribe/services/recorder_service.dart';
import 'package:echoscribe/services/summary_service.dart';
import 'package:echoscribe/services/translation_service.dart';
import 'package:echoscribe/services/whisper_service.dart';
import 'package:echoscribe/services/xai_speech_service.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/state/playback_state.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in <String>{
      'com.llfbandit.record/messages',
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
    }) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channel),
        (_) async => null,
      );
    }
  });

  test(
    'disconnect during microphone startup cannot leave realtime recording active',
    () async {
      final recorder = FakeRecorder(pauseAudioStreamStartup: true);
      final client = FakeRealtimeClient();
      final content = ContentState();
      final controller = buildController(
        settings: SettingsState()
          ..setProvider(AiProviderType.elevenLabs)
          ..setElevenLabsKey('session-key'),
        content: content,
        recorder: recorder,
        realtimeClient: client,
      );

      final start = controller.startRecording();
      await recorder.audioStreamStartupEntered.future;
      client.disconnect();
      recorder.completeAudioStreamStartup();
      await start;

      expect(content.isRecording, isFalse);
      expect(recorder.isStreaming, isFalse);
      recorder.emitAudio(<int>[1, 2, 3]);
      await pumpEventQueue();
      expect(client.sentChunks, isEmpty);
    },
  );

  test('provider change cannot bypass realtime finish and cleanup', () async {
    final settings = SettingsState()
      ..setProvider(AiProviderType.elevenLabs)
      ..setElevenLabsKey('session-key');
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(transcript: 'hello world');
    final content = ContentState();
    final controller = buildController(
      settings: settings,
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    await controller.startRecording();
    expect(content.isRecording, isTrue);

    settings
      ..setProvider(AiProviderType.anthropic)
      ..setAnthropicKey('different-key');
    await controller.stopAndTranscribe();

    expect(client.finishAudioCalls, 1);
    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
    expect(recorder.isStreaming, isFalse);
  });

  test('dispose during playback stop prevents recording startup', () async {
    final playback = PausingPlaybackState();
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient();
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setElevenLabsKey('session-key'),
      content: content,
      recorder: recorder,
      realtimeClient: client,
      playback: playback,
    );

    final start = controller.startRecording();
    await playback.stopEntered.future;
    controller.dispose();
    playback.completeStop();
    await start;

    expect(client.connectCalls, 0);
    expect(recorder.startAudioStreamCalls, 0);
    expect(content.isRecording, isFalse);
  });

  test('dispose during realtime connect prevents microphone startup', () async {
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(pauseConnect: true);
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setElevenLabsKey('session-key'),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    final start = controller.startRecording();
    await client.connectEntered.future;
    controller.dispose();
    client.completeConnect();
    await start;

    expect(recorder.startAudioStreamCalls, 0);
    expect(content.isRecording, isFalse);
  });

  test('dispose during audio startup stops the late microphone stream',
      () async {
    final recorder = FakeRecorder(pauseAudioStreamStartup: true);
    final client = FakeRealtimeClient();
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setElevenLabsKey('session-key'),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    final start = controller.startRecording();
    await recorder.audioStreamStartupEntered.future;
    controller.dispose();
    recorder.completeAudioStreamStartup();
    await start;

    expect(content.isRecording, isFalse);
    expect(recorder.isStreaming, isFalse);
  });

  test('audio subscription cancellation failure still cleans realtime state',
      () async {
    final recorder = FakeRecorder(throwOnAudioCancel: true);
    final client = FakeRealtimeClient(transcript: 'hello');
    final content = ContentState();
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(recorder.stopRecordingCalls, greaterThanOrEqualTo(1));
    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
  });

  test('recorder stop failure still closes realtime client and resets state',
      () async {
    final recorder = FakeRecorder(throwOnStop: true);
    final client = FakeRealtimeClient(transcript: 'hello');
    final content = ContentState();
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
  });

  test('finishAudio failure still closes realtime client and resets state',
      () async {
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(
      transcript: 'hello',
      throwOnFinishAudio: true,
    );
    final content = ContentState();
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
  });

  test('finalization delay failure still closes realtime client', () async {
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(transcript: 'hello');
    final content = ContentState();
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
      waitForRealtimeFinalization: (_) => Future<void>.error('delay failed'),
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
  });

  test('client close failure cannot prevent realtime state reset', () async {
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(
      transcript: 'hello',
      throwOnClose: true,
    );
    final content = ContentState();
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(client.closeCalls, greaterThanOrEqualTo(1));
    expect(content.isRecording, isFalse);
    expect(recorder.isStreaming, isFalse);
  });

  test('a second start is rejected while the first start is in progress',
      () async {
    final recorder = FakeRecorder();
    final client = FakeRealtimeClient(pauseConnect: true);
    final content = ContentState();
    final errors = <String>[];
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
      errors: errors,
    );

    final firstStart = controller.startRecording();
    await client.connectEntered.future;
    final secondStart = controller.startRecording();
    await pumpEventQueue();
    client.completeConnect();
    await Future.wait(<Future<void>>[firstStart, secondStart]);

    expect(client.connectCalls, 1);
    expect(recorder.startAudioStreamCalls, 1);
    expect(errors, contains('Recording is already starting or active.'));
  });

  test('Local AI startup preflight uses the frozen session configuration',
      () async {
    final settings = SettingsState()
      ..setProvider(AiProviderType.localAi)
      ..setLocalAiWhisperUrl('http://original-whisper.test/transcribe')
      ..setLocalAiWhisperModel('original-whisper-model')
      ..setLocalAiLlmUrl('http://original-llm.test/generate')
      ..setLocalAiLlmModel('original-llm-model');
    final recorder = FakeRecorder();
    final checks = <(String, String, String)>[];
    final controller = buildController(
      settings: settings,
      content: ContentState(),
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
      localAiWhisperCheck: ({required endpoint, required model}) async {
        checks.add(('whisper', endpoint, model));
        settings
          ..setProvider(AiProviderType.elevenLabs)
          ..setLocalAiWhisperUrl('http://changed-whisper.test/transcribe')
          ..setLocalAiWhisperModel('changed-whisper-model')
          ..setLocalAiLlmUrl('http://changed-llm.test/generate')
          ..setLocalAiLlmModel('changed-llm-model');
        return const LocalAiCheckResult(message: 'whisper ok');
      },
      localAiLlmCheck: ({required endpoint, required model}) async {
        checks.add(('llm', endpoint, model));
        return const LocalAiCheckResult(message: 'llm ok');
      },
    );

    await controller.startRecording();

    expect(checks, <(String, String, String)>[
      (
        'whisper',
        'http://original-whisper.test/transcribe',
        'original-whisper-model',
      ),
      (
        'llm',
        'http://original-llm.test/generate',
        'original-llm-model',
      ),
    ]);
    expect(recorder.startRecordingCalls, 1);
  });

  test('dispose after Local AI Whisper check cancels before the LLM check',
      () async {
    final recorder = FakeRecorder();
    var llmChecks = 0;
    late HomeController controller;
    controller = buildController(
      settings: SettingsState()
        ..setProvider(AiProviderType.localAi)
        ..setLocalAiWhisperUrl('http://whisper.test/transcribe')
        ..setLocalAiLlmUrl('http://llm.test/generate'),
      content: ContentState(),
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
      localAiWhisperCheck: ({required endpoint, required model}) async {
        controller.dispose();
        return const LocalAiCheckResult(message: 'whisper ok');
      },
      localAiLlmCheck: ({required endpoint, required model}) async {
        llmChecks++;
        return const LocalAiCheckResult(message: 'llm ok');
      },
    );

    await controller.startRecording();
    await pumpEventQueue();

    expect(llmChecks, 0);
    expect(recorder.startRecordingCalls, 0);
  });

  test('dispose during Local AI LLM check cancels before recorder startup',
      () async {
    final recorder = FakeRecorder();
    late HomeController controller;
    controller = buildController(
      settings: SettingsState()
        ..setProvider(AiProviderType.localAi)
        ..setLocalAiWhisperUrl('http://whisper.test/transcribe')
        ..setLocalAiLlmUrl('http://llm.test/generate'),
      content: ContentState(),
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
      localAiWhisperCheck: ({required endpoint, required model}) async =>
          const LocalAiCheckResult(message: 'whisper ok'),
      localAiLlmCheck: ({required endpoint, required model}) async {
        controller.dispose();
        return const LocalAiCheckResult(message: 'llm ok');
      },
    );

    await controller.startRecording();
    await pumpEventQueue();

    expect(recorder.startRecordingCalls, 0);
  });

  test('non-realtime startRecording failure stops acquired recorder', () async {
    final recorder = FakeRecorder(throwOnStart: true);
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
    );

    await controller.startRecording();

    expect(recorder.startRecordingCalls, 1);
    expect(recorder.stopRecordingCalls, 1);
    expect(content.isRecording, isFalse);
  });

  test('non-realtime isRecording failure stops acquired recorder', () async {
    final recorder = FakeRecorder(isRecordingResult: false);
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
    );

    await controller.startRecording();

    expect(recorder.startRecordingCalls, 1);
    expect(recorder.stopRecordingCalls, 1);
    expect(content.isRecording, isFalse);
  });

  test('non-realtime amplitude setup failure stops acquired recorder',
      () async {
    final recorder = FakeRecorder(throwOnLevelListen: true);
    final content = ContentState();
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
    );

    await controller.startRecording();

    expect(recorder.startRecordingCalls, 1);
    expect(recorder.stopRecordingCalls, 1);
    expect(content.isRecording, isFalse);
  });

  test('non-realtime post-amplitude failure cancels its subscription',
      () async {
    final recorder = FakeRecorder();
    final content = ThrowingRecordingLogContentState();
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
    );

    await controller.startRecording();

    expect(recorder.stopRecordingCalls, 1);
    expect(recorder.amplitudeCancelCalls, 1);
    expect(content.isRecording, isFalse);
  });

  test('non-realtime stop failure still cancels amplitude and resets state',
      () async {
    final recorder = FakeRecorder(throwOnStop: true);
    final content = ContentState();
    final errors = <String>[];
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
      errors: errors,
    );

    await controller.startRecording();
    recorder.emitLevel(0.8);
    await pumpEventQueue();
    expect(controller.levelNotifier.value, 0.8);

    await controller.stopAndTranscribe();

    expect(recorder.amplitudeCancelCalls, 1);
    expect(controller.levelNotifier.value, 0);
    expect(controller.smoothedLevelNotifier.value, 0);
    expect(content.isRecording, isFalse);
    expect(content.isTranscribing, isFalse);
    expect(errors, contains('Transcription failed'));
  });

  test('non-realtime cleanup failures are isolated from state reset', () async {
    final recorder = FakeRecorder(
      throwOnStop: true,
      throwOnAmplitudeCancel: true,
    );
    final content = ContentState();
    final errors = <String>[];
    final controller = buildController(
      settings: SettingsState(),
      content: content,
      recorder: recorder,
      realtimeClient: FakeRealtimeClient(),
      errors: errors,
    );

    await controller.startRecording();
    await controller.stopAndTranscribe();

    expect(recorder.amplitudeCancelCalls, 1);
    expect(content.isRecording, isFalse);
    expect(content.isTranscribing, isFalse);
    expect(errors, contains('Transcription failed'));
  });

  test('realtime finalization rejects starts until summary work is finished',
      () async {
    final recorder = FakeRecorder();
    final content = ContentState()..setOutputMode(OutputMode.summary);
    final client = FakeRealtimeClient(transcript: 'session transcript');
    final provider = PausingSummaryAiProvider();
    final errors = <String>[];
    final controller = buildController(
      settings: SettingsState()
        ..setOpenAiKey('session-key')
        ..setOpenAiRealtime(true),
      content: content,
      recorder: recorder,
      realtimeClient: client,
      aiFactory: FixedAiProviderFactory(provider),
      errors: errors,
    );

    await controller.startRecording();
    final finalization = controller.stopAndTranscribe();
    await provider.summaryEntered.future;

    await controller.startRecording();
    final startsDuringFinalization = recorder.startAudioStreamCalls;

    provider.completeSummary();
    await finalization;
    if (startsDuringFinalization != 1) {
      await controller.stopAndTranscribe();
    }

    expect(startsDuringFinalization, 1);
    expect(errors, contains('Recording is already starting or active.'));

    await controller.startRecording();
    expect(recorder.startAudioStreamCalls, 2);
    expect(content.isRecording, isTrue);
    await controller.stopAndTranscribe();
  });

  test('simultaneous realtime stops share one finalization', () async {
    final persistenceEntered = Completer<void>();
    final allowPersistence = Completer<void>();
    var persistenceWrites = 0;
    final recorder = FakeRecorder();
    final content = ClipboardCountingContentState(
      historyWriter: (encoded) async {
        persistenceWrites++;
        if (!persistenceEntered.isCompleted) persistenceEntered.complete();
        await allowPersistence.future;
      },
    );
    final client = FakeRealtimeClient(transcript: 'session transcript');
    final errors = <String>[];
    final controller = buildController(
      settings: elevenLabsSettings(),
      content: content,
      recorder: recorder,
      realtimeClient: client,
      errors: errors,
    );

    await controller.startRecording();
    final firstStop = controller.stopAndTranscribe();
    final secondStop = controller.stopAndTranscribe();
    var stopCompleted = false;
    unawaited(firstStop.whenComplete(() => stopCompleted = true));
    final sharedFuture = identical(firstStop, secondStop);
    await persistenceEntered.future;
    await pumpEventQueue();
    final completedBeforePersistence = stopCompleted;

    await controller.startRecording();
    final startsDuringPersistence = recorder.startAudioStreamCalls;
    final rejectedDuringPersistence =
        errors.contains('Recording is already starting or active.');

    allowPersistence.complete();
    await Future.wait(<Future<void>>[firstStop, secondStop]);
    if (startsDuringPersistence != 1) {
      await controller.stopAndTranscribe();
    }

    expect(startsDuringPersistence, 1);
    expect(rejectedDuringPersistence, isTrue);
    expect(completedBeforePersistence, isFalse);
    expect(sharedFuture, isTrue);
    expect(client.finishAudioCalls, 1);
    expect(persistenceWrites, 1);
    expect(content.history, hasLength(1));
    expect(content.clipboardWrites, 1);

    await controller.startRecording();
    expect(recorder.startAudioStreamCalls, 2);
    await controller.stopAndTranscribe();
  });

  test('Local AI finalization uses endpoints frozen at recording start',
      () async {
    final settings = SettingsState()
      ..setProvider(AiProviderType.localAi)
      ..setLocalAiLlmUrl('http://original-llm.test/api/generate')
      ..setLocalAiWhisperUrl(
        'http://original-whisper.test/v1/audio/transcriptions',
      );
    final recorder = FakeRecorder(recordingPath: '/tmp/recording.m4a');
    final client = FakeRealtimeClient();
    final factory = TrackingAiProviderFactory();
    final content = ContentState()..setOutputMode(OutputMode.summary);
    final checkedEndpoints = <String>[];
    final controller = buildController(
      settings: settings,
      content: content,
      recorder: recorder,
      realtimeClient: client,
      aiFactory: factory,
      localAiWhisperCheck: ({required endpoint, required model}) async {
        checkedEndpoints.add(endpoint);
        return const LocalAiCheckResult(message: 'whisper ok');
      },
      localAiLlmCheck: ({required endpoint, required model}) async {
        checkedEndpoints.add(endpoint);
        return const LocalAiCheckResult(message: 'llm ok');
      },
    );

    await controller.startRecording();
    settings
      ..setLocalAiLlmUrl('http://changed-llm.test/api/generate')
      ..setLocalAiWhisperUrl(
        'http://changed-whisper.test/v1/audio/transcriptions',
      );
    await controller.stopAndTranscribe();

    expect(
      factory.localAiRoutes,
      isNotEmpty,
    );
    expect(
      factory.localAiRoutes,
      everyElement(
        const (
          'http://original-llm.test/api/generate',
          'http://original-whisper.test/v1/audio/transcriptions',
        ),
      ),
    );
    expect(checkedEndpoints, isNot(contains(contains('changed-'))));
    expect(content.currentSummaryValue, 'summary');
  });
}

SettingsState elevenLabsSettings() => SettingsState()
  ..setProvider(AiProviderType.elevenLabs)
  ..setElevenLabsKey('session-key');

HomeController buildController({
  required SettingsState settings,
  required ContentState content,
  required FakeRecorder recorder,
  required FakeRealtimeClient realtimeClient,
  PlaybackState? playback,
  Future<void> Function(Duration)? waitForRealtimeFinalization,
  List<String>? errors,
  AiProviderFactory? aiFactory,
  Future<LocalAiCheckResult> Function({
    required String endpoint,
    required String model,
  })? localAiWhisperCheck,
  Future<LocalAiCheckResult> Function({
    required String endpoint,
    required String model,
  })? localAiLlmCheck,
}) {
  return HomeController(
    settings: settings,
    content: content,
    playback: playback ?? PlaybackState(),
    recorder: recorder,
    aiFactory: aiFactory ??
        AiProviderFactory(
          whisper: WhisperService(),
          gemini: GeminiService(),
          summary: SummaryService(),
          translation: TranslationService(),
          image: ImageService(),
          xaiSpeech: XaiSpeechService(),
        ),
    showError: (message) => errors?.add(message),
    showSuccess: (_) {},
    realtimeClientFactory: (_) => realtimeClient,
    waitForRealtimeFinalization: waitForRealtimeFinalization ?? (_) async {},
    localAiWhisperCheck: localAiWhisperCheck,
    localAiLlmCheck: localAiLlmCheck,
  );
}

class FakeRecorder extends RecorderService {
  FakeRecorder({
    this.pauseAudioStreamStartup = false,
    this.throwOnAudioCancel = false,
    this.throwOnStop = false,
    this.throwOnStart = false,
    this.throwOnLevelListen = false,
    this.throwOnAmplitudeCancel = false,
    this.isRecordingResult,
    this.recordingPath,
  }) {
    _levels = StreamController<double>.broadcast(
      onCancel: () => amplitudeCancelCalls++,
    );
  }

  final bool pauseAudioStreamStartup;
  final bool throwOnAudioCancel;
  final bool throwOnStop;
  final bool throwOnStart;
  final bool throwOnLevelListen;
  final bool throwOnAmplitudeCancel;
  final bool? isRecordingResult;
  final String? recordingPath;
  final StreamController<List<int>> _audio =
      StreamController<List<int>>.broadcast();
  late final StreamController<double> _levels;
  final Completer<void> audioStreamStartupEntered = Completer<void>();
  final Completer<void> _allowAudioStreamStartup = Completer<void>();
  bool isStreaming = false;
  int startAudioStreamCalls = 0;
  int startRecordingCalls = 0;
  int stopRecordingCalls = 0;
  int amplitudeCancelCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isRecording() async => isRecordingResult ?? isStreaming;

  @override
  Future<String?> startRecording() async {
    startRecordingCalls++;
    if (throwOnStart) throw StateError('start');
    isStreaming = true;
    return null;
  }

  @override
  Future<Stream<List<int>>?> startAudioStream({int sampleRate = 24000}) async {
    startAudioStreamCalls++;
    if (!audioStreamStartupEntered.isCompleted) {
      audioStreamStartupEntered.complete();
    }
    if (pauseAudioStreamStartup) await _allowAudioStreamStartup.future;
    isStreaming = true;
    return throwOnAudioCancel
        ? CancelThrowingStream<List<int>>(_audio.stream)
        : _audio.stream;
  }

  void completeAudioStreamStartup() {
    if (!_allowAudioStreamStartup.isCompleted) {
      _allowAudioStreamStartup.complete();
    }
  }

  void emitAudio(List<int> chunk) => _audio.add(chunk);

  void emitLevel(double level) => _levels.add(level);

  @override
  Stream<double> levelStream({
    Duration interval = const Duration(milliseconds: 120),
  }) =>
      throwOnLevelListen
          ? ThrowingListenStream<double>()
          : throwOnAmplitudeCancel
              ? CancelThrowingStream<double>(_levels.stream)
              : _levels.stream;

  @override
  Future<String?> stopRecording() async {
    stopRecordingCalls++;
    if (throwOnStop) throw StateError('stop');
    isStreaming = false;
    return recordingPath;
  }
}

class ThrowingListenStream<T> extends Stream<T> {
  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    throw StateError('listen');
  }
}

class ThrowingRecordingLogContentState extends ContentState {
  @override
  void appendLogLine(String line) {
    if (line == '🎙️ Recording started...') {
      throw StateError('recording log');
    }
    super.appendLogLine(line);
  }
}

class ClipboardCountingContentState extends ContentState {
  ClipboardCountingContentState({super.historyWriter});

  int clipboardWrites = 0;

  @override
  Future<void> addToClipboard(String text) async {
    clipboardWrites++;
  }
}

class FakeRealtimeClient implements RealtimeTranscriptionClient {
  FakeRealtimeClient({
    this.transcript = '',
    this.pauseConnect = false,
    this.throwOnFinishAudio = false,
    this.throwOnClose = false,
  });

  final String transcript;
  final bool pauseConnect;
  final bool throwOnFinishAudio;
  final bool throwOnClose;
  VoidCallback? _onDisconnected;
  final List<List<int>> sentChunks = <List<int>>[];
  final Completer<void> connectEntered = Completer<void>();
  final Completer<void> _allowConnect = Completer<void>();
  int connectCalls = 0;
  int finishAudioCalls = 0;
  int closeCalls = 0;

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
    connectCalls++;
    if (!connectEntered.isCompleted) connectEntered.complete();
    if (pauseConnect) await _allowConnect.future;
    _onDisconnected = onDisconnected;
    onConnected();
    if (transcript.isNotEmpty) onTranscriptCompleted(transcript);
  }

  void completeConnect() {
    if (!_allowConnect.isCompleted) _allowConnect.complete();
  }

  void disconnect() => _onDisconnected?.call();

  @override
  void sendAudioChunk(List<int> chunk) => sentChunks.add(List<int>.from(chunk));

  @override
  Future<void> finishAudio() async {
    finishAudioCalls++;
    if (throwOnFinishAudio) throw StateError('finishAudio');
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (throwOnClose) throw StateError('close');
  }
}

class PausingPlaybackState extends PlaybackState {
  final Completer<void> stopEntered = Completer<void>();
  final Completer<void> _allowStop = Completer<void>();

  @override
  bool get isPlaying => true;

  @override
  Future<void> stopAudio() async {
    if (!stopEntered.isCompleted) stopEntered.complete();
    await _allowStop.future;
  }

  void completeStop() {
    if (!_allowStop.isCompleted) _allowStop.complete();
  }
}

class CancelThrowingStream<T> extends Stream<T> {
  CancelThrowingStream(this.inner);

  final Stream<T> inner;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return CancelThrowingSubscription<T>(
      inner.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
    );
  }
}

class CancelThrowingSubscription<T> implements StreamSubscription<T> {
  CancelThrowingSubscription(this.inner);

  final StreamSubscription<T> inner;

  @override
  Future<void> cancel() async {
    await inner.cancel();
    throw StateError('cancel');
  }

  @override
  void onData(void Function(T data)? handleData) => inner.onData(handleData);

  @override
  void onError(Function? handleError) => inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => inner.pause(resumeSignal);

  @override
  void resume() => inner.resume();

  @override
  bool get isPaused => inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => inner.asFuture<E>(futureValue);
}

class TrackingAiProviderFactory extends AiProviderFactory {
  TrackingAiProviderFactory()
      : super(
          whisper: WhisperService(),
          gemini: GeminiService(),
          summary: SummaryService(),
          translation: TranslationService(),
          image: ImageService(),
          xaiSpeech: XaiSpeechService(),
        );

  final List<(String, String)> localAiRoutes = <(String, String)>[];

  @override
  AiProvider create(
    AiProviderType provider, {
    SettingsState? settings,
    String? localAiLlmUrl,
    String? localAiWhisperUrl,
  }) {
    if (provider == AiProviderType.localAi) {
      localAiRoutes.add((localAiLlmUrl!, localAiWhisperUrl!));
      return const TrackingAiProvider();
    }
    return super.create(
      provider,
      settings: settings,
      localAiLlmUrl: localAiLlmUrl,
      localAiWhisperUrl: localAiWhisperUrl,
    );
  }
}

class TrackingAiProvider implements AiProvider {
  const TrackingAiProvider();

  @override
  Future<String> transcribe({
    required String apiKey,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String model,
  }) async =>
      'transcript';

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
    String? reasoningEffort,
  }) async =>
      text;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) async =>
      'summary';

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) =>
      throw UnimplementedError();
}

class FixedAiProviderFactory extends AiProviderFactory {
  FixedAiProviderFactory(this.provider)
      : super(
          whisper: WhisperService(),
          gemini: GeminiService(),
          summary: SummaryService(),
          translation: TranslationService(),
          image: ImageService(),
          xaiSpeech: XaiSpeechService(),
        );

  final AiProvider provider;

  @override
  AiProvider create(
    AiProviderType providerType, {
    SettingsState? settings,
    String? localAiLlmUrl,
    String? localAiWhisperUrl,
  }) =>
      provider;
}

class PausingSummaryAiProvider implements AiProvider {
  final Completer<void> summaryEntered = Completer<void>();
  final Completer<void> _allowSummary = Completer<void>();

  void completeSummary() {
    if (!_allowSummary.isCompleted) _allowSummary.complete();
  }

  @override
  Future<String> transcribe({
    required String apiKey,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String model,
  }) async =>
      'session transcript';

  @override
  Future<String> translate({
    required String apiKey,
    required String text,
    required String targetLanguageCode,
    required String model,
    String? reasoningEffort,
  }) async =>
      text;

  @override
  Future<String> summarize({
    required String apiKey,
    required String text,
    required String model,
    required String targetLanguageCode,
    String? summaryPrompt,
    String? reasoningEffort,
  }) async {
    if (!summaryEntered.isCompleted) summaryEntered.complete();
    await _allowSummary.future;
    return 'session summary';
  }

  @override
  Future<Uint8List> generateImage({
    required String apiKey,
    required String prompt,
    required String model,
  }) =>
      throw UnimplementedError();
}
