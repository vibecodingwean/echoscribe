import 'dart:async';
import 'dart:convert';

import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/tts_service.dart';
import 'package:echoscribe/state/playback_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in <String>{
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
    }) {
      messenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => null);
    }
  });

  test('an unresponsive speech request releases playback loading state',
      () async {
    final pending = Completer<http.Response>();
    final service = TtsService(
      client: MockClient((_) => pending.future),
      requestTimeout: const Duration(milliseconds: 20),
    );
    final playback = PlaybackState();
    addTearDown(playback.dispose);

    await expectLater(
      playback.playSummary(
        tts: service,
        text: 'Read this text',
        provider: AiProviderType.openai,
        activeApiKey: 'x',
      ),
      throwsA(isA<NetworkException>().having(
        (error) => error.userMessage,
        'message',
        contains('did not respond in time'),
      )),
    );
    expect(playback.isAudioLoading, isFalse);
    expect(playback.isPlaying, isFalse);
  });

  test('timeout aborts pending headers and body while client stays reusable',
      () async {
    var calls = 0;
    final headersAborted = Completer<void>();
    final bodyAborted = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      calls++;
      final trigger = (request as http.AbortableRequest).abortTrigger!;
      if (calls == 1) {
        final pending = Completer<http.StreamedResponse>();
        trigger.then((_) {
          headersAborted.complete();
          pending.complete(http.StreamedResponse(const Stream.empty(), 204));
        });
        return pending.future;
      }
      if (calls == 2) {
        final body = StreamController<List<int>>();
        trigger.then((_) {
          bodyAborted.complete();
          body.close();
        });
        return http.StreamedResponse(body.stream, 200);
      }
      return http.StreamedResponse(const Stream.empty(), 204);
    });
    final service = TtsService(
      client: client,
      requestTimeout: const Duration(milliseconds: 20),
    );

    for (var i = 0; i < 2; i++) {
      await expectLater(
        service.generateSpeechOpenAI(
          apiKey: 'x',
          text: 'Read this text',
        ),
        throwsA(isA<NetworkException>()),
      );
    }
    await headersAborted.future;
    await bodyAborted.future;
    expect(
      await service.generateSpeechOpenAI(
        apiKey: 'x',
        text: 'Read this text',
      ),
      isEmpty,
    );
    expect(calls, 3);
  });

  test('short OpenAI speech has a bounded wait without limiting long speech',
      () async {
    final atLimit = List.filled(200, 'x').join();
    final aboveLimit = List.filled(201, 'x').join();
    final abortedInputs = <String>[];
    final shortRequestsAborted = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      final input = (jsonDecode((request as http.AbortableRequest).body)
          as Map<String, dynamic>)['input'] as String;
      request.abortTrigger!.then((_) {
        abortedInputs.add(input);
        if (abortedInputs.length == 2) shortRequestsAborted.complete();
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return http.StreamedResponse(const Stream.empty(), 204);
    });
    final service = TtsService(
      client: client,
      requestTimeout: const Duration(milliseconds: 250),
      shortOpenAiRequestTimeout: const Duration(milliseconds: 20),
    );

    for (final input in ['Test, 1, 2, 3, 4', atLimit]) {
      await expectLater(
        service.generateSpeechOpenAI(apiKey: 'x', text: input),
        throwsA(isA<NetworkException>().having(
          (error) => error.userMessage,
          'message',
          contains('did not respond in time'),
        )),
      );
    }
    await shortRequestsAborted.future;
    expect(abortedInputs, ['Test, 1, 2, 3, 4', atLimit]);
    expect(
      await service.generateSpeechOpenAI(
        apiKey: 'x',
        text: aboveLimit,
      ),
      isEmpty,
    );
    expect(abortedInputs, hasLength(2));
  });
}
