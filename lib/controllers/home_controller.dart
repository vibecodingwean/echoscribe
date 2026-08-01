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
  });

  @override
  void dispose() {
    _ampSub?.cancel();
    _audioStreamSub?.cancel();
    _realtimeClient?.close();
    _imageOp?.cancel();
    _imageCycleTimer?.cancel();
    levelNotifier.dispose();
    smoothedLevelNotifier.dispose();
    super.dispose();
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

  String _getModelForSummary() {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiSummary(pro: settings.geminiPro);
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiSummary(pro: settings.xaiPro);
      case AiProviderType.localAi:
        return settings.localAiLlmModel;
      case AiProviderType.openai:
        return AiModelConfig.openAiSummary(pro: settings.openAiPro);
    }
  }

  String _getModelForTranscription() {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiTranscription(pro: settings.geminiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiTranscription(pro: settings.xaiPro);
      case AiProviderType.localAi:
        return settings.localAiWhisperModel;
      case AiProviderType.openai:
      case AiProviderType.anthropic:
        return AiModelConfig.openAiTranscription(pro: settings.openAiPro);
    }
  }

  String _getModelForTranslation() {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiTranslation(pro: settings.geminiPro);
      case AiProviderType.anthropic:
        return AiModelConfig.anthropicTranslation(pro: settings.anthropicPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiTranslation(pro: settings.xaiPro);
      case AiProviderType.localAi:
        return settings.localAiLlmModel;
      case AiProviderType.openai:
        return AiModelConfig.openAiTranslation(pro: settings.openAiPro);
    }
  }

  String? _getReasoningEffort() {
    switch (settings.provider) {
      case AiProviderType.openai:
        return AiModelConfig.openAiReasoningEffort(pro: settings.openAiPro);
      case AiProviderType.xai:
        return AiModelConfig.xaiReasoningEffort(pro: settings.xaiPro);
      case AiProviderType.gemini:
      case AiProviderType.anthropic:
      case AiProviderType.localAi:
        return null;
    }
  }

  String _getModelForImage() {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return AiModelConfig.geminiImage(pro: true);
      case AiProviderType.xai:
        return AiModelConfig.xaiImage(pro: true);
      case AiProviderType.openai:
        return AiModelConfig.openAiImage(pro: true);
      case AiProviderType.localAi:
      case AiProviderType.anthropic:
        return ''; // Unsupported
    }
  }

  String get _ttsVoice {
    switch (settings.provider) {
      case AiProviderType.gemini:
        return "Zephyr";
      case AiProviderType.xai:
        return "eve";
      default:
        return "alloy";
    }
  }

  Future<String> _transcribeAudio(
    String path,
    String filename,
    String mimeType, {
    int? fileSizeBytes,
    bool localAiPreflightDone = false,
  }) async {
    final brand = settings.provider.brandName;
    final model = _getModelForTranscription();

    if (fileSizeBytes != null) {
      final sizeInMb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      content.appendLogLine('🎙️ Uploading $sizeInMb MB to $brand...');
    } else {
      content.appendLogLine('🎙️ Uploading audio to $brand...');
    }
    content.appendLogLine('🤖 Transcription Model: $model');

    if (settings.provider == AiProviderType.localAi && !localAiPreflightDone) {
      content.appendLogLine('🔌 Checking Local AI Whisper endpoint...');
      final check = await LocalAiHealthService.checkWhisper(
        endpoint: settings.localAiWhisperUrl,
        model: model,
      );
      content.appendLogLine('✅ ${check.message}');
    }

    final ai = aiFactory.create(settings.provider, settings: settings);
    final text = await ai.transcribe(
      apiKey: settings.activeApiKey,
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
    String targetLanguage,
  ) async {
    if (targetLanguage == 'auto') return text;

    final transModel = _getModelForTranslation();
    final reasoningEffort = _getReasoningEffort();
    final brand = settings.provider.brandName;
    content.appendLogLine('🌐 Translating via $brand...');
    content.appendLogLine('🤖 Translation Model: $transModel');
    if (reasoningEffort != null) {
      content.appendLogLine('🧠 Reasoning Effort: $reasoningEffort');
    }

    if (settings.provider == AiProviderType.localAi) {
      content.appendLogLine('🔌 Checking Local AI LLM endpoint...');
      final check = await LocalAiHealthService.checkLlm(
        endpoint: settings.localAiLlmUrl,
        model: transModel,
      );
      content.appendLogLine('✅ ${check.message}');
    }
    content.appendLogLine('🌍 Target: $targetLanguage');

    final translated = await ai.translate(
      apiKey: settings.activeApiKey,
      text: text,
      targetLanguageCode: targetLanguage,
      model: transModel,
      reasoningEffort: reasoningEffort,
    );
    content.appendLogLine('✅ Translation successful');
    return translated;
  }

  Future<String> _summarize(AiProvider ai, String text) async {
    final brand = settings.provider.brandName;
    final sumModel = _getModelForSummary();
    final reasoningEffort = _getReasoningEffort();
    content.appendLogLine('🤖 Summarizing with $brand...');
    content.appendLogLine('🤖 Summary Model: $sumModel');
    if (reasoningEffort != null) {
      content.appendLogLine('🧠 Reasoning Effort: $reasoningEffort');
    }

    if (settings.provider == AiProviderType.localAi) {
      content.appendLogLine('🔌 Checking Local AI LLM before summary...');
      final check = await LocalAiHealthService.checkLlm(
        endpoint: settings.localAiLlmUrl,
        model: sumModel,
      );
      content.appendLogLine('✅ ${check.message}');
    }

    final summary = await ai.summarize(
      apiKey: settings.activeApiKey,
      text: text.trim(),
      model: sumModel,
      targetLanguageCode: settings.targetLanguageCode,
      summaryPrompt: settings.summaryPrompt,
      reasoningEffort: reasoningEffort,
    );

    content.setCurrentSummary(summary);
    content.updateActiveHistory(summary: summary);
    content.appendLogLine('✨ Summary generated (${summary.length} chars)');
    return summary;
  }

  void _saveToHistory(String text, String language) {
    content.addHistory(
      TranscriptionItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        createdAt: DateTime.now(),
        transcript: text,
        summary: '',
        language: language,
        mode: OutputMode.transcription.name,
      ),
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
    final model = _getModelForImage();

    showProgressToast('Uploading prompt to $brand...');

    int remaining = switch (settings.provider) {
      AiProviderType.openai => 70,
      AiProviderType.gemini => 25,
      AiProviderType.xai => 15,
      AiProviderType.anthropic => 0,
      AiProviderType.localAi => 0,
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
    if (!settings.provider.supportsAudio) {
      showError('${settings.provider.brandName} does not support audio files.');
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

      _saveToHistory(translated, settings.targetLanguageCode);

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

      final ai = aiFactory.create(settings.provider, settings: settings);
      final translated = await _translateIfNeeded(
        ai,
        text,
        settings.targetLanguageCode,
      );
      if (settings.targetLanguageCode != 'auto') {
        content.setCurrentTranscript(translated);
      }

      _saveToHistory(translated, settings.targetLanguageCode);

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

  void _cleanupRealtime() {
    _ampSub?.cancel();
    _ampSub = null;
    _audioStreamSub?.cancel();
    _audioStreamSub = null;
    _realtimeClient?.close();
    _realtimeClient = null;
    levelNotifier.value = 0;
    smoothedLevelNotifier.value = 0;
  }

  Future<void> startRecording() async {
    if (!settings.provider.supportsAudio) {
      showError('${settings.provider.brandName} does not support audio files.');
      return;
    }

    final bool isElevenLabsRealtime = settings.elevenLabsRealtime;
    final bool isOpenAiRealtime =
        settings.provider == AiProviderType.openai && settings.openAiRealtime;
    final bool isRealtime = isOpenAiRealtime || isElevenLabsRealtime;

    try {
      if (playback.isPlaying) {
        await playback.stopAudio();
      }
      content.clearTranscription();

      if (isRealtime) {
        final realtimeApiKey =
            isElevenLabsRealtime ? settings.elevenLabsKey : settings.openAiKey;
        final realtimeBrand = isElevenLabsRealtime ? 'ElevenLabs' : 'OpenAI';
        if (realtimeApiKey.trim().isEmpty) {
          throw AppException('Please add your $realtimeBrand API key first.');
        }
        if (isElevenLabsRealtime && settings.targetLanguageCode != 'auto') {
          throw const AppException(
            'ElevenLabs Realtime transcribes speech but does not translate it. Choose Auto Detect as target language.',
          );
        }

        final String modelName = isElevenLabsRealtime
            ? AiModelConfig.elevenLabsRealtimeTranscription
            : settings.targetLanguageCode == 'auto'
                ? AiModelConfig.openAiRealtimeTranscription
                : AiModelConfig.openAiRealtimeTranslation;

        final StringBuffer logsBuffer = StringBuffer();

        void updateDisplayWithLogs(String transcriptText) {
          final String logsStr = logsBuffer.toString();
          final String fullText = logsStr.isNotEmpty
              ? '```\n$logsStr────────────────────────────────────────\n```\n$transcriptText'
              : transcriptText;
          content.setCurrentTranscript(
            fullText,
            isSource: settings.targetLanguageCode == 'auto',
          );
        }

        content.appendLogLine(
          '🔌 Connecting to $realtimeBrand Realtime WebSocket...',
        );
        logsBuffer.writeln(
          '🔌 Connecting to $realtimeBrand Realtime WebSocket...',
        );
        updateDisplayWithLogs("");

        _realtimeClient = isElevenLabsRealtime
            ? ElevenLabsRealtimeClient()
            : OpenAiRealtimeClient();
        String finalizedTextAccumulated = "";
        final StringBuffer currentWordBuffer = StringBuffer();

        await _realtimeClient!.connect(
          apiKey: realtimeApiKey,
          model: modelName,
          targetLanguageCode: settings.targetLanguageCode,
          onTranscriptDelta: (delta) {
            currentWordBuffer.write(delta);
            final transcriptText = (finalizedTextAccumulated.isNotEmpty)
                ? '$finalizedTextAccumulated${currentWordBuffer.toString()}'
                : currentWordBuffer.toString();
            updateDisplayWithLogs(transcriptText);
          },
          onTranscriptCompleted: (finalizedText) {
            finalizedTextAccumulated = finalizedText;
            currentWordBuffer.clear();
            updateDisplayWithLogs(finalizedText);
          },
          onError: (err) {
            content.appendLogLine('⚠️ Realtime Error: $err');
            showError('Realtime Error: $err');
            _cleanupRealtime();
            content.setRecording(false);
            content.stopTimer();
          },
          onConnected: () {
            content.appendLogLine('⚡ Realtime connected!');
            logsBuffer.writeln('⚡ Realtime connected! (Model: $modelName)');
            updateDisplayWithLogs("");
          },
          onDisconnected: () {
            content.appendLogLine('🔌 Realtime disconnected.');
            logsBuffer.writeln('🔌 Realtime disconnected.');
            final latestText = finalizedTextAccumulated.isNotEmpty
                ? finalizedTextAccumulated
                : currentWordBuffer.toString();
            if (latestText.isNotEmpty) {
              updateDisplayWithLogs(latestText);
            }
          },
        );

        final stream = await recorder.startAudioStream(
          sampleRate: isElevenLabsRealtime ? 16000 : 24000,
        );
        if (stream == null) {
          throw const AppException(
            'Recording could not be started (no permission or audio stream).',
          );
        }

        content.setRecording(true);
        content.startTimer();

        _ampSub?.cancel();
        _ampSub = recorder
            .levelStream(interval: const Duration(milliseconds: 60))
            .listen((lv) {
          levelNotifier.value = lv;
          smoothedLevelNotifier.value =
              (smoothedLevelNotifier.value * 0.70) + (lv * 0.30);
        });

        _audioStreamSub = stream.listen((chunk) {
          _realtimeClient?.sendAudioChunk(chunk);
        });

        content.appendLogLine('🎙️ Realtime recording & streaming started...');
        logsBuffer.writeln('🎙️ Realtime recording & streaming started...');
        updateDisplayWithLogs("");
      } else {
        await _preflightLocalAiForRecording();
        content.setTranscribing(false);
        await recorder.startRecording();
        final didStart = await recorder.isRecording();
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
          levelNotifier.value = lv;
          smoothedLevelNotifier.value =
              (smoothedLevelNotifier.value * 0.70) + (lv * 0.30);
        });
        content.appendLogLine('🎙️ Recording started...');
      }
    } on AppException catch (e) {
      if (isRealtime) _cleanupRealtime();
      content.setRecording(false);
      content.setTranscribing(false);
      content.stopTimer();
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      if (isRealtime) _cleanupRealtime();
      content.setRecording(false);
      content.setTranscribing(false);
      content.stopTimer();
      content.appendLogLine('⚠️ Recording not started: $e');
      showError('Microphone permission required or connection failed');
    }
  }

  Future<bool> _preflightLocalAiForRecording() async {
    if (settings.provider != AiProviderType.localAi) return false;

    content.setTranscribing(true);
    content.appendLogLine('🔌 Checking Local AI before recording...');
    content.appendLogLine('• Whisper reachability...');
    final whisper = await LocalAiHealthService.checkWhisper(
      endpoint: settings.localAiWhisperUrl,
      model: _getModelForTranscription(),
    );
    content.appendLogLine('✅ ${whisper.message}');

    content.appendLogLine('• LLM reachability...');
    final llm = await LocalAiHealthService.checkLlm(
      endpoint: settings.localAiLlmUrl,
      model: _getModelForSummary(),
    );
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

  Future<void> stopAndTranscribe() async {
    final bool isRealtime = (settings.provider == AiProviderType.openai &&
            settings.openAiRealtime) ||
        settings.elevenLabsRealtime;
    try {
      if (isRealtime) {
        // Stop the microphone stream immediately to stop sending audio chunks
        _audioStreamSub?.cancel();
        _audioStreamSub = null;

        await recorder.stopRecording();

        content.setRecording(false);
        content.stopTimer();

        await _realtimeClient?.finishAudio();

        // Wait briefly for final transcription or translation chunks to arrive.
        await Future.delayed(const Duration(milliseconds: 2500));

        final text = content.currentTranscriptValue;
        _cleanupRealtime();

        if (text.trim().isEmpty) {
          content.appendLogLine('⚠️ Realtime transcript is empty.');
          return;
        }

        content.setTranscribing(true);

        final cleanedText = cleanTranscriptText(text);
        content.setCurrentTranscript(
          cleanedText,
          isSource: settings.targetLanguageCode == 'auto',
        );

        _saveToHistory(cleanedText, settings.targetLanguageCode);

        final ai = aiFactory.create(settings.provider, settings: settings);
        if (content.isSummaryMode) {
          final summary = await _summarize(ai, cleanedText);
          try {
            await content.addToClipboard(summary);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        } else {
          try {
            await content.addToClipboard(cleanedText);
            showSuccess('Copied to clipboard');
          } catch (_) {}
        }

        _logFinalResponse(cleanedText);
      } else {
        final path = await recorder.stopRecording();
        _ampSub?.cancel();
        _ampSub = null;
        levelNotifier.value = 0;
        smoothedLevelNotifier.value = 0;

        content.setRecording(false);
        content.stopTimer();
        if (path == null) {
          content.appendLogLine('⚠️ Recording path is null.');
          return;
        }

        content.setTranscribing(true);

        final text = await _transcribeAudio(
          path,
          'audio.m4a',
          'audio/m4a',
          localAiPreflightDone: settings.provider == AiProviderType.localAi,
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

        _saveToHistory(translated, settings.targetLanguageCode);

        if (content.isSummaryMode) {
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
      }
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Transcription failed');
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<void> reprocessOriginalTranscript() async {
    final src = content.sourceTranscriptValue.trim();
    if (src.isEmpty) return;

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
      final reprocessModel = _getModelForTranslation();
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
      content.updateActiveHistory(
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
    if (playback.isPlaying) {
      await playback.pauseAudio();
      showSuccess("Paused");
      return;
    }

    if (playback.canResumeCurrentAudio(
      content.currentSummaryValue,
      settings.provider,
      openAiVoice: "alloy",
      geminiVoice: "Zephyr",
      xaiVoice: "eve",
    )) {
      await playback.resumeAudio();
    } else {
      final cached = playback.hasCachedSummaryAudio(
        content.currentSummaryValue,
        settings.provider,
        voice: _ttsVoice,
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
        text: content.currentSummaryValue,
        provider: settings.provider,
        activeApiKey: settings.activeApiKey,
        openAiVoice: "alloy",
        geminiVoice: "Zephyr",
        xaiVoice: "eve",
        languageCode: lang,
      );
      hideProgressToast();
    }
    final size = playback.cachedSummaryAudioSize(
      content.currentSummaryValue,
      settings.provider,
      openAiVoice: "alloy",
      geminiVoice: "Zephyr",
      xaiVoice: "eve",
    );
    if (size != null && size > 0) {
      final mb = size / (1024 * 1024);
      showSuccess("Playing ${mb.toStringAsFixed(2)} MB Audio ...");
    } else {
      showSuccess("Playing");
    }
  }
}
