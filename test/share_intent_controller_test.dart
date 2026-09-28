import 'dart:io';

import 'package:echoscribe/controllers/share_intent_controller.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/ai/ai_provider_factory.dart';
import 'package:echoscribe/services/secure_storage_service.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_handler/share_handler.dart';

void main() {
  for (final (extension, mime) in [
    ('m4a', 'audio/m4a'),
    ('mp3', 'audio/mpeg'),
    ('wav', 'audio/wav'),
    ('aac', 'audio/mp4'),
    ('webm', 'audio/webm'),
    ('ogg', 'audio/ogg'),
    ('opus', 'audio/ogg'),
    ('mp4', 'audio/mp4'),
  ]) {
    testWidgets('imports $extension and persists its identity once',
        (tester) async {
      final harness = await _Harness.mount(tester);
      final name = 'recording.${extension.toUpperCase()}';
      final path = '/shared/$name';
      final media = SharedMedia(
        attachments: [
          null,
          _attachment(path),
          _attachment('/shared/other.mp3')
        ],
        content: 'caption',
      );

      await tester.runAsync(() => harness.handle(media));
      expect(harness.audio, [(path, name, mime)]);
      expect(harness.text, isEmpty);
      expect(harness.errors, isEmpty);
      // Identity uses the original first attachment, even when it is null.
      expect(harness.storage.savedIds, ['7_caption_']);
      expect(harness.settings.lastSharedIntentId, '7_caption_');

      await tester.runAsync(() => harness.handle(media));
      expect(harness.audio, hasLength(1));
      expect(harness.storage.savedIds, hasLength(1));
      expect(harness.beforeCalls, 2);
    });
  }

  for (final extension in ['txt', 'md', 'rtf']) {
    testWidgets('imports $extension text with malformed UTF-8 replacement',
        (tester) async {
      final harness = await _Harness.mount(tester);
      await tester.runAsync(() async {
        final directory =
            await Directory.systemTemp.createTemp('share-import-test-');
        try {
          final file =
              File('${directory.path}/note.${extension.toUpperCase()}');
          await file.writeAsBytes([65, 255, 66]);
          await harness
              .handle(SharedMedia(attachments: [_attachment(file.path)]));
          expect(harness.text, ['A\uFFFDB']);
          expect(harness.audio, isEmpty);
          expect(harness.storage.savedIds, ['0__${file.path}']);
        } finally {
          await directory.delete(recursive: true);
        }
      });
    });
  }

  for (final path in [
    '',
    'mp3',
    '/shared/mp3',
    '/shared/a.mp3.txt.bak',
    '/shared/a.wav/child'
  ]) {
    testWidgets('does not infer audio for "$path" or inspect later attachments',
        (tester) async {
      final harness = await _Harness.mount(tester);
      await tester.runAsync(() => harness.handle(SharedMedia(
            attachments: [_attachment(path), _attachment('/shared/valid.mp3')],
            content: 'plain text',
          )));
      expect(harness.audio, isEmpty);
      expect(harness.text, ['plain text']);
      expect(harness.errors, isEmpty);
      expect(harness.storage.savedIds, ['10_plain text_$path']);
    });
  }

  testWidgets('imports plain shared text exactly once', (tester) async {
    final harness = await _Harness.mount(tester);
    final media = SharedMedia(content: '  Shared note  ');

    await tester.runAsync(() async {
      await harness.handle(media);
      await harness.handle(media);
    });

    expect(harness.text, ['Shared note']);
    expect(harness.storage.savedIds, ['11_Shared note_']);
  });

  testWidgets('separate iOS shares of similar text both run', (tester) async {
    final harness = await _Harness.mount(tester);
    final first = SharedMedia(
      content: 'A message with tail 2',
      senderIdentifier: 'echoscribe-share-event-one',
    );
    final second = SharedMedia(
      content: 'A message with tail 3',
      senderIdentifier: 'echoscribe-share-event-two',
    );
    await tester.runAsync(() async {
      await harness.handle(first);
      await harness.handle(first);
      await harness.handle(second);
    });
    expect(harness.storage.savedIds,
        ['echoscribe-share-event-one', 'echoscribe-share-event-two']);
    expect(harness.text, ['A message with tail 2', 'A message with tail 3']);
  });

  testWidgets('failed URL share can be retried without becoming plain text',
      (tester) async {
    final harness = await _Harness.mount(tester);
    harness.settings.setProvider(AiProviderType.elevenLabs);
    final media = SharedMedia(content: 'https://example.com/article');

    await tester.runAsync(() async {
      await harness.handle(media);
      await harness.handle(media);
    });

    expect(harness.text, isEmpty);
    expect(harness.storage.savedIds, isEmpty);
    expect(harness.errors, hasLength(2));
  });

  testWidgets('unhandled audio can be retried without saving its identity',
      (tester) async {
    final harness = await _Harness.mount(tester, acceptAudio: false);
    final media = SharedMedia(attachments: [_attachment('/shared/a.mp3')]);
    await tester.runAsync(() async {
      await harness.handle(media);
      await harness.handle(media);
    });
    expect(harness.audio, hasLength(2));
    expect(harness.storage.savedIds, isEmpty);
    expect(harness.errors, isEmpty);
  });

  testWidgets('iOS managed audio copy is removed after a failed import',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final harness = await _Harness.mount(tester, acceptAudio: false);
      await tester.runAsync(() async {
        final directory =
            await Directory.systemTemp.createTemp('share-cleanup-');
        try {
          final imports = Directory('${directory.path}/ShareImports');
          await imports.create();
          final file = File(
              '${imports.path}/123e4567-e89b-12d3-a456-426614174000_recording.mp3');
          await file.writeAsBytes([1, 2, 3]);
          await harness.handle(SharedMedia(
            attachments: [_attachment(file.path)],
            senderIdentifier: 'echoscribe-share-cleanup-test',
          ));
          expect(await file.exists(), isFalse);
          expect(harness.storage.savedIds, isEmpty);
        } finally {
          await directory.delete(recursive: true);
        }
      });
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('missing text file reports the existing read error',
      (tester) async {
    final harness = await _Harness.mount(tester);
    await tester.runAsync(() => harness.handle(SharedMedia(
          attachments: [_attachment('/missing-share-import-test/file.txt')],
        )));
    expect(harness.errors, ['Failed to read shared text']);
    expect(harness.storage.savedIds, isEmpty);
  });

  testWidgets(
      'empty share including null attachments reports unsupported content',
      (tester) async {
    final harness = await _Harness.mount(tester);
    await tester.runAsync(() => harness.handle(SharedMedia(
          attachments: [null],
          content: '  ',
        )));
    expect(harness.errors, ['Content type not supported']);
    expect(harness.storage.savedIds, isEmpty);
  });

  testWidgets('unmounted receiver stops after the before callback',
      (tester) async {
    final harness = await _Harness.mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => harness.handle(SharedMedia(
          attachments: [_attachment('/shared/a.mp3')],
        )));
    expect(harness.beforeCalls, 1);
    expect(harness.audio, isEmpty);
    expect(harness.storage.savedIds, isEmpty);
  });
}

SharedAttachment _attachment(String path) =>
    SharedAttachment(path: path, type: SharedAttachmentType.file);

class _Harness {
  final settings = SettingsState();
  final content = ContentState();
  final storage = _Storage();
  final audio = <(String, String, String)>[];
  final text = <String>[];
  final errors = <String>[];
  int beforeCalls = 0;
  late final ShareIntentController controller;
  late final BuildContext context;

  static Future<_Harness> mount(WidgetTester tester,
      {bool acceptAudio = true}) async {
    final harness = _Harness();
    addTearDown(harness.settings.dispose);
    addTearDown(harness.content.dispose);
    harness.controller = ShareIntentController(
      settings: harness.settings,
      content: harness.content,
      aiFactory: _UnusedFactory(),
      secureStorage: harness.storage,
      onAudioReceived: (path, name, mime) async {
        harness.audio.add((path, name, mime));
        return acceptAudio;
      },
      onTextReceived: (text) async {
        harness.text.add(text);
        return true;
      },
      onBeforeHandle: () => harness.beforeCalls++,
      showError: harness.errors.add,
      showSuccess: (_) {},
    );
    await tester.pumpWidget(Builder(builder: (context) {
      harness.context = context;
      return const SizedBox();
    }));
    return harness;
  }

  Future<void> handle(SharedMedia media) =>
      controller.handleSharedMedia(media, context);
}

class _Storage implements SecureStorageService {
  final savedIds = <String>[];

  @override
  Future<void> saveLastSharedIntentId(String id) async => savedIds.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedFactory implements AiProviderFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
