import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 拨杆落到系统后的铃音模式。
enum RingerMode { silent, vibrate, normal }

RingerMode? parseRingerMode(Object? value) => switch (value) {
      'silent' => RingerMode.silent,
      'vibrate' => RingerMode.vibrate,
      'normal' => RingerMode.normal,
      _ => null,
    };

/// 一加三段式拨杆的 Dart 侧接收器。
///
/// 原生只发标准 RINGER_MODE_CHANGED_ACTION，不读厂商私有接口；
/// 所有平台调用失败都静默降级，绝不打断播放。
class AlertSliderService {
  AlertSliderService({
    MethodChannel? channel,
    Future<String?> Function()? probe,
  })  : _channel = channel ?? const MethodChannel('com.music.player/alert_slider'),
        _probe = probe;

  static final AlertSliderService instance = AlertSliderService();

  final MethodChannel _channel;
  final Future<String?> Function()? _probe;
  final StreamController<RingerMode> _changes = StreamController.broadcast();

  bool _initialized = false;
  bool _listening = false;
  RingerMode _mode = RingerMode.normal;

  Stream<RingerMode> get changes => _changes.stream;
  RingerMode get mode => _mode;
  bool get listening => _listening;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handlePlatformCall);
    try {
      final current = await (_probe ?? _probePlatform)();
      final parsed = parseRingerMode(current);
      if (parsed != null) _mode = parsed;
    } catch (_) {
      // 平台不可用时保持 normal。
    }
  }

  Future<void> startListening() async {
    if (!_initialized) await initialize();
    if (_listening) return;
    try {
      await _channel.invokeMethod<void>('startListening');
      _listening = true;
    } catch (_) {
      _listening = false;
    }
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    try {
      await _channel.invokeMethod<void>('stopListening');
    } catch (_) {
      // 忽略：系统可能已经回收了接收器。
    }
    _listening = false;
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method != 'onRingerModeChanged') return;
    final parsed = parseRingerMode(call.arguments);
    if (parsed == null || parsed == _mode) return;
    _mode = parsed;
    if (!_changes.isClosed) _changes.add(parsed);
  }

  Future<String?> _probePlatform() async {
    if (kIsWeb) return null;
    try {
      return await _channel.invokeMethod<String>('current');
    } catch (_) {
      return null;
    }
  }
}
