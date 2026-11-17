import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/music_api.dart';
import 'package:duck_music/core/player/audio_source_policy.dart';
import 'package:duck_music/core/config/audio_quality_policy.dart';
import 'package:duck_music/core/network/image_request_policy.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/player/source_fallback_resolver.dart';
import 'package:duck_music/core/services/artwork_color_service.dart';
import 'package:duck_music/core/player/last_playback_store.dart';
import 'package:duck_music/core/player/system_media_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/models/playback_info.dart';
import 'package:duck_music/core/services/song_download_service.dart';
import 'package:duck_music/core/services/cache_service.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets(
      'cold black audio remains loading after twenty seconds and can complete',
      (tester) async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer()..holdNextLoad();
    final player = PlayerController(
        settings: settings,
        audioPlayer: native,
        musicApi: _FakePlaybackMusicApi(),
        localFileFor: (_) async => null,
        maintainAudioCache: (_) async {},
        lastPlaybackStore: _MemoryLastPlaybackStore());
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    final pending = player.playQueue(
        [_playbackSong('cold', const Duration(minutes: 3), source: 'qishui')]);
    await tester.pump();
    await tester.pump(const Duration(seconds: 22));
    expect(player.loading, isTrue);
    expect(player.error, isNull);
    native.releaseHeldLoad();
    await tester.pump();
    await pending;
    expect(player.playing, isTrue);
    expect(player.error, isNull);
    await player.pause();
  });

  test(
      'feed continuation appends without restarting and manual queue invalidates a pending page',
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
    await player.playQueue([_playbackSong('a', const Duration(minutes: 3))]);
    final generation = player.queueGeneration;
    player.appendQueue([
      _playbackSong('a', const Duration(minutes: 3)),
      _playbackSong('b', const Duration(minutes: 3))
    ], generation: generation);
    expect(player.queue.map((s) => s.id), ['a', 'b']);
    expect(native.loadCount, 1);
    final pending = Completer<bool>();
    await player.next();
    player.loadMoreQueue = () => pending.future;
    final next = player.next();
    await player
        .playQueue([_playbackSong('manual', const Duration(minutes: 3))]);
    player.appendQueue([_playbackSong('stale', const Duration(minutes: 3))],
        generation: generation);
    pending.complete(true);
    await next;
    expect(player.current!.id, 'manual');
    expect(player.queue.map((s) => s.id), ['manual']);
  });

  test('playback modes cycle list, single, shuffle without conflicting flags',
      () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(settings: settings, audioPlayer: native);
    addTearDown(player.dispose);
    addTearDown(settings.dispose);
    expect(player.loopMode, LoopMode.all);
    expect(player.shuffle, isFalse);
    await player.cycleLoopMode();
    expect(player.loopMode, LoopMode.one);
    expect(player.shuffle, isFalse);
    expect(native.nativeLoop, LoopMode.one);
    await player.cycleLoopMode();
    expect(player.shuffle, isTrue);
    expect(player.loopMode, LoopMode.all);
    expect(native.nativeLoop, LoopMode.off);
    await player.cycleLoopMode();
    expect(player.shuffle, isFalse);
    expect(player.loopMode, LoopMode.all);
    expect(native.nativeLoop, LoopMode.off);
  });

  test(
      'system repeat and shuffle report their actual state and preserve the three-mode cycle',
      () async {
    final settings = SettingsController();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(settings: settings, audioPlayer: native);
    final handler = SystemMediaController()..attach(player);
    addTearDown(() {
      handler.detach(player);
      player.dispose();
      settings.dispose();
    });
    await handler.setRepeatMode(AudioServiceRepeatMode.none);
    expect(player.playbackMode, PlaybackMode.sequential);
    expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.none);
    await player.cyclePlaybackMode();
    expect(player.playbackMode, PlaybackMode.listLoop);
    await handler.setShuffleMode(AudioServiceShuffleMode.all);
    expect(
        handler.playbackState.value.shuffleMode, AudioServiceShuffleMode.all);
    await handler.setRepeatMode(AudioServiceRepeatMode.one);
    expect(player.playbackMode, PlaybackMode.singleLoop);
    expect(
        handler.playbackState.value.shuffleMode, AudioServiceShuffleMode.none);
    await handler.setShuffleMode(AudioServiceShuffleMode.none);
    expect(player.playbackMode, PlaybackMode.singleLoop);
  });

  test('system repeat-none stops at the end of the queue', () async {
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
    await player.playQueue([_playbackSong('last', const Duration(minutes: 3))]);
    await player.setPlaybackMode(PlaybackMode.sequential);
    native.completeTrack();
    await Future<void>.delayed(Duration.zero);
    expect(player.current!.id, 'last');
    expect(player.playing, false);
    expect(native.loadCount, 1);
  });

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
    final config = SystemMediaController.androidConfig;

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

  // --- 安卓切歌加速：下一首预取 + 不可播自动跳过 ---

  test('playing a song prefetches the next one via prefetch flag', () async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    final api = _ScriptedMusicApi();
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('first', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('second', const Duration(minutes: 3), source: 'netease'),
    ]);
    // 让后台预取的异步链完成。
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(api.playRequests, ['first']);
    expect(api.prefetchRequests, ['second']);
  });

  test('advancing to a prefetched song reuses the resolved url', () async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    final api = _ScriptedMusicApi();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('first', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('second', const Duration(minutes: 3), source: 'netease'),
    ]);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await player.next();
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(player.current!.id, 'second');
    // 切到第二首应命中预取缓存，不再产生一次真实解析请求。
    expect(api.playRequests, ['first']);
    // 第二首曾被预热解析过（队尾绕回的下一首预取属于正常行为，不影响断言）。
    expect(api.prefetchRequests, contains('second'));
  });

  testWidgets('an unplayable song is skipped so the next song starts',
      (tester) async {
    final settings = SettingsController();
    final api = _ScriptedMusicApi(errors: {
      'bad': ApiException('模拟解析失败'),
    });
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
      _playbackSong('bad', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('good', const Duration(minutes: 3), source: 'netease'),
    ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    // 350ms 延时后应自动切到下一首并清除错误。
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(player.current!.id, 'good');
    expect(player.error, isNull);
    expect(api.playRequests, ['bad', 'good']);
  });

  testWidgets('membership errors stay visible and never auto-skip',
      (tester) async {
    final settings = SettingsController();
    final api = _ScriptedMusicApi(errors: {
      'vip': ApiException('需要会员', statusCode: 403),
    });
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
      _playbackSong('vip', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('good', const Duration(minutes: 3), source: 'netease'),
    ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(player.current!.id, 'vip');
    expect(player.errorKind, PlaybackErrorKind.membershipRequired);
    expect(player.error, contains('会员'));
  });

  testWidgets('a single unplayable song keeps its error visible',
      (tester) async {
    final settings = SettingsController();
    final api = _ScriptedMusicApi(errors: {
      'only': ApiException('模拟解析失败'),
    });
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
      _playbackSong('only', const Duration(minutes: 3), source: 'netease'),
    ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(player.current!.id, 'only');
    expect(player.error, isNotNull);
  });

  testWidgets('auto-skip can be turned off', (tester) async {
    final settings = SettingsController();
    await settings.setAutoSkipUnplayable(false);
    final api = _ScriptedMusicApi(errors: {
      'bad': ApiException('模拟解析失败'),
    });
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
      _playbackSong('bad', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('good', const Duration(minutes: 3), source: 'netease'),
    ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(player.current!.id, 'bad');
    expect(player.error, isNotNull);
  });

  // ===== 自动换源打分匹配（对标 TuneFreeNext 的 AutomaticSourceFallbackResolver）=====
  group('SourceFallbackResolver 打分逻辑', () {
    const resolver = SourceFallbackResolver();

    test('normalize 去括号附注、大小写、全角与标点', () {
      expect(SourceFallbackResolver.normalize('告白气球 (Live版)'), '告白气球');
      expect(SourceFallbackResolver.normalize('Hello  [Remix]'), 'hello');
      expect(SourceFallbackResolver.normalize('晴天（现场）'), '晴天');
      expect(SourceFallbackResolver.normalize('Ｈｅｌｌｏ，World！'), 'hello world');
    });

    test('同一首歌跨版本打分高于不同歌', () {
      final target = _playbackSong('1', const Duration(minutes: 3),
          name: '告白气球', artist: '周杰伦');
      final same = _playbackSong('2', const Duration(minutes: 3),
          name: '告白气球 (Live)', artist: '周杰伦');
      final other = _playbackSong('3', const Duration(minutes: 4),
          name: '夜曲', artist: '林俊杰');
      expect(resolver.matchScore(target, same),
          greaterThan(resolver.matchScore(target, other)));
      expect(resolver.matchScore(target, same),
          greaterThan(SourceFallbackResolver.acceptThreshold));
    });

    test('bestCandidateOrNull 选出最高分候选', () {
      final target = _playbackSong('1', const Duration(minutes: 3),
          name: '晴天', artist: '周杰伦');
      final candidates = [
        _playbackSong('9', const Duration(minutes: 3), name: '稻香', artist: '周杰伦'),
        _playbackSong('8', const Duration(minutes: 3), name: '晴天', artist: '周杰伦'),
        _playbackSong('7', const Duration(minutes: 5), name: '彩虹', artist: '五月天'),
      ];
      final best = resolver.bestCandidateOrNull(target, candidates);
      expect(best?.id, '8');
      expect(
          resolver.bestCandidateOrNull(target, [
            _playbackSong('x', const Duration(minutes: 3),
                name: '完全不相关的歌', artist: '某人'),
          ]),
          isNull);
    });
  });

  test('当前源解析失败时自动换源到打分最高的候选', () async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    final api = _FallbackMusicApi(
      failIds: {'local-id'},
      searchResults: {
        'netease': [
          _playbackSong('wrong', const Duration(minutes: 3),
              name: '另一首', artist: '别人', source: 'netease'),
          _playbackSong('matched', const Duration(minutes: 3),
              name: '晴天', artist: '周杰伦', source: 'netease'),
        ],
        'kuwo': const [],
        'qishui': const [],
      },
    );
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
      enablePrefetch: false,
      enableAutoSkip: false,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('local-id', const Duration(minutes: 3),
          source: 'qq', name: '晴天', artist: '周杰伦'),
    ]);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // 原源失败 → 搜索了备用源 → 换到匹配候选并成功播放。
    expect(api.playRequests, contains('qq:local-id'));
    expect(api.searchQueries, isNotEmpty);
    expect(api.playRequests, contains('netease:matched'));
    expect(player.error, isNull);
    expect(player.current!.id, 'local-id');
  });

  testWidgets('关闭自动换源后不会搜索备用源', (tester) async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    await settings.setAutoSourceFallback(false);
    final api = _FallbackMusicApi(
      failIds: {'bad'},
      searchResults: {
        'netease': [
          _playbackSong('ok', const Duration(minutes: 3),
              name: 'bad', artist: '测试歌手', source: 'netease'),
        ],
      },
    );
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
      enablePrefetch: false,
      enableAutoSkip: false,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('bad', const Duration(minutes: 3),
          source: 'qq', name: 'bad', artist: '测试歌手'),
    ]);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(api.searchQueries, isEmpty);
    expect(player.error, isNotNull);
  });

  // ===== 封面预取 + 主色过渡（对标 TuneFreeNext 的 DynamicArtworkController）=====
  test('切歌时预热封面并用提取的主色更新 artworkColor', () async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    final api = _ScriptedMusicApi();
    final warmed = <Uri>[];
    final colorService = ArtworkColorService.forTesting(
      (uri) => uri.toString().contains('cover-a')
          ? const Color(0xff112233)
          : null,
    );
    final player = PlayerController(
      settings: settings,
      audioPlayer: _ControllableAudioPlayer(),
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
      enablePrefetch: false,
      enableAutoSkip: false,
      warmArtwork: (uri) async {
        warmed.add(uri);
      },
      artworkColorService: colorService,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('a', const Duration(minutes: 3),
          source: 'netease', picUrl: 'https://img.example.com/cover-a.jpg'),
    ]);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(warmed, isNotEmpty);
    expect(warmed.first.toString(), contains('cover-a'));
    expect(player.artworkColor.value, const Color(0xff112233));
  });

  // ===== AutoMix 平滑切歌（单 player 近似）=====
  test('AutoMix 开启时自然播完切歌包含淡出与淡入', () async {
    final settings = SettingsController();
    await settings.setAutomaticAudioCache(false);
    await settings.setAutoMix(true);
    final api = _ScriptedMusicApi();
    final native = _ControllableAudioPlayer();
    final player = PlayerController(
      settings: settings,
      audioPlayer: native,
      musicApi: api,
      localFileFor: (_) async => null,
      localAudioFor: (_) async => null,
      maintainAudioCache: (_) async {},
      lastPlaybackStore: _MemoryLastPlaybackStore(),
      enablePrefetch: false,
      enableAutoSkip: false,
    );
    addTearDown(() {
      player.dispose();
      settings.dispose();
    });

    await player.playQueue([
      _playbackSong('a', const Duration(minutes: 3), source: 'netease'),
      _playbackSong('b', const Duration(minutes: 3), source: 'netease'),
    ]);
    native.volumeChanges.clear();
    // 模拟当前歌自然播放结束。
    native.completeTrack();
    // 等待淡出(110ms)+切歌+淡入(180ms)异步链完成。
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(player.current!.id, 'b');
    // 至少出现一次淡出到接近 0，以及淡入回接近 1。
    expect(native.volumeChanges.any((v) => v < 0.3), isTrue,
        reason: '应包含淡出');
    expect(native.volumeChanges.last, greaterThan(0.9), reason: '应淡入回原音量');
  });
}

Song _playbackSong(
  String id,
  Duration duration, {
  String source = 'qq',
  String name = '',
  String artist = '测试歌手',
  String? picUrl,
}) =>
    Song(
      id: id,
      name: name.isEmpty ? id : name,
      source: source,
      artists: [Artist(id: 1, name: artist)],
      album: Album(id: 1, name: '测试专辑', picUrl: picUrl),
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
  final List<String> prefetchRequests = [];

  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async {
    // 下一首预热请求带 prefetch=true，不计入真实播放解析次数。
    if (prefetch) {
      prefetchRequests.add('$source:$id');
    } else {
      playRequests.add('$source:$id');
    }
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

/// 可对指定歌曲注入解析错误，并记录真实解析 / 预热请求的次数，
/// 用于验证「下一首预取」与「不可播自动跳过」机制。
class _ScriptedMusicApi extends MusicApi {
  _ScriptedMusicApi({this.errors = const {}});

  /// id -> 仅真实解析（非预热）时抛出的异常。
  final Map<String, Object> errors;
  final List<String> playRequests = [];
  final List<String> prefetchRequests = [];

  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async {
    if (prefetch) {
      prefetchRequests.add(id);
    } else {
      playRequests.add(id);
      final error = errors[id];
      if (error != null) throw error;
    }
    return PlaybackInfo.fromJson(
      {'playUrl': 'https://media.example.com/$id.m4a'},
      id: id,
      source: source,
    );
  }

  @override
  Future<String?> getLyric(String id,
          {String source = 'netease', bool requireVerified = false}) async =>
      null;
}

/// 支持自动换源测试：指定 id 解析失败，searchSongs 返回可注入的候选。
class _FallbackMusicApi extends MusicApi {
  _FallbackMusicApi({
    this.failIds = const {},
    this.searchResults = const {},
  });

  final Set<String> failIds;
  final Map<String, List<Song>> searchResults;
  final List<String> playRequests = [];
  final List<String> searchQueries = [];

  @override
  Future<PlaybackInfo> getPlaybackInfo(
    String id, {
    String source = 'netease',
    String quality = 'exhigh',
    bool prefetch = false,
  }) async {
    if (!prefetch) {
      playRequests.add('$source:$id');
      if (failIds.contains(id)) throw ApiException('解析失败');
    }
    return PlaybackInfo.fromJson(
      {'playUrl': 'https://media.example.com/$source/$id.m4a'},
      id: id,
      source: source,
    );
  }

  @override
  Future<List<Song>> searchSongs(
    String keyword, {
    String source = 'netease',
    int offset = 0,
    int limit = 30,
  }) async {
    searchQueries.add('$source:$keyword');
    return searchResults[source] ?? const [];
  }

  @override
  Future<String?> getLyric(String id,
          {String source = 'netease', bool requireVerified = false}) async =>
      null;
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

  // AutoMix 淡入淡出观测点。
  double _volume = 1.0;
  final List<double> volumeChanges = [];

  @override
  double get volume => _volume;

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    volumeChanges.add(volume);
  }

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
  Future<void> next({bool smooth = false}) async {
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
