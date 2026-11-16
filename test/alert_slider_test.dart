import 'package:duck_music/core/services/alert_slider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('铃音模式字符串只在已知值间解析', () {
    expect(parseRingerMode('silent'), RingerMode.silent);
    expect(parseRingerMode('vibrate'), RingerMode.vibrate);
    expect(parseRingerMode('normal'), RingerMode.normal);
    expect(parseRingerMode('unknown'), isNull);
    expect(parseRingerMode(null), isNull);
  });

  test('初始化读取当前模式', () async {
    const channel = MethodChannel('test_alert_slider_initial');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'current') return 'vibrate';
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AlertSliderService(channel: channel);
    await service.initialize();

    expect(service.mode, RingerMode.vibrate);
  });

  test('startListening 只调用一次，stop 后可再次启动', () async {
    final calls = <String>[];
    const channel = MethodChannel('test_alert_slider_listen');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AlertSliderService(channel: channel, probe: () async => null);
    await service.startListening();
    await service.startListening();
    expect(service.listening, isTrue);
    expect(calls.where((c) => c == 'startListening'), hasLength(1));

    await service.stopListening();
    expect(service.listening, isFalse);
    await service.startListening();
    expect(calls.where((c) => c == 'startListening'), hasLength(2));
  });

  test('平台回调推送变化，重复模式不重复广播', () async {
    const channel = MethodChannel('test_alert_slider_events');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'current') return 'normal';
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AlertSliderService(channel: channel);
    await service.initialize();
    final events = <RingerMode>[];
    service.changes.listen(events.add);
    const codec = StandardMethodCodec();
    Future<void> fire(String mode) => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
              MethodCall('onRingerModeChanged', mode)),
          (_) {},
        );

    await fire('silent');
    await Future<void>.delayed(Duration.zero);
    await fire('silent');
    await Future<void>.delayed(Duration.zero);
    await fire('normal');
    await Future<void>.delayed(Duration.zero);

    expect(events, [RingerMode.silent, RingerMode.normal]);
    expect(service.mode, RingerMode.normal);
  });

  test('平台调用失败时静默降级', () async {
    const channel = MethodChannel('test_alert_slider_failure');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'UNAVAILABLE');
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final service = AlertSliderService(channel: channel);
    await service.initialize();
    await service.startListening();

    expect(service.mode, RingerMode.normal);
    expect(service.listening, isFalse);
  });
}
