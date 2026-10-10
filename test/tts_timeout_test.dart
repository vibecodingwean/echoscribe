import 'dart:async';

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
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
  });

  test('an unresponsive speech request releases playback loading state', () async {
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
}
