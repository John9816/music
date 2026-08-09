import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('mobile shell uses one themed edge-to-edge surface',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final settings = SettingsController();
    final player = _CurrentSongPlayer(settings);
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

    final theme = AppTheme.forAccent('skyBlue', dark: true).data;
    final background = theme.colorScheme.surfaceContainerLowest;
    final miniPlayerBackground =
        theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.97);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
        ],
        child: MaterialApp(
          theme: theme,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pump();

    final shell = tester.widget<Scaffold>(
      find.byKey(const ValueKey('home-shell-scaffold')),
    );
    final miniPlayer = tester.widget<Container>(
      find.byKey(const ValueKey('mobile-mini-player-surface')),
    );
    final bottomNav = tester.widget<Container>(
      find.byKey(const ValueKey('mobile-bottom-nav-surface')),
    );
    expect(shell.backgroundColor, background);
    expect(
      (miniPlayer.decoration! as BoxDecoration).color,
      miniPlayerBackground,
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile-mini-player-surface')),
      ),
      const Size(358, 52),
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('mobile-mini-player-surface')),
          )
          .dx,
      16,
    );
    expect((bottomNav.decoration! as BoxDecoration).color, background);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile bottom navigation hides on nested pages', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final settings = SettingsController();
    final player = _CurrentSongPlayer(settings);
    final auth = AuthController();
    final timer = SleepTimer();
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
        ],
        child: MaterialApp(
          theme: AppTheme.byId('dark').data,
          home: const HomeShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-surface')),
      findsOneWidget,
    );
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('深浅模式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-surface')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile-mini-player-surface')),
      findsOneWidget,
    );
    expect(
      tester
          .getBottomRight(
            find.byKey(const ValueKey('mobile-mini-player-surface')),
          )
          .dy,
      814,
    );

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-surface')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile app bar shares the page themed surface', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final theme = AppTheme.forAccent('skyBlue', dark: true).data;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: GAppBar(title: '设置', onBack: () {}),
          body: const SizedBox.expand(),
        ),
      ),
    );

    final appBar = tester.widget<Container>(
      find.byKey(const ValueKey('g-app-bar-surface')),
    );
    expect(
      (appBar.decoration! as BoxDecoration).color,
      theme.colorScheme.surfaceContainerLowest,
    );
    expect(tester.takeException(), isNull);
  });
}

class _CurrentSongPlayer extends PlayerController {
  _CurrentSongPlayer(SettingsController settings) : super(settings: settings);

  final Song _song = Song(
    id: 'surface-preview',
    name: '不过如此',
    source: 'netease',
    artists: const [Artist(id: 1, name: '怪豆儿')],
    album: const Album(id: 1, name: '不过如此'),
    durationMs: 180000,
  );

  @override
  Song get current => _song;

  @override
  bool get playing => false;
}
