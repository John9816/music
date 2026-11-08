import 'dart:io';
import 'dart:ui' as ui;
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/player/car_media_library.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/car/car_home_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'car_media_library_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('car mode persists independently of player and other preferences',
      () async {
    final settings = SettingsController();
    await settings.setCarModeEnabled(true);
    final restored = SettingsController();
    await restored.load();
    expect(restored.carModeEnabled, true);
    await restored.setCarModeEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('car_mode_enabled'), false);
    settings.dispose();
    restored.dispose();
  });

  for (final config in [
    (size: const Size(800, 480), scale: 1.0),
    (size: const Size(1024, 600), scale: 1.0),
    (size: const Size(1280, 720), scale: 1.0),
    (size: const Size(390, 844), scale: 1.0),
    (size: const Size(800, 480), scale: 1.8),
    (size: const Size(640, 360), scale: 1.3),
  ]) {
    testWidgets('car controls fit ${config.size} at ${config.scale}',
        (tester) async {
      final fixture = await pumpCar(tester, config.size, scale: config.scale);
      expect(tester.takeException(), isNull);
      final play = find.byKey(const ValueKey('car-play-pause'));
      expect(tester.getSize(play).height, greaterThanOrEqualTo(80));
      expect(tester.getSize(find.byKey(const ValueKey('car-next'))).height,
          greaterThanOrEqualTo(64));
      if (config.scale == 1 && config.size.width >= 800) {
        expect(play.hitTestable(), findsOneWidget);
      }
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(fixture.player.playing, true);
      expect(fixture.player.queue.length, 3);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('DUCKMUSIC_EXPORT_QA')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('car-preview')));
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 1);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/qa/car-mode-2026-11-09')
            ..createSync(recursive: true);
          File('${dir.path}/car-${config.size.width.toInt()}x${config.size.height.toInt()}-${config.scale}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }
    });
  }

  testWidgets('search waits for submission and uses the selected provider',
      (tester) async {
    final fixture = await pumpCar(tester, const Size(1024, 600));
    await tester.tap(find.byKey(const ValueKey('car-category-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('car-search-field')), '夜曲');
    await tester.pump(const Duration(seconds: 1));
    expect(fixture.music.source, isNull);
    await tester.tap(find.byKey(const ValueKey('car-search-submit')));
    await tester.pumpAndSettle();
    expect(find.text('车载歌曲 夜曲'), findsOneWidget);
    expect(fixture.music.source, 'qq');
    await tester.tap(find.byKey(const ValueKey('car-song-0')));
    await tester.pumpAndSettle();
    expect(fixture.player.current!.id, '夜曲');
    expect(fixture.player.current!.source, 'qq');
  });

  testWidgets('exit persists mode and leaves the playing queue intact',
      (tester) async {
    final fixture = await pumpCar(tester, const Size(1024, 600));
    await tester.tap(find.byKey(const ValueKey('car-exit')));
    await tester.pumpAndSettle();
    expect(fixture.settings.carModeEnabled, false);
    expect(fixture.player.queue.length, 3);
    expect(fixture.player.playCalls, 0);
  });
}

Future<
    ({
      SettingsController settings,
      fixtures.TestCarPlayer player,
      fixtures.TestCarMusicApi music
    })> pumpCar(WidgetTester tester, Size size, {double scale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (const bool.fromEnvironment('DUCKMUSIC_EXPORT_QA')) {
    final font = File(
        '/Users/wangweijie/projects/xcode/DuckMusic/build/qa/lyric-depth-2026-11-08/NotoSansCJK-Regular.ttc');
    final loader = FontLoader('CarQA')
      ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    await loader.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  }
  final settings = SettingsController();
  await settings.setCarModeEnabled(true);
  await settings.setSearchSource('qq');
  final player = fixtures.TestCarPlayer(settings)
    ..replace([
      fixtures.carSong('夜空中最亮的星'),
      fixtures.carSong('漫长而又美好的旅途'),
      fixtures.carSong('日落大道')
    ]);
  final auth = fixtures.TestCarAuth();
  final music = fixtures.TestCarMusicApi();
  final dir = (await tester
      .runAsync(() => Directory.systemTemp.createTemp('car-layout-')))!;
  final downloads = SongDownloadService.forTesting(
      musicApi: music,
      client: MockClient((_) async => http.Response('', 404)),
      downloadsDirectory: () async => dir);
  final library = CarMediaLibrary(
      auth: auth,
      player: player,
      settings: settings,
      downloads: downloads,
      userApi: fixtures.TestCarUserApi(),
      musicApi: music);
  addTearDown(() async {
    library.dispose();
    downloads.dispose();
    auth.dispose();
    player.dispose();
    settings.dispose();
    await dir.delete(recursive: true);
  });
  var theme = AppTheme.forAccent('forestGreen', dark: true)
      .data
      .copyWith(platform: TargetPlatform.android);
  if (const bool.fromEnvironment('DUCKMUSIC_EXPORT_QA')) {
    theme =
        theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'CarQA'));
  }
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<CarMediaLibrary>.value(value: library),
      ],
      child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: RepaintBoundary(
              key: const ValueKey('car-preview'),
              child: CarHomeView(onFavorite: () {})))));
  await tester.pumpAndSettle();
  return (settings: settings, player: player, music: music);
}
