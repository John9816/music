import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final routeName in ['player', 'app']) {
    for (final reducedMotion in [false, true]) {
      testWidgets(
          'rebuilding $routeName transitions releases animation listeners '
          '(reduced motion: $reducedMotion)', (tester) async {
        final animation = _TrackedRouteAnimation();
        PageRouteBuilder<void>? route;
        final rebuild = ValueNotifier<int>(0);
        addTearDown(rebuild.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reducedMotion,
              ),
              child: child!,
            ),
            home: ValueListenableBuilder<int>(
              valueListenable: rebuild,
              builder: (context, value, _) {
                route ??= (routeName == 'player'
                    ? buildPlayerRoute(reducedMotion: reducedMotion)
                    : buildAppRoute<void>(
                        context,
                        (_) => const SizedBox.expand(),
                      )) as PageRouteBuilder<void>;
                return route!.transitionsBuilder(
                  context,
                  animation,
                  const AlwaysStoppedAnimation<double>(0),
                  const SizedBox.expand(),
                );
              },
            ),
          ),
        );
        for (var i = 1; i <= 12; i++) {
          rebuild.value = i;
          await tester.pump();
        }
        await tester.pumpWidget(const SizedBox.shrink());

        expect(animation.statusListeners, isEmpty);
        expect(animation.valueListeners, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('switching tabs keeps inactive root pages unchanged',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final settings = SettingsController();
    final player = _PerformancePlayer(settings, hasCurrentSong: false);
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

    await tester.pumpWidget(
      _providers(
        settings: settings,
        player: player,
        auth: auth,
        timer: timer,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final homeBefore = tester.widget<DiscoverView>(
      find.byType(DiscoverView, skipOffstage: false),
    );
    await tester.tap(find.byTooltip('我的'));
    await tester.pump();
    final homeAfter = tester.widget<DiscoverView>(
      find.byType(DiscoverView, skipOffstage: false),
    );

    expect(homeAfter, same(homeBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unrelated player notifications do not rebuild ambient artwork',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    final ambientFinder = find.byType(ImageFiltered).first;
    final ambientBefore = tester.widget<ImageFiltered>(ambientFinder);

    harness.player.notifyUnrelatedChange();
    await tester.pump();

    expect(tester.widget<ImageFiltered>(ambientFinder), same(ambientBefore));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyric view ignores position updates within the same line',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();

    harness.player.emitPosition(const Duration(seconds: 1));
    await tester.pump();
    final maskFinder = find.byType(ShaderMask);
    final maskAfterFirstPosition = tester.widget<ShaderMask>(maskFinder);

    harness.player.emitPosition(const Duration(seconds: 2));
    await tester.pump();

    final maskAfterSecondPosition = tester.widget<ShaderMask>(maskFinder);
    expect(maskAfterSecondPosition, same(maskAfterFirstPosition));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambient artwork uses a bounded decode size', (tester) async {
    await _pumpPlayer(tester);
    final ambient = find.byType(ImageFiltered).first;
    final image = tester.widget<CachedNetworkImage>(
      find.descendant(of: ambient, matching: find.byType(CachedNetworkImage)),
    );

    expect(image.memCacheWidth, 256);
    expect(image.memCacheHeight, 256);
    expect(tester.takeException(), isNull);
  });
}

class _TrackedRouteAnimation extends Animation<double> {
  final statusListeners = <AnimationStatusListener>{};
  final valueListeners = <VoidCallback>{};

  @override
  double get value => 0.5;

  @override
  AnimationStatus get status => AnimationStatus.forward;

  @override
  void addListener(VoidCallback listener) => valueListeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => valueListeners.remove(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) =>
      statusListeners.add(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) =>
      statusListeners.remove(listener);
}

Future<_PlayerHarness> _pumpPlayer(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final settings = SettingsController();
  final player = _PerformancePlayer(settings);
  final auth = AuthController();
  final timer = SleepTimer();
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  addTearDown(timer.dispose);

  await tester.pumpWidget(
    _providers(
      settings: settings,
      player: player,
      auth: auth,
      timer: timer,
      child: MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.iOS,
            ),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(top: 47, bottom: 34),
          ),
          child: PlayerView(),
        ),
      ),
    ),
  );
  await tester.pump();
  return _PlayerHarness(player);
}

Widget _providers({
  required SettingsController settings,
  required PlayerController player,
  required AuthController auth,
  required SleepTimer timer,
  required Widget child,
}) {
  final desktop = DesktopIntegrationService(
    settings: settings,
    player: player,
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ChangeNotifierProvider<DesktopIntegrationService>.value(value: desktop),
    ],
    child: child,
  );
}

class _PlayerHarness {
  const _PlayerHarness(this.player);

  final _PerformancePlayer player;
}

class _PerformancePlayer extends PlayerController {
  _PerformancePlayer(
    SettingsController settings, {
    this.hasCurrentSong = true,
  }) : super(settings: settings);

  final bool hasCurrentSong;
  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast(sync: true);
  Duration _position = Duration.zero;

  static final _song = Song(
    id: 'performance-song',
    name: '性能测试歌曲',
    source: 'netease',
    artists: const [Artist(id: 1, name: '测试歌手')],
    album: const Album(
      id: 1,
      name: '性能测试专辑',
      picUrl: 'https://example.com/cover.jpg',
    ),
    durationMs: 180000,
  );

  @override
  Song? get current => hasCurrentSong ? _song : null;

  @override
  bool get playing => false;

  @override
  bool get loading => false;

  @override
  Duration get position => _position;

  @override
  Duration? get duration => const Duration(minutes: 3);

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  String get lyric => '''
[00:00.00]第一行歌词
[00:10.00]第二行歌词
[00:20.00]第三行歌词
''';

  void notifyUnrelatedChange() => notifyListeners();

  void emitPosition(Duration position) {
    _position = position;
    _positions.add(position);
  }

  @override
  void dispose() {
    unawaited(_positions.close());
    super.dispose();
  }
}
