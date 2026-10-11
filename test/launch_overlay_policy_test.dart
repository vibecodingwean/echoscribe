import 'package:echoscribe/config/whats_new.dart';
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

  test('existing +115 through +121 users see +122 whats new once', () {
    expect(WhatsNewCopy.releaseVersionCode, 122);
    for (final (previousVersion, shared, expected) in [
      (115, false, LaunchOverlayKind.whatsNew),
      (117, false, LaunchOverlayKind.whatsNew),
      (117, true, LaunchOverlayKind.none),
      (118, false, LaunchOverlayKind.whatsNew),
      (119, false, LaunchOverlayKind.whatsNew),
      (120, false, LaunchOverlayKind.whatsNew),
      (121, false, LaunchOverlayKind.whatsNew),
      (122, false, LaunchOverlayKind.none),
    ]) {
      expect(
        decideLaunchOverlay(
          welcomeSeen: true,
          lastWhatsNewVersionCode: previousVersion,
          currentVersionCode: WhatsNewCopy.releaseVersionCode,
          hasInitialShare: shared,
        ),
        expected,
      );
    }
  });
}
