import 'dart:async';
import 'dart:io';

import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/services/ai/elevenlabs_realtime_client_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'close before WebSocket acquisition closes the late socket without listening',
    () async {
      final connectorStarted = Completer<void>();
      final socketCompleter = Completer<WebSocket>();
      final socket = FakeWebSocket();
      final client = ElevenLabsRealtimeClientImpl(
        connector: (url, {headers}) {
          connectorStarted.complete();
          return socketCompleter.future;
        },
      );
      var connectedCalls = 0;
      var transcriptCalls = 0;
      var errorCalls = 0;
      var disconnectedCalls = 0;

      final connecting = client.connect(
        apiKey: 'test-key',
        model: 'test-model',
        targetLanguageCode: 'auto',
        onTranscriptDelta: (_) => transcriptCalls++,
        onTranscriptCompleted: (_) => transcriptCalls++,
        onError: (_) => errorCalls++,
        onConnected: () => connectedCalls++,
        onDisconnected: () => disconnectedCalls++,
      );
      await connectorStarted.future;

      await client.close();
      socketCompleter.complete(socket);

      await expectLater(
        connecting,
        throwsA(
          isA<AppException>().having(
            (error) => error.toString(),
            'message',
            contains('cancelled'),
          ),
        ),
      );
      expect(socket.closeCalls, 1);
      expect(socket.listenCalls, 0);
      expect(socket.activeSubscriptions, 0);
      expect(connectedCalls, 0);
      expect(transcriptCalls, 0);
      expect(errorCalls, 0);
      expect(disconnectedCalls, 1);
    },
  );

  test('a socket acquired after the connect timeout is still closed', () async {
    final connectorStarted = Completer<void>();
    final socketCompleter = Completer<WebSocket>();
    final socket = FakeWebSocket();
    final client = ElevenLabsRealtimeClientImpl(
      connectionTimeout: const Duration(milliseconds: 1),
      connector: (url, {headers}) {
        connectorStarted.complete();
        return socketCompleter.future;
      },
    );

    final connecting = connectClient(client);
    await connectorStarted.future;
    await client.close();
    await expectLater(connecting, throwsA(isA<AppException>()));

    socketCompleter.complete(socket);
    await socket.closed.future;
    expect(socket.closeCalls, 1);
    expect(socket.listenCalls, 0);
    expect(socket.activeSubscriptions, 0);
  });

  test('a cancelled attempt cannot close a newer attempt socket', () async {
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstSocketCompleter = Completer<WebSocket>();
    final secondSocketCompleter = Completer<WebSocket>();
    final firstSocket = FakeWebSocket();
    final secondSocket = FakeWebSocket();
    var connectorCalls = 0;
    final client = ElevenLabsRealtimeClientImpl(
      connector: (url, {headers}) {
        connectorCalls++;
        if (connectorCalls == 1) {
          firstStarted.complete();
          return firstSocketCompleter.future;
        }
        secondStarted.complete();
        return secondSocketCompleter.future;
      },
    );

    final firstConnect = connectClient(client);
    await firstStarted.future;
    final secondConnect = connectClient(client);
    await secondStarted.future;

    secondSocketCompleter.complete(secondSocket);
    await secondSocket.listened.future;
    secondSocket.emitSessionStarted();
    await secondConnect;

    firstSocketCompleter.complete(firstSocket);
    await expectLater(
      firstConnect,
      throwsA(
        isA<AppException>().having(
          (error) => error.toString(),
          'message',
          contains('cancelled'),
        ),
      ),
    );
    expect(firstSocket.closeCalls, 1);
    expect(firstSocket.listenCalls, 0);
    expect(secondSocket.closeCalls, 0);
    expect(secondSocket.activeSubscriptions, 1);

    await client.close();
    expect(secondSocket.closeCalls, 1);
    expect(secondSocket.activeSubscriptions, 0);
  });

  test('close still closes the socket when subscription cancellation fails',
      () async {
    final firstSocket = FakeWebSocket(throwOnCancel: true);
    final secondSocket = FakeWebSocket();
    final sockets = <FakeWebSocket>[firstSocket, secondSocket];
    final client = ElevenLabsRealtimeClientImpl(
      connector: (url, {headers}) async => sockets.removeAt(0),
    );

    final firstConnect = connectClient(client);
    await firstSocket.listened.future;
    firstSocket.emitSessionStarted();
    await firstConnect;
    client.sendAudioChunk([1, 2, 3]);

    await expectLater(
      client.close(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'cancel failure',
        ),
      ),
    );
    expect(firstSocket.closeCalls, 1);
    expect(firstSocket.activeSubscriptions, 0);

    await client.close();
    expect(firstSocket.closeCalls, 1);

    final secondConnect = connectClient(client);
    await secondSocket.listened.future;
    secondSocket.emitSessionStarted();
    await secondConnect;
    await client.finishAudio();
    expect(secondSocket.added, isEmpty);
    await client.close();
  });

  test(
    'connect preserves its original failure and reports disconnection when socket close fails',
    () async {
      final socket = FakeWebSocket(
        listenError: StateError('original listen failure'),
        throwOnClose: true,
      );
      final client = ElevenLabsRealtimeClientImpl(
        connector: (url, {headers}) async => socket,
      );
      var disconnectedCalls = 0;

      await expectLater(
        connectClient(
          client,
          onDisconnected: () => disconnectedCalls++,
        ),
        throwsA(
          isA<AppException>()
              .having(
                (error) => error.toString(),
                'message',
                contains('original listen failure'),
              )
              .having(
                (error) => error.toString(),
                'message',
                isNot(contains('cleanup close failure')),
              ),
        ),
      );
      expect(socket.closeCalls, 1);
      expect(disconnectedCalls, 1);
      await client.close();
    },
  );
}

Future<void> connectClient(
  ElevenLabsRealtimeClientImpl client, {
  void Function()? onDisconnected,
}) {
  return client.connect(
    apiKey: 'test-key',
    model: 'test-model',
    targetLanguageCode: 'auto',
    onTranscriptDelta: (_) {},
    onTranscriptCompleted: (_) {},
    onError: (_) {},
    onConnected: () {},
    onDisconnected: onDisconnected ?? () {},
  );
}

class FakeWebSocket extends Stream<dynamic> implements WebSocket {
  FakeWebSocket({
    this.throwOnCancel = false,
    this.throwOnClose = false,
    this.listenError,
  });

  final StreamController<dynamic> _controller = StreamController<dynamic>();
  final bool throwOnCancel;
  final bool throwOnClose;
  final Object? listenError;
  final Completer<void> listened = Completer<void>();
  final Completer<void> closed = Completer<void>();
  final List<dynamic> added = <dynamic>[];

  int closeCalls = 0;
  int listenCalls = 0;
  int activeSubscriptions = 0;

  @override
  int get readyState => WebSocket.open;

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final error = listenError;
    if (error != null) throw error;
    listenCalls++;
    activeSubscriptions++;
    listened.complete();
    var active = true;

    void markInactive() {
      if (!active) return;
      active = false;
      activeSubscriptions--;
    }

    return TrackingSubscription<dynamic>(
      _controller.stream.listen(
        onData,
        onError: onError,
        onDone: () {
          markInactive();
          onDone?.call();
        },
        cancelOnError: cancelOnError,
      ),
      onCancel: markInactive,
      throwOnCancel: throwOnCancel,
    );
  }

  void emitSessionStarted() {
    _controller.add('{"message_type":"session_started"}');
  }

  @override
  void add(dynamic data) {
    added.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCalls++;
    if (!closed.isCompleted) closed.complete();
    if (throwOnClose) throw StateError('cleanup close failure');
    if (listenCalls > 0) await _controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TrackingSubscription<T> implements StreamSubscription<T> {
  TrackingSubscription(
    this._inner, {
    required this.onCancel,
    required this.throwOnCancel,
  });

  final StreamSubscription<T> _inner;
  final void Function() onCancel;
  final bool throwOnCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() async {
    if (throwOnCancel) throw StateError('cancel failure');
    if (!_cancelled) {
      _cancelled = true;
      onCancel();
    }
    await _inner.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  bool get isPaused => _inner.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture<E>(futureValue);
}
