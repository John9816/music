import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// 网络连通性服务（单例，零新增依赖）。
///
/// 背景：应用此前不感知网络状态——更新包下载失败后仅重试 4 次（约 7s）就放弃，
/// 播放失败也直接跳过。用户"断网→重新联网"后没有任何机制自动续传/续播。
///
/// 为什么不用 connectivity_plus：
///  - 新依赖会改变 pubspec.lock，安卓 ECS 构建链路需要重新拉包，风险高；
///  - 网卡"已连接"并不代表能访问业务服务（连着 WiFi 但无外网、代理失效都会误判）。
///
/// 这里改为直接探测真实业务端点：只要能收到任意 HTTP 响应（含 4xx/5xx），
/// 就说明链路可达；只有连接失败/超时才算离线。对"下载/播放能否恢复"而言更准确。
///
/// 省电：采用引用计数，只有在有人监听或等待恢复时才启动周期探测；
/// 在线时低频（8s），离线时高频（3s）以便尽快发现恢复。
class NetworkConnectivity with WidgetsBindingObserver {
  NetworkConnectivity._();
  static final NetworkConnectivity instance = NetworkConnectivity._();

  /// 探测端点：自有 API + 国内公共兜底，任一可达即视为在线。
  /// 用 HEAD，几乎不产生流量。
  static const List<String> _probeUrls = <String>[
    'https://api.751152.xyz/',
    'https://www.baidu.com/',
  ];
  static const Duration _probeTimeout = Duration(seconds: 4);
  static const Duration _onlineInterval = Duration(seconds: 8);
  static const Duration _offlineInterval = Duration(seconds: 3);

  final http.Client _client = http.Client();
  final StreamController<bool> _controller = StreamController<bool>.broadcast(
    onListen: _onListen,
    onCancel: _onCancel,
  );

  bool _online = true;
  int _listenerCount = 0;
  Timer? _timer;
  Future<bool>? _inFlight;
  bool _lifecycleAttached = false;
  /// 仅供测试注入确定性探测结果；生产环境恒为 null。
  Future<bool> Function()? _testProber;

  bool get isOnline => _online;

  /// 仅供测试：覆盖/恢复探测函数。传 null 恢复真实端点探测。
  void setProberForTest(Future<bool> Function()? prober) => _testProber = prober;

  /// 连通性变化流。监听即开启探测，取消监听后无其他使用者则停止探测。
  /// 订阅瞬间会立即推一次当前状态，避免 waitForOnline 的竞态窗口。
  Stream<bool> get onConnectivityChanged => _controller.stream;

  static void _onListen() => instance._retain();
  static void _onCancel() => instance._release();

  /// 注册生命周期观察：回到前台时立即探测一次（手机常在回前台时才恢复网络）。
  void ensureLifecycleAttached() {
    if (_lifecycleAttached) return;
    _lifecycleAttached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _listenerCount > 0) {
      unawaited(probeNow());
    }
  }

  void _retain() {
    ensureLifecycleAttached();
    _listenerCount++;
    if (_timer == null) {
      unawaited(probeNow());
      _scheduleNext();
    }
  }

  void _release() {
    if (_listenerCount > 0) _listenerCount--;
    if (_listenerCount == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(
      _online ? _onlineInterval : _offlineInterval,
      () async {
        await probeNow();
        if (_listenerCount > 0) _scheduleNext();
      },
    );
  }

  void _setOnline(bool value) {
    if (value == _online) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
    // 状态翻转后立刻重排探测节奏（离线时更快重试）。
    if (_listenerCount > 0) _scheduleNext();
  }

  /// 立即探测一次；并发调用共享同一次在途探测，避免重复请求。
  Future<bool> probeNow() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _probeInternal();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<bool> _probeInternal() async {
    final testProber = _testProber;
    if (testProber != null) {
      final online = await testProber();
      _setOnline(online);
      return online;
    }
    final results = await Future.wait<bool>(
      _probeUrls.map(_probeOne),
      eagerError: false,
    );
    final online = results.any((reachable) => reachable);
    _setOnline(online);
    return online;
  }

  Future<bool> _probeOne(String url) async {
    try {
      // 只要拿到 HTTP 响应就算链路可达（4xx/5xx 也算，服务器活着）。
      await _client.head(Uri.parse(url)).timeout(_probeTimeout);
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      // http.ClientException 等：连接被重置/证书异常，视为不可达。
      return false;
    }
  }

  /// 等待网络恢复。
  ///
  /// 当前已在线立即返回 true；否则订阅变化并周期探测，直到恢复或超时。
  /// [timeout] 默认 10 分钟，避免无限等待；返回 false 表示超时或 [shouldAbort] 中止。
  Future<bool> waitForOnline({
    Duration timeout = const Duration(minutes: 10),
    bool Function()? shouldAbort,
  }) async {
    final completer = Completer<bool>();
    late final StreamSubscription<bool> subscription;
    final deadline = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    // 取消下载等外部中止信号：短轮询检查，命中即结束等待。
    Timer? abortTimer;
    if (shouldAbort != null) {
      abortTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (shouldAbort() && !completer.isCompleted) {
          completer.complete(false);
        }
      });
    }

    subscription = _controller.stream.listen((online) {
      if (online && !completer.isCompleted) completer.complete(true);
    });

    // 订阅完成后再主动探测：即便恢复发生在订阅前的竞态窗口，
    // 若当前已在线，也能通过下面这次探测的 onListen 推送或结果兜底捕获。
    final onlineNow = await probeNow();
    if (onlineNow && !completer.isCompleted) completer.complete(true);

    // 若探测判定在线但没有触发流事件（状态本就是 true），补一次完成。
    if (_online && !completer.isCompleted) completer.complete(true);

    try {
      return await completer.future;
    } finally {
      deadline.cancel();
      abortTimer?.cancel();
      await subscription.cancel();
    }
  }
}
