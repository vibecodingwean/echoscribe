import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:async/async.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/state/playback_state.dart';
import 'package:echoscribe/services/recorder_service.dart';
import 'package:echoscribe/services/ai/ai_provider_factory.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/config/prompts.dart';
import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/services/tts_service.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/recording_session.dart';
import 'package:echoscribe/services/local_ai_health_service.dart';

import 'package:echoscribe/services/ai/openai_realtime_client.dart';
import 'package:echoscribe/services/ai/elevenlabs_realtime_client.dart';
import 'package:echoscribe/services/ai/realtime_transcription_client.dart';

class HomeController extends ChangeNotifier {
  final SettingsState settings;
  final ContentState content;
  final PlaybackState playback;
  final RecorderService recorder;
  final AiProviderFactory aiFactory;

  final void Function(String) showError;
  final void Function(String) showSuccess;

  CancelableOperation? _imageOp;
  Timer? _imageCycleTimer;
  bool _imageCycleDone = false;

  RealtimeTranscriptionClient? _realtimeClient;
  StreamSubscription<List<int>>? _audioStreamSub;
  bool _realtimeFailureInProgress = false;
  ActiveRecordingSession? _activeRecordingSession;
  ActiveRecordingSession? _startInProgressSession;
  ActiveRecordingSession? _finalizingRecordingSession;
  Future<void>? _recordingFinalization;
  bool _disposed = false;
  final RealtimeTranscriptionClient Function(bool useElevenLabs)
      _realtimeClientFactory;
  final Future<void> Function(Duration duration) _waitForRealtimeFinalization;
  final Future<LocalAiCheckResult> Function({
    required String endpoint,
    required String model,
  }) _localAiWhisperCheck;
  final Future<LocalAiCheckResult> Function({
    required String endpoint,
    required String model,
  }) _localAiLlmCheck;

  // Expose these for the UI to use
  final ValueNotifier<double> levelNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> smoothedLevelNotifier = ValueNotifier<double>(
    0.0,
  );
  StreamSubscription<double>? _ampSub;

  HomeController({
    required this.settings,
    required this.content,
    required this.playback,
    required this.recorder,
    required this.aiFactory,
    required this.showError,
    required this.showSuccess,
    RealtimeTranscriptionClient Function(bool useElevenLabs)?
        realtimeClientFactory,
    Future<void> Function(Duration duration)? waitForRealtimeFinalization,
    Future<LocalAiCheckResult> Function({
      required String endpoint,
      required String model,
    })? localAiWhisperCheck,
    Future<LocalAiCheckResult> Function({
      required String endpoint,
      required String model,
    })? localAiLlmCheck,
  })  : _realtimeClientFactory = realtimeClientFactory ??
            ((useElevenLabs) => useElevenLabs
                ? ElevenLabsRealtimeClient()
                : OpenAiRealtimeClient()),
        _waitForRealtimeFinalization =
            waitForRealtimeFinalization ?? Future<void>.delayed,
        _localAiWhisperCheck =
            localAiWhisperCheck ?? LocalAiHealthService.checkWhisper,
        _localAiLlmCheck = localAiLlmCheck ?? LocalAiHealthService.checkLlm;

  @override
  void dispose() {
    _disposed = true;
    final session = _activeRecordingSession;
    _activeRecordingSession = null;
    _startInProgressSession = null;
    session?.markStopping();

    final ampSub = _ampSub;
    _ampSub = null;
    final audioStreamSub = _audioStreamSub;
    _audioStreamSub = null;
    final realtimeClient = _realtimeClient;
    _realtimeClient = null;
    unawaited(
      _cleanupDetachedRecordingResources(
        ampSub: ampSub,
        audioStreamSub: audioStreamSub,
        realtimeClient: realtimeClient,
      ),
    );
    _imageOp?.cancel();
    _imageCycleTimer?.cancel();
    levelNotifier.dispose();
    smoothedLevelNotifier.dispose();
    super.dispose();
  }

  bool _isCurrentRecordingSession(ActiveRecordingSession session) =>
      !_disposed && identical(_activeRecordingSession, session);

  void _requireCurrentRecordingSession(ActiveRecordingSession session) {
    if (!_isCurrentRecordingSession(session)) {
      throw const _RecordingStartCancelled();
    }
  }

  void _stopImageCycle() {
    _imageCycleDone = true;
    _imageCycleTimer?.cancel();
    _imageCycleTimer = null;
  }

  void cancelActiveOperations() {
    if (_imageOp != null) {
      _imageOp?.cancel();
      _imageOp = null;
      _stopImageCycle();
      content.setGeneratingImage(false);
      content.appendLogLine('🛑 Image generation cancelled');
    }
    // Note: Add transcription/summary cancel here if needed later
  }

  Future<String> _transcribeAudio(
    String path,
    String filename,
    String mimeType, {
    int? fileSizeBytes,
    bool localAiPreflightDone = false,
    AiProviderType? provider,
    String? apiKey,
    String? transcriptionModel,
    String? localAiLlmUrl,
    String? localAiWhisperUrl,
  }) async {
    final activeProvider = provider ?? settings.provider;
    if (!activeProvider.supportsBatchTranscription) {
      throw AppException(
        '${activeProvider.brandName} supports live transcription only.',
      );
    }
    final brand = activeProvider.brandName;
    final model = transcriptionModel ?? settings.transcriptionModel;

    if (fileSizeBytes != null) {
      final sizeInMb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      content.appendLogLine('🎙️ Uploading $sizeInMb MB to $brand...');
    } else {
      content.appendLogLine('🎙️ Uploading audio to $brand...');
    }
    content.appendLogLine('🤖 Transcription Model: $model');

    if (activeProvider == AiProviderType.localAi && !localAiPreflightDone) {
      content.appendLogLine('🔌 Checking Local AI Whisper endpoint...');
      final check = await _localAiWhisperCheck(
        endpoint: localAiWhisperUrl ?? settings.localAiWhisperUrl,
        model: model,
      );
      content.appendLogLine('✅ ${check.message}');
    }

    final ai = aiFactory.create(
      activeProvider,
      settings: settings,
      localAiLlmUrl: localAiLlmUrl,
      localAiWhisperUrl: localAiWhisperUrl,
    );
    final text = await ai.transcribe(
      apiKey: apiKey ?? settings.activeApiKey,
      filePath: path,
      fileName: filename,
      mimeType: mimeType,
      model: model,
    );

    final wordCount = text.split(' ').length;
    content.appendLogLine('✅ Received $wordCount words');
    return text;
  }

  Future<String> _translateIfNeeded(
    AiProvider ai,
    String text,
    String targetLanguage, {
    AiProviderType? provider,
    String? apiKey,
    String? translationModel,
    String? reasoningEffort,
    String? localAiLlmUrl,
  }) async {
    if (targetLanguage == 'auto') return text;
    final activeProvider = provider ?? settings.provider;
    if (!activeProvider.supportsTranslation) {
      throw AppException(
        '${activeProvider.brandName} does not support translation.',
      );
    }

    final transModel = translationModel ?? settings.translationModel;
    final activeReasoningEffort = reasoningEffort ?? settings.reasoningEffort;
    final brand = activeProvider.brandName;
    content.appendLogLine('🌐 Translating via $brand...');
    content.appendLogLine('🤖 Translation Model: $transModel');
    if (activeReasoningEffort != null) {
      content.appendLogLine('🧠 Reasoning Effort: $activeReasoningEffort');
    }

    if (activeProvider == AiProviderType.localAi) {
      content.appendLogLine('🔌 Checking Local AI LLM endpoint...');
      final check = await _localAiLlmCheck(
        endpoint: localAiLlmUrl ?? settings.localAiLlmUrl,
        model: transModel,
      );
      content.appendLogLine('✅ ${check.message}');
    }
    content.appendLogLine('🌍 Target: $targetLanguage');

    final translated = await ai.translate(
      apiKey: apiKey ?? settings.activeApiKey,
      text: text,
      targetLanguageCode: targetLanguage,
      model: transModel,
      reasoningEffort: activeReasoningEffort,
    );
    content.appendLogLine('✅ Translation successful');
    return translated;
  }

  Future<String> _summarize(
    AiProvider ai,
    String text, {
    AiProviderType? provider,
    String? apiKey,
    String? summaryModel,
    String? reasoningEffort,
    String? targetLanguageCode,
    String? summaryPrompt,
    String? localAiLlmUrl,
  }) async {
    final activeProvider = provider ?? settings.provider;
    if (!activeProvider.supportsSummary) {
      throw AppException(
        '${activeProvider.brandName} does not support summaries.',
      );
    }
    final brand = activeProvider.brandName;
    final sumModel = summaryModel ?? settings.summaryModel;
    final activeReasoningEffort = reasoningEffort ?? settings.reasoningEffort;
    content.appendLogLine('🤖 Summarizing with $brand...');
    content.appendLogLine('🤖 Summary Model: $sumModel');
    if (activeReasoningEffort != null) {
      content.appendLogLine('🧠 Reasoning Effort: $activeReasoningEffort');
    }

    if (activeProvider == AiProviderType.localAi) {
      content.appendLogLine('🔌 Checking Local AI LLM before summary...');
      final check = await _localAiLlmCheck(
        endpoint: localAiLlmUrl ?? settings.localAiLlmUrl,
        model: sumModel,
      );
      content.appendLogLine('✅ ${check.message}');
    }

    final summary = await ai.summarize(
      apiKey: apiKey ?? settings.activeApiKey,
      text: text.trim(),
      model: sumModel,
      targetLanguageCode: targetLanguageCode ?? settings.targetLanguageCode,
      summaryPrompt: summaryPrompt ?? settings.summaryPrompt,
      reasoningEffort: activeReasoningEffort,
    );

    content.setCurrentSummary(summary);
    await content.updateActiveHistoryAndPersist(
      summary: summary,
      mode: OutputMode.summary.name,
      text: summary,
    );
    content.appendLogLine('✨ Summary generated (${summary.length} chars)');
    return summary;
  }

  Future<void> _saveToHistory(String text, String language) {
    return content.addHistoryAndPersist(
      TranscriptionItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        createdAt: DateTime.now(),
        transcript: text,
        summary: '',
        language: language,
        mode: OutputMode.transcription.name,
      ),
      setActive: true,
    );
  }

  void _logFinalResponse(String text) {
    content.appendLogLine('💬 Response (final text):');
    content.appendLogLine(text);
    content.appendLogLine('✅ Done');
  }

  Future<void> generateImageFromCurrentContent({
    required Function(String) showProgressToast,
    required Function() hideProgressToast,
    required Function(String) replaceProgressToast,
  }) async {
    if (content.isGeneratingImage) {
      cancelActiveOperations();
      hideProgressToast();
      return;
    }

    if (!settings.provider.supportsImage) {
      showError(
        '${settings.provider.brandName} does not support image generation.',
      );
      return;
    }
    if (!settings.hasActiveApiKey) {
      showError(settings.missingProviderConfigMessage);
      return;
    }

    final source = content.isSummaryMode
        ? content.currentSummaryValue.trim()
        : content.currentTranscriptValue.trim();
    if (source.isEmpty) return;

    var prompt =
        "Generate an image that represents the following text. Be creative, visual, and accurate to the core theme. Text:\n\n$source";
    if (settings.provider == AiProviderType.openai) {
      prompt =
          "Generate a realistic image that represents the following text. Focus on high quality, lifelike details. Text:\n\n$source";
    }

    content.setGeneratingImage(true);
    content.setCurrentImageBytes(null);

    final brand = settings.provider.brandName;
    final model = settings.imageModel;

    showProgressToast('Uploading prompt to $brand...');

    int remaining = switch (settings.provider) {
      AiProviderType.openai => 70,
      AiProviderType.gemini => 25,
      AiProviderType.xai => 15,
      AiProviderType.anthropic => 0,
      AiProviderType.localAi => 0,
      AiProviderType.elevenLabs => 0,
    };

    _imageCycleDone = false;

    void startCycling() {
      _imageCycleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_imageCycleDone) {
          timer.cancel();
          return;
        }
        remaining--;

        final int cyclePos = timer.tick % 9;
        if (cyclePos < 3) {
          replaceProgressToast(
            remaining > 0
                ? 'Estimate: ~$remaining seconds...'
                : 'Waiting for reply...',
          );
        } else if (cyclePos < 6) {
          replaceProgressToast('Model: $model');
        } else {
          replaceProgressToast('Waiting for reply...');
        }
      });
    }

    try {
      content.appendLogLine('🎨 Generating image with $brand...');
      content.appendLogLine('🤖 Model: $model');

      final ai = aiFactory.create(settings.provider, settings: settings);

      _imageOp = CancelableOperation.fromFuture(
        ai.generateImage(
          apiKey: settings.activeApiKey,
          prompt: prompt,
          model: model,
        ),
      );

      Future.delayed(const Duration(seconds: 2), () {
        if (!_imageCycleDone) startCycling();
      });

      final bytes = await _imageOp!.value;
      _stopImageCycle();
      _imageOp = null;

      final sizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
      content.appendLogLine('✅ Image received ($sizeKb KB)');
      content.setCurrentImageBytes(bytes);
      replaceProgressToast('Image received ($sizeKb KB)');
      Future.delayed(const Duration(seconds: 2), () {
        if (!content.isGeneratingImage) hideProgressToast();
      });
    } on AppException catch (e) {
      _stopImageCycle();
      hideProgressToast();
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      _stopImageCycle();
      hideProgressToast();
      if (_imageOp?.isCanceled ?? false) return;
      content.appendLogLine('⚠️ $e');
      showError('Image generation failed');
    } finally {
      _stopImageCycle();
      content.setGeneratingImage(false);
      _imageOp = null;
    }
  }

  Future<void> summarizeCurrentTranscript() async {
    final source = content.currentTranscriptValue.trim();
    if (source.isEmpty) return;
    if (!settings.provider.supportsSummary) {
      content.setOutputMode(OutputMode.transcription);
      showError('${settings.provider.brandName} does not support summaries.');
      return;
    }
    content.clearLog();
    content.setTranscribing(true);
    try {
      content.appendLogLine('📄 Summarizing current text...');
      final ai = aiFactory.create(settings.provider, settings: settings);
      final summary = await _summarize(ai, source);
      try {
        await content.addToClipboard(summary);
        showSuccess('Copied to clipboard');
      } catch (_) {}
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Summary failed');
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<bool> processSharedAudio({
    required String path,
    required String filename,
    required String mimeType,
    required String mode,
  }) async {
    if (!settings.provider.supportsBatchTranscription) {
      showError(
        '${settings.provider.brandName} supports live transcription only.',
      );
      return false;
    }

    if (!settings.hasActiveApiKey) {
      showError(settings.missingProviderConfigMessage);
      return false;
    }

    content.clearTranscription();
    content.setTranscribing(true);

    try {
      final sizeInBytes = File(path).lengthSync();
      final text = await _transcribeAudio(
        path,
        filename,
        mimeType,
        fileSizeBytes: sizeInBytes,
      );
      content.setCurrentTranscript(text, isSource: true);

      final ai = aiFactory.create(settings.provider, settings: settings);
      final translated = await _translateIfNeeded(
        ai,
        text,
        settings.targetLanguageCode,
      );
      if (settings.targetLanguageCode != 'auto') {
        content.setCurrentTranscript(translated);
      }

      await _saveToHistory(translated, settings.targetLanguageCode);

      if (mode == 'summary') {
        final summary = await _summarize(ai, translated);
        content.setOutputMode(OutputMode.summary);
        try {
          await content.addToClipboard(summary);
          showSuccess('Copied to clipboard');
        } catch (_) {}
      } else {
        content.setOutputMode(OutputMode.transcription);
        try {
          await content.addToClipboard(translated);
          showSuccess('Copied to clipboard');
        } catch (_) {}
      }

      _logFinalResponse(translated);
      return true;
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      if (e.internalMessage != null) {
        content.appendLogLine('   Details: ${e.internalMessage}');
      }
      showError(e.userMessage);
      return false;
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Processing failed');
      return false;
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<bool> processSharedText(String textContent) async {
    final text = textContent.trim();
    if (text.isEmpty) return false;

    if (!settings.hasActiveApiKey) {
      showError(settings.missingProviderConfigMessage);
      return false;
    }

    content.clearTranscription();
    content.setTranscribing(true);
    content.appendLogLine('📄 Processing shared text...');

    try {
      content.setCurrentTranscript(text, isSource: true);

      if (!settings.provider.supportsSummary) {
        content.setOutputMode(OutputMode.transcription);
        await _saveToHistory(text, 'auto');
        try {
          await content.addToClipboard(text);
          showSuccess('Copied to clipboard');
        } catch (_) {}
        content.appendLogLine('✅ Ready for text-to-speech');
        return true;
      }

      final ai = aiFactory.create(settings.provider, settings: settings);
      final translated = await _translateIfNeeded(
        ai,
        text,
        settings.targetLanguageCode,
      );
      if (settings.targetLanguageCode != 'auto') {
        content.setCurrentTranscript(translated);
      }

      await _saveToHistory(translated, settings.targetLanguageCode);

      final summary = await _summarize(ai, translated);
      content.setOutputMode(OutputMode.summary);
      try {
        await content.addToClipboard(summary);
        showSuccess('Copied to clipboard');
      } catch (_) {}
      content.appendLogLine('✅ Done');
      return true;
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
      return false;
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Failed to process text');
      return false;
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<void> _cleanupDetachedRecordingResources({
    StreamSubscription<double>? ampSub,
    StreamSubscription<List<int>>? audioStreamSub,
    RealtimeTranscriptionClient? realtimeClient,
  }) async {
    try {
      await ampSub?.cancel();
    } catch (_) {}
    try {
      await audioStreamSub?.cancel();
    } catch (_) {}
    try {
      await recorder.stopRecording();
    } catch (_) {}
    try {
      await realtimeClient?.close();
    } catch (_) {}
  }

  Future<void> _cleanupRealtime() async {
    final ampSub = _ampSub;
    _ampSub = null;
    final audioStreamSub = _audioStreamSub;
    _audioStreamSub = null;
    final realtimeClient = _realtimeClient;
    _realtimeClient = null;
    await _cleanupDetachedRecordingResources(
      ampSub: ampSub,
      audioStreamSub: audioStreamSub,
      realtimeClient: realtimeClient,
    );
    if (!_disposed) {
      levelNotifier.value = 0;
      smoothedLevelNotifier.value = 0;
    }
  }

  Future<void> _cleanupNonRealtimeRecording({
    required bool stopRecorder,
  }) async {
    final ampSub = _ampSub;
    _ampSub = null;
    try {
      await ampSub?.cancel();
    } catch (_) {}
    if (stopRecorder) {
      try {
        await recorder.stopRecording();
      } catch (_) {}
    }
    if (!_disposed) {
      levelNotifier.value = 0;
      smoothedLevelNotifier.value = 0;
    }
  }

  void _resetRecordingState({bool resetTranscribing = false}) {
    if (_disposed) return;
    try {
      content.setRecording(false);
    } catch (_) {}
    try {
      content.stopTimer();
    } catch (_) {}
    if (resetTranscribing) {
      try {
        content.setTranscribing(false);
      } catch (_) {}
    }
  }

  Future<void> _handleRealtimeFailure(
    Object error,
    ActiveRecordingSession session,
  ) async {
    if (!_isCurrentRecordingSession(session) || _realtimeFailureInProgress) {
      return;
    }
    _realtimeFailureInProgress = true;
    _activeRecordingSession = null;
    try {
      if (!_disposed) {
        content.appendLogLine('⚠️ Realtime Error: $error');
        showError('Realtime Error: $error');
      }
    } finally {
      try {
        await _cleanupRealtime();
      } finally {
        try {
          _resetRecordingState();
        } finally {
          _realtimeFailureInProgress = false;
        }
      }
    }
  }

  Future<void> startRecording() async {
    if (_disposed) return;
    if (_startInProgressSession != null ||
        _activeRecordingSession != null ||
        _finalizingRecordingSession != null ||
        _realtimeFailureInProgress) {
      showError('Recording is already starting or active.');
      return;
    }
    final initialProvider = settings.provider;
    if (!initialProvider.supportsAudio) {
      showError('${initialProvider.brandName} does not support audio files.');
      return;
    }

    final isElevenLabsRealtime = initialProvider == AiProviderType.elevenLabs &&
        settings.elevenLabsRealtime;
    final isOpenAiRealtime =
        initialProvider == AiProviderType.openai && settings.openAiRealtime;
    final isRealtime = isOpenAiRealtime || isElevenLabsRealtime;
    final targetLanguageCode = settings.targetLanguageCode;
    final transcriptionModel = isOpenAiRealtime
        ? targetLanguageCode == 'auto'
            ? AiModelConfig.openAiRealtimeTranscription
            : AiModelConfig.openAiRealtimeTranslation
        : settings.transcriptionModel;
    final session = ActiveRecordingSession(
      RecordingSessionMetadata(
        provider: initialProvider,
        isRealtime: isRealtime,
        targetLanguageCode: targetLanguageCode,
        apiKey: settings.activeApiKey,
        transcriptionModel: transcriptionModel,
        translationModel: settings.translationModel,
        summaryModel: settings.summaryModel,
        reasoningEffort: settings.reasoningEffort,
        summaryPrompt: settings.summaryPrompt,
        localAiLlmUrl: settings.localAiLlmUrl,
        localAiWhisperUrl: settings.localAiWhisperUrl,
      ),
    );
    _startInProgressSession = session;
    _activeRecordingSession = session;
    var nonRealtimeRecorderAcquired = false;

    try {
      if (playback.isPlaying) {
        await playback.stopAudio();
        _requireCurrentRecordingSession(session);
      }
      final hasPermission = await recorder.hasPermission();
      _requireCurrentRecordingSession(session);
      if (!hasPermission) {
        throw const AppException('Microphone permission is required.');
      }
      content.clearTranscription();

      if (isRealtime) {
        final realtimeBrand = isElevenLabsRealtime ? 'ElevenLabs' : 'OpenAI';
        if (session.metadata.apiKey.trim().isEmpty) {
          throw AppException('Please add your $realtimeBrand API key first.');
        }
        if (isElevenLabsRealtime && targetLanguageCode != 'auto') {
          throw const AppException(
            'ElevenLabs Realtime transcribes speech but does not translate it. Choose Auto Detect as target language.',
          );
        }

        final modelName = session.metadata.transcriptionModel;
        final StringBuffer logsBuffer = StringBuffer();

        void updateDisplayWithLogs(String transcriptText) {
          if (!_isCurrentRecordingSession(session)) return;
          final String logsStr = logsBuffer.toString();
          final String fullText = logsStr.isNotEmpty
              ? '```\n$logsStr────────────────────────────────────────\n```\n$transcriptText'
              : transcriptText;
          content.setCurrentTranscript(
            fullText,
            isSource: targetLanguageCode == 'auto',
          );
        }

        content.appendLogLine(
          '🔌 Connecting to $realtimeBrand Realtime WebSocket...',
        );
        logsBuffer.writeln(
          '🔌 Connecting to $realtimeBrand Realtime WebSocket...',
        );
        updateDisplayWithLogs("");

        final realtimeClient = _realtimeClientFactory(isElevenLabsRealtime);
        _realtimeClient = realtimeClient;
        String finalizedTextAccumulated = "";
        final StringBuffer currentWordBuffer = StringBuffer();

        await realtimeClient.connect(
          apiKey: session.metadata.apiKey,
          model: modelName,
          targetLanguageCode: targetLanguageCode,
          onTranscriptDelta: (delta) {
            if (!_isCurrentRecordingSession(session)) return;
            currentWordBuffer.write(delta);
            final transcriptText = (finalizedTextAccumulated.isNotEmpty)
                ? '$finalizedTextAccumulated${currentWordBuffer.toString()}'
                : currentWordBuffer.toString();
            updateDisplayWithLogs(transcriptText);
          },
          onTranscriptCompleted: (finalizedText) {
            if (!_isCurrentRecordingSession(session)) return;
            finalizedTextAccumulated = finalizedText;
            currentWordBuffer.clear();
            updateDisplayWithLogs(finalizedText);
          },
          onError: (err) {
            if (identical(_activeRecordingSession, session) &&
                session.markRealtimeDisconnected()) {
              unawaited(_handleRealtimeFailure(err, session));
            }
          },
          onConnected: () {
            if (!_isCurrentRecordingSession(session)) return;
            session.markRealtimeConnected();
            content.appendLogLine('⚡ Realtime connected!');
            logsBuffer.writeln('⚡ Realtime connected! (Model: $modelName)');
            updateDisplayWithLogs("");
          },
          onDisconnected: () {
            if (!_isCurrentRecordingSession(session)) return;
            content.appendLogLine('🔌 Realtime disconnected.');
            logsBuffer.writeln('🔌 Realtime disconnected.');
            final latestText = finalizedTextAccumulated.isNotEmpty
                ? finalizedTextAccumulated
                : currentWordBuffer.toString();
            if (latestText.isNotEmpty) {
              updateDisplayWithLogs(latestText);
            }
            if (identical(_activeRecordingSession, session) &&
                session.markRealtimeDisconnected()) {
              unawaited(
                _handleRealtimeFailure(
                  'The realtime connection was closed.',
                  session,
                ),
              );
            }
          },
        );
        _requireCurrentRecordingSession(session);
        if (!session.canStreamMicrophone) {
          throw const AppException(
            'The realtime connection closed before microphone startup.',
          );
        }

        final stream = await recorder.startAudioStream(
          sampleRate: isElevenLabsRealtime ? 16000 : 24000,
        );
        _requireCurrentRecordingSession(session);
        if (stream == null) {
          throw const AppException(
            'Recording could not be started (no permission or audio stream).',
          );
        }
        if (!session.canStreamMicrophone) {
          throw const AppException(
            'The realtime connection closed during microphone startup.',
          );
        }

        content.setRecording(true);
        content.startTimer();

        _ampSub?.cancel();
        _ampSub = recorder
            .levelStream(interval: const Duration(milliseconds: 60))
            .listen((lv) {
          if (!_isCurrentRecordingSession(session)) return;
          levelNotifier.value = lv;
          smoothedLevelNotifier.value =
              (smoothedLevelNotifier.value * 0.70) + (lv * 0.30);
        });

        _audioStreamSub = stream.listen((chunk) {
          if (identical(_activeRecordingSession, session) &&
              session.canStreamMicrophone) {
            realtimeClient.sendAudioChunk(chunk);
          }
        });

        content.appendLogLine('🎙️ Realtime recording & streaming started...');
        logsBuffer.writeln('🎙️ Realtime recording & streaming started...');
        updateDisplayWithLogs("");
      } else {
        await _preflightLocalAiForRecording(session);
        _requireCurrentRecordingSession(session);
        content.setTranscribing(false);
        nonRealtimeRecorderAcquired = true;
        await recorder.startRecording();
        _requireCurrentRecordingSession(session);
        final didStart = await recorder.isRecording();
        _requireCurrentRecordingSession(session);
        if (!didStart) {
          throw const AppException(
            'Recording could not be started on this device.',
          );
        }

        content.setRecording(true);
        content.startTimer();

        _ampSub?.cancel();
        _ampSub = recorder
            .levelStream(interval: const Duration(milliseconds: 60))
            .listen((lv) {
          if (!_isCurrentRecordingSession(session)) return;
          levelNotifier.value = lv;
          smoothedLevelNotifier.value =
              (smoothedLevelNotifier.value * 0.70) + (lv * 0.30);
        });
        content.appendLogLine('🎙️ Recording started...');
      }
    } on _RecordingStartCancelled {
      if (isRealtime) {
        await _cleanupRealtime();
      } else if (nonRealtimeRecorderAcquired) {
        await _cleanupNonRealtimeRecording(stopRecorder: true);
      }
    } on AppException catch (e) {
      if (isRealtime) {
        await _cleanupRealtime();
      } else if (nonRealtimeRecorderAcquired) {
        await _cleanupNonRealtimeRecording(stopRecorder: true);
      }
      if (identical(_activeRecordingSession, session)) {
        _activeRecordingSession = null;
      }
      if (!_disposed) {
        content.setRecording(false);
        content.setTranscribing(false);
        content.stopTimer();
        content.appendLogLine('⚠️ ${e.userMessage}');
        showError(e.userMessage);
      }
    } catch (e) {
      if (isRealtime) {
        await _cleanupRealtime();
      } else if (nonRealtimeRecorderAcquired) {
        await _cleanupNonRealtimeRecording(stopRecorder: true);
      }
      if (identical(_activeRecordingSession, session)) {
        _activeRecordingSession = null;
      }
      if (!_disposed) {
        content.setRecording(false);
        content.setTranscribing(false);
        content.stopTimer();
        content.appendLogLine('⚠️ Recording not started: $e');
        showError('Microphone permission required or connection failed');
      }
    } finally {
      if (identical(_startInProgressSession, session)) {
        _startInProgressSession = null;
      }
    }
  }

  Future<bool> _preflightLocalAiForRecording(
    ActiveRecordingSession session,
  ) async {
    final metadata = session.metadata;
    if (metadata.provider != AiProviderType.localAi) return false;

    content.setTranscribing(true);
    content.appendLogLine('🔌 Checking Local AI before recording...');
    content.appendLogLine('• Whisper reachability...');
    final whisper = await _localAiWhisperCheck(
      endpoint: metadata.localAiWhisperUrl ?? '',
      model: metadata.transcriptionModel,
    );
    _requireCurrentRecordingSession(session);
    content.appendLogLine('✅ ${whisper.message}');

    content.appendLogLine('• LLM reachability...');
    final llm = await _localAiLlmCheck(
      endpoint: metadata.localAiLlmUrl ?? '',
      model: metadata.summaryModel,
    );
    _requireCurrentRecordingSession(session);
    content.appendLogLine('✅ ${llm.message}');
    return true;
  }

  static String cleanTranscriptText(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.startsWith('```')) {
      final endIndex = trimmed.indexOf('```', 3);
      if (endIndex != -1) {
        final contentIndex = endIndex + 3;
        if (contentIndex < trimmed.length) {
          return trimmed.substring(contentIndex).trim();
        }
        return '';
      }
    }
    return trimmed;
  }

  Future<void> stopAndTranscribe() {
    final session = _activeRecordingSession;
    if (session == null) {
      return _stopRecordingWithoutSession();
    }

    final currentFinalization = _recordingFinalization;
    if (identical(_finalizingRecordingSession, session) &&
        currentFinalization != null) {
      return currentFinalization;
    }

    final completion = Completer<void>();
    _finalizingRecordingSession = session;
    _recordingFinalization = completion.future;
    unawaited(_finalizeRecordingSession(session, completion));
    return completion.future;
  }

  Future<void> _stopRecordingWithoutSession() async {
    if (content.isRecording) {
      await recorder.stopRecording();
      content.setRecording(false);
      content.stopTimer();
    }
  }

  Future<void> _finalizeRecordingSession(
    ActiveRecordingSession session,
    Completer<void> completion,
  ) async {
    Object? failure;
    StackTrace? failureStackTrace;
    try {
      await _stopAndTranscribeSession(session);
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    } finally {
      if (identical(_activeRecordingSession, session)) {
        _activeRecordingSession = null;
      }
      if (identical(_finalizingRecordingSession, session)) {
        _finalizingRecordingSession = null;
        _recordingFinalization = null;
      }
    }

    if (failure == null) {
      completion.complete();
    } else {
      completion.completeError(failure, failureStackTrace);
    }
  }

  Future<void> _stopAndTranscribeSession(
    ActiveRecordingSession session,
  ) async {
    final metadata = session.metadata;
    session.markStopping();

    try {
      if (metadata.isRealtime) {
        String? text;
        try {
          // Stop the microphone stream immediately to stop sending chunks.
          final audioStreamSub = _audioStreamSub;
          await audioStreamSub?.cancel();
          if (identical(_audioStreamSub, audioStreamSub)) {
            _audioStreamSub = null;
          }

          await recorder.stopRecording();
          await _realtimeClient?.finishAudio();

          // Wait briefly for final transcription or translation chunks.
          await _waitForRealtimeFinalization(
            const Duration(milliseconds: 2500),
          );
          text = content.currentTranscriptValue;
        } finally {
          try {
            await _cleanupRealtime();
          } finally {
            if (!_disposed) {
              content.setRecording(false);
              content.stopTimer();
            }
          }
        }

        final finalizedText = text;
        if (finalizedText.trim().isEmpty) {
          content.appendLogLine('⚠️ Realtime transcript is empty.');
          return;
        }

        content.setTranscribing(true);

        final cleanedText = cleanTranscriptText(finalizedText);
        content.setCurrentTranscript(
          cleanedText,
          isSource: metadata.targetLanguageCode == 'auto',
        );

        await _saveToHistory(cleanedText, metadata.targetLanguageCode);

        final ai = aiFactory.create(
          metadata.provider,
          settings: settings,
          localAiLlmUrl: metadata.localAiLlmUrl,
          localAiWhisperUrl: metadata.localAiWhisperUrl,
        );
        if (content.isSummaryMode && metadata.provider.supportsSummary) {
          final summary = await _summarize(
            ai,
            cleanedText,
            provider: metadata.provider,
            apiKey: metadata.apiKey,
            summaryModel: metadata.summaryModel,
            reasoningEffort: metadata.reasoningEffort,
            targetLanguageCode: metadata.targetLanguageCode,
            summaryPrompt: metadata.summaryPrompt,
            localAiLlmUrl: metadata.localAiLlmUrl,
          );
          try {
            await content.addToClipboard(summary);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        } else {
          content.setOutputMode(OutputMode.transcription);
          try {
            await content.addToClipboard(cleanedText);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        }

        _logFinalResponse(cleanedText);
      } else {
        String? path;
        try {
          path = await recorder.stopRecording();
        } finally {
          await _cleanupNonRealtimeRecording(stopRecorder: false);
          _resetRecordingState();
        }
        if (path == null) {
          content.appendLogLine('⚠️ Recording path is null.');
          return;
        }

        content.setTranscribing(true);

        final text = await _transcribeAudio(
          path,
          'audio.m4a',
          'audio/m4a',
          localAiPreflightDone: metadata.provider == AiProviderType.localAi,
          provider: metadata.provider,
          apiKey: metadata.apiKey,
          transcriptionModel: metadata.transcriptionModel,
          localAiLlmUrl: metadata.localAiLlmUrl,
          localAiWhisperUrl: metadata.localAiWhisperUrl,
        );
        content.setCurrentTranscript(text, isSource: true);

        final ai = aiFactory.create(
          metadata.provider,
          settings: settings,
          localAiLlmUrl: metadata.localAiLlmUrl,
          localAiWhisperUrl: metadata.localAiWhisperUrl,
        );
        final translated = await _translateIfNeeded(
          ai,
          text,
          metadata.targetLanguageCode,
          provider: metadata.provider,
          apiKey: metadata.apiKey,
          translationModel: metadata.translationModel,
          reasoningEffort: metadata.reasoningEffort,
          localAiLlmUrl: metadata.localAiLlmUrl,
        );
        if (metadata.targetLanguageCode != 'auto') {
          content.setCurrentTranscript(translated);
        }

        await _saveToHistory(translated, metadata.targetLanguageCode);

        if (content.isSummaryMode) {
          final summary = await _summarize(
            ai,
            translated,
            provider: metadata.provider,
            apiKey: metadata.apiKey,
            summaryModel: metadata.summaryModel,
            reasoningEffort: metadata.reasoningEffort,
            targetLanguageCode: metadata.targetLanguageCode,
            summaryPrompt: metadata.summaryPrompt,
            localAiLlmUrl: metadata.localAiLlmUrl,
          );
          try {
            await content.addToClipboard(summary);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        } else {
          try {
            await content.addToClipboard(translated);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        }

        _logFinalResponse(translated);
      }
    } on AppException catch (e) {
      if (!_disposed) {
        content.appendLogLine('⚠️ ${e.userMessage}');
        showError(e.userMessage);
      }
    } catch (e) {
      if (!_disposed) {
        content.appendLogLine('⚠️ $e');
        showError('Transcription failed');
      }
    } finally {
      _resetRecordingState(resetTranscribing: true);
    }
  }

  Future<void> reprocessOriginalTranscript() async {
    final src = content.sourceTranscriptValue.trim();
    if (src.isEmpty) return;
    if (!settings.provider.supportsTranslation) {
      showError('${settings.provider.brandName} does not support translation.');
      return;
    }

    if (!settings.hasActiveApiKey) {
      showError(settings.missingProviderConfigMessage);
      return;
    }

    content.clearLog();
    content.setTranscribing(true);

    final StringBuffer logsBuffer = StringBuffer();

    void updateDisplayWithLogs(String textVal) {
      final String logsStr = logsBuffer.toString();
      final String fullText = logsStr.isNotEmpty
          ? '```\n$logsStr────────────────────────────────────────\n```\n$textVal'
          : textVal;
      content.setCurrentTranscript(fullText, isSource: false);
    }

    try {
      final String providerName = settings.provider.brandName;
      final String targetLanguage = settings.targetLanguageCode;

      logsBuffer.writeln('🔌 Connecting to AI translation service...');
      updateDisplayWithLogs(src);
      final reprocessModel = settings.translationModel;
      logsBuffer.writeln('🤖 Model: $reprocessModel ($providerName)');
      updateDisplayWithLogs(src);
      logsBuffer.writeln('🔄 Re-processing original text...');
      updateDisplayWithLogs(src);
      logsBuffer.writeln('🌍 Translating to language: $targetLanguage...');
      updateDisplayWithLogs(src);

      final ai = aiFactory.create(settings.provider, settings: settings);
      final translated = await _translateIfNeeded(
        ai,
        src,
        settings.targetLanguageCode,
      );

      logsBuffer.writeln('✅ Translation completed successfully!');
      updateDisplayWithLogs(translated);

      // Briefly keep the completed log visible before clearing it.
      await Future.delayed(const Duration(milliseconds: 800));

      content.setCurrentTranscript(translated, isSource: false);
      await content.updateActiveHistoryAndPersist(
        transcript: translated,
        text: translated,
        language: settings.targetLanguageCode,
      );

      if (content.isSummaryMode && content.currentSummaryValue.isNotEmpty) {
        final summary = await _summarize(ai, translated);
        try {
          await content.addToClipboard(summary);
          showSuccess('Copied to clipboard');
        } catch (_) {}
      } else {
        try {
          await content.addToClipboard(translated);
          showSuccess('Copied to clipboard');
        } catch (_) {}
      }

      _logFinalResponse(translated);
    } on AppException catch (e) {
      logsBuffer.writeln('⚠️ Error: ${e.userMessage}');
      updateDisplayWithLogs(src);
      showError(e.userMessage);
    } catch (e) {
      logsBuffer.writeln('⚠️ Error: $e');
      updateDisplayWithLogs(src);
      showError('Re-processing failed');
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<void> togglePlayback({
    required TtsService tts,
    required void Function(String) showProgressToast,
    required void Function() hideProgressToast,
    required void Function(String) replaceProgressToast,
    required void Function(String) showSuccess,
  }) async {
    final playbackText = content.isSummaryMode
        ? content.currentSummaryValue
        : content.currentTranscriptValue;
    if (playbackText.trim().isEmpty) return;

    if (playback.isPlaying) {
      await playback.pauseAudio();
      showSuccess("Paused");
      return;
    }

    if (playback.canResumeCurrentAudio(
      playbackText,
      settings.provider,
      openAiVoice: "alloy",
      geminiVoice: "Zephyr",
      xaiVoice: "eve",
      elevenLabsVoice: AiModelConfig.elevenLabsTtsVoice,
    )) {
      await playback.resumeAudio();
    } else {
      final cached = playback.hasCachedSummaryAudio(
        playbackText,
        settings.provider,
        voice: settings.ttsVoice,
      );
      if (cached) {
        hideProgressToast();
      } else {
        showProgressToast(
          "Sending via API to ${settings.provider.brandName} TTS Service",
        );
        Future.delayed(const Duration(milliseconds: 700)).then((_) {
          if (playback.isAudioLoading) {
            replaceProgressToast("Waiting for Response");
          }
        });
      }
      final lang = settings.targetLanguageCode == 'auto'
          ? 'en'
          : settings.targetLanguageCode;
      await playback.playSummary(
        tts: tts,
        text: playbackText,
        provider: settings.provider,
        activeApiKey: settings.activeApiKey,
        openAiVoice: "alloy",
        geminiVoice: "Zephyr",
        xaiVoice: "eve",
        elevenLabsVoice: AiModelConfig.elevenLabsTtsVoice,
        languageCode: lang,
      );
      hideProgressToast();
    }
    final size = playback.cachedSummaryAudioSize(
      playbackText,
      settings.provider,
      openAiVoice: "alloy",
      geminiVoice: "Zephyr",
      xaiVoice: "eve",
      elevenLabsVoice: AiModelConfig.elevenLabsTtsVoice,
    );
    if (size != null && size > 0) {
      final mb = size / (1024 * 1024);
      showSuccess("Playing ${mb.toStringAsFixed(2)} MB Audio ...");
    } else {
      showSuccess("Playing");
    }
  }
}

class _RecordingStartCancelled implements Exception {
  const _RecordingStartCancelled();
}
