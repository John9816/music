import 'dart:async';

import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  for (final textScale in [1.0, 1.5]) {
    testWidgets('320 wide player keeps controls usable at $textScale text',
        (tester) async {
      await _pumpPlayer(tester, const Size(320, 700), textScale: textScale);

      expect(tester.takeException(), isNull);
      _expectVisibleTargets(tester, const Size(320, 700), [
        '收起播放器',
        '播放',
        '上一首',
        '下一首',
        '收藏歌曲',
        '随机播放',
        '不循环',
        'AirPlay 或蓝牙',
        '睡眠定时',
        '歌曲百科',
        '播放队列',
        '更多',
        '切换音质',
      ]);

      await tester.tap(find.byTooltip('播放'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('下一首'));
      await tester.pumpAndSettle();
      expect(find.text('第二首测试歌曲'), findsOneWidget);
      await tester.tap(find.byTooltip('上一首'));
      await tester.pumpAndSettle();
      expect(find.text('第一首测试歌曲'), findsOneWidget);
      await tester.tap(find.byTooltip('收藏歌曲'));
      await tester.pumpAndSettle();
      expect(find.text('请先登录后再收藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '812 landscape player separates cover and controls at '
        '$textScale text', (tester) async {
      await _pumpPlayer(tester, const Size(812, 375), textScale: textScale);

      expect(tester.takeException(), isNull);
      final cover = tester.getRect(find.byKey(const ValueKey('vinyl-disc')));
      final play = tester.getRect(find.byTooltip('播放'));
      expect(cover.right, lessThan(play.left));
      _expectVisibleTargets(tester, const Size(812, 375), [
        '播放',
        '上一首',
        '下一首',
        '收藏歌曲',
        '播放队列',
        '切换音质',
      ]);
      await tester.tap(find.byTooltip('播放'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('查看歌词'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
      expect(tester.getRect(find.byTooltip('暂停')), play);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('low portrait height can scroll to the playback queue',
      (tester) async {
    await _pumpPlayer(tester, const Size(320, 430), textScale: 1.5);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    _expectVisibleTargets(tester, const Size(320, 430), ['播放队列']);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭播放队列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotating the player keeps the selected lyrics page',
      (tester) async {
    await _pumpPlayer(tester, const Size(390, 844));
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();

    for (final size in [const Size(812, 375), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      final pages = tester.widget<PageView>(find.byType(PageView));
      expect(pages.controller!.page, 1);
      expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('shuffle exposes its changed state to accessibility',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPlayer(tester, const Size(390, 844));

      await tester.tap(find.byTooltip('随机播放'));
      await tester.pumpAndSettle();

      final node = tester.getSemantics(find.bySemanticsLabel('随机播放（已开启）'));
      expect(node.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byTooltip('随机播放'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final width in [1080.0, 720.0, 320.0]) {
    testWidgets('mini player respects $width local width in a desktop window',
        (tester) async {
      await _pumpPlayer(
        tester,
        const Size(1280, 800),
        miniWidth: width,
        textScale: 1.5,
        platform: TargetPlatform.macOS,
      );

      expect(tester.takeException(), isNull);
      final bar = tester.getRect(find.byType(MiniPlayer));
      for (final label in ['播放', '播放队列']) {
        final target = tester.getRect(find.byTooltip(label));
        expect(target.shortestSide, greaterThanOrEqualTo(44));
        expect(target.left, greaterThanOrEqualTo(bar.left));
        expect(target.right, lessThanOrEqualTo(bar.right));
      }
      await tester.tap(find.byTooltip('播放'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('播放队列'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭播放队列'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
        'wide mini player timeline supports keyboard seeking on '
        '${platform.name}', (tester) async {
      await _pumpPlayer(
        tester,
        const Size(1280, 800),
        miniWidth: 1080,
        platform: platform,
        textScale: 1.5,
      );

      final progress = find.bySemanticsLabel('播放进度');
      expect(progress, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(progress).height,
        greaterThanOrEqualTo(platform == TargetPlatform.macOS ? 28 : 44),
      );
      await tester.tap(progress);
      await tester.pumpAndSettle();
      expect(find.text('2:00'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('2:05'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectVisibleTargets(
  WidgetTester tester,
  Size size,
  List<String> labels,
) {
  final viewport = Offset.zero & size;
  for (final label in labels) {
    final target = tester.getRect(find.byTooltip(label));
    expect(target.shortestSide, greaterThanOrEqualTo(44), reason: label);
    expect(viewport.contains(target.topLeft), isTrue, reason: label);
    expect(viewport.contains(target.bottomRight), isTrue, reason: label);
  }
}

Future<void> _pumpPlayer(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  double? miniWidth,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  final player = _ResponsivePlayer(settings);
  final auth = AuthController();
  final timer = SleepTimer();
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  addTearDown(timer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ],
      child: MaterialApp(
        theme: AppTheme.byId('dark').data.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: miniWidth == null
            ? const PlayerView()
            : Scaffold(
                body: Center(
                  child: SizedBox(
                    width: miniWidth,
                    child: const MiniPlayer(sidebarWidth: 264),
                  ),
                ),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Native audio is outside a widget test; the UI still uses its real controls,
// subscriptions, routes, and queue while these deterministic tracks are played.
class _ResponsivePlayer extends PlayerController {
  _ResponsivePlayer(SettingsController settings) : super(settings: settings);

  static final _songs = [
    _song('first', '第一首测试歌曲'),
    _song('second', '第二首测试歌曲'),
  ];
  int _index = 0;
  bool _playing = false;
  Duration _position = const Duration(minutes: 1);
  final _positions = StreamController<Duration>.broadcast();

  @override
  Song get current => _songs[_index];

  @override
  List<Song> get queue => _songs;

  @override
  int get queueIndex => _index;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Duration get duration => const Duration(minutes: 4);

  @override
  String get lyric => '[00:00.00]一行用于检查布局的歌词\n[01:00.00]正在播放的歌词';

  @override
  Future<void> togglePlay() async {
    _playing = !_playing;
    notifyListeners();
  }

  @override
  Future<void> next() async {
    _index = (_index + 1) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> previous() async {
    _index = (_index - 1 + _songs.length) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    _position = value;
    _positions.add(value);
  }

  @override
  void dispose() {
    _positions.close();
    super.dispose();
  }
}

Song _song(String id, String name) => Song(
      id: id,
      name: name,
      source: 'netease',
      artists: const [Artist(id: 1, name: '测试歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: 240000,
    );
