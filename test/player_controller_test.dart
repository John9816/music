import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('position stream remains stable across UI rebuilds', () {
    final player = PlayerController(settings: SettingsController());
    addTearDown(player.dispose);

    expect(identical(player.positionStream, player.positionStream), isTrue);
  });
}
