import "package:flutter/material.dart";
class MicButton extends StatelessWidget {
  final bool recording;
  final bool transcribing;
  final bool enabled;
  final bool isAnthropic;
  final double level; // smoothed 0..1 for gentle scaling/glow
  final double instantLevel; // raw 0..1 for flicker
  final VoidCallback onTap;
  const MicButton({
    required this.recording,
    required this.transcribing,
    required this.enabled,
    required this.level,
    required this.instantLevel,
    required this.onTap,
    this.isAnthropic = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;

    // Flicker-driven visual intensity
    final flickerIntensity = (recording && enabled && !isAnthropic) ? instantLevel : 0.0;

    // Base color and disabled appearance: grayed out for Claude or if generally disabled
    final bool effectivelyEnabled = enabled && !isAnthropic;
    final Color baseColor = effectivelyEnabled 
        ? (recording ? c.error : c.primary) 
        : c.surfaceContainerHighest.withValues(alpha: 0.5);

    // Faster glow changes for flicker, gentle base driven by smoothed "level"
    final double blur = (recording && effectivelyEnabled)
        ? (12.0 + 40.0 * (0.5 * level + 0.5 * flickerIntensity))
        : (isAnthropic ? 0.0 : 8.0);
    final double spread = (recording && effectivelyEnabled)
        ? (1.0 + 4.0 * (0.4 * level + 0.6 * flickerIntensity))
        : (isAnthropic ? 0.0 : 0.5);
    final glowColor = (recording && effectivelyEnabled)
        ? c.error.withValues(alpha: 0.40)
        : c.primary.withValues(alpha: 0.12);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration:
            const Duration(milliseconds: 64), // quick to emphasize flicker
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: baseColor,
          boxShadow: effectivelyEnabled 
            ? [BoxShadow(color: glowColor, blurRadius: blur, spreadRadius: spread)]
            : null,
          border: effectivelyEnabled
              ? null
              : Border.all(color: c.outline.withValues(alpha: 0.2), width: 1),
        ),
        child: Stack(alignment: Alignment.center, children: [
          // Subtle highlight that shimmers with instantaneous level
          if (recording && effectivelyEnabled)
            IgnorePointer(
              ignoring: true,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 64),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.10 * flickerIntensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          if (transcribing)
            const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3))
          else ...[
            Icon(Icons.mic_rounded,
                color: effectivelyEnabled
                    ? (recording ? c.onError : c.onPrimary)
                    : c.onSurfaceVariant.withValues(alpha: 0.38),
                size: 32),
          ],
        ]),
      ),
    );
  }
}

class PlayPauseButton extends StatelessWidget {
  final bool isLoading;
  final bool isPlaying;
  final bool isAnthropic;
  final VoidCallback onPressed;
  const PlayPauseButton({
    required this.isLoading,
    required this.isPlaying,
    required this.onPressed,
    this.isAnthropic = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final double size = isAnthropic ? 32 : 44;
    final Color buttonColor = isAnthropic ? Colors.red.withValues(alpha: 0.1) : c.secondary;
    final Color iconColor = isAnthropic ? Colors.red : c.onSecondary;

    return Material(
      color: buttonColor,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                        ),
                      )
                    : Icon(
                        isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: iconColor,
                        size: isAnthropic ? 20 : 24,
                      ),
                if (isAnthropic)
                  const Icon(
                    Icons.block,
                    color: Colors.red,
                    size: 28,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StopButton extends StatelessWidget {
  final bool enabled;
  final bool isAnthropic;
  final VoidCallback onPressed;
  const StopButton({
    required this.enabled,
    required this.onPressed,
    this.isAnthropic = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final double size = isAnthropic ? 32 : 44;
    final Color buttonColor = isAnthropic ? Colors.red.withValues(alpha: 0.1) : c.secondary;
    final Color iconColor = isAnthropic ? Colors.red : c.onSecondary;

    return Opacity(
      opacity: enabled ? 1.0 : 0.6,
      child: Material(
        color: buttonColor,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.stop_rounded,
                    color: iconColor,
                    size: isAnthropic ? 20 : 24,
                  ),
                  if (isAnthropic)
                    const Icon(
                      Icons.block,
                      color: Colors.red,
                      size: 28,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FileLimitPill extends StatelessWidget {
  final ValueNotifier<Duration> durationNotifier;
  final Duration maxDuration;
  const FileLimitPill({super.key, required this.durationNotifier, required this.maxDuration});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: durationNotifier,
      builder: (context, duration, child) {
        final s = duration.inSeconds;
        final m = s ~/ 60;
        final r = s % 60;
        final str = "${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}";

        final ms = maxDuration.inSeconds;
        final mm = ms ~/ 60;
        final mr = ms % 60;
        final maxStr = "${mm.toString().padLeft(2, '0')}:${mr.toString().padLeft(2, '0')}";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "$str / $maxStr",
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
