import 'dart:async';

import 'package:echoscribe/models/app_exception.dart';
import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/ai/ai_provider.dart';
import 'package:echoscribe/services/ai/consent_aware_provider.dart';
import 'package:echoscribe/services/provider_consent_service.dart';
import 'package:echoscribe/services/tts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('a denied first request never reaches the provider', () async {
    final delegate = _CountingProvider();
    final consent =
        ProviderConsentService(requestPermission: (_) async => false);
    final provider = ConsentAwareProvider(
      provider: AiProviderType.openai,
      delegate: delegate,
      consent: consent,
    );

    await expectLater(
      provider.summarize(
        apiKey: 'test-key',
        text: 'private text',
        model: 'test-model',
        targetLanguageCode: 'en',
      ),
      throwsA(isA<AppException>()),
    );
    expect(delegate.calls, 0);
    expect(await consent.hasGrant(AiProviderType.openai), isFalse);
  });

  test('denied speech generation sends no HTTP request', () async {
    var requests = 0;
    final service = TtsService(
      client: MockClient((_) async {
        requests++;
        return http.Response('unexpected request', 500);
      }),
      consent: ProviderConsentService(requestPermission: (_) async => false),
    );

    await expectLater(
      service.generateSpeechOpenAI(apiKey: 'test-key', text: 'private text'),
      throwsA(isA<AppException>()),
    );
    expect(requests, 0);
  });

  test('grant persists per provider and withdrawal blocks future requests',
      () async {
    var prompts = 0;
    final consent = ProviderConsentService(
      requestPermission: (_) async {
        prompts++;
        return true;
      },
    );
    await consent.ensure(
      AiProviderType.openai,
      dataType: 'text',
      purpose: 'summary',
    );
    final restarted = ProviderConsentService(
      requestPermission: (_) async {
        prompts++;
        return true;
      },
    );
    await restarted.ensure(
      AiProviderType.openai,
      dataType: 'text',
      purpose: 'summary',
    );
    expect(prompts, 1);
    expect(await restarted.hasGrant(AiProviderType.gemini), isFalse);

    await restarted.revoke(AiProviderType.openai);
    expect(restarted.canTransferNow(AiProviderType.openai), isFalse);
    expect(await restarted.hasGrant(AiProviderType.openai), isFalse);
  });

  test('withdrawal invalidates an approval dialog already open', () async {
    final decision = Completer<bool>();
    final consent = ProviderConsentService(
      requestPermission: (_) => decision.future,
    );
    final request = consent.ensure(
      AiProviderType.gemini,
      dataType: 'audio',
      purpose: 'transcription',
    );
    await Future<void>.delayed(Duration.zero);
    await consent.revoke(AiProviderType.gemini);
    decision.complete(true);
    await expectLater(request, throwsA(isA<AppException>()));
    expect(await consent.hasGrant(AiProviderType.gemini), isFalse);
    expect(consent.canTransferNow(AiProviderType.gemini), isFalse);
  });

  test('changing the Local AI destination requires renewed permission',
      () async {
    var prompts = 0;
    final consent = ProviderConsentService(
      requestPermission: (_) async {
        prompts++;
        return true;
      },
    );
    await consent.ensure(AiProviderType.localAi,
        dataType: 'text', purpose: 'summary', localEndpoint: 'https://a.test');
    expect(
      await consent.hasGrant(AiProviderType.localAi,
          localEndpoint: 'https://b.test'),
      isFalse,
    );
    await consent.ensure(AiProviderType.localAi,
        dataType: 'text', purpose: 'summary', localEndpoint: 'https://b.test');
    expect(prompts, 2);
  });
}

class _CountingProvider implements AiProvider {
  int calls = 0;

  @override
  Future<String> summarize(
      {required String apiKey,
      required String text,
      required String model,
      required String targetLanguageCode,
      String? summaryPrompt,
      String? reasoningEffort}) async {
    calls++;
    return 'summary';
  }

  @override
  Future<String> translate(
      {required String apiKey,
      required String text,
      required String targetLanguageCode,
      required String model,
      String? reasoningEffort}) async {
    calls++;
    return 'translation';
  }

  @override
  Future<String> transcribe(
      {required String apiKey,
      required String filePath,
      required String fileName,
      required String mimeType,
      required String model}) async {
    calls++;
    return 'transcript';
  }

  @override
  Future<Uint8List> generateImage(
      {required String apiKey,
      required String prompt,
      required String model}) async {
    calls++;
    return Uint8List(0);
  }
}
