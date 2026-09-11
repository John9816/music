import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart'
    as video_controls;
import 'package:video_player/video_player.dart' as video_player;

import '../../core/models/live_tv.dart';
import '../../core/player/playback_coordinator.dart';
import 'live_line_failover.dart';
import 'live_open_queue.dart';

typedef LiveMediaSessionFactory = LiveMediaSession Function();

LiveMediaSession _createDefaultLiveMediaSession() => Platform.isAndroid
    ? _AndroidVideoPlayerLiveMediaSession()
    : _MediaKitLiveMediaSession();

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
      (widget.mediaSessionFactory ?? _createDefaultLiveMediaSession)();
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
    final statusLabel = _exhausted
        ? '线路不可用'
        : _loading
            ? '连接中'
            : '直播中';
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth > constraints.maxHeight;
            final contentWidth = constraints.maxWidth - 32;
            final maxWidth = contentWidth.clamp(0.0, 1080.0).toDouble();
            final maxVideoHeight =
                (constraints.maxHeight - 152).clamp(160.0, double.infinity);
            final landscapeVideoWidth = maxVideoHeight * 16 / 9;
            final boundedVideoWidth = landscape
                ? landscapeVideoWidth < maxWidth
                    ? landscapeVideoWidth
                    : maxWidth
                : maxWidth;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: boundedVideoWidth,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
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
                                    if (_loading) const _LiveLoadingOverlay(),
                                    if (_exhausted)
                                      _UnavailableState(onRetry: _retry),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const _LiveStatusDot(),
                                      const SizedBox(width: 7),
                                      Flexible(
                                        child: Text(
                                          widget.channel.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        statusLabel,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          widget.channel.groupName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const Text(' · '),
                                      Text(
                                        currentIndex < 0
                                            ? '暂无可用线路'
                                            : '线路 ${currentIndex + 1} / '
                                                '${widget.channel.lines.length}',
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
                                _media.isMuted
                                    ? Icons.volume_off
                                    : Icons.volume_up,
                              ),
                            ),
                            IconButton.filled(
                              tooltip: _media.isPlaying ? '暂停' : '播放',
                              onPressed: _exhausted ? null : _togglePlayback,
                              icon: Icon(
                                _media.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LiveLoadingOverlay extends StatelessWidget {
  const _LiveLoadingOverlay();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '正在连接直播源',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
}

class _LiveStatusDot extends StatelessWidget {
  const _LiveStatusDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFE45757),
          shape: BoxShape.circle,
        ),
      );
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
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          _ControlButton(
                            key: const ValueKey(
                              'live-video-playback-button',
                            ),
                            tooltip: widget.isPlaying ? '暂停' : '播放',
                            onPressed: widget.onTogglePlayback,
                            icon: widget.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          _ControlButton(
                            key: const ValueKey('live-video-mute-button'),
                            tooltip: widget.isMuted ? '取消静音' : '静音',
                            onPressed: widget.onToggleMuted,
                            icon: widget.isMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                          ),
                          const Spacer(),
                          Text(
                            '直播',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _ControlButton(
                            tooltip: '退出全屏',
                            onPressed: widget.onToggleFullscreen,
                            icon: Icons.fullscreen_exit,
                          ),
                        ],
                      ),
                    ),
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

class _AndroidVideoPlayerLiveMediaSession implements LiveMediaSession {
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final ValueNotifier<video_player.VideoPlayerController?> _controller =
      ValueNotifier<video_player.VideoPlayerController?>(null);
  final GlobalKey<_AndroidLiveVideoSurfaceState> _videoKey =
      GlobalKey<_AndroidLiveVideoSurfaceState>();

  video_player.VideoPlayerController? _activeController;
  bool _reportedError = false;
  double _audibleVolume = 1;

  @override
  Stream<String> get errors => _errors.stream;

  @override
  bool get isMuted => (_activeController?.value.volume ?? 1) == 0;

  @override
  bool get isPlaying => _activeController?.value.isPlaying ?? false;

  @override
  Widget buildVideo({
    VoidCallback? onShowLines,
    VoidCallback? onPlaybackRequested,
  }) =>
      ValueListenableBuilder<video_player.VideoPlayerController?>(
        valueListenable: _controller,
        builder: (context, controller, _) {
          if (controller == null || !controller.value.isInitialized) {
            return const SizedBox.expand();
          }
          return _AndroidLiveVideoSurface(
            key: _videoKey,
            controller: controller,
            onShowLines: onShowLines ?? () {},
            onToggleMuted: () => unawaited(setMuted(!isMuted)),
            onTogglePlayback: onPlaybackRequested ??
                () => unawaited(isPlaying ? pause() : play()),
          );
        },
      );

  @override
  Future<void> dispose() async {
    final controller = _activeController;
    _activeController = null;
    _controller.value = null;
    if (controller != null) {
      controller.removeListener(_handleControllerValue);
      await controller.dispose();
    }
    _controller.dispose();
    await _errors.close();
  }

  @override
  Future<void> open(Uri uri) async {
    final previous = _activeController;
    _activeController = null;
    _controller.value = null;
    if (previous != null) {
      previous.removeListener(_handleControllerValue);
      await previous.dispose();
    }

    _reportedError = false;
    final controller = video_player.VideoPlayerController.networkUrl(
      uri,
      viewType: video_player.VideoViewType.platformView,
      formatHint: uri.path.toLowerCase().endsWith('.m3u8')
          ? video_player.VideoFormat.hls
          : null,
    );
    _activeController = controller;
    controller.addListener(_handleControllerValue);
    _controller.value = controller;
    try {
      await controller.initialize().timeout(const Duration(seconds: 12));
      await controller.play();
    } catch (_) {
      if (identical(_activeController, controller)) {
        _activeController = null;
        _controller.value = null;
      }
      controller.removeListener(_handleControllerValue);
      await controller.dispose();
      rethrow;
    }
  }

  void _handleControllerValue() {
    final controller = _activeController;
    if (controller == null || !controller.value.hasError || _reportedError) {
      return;
    }
    _reportedError = true;
    if (!_errors.isClosed) {
      _errors.add(controller.value.errorDescription ?? '直播播放失败');
    }
  }

  @override
  Future<void> pause() async {
    final controller = _activeController;
    if (controller != null) await controller.pause();
  }

  @override
  Future<void> play() async {
    final controller = _activeController;
    if (controller != null) await controller.play();
  }

  @override
  Future<void> setMuted(bool value) async {
    final controller = _activeController;
    if (controller == null) return;
    if (value) {
      if (controller.value.volume > 0) {
        _audibleVolume = controller.value.volume;
      }
      await controller.setVolume(0);
    } else {
      await controller.setVolume(_audibleVolume <= 0 ? 1 : _audibleVolume);
    }
  }

  @override
  Future<void> toggleFullscreen() async {
    await _videoKey.currentState?.toggleFullscreen();
  }
}

class _AndroidLiveVideoSurface extends StatefulWidget {
  const _AndroidLiveVideoSurface({
    super.key,
    required this.controller,
    required this.onShowLines,
    required this.onToggleMuted,
    required this.onTogglePlayback,
  });

  final video_player.VideoPlayerController controller;
  final VoidCallback onShowLines;
  final VoidCallback onToggleMuted;
  final VoidCallback onTogglePlayback;

  @override
  State<_AndroidLiveVideoSurface> createState() =>
      _AndroidLiveVideoSurfaceState();
}

class _AndroidLiveVideoSurfaceState extends State<_AndroidLiveVideoSurface> {
  Future<void> toggleFullscreen() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _AndroidFullscreenLiveVideo(
          controller: widget.controller,
          onShowLines: widget.onShowLines,
          onToggleMuted: widget.onToggleMuted,
          onTogglePlayback: widget.onTogglePlayback,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Stack(
          fit: StackFit.expand,
          children: [
            _AndroidVideoFrame(controller: widget.controller),
            LiveVideoControls(
              fullscreen: false,
              isPlaying: widget.controller.value.isPlaying,
              isMuted: widget.controller.value.volume == 0,
              onShowLines: widget.onShowLines,
              onToggleMuted: widget.onToggleMuted,
              onTogglePlayback: widget.onTogglePlayback,
              onToggleFullscreen: () => unawaited(toggleFullscreen()),
            ),
          ],
        ),
      );
}

class _AndroidFullscreenLiveVideo extends StatefulWidget {
  const _AndroidFullscreenLiveVideo({
    required this.controller,
    required this.onShowLines,
    required this.onToggleMuted,
    required this.onTogglePlayback,
  });

  final video_player.VideoPlayerController controller;
  final VoidCallback onShowLines;
  final VoidCallback onToggleMuted;
  final VoidCallback onTogglePlayback;

  @override
  State<_AndroidFullscreenLiveVideo> createState() =>
      _AndroidFullscreenLiveVideoState();
}

class _AndroidFullscreenLiveVideoState
    extends State<_AndroidFullscreenLiveVideo> {
  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _showLines() {
    Navigator.of(context).pop();
    widget.onShowLines();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Stack(
            fit: StackFit.expand,
            children: [
              _AndroidVideoFrame(controller: widget.controller),
              LiveVideoControls(
                fullscreen: true,
                isPlaying: widget.controller.value.isPlaying,
                isMuted: widget.controller.value.volume == 0,
                onShowLines: _showLines,
                onToggleMuted: widget.onToggleMuted,
                onTogglePlayback: widget.onTogglePlayback,
                onToggleFullscreen: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
}

class _AndroidVideoFrame extends StatelessWidget {
  const _AndroidVideoFrame({required this.controller});

  final video_player.VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller.value.aspectRatio;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio > 0 ? aspectRatio : 16 / 9,
          child: video_player.VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _MediaKitLiveMediaSession implements LiveMediaSession {
  static Player? _retainedMacOSPlayer;
  static VideoController? _retainedMacOSVideoController;

  factory _MediaKitLiveMediaSession() {
    if (Platform.isMacOS) {
      final player = _retainedMacOSPlayer ??= _createPlayer();
      final controller =
          _retainedMacOSVideoController ??= _createVideoController(player);
      return _MediaKitLiveMediaSession._(
        player,
        controller,
        disposePlayer: false,
      );
    }
    final player = _createPlayer();
    return _MediaKitLiveMediaSession._(
      player,
      _createVideoController(player),
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

  static VideoController _createVideoController(Player player) {
    // Render Android video into a native Surface. The default MPV GPU texture
    // path can fail with EGL_BAD_ATTRIBUTE on emulators and some vendor ROMs,
    // leaving live streams audible but black.
    final configuration = Platform.isAndroid
        ? const VideoControllerConfiguration(
            vo: 'mediacodec_embed',
            hwdec: 'mediacodec',
            androidAttachSurfaceAfterVideoParameters: false,
          )
        : const VideoControllerConfiguration();
    return VideoController(player, configuration: configuration);
  }

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
  Future<void> open(Uri uri) async {
    await _player.open(Media(uri.toString()), play: true);
    try {
      await _videoController.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 8),
      );
    } on TimeoutException {
      throw StateError('直播画面加载超时');
    }
  }

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
