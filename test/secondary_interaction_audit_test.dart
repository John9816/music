import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/playlists/playlist_import_view.dart';
import 'package:duck_music/features/settings/settings_view.dart';
import 'package:duck_music/widgets/song_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _song = Song(
  id: 'menu-fixture',
  name: '菜单测试歌曲',
  source: 'netease',
  artists: const [Artist(id: 1, name: '测试歌手')],
  album: const Album(id: 1, name: '测试专辑'),
  durationMs: 180000,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  testWidgets('rapid song-menu taps open one route and can reopen after cancel',
      (tester) async {
    final observer = _RouteObserver();
    await _pump(tester,
        observer: observer,
        child: Scaffold(body: Center(child: SongActionButton(song: _song))));
    final button = find.byTooltip('更多：菜单测试歌曲');
    final buttonCenter = tester.getCenter(button);
    await tester.tap(button);
    await tester.tapAt(buttonCenter);
    await tester.pumpAndSettle();
    expect(observer.popupPushes, 1);
    await tester.tapAt(const Offset(4, 100));
    await tester.pumpAndSettle();
    expect(find.text('下一首播放'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(observer.popupPushes, 2);
    expect(find.text('下一首播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion presents an anchored menu in its first frame',
      (tester) async {
    final observer = _RouteObserver();
    await _pump(tester,
        observer: observer,
        disableAnimations: true,
        child: Scaffold(body: Center(child: SongActionButton(song: _song))));
    await tester.tap(find.byTooltip('更多：菜单测试歌曲'));
    await tester.pump();
    expect(observer.lastPopup!.animation!.value, 1);
    expect(find.text('下一首播放').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion presents a bottom song menu in its first frame',
      (tester) async {
    final observer = _RouteObserver();
    await _pump(tester,
        observer: observer,
        disableAnimations: true,
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showSongActions(context, song: _song),
                child: const Text('打开菜单'),
              ),
            ),
          ),
        ));
    await tester.tap(find.text('打开菜单'));
    await tester.pump();
    expect(observer.lastPopup!.animation!.value, 1);
    expect(find.text('下一首播放').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion presents sleep timer choices in the first frame',
      (tester) async {
    final observer = _RouteObserver();
    await _pump(tester,
        observer: observer,
        disableAnimations: true,
        child: const SettingsView());
    await tester.scrollUntilVisible(find.text('睡眠定时'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('睡眠定时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡眠定时'));
    await tester.pump();
    expect(observer.lastPopup!.animation!.value, 1);
    expect(find.text('取消定时').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilding a song menu releases its transition listeners',
      (tester) async {
    final observer = _RouteObserver();
    await _pump(tester,
        observer: observer,
        child: Scaffold(body: Center(child: SongActionButton(song: _song))));
    await tester.tap(find.byTooltip('更多：菜单测试歌曲'));
    await tester.pumpAndSettle();
    final route = observer.lastPopup!;
    final animation = _TrackedAnimation();
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: rebuild,
        builder: (context, value, child) => route.buildTransitions(
          context,
          animation,
          const AlwaysStoppedAnimation<double>(0),
          const SizedBox.expand(),
        ),
      ),
    ));
    for (var i = 1; i <= 12; i++) {
      rebuild.value = i;
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(animation.statusListeners, isEmpty);
    expect(animation.valueListeners, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final anchored in [true, false]) {
    testWidgets(
        'song menu stays above keyboard with 2x text (anchor $anchored)',
        (tester) async {
      var removed = 0;
      await _pump(tester,
          size: const Size(320, 640),
          scale: 2,
          keyboard: 280,
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showSongActions(context,
                      song: _song,
                      anchor: anchored
                          ? const Rect.fromLTWH(266, 280, 40, 40)
                          : null,
                      onRemove: () => removed++),
                  child: const Text('打开菜单'),
                ),
              ),
            ),
          ));
      await tester.tap(find.text('打开菜单'));
      await tester.pumpAndSettle();
      final menuScroll = find.ancestor(
          of: find.text('下一首播放'), matching: find.byType(SingleChildScrollView));
      expect(tester.getRect(menuScroll).bottom, lessThanOrEqualTo(360));
      await tester.ensureVisible(find.text('从歌单移除'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('从歌单移除')).bottom, lessThanOrEqualTo(360));
      await tester.tap(find.text('从歌单移除'));
      await tester.pumpAndSettle();
      expect(removed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'import page keeps its heading and form usable at 320px and 2x text',
      (tester) async {
    await _pump(tester,
        size: const Size(320, 640),
        scale: 2,
        child: const PlaylistImportView());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(
        find.byType(TextField), 'https://example.com/playlist');
    expect(find.text('https://example.com/playlist'), findsOneWidget);
    await tester.ensureVisible(find.text('开始导入'));
    expect(find.text('开始导入').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('sleep timer options can be scrolled and selected at $size 2x',
        (tester) async {
      final timer = SleepTimer();
      await _pump(tester,
          size: size, scale: 2, timer: timer, child: const SettingsView());
      await tester.scrollUntilVisible(find.text('睡眠定时'), 180,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('睡眠定时'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('睡眠定时'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('90 分钟后暂停'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 分钟后暂停'));
      await tester.pumpAndSettle();
      expect(timer.isActive, isTrue);
      expect(timer.remaining!.inMinutes, greaterThanOrEqualTo(89));
      expect(find.text('90 分钟后暂停'), findsNothing);
      expect(tester.takeException(), isNull);
      timer.stop();
    });
  }
}

Future<void> _pump(WidgetTester tester,
    {required Widget child,
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
    bool disableAnimations = false,
    SleepTimer? timer,
    NavigatorObserver? observer}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  final settings = SettingsController();
  final player = PlayerController(settings: settings);
  final account = AuthController();
  final sleepTimer = timer ?? SleepTimer();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    player.dispose();
    settings.dispose();
    account.dispose();
    sleepTimer.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsController>.value(value: settings),
      ChangeNotifierProvider<PlayerController>.value(value: player),
      ChangeNotifierProvider<AuthController>.value(value: account),
      ChangeNotifierProvider<SleepTimer>.value(value: sleepTimer),
    ],
    child: MaterialApp(
      theme: AppTheme.forAccent('forestGreen', dark: false)
          .data
          .copyWith(platform: TargetPlatform.android),
      navigatorObservers: [if (observer != null) observer],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: disableAnimations,
          padding: EdgeInsets.only(top: 24, bottom: keyboard == 0 ? 24 : 0),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}

class _RouteObserver extends NavigatorObserver {
  int popupPushes = 0;
  PopupRoute<dynamic>? lastPopup;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) {
      popupPushes++;
      lastPopup = route;
    }
  }
}

class _TrackedAnimation extends Animation<double> {
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
