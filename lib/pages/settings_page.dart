import 'package:echoscribe/services/secure_storage_service.dart';
import 'package:echoscribe/services/floating_dictation_service.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/local_ai_health_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class SettingsPage extends StatefulWidget {
  final SettingsState settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  final _openAiFormKey = GlobalKey<FormState>();
  final _geminiFormKey = GlobalKey<FormState>();
  final _anthropicFormKey = GlobalKey<FormState>();
  final _elevenLabsFormKey = GlobalKey<FormState>();
  final _localAiFormKey = GlobalKey<FormState>();
  late final TextEditingController _openAiCtrl;
  late final TextEditingController _geminiCtrl;
  late final TextEditingController _anthropicCtrl;
  late final TextEditingController _xaiCtrl;
  late final TextEditingController _elevenLabsCtrl;
  late final TextEditingController _localAiLlmUrlCtrl;
  late final TextEditingController _localAiLlmModelCtrl;
  late final TextEditingController _localAiWhisperUrlCtrl;
  late final TextEditingController _localAiWhisperModelCtrl;
  final ScrollController _scrollController = ScrollController();
  final _xaiFormKey = GlobalKey<FormState>();
  final _storage = SecureStorageService();
  bool _obscureOpenAi = true;
  bool _obscureGemini = true;
  bool _obscureAnthropic = true;
  bool _obscureXai = true;
  bool _obscureElevenLabs = true;
  bool _testingLocalAiLlm = false;
  bool _testingLocalAiWhisper = false;
  late bool _debugMode;
  late bool _openAiPro;
  late bool _openAiRealtime;
  late bool _geminiPro;
  late bool _anthropicPro;
  late bool _xaiPro;
  FloatingDictationStatus _floatingStatus =
      FloatingDictationStatus.unavailable();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openAiCtrl = TextEditingController(text: widget.settings.openAiKey);
    _geminiCtrl = TextEditingController(text: widget.settings.geminiKey);
    _anthropicCtrl = TextEditingController(text: widget.settings.anthropicKey);
    _xaiCtrl = TextEditingController(text: widget.settings.xaiKey);
    _elevenLabsCtrl = TextEditingController(
      text: widget.settings.elevenLabsKey,
    );
    _localAiLlmUrlCtrl = TextEditingController(
      text: widget.settings.localAiLlmUrl,
    );
    _localAiLlmModelCtrl = TextEditingController(
      text: widget.settings.localAiLlmModel,
    );
    _localAiWhisperUrlCtrl = TextEditingController(
      text: widget.settings.localAiWhisperUrl,
    );
    _localAiWhisperModelCtrl = TextEditingController(
      text: widget.settings.localAiWhisperModel,
    );
    _debugMode = widget.settings.debugMode;
    _openAiPro = widget.settings.openAiPro;
    _openAiRealtime = widget.settings.openAiRealtime;
    _geminiPro = widget.settings.geminiPro;
    _anthropicPro = widget.settings.anthropicPro;
    _xaiPro = widget.settings.xaiPro;
    _syncAndRefreshFloatingStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _openAiCtrl.dispose();
    _geminiCtrl.dispose();
    _anthropicCtrl.dispose();
    _xaiCtrl.dispose();
    _elevenLabsCtrl.dispose();
    _localAiLlmUrlCtrl.dispose();
    _localAiLlmModelCtrl.dispose();
    _localAiWhisperUrlCtrl.dispose();
    _localAiWhisperModelCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAndRefreshFloatingStatus();
    }
  }

  void _resetAudioPromptToDefault() {
    final defaultPrompt = SettingsState().summaryPrompt;
    widget.settings.setSummaryPrompt(defaultPrompt);
  }

  void _resetUrlPromptToDefault() {
    final defaultPrompt = SettingsState().urlSummaryPrompt;
    widget.settings.setUrlSummaryPrompt(defaultPrompt);
  }

  void _resetDictationPromptToDefault() {
    final defaultPrompt = SettingsState().dictationPrompt;
    widget.settings.setDictationPrompt(defaultPrompt);
  }

  Future<void> _syncAndRefreshFloatingStatus() async {
    await FloatingDictationService.syncSettings(widget.settings);
    final status = await FloatingDictationService.getStatus();
    if (mounted) {
      setState(() => _floatingStatus = status);
    }
  }

  Future<void> _openAccessibilitySettingsWithDisclosure(
    FloatingDictationStatus status,
  ) async {
    if (!FloatingDictationService.isAndroid) return;

    if (!status.accessibilityEnabled) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Accessibility for Floating Dictation'),
          content: const SingleChildScrollView(
            child: Text(
              'EchoScribe uses the Android Accessibility Service only to detect editable text fields, show the floating microphone button, and insert dictated text after you approve the preview.\n\n'
              'The service does not collect, store, or send the contents of other apps to EchoScribe. It also avoids password, PIN, payment, banking, credit-card, and phone fields.\n\n'
              'Audio is recorded only after you tap the floating button. Dictation requests go directly from your device to the AI provider you selected, using your own API key.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Agree & open settings'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (accepted != true) {
        await _syncAndRefreshFloatingStatus();
        return;
      }
    }

    await FloatingDictationService.openAccessibilitySettings();
    await _syncAndRefreshFloatingStatus();
  }

  Future<void> _openPromptDialog({
    required String labelText,
    required String initialText,
    required Future<void> Function(String value) onSave,
    required Future<void> Function() onReset,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (builderContext) {
        return _EditPromptDialog(
          labelText: labelText,
          initialText: initialText,
        );
      },
    );

    if (result == null) return;

    final action = result['action'];

    if (action == 'reset') {
      await onReset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prompt reset to default'),
            duration: Duration(milliseconds: 1000),
          ),
        );
        setState(() {});
      }
    } else if (action == 'save') {
      final newPrompt = result['text'] as String;
      await onSave(newPrompt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prompt saved'),
            duration: Duration(milliseconds: 1000),
          ),
        );
        setState(() {});
      }
    }
  }

  Future<void> _autoSaveKeysIfValid() async {
    final validOpen = _openAiFormKey.currentState?.validate() ?? true;
    final validGem = _geminiFormKey.currentState?.validate() ?? true;
    final validAnt = _anthropicFormKey.currentState?.validate() ?? true;
    final validXai = _xaiFormKey.currentState?.validate() ?? true;
    final validElevenLabs = _elevenLabsFormKey.currentState?.validate() ?? true;
    final validLocal = _localAiFormKey.currentState?.validate() ?? true;
    if (!validOpen ||
        !validGem ||
        !validAnt ||
        !validXai ||
        !validElevenLabs ||
        !validLocal) {
      return;
    }
    final openKey = _openAiCtrl.text.trim();
    final gemKey = _geminiCtrl.text.trim();
    final antKey = _anthropicCtrl.text.trim();
    final xaiKey = _xaiCtrl.text.trim();
    final elevenLabsKey = _elevenLabsCtrl.text.trim();
    final localLlmUrl = _localAiLlmUrlCtrl.text.trim();
    final localLlmModel = _localAiLlmModelCtrl.text.trim();
    final localWhisperUrl = _localAiWhisperUrlCtrl.text.trim();
    final localWhisperModel = _localAiWhisperModelCtrl.text.trim();
    widget.settings.setOpenAiKey(openKey);
    widget.settings.setGeminiKey(gemKey);
    widget.settings.setAnthropicKey(antKey);
    widget.settings.setXaiKey(xaiKey);
    widget.settings.setElevenLabsKey(elevenLabsKey);
    widget.settings.setLocalAiLlmUrl(localLlmUrl);
    widget.settings.setLocalAiLlmModel(localLlmModel);
    widget.settings.setLocalAiWhisperUrl(localWhisperUrl);
    widget.settings.setLocalAiWhisperModel(localWhisperModel);
    await _storage.saveOpenAiKey(openKey);
    await _storage.saveGeminiKey(gemKey);
    await _storage.saveAnthropicKey(antKey);
    await _storage.saveXaiKey(xaiKey);
    await _storage.saveElevenLabsKey(elevenLabsKey);
    await _storage.saveLocalAiLlmUrl(localLlmUrl);
    await _storage.saveLocalAiLlmModel(localLlmModel);
    await _storage.saveLocalAiWhisperUrl(localWhisperUrl);
    await _storage.saveLocalAiWhisperModel(localWhisperModel);
    await _syncAndRefreshFloatingStatus();
  }

  Future<void> _testLocalAiLlm() async {
    await _autoSaveKeysIfValid();
    if (!mounted) return;
    setState(() => _testingLocalAiLlm = true);
    try {
      final result = await LocalAiHealthService.checkLlm(
        endpoint: _localAiLlmUrlCtrl.text,
        model: _localAiLlmModelCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${result.message}.')));
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingLocalAiLlm = false);
    }
  }

  Future<void> _testLocalAiWhisper() async {
    await _autoSaveKeysIfValid();
    if (!mounted) return;
    setState(() => _testingLocalAiWhisper = true);
    try {
      final result = await LocalAiHealthService.checkWhisper(
        endpoint: _localAiWhisperUrlCtrl.text,
        model: _localAiWhisperModelCtrl.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${result.message}.')));
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.userMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingLocalAiWhisper = false);
    }
  }

  void _scheduleAutoSaveImmediate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final openKey = _openAiCtrl.text.trim();
      final gemKey = _geminiCtrl.text.trim();
      final antKey = _anthropicCtrl.text.trim();
      final xaiKey = _xaiCtrl.text.trim();
      final elevenLabsKey = _elevenLabsCtrl.text.trim();
      final localLlmUrl = _localAiLlmUrlCtrl.text.trim();
      final localLlmModel = _localAiLlmModelCtrl.text.trim();
      final localWhisperUrl = _localAiWhisperUrlCtrl.text.trim();
      final localWhisperModel = _localAiWhisperModelCtrl.text.trim();
      widget.settings.setOpenAiKey(openKey);
      widget.settings.setGeminiKey(gemKey);
      widget.settings.setAnthropicKey(antKey);
      widget.settings.setXaiKey(xaiKey);
      widget.settings.setElevenLabsKey(elevenLabsKey);
      widget.settings.setLocalAiLlmUrl(localLlmUrl);
      widget.settings.setLocalAiLlmModel(localLlmModel);
      widget.settings.setLocalAiWhisperUrl(localWhisperUrl);
      widget.settings.setLocalAiWhisperModel(localWhisperModel);
      await _storage.saveOpenAiKey(openKey);
      await _storage.saveGeminiKey(gemKey);
      await _storage.saveAnthropicKey(antKey);
      await _storage.saveXaiKey(xaiKey);
      await _storage.saveElevenLabsKey(elevenLabsKey);
      await _storage.saveLocalAiLlmUrl(localLlmUrl);
      await _storage.saveLocalAiLlmModel(localLlmModel);
      await _storage.saveLocalAiWhisperUrl(localWhisperUrl);
      await _storage.saveLocalAiWhisperModel(localWhisperModel);
      await _syncAndRefreshFloatingStatus();
    });
  }

  bool _snackShownOnExit = false;

  Widget _buildFloatingDictationCard(BuildContext context) {
    final status = _floatingStatus;
    final color = Theme.of(context).colorScheme;
    final enabled = widget.settings.floatingDictationEnabled;
    final providerLabel = !enabled
        ? 'Disabled'
        : !widget.settings.provider.supportsFloatingDictation
            ? '${widget.settings.provider.brandName}: floating dictation unsupported'
            : '${widget.settings.provider.brandName}: ready after permissions';

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              secondary: Icon(Icons.keyboard_voice, color: color.primary),
              title: Text(
                'Floating Dictation',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              subtitle: Text(
                FloatingDictationService.isAndroid
                    ? providerLabel
                    : 'Available on Android.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: enabled,
              onChanged: FloatingDictationService.isAndroid &&
                      widget.settings.provider.supportsFloatingDictation
                  ? (val) async {
                      widget.settings.setFloatingDictationEnabled(val);
                      await _storage.saveFloatingDictationEnabled(val);
                      await _syncAndRefreshFloatingStatus();
                    }
                  : null,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FloatingStatusPill(
                  label: 'Microphone',
                  ok: status.microphoneGranted,
                  onPressed: FloatingDictationService.isAndroid
                      ? () async {
                          await Permission.microphone.request();
                          await _syncAndRefreshFloatingStatus();
                        }
                      : null,
                ),
                _FloatingStatusPill(
                  label: 'Overlay',
                  ok: status.overlayGranted,
                  onPressed: FloatingDictationService.isAndroid
                      ? () async {
                          await FloatingDictationService.openOverlaySettings();
                          await _syncAndRefreshFloatingStatus();
                        }
                      : null,
                ),
                _FloatingStatusPill(
                  label: 'Accessibility',
                  ok: status.accessibilityEnabled,
                  onPressed: FloatingDictationService.isAndroid
                      ? () async {
                          await _openAccessibilitySettingsWithDisclosure(
                            status,
                          );
                        }
                      : null,
                ),
                _FloatingStatusPill(
                  label: widget.settings.provider.brandName,
                  ok: status.configReady,
                  onPressed: FloatingDictationService.isAndroid
                      ? () async {
                          await _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _floatingDictationStatusMessage(status),
                              ),
                              duration: const Duration(milliseconds: 1400),
                            ),
                          );
                        }
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        await _autoSaveKeysIfValid();
        if (!mounted) return;
        if (didPop && !_snackShownOnExit) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Settings saved'),
              duration: Duration(milliseconds: 1000),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('API Config'),
          leading: BackButton(
            onPressed: () async {
              await _autoSaveKeysIfValid();
              if (!mounted) return;
              _snackShownOnExit = true;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Settings saved'),
                  duration: Duration(milliseconds: 1000),
                ),
              );
              navigator.pop();
            },
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Provider',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                ProviderSelectorCard(
                  selectedProvider: widget.settings.provider,
                  onProviderSelected: (provider) async {
                    widget.settings.setProvider(provider);
                    await _storage.saveProvider(provider);
                    if (!provider.supportsTranslation) {
                      widget.settings.setTargetLanguageCode('auto');
                      await _storage.saveTargetLanguageCode('auto');
                    }
                    if (provider.mustExtractUrl) {
                      widget.settings.setAppFetchUrl(true);
                      await _storage.saveAppFetchUrl(true);
                    }
                    await _syncAndRefreshFloatingStatus();
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
                if (widget.settings.provider == AiProviderType.openai)
                  _ApiKeyCard(
                    labelText: 'OpenAI API Key',
                    hintText: 'sk-...',
                    controller: _openAiCtrl,
                    obscure: _obscureOpenAi,
                    proValue: _openAiPro,
                    realtimeValue: _openAiRealtime,
                    onObscureToggle: () =>
                        setState(() => _obscureOpenAi = !_obscureOpenAi),
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onProChanged: (val) async {
                      setState(() => _openAiPro = val);
                      widget.settings.setOpenAiPro(val);
                      await _storage.saveOpenAiPro(val);
                      await _syncAndRefreshFloatingStatus();
                    },
                    onRealtimeChanged: (val) async {
                      setState(() => _openAiRealtime = val);
                      widget.settings.setOpenAiRealtime(val);
                      await _storage.saveOpenAiRealtime(val);
                    },
                    onDelete: () async {
                      await _storage.deleteOpenAiKey();
                      widget.settings.setOpenAiKey('');
                      _openAiCtrl.clear();
                      await _syncAndRefreshFloatingStatus();
                    },
                    formKey: _openAiFormKey,
                  ),
                if (widget.settings.provider == AiProviderType.elevenLabs)
                  _ApiKeyCard(
                    labelText: 'ElevenLabs API Key (Live STT + TTS)',
                    hintText: 'xi-...',
                    controller: _elevenLabsCtrl,
                    obscure: _obscureElevenLabs,
                    onObscureToggle: () => setState(
                      () => _obscureElevenLabs = !_obscureElevenLabs,
                    ),
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onDelete: () async {
                      await _storage.deleteElevenLabsKey();
                      widget.settings.setElevenLabsKey('');
                      _elevenLabsCtrl.clear();
                    },
                    formKey: _elevenLabsFormKey,
                  ),
                if (widget.settings.provider == AiProviderType.elevenLabs)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      'Live transcription and text-to-speech only. Summary, image generation, translation, shared audio, and Floating Dictation are unavailable.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                if (widget.settings.provider == AiProviderType.gemini)
                  _ApiKeyCard(
                    labelText: 'Gemini API Key',
                    hintText: 'AIza...',
                    controller: _geminiCtrl,
                    obscure: _obscureGemini,
                    proValue: _geminiPro,
                    onObscureToggle: () =>
                        setState(() => _obscureGemini = !_obscureGemini),
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onProChanged: (val) async {
                      setState(() => _geminiPro = val);
                      widget.settings.setGeminiPro(val);
                      await _storage.saveGeminiPro(val);
                      await _syncAndRefreshFloatingStatus();
                    },
                    onDelete: () async {
                      await _storage.deleteGeminiKey();
                      widget.settings.setGeminiKey('');
                      _geminiCtrl.clear();
                      await _syncAndRefreshFloatingStatus();
                    },
                    formKey: _geminiFormKey,
                  ),
                if (widget.settings.provider == AiProviderType.anthropic)
                  _ApiKeyCard(
                    labelText: 'Anthropic API Key',
                    hintText: 'sk-ant-...',
                    controller: _anthropicCtrl,
                    obscure: _obscureAnthropic,
                    proValue: _anthropicPro,
                    onObscureToggle: () =>
                        setState(() => _obscureAnthropic = !_obscureAnthropic),
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onProChanged: (val) async {
                      setState(() => _anthropicPro = val);
                      widget.settings.setAnthropicPro(val);
                      await _storage.saveAnthropicPro(val);
                      await _syncAndRefreshFloatingStatus();
                    },
                    onDelete: () async {
                      await _storage.deleteAnthropicKey();
                      widget.settings.setAnthropicKey('');
                      _anthropicCtrl.clear();
                      await _syncAndRefreshFloatingStatus();
                    },
                    formKey: _anthropicFormKey,
                  ),
                if (widget.settings.provider == AiProviderType.xai)
                  _ApiKeyCard(
                    labelText: 'xAI API Key',
                    hintText: 'xai-...',
                    controller: _xaiCtrl,
                    obscure: _obscureXai,
                    proValue: _xaiPro,
                    onObscureToggle: () =>
                        setState(() => _obscureXai = !_obscureXai),
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onProChanged: (val) async {
                      setState(() => _xaiPro = val);
                      widget.settings.setXaiPro(val);
                      await _storage.saveXaiPro(val);
                      await _syncAndRefreshFloatingStatus();
                    },
                    onDelete: () async {
                      await _storage.deleteXaiKey();
                      widget.settings.setXaiKey('');
                      _xaiCtrl.clear();
                      await _syncAndRefreshFloatingStatus();
                    },
                    formKey: _xaiFormKey,
                  ),
                if (widget.settings.provider == AiProviderType.localAi)
                  _LocalAiConfigCard(
                    formKey: _localAiFormKey,
                    llmUrlController: _localAiLlmUrlCtrl,
                    llmModelController: _localAiLlmModelCtrl,
                    whisperUrlController: _localAiWhisperUrlCtrl,
                    whisperModelController: _localAiWhisperModelCtrl,
                    testingLlm: _testingLocalAiLlm,
                    testingWhisper: _testingLocalAiWhisper,
                    onChanged: (_) => _scheduleAutoSaveImmediate(),
                    onTestLlm: _testingLocalAiLlm ? null : _testLocalAiLlm,
                    onTestWhisper:
                        _testingLocalAiWhisper ? null : _testLocalAiWhisper,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: (MediaQuery.sizeOf(context).width - 48) / 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _openPromptDialog(
                          labelText: 'Audio Prompt',
                          initialText: widget.settings.summaryPrompt,
                          onSave: (val) async {
                            widget.settings.setSummaryPrompt(val);
                            await _storage.saveSummaryPrompt(val);
                          },
                          onReset: () async {
                            await _storage.deleteSummaryPrompt();
                            _resetAudioPromptToDefault();
                          },
                        ),
                        icon: const Icon(Icons.graphic_eq, size: 18),
                        label: const Text(
                          'Audio Prompt',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: (MediaQuery.sizeOf(context).width - 48) / 2,
                      child: OutlinedButton.icon(
                        onPressed: () => _openPromptDialog(
                          labelText: 'URL Prompt',
                          initialText: widget.settings.urlSummaryPrompt,
                          onSave: (val) async {
                            widget.settings.setUrlSummaryPrompt(val);
                            await _storage.saveUrlSummaryPrompt(val);
                          },
                          onReset: () async {
                            await _storage.deleteUrlSummaryPrompt();
                            _resetUrlPromptToDefault();
                          },
                        ),
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text(
                          'URL Prompt',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width - 32,
                      child: OutlinedButton.icon(
                        onPressed: () => _openPromptDialog(
                          labelText: 'Floating Dictation Prompt',
                          initialText: widget.settings.dictationPrompt,
                          onSave: (val) async {
                            widget.settings.setDictationPrompt(val);
                            await _storage.saveDictationPrompt(val);
                            await _syncAndRefreshFloatingStatus();
                          },
                          onReset: () async {
                            await _storage.deleteDictationPrompt();
                            _resetDictationPromptToDefault();
                            await _syncAndRefreshFloatingStatus();
                          },
                        ),
                        icon: const Icon(Icons.keyboard_voice, size: 18),
                        label: const Text(
                          'Dictation Prompt',
                          style: TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                _buildFloatingDictationCard(context),
                const SizedBox(height: 8),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        secondary: const Icon(
                          Icons.cloud_download_outlined,
                          size: 20,
                        ),
                        title: const Text(
                          'App extracts URL content',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: const Text(
                          'App fetches content locally and sends text to AI',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: widget.settings.provider.mustExtractUrl
                            ? true
                            : widget.settings.appFetchUrl,
                        onChanged: widget.settings.provider.mustExtractUrl
                            ? null
                            : (val) async {
                                widget.settings.setAppFetchUrl(val);
                                await _storage.saveAppFetchUrl(val);
                                setState(() {});
                              },
                      ),
                      const Divider(height: 1, indent: 12, endIndent: 12),
                      SwitchListTile.adaptive(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        secondary: const Icon(Icons.bug_report, size: 20),
                        title: const Text(
                          'Debug Mode',
                          style: TextStyle(fontSize: 14),
                        ),
                        value: _debugMode,
                        onChanged: (val) async {
                          setState(() => _debugMode = val);
                          widget.settings.setDebugMode(val);
                          await _storage.saveDebugMode(val);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _floatingDictationStatusMessage(FloatingDictationStatus status) {
    if (!widget.settings.floatingDictationEnabled) {
      return 'Floating Dictation is disabled';
    }
    if (!FloatingDictationService.isAndroid) {
      return 'Floating Dictation is Android only in v1';
    }
    if (!widget.settings.provider.supportsFloatingDictation) {
      return '${widget.settings.provider.brandName} does not support Floating Dictation.';
    }
    if (status.configReady) return 'Provider settings are ready';
    if (widget.settings.provider == AiProviderType.localAi) {
      return 'Configure reachable Local AI LLM and Whisper endpoints first';
    }
    return 'Add the ${widget.settings.provider.brandName} API key above';
  }
}

class _FloatingStatusPill extends StatelessWidget {
  final String label;
  final bool ok;
  final VoidCallback? onPressed;

  const _FloatingStatusPill({
    required this.label,
    required this.ok,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final bg = ok ? color.primaryContainer : color.errorContainer;
    final fg = ok ? color.onPrimaryContainer : color.onErrorContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                ok ? Icons.check_circle : Icons.error_outline,
                size: 16,
                color: fg,
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiKeyCard extends StatelessWidget {
  final String labelText;
  final String hintText;
  final TextEditingController controller;
  final bool obscure;
  final bool? proValue;
  final VoidCallback onObscureToggle;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool>? onProChanged;
  final VoidCallback onDelete;
  final GlobalKey<FormState> formKey;
  final bool? realtimeValue;
  final ValueChanged<bool>? onRealtimeChanged;

  const _ApiKeyCard({
    required this.labelText,
    required this.hintText,
    required this.controller,
    required this.obscure,
    this.proValue,
    required this.onObscureToggle,
    required this.onChanged,
    this.onProChanged,
    required this.onDelete,
    required this.formKey,
    this.realtimeValue,
    this.onRealtimeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: controller,
                obscureText: obscure,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: labelText,
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.vpn_key, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    onPressed: onObscureToggle,
                  ),
                ),
                onChanged: onChanged,
              ),
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Remove ${labelText.split(' ')[0]} key?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) onDelete();
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Remove', style: TextStyle(fontSize: 11)),
                  ),
                  const Spacer(),
                  if (realtimeValue != null && onRealtimeChanged != null) ...[
                    const Text('Realtime', style: TextStyle(fontSize: 11)),
                    SizedBox(
                      height: 32,
                      child: Switch.adaptive(
                        value: realtimeValue!,
                        onChanged: onRealtimeChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (proValue != null && onProChanged != null) ...[
                    const Text('Pro', style: TextStyle(fontSize: 11)),
                    SizedBox(
                      height: 32,
                      child: Switch.adaptive(
                        value: proValue!,
                        onChanged: onProChanged,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalAiConfigCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController llmUrlController;
  final TextEditingController llmModelController;
  final TextEditingController whisperUrlController;
  final TextEditingController whisperModelController;
  final bool testingLlm;
  final bool testingWhisper;
  final ValueChanged<String> onChanged;
  final VoidCallback? onTestLlm;
  final VoidCallback? onTestWhisper;

  const _LocalAiConfigCard({
    required this.formKey,
    required this.llmUrlController,
    required this.llmModelController,
    required this.whisperUrlController,
    required this.whisperModelController,
    required this.testingLlm,
    required this.testingWhisper,
    required this.onChanged,
    required this.onTestLlm,
    required this.onTestWhisper,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Local AI', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _localAiTextField(
                controller: llmUrlController,
                label: 'LLM URL',
                hint: 'http://127.0.0.1:11434/api/chat',
                icon: Icons.hub_outlined,
                onChanged: onChanged,
              ),
              _localAiTextField(
                controller: llmModelController,
                label: 'LLM model',
                hint: 'qwen2.5:7b',
                icon: Icons.memory,
                onChanged: onChanged,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onTestLlm,
                  icon: testingLlm
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fact_check_outlined, size: 18),
                  label: const Text('Test LLM'),
                ),
              ),
              const Divider(height: 18),
              _localAiTextField(
                controller: whisperUrlController,
                label: 'Whisper URL',
                hint: 'http://127.0.0.1:8000/v1/audio/transcriptions',
                icon: Icons.graphic_eq,
                onChanged: onChanged,
              ),
              _localAiTextField(
                controller: whisperModelController,
                label: 'Whisper model',
                hint: 'whisper-1',
                icon: Icons.mic_none,
                onChanged: onChanged,
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onTestWhisper,
                  icon: testingWhisper
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.graphic_eq, size: 18),
                  label: const Text('Test Whisper'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'PoC mode: uses Ollama /api/chat for summaries and translation, plus an OpenAI-compatible Whisper endpoint for STT. Keep it on a trusted local network or VPN.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _localAiTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required ValueChanged<String> onChanged,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: suffixIcon,
      ),
      onChanged: onChanged,
    );
  }
}

class ProviderSelectorCard extends StatelessWidget {
  final AiProviderType selectedProvider;
  final Future<void> Function(AiProviderType provider) onProviderSelected;

  const ProviderSelectorCard({
    super.key,
    required this.selectedProvider,
    required this.onProviderSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          _ProviderOptionTile(
            value: AiProviderType.openai,
            label: 'OpenAI',
            iconPath: 'assets/images/chatgpt-icon.svg',
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
          const Divider(height: 1, indent: 56),
          _ProviderOptionTile(
            value: AiProviderType.gemini,
            label: 'Gemini',
            iconPath: 'assets/images/gemini-color.png',
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
          const Divider(height: 1, indent: 56),
          _ProviderOptionTile(
            value: AiProviderType.anthropic,
            label: 'Claude (no-audio) 🦀',
            iconPath: 'assets/images/claude-ai-icon.svg',
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
          const Divider(height: 1, indent: 56),
          _ProviderOptionTile(
            value: AiProviderType.xai,
            label: 'Grok',
            iconPath: 'assets/images/Grok-icon.svg',
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
          const Divider(height: 1, indent: 56),
          _ProviderOptionTile(
            value: AiProviderType.localAi,
            label: 'Local AI',
            iconData: Icons.storage_outlined,
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
          const Divider(height: 1, indent: 56),
          _ProviderOptionTile(
            value: AiProviderType.elevenLabs,
            label: 'ElevenLabs (Live STT + TTS)',
            iconData: Icons.record_voice_over_outlined,
            selectedProvider: selectedProvider,
            onSelected: onProviderSelected,
          ),
        ],
      ),
    );
  }
}

class _ProviderOptionTile extends StatelessWidget {
  final AiProviderType value;
  final String label;
  final String? iconPath;
  final IconData? iconData;
  final AiProviderType selectedProvider;
  final Future<void> Function(AiProviderType provider) onSelected;

  const _ProviderOptionTile({
    required this.value,
    required this.label,
    this.iconPath,
    this.iconData,
    required this.selectedProvider,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedProvider;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
      selected: selected,
      leading: iconPath == null
          ? Icon(iconData ?? Icons.memory, size: 24)
          : iconPath!.toLowerCase().endsWith('.svg')
              ? SvgPicture.asset(iconPath!, width: 24, height: 24)
              : Image.asset(iconPath!, width: 24, height: 24),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      onTap: () => onSelected(value),
    );
  }
}

class _EditPromptDialog extends StatefulWidget {
  final String labelText;
  final String initialText;

  const _EditPromptDialog({required this.labelText, required this.initialText});

  @override
  State<_EditPromptDialog> createState() => _EditPromptDialogState();
}

class _EditPromptDialogState extends State<_EditPromptDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        left: 16,
        right: 16,
        top: 8,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: TextField(
              controller: _controller,
              minLines: 8,
              maxLines: 15,
              decoration: InputDecoration(
                alignLabelWithHint: true,
                labelText: widget.labelText,
                hintText: 'Write how the summary should be generated…',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop({'action': 'reset'}),
                child: const Text('Reset to default'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop({'action': 'cancel'}),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop({'action': 'save', 'text': _controller.text.trim()}),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
