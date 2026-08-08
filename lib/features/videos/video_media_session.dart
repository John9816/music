import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

typedef VideoMediaSessionFactory = VideoMediaSession Function();

abstract class VideoMediaSession {
  bool get isPlaying;
  Duration get position;
  double get aspectRatio;
  Future<void> open(Uri uri, {Duration resumePosition = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> toggleFullscreen();
  Future<void> dispose();
  Widget buildVideo();
}

class MediaKitVideoMediaSession implements VideoMediaSession {
  factory MediaKitVideoMediaSession() {
    if (shouldRetainPlayerOn(defaultTargetPlatform)) {
      final player = _retainedMacOSPlayer ??= Player();
      final controller =
          _retainedMacOSVideoController ??= VideoController(player);
      return MediaKitVideoMediaSession._(
        player,
        controller,
        disposePlayer: false,
      );
    }
    final player = Player();
    return MediaKitVideoMediaSession._(
      player,
      VideoController(player),
      disposePlayer: true,
    );
  }

  MediaKitVideoMediaSession._(
    this._player,
    this._videoController, {
    required bool disposePlayer,
  }) : _disposePlayer = disposePlayer;

  static Player? _retainedMacOSPlayer;
  static VideoController? _retainedMacOSVideoController;

  @visibleForTesting
  static bool shouldRetainPlayerOn(TargetPlatform platform) =>
      platform == TargetPlatform.macOS;

  final Player _player;
  final VideoController _videoController;
  final bool _disposePlayer;
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();

  @override
  double get aspectRatio {
    final width = _player.state.width;
    final height = _player.state.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Duration get position => _player.state.position;

  @override
  Widget buildVideo() => Video(
        key: _videoKey,
        controller: _videoController,
        fit: BoxFit.contain,
      );

  @override
  Future<void> dispose() => _disposePlayer ? _player.dispose() : _player.stop();

  @override
  Future<void> open(
    Uri uri, {
    Duration resumePosition = Duration.zero,
  }) async {
    await _player.open(Media(uri.toString()), play: false);
    final duration = _player.state.duration;
    if (resumePosition > Duration.zero &&
        (duration == Duration.zero || resumePosition < duration)) {
      await _player.seek(resumePosition);
    }
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> toggleFullscreen() async {
    final state = _videoKey.currentState;
    if (state != null) await state.toggleFullscreen();
  }
}
