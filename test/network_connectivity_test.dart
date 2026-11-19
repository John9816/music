import 'dart:async';

import 'package:duck_music/core/network/network_connectivity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 单例内部会创建 http.Client，必须在 test zone 内初始化，故用 setUpAll。
  late final NetworkConnectivity net;
  setUpAll(() => net = NetworkConnectivity.instance);

  tearDown(() {
    net.setProberForTest(null);
  });

  test('probeNow 把离线状态翻转并通过流广播', () async {
    var online = true;
    net.setProberForTest(() async => online);
    // 单一订阅：onListen 会触发一次自动探测，等待它落地后再建立在线基线。
    final changes = <bool>[];
    final sub = net.onConnectivityChanged.listen(changes.add);
    await net.probeNow();
    expect(net.isOnline, isTrue);
    changes.clear(); // 清掉基线阶段可能收到的事件

    online = false;
    await net.probeNow();
    // 让广播同步分发完成。
    await Future<void>.delayed(Duration.zero);
    expect(net.isOnline, isFalse);
    expect(changes, contains(false));

    await sub.cancel();
  });

  test('waitForOnline 在已在线时立即返回 true', () async {
    net.setProberForTest(() async => true);
    final result = await net.waitForOnline(
      timeout: const Duration(seconds: 2),
    );
    expect(result, isTrue);
  });

  test('waitForOnline 在断网后网络恢复时返回 true（自动续传触发条件）', () async {
    var online = false;
    net.setProberForTest(() async => online);
    await net.probeNow(); // 建立离线基线
    expect(net.isOnline, isFalse);

    final wait = net.waitForOnline(timeout: const Duration(seconds: 5));
    // 稍后模拟网络恢复：翻转探测结果并触发一次探测，应立刻唤醒等待。
    Timer(const Duration(milliseconds: 200), () async {
      online = true;
      await net.probeNow();
    });
    final result = await wait;
    expect(result, isTrue);
  });

  test('waitForOnline 在超时仍未恢复时返回 false', () async {
    net.setProberForTest(() async => false);
    await net.probeNow();
    final result = await net.waitForOnline(
      timeout: const Duration(milliseconds: 600),
    );
    expect(result, isFalse);
  });

  test('waitForOnline 在 shouldAbort 命中时提前结束（用户取消下载）', () async {
    net.setProberForTest(() async => false);
    await net.probeNow();
    var cancelled = false;
    Timer(const Duration(milliseconds: 200), () => cancelled = true);
    final started = DateTime.now();
    final result = await net.waitForOnline(
      timeout: const Duration(seconds: 10),
      shouldAbort: () => cancelled,
    );
    final elapsed = DateTime.now().difference(started);
    expect(result, isFalse);
    expect(elapsed.inSeconds, lessThan(3), reason: '应在取消后快速返回，而非苦等超时');
  });
}
