import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Wraps the entire app on Web inside an iPhone-like chrome with
/// accurate proportions and safe-area paddings.
///
/// On non-web platforms, it simply returns the [child] unchanged.
class IPhoneWebShell extends StatelessWidget {
  final Widget child;
  const IPhoneWebShell({super.key, required this.child});

  // Logical points for iPhone 15/14/13 standard (not Pro Max): 390 x 844.
  static const double _deviceWidth = 390;
  static const double _deviceHeight = 844;
  // Safe areas (approx): top around the Dynamic Island/notch, bottom home indicator.
  static const double _safeTop = 47; // typical iPhone notch safe area ~44-59
  static const double _safeBottom = 34; // home indicator
  static const double _radius = 52; // visual corner radius of the device

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        // Scale the phone to fit inside the browser window while preserving aspect ratio.
        final scaleX = maxW / _deviceWidth;
        final scaleY = maxH / _deviceHeight;
        final scale = math.min(scaleX, scaleY);
        final viewW = _deviceWidth * scale;
        final viewH = _deviceHeight * scale;

        return DecoratedBox(
          decoration: const BoxDecoration(
            // Subtle background to visually separate device from page
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B0F1A), Color(0xFF141A2A)],
            ),
          ),
          child: Center(
            child: SizedBox(
              width: viewW,
              height: viewH,
              child: _IPhoneChrome(
                scale: scale,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IPhoneChrome extends StatelessWidget {
  final double scale;
  final Widget child;
  const _IPhoneChrome({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    // The chrome draws an outer device frame then scales the app to fit
    // and injects a MediaQuery with iPhone logical size and safe paddings.
    return ClipRRect(
      borderRadius: BorderRadius.circular(IPhoneWebShell._radius),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(IPhoneWebShell._radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 40,
              spreadRadius: 6,
            ),
          ],
          border: Border.all(color: Colors.black, width: 6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Inner screen area
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black,
                ),
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: IPhoneWebShell._deviceWidth,
                    height: IPhoneWebShell._deviceHeight,
                    child: _IPhoneSafeAreaHost(child: child),
                  ),
                ),
              ),
            ),
            // Top notch / dynamic island (decorative)
            Positioned(
              top: 8 * scale,
              child: _DynamicIsland(width: 120 * scale, height: 36 * scale),
            ),
            // Bottom home indicator (decorative)
            Positioned(
              bottom: 10 * scale,
              child: Container(
                width: 140 * scale,
                height: 5.0 * scale,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(3 * scale),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IPhoneSafeAreaHost extends StatelessWidget {
  final Widget child;
  const _IPhoneSafeAreaHost({required this.child});

  @override
  Widget build(BuildContext context) {
    // Inject a MediaQuery describing the iPhone logical size and safe padding
    final base = MediaQuery.maybeOf(context);
    final data = (base ?? const MediaQueryData()).copyWith(
      size: const Size(IPhoneWebShell._deviceWidth, IPhoneWebShell._deviceHeight),
      padding: const EdgeInsets.only(
        top: IPhoneWebShell._safeTop,
        bottom: IPhoneWebShell._safeBottom,
      ),
      viewPadding: const EdgeInsets.only(
        top: IPhoneWebShell._safeTop,
        bottom: IPhoneWebShell._safeBottom,
      ),
      // Match iPhone-ish pixel density to keep font sizes reasonable in browser
      devicePixelRatio: base?.devicePixelRatio ?? 3.0,
      textScaler: base?.textScaler ?? const TextScaler.linear(1.0),
    );

    return MediaQuery(
      data: data,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: SafeArea(
          // We keep SafeArea so the app content respects the simulated notch and home indicator
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DynamicIsland extends StatelessWidget {
  final double width;
  final double height;
  const _DynamicIsland({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            spreadRadius: 3,
          ),
        ],
        border: Border.all(color: Colors.black, width: 1),
      ),
    );
  }
}
