import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareContentOptions {
  const ShareContentOptions({
    required this.hasText,
    required this.hasAudio,
    required this.hasImage,
  });

  final bool hasText;
  final bool hasAudio;
  final bool hasImage;

  bool get isEmpty => !hasText && !hasAudio && !hasImage;

  int get count =>
      (hasText ? 1 : 0) + (hasAudio ? 1 : 0) + (hasImage ? 1 : 0);
}

ShareContentOptions resolveShareContentOptions({
  required bool hasText,
  required bool hasAudio,
  required bool hasImage,
}) {
  return ShareContentOptions(
    hasText: hasText,
    hasAudio: hasAudio,
    hasImage: hasImage,
  );
}

String shareAudioExtension(String mimeType) {
  return mimeType == 'audio/wav' ? 'wav' : 'mp3';
}

Future<void> sharePlainText(String text) {
  return SharePlus.instance.share(ShareParams(text: text));
}

Future<void> shareBytesAsFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? text,
}) async {
  final tempDir = await getTemporaryDirectory();
  final file = await File('${tempDir.path}/$filename').create();
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      text: text,
    ),
  );
}

Future<void> showShareContentSheet({
  required BuildContext context,
  required String text,
  Uint8List? audioBytes,
  String audioMimeType = 'audio/mpeg',
  Uint8List? imageBytes,
}) async {
  final options = resolveShareContentOptions(
    hasText: text.trim().isNotEmpty,
    hasAudio: audioBytes != null && audioBytes.isNotEmpty,
    hasImage: imageBytes != null && imageBytes.isNotEmpty,
  );
  if (options.isEmpty) return;

  if (options.count == 1) {
    if (options.hasText) {
      await sharePlainText(text.trim());
      return;
    }
    if (options.hasAudio) {
      await shareBytesAsFile(
        bytes: audioBytes!,
        filename: 'echoscribe_tts.${shareAudioExtension(audioMimeType)}',
        mimeType: audioMimeType,
      );
      return;
    }
    await shareBytesAsFile(
      bytes: imageBytes!,
      filename: 'echoscribe_image.png',
      mimeType: 'image/png',
      text: 'Generated with EchoScribe',
    );
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (options.hasText)
              ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('Text'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await sharePlainText(text.trim());
                },
              ),
            if (options.hasAudio)
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: const Text('Audio'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await shareBytesAsFile(
                    bytes: audioBytes!,
                    filename:
                        'echoscribe_tts.${shareAudioExtension(audioMimeType)}',
                    mimeType: audioMimeType,
                  );
                },
              ),
            if (options.hasImage)
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Image'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await shareBytesAsFile(
                    bytes: imageBytes!,
                    filename: 'echoscribe_image.png',
                    mimeType: 'image/png',
                    text: 'Generated with EchoScribe',
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}
