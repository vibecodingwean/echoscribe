import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:echoscribe/widgets/home/recording_controls.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:echoscribe/widgets/home/full_screen_text_page.dart';
import 'package:echoscribe/theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

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
  final ValueNotifier<Uint8List?> imageBytesNotifier;
  final bool isGeneratingImage;
  final bool supportsImage;
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
  final VoidCallback onGenerateImage;
  final void Function(Uint8List)? onImageTap;

  const TranscriptionPanel({
    super.key,
    required this.title,
    required this.transcriptNotifier,
    required this.summaryNotifier,
    required this.logTextNotifier,
    required this.imageBytesNotifier,
    required this.isGeneratingImage,
    required this.supportsImage,
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
    required this.onGenerateImage,
    this.onImageTap,
  });

  @override
  State<TranscriptionPanel> createState() => TranscriptionPanelState();
}

class TranscriptionPanelState extends State<TranscriptionPanel> {
  void _showImageOptions(BuildContext context, Uint8List bytes) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(context);
                final tempDir = await getTemporaryDirectory();
                final file = await File('${tempDir.path}/generated_image.png').create();
                await file.writeAsBytes(bytes);
                await Share.shareXFiles([XFile(file.path)], text: 'Generated with EchoScribe');
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to device'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  Directory? dir;
                  if (Platform.isAndroid) {
                    dir = Directory('/storage/emulated/0/Download');
                    if (!await dir.exists()) dir = await getExternalStorageDirectory();
                  } else {
                    dir = await getApplicationDocumentsDirectory();
                  }
                  
                  final fileName = 'EchoScribe_${DateTime.now().millisecondsSinceEpoch}.png';
                  final file = File('${dir!.path}/$fileName');
                  await file.writeAsBytes(bytes);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved to ${dir.path}/$fileName')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to save image')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

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
        widget.imageBytesNotifier,
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
                      if (displayText.isEmpty && widget.imageBytesNotifier.value == null && !widget.isLoading && !widget.isRecording)
                        Center(
                          child: Text(
                            "Your transcription will appear here...",
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          ),
                        )
                      else if (displayText.isNotEmpty || widget.imageBytesNotifier.value != null)
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (displayText.isNotEmpty)
                                showAsLog
                                  ? Text(
                                      displayText,
                                      style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                                    )
                                  : MarkdownBody(
                                      data: displayText,
                                      selectable: true,
                                      styleSheet: AppMarkdownStyle.of(context),
                                    ),
                              if (widget.imageBytesNotifier.value != null) ...[
                                if (displayText.isNotEmpty) const SizedBox(height: 16),
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => _FullScreenImageViewer(
                                          imageBytes: widget.imageBytesNotifier.value!,
                                        ),
                                      ),
                                    );
                                  },
                                  onLongPress: () {
                                    _showImageOptions(context, widget.imageBytesNotifier.value!);
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      widget.imageBytesNotifier.value!,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      if (widget.isRecording)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: FileLimitPill(durationNotifier: widget.recordDurationNotifier, maxDuration: widget.maxRecordDuration),
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

class _FullScreenImageViewer extends StatefulWidget {
  final Uint8List imageBytes;
  const _FullScreenImageViewer({required this.imageBytes});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails!.localPosition;
      // zoom in 3x
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx * 2, -position.dy * 2)
        ..scale(3.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: Center(
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.5,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: Image.memory(
              widget.imageBytes,
              fit: BoxFit.contain,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
            ),
          ),
        ),
      ),
    );
  }
}
