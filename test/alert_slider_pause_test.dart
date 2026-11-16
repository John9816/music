import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/services/alert_slider.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'car_media_library_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.music.player/alert_slider');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'current') return 'normal';
      return true;
    });
    SystemMediaController.setAlertSliderPauseEnabledProvider(() => false);
  });

  tearDown(() {
    SystemMediaController.setAlertSliderPauseEnabledProvider(() => false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> fire(String mode) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onRingerModeChanged', mode),
        ),
        (_) {},
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('静音与振动档暂停播放，恢复响铃不自动续播', () async {
    SystemMediaController.setAlertSliderPauseEnabledProvider(() => true);
    final settings = SettingsController();
    final player = fixtures.TestCarPlayer(settings);
    final handler = SystemMediaController(isAndroid: () => true)
      ..attach(player);
    addTearDown(() {
      handler.detach(player);
      settings.dispose();
      player.dispose();
    });

    await AlertSliderService.instance.initialize();
    await player.playAt(0);
    expect(player.isPlaying, isTrue);

    await fire('silent');
    await settle();
    expect(player.isPlaying, isFalse);

    await player.playAt(0);
    await fire('normal');
    await settle();
    expect(player.isPlaying, isTrue, reason: '恢复响铃不应改变播放状态');

    await fire('vibrate');
    await settle();
    expect(player.isPlaying, isFalse);
  });

  test('开关关闭时静音档不暂停', () async {
    final settings = SettingsController();
    final player = fixtures.TestCarPlayer(settings);
    final handler = SystemMediaController(isAndroid: () => true)
      ..attach(player);
    addTearDown(() {
      handler.detach(player);
      settings.dispose();
      player.dispose();
    });

    await AlertSliderService.instance.initialize();
    await player.playAt(0);

    await fire('silent');
    await settle();

    expect(player.isPlaying, isTrue);
  });
}
