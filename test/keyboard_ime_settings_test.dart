import 'package:echoscribe/models/enums.dart';
import 'package:echoscribe/services/keyboard_ime_service.dart';
import 'package:echoscribe/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Keyboard IME settings', () {
    test('defaults to google voiceMode and autocorrect enabled', () {
      final settings = SettingsState();

      expect(settings.voiceMode, 'google');
      expect(settings.autocorrectEnabled, isTrue);
      expect(settings.autoCapitalizeEnabled, isTrue);
      expect(settings.hapticFeedbackEnabled, isTrue);
      expect(settings.soundFeedbackEnabled, isTrue);
      expect(settings.opticalFeedbackEnabled, isTrue);
      expect(settings.keyboardLayout, 'qwertz');
      expect(settings.customTones, isEmpty);

      final payload = KeyboardImeService.buildConfigPayload(settings);
      expect(payload['voiceMode'], 'google');
      expect(payload['keyboardLayout'], 'qwertz');
      expect(payload['autocorrectEnabled'], isTrue);
      expect(payload['autoCapitalizeEnabled'], isTrue);
      expect(payload['hapticFeedbackEnabled'], isTrue);
      expect(payload['soundFeedbackEnabled'], isTrue);
      expect(payload['opticalFeedbackEnabled'], isTrue);
    });

    test('voiceMode setter roundtrips google and echoscribe', () {
      final settings = SettingsState()..setVoiceMode('echoscribe');
      expect(settings.voiceMode, 'echoscribe');

      settings.setVoiceMode('GOOGLE');
      expect(settings.voiceMode, 'google');

      settings.setVoiceMode('unknown');
      expect(settings.voiceMode, 'google');

      final payload = KeyboardImeService.buildConfigPayload(settings);
      expect(payload['voiceMode'], 'google');

      settings.setVoiceMode('echoscribe');
      expect(
        KeyboardImeService.buildConfigPayload(settings)['voiceMode'],
        'echoscribe',
      );
    });

    test('keyboard layout setter roundtrips qwerty and qwertz', () {
      final settings = SettingsState()..setKeyboardLayout('qwerty');
      expect(settings.keyboardLayout, 'qwerty');
      expect(
        KeyboardImeService.buildConfigPayload(settings)['keyboardLayout'],
        'qwerty',
      );

      settings.setKeyboardLayout('QWERTZ');
      expect(settings.keyboardLayout, 'qwertz');

      settings.setKeyboardLayout('unknown');
      expect(settings.keyboardLayout, 'qwertz');
    });

    test('startup layout uses stored value and never needs native status', () {
      expect(
        KeyboardImeService.resolveLayout('qwertz', languageCode: 'en'),
        'qwertz',
      );
    });

    test('getStatus completes without a native plugin', () async {
      final status = await KeyboardImeService.getStatus()
          .timeout(const Duration(seconds: 2));
      expect(status.imeEnabled, isFalse);
    });

    test('mergeCustomTones folds grammar and assistants into tones', () {
      final merged = KeyboardImeService.mergeCustomTones(
        tones: [
          {'name': 'Warm', 'prompt': 'Be warm'},
        ],
        grammar: [
          {'name': 'Bullets', 'instruction': 'Make bullets'},
          {'name': 'Warm', 'instruction': 'Duplicate name ignored'},
        ],
        assistants: [
          {'name': 'Coach', 'prompt': 'Be a coach'},
        ],
      );
      expect(merged, [
        {'name': 'Warm', 'prompt': 'Be warm'},
        {'name': 'Bullets', 'prompt': 'Make bullets'},
        {'name': 'Coach', 'prompt': 'Be a coach'},
      ]);
    });

    test('resolveLayout prefers stored layout then device language', () {
      expect(
        KeyboardImeService.resolveLayout('qwerty', languageCode: 'de'),
        'qwerty',
      );
      expect(
        KeyboardImeService.resolveLayout('', languageCode: 'de'),
        'qwertz',
      );
      expect(
        KeyboardImeService.resolveLayout(null, languageCode: 'en'),
        'qwerty',
      );
    });

    test('custom tones appear in buildConfigPayload', () {
      final settings = SettingsState()
        ..setProvider(AiProviderType.openai)
        ..setOpenAiKey('sk-test')
        ..setCustomTones([
          {'name': 'Formal', 'prompt': 'Write formally'},
        ])
        ..setAutocorrectEnabled(false)
        ..setAutoCapitalizeEnabled(false);

      final payload = KeyboardImeService.buildConfigPayload(settings);
      expect(payload['autocorrectEnabled'], isFalse);
      expect(payload['autoCapitalizeEnabled'], isFalse);
      expect(payload.containsKey('personalDictionary'), isFalse);
      expect(payload['customTones'], [
        {'name': 'Formal', 'prompt': 'Write formally'},
      ]);
    });

    test('keyboard payload omits floatingEnabled so hover toggle is preserved', () {
      final settings = SettingsState()
        ..setProvider(AiProviderType.openai)
        ..setOpenAiKey('sk-test')
        ..setFloatingDictationEnabled(false);

      final payload = KeyboardImeService.buildConfigPayload(settings);
      expect(payload.containsKey('floatingEnabled'), isFalse);
      expect(payload['enabled'], isTrue);
    });

    test('ElevenLabs still strips apiKey from keyboard payload', () {
      final settings = SettingsState()
        ..setProvider(AiProviderType.elevenLabs)
        ..setElevenLabsKey('secret-eleven-key')
        ..setVoiceMode('echoscribe')
        ..setCustomTones([
          {'name': 'Warm', 'prompt': 'Be warm'},
        ]);

      final payload = KeyboardImeService.buildConfigPayload(settings);

      expect(payload['supportsDictation'], isFalse);
      expect(payload['enabled'], isFalse);
      expect(payload['apiKey'], '');
      expect(payload['voiceMode'], 'echoscribe');
      expect(payload['customTones'], [
        {'name': 'Warm', 'prompt': 'Be warm'},
      ]);
    });
  });
}
