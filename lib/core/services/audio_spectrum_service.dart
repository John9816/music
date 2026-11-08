import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum AudioSpectrumStatus {
  idle,
  starting,
  active,
  permissionRequired,
  unavailable
}

/// Reads the current Android playback session's FFT; never records microphone
/// audio. Only a user action should call [start] with requestPermission: true.
class AudioSpectrumService extends ChangeNotifier with WidgetsBindingObserver {
  AudioSpectrumService({MethodChannel? channel, EventChannel? eventChannel})
      : _channel = channel ?? const MethodChannel('duckmusic/audio_spectrum'),
        _eventChannel = eventChannel ??
            const EventChannel('duckmusic/audio_spectrum/frames') {
    WidgetsBinding.instance.addObserver(this);
  }

  static const bandCount = 32;
  static int _nextRequestId = 0;
  final MethodChannel _channel;
  final EventChannel _eventChannel;
  late final MethodChannel _frameControl = MethodChannel(
      _eventChannel.name, _eventChannel.codec, _eventChannel.binaryMessenger);
  final _frames = StreamController<List<double>>.broadcast();
  Future<void> _frameCancellation = Future<void>.value();
  bool _listening = false;
  AudioSpectrumStatus _status = AudioSpectrumStatus.idle;
  String _message = '';
  int _requestId = 0;
  bool _disposed = false;

  AudioSpectrumStatus get status => _status;
  String get message => _message;
  Stream<List<double>> get frames => _frames.stream;

  Future<bool> start(int sessionId, {bool requestPermission = false}) async {
    if (_disposed) return false;
    final requestId = _requestId = ++_nextRequestId;
    if (sessionId <= 0) {
      _setStatus(AudioSpectrumStatus.unavailable, '当前音频会话尚未就绪');
      _clearFrame();
      await _detachFrames();
      await _stopNative(requestId);
      return false;
    }
    _setStatus(AudioSpectrumStatus.starting, '正在连接音频频谱');
    try {
      // Activity recreation preserves the Flutter engine but replaces the
      // native EventSink. Rebind each capture after its old cancel completes;
      // a late cancel must never release the replacement Visualizer.
      await _detachFrames();
      if (_disposed || requestId != _requestId) return false;
      _prepareFrameHandler(requestId);
      final result = await _channel.invokeMapMethod<String, dynamic>('start', {
        'sessionId': sessionId,
        'requestPermission': requestPermission,
        'requestId': requestId,
      });
      if (_disposed || requestId != _requestId) return false;
      final status = _parseStatus(result?['status']);
      // Subscribe only after the optional native bridge confirms capture.
      if (status == AudioSpectrumStatus.active) {
        _listening = true;
        await _frameControl.invokeMethod<void>('listen');
      }
      if (_disposed || requestId != _requestId) return false;
      _setStatus(
          status, result?['message']?.toString() ?? _defaultMessage(status));
      if (status != AudioSpectrumStatus.active) _clearFrame();
      return !_disposed &&
          requestId == _requestId &&
          status == AudioSpectrumStatus.active;
    } catch (error) {
      if (_disposed || requestId != _requestId) return false;
      final status =
          error is PlatformException && error.code == 'permissionRequired'
              ? AudioSpectrumStatus.permissionRequired
              : AudioSpectrumStatus.unavailable;
      _setStatus(status, _defaultMessage(status));
      _clearFrame();
      await _detachFrames();
      await _stopNative(requestId);
      return false;
    }
  }

  void _prepareFrameHandler(int requestId) {
    // Own the EventChannel handshake so a missing Activity/listener is a
    // recoverable service state, rather than an uncaught global FlutterError.
    _eventChannel.binaryMessenger.setMessageHandler(_eventChannel.name,
        (data) async {
      if (_disposed || requestId != _requestId) return null;
      try {
        _onEvent(data == null
            ? {'requestId': requestId, 'status': 'idle'}
            : _eventChannel.codec.decodeEnvelope(data));
      } on PlatformException catch (error) {
        final status = error.code == 'permissionRequired'
            ? AudioSpectrumStatus.permissionRequired
            : AudioSpectrumStatus.unavailable;
        final retiredId = _requestId = ++_nextRequestId;
        _setStatus(status, '当前设备无法获取音频频谱');
        _clearFrame();
        unawaited(_detachFrames().then((_) => _stopNative(retiredId)));
      }
      return null;
    });
  }

  Future<void> _detachFrames() {
    _eventChannel.binaryMessenger.setMessageHandler(_eventChannel.name, null);
    if (!_listening) return _frameCancellation;
    _listening = false;
    return _frameCancellation = () async {
      try {
        await _frameControl.invokeMethod<void>('cancel');
      } catch (_) {
        // The Activity may be gone, or its replacement has no active stream.
      }
    }();
  }

  Future<void> stop() async {
    if (_disposed) return;
    final requestId = _requestId = ++_nextRequestId;
    _setStatus(AudioSpectrumStatus.idle, '');
    _clearFrame();
    await _detachFrames();
    await _stopNative(requestId);
  }

  Future<void> _stopNative(int requestId) async {
    try {
      await _channel.invokeMethod<void>('stop', {'requestId': requestId});
    } catch (_) {
      // Optional bridge, or the Android activity/engine has already gone away.
    }
  }

  void _onEvent(dynamic event) {
    if (_disposed || event is! Map || event['requestId'] != _requestId) return;
    if (event.containsKey('status')) {
      final status = _parseStatus(event['status']);
      // Separate Android channels can deliver a terminal event before the
      // method response. A late response must not reactivate that capture.
      if (status != AudioSpectrumStatus.active) _requestId = ++_nextRequestId;
      _setStatus(
          status, event['message']?.toString() ?? _defaultMessage(status));
      if (status != AudioSpectrumStatus.active) {
        _clearFrame();
        unawaited(_detachFrames());
      }
      return;
    }
    if (_status != AudioSpectrumStatus.active) return;
    final raw = event['bands'];
    if (raw is! List || raw.length != bandCount) return;
    final bands = <double>[];
    for (final value in raw) {
      if (value is! num || !value.isFinite) return;
      bands.add(value.toDouble().clamp(0.0, 1.0));
    }
    _frames.add(List<double>.unmodifiable(bands));
  }

  void _clearFrame() {
    if (!_disposed) {
      _frames.add(List<double>.filled(bandCount, 0, growable: false));
    }
  }

  void _setStatus(AudioSpectrumStatus status, String message) {
    if (_disposed || (_status == status && _message == message)) return;
    _status = status;
    _message = message;
    notifyListeners();
  }

  static AudioSpectrumStatus _parseStatus(dynamic status) => switch (status) {
        'active' => AudioSpectrumStatus.active,
        'permissionRequired' => AudioSpectrumStatus.permissionRequired,
        'idle' => AudioSpectrumStatus.idle,
        _ => AudioSpectrumStatus.unavailable,
      };

  static String _defaultMessage(AudioSpectrumStatus status) => switch (status) {
        AudioSpectrumStatus.permissionRequired => '需要授权后才能读取播放音频频谱',
        AudioSpectrumStatus.unavailable => '当前设备暂不支持音频频谱',
        _ => '',
      };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A permission dialog can make the app inactive. Let that request finish;
    // only backgrounding or leaving the page should cancel the requested start.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final requestId = _requestId = ++_nextRequestId;
    unawaited(_detachFrames().then((_) => _stopNative(requestId)));
    unawaited(_frames.close());
    super.dispose();
  }
}
