import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter/foundation.dart";
import "package:share_plus/share_plus.dart";
import "package:share_handler/share_handler.dart";

import "package:echoscribe/services/service_locator.dart";
import "package:echoscribe/services/debug_console.dart";
import "package:echoscribe/services/url_handler.dart";

import "package:echoscribe/state/settings_state.dart";
import "package:echoscribe/state/content_state.dart";
import "package:echoscribe/state/playback_state.dart";
import "package:echoscribe/models/transcription_item.dart";

import "package:echoscribe/pages/history_page.dart";
import "package:echoscribe/pages/settings_page.dart";

import "package:echoscribe/controllers/home_controller.dart";
import "package:echoscribe/controllers/share_intent_controller.dart";

import "package:echoscribe/widgets/home/recording_controls.dart";
import "package:echoscribe/widgets/home/transcription_panel.dart";
import "package:echoscribe/models/enums.dart";


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sl = ServiceLocator();

  final SettingsState _settings = SettingsState();
  final ContentState _content = ContentState()
    ..addHistory(TranscriptionItem.sample(1))
    ..addHistory(TranscriptionItem.sample(2));
  final PlaybackState _playback = PlaybackState();

  bool _isLoading = true;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _progressSnack;
  final ValueNotifier<String> _progressText = ValueNotifier('');

  final ShareHandlerPlatform _shareHandler = ShareHandlerPlatform.instance;

  late final HomeController _controller;
  late final ShareIntentController _shareIntentController;

  @override
  void initState() {
    super.initState();

    _controller = HomeController(
      settings: _settings,
      content: _content,
      playback: _playback,
      recorder: _sl.recorder,
      aiFactory: _sl.aiProviderFactory,
      showError: _showError,
      showSuccess: _showSuccess,
    );

    DebugConsole.configure(
      isEnabled: () => _settings.debugMode,
      println: (line) => _content.appendLogLine(line),
    );

    _bootstrap();
  }

  @override
  void dispose() {
    _progressText.dispose();
    _controller.dispose();
    _sl.recorder.dispose();
    _settings.dispose();
    _content.dispose();
    _playback.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _initializeFromStorage();
    await _initShareHandling();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeFromStorage() async {
    try {
      final secure = _sl.secureStorage;
      final provider = await secure.readProvider();
      final open = await secure.readOpenAiKey();
      final gem = await secure.readGeminiKey();
      final ant = await secure.readAnthropicKey();
      final prompt = await secure.readSummaryPrompt();
      final urlPrompt = await secure.readUrlSummaryPrompt();
      final dbg = await secure.readDebugMode();
      final openAiPro = await secure.readOpenAiPro();
      final geminiPro = await secure.readGeminiPro();
      final anthropicPro = await secure.readAnthropicPro();
      final xai = await secure.readXaiKey();
      final xaiPro = await secure.readXaiPro();
      final appFetchUrl = await secure.readAppFetchUrl();

      _settings.setProvider(provider);
      if (open.isNotEmpty) _settings.setOpenAiKey(open);
      if (gem.isNotEmpty) _settings.setGeminiKey(gem);
      if (ant.isNotEmpty) _settings.setAnthropicKey(ant);
      if (xai.isNotEmpty) _settings.setXaiKey(xai);
      if (prompt.isNotEmpty) _settings.setSummaryPrompt(prompt);
      if (urlPrompt.isNotEmpty) _settings.setUrlSummaryPrompt(urlPrompt);
      _settings.setDebugMode(dbg);
      _settings.setOpenAiPro(openAiPro);
      _settings.setGeminiPro(geminiPro);
      _settings.setAnthropicPro(anthropicPro);
      _settings.setXaiPro(xaiPro);
      _settings.setAppFetchUrl(appFetchUrl);
    } catch (_) {}
  }

  Future<void> _initShareHandling() async {
    if (kIsWeb) return;
    _shareIntentController = ShareIntentController(
      settings: _settings,
      content: _content,
      aiFactory: _sl.aiProviderFactory,
      onAudioReceived: (path, name, mime) async {
        await _controller.processSharedAudio(path: path, filename: name, mimeType: mime, mode: "transcription");
      },
      onTextReceived: (content) => _controller.processSharedText(content),
      showError: _showError,
      showSuccess: _showSuccess,
    );
    try {
      final initialMedia = await _shareHandler.getInitialSharedMedia();
      if (initialMedia != null) {
        if (mounted) _shareIntentController.handleSharedMedia(initialMedia, context);
      }
      _shareHandler.sharedMediaStream.listen((m) {
        if (mounted) _shareIntentController.handleSharedMedia(m, context);
      });
    } catch (e) {
      debugPrint("Share handling init failed: $e");
    }
  }

  Future<void> _pasteFromClipboard() async {
    final handled = await UrlHandler.tryPasteAndProcessUrl(
      context: context,
      settings: _settings,
      content: _content,
      aiFactory: _sl.aiProviderFactory,
      showError: _showError,
      showSuccess: _showSuccess,
    );
    if (handled) return;

    if (await Clipboard.hasStrings()) {
      final text = await Clipboard.getData("text/plain");
      if (text != null && text.text != null && text.text!.isNotEmpty) {
        await _controller.processSharedText(text.text!);
      }
    }
  }

  void _clearTranscription() {
    _controller.cancelActiveOperations();
    _content.clearTranscription();
    _playback.stopAudio();
  }

  void _showLanguagePicker() {
    final List<Map<String, String>> langs = [
      {'code': 'auto', 'label': 'Auto (match spoken)'},
      {'code': 'en', 'label': 'English'},
      {'code': 'zh', 'label': 'Chinese (Simplified)'},
      {'code': 'hi', 'label': 'Hindi'},
      {'code': 'es', 'label': 'Spanish'},
      {'code': 'fr', 'label': 'French'},
      {'code': 'ar', 'label': 'Arabic'},
      {'code': 'bn', 'label': 'Bengali'},
      {'code': 'pt', 'label': 'Portuguese'},
      {'code': 'ru', 'label': 'Russian'},
      {'code': 'ur', 'label': 'Urdu'},
      {'code': 'id', 'label': 'Indonesian'},
      {'code': 'de', 'label': 'German'},
      {'code': 'ja', 'label': 'Japanese'},
      {'code': 'sw', 'label': 'Swahili'},
      {'code': 'mr', 'label': 'Marathi'},
      {'code': 'te', 'label': 'Telugu'},
      {'code': 'tr', 'label': 'Turkish'},
      {'code': 'ta', 'label': 'Tamil'},
      {'code': 'vi', 'label': 'Vietnamese'},
      {'code': 'ko', 'label': 'Korean'},
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return ListView.builder(
          itemCount: langs.length,
          itemBuilder: (context, index) {
            final lang = langs[index];
            return RadioListTile<String>(
              title: Text(lang['label']!),
              value: lang['code']!,
              groupValue: _settings.targetLanguageCode,
              onChanged: (value) async {
                if (value == null) return;
                final oldLang = _settings.targetLanguageCode;
                _settings.setTargetLanguageCode(value);
                Navigator.pop(context);
                if (oldLang != value && _content.sourceTranscriptValue.isNotEmpty) {
                  await _controller.reprocessOriginalTranscript();
                }
              },
            );
          },
        );
      }
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.green,
    ));
  }

  void _hideProgressToast() {
    _progressSnack?.close();
    _progressSnack = null;
  }

  void _showProgressToast(String msg) {
    if (!mounted) return;
    _progressText.value = msg;
    if (_progressSnack != null) return; // already showing, just update text
    _progressSnack = ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ValueListenableBuilder<String>(
        valueListenable: _progressText,
        builder: (_, text, __) => Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 16),
            Expanded(child: Text(text)),
          ],
        ),
      ),
      duration: const Duration(days: 1),
    ));
  }

  void _replaceProgressToast(String msg) {
    if (!mounted) return;
    _progressText.value = msg;
    if (_progressSnack == null) _showProgressToast(msg);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    final color = Theme.of(context).colorScheme;

    return ListenableBuilder(listenable: Listenable.merge([_settings, _content, _playback]), builder: (context, _) {
      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                "assets/images/logo.png",
                height: 24,
              ),
              const SizedBox(width: 8),
              const Text("Echo Scribe"),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: "History",
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HistoryPage(content: _content))),
            ),
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: "Target language",
              onPressed: _showLanguagePicker,
            ),
            IconButton(
              icon: const Icon(Icons.vpn_key),
              tooltip: "API Config",
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings))),
            ),
          ],
        ),
        body: SafeArea(
          child: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;

              final transcriptionPanel = TranscriptionPanel(
                title: _content.isSummaryMode ? "Summary" : "Transcription",
                transcriptNotifier: _content.currentTranscript,
                summaryNotifier: _content.currentSummary,
                logTextNotifier: _content.logText,
                imageBytesNotifier: _content.currentImageBytes,
                isGeneratingImage: _content.isGeneratingImage,
                supportsImage: _settings.provider.supportsImage,
                isLoading: _content.isTranscribing,
                isRecording: _content.isRecording,
                recordDurationNotifier: _content.recordDuration,
                maxRecordDuration: _settings.provider == AiProviderType.openai ? const Duration(minutes: 25) : (_settings.provider == AiProviderType.gemini ? const Duration(minutes: 10) : const Duration(minutes: 5)),  // N/A for no-audio providers
                isSummaryMode: _content.isSummaryMode,
                isDebugMode: _settings.debugMode,
                onCopy: () async {
                  final t = ((_settings.debugMode || _content.isTranscribing || _content.isRecording) && _content.logText.value.isNotEmpty ? _content.logText.value : (_content.isSummaryMode ? _content.currentSummaryValue : _content.currentTranscriptValue)).trim();
                  if (t.isEmpty) return;
                  await _content.addToClipboard(t);
                  _showSuccess("Copied");
                },
                onShare: () async {
                  final text = ((_settings.debugMode || _content.isTranscribing || _content.isRecording) && _content.logText.value.isNotEmpty ? _content.logText.value : (_content.isSummaryMode ? _content.currentSummaryValue : _content.currentTranscriptValue)).trim();
                  if (text.isEmpty) return;
                  await SharePlus.instance.share(ShareParams(text: text));
                },
                onPaste: _pasteFromClipboard,
                onClear: _clearTranscription,
                onGenerateImage: () => _controller.generateImageFromCurrentContent(
                  showProgressToast: _showProgressToast,
                  hideProgressToast: _hideProgressToast,
                  replaceProgressToast: _replaceProgressToast,
                ),
                onImageTap: null,
              );

              final controls = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final totalWidth = constraints.maxWidth;
                      final minWidth = (totalWidth - 8) / 2;
                      final isTranscription = _content.outputMode == OutputMode.transcription;
                      return ToggleButtons(
                        isSelected: [isTranscription, !isTranscription],
                        onPressed: (index) async {
                          if (index == 0) {
                            _content.setOutputMode(OutputMode.transcription);
                          } else {
                            if (_content.currentSummaryValue.isEmpty &&
                                _content.currentTranscriptValue.isNotEmpty &&
                                !_content.isTranscribing) {
                              await _controller.summarizeCurrentTranscript();
                            }
                            _content.setOutputMode(OutputMode.summary);
                          }
                        },
                        constraints: BoxConstraints(minHeight: 44, minWidth: minWidth),
                        borderRadius: BorderRadius.circular(12),
                        selectedColor: Colors.white,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fillColor: Theme.of(context).colorScheme.primary,
                        children: const [
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.short_text),
                                SizedBox(width: 8),
                                Text("Transcription", overflow: TextOverflow.ellipsis, softWrap: false),
                              ],
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.summarize),
                                SizedBox(width: 8),
                                Text("Summary", overflow: TextOverflow.ellipsis, softWrap: false),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.surfaceContainerHigh.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: color.outlineVariant.withValues(alpha: 0.3),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Left Slot (TTS) - Fixed width to keep Mic centered
                          SizedBox(
                            width: 100,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: (_content.isSummaryMode && _content.currentSummaryValue.trim().isNotEmpty)
                                    ? Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: color.secondaryContainer.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            StopButton(
                                              enabled: !_playback.isAudioLoading,
                                              isAnthropic: !_settings.provider.supportsTts,
                                              onPressed: () async {
                                                if (!_settings.provider.supportsTts) {
                                                  _showError("${_settings.provider.brandName} does not support audio playback");
                                                  return;
                                                }
                                                try {
                                                  _hideProgressToast();
                                                  await _playback.stopAudio();
                                                } catch (e) {
                                                  _showError("TTS error");
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                            PlayPauseButton(
                                              isLoading: _playback.isAudioLoading,
                                              isPlaying: _playback.isPlaying,
                                              isAnthropic: !_settings.provider.supportsTts,
                                              onPressed: () async {
                                                if (!_settings.provider.supportsTts) {
                                                  _showError("${_settings.provider.brandName} does not support audio playback");
                                                  return;
                                                }
                                                if (_playback.isAudioLoading) return;
                                                try {
                                                  await _controller.togglePlayback(
                                                    tts: _sl.tts,
                                                    showProgressToast: _showProgressToast,
                                                    hideProgressToast: _hideProgressToast,
                                                    replaceProgressToast: _replaceProgressToast,
                                                    showSuccess: _showSuccess
                                                  );
                                                } catch (e) {
                                                  _hideProgressToast();
                                                  _showError("TTS error");
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                          
                          // Center: Mic
                          AnimatedBuilder(
                            animation: Listenable.merge([_controller.levelNotifier, _controller.smoothedLevelNotifier]),
                            builder: (context, child) {
                              final pulse = _content.isRecording ? _controller.smoothedLevelNotifier.value.clamp(0.0, 1.0) : 0.0;
                              final flicker = _content.isRecording ? _controller.levelNotifier.value.clamp(0.0, 1.0) : 0.0;
                              final ringColors = _content.isRecording
                                  ? [
                                      color.error.withValues(alpha: 0.16 + 0.18 * pulse),
                                      color.error.withValues(alpha: 0.03 + 0.03 * pulse),
                                    ]
                                  : [
                                      color.secondary.withValues(alpha: 0.18),
                                      color.secondary.withValues(alpha: 0.04),
                                    ];
                              return AnimatedScale(
                                duration: const Duration(milliseconds: 160),
                                scale: _content.isRecording ? (1.0 + 0.06 * pulse) : 1.0,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      width: 90,
                                      height: 90,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(colors: ringColors),
                                        border: Border.all(color: color.primary.withValues(alpha: 0.12), width: 1),
                                      ),
                                    ),
                                    MicButton(
                                      recording: _content.isRecording,
                                      transcribing: _content.isTranscribing,
                                      enabled: _settings.hasActiveApiKey,
                                      isAnthropic: !_settings.provider.supportsAudio,
                                      level: pulse,
                                      instantLevel: flicker,
                                      onTap: () async {
                                        if (_content.isTranscribing) return;
                                        if (_content.isGeneratingImage) {
                                          _controller.cancelActiveOperations();
                                          _hideProgressToast();
                                        }
                                        if (!_settings.hasActiveApiKey) {
                                          _showError("Add your API key first");
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(builder: (_) => SettingsPage(settings: _settings)),
                                          );
                                          return;
                                        }
                                        if (!_settings.provider.supportsAudio) {
                                          _showError('${_settings.provider.brandName} does not support audio - Please select GPT or Gemini.');
                                          return;
                                        }
                                        if (!_content.isRecording) {
                                          await _controller.startRecording();
                                        } else {
                                          await _controller.stopAndTranscribe();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          // Right Slot (Image Gen) - Fixed width to keep Mic centered
                          SizedBox(
                            width: 100,
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: (_settings.provider.supportsImage && (_content.isSummaryMode ? _content.currentSummaryValue.trim().isNotEmpty : _content.currentTranscriptValue.trim().isNotEmpty))
                                    ? ImageGenButton(
                                        isLoading: _content.isGeneratingImage,
                                        enabled: _settings.hasActiveApiKey,
                                        supportsImage: _settings.provider.supportsImage,
                                        onPressed: () async {
                                          if (!_settings.provider.supportsImage) {
                                            _showError("${_settings.provider.brandName} does not support image generation");
                                            return;
                                          }
                                          await _controller.generateImageFromCurrentContent(
                                            showProgressToast: _showProgressToast,
                                            hideProgressToast: _hideProgressToast,
                                            replaceProgressToast: _replaceProgressToast,
                                          );
                                        },
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _content.isRecording
                          ? Text("Tap to stop",
                              key: const ValueKey("stop"),
                              style: Theme.of(context).textTheme.bodyMedium)
                          : !_settings.provider.supportsAudio
                              ? Text("${_settings.provider.brandName} has no audio support",
                                  key: const ValueKey("no_audio"),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red))
                              : Text("Tap to record",
                                  key: const ValueKey("record"),
                                  style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
                ],
              );

              if (isLandscape) {
                return Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: transcriptionPanel,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                          child: controls,
                        ),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: transcriptionPanel,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: controls,
                    ),
                  ],
                );
              }
            },
          ),
        ),
      );
    });
  }
}
