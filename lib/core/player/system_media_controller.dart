import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../network/image_request_policy.dart';
import 'player_controller.dart';

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
  );

  /// 通知权限弹窗需要用户交互，给足时间；仅用于防止原生侧永不回调时状态锁死。
  static const Duration _androidNotificationPermissionTimeout =
      Duration(minutes: 2);

  final Future<dynamic> Function() _androidNotificationPermissionRequester;  final bool Function() _isAndroid;
  bool _androidNotificationPermissionRequested = false;
  Future<dynamic>? _androidNotificationPermissionRequest;
  List<String> _publishedQueueKeys = const [];
  String? _publishedMediaKey;

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
    if (!_isAndroid()) return;
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
    final currentItem = queueIndex >= 0 && queueIndex < items.length
        ? items[queueIndex]
        : player.current == null
            ? null
            : _mediaItem(player.current!, 0);
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

  MediaItem _mediaItem(Song song, int index) {
    final artworkUrl = normalizeRemoteImageUrl(song.album.picUrl);
    final artworkHeaders = imageRequestHeaders(artworkUrl);
    return MediaItem(
      id: '${song.source}:${song.id}:$index',
      title: song.name,
      artist: song.artistNames,
      album: song.album.name,
      artUri: artworkUrl == null ? null : Uri.tryParse(artworkUrl),
      artHeaders: artworkHeaders.isEmpty ? null : artworkHeaders,
      duration:
          song.durationMs > 0 ? Duration(milliseconds: song.durationMs) : null,
    );
  }

  String _songMediaKey(Song song, int index) {
    return '$index\u001f${song.source}\u001f${song.id}\u001f${song.name}\u001f'
        '${song.artistNames}\u001f${song.album.name}\u001f${song.album.picUrl}\u001f'
        '${song.durationMs}';
  }

  @override
  Future<void> play() async {
    final player = _player;
    if (player != null && !player.playing) await player.togglePlay();
    _sync();
  }

  @override
  Future<void> pause() async {
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
    await _player?.next();
    _sync();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player?.previous();
    _sync();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _player?.playAt(index);
    _sync();
  }

  @override
  Future<void> fastForward() async {
    final player = _player;
    if (player == null) return;
    await player.seek(player.position + const Duration(seconds: 10));
    _sync();
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
    await _player?.stopAndClear();
    _sync();
  }
}
