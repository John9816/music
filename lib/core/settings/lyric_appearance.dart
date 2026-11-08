import 'package:flutter/material.dart';

const minLyricFontSize = 20;
const maxLyricFontSize = 40;
const defaultLyricFontSize = 28;

/// These presets use the system font, including its CJK fallback. They need no
/// downloaded fonts, and the same metrics are used for layout and word masks.
enum LyricFontStyle {
  standard('标准', '清晰、均衡', FontWeight.w500, 0),
  soft('柔和', '轻盈、舒展', FontWeight.w300, 0.4),
  bold('粗体', '醒目、有力量', FontWeight.w700, -0.3);

  const LyricFontStyle(this.label, this.description, this.weight, this.spacing);

  final String label;
  final String description;
  final FontWeight weight;
  final double spacing;

  static LyricFontStyle fromStored(Object? value) => values.firstWhere(
        (style) => style.name == value,
        orElse: () => bold,
      );
}

int normalizeLyricFontSize(Object? value) => value is int
    ? ((value.clamp(minLyricFontSize, maxLyricFontSize) / 2).round() * 2)
    : defaultLyricFontSize;

TextStyle lyricTextStyle(
  TextStyle base, {
  required int fontSize,
  required LyricFontStyle fontStyle,
  double scale = 1,
}) =>
    base.copyWith(
      fontSize: fontSize * scale,
      fontWeight: fontStyle.weight,
      letterSpacing: fontStyle.spacing,
      height: 1.38,
    );
