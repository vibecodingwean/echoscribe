enum LaunchOverlayKind { none, welcome, whatsNew }

LaunchOverlayKind decideLaunchOverlay({
  required bool welcomeSeen,
  required int lastWhatsNewVersionCode,
  required int currentVersionCode,
  required bool hasInitialShare,
}) {
  if (hasInitialShare) return LaunchOverlayKind.none;
  if (!welcomeSeen) return LaunchOverlayKind.welcome;
  if (currentVersionCode > lastWhatsNewVersionCode) {
    return LaunchOverlayKind.whatsNew;
  }
  return LaunchOverlayKind.none;
}
