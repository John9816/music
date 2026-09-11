import 'package:flutter/scheduler.dart';
import 'dart:developer' as developer;

/// 性能监控工具
///
/// 用于检测掉帧和性能问题，仅在调试模式下使用
class PerformanceMonitor {
  static bool _enabled = false;
  static final List<Duration> _frameTimes = [];
  static int _droppedFrames = 0;

  /// 启用性能监控
  static void enable() {
    if (_enabled) return;
    _enabled = true;
    SchedulerBinding.instance.addTimingsCallback(_onFrame);
    developer.log('Performance monitor enabled', name: 'Performance');
  }

  /// 禁用性能监控
  static void disable() {
    if (!_enabled) return;
    _enabled = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFrame);
    developer.log('Performance monitor disabled', name: 'Performance');
  }

  static void _onFrame(List<FrameTiming> timings) {
    if (!_enabled) return;

    for (final timing in timings) {
      final frameTime = timing.totalSpan;
      _frameTimes.add(frameTime);

      // 检测掉帧（>16.67ms = 60fps）
      if (frameTime.inMicroseconds > 16670) {
        _droppedFrames++;
        developer.log(
          'Frame dropped: ${frameTime.inMilliseconds}ms',
          name: 'Performance',
        );
      }
    }

    // 保持最近 100 帧
    if (_frameTimes.length > 100) {
      _frameTimes.removeAt(0);
    }
  }

  /// 获取平均 FPS
  static double get averageFps {
    if (_frameTimes.isEmpty) return 0;
    final avgMicros = _frameTimes
            .map((d) => d.inMicroseconds)
            .reduce((a, b) => a + b) /
        _frameTimes.length;
    return 1000000 / avgMicros;
  }

  /// 获取掉帧数
  static int get droppedFrames => _droppedFrames;

  /// 重置统计
  static void reset() {
    _frameTimes.clear();
    _droppedFrames = 0;
  }

  /// 获取性能报告
  static Map<String, dynamic> getReport() {
    return {
      'enabled': _enabled,
      'averageFps': averageFps.toStringAsFixed(2),
      'droppedFrames': _droppedFrames,
      'totalFrames': _frameTimes.length,
      'dropRate': _frameTimes.isEmpty
          ? '0%'
          : '${(_droppedFrames / _frameTimes.length * 100).toStringAsFixed(2)}%',
    };
  }
}
