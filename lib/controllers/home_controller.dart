import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
    levelNotifier.dispose();
    smoothedLevelNotifier.dispose();
    super.dispose();
  }

  String _getModelForSummary() {
    if (settings.provider == AiProviderType.gemini) return AiModelConfig.geminiSummary(pro: settings.geminiPro);
    if (settings.provider == AiProviderType.anthropic) return AiModelConfig.anthropicSummary(pro: settings.anthropicPro);
    return AiModelConfig.openAiSummary(pro: settings.openAiPro);
  }

  String _getModelForTranscription() {
    if (settings.provider == AiProviderType.gemini) return AiModelConfig.geminiTranscription(pro: settings.geminiPro);
    return AiModelConfig.openAiTranscription(pro: settings.openAiPro);
  }

  String _getModelForTranslation() {
    if (settings.provider == AiProviderType.gemini) return AiModelConfig.geminiTranslation(pro: settings.geminiPro);
    if (settings.provider == AiProviderType.anthropic) return AiModelConfig.anthropicTranslation(pro: settings.anthropicPro);
    return AiModelConfig.openAiTranslation(pro: settings.openAiPro);
  }

  String get _ttsVoice => settings.provider == AiProviderType.gemini ? "Zephyr" : "alloy";

  Future<String> _transcribeAudio(String path, String filename, String mimeType, {int? fileSizeBytes}) async {
    if (fileSizeBytes != null) {
      final sizeInMb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(1);
      content.appendLogLine('🎙️ Processing $sizeInMb MB audio file...');
    } else {
      content.appendLogLine('🎙️ Processing audio...');
    }

    final ai = aiFactory.create(settings.provider);
    final brand = settings.provider.brandName;
    final model = _getModelForTranscription();
    content.appendLogLine('📡 Uploading audio to $brand\n($model)...');
    
    final text = await ai.transcribe(
      apiKey: settings.activeApiKey,
      filePath: path,
      fileName: filename,
      mimeType: mimeType,
      model: model,
    );
    content.appendLogLine('✅ Received text');
    return text;
  }

  Future<String> _translateIfNeeded(AiProvider ai, String text, String targetLanguage) async {
    if (targetLanguage == 'auto') return text;
    
    final transModel = _getModelForTranslation();
    content.appendLogLine('🌐 Translating to $targetLanguage\n($transModel)...');
    final translated = await ai.translate(
      apiKey: settings.activeApiKey,
      text: text,
      targetLanguageCode: targetLanguage,
      model: transModel,
    );
    content.appendLogLine('✅ Translation received');
    return translated;
  }

  Future<String> _summarize(AiProvider ai, String text) async {
    final brand = settings.provider.brandName;
    final sumModel = _getModelForSummary();
    content.appendLogLine('🤖 $brand\n($sumModel) is analyzing...');
    
    final summary = await ai.summarize(
      apiKey: settings.activeApiKey,
      text: text,
      model: sumModel,
      targetLanguageCode: settings.targetLanguageCode,
      summaryPrompt: settings.summaryPrompt,
    );
    
    content.setCurrentSummary(summary);
    content.updateActiveHistory(summary: summary);
    content.appendLogLine('✨ Summary received successfully');
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

  Future<void> summarizeCurrentTranscript() async {
    final source = content.currentTranscriptValue.trim();
    if (source.isEmpty) return;
    content.clearLog();
    content.setTranscribing(true);
    try {
      content.appendLogLine('📄 Summarizing current text...');
      final ai = aiFactory.create(settings.provider);
      await _summarize(ai, source);
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
    if (settings.provider == AiProviderType.anthropic) {
      showError('Claude does not support audio files - Please select GPT or Gemini.');
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
        await _summarize(ai, translated);
        content.setOutputMode(OutputMode.summary);
      } else {
        content.setOutputMode(OutputMode.transcription);
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
      
      await _summarize(ai, translated);
      content.setOutputMode(OutputMode.summary);
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
    if (settings.provider == AiProviderType.anthropic) {
      showError('Claude does not support audio files - Please select GPT or Gemini.');
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
        await _summarize(ai, translated);
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
         await _summarize(ai, translated);
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
    
    if (playback.canResumeCurrentAudio(content.currentSummaryValue, settings.provider, openAiVoice: "alloy", geminiVoice: "Zephyr")) {
      await playback.resumeAudio();
    } else {
      final cached = playback.hasCachedSummaryAudio(content.currentSummaryValue, settings.provider, voice: _ttsVoice);
      if (cached) {
        hideProgressToast();
      } else {
        showProgressToast(
          settings.provider == AiProviderType.gemini
              ? "Sending via API to Gemini TTS Service"
              : "Sending via API to GPT TTS Service",
        );
        Future.delayed(const Duration(milliseconds: 700)).then((_) {
          if (playback.isAudioLoading) {
            replaceProgressToast("Waiting for Response");
          }
        });
      }
      await playback.playSummary(
        tts: tts,
        text: content.currentSummaryValue,
        provider: settings.provider,
        activeApiKey: settings.activeApiKey,
        openAiVoice: "alloy",
        geminiVoice: "Zephyr",
      );
      hideProgressToast();
    }
    final size = playback.cachedSummaryAudioSize(content.currentSummaryValue, settings.provider, openAiVoice: "alloy", geminiVoice: "Zephyr");
    if (size != null && size > 0) {
      final mb = size / (1024 * 1024);
      showSuccess("Playing ${mb.toStringAsFixed(2)} MB Audio ...");
    } else {
      showSuccess("Playing");
    }
  }
}
