import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 统一的应用动画配置
///
/// 提供一致的动画曲线和持续时间，确保整个应用的交互体验连贯流畅
class AppAnimations {
  // 动画曲线
  /// 页面切换动画曲线（快出慢入，更自然）
  static const Curve pageTransition = Curves.fastOutSlowIn;

  /// 列表项动画曲线
  static const Curve listItem = Curves.easeOut;

  /// 播放器动画曲线
  static const Curve player = Curves.easeInOutCubic;

  /// 弹性动画曲线（用于强调）
  static const Curve elastic = Curves.elasticOut;

  /// 标准缓动曲线
  static const Curve standard = Curves.easeInOut;

  // 持续时间
  /// 快速动画（按钮按下、小组件切换）
  static const Duration fast = Motion.fast;

  /// 标准动画（大多数交互）
  static const Duration normal = Motion.normal;

  /// 慢速动画（页面切换、复杂过渡）
  static const Duration slow = Motion.slow;

  /// 超慢动画（特殊场景）
  static const Duration verySlow = Duration(milliseconds: 600);

  /// 自适应动画持续时间
  ///
  /// 根据系统设置自动调整：
  /// - reducedMotion = true：返回零持续时间（无动画）
  /// - 否则返回原始持续时间
  static Duration adaptive(Duration base, {bool reducedMotion = false}) {
    if (reducedMotion) return Duration.zero;
    return base;
  }

  /// 根据上下文自适应动画持续时间
  ///
  /// 自动检测系统的"减弱动态效果"设置
  static Duration adaptiveContext(BuildContext context, Duration base) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return adaptive(base, reducedMotion: reducedMotion);
  }
}
