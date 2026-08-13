import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';

import '../models/song.dart';
import '../network/image_request_policy.dart';
import 'player_controller.dart';

class SystemMediaController extends BaseAudioHandler {
  SystemMediaController();

  static final SystemMediaController instance = SystemMediaController();
  static bool _initialized = false;
  static const MethodChannel _iosChannel = MethodChannel(
    'com.751152.duckmusic/system_media',
  );

  static Future<void> initialize() async {
    if (_initialized) return;
    if (Platform.isIOS) {
      _iosChannel.setMethodCallHandler(instance._handleIosCommand);
      await _iosChannel.invokeMethod<void>('initialize');
      _initialized = true;
      return;
    }
    await AudioService.init(
      builder: () => instance,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.751152.duck_music.channel.audio',
        androidNotificationChannelName: '音频播放',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
    _initialized = true;
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
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    playbackState.add(PlaybackState());
    if (Platform.isIOS) {
      unawaited(_iosChannel.invokeMethod<void>('clear'));
    }
  }

  void _sync() {
    final player = _player;
    if (player == null) return;
    final songs = player.queue;
    final items = <MediaItem>[
      for (var index = 0; index < songs.length; index++)
        _mediaItem(songs[index], index),
    ];
    queue.add(items);

    final queueIndex = player.queueIndex;
    final currentItem = queueIndex >= 0 && queueIndex < items.length
        ? items[queueIndex]
        : player.current == null
            ? null
            : _mediaItem(player.current!, 0);
    mediaItem.add(currentItem);

    final hasQueueNavigation = songs.length > 1;
    final controls = <MediaControl>[
      if (hasQueueNavigation) MediaControl.skipToPrevious,
      if (player.playing) MediaControl.pause else MediaControl.play,
      if (hasQueueNavigation) MediaControl.skipToNext,
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
        bufferedPosition: player.position,
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
    if (Platform.isIOS && currentItem != null) {
      unawaited(
        _iosChannel.invokeMethod<void>('update', {
          'title': currentItem.title,
          'artist': currentItem.artist ?? '',
          'album': currentItem.album ?? '',
          'artworkUrl': currentItem.artUri?.toString(),
          'durationMs': currentItem.duration?.inMilliseconds ?? 0,
          'positionMs': player.position.inMilliseconds,
          'playing': player.playing,
          'hasPrevious': hasQueueNavigation,
          'hasNext': hasQueueNavigation,
        }),
      );
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
