import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/settings/player_appearance.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/features/player/player_skin_stage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Player extends PlayerController {
  _Player(SettingsController settings) : super(settings: settings);
  @override
  bool get playing => false;
  @override
  Duration get position => const Duration(seconds: 12);
}

void main() {
  testWidgets(
      'artwork clock stops when disabled, hidden, reduced or backgrounded',
      (tester) async {
    var phase = 0.0;
    Future<void> mount(
            {bool enabled = true, bool ticker = true, bool reduced = false}) =>
        tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(disableAnimations: reduced),
                child: TickerMode(
                    enabled: ticker,
                    child: ArtworkMotion(
                        enabled: enabled,
                        builder: (_, t, child) {
                          phase = t;
                          return const SizedBox();
                        })))));
    await mount();
    await tester.pump(const Duration(seconds: 2));
    final moving = phase;
    expect(moving, greaterThan(0));
    for (final option in ['disabled', 'ticker', 'reduced', 'background']) {
      await mount(
          enabled: option != 'disabled',
          ticker: option != 'ticker',
          reduced: option == 'reduced');
      if (option == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      final stopped = phase;
      await tester.pump(const Duration(seconds: 2));
      expect(phase, stopped, reason: option);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpWidget(const SizedBox());
  });

  for (final skin in PlayerSkin.values.where((s) => s != PlayerSkin.classic)) {
    for (final size in [const Size(280, 210), const Size(390, 450)]) {
      testWidgets('${skin.name} fits $size and opens synchronized lyrics',
          (tester) async {
        final settings = SettingsController();
        final player = _Player(settings);
        addTearDown(player.dispose);
        addTearDown(settings.dispose);
        var opened = false;
        final song = Song.fromV1(
            {'id': 'a', 'source': 'qishui', 'name': '歌名', 'artist': '歌手'});
        await tester.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsController>.value(value: settings),
              ChangeNotifierProvider<PlayerController>.value(value: player),
            ],
            child: MaterialApp(
                home: Center(
                    child: SizedBox.fromSize(
                        size: size,
                        child: MediaQuery(
                            data: const MediaQueryData(
                                textScaler: TextScaler.linear(2)),
                            child: PlayerSkinStage(
                                song: song,
                                skin: skin,
                                lrc:
                                    '[00:01.00]上一句\n[00:10.00]当下这一句歌词\n[00:20.00]下一句',
                                onLyrics: () => opened = true)))))));
        await tester.pump();
        expect(find.text('当下这一句歌词'), findsOneWidget);
        expect(find.text('下一句'), findsOneWidget);
        expect(find.text('上一句'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('当下这一句歌词'));
        expect(opened, isTrue);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
