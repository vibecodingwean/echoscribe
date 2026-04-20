import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:flutter/material.dart';
import 'package:echoscribe/models/enums.dart';

import 'package:share_plus/share_plus.dart';

class HistoryPage extends StatelessWidget {
  final ContentState content;
  const HistoryPage({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: content,
      builder: (context, _) {
        final items = content.history;
        return Scaffold(
          appBar: AppBar(
            title: const Text('History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Clear all',
                onPressed: items.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Clear history?'),
                            content: const Text('This will remove all transcriptions.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
                            ],
                          ),
                        );
                        if (!context.mounted) return;
                        if (ok == true) {
                          content.clearHistory();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared'), duration: Duration(milliseconds: 1000)));
                        }
                      },
              )
            ],
          ),
          body: SafeArea(
            child: items.isEmpty
                ? const Center(child: Text('No transcriptions yet'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) => _HistoryTile(
                      item: items[i],
                      onDelete: () => content.deleteHistoryItem(items[i].id),
                      onSelect: () {
                        final it = items[i];
                        // Start a fresh log for this loaded item
                        content.clearLog();
                        // Mark this item as active in the main view
                        content.setActiveHistory(it.id);
                        // Load into main view with correct mode
                        if ((it.mode == OutputMode.summary.name) || (it.summary != null)) {
                          content.setCurrentTranscript(it.transcript ?? it.text);
                          content.setCurrentSummary(it.summary ?? it.text);
                          content.setOutputMode(OutputMode.summary);
                        } else {
                          content.setCurrentTranscript(it.transcript ?? it.text);
                          content.setCurrentSummary('');
                          content.setOutputMode(OutputMode.transcription);
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final TranscriptionItem item;
  final VoidCallback onDelete;
  final VoidCallback onSelect;
  const _HistoryTile({required this.item, required this.onDelete, required this.onSelect});

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  bool _isUrlSummary(TranscriptionItem item) {
    final t = item.transcript ?? '';
    final isSummary = (item.mode == OutputMode.summary.name) || (item.summary != null);
    if (!isSummary || t.isEmpty) return false;
    final uri = Uri.tryParse(t);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }
 
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(color: c.errorContainer, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete_outline),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onSelect,
          onLongPress: () => SharePlus.instance.share(ShareParams(text: item.text)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.text_snippet_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.schedule, size: 16, color: c.primary),
                const SizedBox(width: 6),
                Text(_formatDate(item.createdAt), style: Theme.of(context).textTheme.labelMedium),
                if (item.duration != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.mic_none, size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  Text('${item.duration!.inSeconds}s', style: Theme.of(context).textTheme.labelMedium),
                ] else if (_isUrlSummary(item)) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.public, size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  Text('www', style: Theme.of(context).textTheme.labelMedium),
                ]
              ])
            ]),
          ),
        ),
      ),
    );
  }
}
