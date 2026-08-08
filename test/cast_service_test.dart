import 'package:duck_music/core/services/cast_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts idle and reports unsupported platforms explicitly', () {
    final service = CastService();

    expect(service.status, CastStatus.idle);
    service.markUnsupported('当前设备未安装投屏服务');

    expect(service.status, CastStatus.unsupported);
    expect(service.message, '当前设备未安装投屏服务');
  });

  test('opening the Apple route picker does not claim a connection', () async {
    const channel = MethodChannel('test.duckmusic/cast-picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'startCast');
      return <String, Object?>{
        'supported': true,
        'connected': false,
        'message': '请选择投屏设备',
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = CastService(channel: channel);
    final opened = await service.start(
      mediaUrl: 'https://cdn.ncat21.com/video.m3u8',
      title: '消失的人',
    );

    expect(opened, isTrue);
    expect(service.status, CastStatus.idle);
    expect(service.message, '请选择投屏设备');
  });

  test('only a native route callback marks casting connected', () async {
    const channel = MethodChannel('test.duckmusic/cast-callback');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{
              'supported': true,
              'connected': false,
            });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final service = CastService(channel: channel);
    await service.start(
      mediaUrl: 'https://cdn.ncat21.com/video.m3u8',
      title: '消失的人',
    );
    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('castStateChanged', <String, Object?>{
        'connected': true,
        'message': '已连接 AirPlay 设备',
        'pauseLocal': true,
      }),
    );
    await messenger.handlePlatformMessage(channel.name, message, (_) {});

    expect(service.status, CastStatus.connected);
    expect(service.message, '已连接 AirPlay 设备');
    expect(service.shouldPauseLocalPlayback, isTrue);
  });

  test('external playback fallback only opens ncat21 HTTPS pages', () async {
    Uri? openedUri;
    final service = CastService(
      launchFallback: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    expect(await service.openFallback('https://evil.example/play/42'), isFalse);
    expect(openedUri, isNull);
    expect(
      await service.openFallback('https://player.ncat21.com/play/42'),
      isTrue,
    );
    expect(openedUri?.host, 'player.ncat21.com');
  });
}
