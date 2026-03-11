import 'package:echoscribe/services/secure_storage_service.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';

class SettingsPage extends StatefulWidget {
  final SettingsState settings;
  const SettingsPage({super.key, required this.settings});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _openAiFormKey = GlobalKey<FormState>();
  final _geminiFormKey = GlobalKey<FormState>();
  final _anthropicFormKey = GlobalKey<FormState>();
  late final TextEditingController _openAiCtrl;
  late final TextEditingController _geminiCtrl;
  late final TextEditingController _anthropicCtrl;
  late final TextEditingController _xaiCtrl;
  final _xaiFormKey = GlobalKey<FormState>();
  final _storage = SecureStorageService();
  bool _obscureOpenAi = true;
  bool _obscureGemini = true;
  bool _obscureAnthropic = true;
  bool _obscureXai = true;
  late bool _debugMode;
  late bool _openAiPro;
  late bool _geminiPro;
  late bool _anthropicPro;
  late bool _xaiPro;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _openAiCtrl = TextEditingController(text: widget.settings.openAiKey);
    _geminiCtrl = TextEditingController(text: widget.settings.geminiKey);
    _anthropicCtrl = TextEditingController(text: widget.settings.anthropicKey);
    _xaiCtrl = TextEditingController(text: widget.settings.xaiKey);
    _debugMode = widget.settings.debugMode;
    _openAiPro = widget.settings.openAiPro;
    _geminiPro = widget.settings.geminiPro;
    _anthropicPro = widget.settings.anthropicPro;
    _xaiPro = widget.settings.xaiPro;
  }

  @override
  void dispose() {
    _openAiCtrl.dispose();
    _geminiCtrl.dispose();
    _anthropicCtrl.dispose();
    _xaiCtrl.dispose();
    super.dispose();
  }

  void _resetAudioPromptToDefault() {
    final defaultPrompt = SettingsState().summaryPrompt;
    widget.settings.setSummaryPrompt(defaultPrompt);
  }

  void _resetUrlPromptToDefault() {
    final defaultPrompt = SettingsState().urlSummaryPrompt;
    widget.settings.setUrlSummaryPrompt(defaultPrompt);
  }

  Future<void> _openPromptDialog({required String labelText, required String initialText, required Future<void> Function(String value) onSave, required Future<void> Function() onReset}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (builderContext) {
        return _EditPromptDialog(labelText: labelText, initialText: initialText);
      },
    );

    if (result == null) return;

    final action = result['action'];

    if (action == 'reset') {
      await onReset();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt reset to default'), duration: Duration(milliseconds: 1000)));
        setState(() {});
      }
    } else if (action == 'save') {
      final newPrompt = result['text'] as String;
      await onSave(newPrompt);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt saved'), duration: Duration(milliseconds: 1000)));
        setState(() {});
      }
    }
  }

  Future<void> _autoSaveKeysIfValid() async {
    final validOpen = _openAiFormKey.currentState?.validate() ?? true;
    final validGem = _geminiFormKey.currentState?.validate() ?? true;
    final validAnt = _anthropicFormKey.currentState?.validate() ?? true;
    final validXai = _xaiFormKey.currentState?.validate() ?? true;
    if (!validOpen || !validGem || !validAnt || !validXai) return;
    final openKey = _openAiCtrl.text.trim();
    final gemKey = _geminiCtrl.text.trim();
    final antKey = _anthropicCtrl.text.trim();
    final xaiKey = _xaiCtrl.text.trim();
    widget.settings.setOpenAiKey(openKey);
    widget.settings.setGeminiKey(gemKey);
    widget.settings.setAnthropicKey(antKey);
    widget.settings.setXaiKey(xaiKey);
    await _storage.saveOpenAiKey(openKey);
    await _storage.saveGeminiKey(gemKey);
    await _storage.saveAnthropicKey(antKey);
    await _storage.saveXaiKey(xaiKey);
  }

  void _scheduleAutoSaveImmediate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final openKey = _openAiCtrl.text.trim();
      final gemKey = _geminiCtrl.text.trim();
      final antKey = _anthropicCtrl.text.trim();
      final xaiKey = _xaiCtrl.text.trim();
      widget.settings.setOpenAiKey(openKey);
      widget.settings.setGeminiKey(gemKey);
      widget.settings.setAnthropicKey(antKey);
      widget.settings.setXaiKey(xaiKey);
      await _storage.saveOpenAiKey(openKey);
      await _storage.saveGeminiKey(gemKey);
      await _storage.saveAnthropicKey(antKey);
      await _storage.saveXaiKey(xaiKey);
    });
  }

  bool _snackShownOnExit = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        await _autoSaveKeysIfValid();
        if (didPop && !_snackShownOnExit && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Settings saved'), duration: Duration(milliseconds: 1000)),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('API Config'),
          leading: BackButton(
            onPressed: () async {
              await _autoSaveKeysIfValid();
              if (mounted) {
                _snackShownOnExit = true;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings saved'), duration: Duration(milliseconds: 1000)),
                );
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Choose Provider', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _ProviderRadioTile(
                            value: AiProviderType.openai,
                            label: 'OpenAI',
                            iconPath: 'assets/images/chatgpt-icon.svg',
                            groupValue: widget.settings.provider,
                            onChanged: (val) {
                              widget.settings.setProvider(val!);
                              _storage.saveProvider(val);
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                          _ProviderRadioTile(
                            value: AiProviderType.gemini,
                            label: 'Gemini',
                            iconPath: 'assets/images/google-gemini-icon.svg',
                            groupValue: widget.settings.provider,
                            onChanged: (val) {
                              widget.settings.setProvider(val!);
                              _storage.saveProvider(val);
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                          _ProviderRadioTile(
                            value: AiProviderType.anthropic,
                            label: 'Claude (no-audio) 🦀',
                            iconPath: 'assets/images/claude-ai-icon.svg',
                            groupValue: widget.settings.provider,
                            onChanged: (val) async {
                              widget.settings.setProvider(val!);
                              await _storage.saveProvider(val);
                              if (val.mustExtractUrl) {
                                widget.settings.setAppFetchUrl(true);
                                await _storage.saveAppFetchUrl(true);
                              }
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 56),
                          _ProviderRadioTile(
                            value: AiProviderType.xai,
                            label: 'Grok (no-audio)',
                            iconPath: 'assets/images/grok-ai-icon.svg',
                            groupValue: widget.settings.provider,
                            onChanged: (val) async {
                              widget.settings.setProvider(val!);
                              await _storage.saveProvider(val);
                              if (val.mustExtractUrl) {
                                widget.settings.setAppFetchUrl(true);
                                await _storage.saveAppFetchUrl(true);
                              }
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    if (widget.settings.provider == AiProviderType.openai)
                      _ApiKeyCard(
                        labelText: 'OpenAI API Key',
                        hintText: 'sk-...',
                        controller: _openAiCtrl,
                        obscure: _obscureOpenAi,
                        proValue: _openAiPro,
                        onObscureToggle: () => setState(() => _obscureOpenAi = !_obscureOpenAi),
                        onChanged: (_) => _scheduleAutoSaveImmediate(),
                        onProChanged: (val) async {
                          setState(() => _openAiPro = val);
                          widget.settings.setOpenAiPro(val);
                          await _storage.saveOpenAiPro(val);
                        },
                        onDelete: () async {
                          await _storage.deleteOpenAiKey();
                          widget.settings.setOpenAiKey('');
                          _openAiCtrl.clear();
                        },
                        formKey: _openAiFormKey,
                      ),

                    if (widget.settings.provider == AiProviderType.gemini)
                      _ApiKeyCard(
                        labelText: 'Gemini API Key',
                        hintText: 'AIza...',
                        controller: _geminiCtrl,
                        obscure: _obscureGemini,
                        proValue: _geminiPro,
                        onObscureToggle: () => setState(() => _obscureGemini = !_obscureGemini),
                        onChanged: (_) => _scheduleAutoSaveImmediate(),
                        onProChanged: (val) async {
                          setState(() => _geminiPro = val);
                          widget.settings.setGeminiPro(val);
                          await _storage.saveGeminiPro(val);
                        },
                        onDelete: () async {
                          await _storage.deleteGeminiKey();
                          widget.settings.setGeminiKey('');
                          _geminiCtrl.clear();
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
                        onObscureToggle: () => setState(() => _obscureAnthropic = !_obscureAnthropic),
                        onChanged: (_) => _scheduleAutoSaveImmediate(),
                        onProChanged: (val) async {
                          setState(() => _anthropicPro = val);
                          widget.settings.setAnthropicPro(val);
                          await _storage.saveAnthropicPro(val);
                        },
                        onDelete: () async {
                          await _storage.deleteAnthropicKey();
                          widget.settings.setAnthropicKey('');
                          _anthropicCtrl.clear();
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
                        onObscureToggle: () => setState(() => _obscureXai = !_obscureXai),
                        onChanged: (_) => _scheduleAutoSaveImmediate(),
                        onProChanged: (val) async {
                          setState(() => _xaiPro = val);
                          widget.settings.setXaiPro(val);
                          await _storage.saveXaiPro(val);
                        },
                        onDelete: () async {
                          await _storage.deleteXaiKey();
                          widget.settings.setXaiKey('');
                          _xaiCtrl.clear();
                        },
                        formKey: _xaiFormKey,
                      ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
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
                            label: const Text('Audio Prompt', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
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
                            label: const Text('URL Prompt', style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                            secondary: const Icon(Icons.cloud_download_outlined, size: 20),
                            title: const Text('App extracts URL content', style: TextStyle(fontSize: 14)),
                            subtitle: const Text('App fetches content locally and sends text to AI', style: TextStyle(fontSize: 12)),
                            value: widget.settings.provider.mustExtractUrl ? true : widget.settings.appFetchUrl,
                            onChanged: widget.settings.provider.mustExtractUrl ? null : (val) async {
                              widget.settings.setAppFetchUrl(val);
                              await _storage.saveAppFetchUrl(val);
                              setState(() {});
                            },
                          ),
                          const Divider(height: 1, indent: 12, endIndent: 12),
                          SwitchListTile.adaptive(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                            secondary: const Icon(Icons.bug_report, size: 20),
                            title: const Text('Debug Mode', style: TextStyle(fontSize: 14)),
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
                  ]),
                ),
              ),
      ),
    );
  }
}

class _ProviderRadioTile extends StatelessWidget {
  final AiProviderType value;
  final String label;
  final String iconPath;
  final AiProviderType groupValue;
  final ValueChanged<AiProviderType?> onChanged;

  const _ProviderRadioTile({
    required this.value,
    required this.label,
    required this.iconPath,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<AiProviderType>(
      value: value,
      groupValue: groupValue,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      visualDensity: VisualDensity.compact,
      title: Row(
        children: [
          SvgPicture.asset(iconPath, width: 24, height: 24),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ApiKeyCard extends StatelessWidget {
  final String labelText;
  final String hintText;
  final TextEditingController controller;
  final bool obscure;
  final bool proValue;
  final VoidCallback onObscureToggle;
  final ValueChanged<String> onChanged;
  final ValueChanged<bool> onProChanged;
  final VoidCallback onDelete;
  final GlobalKey<FormState> formKey;

  const _ApiKeyCard({
    required this.labelText,
    required this.hintText,
    required this.controller,
    required this.obscure,
    required this.proValue,
    required this.onObscureToggle,
    required this.onChanged,
    required this.onProChanged,
    required this.onDelete,
    required this.formKey,
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
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, size: 18),
                    onPressed: onObscureToggle,
                  ),
                ),
                onChanged: onChanged,
              ),
              Row(children: [
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
                          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (confirm == true) onDelete();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove', style: TextStyle(fontSize: 11)),
                ),
                const Spacer(),
                const Text('Pro', style: TextStyle(fontSize: 11)),
                SizedBox(
                  height: 32,
                  child: Switch.adaptive(
                    value: proValue,
                    onChanged: onProChanged,
                  ),
                ),
              ])
            ],
          ),
        ),
      ),
    );
  }
}

class _EditPromptDialog extends StatefulWidget {
  final String labelText;
  final String initialText;

  const _EditPromptDialog({super.key, required this.labelText, required this.initialText});

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
                onPressed: () => Navigator.of(context).pop({'action': 'cancel'}),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop({'action': 'save', 'text': _controller.text.trim()}),
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
