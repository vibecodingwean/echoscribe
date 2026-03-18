import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LightModeColors {
  // Neo palette: electric indigo, violet, and slate neutrals
  static const lightPrimary = Color(0xFF5B5BD6);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFE7E7FF);
  static const lightOnPrimaryContainer = Color(0xFF17174A);
  static const lightSecondary = Color(0xFF6C7A90);
  static const lightOnSecondary = Color(0xFFFFFFFF);
  static const lightTertiary = Color(0xFFBB86FC);
  static const lightOnTertiary = Color(0xFF2B1E40);
  static const lightError = Color(0xFFB00020);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFFE5E7);
  static const lightOnErrorContainer = Color(0xFF410002);
  static const lightInversePrimary = Color(0xFFC7C7FF);
  static const lightSurface = Color(0xFFF7F8FA);
  static const lightOnSurface = Color(0xFF16181D);
  static const lightAppBarBackground = Color(0xFFEDEFFF);
}

class DarkModeColors {
  static const darkPrimary = Color(0xFFB7B7FF);
  static const darkOnPrimary = Color(0xFF18183B);
  static const darkPrimaryContainer = Color(0xFF2E2E7A);
  static const darkOnPrimaryContainer = Color(0xFFEDEFFF);
  static const darkSecondary = Color(0xFF8B98AD);
  static const darkOnSecondary = Color(0xFF111318);
  static const darkTertiary = Color(0xFFD4B9FF);
  static const darkOnTertiary = Color(0xFF231735);
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF93000A);
  static const darkOnErrorContainer = Color(0xFFFFDAD6);
  static const darkInversePrimary = Color(0xFF5B5BD6);
  static const darkSurface = Color(0xFF0F1116);
  static const darkOnSurface = Color(0xFFE6E8EE);
  static const darkAppBarBackground = Color(0xFF1A1E2D);
}

class Spacing { static const xxs = 4.0; static const xs = 8.0; static const sm = 12.0; static const md = 16.0; static const lg = 24.0; static const xl = 32.0; static const xxl = 48.0; }
class Radii { static const sm = 8.0; static const md = 12.0; static const lg = 20.0; static const pill = 999.0; }

class FontSizes {
  static const double displayLarge = 56.0;
  static const double displayMedium = 44.0;
  static const double displaySmall = 36.0;
  static const double headlineLarge = 32.0;
  static const double headlineMedium = 24.0;
  static const double headlineSmall = 22.0;
  static const double titleLarge = 22.0;
  static const double titleMedium = 18.0;
  static const double titleSmall = 16.0;
  static const double labelLarge = 16.0;
  static const double labelMedium = 14.0;
  static const double labelSmall = 12.0;
  static const double bodyLarge = 16.0;
  static const double bodyMedium = 14.0;
  static const double bodySmall = 12.0;
}

const _fontFamilyFallback = <String>[
  'Noto Sans',
  'Noto Sans Symbols 2',
  'Noto Sans JP',
  'Noto Sans KR',
  'Noto Sans SC',
  'Noto Sans TC',
  'Noto Sans Arabic',
  'Noto Sans Hebrew',
  'Noto Sans Devanagari',
  'Noto Sans Thai',
  'Noto Sans Bengali',
  'Noto Color Emoji',
  'emoji',
  'sans-serif',
];

TextStyle _interStyle({
  required double size,
  required FontWeight weight,
  required double height,
}) {
  // Supply extensive fallbacks so transcripts in non-Latin scripts render without CanvasKit warnings.
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    height: height,
  ).copyWith(
    fontFamilyFallback: _fontFamilyFallback,
  );
}

ThemeData get lightTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.light(
    primary: LightModeColors.lightPrimary,
    onPrimary: LightModeColors.lightOnPrimary,
    primaryContainer: LightModeColors.lightPrimaryContainer,
    onPrimaryContainer: LightModeColors.lightOnPrimaryContainer,
    secondary: LightModeColors.lightSecondary,
    onSecondary: LightModeColors.lightOnSecondary,
    tertiary: LightModeColors.lightTertiary,
    onTertiary: LightModeColors.lightOnTertiary,
    error: LightModeColors.lightError,
    onError: LightModeColors.lightOnError,
    errorContainer: LightModeColors.lightErrorContainer,
    onErrorContainer: LightModeColors.lightOnErrorContainer,
    inversePrimary: LightModeColors.lightInversePrimary,
    surface: LightModeColors.lightSurface,
    onSurface: LightModeColors.lightOnSurface,
  ),
  brightness: Brightness.light,
  appBarTheme: AppBarTheme(backgroundColor: LightModeColors.lightAppBarBackground, foregroundColor: LightModeColors.lightOnPrimaryContainer, elevation: 0),
  cardTheme: CardThemeData(color: LightModeColors.lightSurface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg))),
  dialogTheme: DialogThemeData(backgroundColor: LightModeColors.lightSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
  tabBarTheme: const TabBarThemeData(labelPadding: EdgeInsets.symmetric(horizontal: 20)),
  textTheme: TextTheme(
    displayLarge: _interStyle(size: FontSizes.displayLarge, weight: FontWeight.w600, height: 1.1),
    displayMedium: _interStyle(size: FontSizes.displayMedium, weight: FontWeight.w600, height: 1.1),
    displaySmall: _interStyle(size: FontSizes.displaySmall, weight: FontWeight.w600, height: 1.1),
    headlineLarge: _interStyle(size: FontSizes.headlineLarge, weight: FontWeight.w600, height: 1.2),
    headlineMedium: _interStyle(size: FontSizes.headlineMedium, weight: FontWeight.w600, height: 1.2),
    headlineSmall: _interStyle(size: FontSizes.headlineSmall, weight: FontWeight.w600, height: 1.2),
    titleLarge: _interStyle(size: FontSizes.titleLarge, weight: FontWeight.w600, height: 1.25),
    titleMedium: _interStyle(size: FontSizes.titleMedium, weight: FontWeight.w600, height: 1.3),
    titleSmall: _interStyle(size: FontSizes.titleSmall, weight: FontWeight.w600, height: 1.3),
    labelLarge: _interStyle(size: FontSizes.labelLarge, weight: FontWeight.w600, height: 1.2),
    labelMedium: _interStyle(size: FontSizes.labelMedium, weight: FontWeight.w600, height: 1.2),
    labelSmall: _interStyle(size: FontSizes.labelSmall, weight: FontWeight.w600, height: 1.2),
    bodyLarge: _interStyle(size: FontSizes.bodyLarge, weight: FontWeight.w400, height: 1.45),
    bodyMedium: _interStyle(size: FontSizes.bodyMedium, weight: FontWeight.w400, height: 1.5),
    bodySmall: _interStyle(size: FontSizes.bodySmall, weight: FontWeight.w400, height: 1.45),
  ),
);

ThemeData get darkTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: DarkModeColors.darkPrimary,
    onPrimary: DarkModeColors.darkOnPrimary,
    primaryContainer: DarkModeColors.darkPrimaryContainer,
    onPrimaryContainer: DarkModeColors.darkOnPrimaryContainer,
    secondary: DarkModeColors.darkSecondary,
    onSecondary: DarkModeColors.darkOnSecondary,
    tertiary: DarkModeColors.darkTertiary,
    onTertiary: DarkModeColors.darkOnTertiary,
    error: DarkModeColors.darkError,
    onError: DarkModeColors.darkOnError,
    errorContainer: DarkModeColors.darkErrorContainer,
    onErrorContainer: DarkModeColors.darkOnErrorContainer,
    inversePrimary: DarkModeColors.darkInversePrimary,
    surface: DarkModeColors.darkSurface,
    onSurface: DarkModeColors.darkOnSurface,
  ),
  brightness: Brightness.dark,
  appBarTheme: AppBarTheme(backgroundColor: DarkModeColors.darkAppBarBackground, foregroundColor: DarkModeColors.darkOnPrimaryContainer, elevation: 0),
  cardTheme: CardThemeData(color: DarkModeColors.darkSurface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg))),
  dialogTheme: DialogThemeData(backgroundColor: DarkModeColors.darkSurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md))),
  tabBarTheme: const TabBarThemeData(labelPadding: EdgeInsets.symmetric(horizontal: 20)),
  textTheme: TextTheme(
    displayLarge: _interStyle(size: FontSizes.displayLarge, weight: FontWeight.w600, height: 1.1),
    displayMedium: _interStyle(size: FontSizes.displayMedium, weight: FontWeight.w600, height: 1.1),
    displaySmall: _interStyle(size: FontSizes.displaySmall, weight: FontWeight.w600, height: 1.1),
    headlineLarge: _interStyle(size: FontSizes.headlineLarge, weight: FontWeight.w600, height: 1.2),
    headlineMedium: _interStyle(size: FontSizes.headlineMedium, weight: FontWeight.w600, height: 1.2),
    headlineSmall: _interStyle(size: FontSizes.headlineSmall, weight: FontWeight.w600, height: 1.2),
    titleLarge: _interStyle(size: FontSizes.titleLarge, weight: FontWeight.w600, height: 1.25),
    titleMedium: _interStyle(size: FontSizes.titleMedium, weight: FontWeight.w600, height: 1.3),
    titleSmall: _interStyle(size: FontSizes.titleSmall, weight: FontWeight.w600, height: 1.3),
    labelLarge: _interStyle(size: FontSizes.labelLarge, weight: FontWeight.w600, height: 1.2),
    labelMedium: _interStyle(size: FontSizes.labelMedium, weight: FontWeight.w600, height: 1.2),
    labelSmall: _interStyle(size: FontSizes.labelSmall, weight: FontWeight.w600, height: 1.2),
    bodyLarge: _interStyle(size: FontSizes.bodyLarge, weight: FontWeight.w400, height: 1.45),
    bodyMedium: _interStyle(size: FontSizes.bodyMedium, weight: FontWeight.w400, height: 1.5),
    bodySmall: _interStyle(size: FontSizes.bodySmall, weight: FontWeight.w400, height: 1.45),
  ),
);

class AppMarkdownStyle {
  /// Central Markdown styling for the app.
  /// [scaleFactor] enables larger font sizes for FullScreen (default 1.0).
  static MarkdownStyleSheet of(BuildContext context, {double scaleFactor = 1.0}) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge;
    return MarkdownStyleSheet(
      p: base?.copyWith(fontSize: (base.fontSize ?? 16) * scaleFactor, height: 1.6),
      h1: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, height: 1.5),
      h2: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, height: 1.4),
      h3: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
      h4: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.hintColor,
        height: 1.5,
        letterSpacing: 0.5,
      ),
      listBullet: base?.copyWith(height: 1.6),
      blockquote: base?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 4)),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.only(topRight: Radius.circular(4), bottomRight: Radius.circular(4)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }
}

