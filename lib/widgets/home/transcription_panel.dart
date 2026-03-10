import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:echoscribe/widgets/home/recording_controls.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:echoscribe/widgets/home/full_screen_text_page.dart';
import 'package:echoscribe/theme.dart';

class ProgressDots extends StatefulWidget {
  final Color? color;
  const ProgressDots({super.key, this.color});

  @override
  State<ProgressDots> createState() => ProgressDotsState();
}

class ProgressDotsState extends State<ProgressDots> {
  int _count = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) {
        setState(() {
          _count = (_count + 1) % 4; // 0..3 dots
        });
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Text(
        '.' * _count,
        style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: widget.color ?? Theme.of(context).colorScheme.primary,
            height: 0.5),
      ),
    );
  }
}

class TranscriptionPanel extends StatefulWidget {
  final String title;
  final ValueNotifier<String> transcriptNotifier;
  final ValueNotifier<String> summaryNotifier;
  final ValueNotifier<String> logTextNotifier;
  final bool isLoading;
  final bool isRecording;
  final ValueNotifier<Duration> recordDurationNotifier;
  final Duration maxRecordDuration;
  final bool isSummaryMode;
  final bool isDebugMode;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onPaste;
  final VoidCallback onClear;

  const TranscriptionPanel({
    super.key,
    required this.title,
    required this.transcriptNotifier,
    required this.summaryNotifier,
    required this.logTextNotifier,
    required this.isLoading,
    required this.isRecording,
    required this.recordDurationNotifier,
    required this.maxRecordDuration,
    required this.isSummaryMode,
    required this.isDebugMode,
    required this.onCopy,
    required this.onShare,
    required this.onPaste,
    required this.onClear,
  });

  @override
  State<TranscriptionPanel> createState() => TranscriptionPanelState();
}

class TranscriptionPanelState extends State<TranscriptionPanel> {
  Widget _buildHeader(BuildContext context, String displayText) {
    final bool hasText = displayText.trim().isNotEmpty;
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.paste, size: 20),
            onPressed: (widget.isLoading || widget.isRecording) ? null : widget.onPaste,
            tooltip: 'Paste',
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: hasText ? widget.onCopy : null,
            tooltip: 'Copy',
          ),
          IconButton(
            icon: const Icon(Icons.share, size: 20),
            onPressed: hasText ? widget.onShare : null,
            tooltip: 'Share',
          ),
          IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: hasText ? widget.onClear : null,
            tooltip: 'Clear',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.transcriptNotifier,
        widget.summaryNotifier,
        widget.logTextNotifier,
      ]),
      builder: (context, child) {
        final bool showAsLog = (widget.isDebugMode || widget.isLoading || widget.isRecording) && widget.logTextNotifier.value.isNotEmpty;
        final String displayText = showAsLog 
            ? widget.logTextNotifier.value 
            : (widget.isSummaryMode ? widget.summaryNotifier.value : widget.transcriptNotifier.value);

        return GestureDetector(
          onDoubleTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FullScreenTextPage(
                  title: widget.title,
                  text: displayText,
                ),
              ),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, displayText),
                const Divider(height: 1),
                Expanded(
                  child: Stack(
                    children: [
                      if (displayText.isEmpty && !widget.isLoading && !widget.isRecording)
                        Center(
                          child: Text(
                            "Your transcription will appear here...",
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                        )
                      else if (displayText.isNotEmpty)
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: showAsLog
                              ? Text(
                                  displayText,
                                  style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                                )
                              : MarkdownBody(
                                  data: displayText,
                                  selectable: true,
                                  styleSheet: AppMarkdownStyle.of(context),
                                ),
                        ),
                      if (widget.isLoading || widget.isRecording)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: widget.isRecording
                              ? FileLimitPill(durationNotifier: widget.recordDurationNotifier, maxDuration: widget.maxRecordDuration)
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ProgressDots(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  ),
                                ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
