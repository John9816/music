import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// vivo OriginOS 原子岛的本地驱动。
///
/// 原生侧用 `notification.superx.*` extras 发一条普通通知，在支持原子岛的
/// ROM 上会被渲染成挖孔周围的胶囊；其他品牌 / ROM 上它只是一条静默通知，
/// 因此这里必须先用 [available] 判断，避免在非 vivo 设备上打扰用户。
class OriginIslandService {
  OriginIslandService({MethodChannel? channel, Future<bool> Function()? probe})
      : _channel =
            channel ?? const MethodChannel('com.music.player/origin_island'),
        _probe = probe ?? _probePlatform;

  static final OriginIslandService instance = OriginIslandService();

  final MethodChannel _channel;
  final Future<bool> Function() _probe;

  bool _available = false;
  bool _initialized = false;
  String? _lastSignature;
  DateTime? _lastPost;

  /// 距上次刷新至少间隔这么久，避免进度每 1% 都重发一条通知。
  static const Duration _minInterval = Duration(seconds: 2);

  /// 是否值得尝试向原子岛推送。初始化完成后才准确。
  bool get available => _available;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _available = await _probe();
    } catch (_) {
      _available = false;
    }
  }

  /// 测试用：直接注入可用性，跳过平台探测。
  void initializeForTesting(bool available) {
    _initialized = true;
    _available = available;
  }

  /// 推送当前播放进度。相同进度在 [_minInterval] 内会被节流掉。
  ///
  /// [progressMs]/[durationMs] 为毫秒；[accentColor] 为 ARGB int。
  /// 返回是否真正发出（false 表示节流跳过、不可用或原生报错）。
  Future<bool> show({
    required String title,
    String? subText,
    String? content,
    required bool playing,
    required int progressMs,
    required int durationMs,
    int? accentColor,
  }) async {
    if (!_available) return false;
    final percent =
        durationMs > 0 ? (progressMs * 100 ~/ durationMs).clamp(0, 100) : 0;
    final signature = [
      title,
      subText ?? '',
      content ?? '',
      playing ? '1' : '0',
      // 播放中用百分比即可；暂停态进度变化没意义，固定签名避免频繁刷新。
      playing ? percent.toString() : 'paused',
    ].join('\u001f');

    final now = DateTime.now();
    final last = _lastPost;
    if (signature == _lastSignature &&
        last != null &&
        now.difference(last) < _minInterval) {
      return false;
    }

    final args = <String, Object?>{
      'title': title,
      'subText': subText,
      'content': content ?? '',
      'playing': playing,
      'progress': progressMs,
      'progressMax': durationMs,
      'accentColor': accentColor,
      'rightText': playing ? null : '已暂停',
    };
    try {
      final ok = await _channel.invokeMethod<bool>('show', args) ?? false;
      if (ok) {
        _lastSignature = signature;
        _lastPost = now;
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// 收起胶囊。切歌、停止、清空队列或关闭开关时调用。
  Future<void> hide() async {
    _lastSignature = null;
    _lastPost = null;
    if (!_available) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } catch (_) {}
  }

  static Future<bool> _probePlatform() async {
    if (kIsWeb) return false;
    try {
      return await instance._channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }
}
