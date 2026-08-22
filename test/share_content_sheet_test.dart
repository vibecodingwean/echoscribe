import 'package:echoscribe/widgets/home/share_content_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('share options include audio and image only when present', () {
    expect(
      resolveShareContentOptions(
        hasText: true,
        hasAudio: false,
        hasImage: false,
      ).count,
      1,
    );
    expect(
      resolveShareContentOptions(
        hasText: true,
        hasAudio: true,
        hasImage: true,
      ).count,
      3,
    );
    expect(
      resolveShareContentOptions(
        hasText: false,
        hasAudio: false,
        hasImage: false,
      ).isEmpty,
      isTrue,
    );
  });

  test('audio extension follows mime type', () {
    expect(shareAudioExtension('audio/wav'), 'wav');
    expect(shareAudioExtension('audio/mpeg'), 'mp3');
  });
}
