import 'dart:async';

import 'package:duck_music/core/models/live_tv.dart';
import 'package:duck_music/core/player/playback_coordinator.dart';
import 'package:duck_music/features/live_tv/live_player_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _channel = LiveChannel(
  id: 'cctv1',
  name: 'CCTV1综合',
  groupName: '央视频道',
  lines: [
    LiveLine(
      id: 'line-1',
      name: '线路 1',
      uri: Uri.parse('http://stream.test/cctv1-a.m3u8?token=a'),
    ),
    LiveLine(
      id: 'line-2',
      name: '线路 2',
      uri: Uri.parse('https://stream.test/cctv1-b.m3u8?token=b'),
    ),
  ],
);

class _FakeLiveMediaSession implements LiveMediaSession {
  final StreamController<String> _errors =
      StreamController<String>.broadcast(sync: true);
  final List<Uri> openedUris = <Uri>[];
  final Set<Uri> failingUris = <Uri>{};
  bool playing = false;
  bool muted = false;
  bool disposed = false;
  int fullscreenToggleCount = 0;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  bool get isMuted => muted;

  @override
  bool get isPlaying => playing;

  @override
  Widget buildVideo({
    VoidCallback? onShowLines,
    VoidCallback? onPlaybackRequested,
  }) =>
      const ColoredBox(
        key: ValueKey('live-video-surface'),
        color: Colors.black,
      );

  @override
  Future<void> dispose() async {
    disposed = true;
    await _errors.close();
  }

  @override
  Future<void> open(Uri uri) async {
    openedUris.add(uri);
    if (failingUris.contains(uri)) throw StateError('open failed');
    playing = true;
  }

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> setMuted(bool value) async => muted = value;

  @override
  Future<void> toggleFullscreen() async => fullscreenToggleCount++;

  void emitError() => _errors.add('stream failed');
}

class _BlockingLiveMediaSession extends _FakeLiveMediaSession {
  final Completer<void> openStarted = Completer<void>();
  final Completer<void> releaseOpen = Completer<void>();

  @override
  Future<void> open(Uri uri) async {
    openedUris.add(uri);
    openStarted.complete();
    await releaseOpen.future;
    playing = true;
  }
}

class _CancellationAwareLiveMediaSession extends _FakeLiveMediaSession {
  final Completer<void> cancelStarted = Completer<void>();
  final Completer<void> releaseCancel = Completer<void>();
  late final StreamController<String> _controlledErrors =
      StreamController<String>.broadcast(
    onCancel: () async {
      cancelStarted.complete();
      await releaseCancel.future;
      cancelCompleted = true;
    },
  );
  bool cancelCompleted = false;
  bool disposedBeforeCancel = false;

  @override
  Stream<String> get errors => _controlledErrors.stream;

  @override
  Future<void> dispose() async {
    disposedBeforeCancel = !cancelCompleted;
    disposed = true;
  }

  Future<void> close() => _controlledErrors.close();
}

void main() {
  testWidgets('passes direct HTTP URI unchanged and fails over on open error',
      (tester) async {
    final session = _FakeLiveMediaSession()
      ..failingUris.add(_channel.lines.first.uri);

    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    expect(session.openedUris, [
      Uri.parse('http://stream.test/cctv1-a.m3u8?token=a'),
      Uri.parse('https://stream.test/cctv1-b.m3u8?token=b'),
    ]);
    expect(find.byKey(const ValueKey('live-video-surface')), findsOneWidget);
    expect(find.text('线路 2 / 2'), findsOneWidget);
  });

  testWidgets('advances once when the active stream reports a runtime error',
      (tester) async {
    final session = _FakeLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    session.emitError();
    await tester.pumpAndSettle();

    expect(session.openedUris, [_channel.lines[0].uri, _channel.lines[1].uri]);
    expect(find.text('线路 2 / 2'), findsOneWidget);
  });

  testWidgets('manual line selection starts a fresh cycle at that direct URI',
      (tester) async {
    final session = _FakeLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('player-live-line-line-2')));
    await tester.pumpAndSettle();

    expect(session.openedUris, [_channel.lines[0].uri, _channel.lines[1].uri]);
    expect(find.text('线路 2 / 2'), findsOneWidget);
  });

  testWidgets('shows exhaustion and retries a fresh cycle', (tester) async {
    final session = _FakeLiveMediaSession()
      ..failingUris.addAll(_channel.lines.map((line) => line.uri));
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('所有线路暂时不可用'), findsOneWidget);
    session.failingUris.clear();
    await tester.tap(find.byKey(const ValueKey('live-retry-lines')));
    await tester.pumpAndSettle();

    expect(session.openedUris, [
      _channel.lines[0].uri,
      _channel.lines[1].uri,
      _channel.lines[0].uri,
    ]);
    expect(find.byKey(const ValueKey('live-video-surface')), findsOneWidget);
  });

  testWidgets('play and mute controls update the direct media session',
      (tester) async {
    final session = _FakeLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
    expect(session.playing, isFalse);

    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(session.muted, isTrue);
  });

  testWidgets('opening live playback pauses another playback owner',
      (tester) async {
    final session = _FakeLiveMediaSession();
    final musicOwner = Object();
    var musicPauseCount = 0;
    final coordinator = PlaybackCoordinator.instance;
    coordinator.register(musicOwner, () async => musicPauseCount++);
    addTearDown(() => coordinator.unregister(musicOwner));

    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    expect(musicPauseCount, 1);
  });

  testWidgets('live player exposes fullscreen without seek controls',
      (tester) async {
    final session = _FakeLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing);
    final fullscreen = find.byKey(const ValueKey('live-fullscreen-button'));
    expect(fullscreen, findsOneWidget);

    await tester.tap(fullscreen);
    await tester.pump();
    expect(session.fullscreenToggleCount, 1);
  });

  testWidgets('fullscreen live controls show on tap and hide automatically',
      (tester) async {
    var routeCount = 0;
    var muteCount = 0;
    var playbackCount = 0;
    var fullscreenCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveVideoControls(
          fullscreen: true,
          isPlaying: true,
          isMuted: false,
          onShowLines: () => routeCount++,
          onToggleMuted: () => muteCount++,
          onTogglePlayback: () => playbackCount++,
          onToggleFullscreen: () => fullscreenCount++,
        ),
      ),
    ));

    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const ValueKey('live-video-controls-surface')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('live-video-route-button')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('live-video-controls-surface')));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('live-video-route-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-video-mute-button')), findsNothing);
    expect(
        find.byKey(const ValueKey('live-video-playback-button')), findsNothing);
    expect(find.byKey(const ValueKey('live-video-overlay-fullscreen-button')),
        findsOneWidget);

    final backButton = tester.getTopLeft(
      find.byKey(const ValueKey('live-video-overlay-fullscreen-button')),
    );
    expect(backButton.dx, lessThan(40));
    expect(backButton.dy, lessThan(40));

    await tester.tap(find.byKey(const ValueKey('live-video-route-button')));
    await tester.tap(
        find.byKey(const ValueKey('live-video-overlay-fullscreen-button')));
    expect(routeCount, 1);
    expect(muteCount, 0);
    expect(playbackCount, 0);
    expect(fullscreenCount, 1);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byKey(const ValueKey('live-video-route-button')), findsNothing);
    expect(find.byKey(const ValueKey('live-video-overlay-fullscreen-button')),
        findsNothing);
  });

  testWidgets('escape exits fullscreen live controls', (tester) async {
    var fullscreenCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveVideoControls(
          fullscreen: true,
          isPlaying: true,
          isMuted: false,
          onShowLines: () {},
          onToggleMuted: () {},
          onTogglePlayback: () {},
          onToggleFullscreen: () => fullscreenCount++,
        ),
      ),
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(fullscreenCount, 1);
  });

  testWidgets('waits for an in-flight open before disposing the media session',
      (tester) async {
    final session = _BlockingLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await session.openStarted.future;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(session.disposed, isFalse);

    session.releaseOpen.complete();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !session.disposed; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(session.disposed, isTrue);
  });

  testWidgets('waits for error cancellation before disposing the media session',
      (tester) async {
    final session = _CancellationAwareLiveMediaSession();
    await tester.pumpWidget(MaterialApp(
      home: LivePlayerView(
        channel: _channel,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await session.cancelStarted.future;
    expect(session.disposed, isFalse);

    session.releaseCancel.complete();
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100 && !session.disposed; attempt++) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    expect(session.disposed, isTrue);
    expect(session.disposedBeforeCancel, isFalse);
    await session.close();
  });
}
