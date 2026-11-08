import 'dart:async';
import 'package:flutter/foundation.dart';

/// 睡眠定时器（对应 macOS 版 PlaybackCoordinator 的 sleepTimer 逻辑）。
class SleepTimer extends ChangeNotifier {
  Timer? _timer;
  Duration? _remaining;
  VoidCallback? _onTimeout;
  VoidCallback? _cancelTrackEnd;
  bool _atTrackEnd = false;
  bool get atTrackEnd => _atTrackEnd;

  Duration? get remaining => _remaining;
  bool get isActive => _remaining != null || _atTrackEnd;

  String get displayText {
    if (_atTrackEnd) return '本曲结束';
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
        final onTimeout = _onTimeout;
        stop();
        onTimeout?.call();
        return;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> startAtTrackEnd(
      {required Future<void> Function(VoidCallback?) configure}) async {
    stop();
    _atTrackEnd = true;
    _cancelTrackEnd = () => unawaited(configure(null));
    notifyListeners();
    await configure(() {
      _cancelTrackEnd = null;
      _atTrackEnd = false;
      notifyListeners();
    });
  }

  void stop() {
    final cancel = _cancelTrackEnd;
    _cancelTrackEnd = null;
    _atTrackEnd = false;
    cancel?.call();
    _timer?.cancel();
    _timer = null;
    _remaining = null;
    _onTimeout = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelTrackEnd?.call();
    super.dispose();
  }
}
