import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/settings/player_appearance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('appearance survives restart without altering independent sources', () async {
    SharedPreferences.setMockInitialValues({
      'music_source': 'netease', 'search_music_source': 'qishui',
    });
    final settings = SettingsController();
    await settings.load();
    await settings.setPlayerSkin(PlayerSkin.poster);
    await settings.setFluidBackground(false);
    await settings.setAnimatedArtwork(false);
    await settings.setLiquidNavigation(false);
    final restored = SettingsController();
    await restored.load();
    expect(restored.playerSkin, PlayerSkin.poster);
    expect(restored.fluidBackground, isFalse);
    expect(restored.animatedArtwork, isFalse);
    expect(restored.liquidNavigation, isFalse);
    expect(restored.source, 'netease');
    expect(restored.searchSource, 'qishui');
  });
  test('unknown skin falls back to classic', () async {
    SharedPreferences.setMockInitialValues({'player_skin': 'missing'});
    final settings = SettingsController();
    await settings.load();
    expect(settings.playerSkin, PlayerSkin.classic);
  });
}
