import "package:echoscribe/services/ai/ai_provider_factory.dart";
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/utils/cross_file_reader.dart';
import 'package:echoscribe/services/share_handler.dart'
    as share_handler_service;
import 'package:echoscribe/services/secure_storage_service.dart';

class ShareIntentController {
  final SettingsState settings;
  final ContentState content;
  final AiProviderFactory aiFactory;
  final SecureStorageService secureStorage;
  final Future<bool> Function(String, String, String) onAudioReceived;
  final Future<bool> Function(String) onTextReceived;
  final void Function(String) showError;
  final void Function(String) showSuccess;

  ShareIntentController({
    required this.settings,
    required this.content,
    required this.aiFactory,
    required this.secureStorage,
    required this.onAudioReceived,
    required this.onTextReceived,
    required this.showError,
    required this.showSuccess,
  });

  Future<void> handleSharedMedia(
      SharedMedia media, BuildContext context) async {
    final String currentId = _getMediaIdentifier(media);
    if (currentId.isNotEmpty && currentId == settings.lastSharedIntentId) {
      debugPrint("Ignoring duplicate share intent: $currentId");
      return;
    }

    // Prefer explicit file attachments; fall back to text content
    final List<SharedAttachment> attachments =
        (media.attachments ?? const <SharedAttachment?>[])
            .whereType<SharedAttachment>()
            .toList();

    bool handled = false;

    if (attachments.isNotEmpty) {
      final SharedAttachment first = attachments.first;
      final String path = first.path;
      final String name =
          path.split('/').isNotEmpty ? path.split('/').last : 'file';
      final String lower = path.toLowerCase();

      if (lower.endsWith('.m4a') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.webm') ||
          lower.endsWith('.ogg') ||
          lower.endsWith('.opus') ||
          lower.endsWith('.mp4')) {
        final inferredMime = lower.endsWith('.webm')
            ? 'audio/webm'
            : lower.endsWith('.m4a')
                ? 'audio/m4a'
                : lower.endsWith('.mp3')
                    ? 'audio/mpeg'
                    : lower.endsWith('.wav')
                        ? 'audio/wav'
                        : lower.endsWith('.ogg') || lower.endsWith('.opus')
                            ? 'audio/ogg'
                            : lower.endsWith('.mp4')
                                ? 'audio/mp4'
                                : 'audio/mp4';
        handled = await onAudioReceived(path, name, inferredMime);
      } else if (lower.endsWith('.txt') ||
          lower.endsWith('.md') ||
          lower.endsWith('.rtf')) {
        try {
          final bytes = await readAllBytesCross(path);
          final content = utf8.decode(bytes, allowMalformed: true);
          handled = await onTextReceived(content);
        } catch (e) {
          showError('Failed to read shared text');
        }
      }
    }

    if (!handled) {
      final mediaContent = (media.content ?? '').trim();
      if (mediaContent.isNotEmpty && context.mounted) {
        handled =
            await share_handler_service.ShareIntentHandler.tryHandleSharedText(
          context: context,
          textContent: mediaContent,
          settings: settings,
          content: content,
          aiFactory: aiFactory,
          showError: showError,
          showSuccess: showSuccess,
        );
      }
    }

    if (handled) {
      if (currentId.isNotEmpty) {
        settings.setLastSharedIntentId(currentId);
        await secureStorage.saveLastSharedIntentId(currentId);
      }
    } else if (attachments.isEmpty && (media.content ?? '').trim().isEmpty) {
      // Only show error if we really have nothing to work with
      showError('Content type not supported');
    }
  }

  String _getMediaIdentifier(SharedMedia media) {
    // Create a reasonably unique string for this media object
    final content = (media.content ?? '').trim();
    final firstPath = (media.attachments?.isNotEmpty ?? false)
        ? media.attachments!.first?.path ?? ''
        : '';
    if (content.isEmpty && firstPath.isEmpty) return '';

    // Hash-like string: length + first 20 chars of content + path
    final contentPart =
        content.length > 20 ? content.substring(0, 20) : content;
    return "${content.length}_${contentPart}_$firstPath";
  }
}
