import 'package:duck_music/core/player/audio_source_policy.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('position stream remains stable across UI rebuilds', () {
    final player = PlayerController(settings: SettingsController());
    addTearDown(player.dispose);

    expect(identical(player.positionStream, player.positionStream), isTrue);
  });

  test('native platforms use native audio request headers', () {
    expect(usesNativeAudioHeaders(TargetPlatform.android), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.iOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.macOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.windows), isFalse);
  });
}
