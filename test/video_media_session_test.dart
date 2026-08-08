import 'package:duck_music/core/api/video_api.dart';
import 'package:duck_music/core/models/video.dart';
import 'package:duck_music/core/services/video_history_service.dart';
import 'package:duck_music/features/videos/video_media_session.dart';
import 'package:duck_music/features/videos/video_player_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeVideoMediaSession implements VideoMediaSession {
  Uri? openedUri;
  Duration openedResumePosition = Duration.zero;
  Duration currentPosition = const Duration(minutes: 18);
  bool playing = false;
  int fullscreenToggleCount = 0;
  int disposeCount = 0;

  @override
  double get aspectRatio => 16 / 9;

  @override
  bool get isPlaying => playing;

  @override
  Duration get position => currentPosition;

  @override
  Widget buildVideo() => const ColoredBox(
        key: ValueKey('vod-video-surface'),
        color: Colors.black,
      );

  @override
  Future<void> dispose() async => disposeCount++;

  @override
  Future<void> open(
    Uri uri, {
    Duration resumePosition = Duration.zero,
  }) async {
    openedUri = uri;
    openedResumePosition = resumePosition;
    playing = true;
  }

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> toggleFullscreen() async => fullscreenToggleCount++;
}

class _RecordingVideoHistoryService extends VideoHistoryService {
  final List<VideoHistoryEntry> saved = [];

  @override
  Future<void> save(VideoHistoryEntry entry) async => saved.add(entry);
}

void main() {
  test('retains the native player only on macOS', () {
    expect(
      MediaKitVideoMediaSession.shouldRetainPlayerOn(TargetPlatform.macOS),
      isTrue,
    );
    expect(
      MediaKitVideoMediaSession.shouldRetainPlayerOn(TargetPlatform.android),
      isFalse,
    );
    expect(
      MediaKitVideoMediaSession.shouldRetainPlayerOn(TargetPlatform.iOS),
      isFalse,
    );
    expect(
      MediaKitVideoMediaSession.shouldRetainPlayerOn(TargetPlatform.windows),
      isFalse,
    );
  });

  testWidgets('VOD delegates resume fullscreen and disposal to media session',
      (tester) async {
    final session = _FakeVideoMediaSession();
    final history = _RecordingVideoHistoryService();
    const playback = VideoPlayback(
      videoId: 'video-42',
      episodeId: 'episode-3',
      lineId: 'line-2',
      playable: true,
      mediaUrl: 'https://cdn.example.com/video-42.m3u8',
      format: 'hls',
      sourceId: 'source-a',
    );

    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        api: VideoApi(),
        title: '测试影片',
        play: playback,
        source: 'source-a',
        resumePosition: const Duration(minutes: 12),
        historyService: history,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
        session.openedUri, Uri.parse('https://cdn.example.com/video-42.m3u8'));
    expect(session.openedResumePosition, const Duration(minutes: 12));
    expect(find.byKey(const ValueKey('vod-video-surface')), findsOneWidget);

    final fullscreen = find.byKey(const ValueKey('vod-fullscreen-button'));
    expect(fullscreen, findsOneWidget);
    await tester.tap(fullscreen);
    await tester.pump();
    expect(session.fullscreenToggleCount, 1);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(session.disposeCount, 1);
    expect(history.saved.last.position, const Duration(minutes: 18));
  });

  testWidgets('VOD fallback preserves the existing resume position',
      (tester) async {
    final session = _FakeVideoMediaSession()..currentPosition = Duration.zero;
    final history = _RecordingVideoHistoryService();
    const playback = VideoPlayback(
      videoId: 'video-42',
      episodeId: 'episode-3',
      lineId: 'line-2',
      playable: false,
      sourceId: 'source-a',
      message: '当前线路未提供直链',
    );

    await tester.pumpWidget(MaterialApp(
      home: VideoPlayerView(
        api: VideoApi(),
        title: '测试影片',
        play: playback,
        source: 'source-a',
        resumePosition: const Duration(minutes: 7),
        historyService: history,
        mediaSessionFactory: () => session,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(history.saved.last.position, const Duration(minutes: 7));
  });
}
