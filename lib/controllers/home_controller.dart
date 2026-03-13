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

class HomeController extends ChangeNotifier {
  final SettingsState settings;
  final ContentState content;
  final PlaybackState playback;
  final RecorderService recorder;
  final AiProviderFactory aiFactory;
  
  final void Function(String) showError;
  final void Function(String) showSuccess;
  
  CancelableOperation? _imageOp;

  // Expose these for the UI to use
  final ValueNotifier<double> levelNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> smoothedLevelNotifier = ValueNotifier<double>(0.0);
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
    _imageOp?.cancel();
    levelNotifier.dispose();
    smoothedLevelNotifier.dispose();
    super.dispose();
  }

  void cancelActiveOperations() {
    if (_imageOp != null) {
      _imageOp?.cancel();
      _imageOp = null;
      content.setGeneratingImage(false);
      content.appendLogLine('🛑 Image generation cancelled');
    }
    // Note: Add transcription/summary cancel here if needed later
  }

  String _getModelForSummary() {
    switch (settings.provider) {
      case AiProviderType.gemini: return AiModelConfig.geminiSummary(pro: settings.geminiPro);
      case AiProviderType.anthropic: return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
      case AiProviderType.xai: return AiModelConfig.xaiSummary(pro: settings.xaiPro);
      case AiProviderType.openai: return AiModelConfig.openAiSummary(pro: settings.openAiPro);
    }
  }

  String _getModelForTranscription() {
    if (settings.provider == AiProviderType.gemini) return AiModelConfig.geminiTranscription(pro: settings.geminiPro);
    return AiModelConfig.openAiTranscription(pro: settings.openAiPro);
  }

  String _getModelForTranslation() {
    switch (settings.provider) {
      case AiProviderType.gemini: return AiModelConfig.geminiTranslation(pro: settings.geminiPro);
      case AiProviderType.anthropic: return AiModelConfig.anthropicTranslation(pro: settings.anthropicPro);
      case AiProviderType.xai: return AiModelConfig.xaiTranslation(pro: settings.xaiPro);
      case AiProviderType.openai: return AiModelConfig.openAiTranslation(pro: settings.openAiPro);
    }
  }

  String _getModelForImage() {
    switch (settings.provider) {
      case AiProviderType.gemini: return AiModelConfig.geminiImage(pro: true);
      case AiProviderType.xai: return AiModelConfig.xaiImage(pro: true);
      case AiProviderType.openai: return AiModelConfig.openAiImage(pro: true);
      case AiProviderType.anthropic: return ''; // Unsupported
    }
  }

  String get _ttsVoice {
    switch (settings.provider) {
      case AiProviderType.gemini: return "Zephyr";
      case AiProviderType.xai: return "Eve";
      default: return "alloy";
    }
  }

  Future<String> _transcribeAudio(String path, String filename, String mimeType, {int? fileSizeBytes}) async {
    final brand = settings.provider.brandName;
    final model = _getModelForTranscription();
    
    if (fileSizeBytes != null) {
      final sizeInMb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      content.appendLogLine('🎙️ Uploading $sizeInMb MB to $brand...');
    } else {
      content.appendLogLine('🎙️ Uploading audio to $brand...');
    }
    content.appendLogLine('🤖 Transcription Model: $model');

    final ai = aiFactory.create(settings.provider);
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

  Future<String> _translateIfNeeded(AiProvider ai, String text, String targetLanguage) async {
    if (targetLanguage == 'auto') return text;
    
    final transModel = _getModelForTranslation();
    final brand = settings.provider.brandName;
    content.appendLogLine('🌐 Translating via $brand...');
    content.appendLogLine('🤖 Translation Model: $transModel');
    content.appendLogLine('🌍 Target: $targetLanguage');
    
    final translated = await ai.translate(
      apiKey: settings.activeApiKey,
      text: text,
      targetLanguageCode: targetLanguage,
      model: transModel,
    );
    content.appendLogLine('✅ Translation successful');
    return translated;
  }

  Future<String> _summarize(AiProvider ai, String text) async {
    final brand = settings.provider.brandName;
    final sumModel = _getModelForSummary();
    content.appendLogLine('🤖 Summarizing with $brand...');
    content.appendLogLine('🤖 Summary Model: $sumModel');
    
    final summary = await ai.summarize(
      apiKey: settings.activeApiKey,
      text: text,
      model: sumModel,
      targetLanguageCode: settings.targetLanguageCode,
      summaryPrompt: settings.summaryPrompt,
    );
    
    content.setCurrentSummary(summary);
    content.updateActiveHistory(summary: summary);
    content.appendLogLine('✨ Summary generated (${summary.length} chars)');
    return summary;
  }

  void _saveToHistory(String text, String language) {
    content.addHistory(TranscriptionItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(), 
      text: text, 
      createdAt: DateTime.now(), 
      transcript: text, 
      summary: '', 
      language: language, 
      mode: OutputMode.transcription.name
    ));
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
      showError('${settings.provider.brandName} does not support image generation.');
      return;
    }
    if (!settings.hasActiveApiKey) {
      showError('Add your API key first');
      return;
    }

    final source = content.isSummaryMode ? content.currentSummaryValue.trim() : content.currentTranscriptValue.trim();
    if (source.isEmpty) return;

    var prompt = "Generate an image that represents the following text. Be creative, visual, and accurate to the core theme. Text:\n\n$source";
    if (settings.provider == AiProviderType.openai) {
      prompt = "Generate a realistic image that represents the following text. Focus on high quality, lifelike details. Text:\n\n$source";
    }

    content.setGeneratingImage(true);
    content.setCurrentImageBytes(null);
    
    final brand = settings.provider.brandName;
    final model = _getModelForImage();
    
    showProgressToast('Uploading prompt to $brand...');

    // Estimated generation time per provider
    final int estimateSec = switch (settings.provider) {
      AiProviderType.openai => 70,
      AiProviderType.gemini => 25,
      AiProviderType.xai => 15,
      AiProviderType.anthropic => 0,
    };

    Timer? countdownTimer;
    int remaining = estimateSec;
    bool done = false;

    void stopCountdown() {
      done = true;
      countdownTimer?.cancel();
      countdownTimer = null;
    }

    void startCountdown() {
      // Show first message after 2s delay
      countdownTimer = Timer(const Duration(seconds: 2), () {
        if (done) return;
        // Start 1-second ticks
        countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (done) { timer.cancel(); return; }
          remaining--;
          if (remaining <= 0) {
            // Estimate expired — just cycle model/waiting
            if (timer.tick % 4 < 2) {
              replaceProgressToast('Model: $model');
            } else {
              replaceProgressToast('Waiting for reply...');
            }
          } else if (remaining % 4 < 2) {
            replaceProgressToast('Estimate: ~$remaining seconds...');
          } else {
            replaceProgressToast('Model: $model');
          }
        });
      });
    }

    try {
      content.appendLogLine('🎨 Generating image with $brand...');
      content.appendLogLine('🤖 Model: $model');

      final ai = aiFactory.create(settings.provider);

      _imageOp = CancelableOperation.fromFuture(
        ai.generateImage(
          apiKey: settings.activeApiKey,
          prompt: prompt,
          model: model,
        ),
      );

      startCountdown();

      final bytes = await _imageOp!.value;
      stopCountdown();
      _imageOp = null;

      final sizeKb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
      content.appendLogLine('✅ Image received ($sizeKb KB)');
      content.setCurrentImageBytes(bytes);
      replaceProgressToast('Image received ($sizeKb KB)');
      Future.delayed(const Duration(seconds: 2), () {
        if (!content.isGeneratingImage) hideProgressToast();
      });
    } on AppException catch (e) {
      stopCountdown();
      hideProgressToast();
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      stopCountdown();
      hideProgressToast();
      if (_imageOp?.isCanceled ?? false) return;
      content.appendLogLine('⚠️ $e');
      showError('Image generation failed');
    } finally {
      stopCountdown();
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
      final ai = aiFactory.create(settings.provider);
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

  Future<void> processSharedAudio({
    required String path,
    required String filename,
    required String mimeType,
    required String mode,
  }) async {
    if (!settings.provider.supportsAudio) {
      showError('${settings.provider.brandName} does not support audio files - Please select GPT or Gemini.');
      return;
    }

    if (!settings.hasActiveApiKey) {
      showError('Add your API key first');
      return;
    }

    content.clearTranscription();
    content.setTranscribing(true);

    try {
      final sizeInBytes = File(path).lengthSync();
      final text = await _transcribeAudio(path, filename, mimeType, fileSizeBytes: sizeInBytes);
      content.setCurrentTranscript(text, isSource: true);

      final ai = aiFactory.create(settings.provider);
      final translated = await _translateIfNeeded(ai, text, settings.targetLanguageCode);
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
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Processing failed');
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<void> processSharedText(String textContent) async {
    final text = textContent.trim();
    if (text.isEmpty) return;
    
    if (!settings.hasActiveApiKey) {
      showError('Add your API key first');
      return;
    }

    content.clearTranscription();
    content.setTranscribing(true);
    content.appendLogLine('📄 Processing shared text...');

    try {
      content.setCurrentTranscript(text, isSource: true);
      
      final ai = aiFactory.create(settings.provider);
      final translated = await _translateIfNeeded(ai, text, settings.targetLanguageCode);
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
    } on AppException catch (e) {
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
      showError('Failed to process text');
    } finally {
      content.setTranscribing(false);
    }
  }

  Future<void> startRecording() async {
    if (!settings.provider.supportsAudio) {
      showError('${settings.provider.brandName} does not support audio files - Please select GPT or Gemini.');
      return;
    }
    try {
      if (playback.isPlaying) {
        await playback.stopAudio();
      }
      content.clearTranscription();
      content.setRecording(true);
      content.startTimer();

      await recorder.startRecording();

      _ampSub?.cancel();
      _ampSub = recorder.levelStream(interval: const Duration(milliseconds: 60)).listen((lv) {
        levelNotifier.value = lv;
        smoothedLevelNotifier.value = (smoothedLevelNotifier.value * 0.70) + (lv * 0.30);
      });
      content.appendLogLine('🎙️ Recording started...');
    } on AppException catch (e) {
      content.setRecording(false);
      content.stopTimer();
      showError(e.userMessage);
    } catch (e) {
      content.setRecording(false);
      content.stopTimer();
      showError('Microphone permission required');
    }
  }

  Future<void> stopAndTranscribe() async {
    try {
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

      final text = await _transcribeAudio(path, 'audio.m4a', 'audio/m4a');
      content.setCurrentTranscript(text, isSource: true);

      final ai = aiFactory.create(settings.provider);
      final translated = await _translateIfNeeded(ai, text, settings.targetLanguageCode);
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
      showError('Add your API key first');
      return;
    }

    content.clearLog();
    content.setTranscribing(true);
    
    try {
      content.appendLogLine('🔄 Re-processing original text...');
      final ai = aiFactory.create(settings.provider);
      final translated = await _translateIfNeeded(ai, src, settings.targetLanguageCode);
      
      content.setCurrentTranscript(translated);
      content.updateActiveHistory(transcript: translated, text: translated, language: settings.targetLanguageCode);
      
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
      content.appendLogLine('⚠️ ${e.userMessage}');
      showError(e.userMessage);
    } catch (e) {
      content.appendLogLine('⚠️ $e');
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
    
    if (playback.canResumeCurrentAudio(content.currentSummaryValue, settings.provider, openAiVoice: "alloy", geminiVoice: "Zephyr", xaiVoice: "Eve")) {
      await playback.resumeAudio();
    } else {
      final cached = playback.hasCachedSummaryAudio(content.currentSummaryValue, settings.provider, voice: _ttsVoice);
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
      final lang = settings.targetLanguageCode == 'auto' ? 'en' : settings.targetLanguageCode;
      await playback.playSummary(
        tts: tts,
        text: content.currentSummaryValue,
        provider: settings.provider,
        activeApiKey: settings.activeApiKey,
        openAiVoice: "alloy",
        geminiVoice: "Zephyr",
        xaiVoice: "Eve",
        languageCode: lang,
      );
      hideProgressToast();
    }
    final size = playback.cachedSummaryAudioSize(content.currentSummaryValue, settings.provider, openAiVoice: "alloy", geminiVoice: "Zephyr", xaiVoice: "Eve");
    if (size != null && size > 0) {
      final mb = size / (1024 * 1024);
      showSuccess("Playing ${mb.toStringAsFixed(2)} MB Audio ...");
    } else {
      showSuccess("Playing");
    }
  }
}
