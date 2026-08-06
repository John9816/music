import 'package:flutter/material.dart';

/// ============================================================
/// 大厂级设计令牌（Design Tokens）
/// 参考 Apple Music / Spotify / 原 Android 项目的设计语言：
/// - 暗色主题：纯黑背景 + 分层灰面 + 高对比文字
/// - 明亮主题：iOS 分组灰底 + 白色表面
/// - 强调色：品牌红 #FF2D55（与 Android 版 brand_primary 一致）
/// - 文字层级：Apple 语义（#F5F5F7 / #A1A1A6 / #6E6E73）
/// ============================================================

// ---- 品牌色（全主题共享）----
class AppBrand {
  AppBrand._();

  /// 品牌红：Apple Music 红
  static const Color red = Color(0xFF2FD365);

  /// 品牌红渐变终点
  static const Color redDeep = Color(0xFF20B950);

  /// 收藏红心
  static const Color favoriteRed = Color(0xFF2FD365);

  /// iOS 系统绿（语音/在线状态）
  static const Color systemGreen = Color(0xFF34C759);

  /// 品牌渐变（按钮、进度、高亮）
  static LinearGradient gradient(Color seed,
      {AlignmentGeometry begin = Alignment.topLeft,
      AlignmentGeometry end = Alignment.bottomRight}) {
    return LinearGradient(
      colors: [seed, seed.withValues(alpha: 0.72)],
      begin: begin,
      end: end,
    );
  }
}

// ---- 暗色主题令牌 ----
class DarkPalette {
  DarkPalette._();

  static const Color background = Color(0xFF000000);
  static const Color surface = Color(0xFF111113);
  static const Color surfaceRaised = Color(0xFF1B1B1E);
  static const Color surfaceHigh = Color(0xFF2C2C2E);
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFA1A1A6);
  static const Color textTertiary = Color(0xFF6E6E73);
  static const Color hairline = Color(0x1FFFFFFF); // 12%
  static const Color hairlineStrong = Color(0x33FFFFFF); // 20%
  static const Color glass = Color(0x0FFFFFFF); // 6%
  static const Color glassStrong = Color(0x1FFFFFFF); // 12%
  static const Color shadow = Color(0x66000000);
}

// ---- 明亮主题令牌 ----
class LightPalette {
  LightPalette._();

  static const Color background = Color(0xFFF2F2F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceRaised = Color(0xFFF7F7FA);
  static const Color surfaceHigh = Color(0xFFEBEBF0);
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textTertiary = Color(0xFF98989D);
  static const Color hairline = Color(0x143C3C43); // 8%
  static const Color hairlineStrong = Color(0x263C3C43); // 15%
  static const Color glass = Color(0x0A000000); // 4%
  static const Color glassStrong = Color(0x14000000); // 8%
  static const Color shadow = Color(0x143C3C43);
}

// ---- 字体尺度 ----
class TypeScale {
  TypeScale._();

  static const double caption = 11;
  static const double small = 12;
  static const double body = 13;
  static const double bodyLarge = 14;
  static const double subhead = 16;
  static const double title = 18;
  static const double section = 22;
  static const double pageTitle = 28;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight heavy = FontWeight.w800;
}

// ---- 间距尺度（4pt 网格）----
class Space {
  Space._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

// ---- 圆角尺度 ----
class RadiusToken {
  RadiusToken._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;
}

// ---- 阴影令牌 ----
class ShadowToken {
  ShadowToken._();

  static List<BoxShadow> card(BuildContext context,
      {double radius = 18, double opacity = 0.24}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? Colors.black : Colors.black.withValues(alpha: 0.16);
    return [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: radius,
        offset: Offset(0, radius * 0.42),
      ),
    ];
  }

  static List<BoxShadow> cover(BuildContext context, {double radius = 22}) =>
      card(context, radius: radius, opacity: 0.32);
}

// ---- 动效令牌 ----
class Motion {
  Motion._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
}

/// 兼容旧常量（历史代码仍引用 kSpace / kRadius / kFont）
const double kSpaceXs = Space.xs;
const double kSpaceSm = Space.sm;
const double kSpaceMd = Space.md;
const double kSpaceLg = Space.lg;
const double kSpaceXl = Space.xl;

const double kRadiusSm = RadiusToken.sm;
const double kRadiusMd = RadiusToken.md;
const double kRadiusLg = RadiusToken.lg;
const double kRadiusXl = RadiusToken.xl;

const double kFontCaption = TypeScale.caption;
const double kFontSmall = TypeScale.small;
const double kFontBody = TypeScale.bodyLarge;
const double kFontSubhead = TypeScale.subhead;
const double kFontTitle = TypeScale.title;
const double kFontSection = TypeScale.section;
const double kFontPageTitle = TypeScale.pageTitle;
