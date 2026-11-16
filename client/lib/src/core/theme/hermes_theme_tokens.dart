import 'package:material_ui/material_ui.dart';

enum HermesThemeId {
  crimson('crimson', 'Crimson'),
  midnight('midnight', 'Midnight'),
  forest('forest', 'Forest'),
  amethyst('amethyst', 'Amethyst'),
  amber('amber', 'Amber'),
  graphite('graphite', 'Graphite');

  const HermesThemeId(this.id, this.label);

  final String id;
  final String label;

  static HermesThemeId fromId(String? value) {
    return HermesThemeId.values.firstWhere(
      (item) => item.id == value,
      orElse: () => HermesThemeId.crimson,
    );
  }
}

/// Legacy preset enum retained for backward compatibility with older call sites.
enum SurfacePreset {
  obsidianGlow('obsidian_glow', 'Obsidian'),
  oledBlack('oled_black', 'Pure Black (OLED)'),
  slate('slate', 'Slate');

  const SurfacePreset(this.id, this.label);

  final String id;
  final String label;
}

/// Legacy accent enum retained for backward compatibility with older call sites.
enum HermesAccentKind {
  crimson('crimson', 'Crimson'),
  violet('violet', 'Amethyst'),
  amber('amber', 'Amber'),
  emerald('emerald', 'Forest'),
  cyan('cyan', 'Midnight'),
  dynamicAlbumArt('dynamic', 'Dynamic Album Art');

  const HermesAccentKind(this.id, this.label);

  final String id;
  final String label;
}

class _HermesPalette {
  const _HermesPalette({
    required this.bg,
    required this.bgSunken,
    required this.bgRail,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentHover,
    required this.accentInk,
  });

  final Color bg;
  final Color bgSunken;
  final Color bgRail;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentHover;
  final Color accentInk;
}

const Map<HermesThemeId, _HermesPalette> _v4Palettes = {
  HermesThemeId.crimson: _HermesPalette(
    bg: Color(0xFF130A0C),
    bgSunken: Color(0xFF0B0506),
    bgRail: Color(0xFF0F0708),
    surface: Color(0xFF1C1012),
    surface2: Color(0xFF27171A),
    surface3: Color(0xFF331E22),
    text: Color(0xFFF6EEEF),
    text2: Color(0xFFB9A2A6),
    text3: Color(0xFF806A6E),
    accent: Color(0xFFDC143C),
    accentHover: Color(0xFFEF2D52),
    accentInk: Color(0xFFFFFFFF),
  ),
  HermesThemeId.midnight: _HermesPalette(
    bg: Color(0xFF0B0E15),
    bgSunken: Color(0xFF06080D),
    bgRail: Color(0xFF080A10),
    surface: Color(0xFF131826),
    surface2: Color(0xFF1B2233),
    surface3: Color(0xFF252D42),
    text: Color(0xFFEEF1F7),
    text2: Color(0xFF9AA3B8),
    text3: Color(0xFF687189),
    accent: Color(0xFF5B8CFF),
    accentHover: Color(0xFF7AA2FF),
    accentInk: Color(0xFFFFFFFF),
  ),
  HermesThemeId.forest: _HermesPalette(
    bg: Color(0xFF0A110D),
    bgSunken: Color(0xFF050A07),
    bgRail: Color(0xFF070D09),
    surface: Color(0xFF111C16),
    surface2: Color(0xFF18271F),
    surface3: Color(0xFF213429),
    text: Color(0xFFEDF5F0),
    text2: Color(0xFF98ADA0),
    text3: Color(0xFF66796D),
    accent: Color(0xFF3DD68C),
    accentHover: Color(0xFF62E3A4),
    accentInk: Color(0xFF04140B),
  ),
  HermesThemeId.amethyst: _HermesPalette(
    bg: Color(0xFF100C16),
    bgSunken: Color(0xFF08060C),
    bgRail: Color(0xFF0C0911),
    surface: Color(0xFF1A1424),
    surface2: Color(0xFF241C31),
    surface3: Color(0xFF2F253F),
    text: Color(0xFFF2EEF8),
    text2: Color(0xFFA99FB9),
    text3: Color(0xFF756C86),
    accent: Color(0xFFA678FF),
    accentHover: Color(0xFFBA95FF),
    accentInk: Color(0xFFFFFFFF),
  ),
  HermesThemeId.amber: _HermesPalette(
    bg: Color(0xFF120E09),
    bgSunken: Color(0xFF0A0705),
    bgRail: Color(0xFF0E0B07),
    surface: Color(0xFF1D1710),
    surface2: Color(0xFF282016),
    surface3: Color(0xFF342A1D),
    text: Color(0xFFF7F1E8),
    text2: Color(0xFFB7A891),
    text3: Color(0xFF82745F),
    accent: Color(0xFFF2A93B),
    accentHover: Color(0xFFF7BC5F),
    accentInk: Color(0xFF1A1004),
  ),
  HermesThemeId.graphite: _HermesPalette(
    bg: Color(0xFF0F0F10),
    bgSunken: Color(0xFF080809),
    bgRail: Color(0xFF0B0B0C),
    surface: Color(0xFF18181A),
    surface2: Color(0xFF222225),
    surface3: Color(0xFF2D2D31),
    text: Color(0xFFF2F2F3),
    text2: Color(0xFFA1A1A6),
    text3: Color(0xFF6D6D72),
    accent: Color(0xFFF2F2F3),
    accentHover: Color(0xFFFFFFFF),
    accentInk: Color(0xFF0F0F10),
  ),
};

@immutable
class HermesThemeTokens {
  const HermesThemeTokens({
    required this.themeId,
    required this.pureBlack,
    required this.bg,
    required this.bgSunken,
    required this.bgRail,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.accentHover,
    required this.accentInk,
    required this.line,
    required this.lineSoft,
    this.titleTint,
    this.surfacePreset = SurfacePreset.obsidianGlow,
    this.accentKind = HermesAccentKind.crimson,
  });

  final HermesThemeId themeId;
  final bool pureBlack;
  final Color bg;
  final Color bgSunken;
  final Color bgRail;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color text;
  final Color text2;
  final Color text3;
  final Color accent;
  final Color accentHover;
  final Color accentInk;
  final Color line;
  final Color lineSoft;
  final Color? titleTint;

  // Legacy properties preserved so untouched features continue compiling cleanly.
  final SurfacePreset surfacePreset;
  final HermesAccentKind accentKind;

  Color get bgPrimary => bg;
  Color get bgElevated => surface;
  Color get bgGlass => surface.withValues(alpha: 0.72);
  Color get surfaceBorder => line;
  Color get textPrimary => text;
  Color get textSecondary => text2;
  Color get accentPrimary => accent;
  Color get subtitleSafeColor => const Color(0xFFD8D8D8);

  /// Light ambient wash matching Figma v4 `#view-cinema` and `#view-cinema-detail`.
  Color get pageWash =>
      titleTint == null ? bg : Color.lerp(bg, titleTint!, 0.09)!;

  static HermesThemeId _themeFromLegacyAccent(HermesAccentKind kind) {
    return switch (kind) {
      HermesAccentKind.crimson => HermesThemeId.crimson,
      HermesAccentKind.cyan => HermesThemeId.midnight,
      HermesAccentKind.emerald => HermesThemeId.forest,
      HermesAccentKind.violet => HermesThemeId.amethyst,
      HermesAccentKind.amber => HermesThemeId.amber,
      HermesAccentKind.dynamicAlbumArt => HermesThemeId.crimson,
    };
  }

  static HermesAccentKind _legacyAccentFromTheme(HermesThemeId id) {
    return switch (id) {
      HermesThemeId.crimson => HermesAccentKind.crimson,
      HermesThemeId.midnight => HermesAccentKind.cyan,
      HermesThemeId.forest => HermesAccentKind.emerald,
      HermesThemeId.amethyst => HermesAccentKind.violet,
      HermesThemeId.amber => HermesAccentKind.amber,
      HermesThemeId.graphite => HermesAccentKind.crimson,
    };
  }

  factory HermesThemeTokens.resolve({
    HermesThemeId? themeId,
    bool pureBlack = false,
    SurfacePreset surfacePreset = SurfacePreset.obsidianGlow,
    HermesAccentKind accentKind = HermesAccentKind.crimson,
    Color? albumArtAccent,
    Color? dynamicSourceColor,
  }) {
    final resolvedId = themeId ?? _themeFromLegacyAccent(accentKind);
    final effectivePureBlack = pureBlack || surfacePreset == SurfacePreset.oledBlack;
    final palette = _v4Palettes[resolvedId]!;

    final bg = effectivePureBlack ? const Color(0xFF000000) : palette.bg;
    final bgSunken =
        effectivePureBlack ? const Color(0xFF000000) : palette.bgSunken;
    final bgRail =
        effectivePureBlack ? const Color(0xFF000000) : palette.bgRail;

    Color accent = palette.accent;
    Color accentHover = palette.accentHover;
    Color accentInk = palette.accentInk;

    final effectiveDynamicColor = albumArtAccent ?? dynamicSourceColor;
    if (accentKind == HermesAccentKind.dynamicAlbumArt &&
        effectiveDynamicColor != null) {
      accent = _clampDynamicAccent(effectiveDynamicColor, bg);
      accentHover = Color.lerp(accent, const Color(0xFFFFFFFF), 0.16)!;
      accentInk = wcagContrastRatio(accent, const Color(0xFF08080A)) >=
              wcagContrastRatio(accent, const Color(0xFFFFFFFF))
          ? const Color(0xFF08080A)
          : const Color(0xFFFFFFFF);
    }

    return HermesThemeTokens(
      themeId: resolvedId,
      pureBlack: effectivePureBlack,
      bg: bg,
      bgSunken: bgSunken,
      bgRail: bgRail,
      surface: palette.surface,
      surface2: palette.surface2,
      surface3: palette.surface3,
      text: palette.text,
      text2: palette.text2,
      text3: palette.text3,
      accent: accent,
      accentHover: accentHover,
      accentInk: accentInk,
      line: const Color(0x14FFFFFF),
      lineSoft: const Color(0x0DFFFFFF),
      surfacePreset: effectivePureBlack ? SurfacePreset.oledBlack : surfacePreset,
      accentKind: themeId == null ? accentKind : _legacyAccentFromTheme(resolvedId),
    );
  }

  /// Applies a title or album artwork tint locally (and optionally overrides the accent).
  HermesThemeTokens withTitleTint(
    Color tint, {
    Color? tintInk,
    bool overrideAccent = true,
  }) {
    if (!overrideAccent) {
      return copyWith(titleTint: tint);
    }

    final safeAccent = _clampDynamicAccent(tint, bg);
    final safeHover = Color.lerp(safeAccent, const Color(0xFFFFFFFF), 0.16)!;
    final resolvedInk = tintInk ??
        (wcagContrastRatio(safeAccent, const Color(0xFF08080A)) >=
                wcagContrastRatio(safeAccent, const Color(0xFFFFFFFF))
            ? const Color(0xFF08080A)
            : const Color(0xFFFFFFFF));

    return copyWith(
      titleTint: tint,
      accent: safeAccent,
      accentHover: safeHover,
      accentInk: resolvedInk,
    );
  }

  HermesThemeTokens copyWith({
    HermesThemeId? themeId,
    bool? pureBlack,
    Color? bg,
    Color? bgSunken,
    Color? bgRail,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? text,
    Color? text2,
    Color? text3,
    Color? accent,
    Color? accentHover,
    Color? accentInk,
    Color? line,
    Color? lineSoft,
    Color? titleTint,
    bool clearTitleTint = false,
    SurfacePreset? surfacePreset,
    HermesAccentKind? accentKind,
  }) {
    return HermesThemeTokens(
      themeId: themeId ?? this.themeId,
      pureBlack: pureBlack ?? this.pureBlack,
      bg: bg ?? this.bg,
      bgSunken: bgSunken ?? this.bgSunken,
      bgRail: bgRail ?? this.bgRail,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      accent: accent ?? this.accent,
      accentHover: accentHover ?? this.accentHover,
      accentInk: accentInk ?? this.accentInk,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      titleTint: clearTitleTint ? null : (titleTint ?? this.titleTint),
      surfacePreset: surfacePreset ?? this.surfacePreset,
      accentKind: accentKind ?? this.accentKind,
    );
  }

  static HermesThemeTokens of(BuildContext context) {
    final extension = Theme.of(context).extension<HermesThemeExtension>();
    return extension?.tokens ?? HermesThemeTokens.resolve();
  }

  static double wcagContrastRatio(Color a, Color b) {
    final l1 = a.computeLuminance();
    final l2 = b.computeLuminance();
    final brightest = l1 > l2 ? l1 : l2;
    final darkest = l1 > l2 ? l2 : l1;
    return (brightest + 0.05) / (darkest + 0.05);
  }

  static Color _clampDynamicAccent(Color rawAccent, Color background) {
    if (wcagContrastRatio(rawAccent, background) >= 4.5) {
      return rawAccent;
    }

    var candidate = HSLColor.fromColor(rawAccent);
    for (var i = 0; i < 16; i++) {
      candidate = candidate.withLightness(
        (candidate.lightness + 0.05).clamp(0.45, 0.85),
      );
      final color = candidate.toColor();
      if (wcagContrastRatio(color, background) >= 4.5) {
        return color;
      }
    }
    return candidate.toColor();
  }

  ThemeData toThemeData() {
    final colorScheme = ColorScheme.dark(
      primary: accent,
      onPrimary: accentInk,
      secondary: accentHover,
      onSecondary: accentInk,
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: bgSunken,
      surfaceContainerLow: bgRail,
      surfaceContainer: surface,
      surfaceContainerHigh: surface2,
      surfaceContainerHighest: surface3,
      outline: line,
      outlineVariant: lineSoft,
      error: const Color(0xFFFF6B7D),
      onError: const Color(0xFF1B0407),
    );

    const baseTextStyle = TextStyle(fontFamily: 'Figtree');

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Figtree',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      textTheme: TextTheme(
        displaySmall: baseTextStyle.copyWith(
          color: text,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.64,
        ),
        headlineMedium: baseTextStyle.copyWith(
          color: text,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.56,
        ),
        headlineSmall: baseTextStyle.copyWith(
          color: text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.44,
        ),
        titleLarge: baseTextStyle.copyWith(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: baseTextStyle.copyWith(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: baseTextStyle.copyWith(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: baseTextStyle.copyWith(
          color: text2,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        bodySmall: baseTextStyle.copyWith(
          color: text2,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: baseTextStyle.copyWith(
          color: text,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: baseTextStyle.copyWith(
          color: text2,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: baseTextStyle.copyWith(
          color: text3,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: line,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: TextStyle(color: text3, fontSize: 14),
        labelStyle: TextStyle(color: text2, fontSize: 13, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentInk,
          textStyle: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: line),
          textStyle: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: text2,
          textStyle: const TextStyle(
            fontFamily: 'Figtree',
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accentInk;
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return text3;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      extensions: [
        HermesThemeExtension(tokens: this),
      ],
    );
  }
}

@immutable
class HermesThemeExtension extends ThemeExtension<HermesThemeExtension> {
  const HermesThemeExtension({required this.tokens});

  final HermesThemeTokens tokens;

  @override
  HermesThemeExtension copyWith({HermesThemeTokens? tokens}) {
    return HermesThemeExtension(tokens: tokens ?? this.tokens);
  }

  @override
  HermesThemeExtension lerp(
    covariant ThemeExtension<HermesThemeExtension>? other,
    double t,
  ) {
    if (other is! HermesThemeExtension) return this;
    return t < 0.5 ? this : other;
  }
}
