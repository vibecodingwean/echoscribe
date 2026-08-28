import 'package:flutter/material.dart';

const String kLaunchOverlayRouteName = 'launchOverlay';

Future<bool> showLaunchOverlayDialog({
  required BuildContext context,
  required String title,
  required List<String> bullets,
  required String buttonLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: kLaunchOverlayRouteName),
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final bullet in bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(bullet)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(buttonLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
