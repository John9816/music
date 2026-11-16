import 'package:duck_music/core/services/origin_island.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.music.player/origin_island');
  late List<MethodCall> calls;
  late bool showResult;

  setUp(() {
    calls = <MethodCall>[];
    showResult = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isSupported':
          return true;
        case 'show':
          return showResult;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('非 vivo 设备不推送也不隐藏', () async {
    final island = OriginIslandService(probe: () async => false);
    await island.initialize();

    final shown = await island.show(
        title: '歌', playing: true, progressMs: 1000, durationMs: 2000);
    await island.hide();

    expect(shown, isFalse);
    expect(calls, isEmpty);
  });

  test('相同进度在节流窗口内只推一次', () async {
    final island = OriginIslandService(probe: () async => true);
    await island.initialize();

    expect(
      await island.show(
          title: '歌', playing: true, progressMs: 1000, durationMs: 10000),
      isTrue,
    );
    // 进度未变、时间未过窗口 → 被节流。
    expect(
      await island.show(
          title: '歌', playing: true, progressMs: 1000, durationMs: 10000),
      isFalse,
    );
    expect(calls.where((c) => c.method == 'show'), hasLength(1));
  });

  test('暂停与切歌会重建签名并推送', () async {
    final island = OriginIslandService(probe: () async => true);
    await island.initialize();

    await island.show(
        title: '歌', playing: true, progressMs: 1000, durationMs: 10000);
    // playing 变化 → 签名变化，即使进度相同也要推。
    await island.show(
        title: '歌', playing: false, progressMs: 1000, durationMs: 10000);
    // 切歌 → 签名变化。
    await island.show(
        title: '另一首', playing: false, progressMs: 0, durationMs: 10000);

    expect(calls.where((c) => c.method == 'show'), hasLength(3));
    final last = calls.where((c) => c.method == 'show').last;
    expect(last.arguments['rightText'], '已暂停');
  });

  test('hide 会清空签名，下次 show 一定推送', () async {
    final island = OriginIslandService(probe: () async => true);
    await island.initialize();

    await island.show(
        title: '歌', playing: true, progressMs: 1000, durationMs: 10000);
    await island.hide();
    await island.show(
        title: '歌', playing: true, progressMs: 1000, durationMs: 10000);

    expect(calls.where((c) => c.method == 'show'), hasLength(2));
    expect(calls.where((c) => c.method == 'hide'), hasLength(1));
  });
}
