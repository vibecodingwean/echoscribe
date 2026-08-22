import 'package:echoscribe/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('target language names cover the picker languages', () {
    expect(kTargetLanguageNames['en'], 'English');
    expect(kTargetLanguageNames['de'], 'German');
    expect(kTargetLanguageNames['zh'], 'Chinese (Simplified)');
    expect(targetLanguageName('ko'), 'Korean');
    expect(targetLanguageName('auto'), 'auto');
    expect(targetLanguageName('xx'), 'xx');
    expect(
      kTargetLanguageNames.keys.toList(),
      [
        'en',
        'zh',
        'hi',
        'es',
        'fr',
        'ar',
        'bn',
        'pt',
        'ru',
        'ur',
        'id',
        'de',
        'ja',
        'sw',
        'mr',
        'te',
        'tr',
        'ta',
        'vi',
        'ko',
      ],
    );
  });
}
