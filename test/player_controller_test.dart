import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/player/audio_source_policy.dart';
import 'package:duck_music/core/config/audio_quality_policy.dart';
import 'package:duck_music/core/network/image_request_policy.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/player/last_playback_store.dart';
import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/playback_info.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/services/cache_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock platform channels used by SystemMediaController
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.751152.duckmusic/system_media'),
    (MethodCall methodCall) async {
      // Mock iOS system media channel
      return null;
    },
  );

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.751152.duckmusic/notifications'),
    (MethodCall methodCall) async {
      // Mock Android notification channel
      if (methodCall.method == 'areNotificationsEnabled') {
        return true;
      }
      return null;
    },
  );

  test('sleep at track end pauses without advancing queued songs', () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
        settings: settings,
        audioPlayer: native,
        musicApi: _FakePlaybackMusicApi(),
        localFileFor: (_) async => null,
        maintainAudioCache: (_) async {},
        lastPlaybackStore: _MemoryLastPlaybackStore());
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    await player.playQueue([
      _playbackSong('one', const Duration(minutes: 4)),
      _playbackSong('two', const Duration(minutes: 4))
    ]);
    var stopped = 0;
    await player.setStopAtTrackEnd(() => stopped++);
    native.completeTrack();
    await Future<void>.delayed(Duration.zero);
    expect(player.current!.id, 'one');
    expect(player.playing, isFalse);
    expect(stopped, 1);
    native.completeTrack();
    await Future<void>.delayed(Duration.zero);
    expect(stopped, 1);
    expect(player.current!.id, 'one');
  });

  test('sleep completion preserves a later seek when playback resumes',
      () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
        settings: settings,
        audioPlayer: native,
        musicApi: _FakePlaybackMusicApi(),
        localFileFor: (_) async => null,
        maintainAudioCache: (_) async {},
        lastPlaybackStore: _MemoryLastPlaybackStore());
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    await player.playQueue([_playbackSong('one', const Duration(minutes: 4))]);
    await player.setStopAtTrackEnd(() {});
    native.completeTrack();
    await Future<void>.delayed(Duration.zero);
    await player.seek(const Duration(minutes: 1));
    await player.togglePlay();
    expect(native.loadCount, 1);
    expect(player.position.inSeconds, 60);
    expect(player.playing, isTrue);
  });

  test('new sleep request survives prior completion cleanup', () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
        settings: settings,
        audioPlayer: native,
        musicApi: _FakePlaybackMusicApi(),
        localFileFor: (_) async => null,
        maintainAudioCache: (_) async {},
        lastPlaybackStore: _MemoryLastPlaybackStore());
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    await player.playQueue([_playbackSong('one', const Duration(minutes: 4))]);
    await player.cycleLoopMode();
    await player.cycleLoopMode();
    await player.setStopAtTrackEnd(() {});
    native.pauseGate = Completer<void>();
    native.completeTrack();
    await Future<void>.delayed(Duration.zero);
    await player.setStopAtTrackEnd(() {});
    native.pauseGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(native.nativeLoop, LoopMode.off);
  });

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

  test('a persistent native clock reset cannot create a fictional UI timeline',
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
    expect(positions.last, lessThan(pausedAt));
    expect((player.position - nativePlayer.position).inMilliseconds.abs(),
        lessThan(50));
  });

  test(
      'buffering and paused native seeks cannot keep a projected clock running',
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
    await player
        .playQueue([_playbackSong('buffer', const Duration(minutes: 4))]);
    await player.seek(const Duration(seconds: 70));
    nativePlayer.bufferAt(const Duration(milliseconds: 69900));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(player.position, const Duration(milliseconds: 69900));
    await player.pause();
    await nativePlayer.seek(const Duration(seconds: 20));
    expect(player.position, const Duration(seconds: 20));
    final positions = <Duration>[];
    final subscription = player.positionStream.listen(positions.add);
    addTearDown(subscription.cancel);
    nativePlayer.nextSeekResult = const Duration(milliseconds: 29980);
    await player.seek(const Duration(seconds: 30));
    expect(positions.last, nativePlayer.position,
        reason: 'A paused seek must report the actual resolved media position');
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

  test('resolved audio selects lyric identity, headers and duration metadata',
      () async {
    final api = _IdentityMusicApi({
      'selected': {
        'actualSource': 'kuwo',
        'actualId': 'recording',
        'lyricMatch': 'exact',
        'durationSec': 185,
      },
    });
    final native = _ControllableAudioPlayer(withNativeDuration: false);
    final settings = SettingsController();
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: api,
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    final handler = SystemMediaController()..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });
    final selected = _playbackSong('selected', const Duration(minutes: 3),
        source: 'netease');

    await player.playQueue([selected]);
    await Future<void>.delayed(Duration.zero);

    expect(player.current, same(selected));
    expect(api.lyricRequests, ['kuwo:recording']);
    expect(player.lyric, '[00:01.00]kuwo:recording');
    final source = native.lastSource! as UriAudioSource;
    expect(source.headers?['Referer'], 'https://www.kuwo.cn/');
    expect((source.tag as MediaItem).duration, const Duration(seconds: 185));
    expect(player.duration, const Duration(seconds: 185));
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 185));
  });

  test('clearing playback discards resolved audio duration and quality',
      () async {
    final settings = SettingsController();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(withNativeDuration: false),
      musicApi: _IdentityMusicApi({
        'selected': {
          'actualSource': 'kuwo',
          'actualId': 'recording',
          'lyricMatch': 'exact',
          'durationSec': 185
        },
      }),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });
    await player
        .playQueue([_playbackSong('selected', const Duration(minutes: 3))]);
    expect(player.duration, const Duration(seconds: 185));

    await player.stopAndClear();

    expect(player.current, isNull);
    expect(player.duration, isNull);
    expect(player.effectiveQuality, isNull);
    expect(player.lyric, isEmpty);
  });

  test('restore after clearing uses the restored song duration', () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer(withNativeDuration: false);
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: _IdentityMusicApi({
        'selected': {
          'actualSource': 'kuwo',
          'actualId': 'recording',
          'lyricMatch': 'exact',
          'durationSec': 185
        },
      }),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });
    await player
        .playQueue([_playbackSong('selected', const Duration(minutes: 3))]);
    await player.stopAndClear();
    final restored = _playbackSong('restored', const Duration(minutes: 2));

    await player.restoreLastPlayback(preferredLoader: () async => restored);

    expect(player.current, same(restored));
    expect(player.duration, const Duration(minutes: 2));
    expect(player.effectiveQuality, isNull);
    expect(player.lyric, isEmpty);
    expect(native.loadCount, 1);
  });

  test('failed audio load discards the resolved recording metadata', () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer(withNativeDuration: false)
      ..nextLoadError = StateError('decoder rejected source');
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: _IdentityMusicApi({
        'selected': {
          'actualSource': 'kuwo',
          'actualId': 'recording',
          'lyricMatch': 'exact',
          'durationSec': 185
        },
      }),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player
        .playQueue([_playbackSong('selected', const Duration(minutes: 3))]);

    expect(player.error, contains('decoder rejected source'));
    expect(player.duration, const Duration(minutes: 3));
    expect(player.effectiveQuality, isNull);
    expect(player.lyric, isEmpty);
  });

  test('late lyrics cannot repopulate metadata after playback fails', () async {
    final lyrics = Completer<String?>();
    final settings = SettingsController();
    final native = _ControllableAudioPlayer(withNativeDuration: false)
      ..nextPlayError = StateError('audio could not start');
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: _IdentityMusicApi({
        'selected': {
          'actualSource': 'kuwo',
          'actualId': 'recording',
          'lyricMatch': 'exact',
          'durationSec': 185
        },
      }, heldLyrics: {
        'kuwo:recording': lyrics
      }),
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });
    await player
        .playQueue([_playbackSong('selected', const Duration(minutes: 3))]);
    await Future<void>.delayed(Duration.zero);
    expect(player.error, contains('audio could not start'));

    lyrics.complete('[00:01.00]late lyrics');
    await Future<void>.delayed(Duration.zero);

    expect(player.lyric, isEmpty);
    expect(player.duration, const Duration(minutes: 3));
    expect(player.effectiveQuality, isNull);
  });

  test(
      'automatic audio cache persists identity and suppresses lyrics if metadata is lost',
      () async {
    final directory = await Directory.systemTemp.createTemp('player-cache-');
    final cache = CacheService.forTesting(
      temporaryDirectory: () async => directory,
      documentsDirectory: () async => directory,
    );
    final api = _IdentityMusicApi({
      'selected': {
        'actualSource': 'netease',
        'actualId': 'cached-recording',
        'lyricMatch': 'exact'
      },
    });
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: api,
      cacheService: cache,
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() async {
      player.dispose();
      settings.dispose();
      await directory.delete(recursive: true);
    });
    final song = _playbackSong('selected', const Duration(minutes: 3));
    await player.playQueue([song]);
    await Future<void>.delayed(Duration.zero);
    // ignore: experimental_member_use
    final source = native.lastSource! as LockCachingAudioSource;
    final cachedFile = await source.cacheFile;
    expect(source.headers?['Referer'], 'https://music.163.com/');
    expect((await cache.audioIdentityFor(cachedFile))?.id, 'cached-recording');
    expect(api.lyricRequests, ['netease:cached-recording']);

    cachedFile.writeAsBytesSync([1]);
    await File('${cachedFile.path}.identity.json').delete();
    await player.playAt(0);
    await Future<void>.delayed(Duration.zero);
    // ignore: experimental_member_use
    final reusedSource = native.lastSource! as LockCachingAudioSource;
    expect((await reusedSource.cacheFile).path, cachedFile.path);
    expect(player.lyric, isEmpty);
    expect(api.lyricRequests, ['netease:cached-recording']);
  });

  test(
      'unverified and legacy cross-source playback suppress synchronized lyrics',
      () async {
    final api = _IdentityMusicApi({
      'unverified': {
        'actualSource': 'qq',
        'actualId': 'candidate',
        'lyricMatch': 'unverified'
      },
      'legacy-cross': {'actualSource': 'kuwo'},
      'legacy-same': {},
    });
    final settings = SettingsController();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });
    await player.playQueue([
      for (final id in ['unverified', 'legacy-cross', 'legacy-same'])
        _playbackSong(id, const Duration(minutes: 3)),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(player.lyric, isEmpty);
    await player.next();
    await Future<void>.delayed(Duration.zero);
    expect(player.lyric, isEmpty);
    expect(api.lyricRequests, isEmpty);
    await player.next();
    await Future<void>.delayed(Duration.zero);
    expect(api.lyricRequests, ['qq:legacy-same']);
  });

  test(
      'late lyrics from the previous actual recording cannot overwrite the next song',
      () async {
    final oldLyrics = Completer<String?>();
    final api = _IdentityMusicApi({
      'first': {
        'actualSource': 'kuwo',
        'actualId': 'old-recording',
        'lyricMatch': 'exact'
      },
      'second': {
        'actualSource': 'kuwo',
        'actualId': 'new-recording',
        'lyricMatch': 'exact'
      },
    }, heldLyrics: {
      'kuwo:old-recording': oldLyrics
    });
    final settings = SettingsController();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localFileFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });
    await player.playQueue([
      _playbackSong('first', const Duration(minutes: 3)),
      _playbackSong('second', const Duration(minutes: 3)),
    ]);
    expect(api.lyricRequests, ['kuwo:old-recording']);
    await player.next();
    await Future<void>.delayed(Duration.zero);
    oldLyrics.complete('[00:01.00]stale lyrics');
    await Future<void>.delayed(Duration.zero);
    expect(api.lyricRequests, ['kuwo:old-recording', 'kuwo:new-recording']);
    expect(player.lyric, '[00:01.00]kuwo:new-recording');
  });

  test(
      'downloaded audio uses persisted identity and legacy files suppress lyrics',
      () async {
    final directory = await Directory.systemTemp.createTemp('player-local-');
    final file = File('${directory.path}/audio.mp3')..writeAsBytesSync([1]);
    final api = _IdentityMusicApi({});
    final settings = SettingsController();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localAudioFor: (song) async => LocalAudio(
        file: file,
        quality: 'exhigh',
        identity: song.id == 'known'
            ? const AudioIdentity(
                source: 'kuwo',
                id: 'saved-recording',
                lyricMatch: LyricMatch.exact)
            : const AudioIdentity(source: 'qq'),
      ),
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() async {
      player.dispose();
      settings.dispose();
      await directory.delete(recursive: true);
    });
    await player.playQueue([
      _playbackSong('known', const Duration(minutes: 3)),
      _playbackSong('legacy', const Duration(minutes: 3)),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(api.lyricRequests, ['kuwo:saved-recording']);
    await player.next();
    await Future<void>.delayed(Duration.zero);
    expect(player.lyric, isEmpty);
    expect(api.lyricRequests, ['kuwo:saved-recording']);
    expect(api.playRequests, isEmpty);
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

  test('system media does not republish unchanged queue or artwork', () async {
    final settings = SettingsController();
    final player = _SystemMediaPlayer(settings);
    final handler = SystemMediaController();
    var queueUpdates = 0;
    var mediaUpdates = 0;
    final queueSubscription = handler.queue.listen((_) => queueUpdates++);
    final mediaSubscription = handler.mediaItem.listen((_) => mediaUpdates++);
    handler.attach(player);
    await Future<void>.delayed(Duration.zero);
    addTearDown(() async {
      handler.detach(player);
      await queueSubscription.cancel();
      await mediaSubscription.cancel();
      player.dispose();
      settings.dispose();
    });

    final queueUpdatesAfterAttach = queueUpdates;
    final mediaUpdatesAfterAttach = mediaUpdates;

    player.notifyListeners();
    player.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    expect(queueUpdates, queueUpdatesAfterAttach);
    expect(mediaUpdates, mediaUpdatesAfterAttach);

    await handler.skipToNext();
    await Future<void>.delayed(Duration.zero);
    expect(queueUpdates, queueUpdatesAfterAttach);
    expect(mediaUpdates, mediaUpdatesAfterAttach + 1);
  });

  test('Android media notification uses vendor-compatible visuals', () {
    const config = SystemMediaController.androidConfig;

    expect(config.androidNotificationIcon, 'drawable/ic_notification_music');
    expect(config.notificationColor, const Color(0xFF2FD365));
    expect(config.artDownscaleWidth, 512);
    expect(config.artDownscaleHeight, 512);
  });

  test('notification permission preparation shares an in-flight request',
      () async {
    final gate = Completer<void>();
    var requestCount = 0;
    final handler = SystemMediaController(
      isAndroid: () => true,
      androidNotificationPermissionRequester: () {
        requestCount++;
        return gate.future;
      },
    );

    final first = handler.prepareForPlayback();
    final second = handler.prepareForPlayback();
    await Future<void>.delayed(Duration.zero);
    expect(requestCount, 1);
    expect(first, isNot(same(second)));

    gate.complete();
    await Future.wait([first, second]);
  });
}

Song _playbackSong(String id, Duration duration, {String source = 'qq'}) =>
    Song(
      id: id,
      name: id,
      source: source,
      artists: const [Artist(id: 1, name: '测试歌手')],
      album: const Album(id: 1, name: '测试专辑'),
      durationMs: duration.inMilliseconds,
    );

class _FakePlaybackMusicApi extends MusicApi {
  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async =>
      PlaybackInfo.fromJson(
        {'playUrl': 'https://media.example.com/$id.m4a'},
        id: id,
        source: source,
      );

  @override
  Future<String?> getLyric(String id,
          {String source = 'netease', bool requireVerified = false}) async =>
      id == 'second' ? '[01:15.00]第二首歌词\n[01:16.00]继续播放' : '[00:20.00]第一首歌词';
}

class _IdentityMusicApi extends MusicApi {
  _IdentityMusicApi(this.responses, {this.heldLyrics = const {}});
  final Map<String, Map<String, dynamic>> responses;
  final Map<String, Completer<String?>> heldLyrics;
  final List<String> lyricRequests = [];
  final List<String> playRequests = [];

  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async {
    expect(prefetch, isFalse);
    playRequests.add('$source:$id');
    return PlaybackInfo.fromJson({
      'playUrl': 'https://media.example.com/$id.mp3',
      ...?responses[id],
    }, id: id, source: source);
  }

  @override
  Future<String?> getLyric(String id,
      {String source = 'netease', bool requireVerified = false}) async {
    expect(requireVerified, isTrue);
    final key = '$source:$id';
    lyricRequests.add(key);
    return heldLyrics[key]?.future ?? Future.value('[00:01.00]$key');
  }
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
  _ControllableAudioPlayer({this.withNativeDuration = true});

  final bool withNativeDuration;
  AudioSource? lastSource;

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
  Duration? nextSeekResult;
  Object? nextLoadError;
  Object? nextPlayError;
  Completer<void>? pauseGate;
  LoopMode nativeLoop = LoopMode.off;
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

  void bufferAt(Duration position) {
    _positionAnchor = position;
    _processingState = ProcessingState.buffering;
    _emitEvent();
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    lastSource = source;
    loadCount++;
    _playing = false;
    _playingEvents.add(false);
    _processingState = ProcessingState.loading;
    _positionAnchor = initialPosition ?? Duration.zero;
    _emitEvent();
    final loadError = nextLoadError;
    nextLoadError = null;
    if (loadError != null) throw loadError;
    final heldLoad = _heldLoad;
    if (heldLoad != null && !heldLoad.isCompleted) {
      _heldLoadStarted?.complete();
      await heldLoad.future;
      _heldLoad = null;
      _heldLoadStarted = null;
    }
    _duration =
        withNativeDuration ? Duration(minutes: loadCount == 1 ? 3 : 4) : null;
    _durationEvents.add(_duration);
    _processingState = ProcessingState.ready;
    _positionAnchorTime = DateTime.now();
    _emitEvent();
    return _duration;
  }

  @override
  Future<void> play() async {
    final playError = nextPlayError;
    nextPlayError = null;
    if (playError != null) throw playError;
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
    await pauseGate?.future;
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
    _processingState = ProcessingState.ready;
    _positionAnchor = nextSeekResult ?? target;
    nextSeekResult = null;
    _positionAnchorTime = DateTime.now();
    _emitEvent();
  }

  void completeTrack() {
    _processingState = ProcessingState.completed;
    _emitEvent();
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    nativeLoop = mode;
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
