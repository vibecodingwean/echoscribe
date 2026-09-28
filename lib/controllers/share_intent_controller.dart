import "package:echoscribe/services/ai/ai_provider_factory.dart";
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:share_handler/share_handler.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:echoscribe/state/content_state.dart';
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
  final VoidCallback? onBeforeHandle;
  final void Function(String) showError;
  final void Function(String) showSuccess;

  ShareIntentController({
    required this.settings,
    required this.content,
    required this.aiFactory,
    required this.secureStorage,
    required this.onAudioReceived,
    required this.onTextReceived,
    this.onBeforeHandle,
    required this.showError,
    required this.showSuccess,
  });

  Future<void> handleSharedMedia(
      SharedMedia media, BuildContext context) async {
    onBeforeHandle?.call();
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    final String currentId = _getMediaIdentifier(media);
    if (currentId.isNotEmpty && currentId == settings.lastSharedIntentId) {
      debugPrint("Ignoring duplicate share intent: $currentId");
      return;
    }

    // Prefer explicit file attachments; fall back to text content
    final attachment =
        media.attachments?.whereType<SharedAttachment>().firstOrNull;

    try {
      bool handled = false;

      if (attachment != null) {
        final path = attachment.path;
        final name = path.split('/').last;
        final dot = path.lastIndexOf('.');
        final extension = dot < 0 ? '' : path.substring(dot).toLowerCase();
        final inferredMime = switch (extension) {
          '.m4a' => 'audio/m4a',
          '.mp3' => 'audio/mpeg',
          '.wav' => 'audio/wav',
          '.webm' => 'audio/webm',
          '.ogg' || '.opus' => 'audio/ogg',
          '.aac' || '.mp4' => 'audio/mp4',
          _ => null,
        };

        if (inferredMime != null) {
          handled = await onAudioReceived(path, name, inferredMime);
        } else if (extension == '.txt' ||
            extension == '.md' ||
            extension == '.rtf') {
          try {
            final bytes = await File(path).readAsBytes();
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
          if (share_handler_service.ShareIntentHandler.extractFirstHttpUrl(
                  mediaContent) !=
              null) {
            handled = await share_handler_service.ShareIntentHandler
                .tryHandleSharedText(
              context: context,
              textContent: mediaContent,
              settings: settings,
              content: content,
              aiFactory: aiFactory,
              showError: showError,
              showSuccess: showSuccess,
            );
          } else {
            handled = await onTextReceived(mediaContent);
          }
        }
      }

      if (handled) {
        if (currentId.isNotEmpty) {
          settings.setLastSharedIntentId(currentId);
          await secureStorage.saveLastSharedIntentId(currentId);
        }
      } else if (attachment == null && (media.content ?? '').trim().isEmpty) {
        // Only show error if we really have nothing to work with
        showError('Content type not supported');
      }
    } finally {
      await _removeManagedShareFile(media, attachment);
    }
  }

  Future<void> _removeManagedShareFile(
      SharedMedia media, SharedAttachment? attachment) async {
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        media.senderIdentifier?.startsWith('echoscribe-share-') != true ||
        attachment == null) {
      return;
    }
    final file = File(attachment.path);
    final managedName =
        RegExp(r'^[0-9a-fA-F-]{36}_').hasMatch(file.uri.pathSegments.last);
    if (!managedName || !file.parent.path.endsWith('/ShareImports')) return;
    try {
      await file.delete();
    } on FileSystemException {
      // A previous delivery may already have cleaned the same import.
    }
  }

  String _getMediaIdentifier(SharedMedia media) {
    // The iOS extension assigns a fresh identifier to every user share. This
    // prevents a later share of the same content from being dropped forever.
    final eventId = media.senderIdentifier;
    if (eventId != null && eventId.startsWith('echoscribe-share-')) {
      return eventId;
    }
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
