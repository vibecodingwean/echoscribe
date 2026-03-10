import "package:flutter/material.dart";
import "package:flutter_markdown_plus/flutter_markdown_plus.dart";
import 'package:echoscribe/theme.dart';
class FullScreenTextPage extends StatelessWidget {
  final String text;
  final String title;
  final bool isLog;

  const FullScreenTextPage({
    required this.text,
    required this.title,
    this.isLog = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: c.surface.withValues(alpha: 0.98),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.primary.withValues(alpha: 0.1), width: 1),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onDoubleTap: () => Navigator.of(context).pop(),
                    child: Hero(
                      tag: 'transcription_hero',
                      child: Material(
                        color: Colors.transparent,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: isLog
                                ? SelectableText(
                                    text,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  )
                                : MarkdownBody(
                                    data: text,
                                    selectable: true,
                                    styleSheet: AppMarkdownStyle.of(context, scaleFactor: 1.2),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
