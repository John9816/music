import 'package:duck_music/app.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/profile/login_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('accent themes', () {
    test('preserve every selectable accent with readable foregrounds', () {
      for (final accent in AppAccent.all) {
        for (final dark in [false, true]) {
          final scheme =
              AppTheme.forAccent(accent.id, dark: dark).data.colorScheme;

          expect(scheme.primary, accent.color);
          expect(
            _contrastRatio(scheme.primary, scheme.onPrimary),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.name} ${dark ? 'dark' : 'light'} foreground',
          );
          expect(
            _contrastRatio(
              scheme.primaryContainer,
              scheme.onPrimaryContainer,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${accent.name} ${dark ? 'dark' : 'light'} container',
          );
        }
      }
    });

    test('keep application surfaces neutral across accent choices', () {
      for (final dark in [false, true]) {
        final first = AppTheme.forAccent(
          AppAccent.all.first.id,
          dark: dark,
        ).data.colorScheme;

        for (final accent in AppAccent.all.skip(1)) {
          final scheme =
              AppTheme.forAccent(accent.id, dark: dark).data.colorScheme;
          expect(scheme.surface, first.surface);
          expect(scheme.surfaceContainerLowest, first.surfaceContainerLowest);
          expect(scheme.surfaceContainerLow, first.surfaceContainerLow);
          expect(scheme.surfaceContainer, first.surfaceContainer);
          expect(scheme.surfaceContainerHigh, first.surfaceContainerHigh);
          expect(scheme.surfaceContainerHighest, first.surfaceContainerHighest);
        }
      }
    });
  });

  testWidgets('desktop press targets expose pointer affordance',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.windows,
            ),
        home: const Scaffold(
          body: GPressScale(
            key: ValueKey('press-target'),
            onTap: _noop,
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );

    final pointerRegion = find.descendant(
      of: find.byKey(const ValueKey('press-target')),
      matching: find.byType(MouseRegion),
    );
    expect(pointerRegion, findsOneWidget);
    expect(
      tester.widget<MouseRegion>(pointerRegion).cursor,
      SystemMouseCursors.click,
    );
  });

  testWidgets('830px player stays in the navigation compact mode',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(830, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final settings = SettingsController();
    final player = _PreviewPlayer(settings);
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
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.iOS,
              ),
          home: const PlayerView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('查看歌词'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows scroll views expose a desktop scrollbar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DuckMusicScrollBehavior(),
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.windows,
            ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(height: 1600),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS scroll views avoid the MouseTracker scrollbar path',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const DuckMusicScrollBehavior(),
        theme: AppTheme.byId('dark').data.copyWith(
              platform: TargetPlatform.macOS,
            ),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(height: 1600),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login labels persist and consent copy wraps at large text sizes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final auth = AuthController();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.android,
              ),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.6),
            ),
            child: LoginView(allowBack: false),
          ),
        ),
      ),
    );

    final fields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(
      fields.map((field) => field.decoration?.labelText),
      ['用户名或邮箱', '密码'],
    );
    expect(
      fields.map((field) => field.decoration?.floatingLabelBehavior),
      everyElement(FloatingLabelBehavior.always),
    );
    final consent = tester.widget<Text>(
      find.text('已阅读并同意用户协议与隐私政策'),
    );
    expect(consent.maxLines, isNull);
    expect(consent.overflow, isNot(TextOverflow.ellipsis));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop login content is vertically balanced', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final auth = AuthController();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.byId('dark').data.copyWith(
                platform: TargetPlatform.macOS,
              ),
          home: const LoginView(allowBack: false),
        ),
      ),
    );

    final content = find.byKey(const ValueKey('auth-content'));
    expect(content, findsOneWidget);
    expect(
      tester.getCenter(content).dy,
      closeTo(tester.view.physicalSize.height / 2, 80),
    );
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

class _PreviewPlayer extends PlayerController {
  _PreviewPlayer(SettingsController settings) : super(settings: settings);

  final Song song = Song(
    id: 'design-preview',
    name: '继续聆听',
    source: 'netease',
    artists: const [Artist(id: 7511, name: '柒伍壹壹')],
    album: const Album(id: 7511, name: '设计回归'),
    durationMs: 180000,
  );

  @override
  Song? get current => song;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance > secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance > secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
