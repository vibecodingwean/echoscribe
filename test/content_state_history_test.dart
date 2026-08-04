import 'dart:async';
import 'dart:convert';

import 'package:echoscribe/models/transcription_item.dart';
import 'package:echoscribe/state/content_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history persistence is awaitable and serialized in mutation order',
      () async {
    final firstWriteEntered = Completer<void>();
    final allowFirstWrite = Completer<void>();
    final secondWriteEntered = Completer<void>();
    final persisted = <String>[];
    var writeCalls = 0;
    final content = ContentState(
      historyWriter: (encoded) async {
        writeCalls++;
        if (writeCalls == 1) {
          firstWriteEntered.complete();
          await allowFirstWrite.future;
        } else {
          secondWriteEntered.complete();
        }
        persisted.add(encoded);
      },
    );
    final item = TranscriptionItem(
      id: 'item-1',
      text: 'original',
      transcript: 'original',
      createdAt: DateTime.utc(2026),
    );

    final add = content.addHistoryAndPersist(item);
    expect(content.history.single.text, 'original');
    await firstWriteEntered.future;

    content.setActiveHistory(item.id);
    final update = content.updateActiveHistoryAndPersist(
      text: 'updated',
      transcript: 'updated',
    );
    expect(content.history.single.text, 'updated');
    await pumpEventQueue();
    expect(writeCalls, 1);

    allowFirstWrite.complete();
    await add;
    await secondWriteEntered.future;
    await update;

    expect(writeCalls, 2);
    expect(_firstText(persisted[0]), 'original');
    expect(_firstText(persisted[1]), 'updated');
  });

  test('new active history isolates summary from previously selected item',
      () async {
    final persisted = <String>[];
    final content = ContentState(
      historyWriter: (encoded) async => persisted.add(encoded),
    );
    final oldItem = _item('old');
    final newItem = _item('new');

    await content.addHistoryAndPersist(oldItem);
    content.setActiveHistory(oldItem.id);
    await content.addHistoryAndPersist(newItem, setActive: true);
    await content.updateActiveHistoryAndPersist(
      summary: 'new summary',
      mode: 'summary',
      text: 'new summary',
    );

    final oldSaved = content.history.singleWhere((item) => item.id == 'old');
    final newSaved = content.history.singleWhere((item) => item.id == 'new');
    expect(oldSaved.summary, isNull);
    expect(oldSaved.mode, isNull);
    expect(newSaved.summary, 'new summary');
    expect(newSaved.mode, 'summary');
    expect(newSaved.text, 'new summary');
    expect(_itemById(persisted.last, 'old')['summary'], isNull);
    expect(_itemById(persisted.last, 'new')['summary'], 'new summary');
  });

  test('failed history persistence does not poison later queued saves',
      () async {
    var writeCalls = 0;
    final persisted = <String>[];
    final content = ContentState(
      historyWriter: (encoded) async {
        writeCalls++;
        if (writeCalls == 1) throw StateError('first write failed');
        persisted.add(encoded);
      },
    );

    final first = content.addHistoryAndPersist(_item('first'));
    final second = content.addHistoryAndPersist(_item('second'));

    await expectLater(first, throwsStateError);
    await second;

    expect(writeCalls, 2);
    expect(_firstText(persisted.single), 'second');
  });
}

TranscriptionItem _item(String id) => TranscriptionItem(
      id: id,
      text: id,
      transcript: id,
      createdAt: DateTime.utc(2026),
    );

String _firstText(String encoded) {
  final items = (json.decode(encoded) as List).cast<Map<String, dynamic>>();
  return items.first['text'] as String;
}

Map<String, dynamic> _itemById(String encoded, String id) {
  final items = (json.decode(encoded) as List).cast<Map<String, dynamic>>();
  return items.singleWhere((item) => item['id'] == id);
}
