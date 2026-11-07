import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/desktop_integration_service.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/discover/discover_view.dart';
import 'package:duck_music/features/home/home_shell.dart';
import 'package:duck_music/features/playlists/playlists_view.dart';
import 'package:duck_music/features/search/search_view.dart';
import 'package:duck_music/features/profile/user_library_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('closing the dock on resize returns its space to content',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.tap(find.byTooltip('歌词'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DiscoverView)).width,
        greaterThanOrEqualTo(560));

    tester.view.physicalSize = const Size(900, 700);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DiscoverView)).width,
        greaterThanOrEqualTo(560));
    tester.view.physicalSize = const Size(700, 700);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DiscoverView)).width, 700);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile navigation exposes the library directly', (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    final navigation = find.byKey(const ValueKey('mobile-bottom-nav-surface'));
    expect(find.descendant(of: navigation, matching: find.text('资料库')),
        findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets(
        'search source changes preserve home and discover at ${size.width}',
        (tester) async {
      await _pumpShell(tester, size);
      final home = find.byType(DiscoverView, skipOffstage: false);
      final homeState = tester.state(home);
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      final discover = find.byType(PlaylistsView, skipOffstage: false);
      final discoverState = tester.state(discover);
      if (size.width < 900) {
        await tester.tap(find.text('搜索').last);
      } else {
        await tester.tap(find.byKey(const ValueKey('sidebar_search_control')));
      }
      await tester.pumpAndSettle();
      final settings =
          tester.element(find.byType(HomeShell)).read<SettingsController>();
      await tester.tap(find.byKey(const ValueKey('search_source_qq')));
      await tester.pumpAndSettle();

      expect(settings.source, 'netease',
          reason: 'Searching another provider must not change browsing.');
      await tester.tap(find.text('首页').last);
      await tester.pumpAndSettle();
      expect(tester.state(home), same(homeState));
      await tester.tap(find.text('发现').last);
      await tester.pumpAndSettle();
      expect(tester.state(discover), same(discoverState));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching tabs removes focus from the hidden search input',
      (tester) async {
    await _pumpShell(tester, const Size(390, 844));
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    final searchField = find.descendant(
      of: find.byType(SearchView),
      matching: find.byType(TextField),
    );
    await tester.tap(searchField);
    await tester.pump();
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.focusNode.hasFocus, isTrue);
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    expect(input.focusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop search shortcut opens and focuses the search field',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
    expect(find.byType(SearchView), findsOneWidget);
    final input = tester.widget<EditableText>(find.descendant(
      of: find.byType(SearchView),
      matching: find.byType(EditableText),
    ));
    expect(input.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playback shortcuts leave text caret and selection keys intact',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('sidebar_search_control')));
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(SearchView), matching: find.byType(TextField));
    await tester.enterText(field, 'abcd');
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(controller.selection,
        const TextSelection(baseOffset: 2, extentOffset: 1));
    final player = Provider.of<PlayerController>(
        tester.element(find.byType(SearchView)),
        listen: false) as _CurrentSongPlayer;
    expect(player.seekCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'search shortcut reveals the field above a preserved detail route',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('sidebar_search_control')));
    await tester.pumpAndSettle();
    final searchContext = tester.element(find.byType(SearchView));
    Navigator.of(searchContext).push<void>(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('搜索详情页')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('首页').first);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.text('搜索详情页'), findsNothing);
    expect(find.byType(SearchView), findsOneWidget);
    final input = tester.widget<EditableText>(find.descendant(
        of: find.byType(SearchView), matching: find.byType(EditableText)));
    expect(input.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'focused progress keeps modified app playback shortcuts available',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    final player = Provider.of<PlayerController>(
        tester.element(find.byType(HomeShell)),
        listen: false) as _CurrentSongPlayer;
    await tester.tap(find.bySemanticsLabel('播放进度'));
    await tester.pumpAndSettle();
    final initialSeekCount = player.seekCount;
    expect(initialSeekCount, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'playback-progress');

    for (final modifier in [
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.meta,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }
    expect(player.nextCount, 2);
    expect(player.seekCount, initialSeekCount);

    final initialPosition = player.position;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(player.position, initialPosition + const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
  });

  testWidgets('history receives activation changes without losing its state',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800),
        authOverride: _SignedInAuth());
    await tester.tap(find.text('播放历史').first);
    await tester.pumpAndSettle();
    final history = find.byType(UserLibraryView, skipOffstage: false);
    final historyState = tester.state(history);
    expect(tester.widget<UserLibraryView>(history).active, isTrue);
    await tester.tap(find.text('首页').first);
    await tester.pumpAndSettle();
    expect(tester.widget<UserLibraryView>(history).active, isFalse);
    await tester.tap(find.text('播放历史').first);
    await tester.pumpAndSettle();
    expect(tester.widget<UserLibraryView>(history).active, isTrue);
    expect(tester.state(history), same(historyState));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotating credentials preserves the current account page state',
      (tester) async {
    final auth = _SignedInAuth();
    await _pumpShell(tester, const Size(1280, 800), authOverride: auth);
    await tester.tap(find.text('播放历史').first);
    await tester.pumpAndSettle();
    final history = find.byType(UserLibraryView);
    final state = tester.state(history);
    auth.rotateToken();
    await tester.pumpAndSettle();

    expect(tester.state(history), same(state));
    expect(tester.widget<UserLibraryView>(history).active, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search input survives moving between desktop and mobile layouts',
      (tester) async {
    await _pumpShell(tester, const Size(1280, 800));
    await tester.tap(find.byKey(const ValueKey('sidebar_search_control')));
    await tester.pumpAndSettle();
    final field = find.descendant(
        of: find.byType(SearchView), matching: find.byType(TextField));
    await tester.enterText(field, '保存搜索状态');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    for (final width in [700.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).controller!.text, '保存搜索状态');
      expect(tester.takeException(), isNull);
    }
  });
}

Future<void> _pumpShell(WidgetTester tester, Size size,
    {AuthController? authOverride}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  final player = _CurrentSongPlayer(settings);
  final auth = authOverride ?? AuthController();
  final timer = SleepTimer();
  final desktop = DesktopIntegrationService(settings: settings, player: player);
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  addTearDown(timer.dispose);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ChangeNotifierProvider<DesktopIntegrationService>.value(value: desktop),
    ],
    child: MaterialApp(
      theme: AppTheme.forAccent('forestGreen', dark: false)
          .data
          .copyWith(platform: TargetPlatform.windows),
      home: const HomeShell(),
    ),
  ));
  await tester.pumpAndSettle();
}

class _SignedInAuth extends AuthController {
  String _testToken = 'history-test-session';
  @override
  String get token => _testToken;
  @override
  bool get isLoggedIn => true;

  void rotateToken() {
    _testToken = 'refreshed-history-test-session';
    notifyListeners();
  }
}

class _CurrentSongPlayer extends PlayerController {
  _CurrentSongPlayer(SettingsController settings) : super(settings: settings);
  int seekCount = 0;
  int nextCount = 0;
  Duration _position = Duration.zero;

  @override
  Duration get position => _position;

  @override
  Duration get duration => const Duration(minutes: 3);

  @override
  Future<void> seek(Duration position) async {
    seekCount++;
    _position = position;
    notifyListeners();
  }

  @override
  Future<void> next() async => nextCount++;

  @override
  Song get current => Song(
        id: 'responsive-preview',
        name: '继续聆听',
        source: 'netease',
        artists: const [Artist(id: 1, name: '柒伍壹壹')],
        album: const Album(id: 1, name: '音乐时光'),
        durationMs: 180000,
      );

  @override
  bool get playing => false;
}
