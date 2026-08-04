import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/pages/settings_page.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.text('ElevenLabs (Live STT + TTS)'), findsOneWidget);
  });

  testWidgets('ElevenLabs key is only shown for the ElevenLabs provider',
      (tester) async {
    final openAi = SettingsState()..setProvider(AiProviderType.openai);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: openAi)),
    );
    await tester.pump();
    expect(find.text('ElevenLabs API Key (Live STT + TTS)'), findsNothing);

    final elevenLabs = SettingsState()..setProvider(AiProviderType.elevenLabs);
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settings: elevenLabs)),
    );
    await tester.pump();
    expect(
      find.text('ElevenLabs API Key (Live STT + TTS)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Live transcription and text-to-speech only.'),
      findsOneWidget,
    );
  });
}
