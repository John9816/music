import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

import '../models/song.dart';
import '../network/image_request_policy.dart';
import 'player_controller.dart';
import 'car_media_library.dart';

class SystemMediaController extends BaseAudioHandler {
  SystemMediaController({
    Future<void> Function()? androidNotificationPermissionRequester,
    bool Function()? isAndroid,
  })  : _androidNotificationPermissionRequester =
            androidNotificationPermissionRequester ??
                _requestAndroidNotificationPermission,
        _isAndroid = isAndroid ?? _platformIsAndroid;

  static final SystemMediaController instance = SystemMediaController();
  static bool _initialized = false;
  static const MethodChannel _iosChannel = MethodChannel(
    'com.751152.duckmusic/system_media',
  );
  static const MethodChannel _androidNotificationChannel = MethodChannel(
    'com.751152.duckmusic/notifications',
  );
  static const AudioServiceConfig androidConfig = AudioServiceConfig(
    androidNotificationChannelId: 'com.751152.duck_music.channel.audio',
    androidNotificationChannelName: '音频播放',
    androidNotificationChannelDescription: '显示当前歌曲和播放控制',
    androidNotificationIcon: 'drawable/ic_notification_music',
    notificationColor: Color(0xFF2FD365),
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
    artDownscaleWidth: 512,
    artDownscaleHeight: 512,
    androidBrowsableRootExtras: {
      AndroidContentStyle.supportedKey: true,
      AndroidContentStyle.browsableHintKey:
          AndroidContentStyle.listItemHintValue,
      AndroidContentStyle.playableHintKey:
          AndroidContentStyle.listItemHintValue,
      'android.media.browse.SEARCH_SUPPORTED': true,
    },
  );

  /// 通知权限弹窗需要用户交互，给足时间；仅用于防止原生侧永不回调时状态锁死。
  static const Duration _androidNotificationPermissionTimeout =
      Duration(minutes: 2);

  final Future<dynamic> Function() _androidNotificationPermissionRequester;
  final bool Function() _isAndroid;
  bool _androidNotificationPermissionRequested = false;
  Future<dynamic>? _androidNotificationPermissionRequest;
  List<String> _publishedQueueKeys = const [];
  String? _publishedMediaKey;
  CarMediaLibrary? _library;
  final _libraryReady = Completer<void>();
  final _children = <String, BehaviorSubject<Map<String, dynamic>>>{};
  int _browseRevision = 0;
  int _externalCommands = 0;
  int _playRequest = 0;
  int? _librarySession;

  /// iOS 与 macOS 共用 MPNowPlayingInfoCenter 通道；Android 走 audio_service。
  static bool get _usesAppleNowPlaying => Platform.isIOS || Platform.isMacOS;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (_usesAppleNowPlaying) {
      _iosChannel.setMethodCallHandler(instance._handleIosCommand);
      await _iosChannel.invokeMethod<void>('initialize');
      _initialized = true;
      return;
    }
    await AudioService.init(
      builder: () => instance,
      config: androidConfig,
    );
    _initialized = true;
  }

  /// Waits for the Android notification permission dialog before playback
  /// starts. The native method resolves only after the user makes a choice.
  Future<void> prepareForPlayback() async {
    if (!_isAndroid() || _externalCommands > 0) return;
    if (_androidNotificationPermissionRequester ==
            _requestAndroidNotificationPermission &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final inFlight = _androidNotificationPermissionRequest;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    if (_androidNotificationPermissionRequested) return;
    _androidNotificationPermissionRequested = true;
    final request = _androidNotificationPermissionRequest =
        _androidNotificationPermissionRequester();
    try {
      // 兜底超时：若原生侧因 Activity 回收等原因始终不回调，这里必须让出，
      // 否则 _androidNotificationPermissionRequest 会永远非空，
      // 后续每次调用都跟着挂起，权限再也不会被请求第二次。
      await request.timeout(_androidNotificationPermissionTimeout);
    } catch (_) {
      _androidNotificationPermissionRequested = false;
      rethrow;
    } finally {
      if (identical(_androidNotificationPermissionRequest, request)) {
        _androidNotificationPermissionRequest = null;
      }
    }
  }

  /// Re-checks the system switch after returning from Settings. This allows a
  /// previously denied notification permission to recover without restarting.
  Future<void> refreshAndroidNotificationPermission() async {
    if (!_isAndroid()) return;
    try {
      final enabled = await _androidNotificationChannel
          .invokeMethod<bool>('areNotificationsEnabled');
      if (enabled == true) {
        _androidNotificationPermissionRequested = true;
        // Re-publish playback state so a notification suppressed while the
        // app was in Settings is created immediately after the user returns.
        if (_player != null) _sync();
      }
    } catch (_) {}
  }

  PlayerController? _player;

  void attach(PlayerController player) {
    if (identical(_player, player)) return;
    _player?.removeListener(_sync);
    _player = player;
    player.addListener(_sync);
    _sync();
  }

  void detach(PlayerController player) {
    if (!identical(_player, player)) return;
    player.removeListener(_sync);
    _player = null;
    _publishedQueueKeys = const [];
    _publishedMediaKey = null;
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    playbackState.add(PlaybackState());
    if (_usesAppleNowPlaying) {
      unawaited(_iosChannel.invokeMethod<void>('clear'));
    }
  }

  void _sync() {
    final player = _player;
    if (player == null) return;
    _ensureAndroidNotificationPermission(player.playing);
    final songs = player.queue;
    final queueKeys = <String>[
      for (var index = 0; index < songs.length; index++)
        _songMediaKey(songs[index], index),
    ];
    final queueChanged = !listEquals(_publishedQueueKeys, queueKeys);
    final items = queueChanged
        ? <MediaItem>[
            for (var index = 0; index < songs.length; index++)
              _mediaItem(songs[index], index),
          ]
        : queue.value;
    if (queueChanged) {
      _publishedQueueKeys = List.unmodifiable(queueKeys);
      queue.add(items);
    }

    final queueIndex = player.queueIndex;
    final hasQueueItem = queueIndex >= 0 && queueIndex < songs.length;
    final currentSong = hasQueueItem ? songs[queueIndex] : player.current;
    final currentItem = currentSong == null
        ? null
        : _mediaItem(
            currentSong,
            hasQueueItem ? queueIndex : 0,
            duration: player.duration,
          );
    final mediaKey = currentItem == null
        ? null
        : '${currentItem.id}\u001f${currentItem.title}\u001f'
            '${currentItem.artist}\u001f${currentItem.album}\u001f'
            '${currentItem.artUri}\u001f${currentItem.duration?.inMilliseconds}';
    if (_publishedMediaKey != mediaKey) {
      _publishedMediaKey = mediaKey;
      mediaItem.add(currentItem);
    }

    // Keep transport controls stable even for a one-song queue. Both Android
    // SystemUI and iOS hide previous/next when those actions are omitted; the
    // player deliberately wraps a one-song queue back to the current track.
    final hasTransportControls = currentItem != null;
    final controls = <MediaControl>[
      if (hasTransportControls) MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      if (hasTransportControls) MediaControl.skipToNext,
    ];
    final processingState = player.current == null
        ? AudioProcessingState.idle
        : player.error != null
            ? AudioProcessingState.error
            : player.loading
                ? AudioProcessingState.loading
                : AudioProcessingState.ready;
    playbackState.add(
      PlaybackState(
        controls: controls,
        androidCompactActionIndices: [
          for (var index = 0; index < controls.length && index < 3; index++)
            index,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.playFromMediaId,
          MediaAction.playFromSearch,
          MediaAction.skipToQueueItem,
          MediaAction.setRepeatMode,
          MediaAction.setShuffleMode,
        },
        processingState: processingState,
        playing: player.playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: 1,
        queueIndex: queueIndex >= 0 ? queueIndex : null,
        repeatMode: switch (player.loopMode.name) {
          'one' => AudioServiceRepeatMode.one,
          'all' => AudioServiceRepeatMode.all,
          _ => AudioServiceRepeatMode.none,
        },
        shuffleMode: player.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        errorCode: player.error == null ? null : 1,
        errorMessage: player.error,
      ),
    );
    if (_usesAppleNowPlaying && currentItem != null) {
      unawaited(
        _iosChannel.invokeMethod<void>('update', {
          'title': currentItem.title,
          'artist': currentItem.artist ?? '',
          'album': currentItem.album ?? '',
          'artworkUrl': currentItem.artUri?.toString(),
          'durationMs': currentItem.duration?.inMilliseconds ?? 0,
          'positionMs': player.position.inMilliseconds,
          'playing': player.playing,
          'hasPrevious': hasTransportControls,
          'hasNext': hasTransportControls,
        }),
      );
    }
  }

  void _ensureAndroidNotificationPermission(bool playing) {
    if (!playing) return;
    unawaited(
      prepareForPlayback().catchError((Object _) {
        // Permission errors must never interrupt audio playback.
      }),
    );
  }

  static bool _platformIsAndroid() => Platform.isAndroid;

  static Future<dynamic> _requestAndroidNotificationPermission() async {
    // Headless Android Auto commands must never wait for a phone permission UI.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    await _androidNotificationChannel
        .invokeMethod<dynamic>('requestPermission');
  }

  /// Returns whether Android is currently allowing this app's notifications.
  /// Used by Settings to explain why lock-screen/media controls may be absent.
  static Future<bool?> androidNotificationsEnabled() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _androidNotificationChannel
          .invokeMethod<bool>('areNotificationsEnabled');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openAndroidNotificationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _androidNotificationChannel
              .invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<dynamic> _handleIosCommand(MethodCall call) async {
    final player = _player;
    if (player == null) return;
    switch (call.method) {
      case 'play':
        if (!player.playing) await player.togglePlay();
      case 'pause':
        await player.pause();
      case 'previous':
        await player.previous();
      case 'next':
        await player.next();
      case 'seek':
        final arguments = call.arguments as Map<Object?, Object?>?;
        final positionMs = arguments?['positionMs'] as int?;
        if (positionMs != null) {
          await player.seek(Duration(milliseconds: positionMs));
        }
    }
    _sync();
  }

  MediaItem _mediaItem(Song song, int index, {Duration? duration}) {
    final artworkUrl = normalizeRemoteImageUrl(song.album.picUrl);
    final artworkHeaders = imageRequestHeaders(artworkUrl);
    return MediaItem(
      id: CarMediaLibrary.mediaIdFor(song),
      title: song.name,
      artist: song.artistNames,
      album: song.album.name,
      artUri: artworkUrl == null ? null : Uri.tryParse(artworkUrl),
      artHeaders: artworkHeaders.isEmpty ? null : artworkHeaders,
      duration: duration ??
          (song.durationMs > 0
              ? Duration(milliseconds: song.durationMs)
              : null),
      playable: true,
    );
  }

  void attachLibrary(CarMediaLibrary library) {
    if (identical(_library, library)) return;
    _library?.removeListener(_catalogChanged);
    _library = library;
    _librarySession = library.sessionGeneration;
    library.addListener(_catalogChanged);
    if (!_libraryReady.isCompleted) _libraryReady.complete();
    _catalogChanged();
  }

  void detachLibrary(CarMediaLibrary library) {
    if (!identical(_library, library)) return;
    library.removeListener(_catalogChanged);
    _library = null;
    _playRequest++;
    for (final subject in _children.values) {
      unawaited(subject.close());
    }
    _children.clear();
  }

  void _catalogChanged() {
    if (_librarySession != _library?.sessionGeneration) {
      _librarySession = _library?.sessionGeneration;
      _playRequest++;
    }
    _browseRevision++;
    for (final subject in _children.values) {
      subject.add({'revision': _browseRevision});
    }
  }

  Future<CarMediaLibrary> _catalog() async {
    if (_library == null) {
      await _libraryReady.future.timeout(const Duration(seconds: 12));
    }
    final library = _library;
    if (library == null) throw const CarMediaLibraryException('请重新打开应用');
    return library;
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) =>
      _children.putIfAbsent(parentMediaId,
          () => BehaviorSubject.seeded({'revision': _browseRevision}));

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    if (parentMediaId == CarMediaLibrary.rootId) {
      return [
        for (final entry in CarMediaLibrary.categories.entries)
          MediaItem(id: entry.key, title: entry.value, playable: false)
      ];
    }
    try {
      final group =
          RegExp(r'^(car:[a-z]+)/page/([0-9]+)$').firstMatch(parentMediaId);
      final category = group?.group(1) ?? parentMediaId;
      final songs = await (await _catalog()).songsFor(category);
      if (songs.length > 100 &&
          group == null &&
          options?['android.media.browse.extra.PAGE'] == null) {
        return [
          for (var offset = 0; offset < songs.length; offset += 100)
            MediaItem(
                id: '$category/page/${offset ~/ 100}',
                title:
                    '${offset + 1}–${(offset + 100).clamp(0, songs.length)} 首',
                playable: false),
        ];
      }
      final page = (int.tryParse(group?.group(2) ?? '') ??
              (options?['android.media.browse.extra.PAGE'] as num?)?.toInt() ??
              0)
          .clamp(0, 100000);
      final size = ((options?['android.media.browse.extra.PAGE_SIZE'] as num?)
                  ?.toInt() ??
              100)
          .clamp(1, 100);
      return [
        for (final song in songs.skip(page * size).take(size))
          _mediaItem(song, 0)
      ];
    } catch (error) {
      return [
        MediaItem(
            id: 'car:message', title: _catalogMessage(error), playable: false)
      ];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    try {
      final song = await (await _catalog()).songForMediaId(mediaId);
      return song == null ? null : _mediaItem(song, 0);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MediaItem>> search(String query,
      [Map<String, dynamic>? extras]) async {
    try {
      return [
        for (final song in await (await _catalog()).search(query))
          _mediaItem(song, 0)
      ];
    } catch (error) {
      _reportCatalogError(error);
      return const [];
    }
  }

  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    final request = ++_playRequest;
    _externalCommands++;
    try {
      final catalog = await _catalog();
      final session = catalog.sessionGeneration;
      final song = await catalog.songForMediaId(mediaId);
      if (request != _playRequest || session != catalog.sessionGeneration) {
        return;
      }
      if (song == null) {
        throw const CarMediaLibraryException('歌曲列表已更新，请重新打开目录选择歌曲');
      }
      final player = _player;
      if (player == null) return;
      final index = player.queue
          .indexWhere((item) => CarMediaLibrary.mediaIdFor(item) == mediaId);
      if (index >= 0) {
        await player.playAt(index);
      } else {
        final songs = catalog.playbackQueueFor(song);
        await player.playQueue(songs,
            index: songs.indexWhere(
                (entry) => CarMediaLibrary.mediaIdFor(entry) == mediaId));
      }
      _sync();
    } catch (error) {
      if (request == _playRequest) _reportCatalogError(error);
    } finally {
      _externalCommands--;
    }
  }

  @override
  Future<void> playFromSearch(String query,
      [Map<String, dynamic>? extras]) async {
    if (query.trim().isEmpty) {
      await play();
      return;
    }
    final request = ++_playRequest;
    _externalCommands++;
    try {
      final songs = await (await _catalog()).search(query);
      if (request != _playRequest) return;
      if (songs.isEmpty) throw const CarMediaLibraryException('没有找到歌曲，请换个名称搜索');
      await _player?.playQueue(songs);
      _sync();
    } catch (error) {
      if (request == _playRequest) _reportCatalogError(error);
    } finally {
      _externalCommands--;
    }
  }

  String _catalogMessage(Object error) =>
      error is CarMediaLibraryException ? error.message : '暂时无法加载，请稍后重试';

  void _reportCatalogError(Object error) {
    playbackState.add(playbackState.value.copyWith(
      errorCode: 1,
      errorMessage: _catalogMessage(error),
      processingState: _player?.current == null
          ? AudioProcessingState.error
          : playbackState.value.processingState,
    ));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _player?.setPlaybackMode(switch (repeatMode) {
      AudioServiceRepeatMode.one => PlaybackMode.singleLoop,
      AudioServiceRepeatMode.none => PlaybackMode.sequential,
      _ =>
        _player?.shuffle == true ? PlaybackMode.shuffle : PlaybackMode.listLoop,
    });
    _sync();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final player = _player;
    if (player == null) return;
    if (shuffleMode != AudioServiceShuffleMode.none) {
      await player.setPlaybackMode(PlaybackMode.shuffle);
    } else if (player.shuffle) {
      await player.setPlaybackMode(PlaybackMode.listLoop);
    }
    _sync();
  }

  String _songMediaKey(Song song, int index) {
    return '$index\u001f${song.source}\u001f${song.id}\u001f${song.name}\u001f'
        '${song.artistNames}\u001f${song.album.name}\u001f${song.album.picUrl}\u001f'
        '${song.durationMs}';
  }

  @override
  Future<void> play() async {
    final request = ++_playRequest;
    _externalCommands++;
    try {
      if (_player == null || _player?.current == null) await _catalog();
      if (request != _playRequest) return;
      final player = _player;
      if (player?.current == null) {
        throw const CarMediaLibraryException('请先从目录选择歌曲');
      }
      if (!player!.playing) await player.togglePlay();
      _sync();
    } catch (error) {
      if (request == _playRequest) _reportCatalogError(error);
    } finally {
      _externalCommands--;
    }
  }

  @override
  Future<void> pause() async {
    _playRequest++;
    await _player?.pause();
    _sync();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    _sync();
  }

  @override
  Future<void> skipToNext() async {
    _playRequest++;
    _externalCommands++;
    try {
      await _player?.next();
      _sync();
    } finally {
      _externalCommands--;
    }
  }

  @override
  Future<void> skipToPrevious() async {
    _playRequest++;
    _externalCommands++;
    try {
      await _player?.previous();
      _sync();
    } finally {
      _externalCommands--;
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    _playRequest++;
    _externalCommands++;
    try {
      await _player?.playAt(index);
      _sync();
    } finally {
      _externalCommands--;
    }
  }

  @override
  Future<void> fastForward() async {
    final player = _player;
    if (player == null) return;
    await player.seek(player.position + const Duration(seconds: 10));
    _sync();
  }

  @override
  Future<void> seekForward(bool begin) async {
    if (begin) await fastForward();
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (begin) await rewind();
  }

  @override
  Future<void> rewind() async {
    final player = _player;
    if (player == null) return;
    final target = player.position - const Duration(seconds: 10);
    await player.seek(target < Duration.zero ? Duration.zero : target);
    _sync();
  }

  @override
  Future<void> stop() async {
    _playRequest++;
    await _player?.stopAndClear();
    _sync();
  }
}
