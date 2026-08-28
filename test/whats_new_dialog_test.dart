import 'package:echoscribe/config/whats_new.dart';
import 'package:echoscribe/widgets/whats_new_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome dialog shows compact bullets and Got it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showLaunchOverlayDialog(
                  context: context,
                  title: WhatsNewCopy.welcomeTitle,
                  bullets: WhatsNewCopy.welcomeBullets,
                  buttonLabel: WhatsNewCopy.welcomeButton,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Echo Scribe'), findsOneWidget);
    expect(find.text('Your API key, your data.'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    for (final bullet in WhatsNewCopy.welcomeBullets) {
      expect(bullet.contains('\n'), isFalse);
    }
  });

  testWidgets('whats new dialog shows three single-line bullets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showLaunchOverlayDialog(
                  context: context,
                  title: WhatsNewCopy.whatsNewTitle,
                  bullets: WhatsNewCopy.whatsNewBullets,
                  buttonLabel: WhatsNewCopy.whatsNewButton,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(WhatsNewCopy.whatsNewBullets, hasLength(3));
    for (final bullet in WhatsNewCopy.whatsNewBullets) {
      expect(bullet.contains('\n'), isFalse);
      expect(find.text(bullet), findsOneWidget);
    }
  });
}
