import "package:echoscribe/services/ai/ai_provider_factory.dart";
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_handler/share_handler.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/utils/cross_file_reader.dart';
import 'package:echoscribe/services/share_handler.dart' as share_handler_service;

class ShareIntentController {
  final SettingsState settings;
  final ContentState content;
  final AiProviderFactory aiFactory;
  final Future<void> Function(String, String, String) onAudioReceived;
  final Future<void> Function(String) onTextReceived;
  final void Function(String) showError;
  final void Function(String) showSuccess;

  ShareIntentController({
    required this.settings,
    required this.content,
    required this.aiFactory,
    required this.onAudioReceived,
    required this.onTextReceived,
    required this.showError,
    required this.showSuccess,
  });

  Future<void> handleSharedMedia(SharedMedia media, BuildContext context) async {
    // Prefer explicit file attachments; fall back to text content
    final List<SharedAttachment> attachments =
        (media.attachments ?? const <SharedAttachment?>[])
            .whereType<SharedAttachment>()
            .toList();

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
        await onAudioReceived(path, name, inferredMime);
        return;
      }

      if (lower.endsWith('.txt') ||
          lower.endsWith('.md') ||
          lower.endsWith('.rtf')) {
        try {
          final bytes = await readAllBytesCross(path);
          final content = utf8.decode(bytes, allowMalformed: true);
          await onTextReceived(content);
        } catch (e) {
          showError('Failed to read shared text');
        }
        return;
      }

      final contentIfAny = (media.content ?? '').trim();
      if (contentIfAny.isEmpty) {
        showError('Content type not supported');
        return;
      }
    }

    final mediaContent = (media.content ?? '').trim();
    if (mediaContent.isNotEmpty) {
      final handled = await share_handler_service.ShareIntentHandler.tryHandleSharedText(
        context: context,
        textContent: mediaContent,
        settings: settings,
        content: content,
        aiFactory: aiFactory,
        showError: showError,
        showSuccess: showSuccess,
      );
      if (!handled) {
        showError('Content type not supported');
      }
    }
  }
}
