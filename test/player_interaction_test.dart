import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Future<http.Response> Function(http.Request) _handleRequest;

void main() {
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) => _handleRequest(request)),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    _handleRequest = (_) async => _response(const {'items': []});
  });

  testWidgets('top drag follows the finger and returns below the threshold',
      (tester) async {
    await _pumpPlayer(tester, route: true);
    final cover = find.byKey(const ValueKey('vinyl-tonearm'));
    final originalTop = tester.getTopLeft(cover).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('正在播放')),
    );

    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 52));
    await tester.pump();
    expect(tester.getTopLeft(cover).dy, greaterThan(originalTop + 40));

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsOneWidget);
    expect(tester.getTopLeft(cover).dy, closeTo(originalTop, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deliberate downward drag dismisses the player route',
      (tester) async {
    await _pumpPlayer(tester, route: true);
    await tester.dragFrom(
      tester.getCenter(find.text('正在播放')),
      const Offset(0, 210),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlayerView), findsNothing);
    expect(find.text('Open player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyrics scroll and progress scrubbing keep the player open',
      (tester) async {
    final harness = await _pumpPlayer(tester, route: true);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    final closeTop = tester.getTopLeft(find.byTooltip('收起播放器'));

    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byTooltip('收起播放器')), closeTop);
    expect(find.byType(PlayerView), findsOneWidget);

    final progress = tester.getRect(find.byType(GProgressBar));
    await tester.dragFrom(
      Offset(progress.left + 20, progress.center.dy),
      Offset(progress.width * 0.55, 0),
    );
    await tester.pumpAndSettle();
    expect(harness.player.soughtTo, isNotNull);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps a playing vinyl stationary',
      (tester) async {
    await _pumpPlayer(tester, playing: true, reducedMotion: true);
    final disc = tester.widget<RotationTransition>(
      find.byKey(const ValueKey('vinyl-disc')),
    );
    final initialRotation = disc.turns.value;
    await tester.pump(const Duration(seconds: 2));

    expect(disc.turns.value, initialRotation);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused queue equalizer does not keep animating', (tester) async {
    final harness = await _pumpPlayer(tester, playing: true);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final equalizer = _equalizerAnimation(tester);
    expect(equalizer.isAnimating, isTrue);

    harness.player.setPlaying(false);
    await tester.pump();

    expect(equalizer.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue equalizer stops when reduced motion is enabled',
      (tester) async {
    await _pumpPlayer(tester, playing: true, reducedMotion: true);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_equalizerAnimation(tester).isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same song id from another source resets the lyrics page',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);

    harness.player.replaceCurrent(_song(source: 'qq'));
    await tester.pumpAndSettle();

    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.controller!.page, 0);
    expect(find.byKey(const ValueKey('cover-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late favorite response cannot like the replacement song',
      (tester) async {
    final mutation = Completer<http.Response>();
    var favoriteLoads = 0;
    String? submittedSource;
    _handleRequest = (request) async {
      if (request.method == 'POST') {
        submittedSource = (jsonDecode(request.body) as Map)['source'] as String;
        return mutation.future;
      }
      favoriteLoads++;
      return _response(const {'items': []});
    };
    final harness = await _pumpPlayer(tester, loggedIn: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await tester.pump();
    expect(submittedSource, 'netease');

    harness.player.replaceCurrent(_song(source: 'qq'));
    await tester.pump();
    mutation.complete(_response(const {}));
    await tester.pumpAndSettle();

    expect(harness.player.current.source, 'qq');
    expect(harness.player.liked, isFalse);
    expect(find.byIcon(Icons.favorite_outline_rounded), findsOneWidget);
    expect(favoriteLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyrics follow the current line again after scrolling stops',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final initialOffset = list.controller!.offset;

    await tester.drag(find.byType(ListView), const Offset(0, -170));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(initialOffset + 100));
    expect(find.text('回到当前'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(list.controller!.offset, closeTo(initialOffset, 0.5));
    expect(find.text('回到当前'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return to current realigns lyrics even within the same line',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final initialOffset = list.controller!.offset;

    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到当前'));
    await tester.pumpAndSettle();

    expect(list.controller!.offset, closeTo(initialOffset, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue sheet expands before scrolling the queue independently',
      (tester) async {
    await _pumpPlayer(tester, queueLength: 30);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    final sheetFinder = find.byType(DraggableScrollableSheet);
    expect(sheetFinder, findsOneWidget);
    final initialHeight = tester.getSize(sheetFinder).height;
    final scroll = find.descendant(
      of: sheetFinder,
      matching: find.byType(Scrollable),
    );

    await tester.drag(scroll, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheetFinder).height, greaterThan(initialHeight));
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
        tester.state<ScrollableState>(scroll).position.pixels, greaterThan(0));
    expect(find.byTooltip('关闭播放队列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final queueLength in [0, 1]) {
    testWidgets('queue with $queueLength tracks still expands and dismisses',
        (tester) async {
      await _pumpPlayer(tester, queueLength: queueLength);
      await tester.tap(find.byTooltip('播放队列'));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      final initialHeight = tester.getSize(sheet).height;
      final scroll = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );

      await tester.drag(scroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, greaterThan(initialHeight));

      await tester.drag(scroll, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320 wide mini player fits large text and Android touch targets',
      (tester) async {
    await _pumpPlayer(
      tester,
      mini: true,
      size: const Size(320, 700),
      textScale: 2,
    );

    expect(tester.getSize(find.byType(MiniPlayer)).height, 56);
    expect(
      tester
          .getSize(
              find.byKey(const ValueKey('mobile-mini-player-progress-fill')))
          .height,
      3,
    );
    expect(find.byTooltip('上一首'), findsNothing);
    for (final label in ['播放', '下一首', '播放队列']) {
      final button = tester.getRect(find.byTooltip(label));
      expect(button.shortestSide, greaterThanOrEqualTo(48));
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(320));
    }
    final title = tester.getRect(find.textContaining('Test song same-id'));
    final disc = tester.getRect(
      find.byKey(const ValueKey('mobile-mini-player-disc')),
    );
    expect(title.width, greaterThanOrEqualTo(90));
    expect(disc.width, 54);
    expect(title.left, greaterThanOrEqualTo(disc.right));
    expect(title.right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('播放')).left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow mini player keeps play and queue targets on both platforms',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await _pumpPlayer(
        tester,
        mini: true,
        size: const Size(280, 700),
        textScale: 2,
        platform: platform,
      );

      expect(find.byTooltip('上一首'), findsNothing);
      expect(find.byTooltip('下一首'), findsNothing);
      final minimumTarget = platform == TargetPlatform.android ? 48 : 44;
      for (final label in ['播放', '播放队列']) {
        expect(
          tester.getSize(find.byTooltip(label)).shortestSide,
          greaterThanOrEqualTo(minimumTarget),
        );
      }
      expect(
        tester.getSize(find.textContaining('Test song same-id')).width,
        greaterThanOrEqualTo(100),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'mini player keeps controls in place during track and state changes',
      (tester) async {
    final harness = await _pumpPlayer(tester, mini: true);
    final size = tester.getSize(find.byType(MiniPlayer));
    final queuePosition = tester.getCenter(find.byTooltip('播放队列'));
    harness.player
        .replaceCurrent(_song(source: 'qq', name: 'A much longer title'));
    harness.player.setPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.getSize(find.byType(MiniPlayer)), size);
    expect(tester.getCenter(find.byTooltip('播放队列')), queuePosition);
    await tester.pumpAndSettle();
    expect(find.byIcon(cupertino.CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

AnimationController _equalizerAnimation(WidgetTester tester) {
  return tester
      .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
      .map((widget) => widget.animation)
      .whereType<AnimationController>()
      .singleWhere(
        (controller) =>
            controller.duration == const Duration(milliseconds: 800),
      );
}

http.Response _response(Map<String, dynamic> data) => http.Response(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: const {'content-type': 'application/json'},
    );

Future<_PlayerHarness> _pumpPlayer(
  WidgetTester tester, {
  bool route = false,
  bool playing = false,
  bool reducedMotion = false,
  bool loggedIn = false,
  bool mini = false,
  int queueLength = 1,
  Size size = const Size(390, 844),
  double textScale = 1,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  final player = _InteractionPlayer(settings, queueLength: queueLength)
    ..setPlaying(playing);
  final auth = _InteractionAuth(loggedIn);
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
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: mini
            ? const Scaffold(body: Align(child: MiniPlayer()))
            : route
                ? Builder(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            buildPlayerRoute(reducedMotion: reducedMotion),
                          ),
                          child: const Text('Open player'),
                        ),
                      ),
                    ),
                  )
                : const PlayerView(),
      ),
    ),
  );
  if (route) {
    await tester.tap(find.text('Open player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump();
  return _PlayerHarness(player);
}

class _PlayerHarness {
  const _PlayerHarness(this.player);

  final _InteractionPlayer player;
}

class _InteractionAuth extends AuthController {
  _InteractionAuth(this.loggedIn);

  final bool loggedIn;

  @override
  String? get token => loggedIn ? 'interaction-token' : null;
}

class _InteractionPlayer extends PlayerController {
  _InteractionPlayer(SettingsController settings, {required int queueLength})
      : _queue = List.generate(queueLength, (index) => _song(id: '$index')),
        super(settings: settings);

  final List<Song> _queue;
  Song _current = _song();
  bool _playing = false;
  Duration? soughtTo;

  @override
  Song get current => _current;

  @override
  List<Song> get queue => _queue;

  @override
  int get queueIndex => 0;

  @override
  bool get loading => false;

  @override
  bool get playing => _playing;

  @override
  Duration get position => const Duration(seconds: 60);

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Duration get duration => const Duration(minutes: 4);

  @override
  String get lyric => List.generate(
        24,
        (index) => '[${(index ~/ 6).toString().padLeft(2, '0')}:'
            '${(index % 6 * 10).toString().padLeft(2, '0')}.00]Lyric line $index',
      ).join('\n');

  void replaceCurrent(Song song) {
    _current = song;
    notifyListeners();
  }

  void setPlaying(bool value) {
    _playing = value;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    soughtTo = position;
  }
}

Song _song({String id = 'same-id', String source = 'netease', String? name}) =>
    Song(
      id: id,
      name: name ?? 'Test song $id',
      source: source,
      artists: const [Artist(id: 1, name: 'Test artist')],
      album: const Album(id: 1, name: 'Test album'),
      durationMs: 240000,
    );
