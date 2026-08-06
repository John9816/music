import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 应用主题：与 Android 原版同源的 Apple Music 风格配色。
///
/// - dark（默认）：纯黑背景 + 白色强调（Apple Music 暗色模式）
/// - light：iOS 分组灰底 + 品牌红
/// - sunset / ocean / graphite：三套暗色个性主题
class AppTheme {
  const AppTheme({
    required this.id,
    required this.name,
    required this.dark,
    required this.scheme,
  });

  final String id;
  final String name;
  final bool dark;
  final ColorScheme scheme;

  /// 兼容旧调用方（seedColor 仅作占位，实际配色见 [scheme]）
  Color get seedColor => scheme.primary;

  ThemeData get data => _build(scheme, dark);

  static const List<AppTheme> all = [
    AppTheme(
      id: 'dark',
      name: '暗黑',
      dark: true,
      scheme: _darkScheme,
    ),
    AppTheme(
      id: 'light',
      name: '明亮',
      dark: false,
      scheme: _lightScheme,
    ),
    AppTheme(
      id: 'sunset',
      name: '日落',
      dark: true,
      scheme: _sunsetScheme,
    ),
    AppTheme(
      id: 'ocean',
      name: '海洋',
      dark: true,
      scheme: _oceanScheme,
    ),
    AppTheme(
      id: 'graphite',
      name: '石墨',
      dark: true,
      scheme: _graphiteScheme,
    ),
  ];

  static AppTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => all[0]);

  /// 主题色与深浅模式分开保存。这里用同一套中性色表面，
  /// 仅替换强调色，避免切换主题色时意外强制进入深色模式。
  static AppTheme forAccent(String accentId, {required bool dark}) {
    final accent = AppAccent.byId(accentId);
    final base = dark ? _darkScheme : _lightScheme;
    final scheme = base.copyWith(
      primary: accent.color,
      primaryContainer: dark
          ? Color.alphaBlend(
              accent.color.withValues(alpha: 0.30),
              const Color(0xFF1A1A1D),
            )
          : accent.color.withValues(alpha: 0.14),
      onPrimaryContainer: dark ? Colors.white : const Color(0xFF1C1C1E),
      inversePrimary: accent.color,
    );
    return AppTheme(
      id: '${accent.id}-${dark ? 'dark' : 'light'}',
      name: accent.name,
      dark: dark,
      scheme: scheme,
    );
  }

  // ---------------------------------------------------------------
  // 主题配色（与 Android 版 Theme.MusicPlayer.* 对齐）
  // ---------------------------------------------------------------

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF2FD365),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF204D31),
    onPrimaryContainer: Color(0xFFE8FFF0),
    secondary: Color(0xFFAAB8AE),
    onSecondary: Color(0xFF102018),
    secondaryContainer: Color(0xFF263D30),
    onSecondaryContainer: Color(0xFFF5F5F7),
    tertiary: Color(0xFFA2ADA5),
    onTertiary: Colors.black,
    tertiaryContainer: Color(0xFF2C4033),
    onTertiaryContainer: Color(0xFFEBEBF0),
    error: Color(0xFFFF453A),
    onError: Colors.white,
    errorContainer: Color(0x33FF453A),
    onErrorContainer: Color(0xFFFFD6D6),
    surface: Color(0xFF102319),
    onSurface: Color(0xFFF3F7F4),
    surfaceContainerLowest: Color(0xFF0D2116),
    surfaceContainerLow: Color(0xFF13271C),
    surfaceContainer: Color(0xFF192E22),
    surfaceContainerHigh: Color(0xFF21372A),
    surfaceContainerHighest: Color(0xFF2D4235),
    onSurfaceVariant: Color(0xFF929A95),
    outline: Color(0xFF768078),
    outlineVariant: Color(0x2EE7F7EC),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,
    inversePrimary: Color(0xFF2FD365),
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFFF2D55),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFE5EC),
    onPrimaryContainer: Color(0xFF7A0018),
    secondary: Color(0xFF34C759),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD9FBE3),
    onSecondaryContainer: Color(0xFF0B3D1B),
    tertiary: Color(0xFF6E6E73),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFEBEBF0),
    onTertiaryContainer: Color(0xFF3A3A3C),
    error: Color(0xFFFF3B30),
    onError: Colors.white,
    errorContainer: Color(0x33FF3B30),
    onErrorContainer: Color(0xFF7A0018),
    surface: Colors.white,
    onSurface: Color(0xFF1C1C1E),
    surfaceContainerLowest: Color(0xFFF2F2F7),
    surfaceContainerLow: Color(0xFFF2F2F7),
    surfaceContainer: Color(0xFFF7F7FA),
    surfaceContainerHigh: Color(0xFFEBEBF0),
    surfaceContainerHighest: Color(0xFFE1E1E6),
    onSurfaceVariant: Color(0xFF6E6E73),
    outline: Color(0xFF98989D),
    outlineVariant: Color(0x263C3C43),
    shadow: Color(0x143C3C43),
    scrim: Colors.black,
    inverseSurface: Color(0xFF1C1C1E),
    onInverseSurface: Color(0xFFF5F5F7),
    inversePrimary: Color(0xFFFF2D55),
  );

  static const ColorScheme _sunsetScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFFF756C),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF643A3A),
    onPrimaryContainer: Color(0xFFFFD6D1),
    secondary: Color(0xFF34DCA2),
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF2A5144),
    onSecondaryContainer: Color(0xFFC9F5E3),
    tertiary: Color(0xFFB9ADB0),
    onTertiary: Colors.black,
    tertiaryContainer: Color(0xFF3A3336),
    onTertiaryContainer: Color(0xFFF0E2E5),
    error: Color(0xFFFF8C83),
    onError: Colors.black,
    errorContainer: Color(0x33FF8C83),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF171B22),
    onSurface: Color(0xFFF8F0F0),
    surfaceContainerLowest: Color(0xFF101217),
    surfaceContainerLow: Color(0xFF171B22),
    surfaceContainer: Color(0xFF202630),
    surfaceContainerHigh: Color(0xFF2C3540),
    surfaceContainerHighest: Color(0xFF3A4550),
    onSurfaceVariant: Color(0xFFB9ADB0),
    outline: Color(0xFF9C9093),
    outlineVariant: Color(0x30FFFFFF),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFF8F0F0),
    onInverseSurface: Color(0xFF101217),
    inversePrimary: Color(0xFFFF756C),
  );

  static const ColorScheme _oceanScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF59CDEB),
    onPrimary: Colors.black,
    primaryContainer: Color(0xFF123B48),
    onPrimaryContainer: Color(0xFFD0F5FF),
    secondary: Color(0xFF58E2B9),
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF14463B),
    onSecondaryContainer: Color(0xFFC9F8E8),
    tertiary: Color(0xFFAAC4CC),
    onTertiary: Colors.black,
    tertiaryContainer: Color(0xFF2A3F47),
    onTertiaryContainer: Color(0xFFE3F4F8),
    error: Color(0xFFFF8A8A),
    onError: Colors.black,
    errorContainer: Color(0x33FF8A8A),
    onErrorContainer: Color(0xFFFFDADA),
    surface: Color(0xFF0F1B21),
    onSurface: Color(0xFFE8F7FB),
    surfaceContainerLowest: Color(0xFF09141A),
    surfaceContainerLow: Color(0xFF0F1B21),
    surfaceContainer: Color(0xFF172833),
    surfaceContainerHigh: Color(0xFF213541),
    surfaceContainerHighest: Color(0xFF2C424F),
    onSurfaceVariant: Color(0xFFAAC4CC),
    outline: Color(0xFF8CA6AE),
    outlineVariant: Color(0x30E6FFFF),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFE8F7FB),
    onInverseSurface: Color(0xFF09141A),
    inversePrimary: Color(0xFF59CDEB),
  );

  static const ColorScheme _graphiteScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFC3F26A),
    onPrimary: Colors.black,
    primaryContainer: Color(0xFF334010),
    onPrimaryContainer: Color(0xFFECFFC0),
    secondary: Color(0xFF63EAD2),
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF18483E),
    onSecondaryContainer: Color(0xFFCBFBEF),
    tertiary: Color(0xFFB4BBA8),
    onTertiary: Colors.black,
    tertiaryContainer: Color(0xFF33382E),
    onTertiaryContainer: Color(0xFFEEF2E6),
    error: Color(0xFFFF9A8D),
    onError: Colors.black,
    errorContainer: Color(0x33FF9A8D),
    onErrorContainer: Color(0xFFFFE0DC),
    surface: Color(0xFF151813),
    onSurface: Color(0xFFF5F8EE),
    surfaceContainerLowest: Color(0xFF0D100C),
    surfaceContainerLow: Color(0xFF151813),
    surfaceContainer: Color(0xFF20251B),
    surfaceContainerHigh: Color(0xFF2C3327),
    surfaceContainerHighest: Color(0xFF394134),
    onSurfaceVariant: Color(0xFFB4BBA8),
    outline: Color(0xFF99A08C),
    outlineVariant: Color(0x33F2FFCB),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFF5F8EE),
    onInverseSurface: Color(0xFF0D100C),
    inversePrimary: Color(0xFFC3F26A),
  );

  static ThemeData _build(ColorScheme scheme, bool dark) {
    final Color hairline = dark ? DarkPalette.hairline : LightPalette.hairline;
    final Color hairlineStrong =
        dark ? DarkPalette.hairlineStrong : LightPalette.hairlineStrong;
    final Color glassFillColor = dark ? DarkPalette.glass : LightPalette.glass;
    final Color background = scheme.surfaceContainerLowest;

    final textTheme = _textTheme(scheme);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: TypeScale.semibold,
          letterSpacing: 0,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shadowColor: scheme.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RadiusToken.lg),
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        labelType: NavigationRailLabelType.none,
        groupAlignment: -1,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: TypeScale.semibold,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: TypeScale.medium,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? scheme.surfaceContainerHigh : const Color(0xE6FFFFFF),
        contentTextStyle: TextStyle(
          fontSize: 13,
          color: dark ? Colors.white : const Color(0xFF1C1C1E),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: hairline),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:
            dark ? scheme.surfaceContainerLow : const Color(0xF2FFFFFF),
        modalBackgroundColor:
            dark ? scheme.surfaceContainerLow : const Color(0xF2FFFFFF),
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(RadiusToken.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dark ? scheme.surfaceContainer : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: hairline),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: TypeScale.semibold,
          color: scheme.onSurface,
        ),
        contentTextStyle:
            TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? scheme.surfaceContainer : const Color(0xFFF2F2F7),
        hintStyle: TextStyle(fontSize: 14, color: scheme.outline),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: glassFillColor,
        circularTrackColor: glassFillColor,
      ),
      iconTheme: IconThemeData(color: scheme.onSurface),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SlideFadeTransitionsBuilder(),
          TargetPlatform.iOS: cupertino.CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: _SlideFadeTransitionsBuilder(),
          TargetPlatform.windows: _SlideFadeTransitionsBuilder(),
          TargetPlatform.linux: _SlideFadeTransitionsBuilder(),
        },
      ),
      extensions: [
        GlassTokens(
          fill: glassFillColor,
          fillStrong: dark ? DarkPalette.glassStrong : LightPalette.glassStrong,
          hairline: hairline,
          hairlineStrong: hairlineStrong,
          surfaceRaised:
              dark ? const Color(0xFF1C1C1E) : const Color(0xFFF7F7FA),
        ),
      ],
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    const Color primary = Color(0xFFF5F5F7);
    const Color secondary = Color(0xFFA1A1A6);
    const Color lightPrimary = Color(0xFF1C1C1E);
    const Color lightSecondary = Color(0xFF6E6E73);
    final bool dark = scheme.brightness == Brightness.dark;
    final onSurface = dark ? primary : lightPrimary;
    final onSurfaceVariant = dark ? secondary : lightSecondary;
    TextStyle base(Color c, double size, FontWeight w, {double tracking = 0}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          color: c,
          letterSpacing: tracking,
          height: 1.25,
        );
    return TextTheme(
      displayLarge: base(onSurface, 34, TypeScale.heavy),
      displayMedium: base(onSurface, 30, TypeScale.bold),
      displaySmall: base(onSurface, 26, TypeScale.bold),
      headlineLarge: base(onSurface, 24, TypeScale.bold),
      headlineMedium: base(onSurface, 20, TypeScale.bold),
      headlineSmall: base(onSurface, 18, TypeScale.semibold),
      titleLarge: base(onSurface, 17, TypeScale.semibold),
      titleMedium: base(onSurface, 16, TypeScale.semibold),
      titleSmall: base(onSurface, 14, TypeScale.semibold),
      bodyLarge: base(onSurface, 15, TypeScale.regular),
      bodyMedium: base(onSurface, 14, TypeScale.regular),
      bodySmall: base(onSurfaceVariant, 12, TypeScale.regular),
      labelLarge: base(onSurface, 14, TypeScale.semibold),
      labelMedium: base(onSurfaceVariant, 12, TypeScale.medium),
      labelSmall: base(onSurfaceVariant, 11, TypeScale.medium),
    );
  }
}

class AppAccent {
  const AppAccent(this.id, this.name, this.color);

  final String id;
  final String name;
  final Color color;

  static const all = <AppAccent>[
    AppAccent('rhythmRed', '律动红', Color(0xFFFF375F)),
    AppAccent('sunsetOrange', '落日橙', Color(0xFFFF9F0A)),
    AppAccent('forestGreen', '森林绿', Color(0xFF30D158)),
    AppAccent('lakeCyan', '湖水青', Color(0xFF40C8E0)),
    AppAccent('skyBlue', '天际蓝', Color(0xFF0A84FF)),
    AppAccent('nightPurple', '幻夜紫', Color(0xFFBF5AF2)),
    AppAccent('rosePink', '蔷薇粉', Color(0xFFFF6482)),
  ];

  static AppAccent byId(String id) =>
      all.firstWhere((accent) => accent.id == id, orElse: () => all[2]);
}

/// 毛玻璃/细线令牌（通过 ThemeExtension 全局取用）
class GlassTokens extends ThemeExtension<GlassTokens> {
  const GlassTokens({
    required this.fill,
    required this.fillStrong,
    required this.hairline,
    required this.hairlineStrong,
    required this.surfaceRaised,
  });

  final Color fill;
  final Color fillStrong;
  final Color hairline;
  final Color hairlineStrong;
  final Color surfaceRaised;

  @override
  GlassTokens copyWith({
    Color? fill,
    Color? fillStrong,
    Color? hairline,
    Color? hairlineStrong,
    Color? surfaceRaised,
  }) {
    return GlassTokens(
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    );
  }

  @override
  GlassTokens lerp(GlassTokens? other, double t) {
    if (other == null) return this;
    return GlassTokens(
      fill: Color.lerp(fill, other.fill, t)!,
      fillStrong: Color.lerp(fillStrong, other.fillStrong, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
    );
  }
}

extension GlassTheme on BuildContext {
  GlassTokens get glass => Theme.of(this).extension<GlassTokens>()!;
}

/// 页面转场：轻微上浮 + 淡入（原生大厂应用常见的"推入"动效）
class _SlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideFadeTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
