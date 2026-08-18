import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/player/audio_source_policy.dart';
import 'package:duck_music/core/config/audio_quality_policy.dart';
import 'package:duck_music/core/network/image_request_policy.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/player/last_playback_store.dart';
import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('position stream remains stable across UI rebuilds', () {
    final player = PlayerController(settings: SettingsController());
    addTearDown(player.dispose);

    expect(identical(player.positionStream, player.positionStream), isTrue);
  });

  test('position bridge survives UI listener gaps while audio keeps playing',
      () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      musicApi: _FakePlaybackMusicApi(),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('continuous', const Duration(minutes: 4)),
    ]);
    final firstPositions = <Duration>[];
    final firstSubscription = player.positionStream.listen(firstPositions.add);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    await firstSubscription.cancel();
    final positionBeforeGap = player.position;

    await Future<void>.delayed(const Duration(milliseconds: 240));
    final resumedPositions = <Duration>[];
    final resumedSubscription =
        player.positionStream.listen(resumedPositions.add);
    addTearDown(resumedSubscription.cancel);
    player.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 240));

    expect(firstPositions, isNotEmpty);
    expect(resumedPositions, isNotEmpty);
    expect(resumedPositions.last, greaterThan(positionBeforeGap));
    expect(player.playing, isTrue);
  });

  test('resume ignores a transient native jump to zero', () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      musicApi: _FakePlaybackMusicApi(),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    final positions = <Duration>[];
    final subscription = player.positionStream.listen(positions.add);
    addTearDown(() async {
      await subscription.cancel();
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('resume', const Duration(minutes: 4)),
    ]);
    await player.seek(const Duration(seconds: 70));
    await player.pause();
    final pausedAt = player.position;
    positions.clear();

    nativePlayer.reportZeroForReadsOnNextPlay(4);
    await player.togglePlay();
    expect(player.position, greaterThanOrEqualTo(pausedAt));
    await Future<void>.delayed(const Duration(milliseconds: 550));

    expect(positions, isNotEmpty);
    expect(positions, everyElement(greaterThanOrEqualTo(pausedAt)));
    expect(positions.last, greaterThan(pausedAt));
  });

  test('resume keeps advancing when the native clock restarts at zero',
      () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      musicApi: _FakePlaybackMusicApi(),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    final positions = <Duration>[];
    final subscription = player.positionStream.listen(positions.add);
    addTearDown(() async {
      await subscription.cancel();
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('restarted-clock', const Duration(minutes: 4)),
    ]);
    await player.seek(const Duration(seconds: 70));
    await player.pause();
    final pausedAt = player.position;
    positions.clear();

    nativePlayer.restartClockOnNextPlay();
    await player.togglePlay();
    await Future<void>.delayed(const Duration(milliseconds: 550));

    expect(nativePlayer.position, lessThan(const Duration(seconds: 2)));
    expect(positions, isNotEmpty);
    expect(positions, everyElement(greaterThanOrEqualTo(pausedAt)));
    expect(positions.last,
        greaterThan(pausedAt + const Duration(milliseconds: 350)));
  });

  test('startup restore prefers recent history without loading audio',
      () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final cached = _playbackSong('cached', const Duration(minutes: 2));
    final history = _playbackSong('history', const Duration(minutes: 3));
    final store = _MemoryLastPlaybackStore(cached);
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      lastPlaybackStore: store,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.restoreLastPlayback(preferredLoader: () async => history);
    await Future<void>.delayed(Duration.zero);

    expect(player.current?.id, 'history');
    expect(player.queue.map((song) => song.id), ['history']);
    expect(player.playing, isFalse);
    expect(player.position, Duration.zero);
    expect(nativePlayer.loadCount, 0);
    expect(store.saved?.id, 'history');
  });

  test('startup restore uses local snapshot only when history request fails',
      () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final cached = _playbackSong('cached', const Duration(minutes: 2));
    final store = _MemoryLastPlaybackStore(cached);
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      lastPlaybackStore: store,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.restoreLastPlayback(
      preferredLoader: () async => throw StateError('offline'),
    );

    expect(player.current?.id, 'cached');
    expect(nativePlayer.loadCount, 0);
  });

  test('empty account history does not restore a stale local song', () async {
    final settings = SettingsController();
    final store = _MemoryLastPlaybackStore(
      _playbackSong('cached', const Duration(minutes: 2)),
    );
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      lastPlaybackStore: store,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.restoreLastPlayback(preferredLoader: () async => null);

    expect(player.current, isNull);
    expect(store.cleared, isTrue);
  });

  test('late startup restore cannot replace a song selected by the user',
      () async {
    final settings = SettingsController();
    final history = Completer<Song?>();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: _FakePlaybackMusicApi(),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    final restore = player.restoreLastPlayback(
      preferredLoader: () => history.future,
    );
    final selected = _playbackSong('selected', const Duration(minutes: 4));
    await player.playQueue([selected]);
    history.complete(_playbackSong('history', const Duration(minutes: 3)));
    await restore;

    expect(player.current?.id, 'selected');
    expect(player.playing, isTrue);
  });

  test('rapid next and seek stay bound to the second native source', () async {
    final settings = SettingsController();
    final nativePlayer = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: nativePlayer,
      musicApi: _FakePlaybackMusicApi(),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
    );
    final positions = <Duration>[];
    final positionSub = player.positionStream.listen(positions.add);
    addTearDown(() async {
      await positionSub.cancel();
      player.dispose();
      settings.dispose();
    });

    final songs = [
      _playbackSong('first', const Duration(minutes: 3)),
      _playbackSong('second', const Duration(minutes: 4)),
    ];
    await player.playQueue(songs);

    await player.seek(const Duration(seconds: 20));
    nativePlayer.holdNextSeek();
    final oldSeek = player.seek(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(nativePlayer.seekRequests.last, const Duration(seconds: 30));

    nativePlayer.holdNextLoad();
    final switchToSecond = player.next();
    await Future<void>.delayed(Duration.zero);
    expect(player.current?.id, 'second');
    expect(player.loading, isTrue);
    expect(player.duration, const Duration(minutes: 4));

    // The UI can be tapped as soon as the second song is visible. This seek
    // must belong to the second source even though its decoder is not ready.
    await player.seek(const Duration(seconds: 75));
    nativePlayer.releaseHeldSeek();
    await oldSeek;
    await nativePlayer.waitForHeldLoad();
    expect(nativePlayer.loadCount, 2);
    nativePlayer.releaseHeldLoad();
    await switchToSecond;

    expect(nativePlayer.seekRequests, [
      const Duration(seconds: 20),
      const Duration(seconds: 30),
      const Duration(seconds: 75),
    ]);
    expect(player.position, greaterThanOrEqualTo(const Duration(seconds: 75)));
    await Future<void>.delayed(Duration.zero);
    expect(player.lyric, contains('第二首歌词'));

    final eventCountAfterSwitch = positions.length;
    await Future<void>.delayed(const Duration(milliseconds: 240));
    expect(positions.length, greaterThan(eventCountAfterSwitch));
    expect(positions.last, greaterThan(const Duration(seconds: 75)));
  });

  test('native platforms use native audio request headers', () {
    expect(usesNativeAudioHeaders(TargetPlatform.android), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.iOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.macOS), isTrue);
    expect(usesNativeAudioHeaders(TargetPlatform.windows), isFalse);
  });

  test('system media artwork uses a secure NetEase cover URL', () {
    expect(
      normalizeRemoteImageUrl(
        'http://p1.music.126.net/cover-id/playlist.jpg',
      ),
      'https://p1.music.126.net/cover-id/playlist.jpg',
    );
  });

  test('playback only requests qualities supported by the source', () {
    expect(
      playbackQualityCandidates('qq', 'hires'),
      ['exhigh'],
    );
    expect(
      playbackQualityCandidates('qq', 'lossless'),
      ['lossless'],
    );
    expect(
      playbackQualityCandidates('qq', 'auto'),
      ['exhigh'],
    );
    expect(
      playbackQualityCandidates('netease', 'hires'),
      ['hires'],
    );
    expect(
      qualityOptionsForSource('qq').map((option) => option.id),
      ['standard', 'exhigh', 'lossless'],
    );
    expect(defaultQualityForSource('qq'), 'exhigh');
  });

  test('QQ playback resolves one supported URL without serial preflight',
      () async {
    final requestedQualities = <String>[];

    final resolved = await resolvePlaybackUrl(
      source: 'qq',
      requestedQuality: 'hires',
      loadUrl: (quality) async {
        requestedQualities.add(quality);
        return 'https://media.example.com/song.m4a';
      },
    );

    expect(requestedQualities, ['exhigh']);
    expect(resolved?.url, 'https://media.example.com/song.m4a');
    expect(resolved?.quality, 'exhigh');
  });

  test('system media controls expose and execute previous and next', () async {
    final settings = SettingsController();
    final player = _SystemMediaPlayer(settings);
    final handler = SystemMediaController()..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });

    final actions = handler.playbackState.value.controls
        .map((control) => control.action)
        .toList();
    expect(actions, contains(MediaAction.skipToPrevious));
    expect(actions, contains(MediaAction.skipToNext));
    expect(handler.queue.value, hasLength(3));
    expect(handler.playbackState.value.queueIndex, 1);
    expect(
      handler.mediaItem.value?.artUri.toString(),
      'https://p1.music.126.net/cover-id/system.jpg',
    );
    expect(
      handler.mediaItem.value?.artHeaders?['Referer'],
      'https://music.163.com/',
    );

    await handler.skipToNext();
    expect(player.queueIndex, 2);
    expect(handler.mediaItem.value?.title, '第三首');

    await handler.skipToPrevious();
    expect(player.queueIndex, 1);
    expect(handler.mediaItem.value?.title, '第二首');
  });

  test('single-song system media keeps previous and next controls', () async {
    final settings = SettingsController();
    final player = _SystemMediaPlayer(settings)..keepOnlyCurrentSong();
    final handler = SystemMediaController()..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });

    expect(
      handler.playbackState.value.controls
          .map((control) => control.action)
          .toList(),
      [
        MediaAction.skipToPrevious,
        MediaAction.pause,
        MediaAction.skipToNext,
      ],
    );
    expect(
      handler.playbackState.value.androidCompactActionIndices,
      [0, 1, 2],
    );

    await handler.skipToPrevious();
    expect(player.queueIndex, 0);
    expect(handler.mediaItem.value?.title, '第二首');

    await handler.skipToNext();
    expect(player.queueIndex, 0);
    expect(handler.mediaItem.value?.title, '第二首');
  });

  test('system media requests Android notification permission once', () async {
    final settings = SettingsController();
    final player = _SystemMediaPlayer(settings);
    var requestCount = 0;
    final handler = SystemMediaController(
      isAndroid: () => true,
      androidNotificationPermissionRequester: () async {
        requestCount++;
      },
    )..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });

    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);

    player.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);
  });

  test('Android media notification uses vendor-compatible visuals', () {
    const config = SystemMediaController.androidConfig;

    expect(config.androidNotificationIcon, 'drawable/ic_notification_music');
    expect(config.notificationColor, const Color(0xFF2FD365));
    expect(config.artDownscaleWidth, 512);
    expect(config.artDownscaleHeight, 512);
  });
}

Song _playbackSong(String id, Duration duration) => Song(
      id: id,
      name: id,
      source: 'qq',
      artists: const [Artist(id: 1, name: '测试歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: duration.inMilliseconds,
    );

class _FakePlaybackMusicApi extends MusicApi {
  @override
  Future<String?> getSongUrl(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
  }) async =>
      'https://media.example.com/$id.m4a';

  @override
  Future<String?> getLyric(String id, {String source = 'netease'}) async =>
      id == 'second' ? '[01:15.00]第二首歌词\n[01:16.00]继续播放' : '[00:20.00]第一首歌词';
}

class _MemoryLastPlaybackStore implements LastPlaybackStore {
  _MemoryLastPlaybackStore([this.cached]);

  Song? cached;
  Song? saved;
  bool cleared = false;

  @override
  Future<Song?> load() async => cached;

  @override
  Future<void> save(Song song) async {
    cached = song;
    saved = song;
  }

  @override
  Future<void> clear() async {
    cached = null;
    cleared = true;
  }
}

class _ControllableAudioPlayer extends AudioPlayer {
  _ControllableAudioPlayer();

  final _events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final _playingEvents = StreamController<bool>.broadcast(sync: true);
  final _durationEvents = StreamController<Duration?>.broadcast(sync: true);
  final List<Duration> seekRequests = [];

  bool _playing = false;
  ProcessingState _processingState = ProcessingState.idle;
  Duration? _duration;
  Duration _positionAnchor = Duration.zero;
  DateTime _positionAnchorTime = DateTime.now();
  Completer<void>? _heldSeek;
  Completer<void>? _heldLoad;
  Completer<void>? _heldLoadStarted;
  int _zeroReadsOnNextPlay = 0;
  int _remainingZeroReads = 0;
  bool _restartClockOnNextPlay = false;
  int loadCount = 0;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;

  @override
  Stream<bool> get playingStream => _playingEvents.stream;

  @override
  Stream<Duration?> get durationStream => _durationEvents.stream;

  // Deliberately emits no periodic values. PlayerController's native-position
  // watchdog must keep UI progress alive when a platform stream goes quiet.
  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState => _processingState;

  @override
  Duration? get duration => _duration;

  @override
  Duration get position {
    if (_remainingZeroReads > 0) {
      _remainingZeroReads--;
      return Duration.zero;
    }
    if (!_playing || _processingState != ProcessingState.ready) {
      return _positionAnchor;
    }
    final advanced =
        _positionAnchor + DateTime.now().difference(_positionAnchorTime);
    final total = _duration;
    return total != null && advanced > total ? total : advanced;
  }

  void holdNextSeek() => _heldSeek = Completer<void>();

  void releaseHeldSeek() => _heldSeek?.complete();

  void holdNextLoad() {
    _heldLoad = Completer<void>();
    _heldLoadStarted = Completer<void>();
  }

  Future<void> waitForHeldLoad() => _heldLoadStarted!.future;

  void releaseHeldLoad() => _heldLoad?.complete();

  void reportZeroForReadsOnNextPlay(int reads) {
    _zeroReadsOnNextPlay = reads;
  }

  void restartClockOnNextPlay() {
    _restartClockOnNextPlay = true;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loadCount++;
    _playing = false;
    _playingEvents.add(false);
    _processingState = ProcessingState.loading;
    _positionAnchor = initialPosition ?? Duration.zero;
    _emitEvent();
    final heldLoad = _heldLoad;
    if (heldLoad != null && !heldLoad.isCompleted) {
      _heldLoadStarted?.complete();
      await heldLoad.future;
      _heldLoad = null;
      _heldLoadStarted = null;
    }
    _duration = Duration(minutes: loadCount == 1 ? 3 : 4);
    _durationEvents.add(_duration);
    _processingState = ProcessingState.ready;
    _positionAnchorTime = DateTime.now();
    _emitEvent();
    return _duration;
  }

  @override
  Future<void> play() async {
    _positionAnchor = position;
    if (_restartClockOnNextPlay) {
      _positionAnchor = Duration.zero;
      _restartClockOnNextPlay = false;
    }
    _positionAnchorTime = DateTime.now();
    _playing = true;
    _remainingZeroReads = _zeroReadsOnNextPlay;
    _zeroReadsOnNextPlay = 0;
    _playingEvents.add(true);
    _emitEvent();
  }

  @override
  Future<void> pause() async {
    _positionAnchor = position;
    _playing = false;
    _playingEvents.add(false);
    _emitEvent();
  }

  @override
  Future<void> stop() async {
    _positionAnchor = position;
    _playing = false;
    _playingEvents.add(false);
    _processingState = ProcessingState.idle;
    _emitEvent();
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    final target = position ?? Duration.zero;
    seekRequests.add(target);
    final heldSeek = _heldSeek;
    if (heldSeek != null && !heldSeek.isCompleted) {
      await heldSeek.future;
      _heldSeek = null;
    }
    _positionAnchor = target;
    _positionAnchorTime = DateTime.now();
    _emitEvent();
  }

  void _emitEvent() {
    _events.add(
      PlaybackEvent(
        processingState: _processingState,
        updatePosition: position,
        bufferedPosition: position,
        duration: _duration,
        currentIndex: 0,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _events.close();
    await _playingEvents.close();
    await _durationEvents.close();
  }
}

class _SystemMediaPlayer extends PlayerController {
  _SystemMediaPlayer(SettingsController settings) : super(settings: settings);

  final List<Song> _songs = [
    Song(
      id: 'one',
      name: '第一首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(
        id: 1,
        name: '测试专辑',
        picUrl: 'http://p1.music.126.net/cover-id/system.jpg',
      ),
      durationMs: 180000,
    ),
    Song(
      id: 'two',
      name: '第二首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(
        id: 1,
        name: '测试专辑',
        picUrl: 'http://p1.music.126.net/cover-id/system.jpg',
      ),
      durationMs: 180000,
    ),
    Song(
      id: 'three',
      name: '第三首',
      source: 'netease',
      artists: const [Artist(id: 1, name: '歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: 180000,
    ),
  ];
  int _currentIndex = 1;
  bool _isPlaying = true;
  Duration _position = const Duration(seconds: 12);

  void keepOnlyCurrentSong() {
    final song = _songs[_currentIndex];
    _songs
      ..clear()
      ..add(song);
    _currentIndex = 0;
  }

  @override
  List<Song> get queue => _songs;

  @override
  int get queueIndex => _currentIndex;

  @override
  Song get current => _songs[_currentIndex];

  @override
  bool get playing => _isPlaying;

  @override
  Duration get position => _position;

  @override
  Future<void> next() async {
    _currentIndex = (_currentIndex + 1) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> previous() async {
    _currentIndex = (_currentIndex - 1 + _songs.length) % _songs.length;
    notifyListeners();
  }

  @override
  Future<void> playAt(int index) async {
    _currentIndex = index;
    notifyListeners();
  }

  @override
  Future<void> togglePlay() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    notifyListeners();
  }
}
