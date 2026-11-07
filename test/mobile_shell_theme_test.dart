import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
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
    final desktop = DesktopIntegrationService(
      settings: settings,
      player: player,
    );
    addTearDown(settings.dispose);
    addTearDown(player.dispose);
    addTearDown(auth.dispose);
    addTearDown(timer.dispose);

    final theme = AppTheme.forAccent('skyBlue', dark: true).data;
    final background = theme.colorScheme.surfaceContainerLowest;
    final miniPlayerBackground = theme.colorScheme.surfaceContainer;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsController>.value(value: settings),
          ChangeNotifierProvider<PlayerController>.value(value: player),
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<SleepTimer>.value(value: timer),
          ChangeNotifierProvider<DesktopIntegrationService>.value(
              value: desktop),
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
    final miniBounds = tester
        .getRect(find.byKey(const ValueKey('mobile-mini-player-surface')));
    final navBounds =
        tester.getRect(find.byKey(const ValueKey('mobile-bottom-nav-surface')));
    expect(miniBounds.left, 0);
    expect(miniBounds.right, tester.view.physicalSize.width);
    expect(miniBounds.bottom, navBounds.top);
    expect(miniBounds.height, greaterThanOrEqualTo(48));
    expect(
        (bottomNav.decoration! as BoxDecoration).color, miniPlayerBackground);
    expect(tester.takeException(), isNull);
  });

  for (final bottomInset in [0.0, 24.0]) {
    testWidgets(
        'nested pages keep playback above the $bottomInset system inset',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewPadding = FakeViewPadding(top: 24, bottom: bottomInset);
      tester.view.padding = FakeViewPadding(top: 24, bottom: bottomInset);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final settings = SettingsController();
      final player = _CurrentSongPlayer(settings);
      final auth = AuthController();
      final timer = SleepTimer();
      final desktop = DesktopIntegrationService(
        settings: settings,
        player: player,
      );
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
            ChangeNotifierProvider<DesktopIntegrationService>.value(
                value: desktop),
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
        tester.view.physicalSize.height - bottomInset,
      );

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(
                find.byKey(const ValueKey('mobile-mini-player-surface')))
            .dy,
        tester.view.physicalSize.height - 300,
      );
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.padding = FakeViewPadding(top: 24, bottom: bottomInset);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mobile-bottom-nav-surface')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

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
