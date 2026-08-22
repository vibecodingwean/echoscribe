import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/pages/settings_page.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keyboardChannel = MethodChannel('com.echoscribe.app/keyboard_ime');
  const floatingChannel = MethodChannel('com.echoscribe.app/floating_dictation');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyboardChannel, (call) async {
      if (call.method == 'getStatus') {
        return <String, dynamic>{
          'isAndroid': false,
          'microphoneGranted': false,
          'imeEnabled': false,
          'voiceMode': 'google',
          'keyboardLayout': 'qwertz',
          'configReady': false,
          'provider': '',
        };
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(floatingChannel, (call) async {
      if (call.method == 'getStatus') {
        return <String, dynamic>{
          'isAndroid': false,
          'microphoneGranted': false,
          'overlayGranted': false,
          'accessibilityEnabled': false,
          'configReady': false,
          'enabled': true,
          'provider': '',
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(keyboardChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(floatingChannel, null);
  });

  testWidgets('provider selector exposes ElevenLabs as a first-class option',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProviderSelectorCard(
              selectedProvider: AiProviderType.openai,
              onProviderSelected: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Gemini'), findsOneWidget);
    expect(find.text('Claude (no-audio) 🦀'), findsOneWidget);
    expect(find.text('Grok'), findsOneWidget);
    expect(find.text('Local AI'), findsOneWidget);
    expect(find.text('ElevenLabs (STT + TTS)'), findsOneWidget);
  });

  testWidgets('ElevenLabs key is only shown for the ElevenLabs provider',
      (tester) async {
    final openAi = SettingsState()..setProvider(AiProviderType.openai);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: openAi)),
    );
    await tester.pump();
    expect(find.text('ElevenLabs API Key (STT + TTS)'), findsNothing);
    expect(find.text('TTS Voice ID'), findsNothing);

    final elevenLabs = SettingsState()..setProvider(AiProviderType.elevenLabs);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: elevenLabs)),
    );
    await tester.pump();
    expect(
      find.text('ElevenLabs API Key (STT + TTS)'),
      findsOneWidget,
    );
    expect(find.text('TTS Voice ID'), findsOneWidget);
    expect(find.text('Q0Co3mt4NHZCSmKqCMMo'), findsOneWidget);
    expect(find.text('Voice Library'), findsOneWidget);
    expect(find.text('Pro'), findsNothing);
    expect(find.text('Realtime'), findsOneWidget);
    expect(
      find.textContaining('Realtime uses Scribe v2 Realtime'),
      findsOneWidget,
    );
  });

  testWidgets('keyboard tab uses English labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: SettingsState())),
    );
    await tester.pump();

    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.text('Tastatur'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Keyboard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Enable keyboard'), findsOneWidget);
    expect(find.text('QWERTY English'), findsOneWidget);
    expect(find.text('QWERTZ Deutsch'), findsOneWidget);
    expect(find.text('Auto-capitalize'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(find.text('Custom tone'), findsOneWidget);
    expect(find.text('Personal dictionary'), findsNothing);
    expect(find.text('Custom grammar'), findsNothing);
    expect(find.text('Custom assistant'), findsNothing);
    expect(find.text('Custom assistants'), findsNothing);
    expect(find.text('Tastatur aktivieren'), findsNothing);
    expect(find.text('Automatisch großschreiben'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
}
