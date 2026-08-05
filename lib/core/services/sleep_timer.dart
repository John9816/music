import 'dart:async';
import 'package:flutter/foundation.dart';

/// 睡眠定时器（对应 macOS 版 PlaybackCoordinator 的 sleepTimer 逻辑）。
class SleepTimer extends ChangeNotifier {
  Timer? _timer;
  Duration? _remaining;
  VoidCallback? _onTimeout;

  Duration? get remaining => _remaining;
  bool get isActive => _remaining != null;

  String get displayText {
    if (_remaining == null) return '';
    final m = _remaining!.inMinutes;
    final s = _remaining!.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void start(Duration duration, {VoidCallback? onTimeout}) {
    stop();
    _remaining = duration;
    _onTimeout = onTimeout;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining == null) return;
      _remaining = _remaining! - const Duration(seconds: 1);
      if (_remaining!.inSeconds <= 0) {
        stop();
        _onTimeout?.call();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _remaining = null;
    _onTimeout = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
