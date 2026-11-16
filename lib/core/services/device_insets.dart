import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// 原生侧报告的顶部安全区高度（逻辑像素）。
///
/// 存在的原因：`targetSdk` 已经进入 Android 15+ 的强制 edge-to-edge 区间，
/// 窗口必然铺满整屏，内容避让完全依赖 insets。少数国产 ROM 不会把
/// `displayCutout` 的 inset 透传给 Flutter，`MediaQuery.padding.top` 只剩状态栏
/// 高度，`SafeArea` 让出的空间不够，屏幕正中的挖孔就会压住居中标题。
///
/// 这里只做「补足」不做「覆盖」：只有原生值大于 Flutter 给出的值时才会生效，
/// 正常设备上两者一致，行为与改动前完全相同。
class DeviceInsets {
  DeviceInsets._();

  static const MethodChannel _channel =
      MethodChannel('com.music.player/insets');

  /// 0 表示未取到，此时完全沿用 Flutter 自身的 insets。
  static final ValueNotifier<double> top = ValueNotifier<double>(0);

  static bool _observing = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(_MetricsObserver());
    }
    await refresh();
  }

  /// 屏幕旋转、系统栏显隐、分屏切换后重新取值。
  static Future<void> refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final value = await _channel.invokeMethod<num>('getSafeAreaTop');
      final next = (value ?? 0).toDouble();
      if (next != top.value) top.value = next;
    } catch (_) {
      // 通道不可用（例如 media browser 宿主没有 Activity）时保持 0。
    }
  }
}

class _MetricsObserver extends WidgetsBindingObserver {
  @override
  void didChangeMetrics() {
    DeviceInsets.refresh();
  }
}
