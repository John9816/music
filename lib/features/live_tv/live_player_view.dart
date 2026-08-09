import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as video_controls;

import '../../core/models/live_tv.dart';
import '../../core/player/playback_coordinator.dart';
import 'live_line_failover.dart';
import 'live_open_queue.dart';

typedef LiveMediaSessionFactory = LiveMediaSession Function();

abstract class LiveMediaSession {
  Stream<String> get errors;
  bool get isPlaying;
  bool get isMuted;
  Future<void> open(Uri uri);
  Future<void> play();
  Future<void> pause();
  Future<void> setMuted(bool value);
  Future<void> toggleFullscreen();
  Future<void> dispose();
  Widget buildVideo({
    VoidCallback? onShowLines,
    VoidCallback? onPlaybackRequested,
  });
}

class LivePlayerView extends StatefulWidget {
  const LivePlayerView({
    super.key,
    required this.channel,
    this.initialLineId,
    this.mediaSessionFactory,
  });

  final LiveChannel channel;
  final String? initialLineId;
  final LiveMediaSessionFactory? mediaSessionFactory;

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView> {
  late final LiveMediaSession _media =
      (widget.mediaSessionFactory ?? _MediaKitLiveMediaSession.new)();
  final LiveOpenQueue _openQueue = LiveOpenQueue();
  late final LiveLineFailover _failover =
      LiveLineFailover(widget.channel.lines.map((line) => line.id));
  StreamSubscription<String>? _errorSubscription;
  LiveLine? _currentLine;
  bool _loading = true;
  bool _exhausted = false;
  int _openGeneration = 0;
  int? _failedGeneration;

  @override
  void initState() {
    super.initState();
    PlaybackCoordinator.instance.register(this, _pauseLive);
    _errorSubscription = _media.errors.listen((_) {
      _failCurrentGeneration(_openGeneration);
    });
    final first = _failover.start(preferredId: widget.initialLineId);
    unawaited(_openLine(first));
  }

  @override
  void dispose() {
    _openGeneration++;
    PlaybackCoordinator.instance.unregister(this);
    final cancelErrors = _errorSubscription?.cancel() ?? Future<void>.value();
    unawaited(_openQueue.enqueue(() async {
      await cancelErrors;
      await _media.dispose();
    }));
    super.dispose();
  }

  Future<void> _openLine(String? lineId) async {
    if (lineId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _exhausted = true;
          _currentLine = null;
        });
      }
      return;
    }
    final line = widget.channel.lines.firstWhere((item) => item.id == lineId);
    final generation = ++_openGeneration;
    _failedGeneration = null;
    setState(() {
      _currentLine = line;
      _loading = true;
      _exhausted = false;
    });
    try {
      await PlaybackCoordinator.instance.activate(this);
      await _openQueue.enqueue(() => _media.open(line.uri));
      if (!mounted || generation != _openGeneration) return;
      setState(() => _loading = false);
    } catch (_) {
      _failCurrentGeneration(generation);
    }
  }

  void _failCurrentGeneration(int generation) {
    if (!mounted || generation != _openGeneration) return;
    if (_failedGeneration == generation) return;
    _failedGeneration = generation;
    final next = _failover.failCurrent();
    if (next == null) {
      setState(() {
        _loading = false;
        _exhausted = true;
      });
      return;
    }
    unawaited(_openLine(next));
  }

  void _selectLine(LiveLine line) {
    Navigator.of(context).pop();
    unawaited(_openLine(_failover.select(line.id)));
  }

  void _retry() => unawaited(_openLine(_failover.restart()));

  Future<void> _togglePlayback() async {
    if (_media.isPlaying) {
      await _media.pause();
    } else {
      await PlaybackCoordinator.instance.activate(this);
      await _media.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMuted() async {
    await _media.setMuted(!_media.isMuted);
    if (mounted) setState(() {});
  }

  Future<void> _pauseLive() => _media.pause();

  void _showLines() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const ListTile(
              title:
                  Text('切换线路', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            for (final line in widget.channel.lines)
              ListTile(
                key: ValueKey('player-live-line-${line.id}'),
                leading: Icon(
                  line.id == _currentLine?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                title: Text(line.name),
                subtitle: Text(line.protocol),
                onTap: () => _selectLine(line),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _currentLine == null
        ? -1
        : widget.channel.lines.indexWhere(
            (line) => line.id == _currentLine!.id,
          );
    return Scaffold(
      key: const ValueKey('live-player-view'),
      appBar: AppBar(
        title: Text(widget.channel.name),
        actions: [
          IconButton(
            tooltip: '切换线路',
            onPressed: widget.channel.lines.isEmpty ? null : _showLines,
            icon: const Icon(Icons.route),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ColoredBox(
                        color: Colors.black,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (!_exhausted)
                              _media.buildVideo(
                                onShowLines: _showLines,
                                onPlaybackRequested: () =>
                                    unawaited(_togglePlayback()),
                              ),
                            if (_loading)
                              const Center(child: CircularProgressIndicator()),
                            if (_exhausted) _UnavailableState(onRetry: _retry),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          currentIndex < 0
                              ? widget.channel.name
                              : '线路 ${currentIndex + 1} / '
                                  '${widget.channel.lines.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('live-fullscreen-button'),
                        tooltip: '全屏',
                        onPressed: _media.toggleFullscreen,
                        icon: const Icon(Icons.fullscreen),
                      ),
                      IconButton(
                        tooltip: _media.isMuted ? '取消静音' : '静音',
                        onPressed: _toggleMuted,
                        icon: Icon(
                          _media.isMuted ? Icons.volume_off : Icons.volume_up,
                        ),
                      ),
                      IconButton.filled(
                        tooltip: _media.isPlaying ? '暂停' : '播放',
                        onPressed: _exhausted ? null : _togglePlayback,
                        icon: Icon(
                          _media.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  const _UnavailableState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white70, size: 42),
              const SizedBox(height: 10),
              const Text(
                '所有线路暂时不可用',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('live-retry-lines'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重新尝试'),
              ),
            ],
          ),
        ),
      );
}

class LiveVideoControls extends StatefulWidget {
  const LiveVideoControls({
    super.key,
    required this.fullscreen,
    required this.isPlaying,
    required this.isMuted,
    required this.onShowLines,
    required this.onToggleMuted,
    required this.onTogglePlayback,
    required this.onToggleFullscreen,
    this.onDoubleTap,
  });

  final bool fullscreen;
  final bool isPlaying;
  final bool isMuted;
  final VoidCallback onShowLines;
  final VoidCallback onToggleMuted;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onDoubleTap;

  @override
  State<LiveVideoControls> createState() => _LiveVideoControlsState();
}

class _LiveVideoControlsState extends State<LiveVideoControls> {
  static const _hideAfter = Duration(seconds: 3);

  Timer? _hideTimer;
  bool _controlsVisible = false;

  @override
  void didUpdateWidget(covariant LiveVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen != widget.fullscreen) {
      _hideTimer?.cancel();
      _controlsVisible = false;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _showControls() {
    if (!widget.fullscreen) return;
    setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          if (widget.fullscreen)
            const SingleActivator(LogicalKeyboardKey.escape):
                widget.onToggleFullscreen,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('live-video-controls-surface'),
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: widget.onDoubleTap,
                ),
              ),
              if (widget.fullscreen && _controlsVisible) ...[
                Positioned(
                  top: 16,
                  left: 16,
                  child: _ControlButton(
                    key: const ValueKey(
                      'live-video-overlay-fullscreen-button',
                    ),
                    tooltip: '退出全屏',
                    onPressed: widget.onToggleFullscreen,
                    icon: Icons.arrow_back,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _ControlButton(
                    key: const ValueKey('live-video-route-button'),
                    tooltip: '切换线路',
                    onPressed: widget.onShowLines,
                    icon: Icons.route,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          tooltip: tooltip,
          color: Colors.white,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      );
}

class _MediaKitLiveMediaSession implements LiveMediaSession {
  static Player? _retainedMacOSPlayer;
  static VideoController? _retainedMacOSVideoController;

  factory _MediaKitLiveMediaSession() {
    if (Platform.isMacOS) {
      final player = _retainedMacOSPlayer ??= _createPlayer();
      final controller =
          _retainedMacOSVideoController ??= VideoController(player);
      return _MediaKitLiveMediaSession._(
        player,
        controller,
        disposePlayer: false,
      );
    }
    final player = _createPlayer();
    return _MediaKitLiveMediaSession._(
      player,
      VideoController(player),
      disposePlayer: true,
    );
  }

  _MediaKitLiveMediaSession._(
    this._player,
    this._videoController, {
    required bool disposePlayer,
  }) : _disposePlayer = disposePlayer;

  static Player _createPlayer() => Player(
        // Finish each MPV command before another live line can be loaded.
        configuration: const PlayerConfiguration(async: false),
      );

  final Player _player;
  final VideoController _videoController;
  final bool _disposePlayer;
  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  double _audibleVolume = 100;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  bool get isMuted => _player.state.volume == 0;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Widget buildVideo({
    VoidCallback? onShowLines,
    VoidCallback? onPlaybackRequested,
  }) =>
      Video(
        key: _videoKey,
        controller: _videoController,
        fit: BoxFit.contain,
        controls: (_) => StreamBuilder<bool>(
          stream: _player.stream.playing,
          initialData: _player.state.playing,
          builder: (context, playingSnapshot) => StreamBuilder<double>(
            stream: _player.stream.volume,
            initialData: _player.state.volume,
            builder: (context, volumeSnapshot) {
              final fullscreen = video_controls.isFullscreen(context);
              return LiveVideoControls(
                fullscreen: fullscreen,
                isPlaying: playingSnapshot.data ?? _player.state.playing,
                isMuted: (volumeSnapshot.data ?? _player.state.volume) == 0,
                onShowLines: onShowLines ?? () {},
                onToggleMuted: () => unawaited(setMuted(!isMuted)),
                onTogglePlayback: onPlaybackRequested ??
                    () => unawaited(isPlaying ? pause() : play()),
                onToggleFullscreen: () => unawaited(
                  video_controls.toggleFullscreen(context),
                ),
                onDoubleTap: Platform.isMacOS || Platform.isWindows
                    ? () => unawaited(
                          video_controls.toggleFullscreen(context),
                        )
                    : null,
              );
            },
          ),
        ),
      );

  @override
  Future<void> dispose() => _disposePlayer ? _player.dispose() : _player.stop();

  @override
  Future<void> open(Uri uri) => _player.open(Media(uri.toString()), play: true);

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> setMuted(bool value) async {
    if (value) {
      if (_player.state.volume > 0) _audibleVolume = _player.state.volume;
      await _player.setVolume(0);
    } else {
      await _player.setVolume(_audibleVolume <= 0 ? 100 : _audibleVolume);
    }
  }

  @override
  Future<void> toggleFullscreen() async {
    final state = _videoKey.currentState;
    if (state != null) await state.toggleFullscreen();
  }
}
