import 'package:echoscribe/services/launch_overlay_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('share launch never shows welcome or whats new', () {
    expect(
      decideLaunchOverlay(
        welcomeSeen: false,
        lastWhatsNewVersionCode: 0,
        currentVersionCode: 94,
        hasInitialShare: true,
      ),
      LaunchOverlayKind.none,
    );
    expect(
      decideLaunchOverlay(
        welcomeSeen: true,
        lastWhatsNewVersionCode: 0,
        currentVersionCode: 94,
        hasInitialShare: true,
      ),
      LaunchOverlayKind.none,
    );
  });

  test('first normal launch shows welcome and skips whats new', () {
    expect(
      decideLaunchOverlay(
        welcomeSeen: false,
        lastWhatsNewVersionCode: 0,
        currentVersionCode: 94,
        hasInitialShare: false,
      ),
      LaunchOverlayKind.welcome,
    );
  });

  test('after welcome a newer versionCode shows whats new once', () {
    expect(
      decideLaunchOverlay(
        welcomeSeen: true,
        lastWhatsNewVersionCode: 0,
        currentVersionCode: 94,
        hasInitialShare: false,
      ),
      LaunchOverlayKind.whatsNew,
    );
    expect(
      decideLaunchOverlay(
        welcomeSeen: true,
        lastWhatsNewVersionCode: 94,
        currentVersionCode: 94,
        hasInitialShare: false,
      ),
      LaunchOverlayKind.none,
    );
  });
}
