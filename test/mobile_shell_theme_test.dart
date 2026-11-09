import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/settings/settings_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'mobile shell stacks the full mini player above the three glass tabs',
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
    expect(shell.backgroundColor, background);
    final nav = find.byKey(const ValueKey('mobile-bottom-nav-surface'));
    final disc = find.byKey(const ValueKey('mobile-mini-player-surface'));
    final navBounds = tester.getRect(nav);
    final playerBounds = tester.getRect(disc);
    expect(navBounds.left, greaterThan(0));
    expect(playerBounds.right, lessThan(390));
    expect(playerBounds.bottom, lessThan(navBounds.top));
    expect(find.byKey(const ValueKey('mobile-player-disc-shortcut')),
        findsNothing);
    for (final label in ['探索', '资料库', '我的']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(disc);
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起播放器'), findsOneWidget);
    await tester.tap(find.byTooltip('收起播放器'));
    await tester.pumpAndSettle();
    expect(disc, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final bottomInset in [0.0, 24.0]) {
    for (final hasSong in [true, false]) {
      testWidgets(
          'nested pages protect the $bottomInset system inset with song=$hasSong',
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
        final player = _CurrentSongPlayer(settings, hasSong: hasSong);
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

        expect(find.byType(SettingsView), findsOneWidget);
        expect(find.text('深浅模式'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-bottom-nav-surface')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('mobile-mini-player-surface')),
            hasSong ? findsOneWidget : findsNothing);
        if (hasSong) {
          expect(
              tester
                  .getBottomRight(
                      find.byKey(const ValueKey('mobile-mini-player-surface')))
                  .dy,
              tester.view.physicalSize.height - bottomInset - 10);
        } else {
          expect(tester.getBottomRight(find.byType(SettingsView)).dy,
              tester.view.physicalSize.height - bottomInset);
        }

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        tester.view.padding = const FakeViewPadding(top: 24);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('mobile-mini-player-surface')),
            findsNothing);
        expect(find.text('深浅模式'), findsOneWidget);
        expect(tester.getSize(find.byType(SettingsView)).height,
            tester.view.physicalSize.height - 300);
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
  _CurrentSongPlayer(SettingsController settings, {this.hasSong = true})
      : super(settings: settings);
  final bool hasSong;

  final Song _song = Song(
    id: 'surface-preview',
    name: '不过如此',
    source: 'netease',
    artists: const [Artist(id: 1, name: '怪豆儿')],
    album: const Album(id: 1, name: '不过如此'),
    durationMs: 180000,
  );

  @override
  Song? get current => hasSong ? _song : null;

  @override
  bool get playing => false;
}
