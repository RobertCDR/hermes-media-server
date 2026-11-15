import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

enum SurfacePreset {
  obsidianGlow('Obsidian Glow'),
  oledBlack('OLED Black'),
  slate('Slate');

  const SurfacePreset(this.label);
  final String label;
}

enum HermesAccentKind {
  crimson('Crimson'),
  violet('Violet'),
  emerald('Emerald'),
  amber('Amber'),
  cyan('Cyan'),
  dynamicAlbumArt('Dynamic Album Art');

  const HermesAccentKind(this.label);
  final String label;
}

class HermesThemeExtension extends ThemeExtension<HermesThemeExtension> {
  const HermesThemeExtension({required this.tokens});

  final HermesThemeTokens tokens;

  @override
  ThemeExtension<HermesThemeExtension> copyWith({HermesThemeTokens? tokens}) {
    return HermesThemeExtension(tokens: tokens ?? this.tokens);
  }

  @override
  ThemeExtension<HermesThemeExtension> lerp(
    covariant ThemeExtension<HermesThemeExtension>? other,
    double t,
  ) {
    if (other is! HermesThemeExtension) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}

class HermesThemeTokens {
  const HermesThemeTokens({
    required this.surfacePreset,
    required this.accentKind,
    required this.bgPrimary,
    required this.bgElevated,
    required this.bgGlass,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentPrimary,
    required this.accentHover,
    required this.subtitleSafeColor,
  });

  final SurfacePreset surfacePreset;
  final HermesAccentKind accentKind;
  final Color bgPrimary;
  final Color bgElevated;
  final Color bgGlass;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentPrimary;
  final Color accentHover;
  final Color subtitleSafeColor;

  static const Color defaultTextPrimary = Color(0xFFF3F4F6);
  static const Color defaultTextSecondary = Color(0xFF94A3B8);
  static const Color hdrSafeSubtitleGray = Color(0xFFD8D8D8);

  factory HermesThemeTokens.resolve({
    SurfacePreset surfacePreset = SurfacePreset.obsidianGlow,
    HermesAccentKind accentKind = HermesAccentKind.crimson,
    Color? dynamicSourceColor,
  }) {
    final (bgPrimary, bgElevated, bgGlass) = switch (surfacePreset) {
      SurfacePreset.obsidianGlow => (
        const Color(0xFF090B12),
        const Color(0xFF111522),
        const Color(0xBF161B2C),
      ),
      SurfacePreset.oledBlack => (
        const Color(0xFF000000),
        const Color(0xFF0B0D13),
        const Color(0xD911141F),
      ),
      SurfacePreset.slate => (
        const Color(0xFF0F172A),
        const Color(0xFF1E293B),
        const Color(0xCC1E293B),
      ),
    };

    final (accentPrimary, accentHover) = switch (accentKind) {
      HermesAccentKind.crimson => (
        const Color(0xFFE11D48),
        const Color(0xFFF43F5E),
      ),
      HermesAccentKind.violet => (
        const Color(0xFF7C3AED),
        const Color(0xFF8B5CF6),
      ),
      HermesAccentKind.emerald => (
        const Color(0xFF10B981),
        const Color(0xFF34D399),
      ),
      HermesAccentKind.amber => (
        const Color(0xFFF59E0B),
        const Color(0xFFFBBF24),
      ),
      HermesAccentKind.cyan => (
        const Color(0xFF06B6D4),
        const Color(0xFF22D3EE),
      ),
      HermesAccentKind.dynamicAlbumArt => _clampDynamicAccent(
        dynamicSourceColor ?? const Color(0xFFE11D48),
        bgPrimary,
      ),
    };

    return HermesThemeTokens(
      surfacePreset: surfacePreset,
      accentKind: accentKind,
      bgPrimary: bgPrimary,
      bgElevated: bgElevated,
      bgGlass: bgGlass,
      textPrimary: defaultTextPrimary,
      textSecondary: defaultTextSecondary,
      accentPrimary: accentPrimary,
      accentHover: accentHover,
      subtitleSafeColor: hdrSafeSubtitleGray,
    );
  }

  static HermesThemeTokens of(BuildContext context) {
    final ext = Theme.of(context).extension<HermesThemeExtension>();
    return ext?.tokens ?? HermesThemeTokens.resolve();
  }

  static double wcagContrastRatio(Color foreground, Color background) {
    final l1 = foreground.computeLuminance();
    final l2 = background.computeLuminance();
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static (Color, Color) _clampDynamicAccent(Color candidate, Color bgPrimary) {
    var hsl = HSLColor.fromColor(candidate);
    if (hsl.saturation < 0.35) {
      hsl = hsl.withSaturation(0.55);
    }

    while (wcagContrastRatio(hsl.toColor(), bgPrimary) < 4.5 && hsl.lightness < 0.78) {
      hsl = hsl.withLightness((hsl.lightness + 0.06).clamp(0.0, 0.78));
    }

    final primary = hsl.toColor();
    final hover = hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 0.86)).toColor();
    return (primary, hover);
  }

  ThemeData toThemeData() {
    final colorScheme = ColorScheme.dark(
      primary: accentPrimary,
      onPrimary: Colors.white,
      secondary: accentHover,
      onSecondary: Colors.white,
      surface: bgElevated,
      onSurface: textPrimary,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bgPrimary,
      cardColor: bgElevated,
      dividerColor: const Color(0x1FFFFFFF),
      appBarTheme: AppBarTheme(
        backgroundColor: bgPrimary,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: bgElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x1AFFFFFF)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x26FFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0x26FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentPrimary, width: 1.5),
        ),
      ),
      extensions: [HermesThemeExtension(tokens: this)],
    );
  }
}
