import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/video_api.dart';
import '../../core/models/video.dart';
import '../../core/services/cast_service.dart';
import '../../core/services/video_history_service.dart';
import 'video_media_session.dart';

class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({
    super.key,
    required this.api,
    required this.title,
    required this.play,
    this.source,
    this.resumePosition = Duration.zero,
    this.historyService,
    this.mediaSessionFactory,
  });

  final VideoApi api;
  final String title;
  final VideoPlayback play;
  final String? source;
  final Duration resumePosition;
  final VideoHistoryService? historyService;
  final VideoMediaSessionFactory? mediaSessionFactory;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  final CastService _cast = CastService();
  late final VideoHistoryService _historyService;
  late final VideoMediaSession _media;
  Future<void>? _initialize;
  Timer? _historyTimer;
  bool _mediaOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _historyService = widget.historyService ?? VideoHistoryService();
    _media = (widget.mediaSessionFactory ?? MediaKitVideoMediaSession.new)();
    _cast.addListener(_handleCastState);
    final url = widget.play.mediaUrl;
    if (widget.play.isInlinePlayable && url != null) {
      _initialize = _media
          .open(
        Uri.parse(url),
        resumePosition: widget.resumePosition,
      )
          .then<void>((_) async {
        _mediaOpened = true;
        if (!mounted) return;
        setState(() {});
        _historyTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _persistProgress(),
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _persistProgress();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _historyTimer?.cancel();
    _persistProgress();
    _cast.removeListener(_handleCastState);
    unawaited(_cast.stop().whenComplete(_cast.dispose));
    unawaited(_media.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (widget.play.isInlinePlayable)
              AnimatedBuilder(
                animation: _cast,
                builder: (_, __) => IconButton(
                  tooltip: '投屏',
                  icon: Icon(_cast.status == CastStatus.connected
                      ? Icons.cast_connected
                      : Icons.cast),
                  onPressed:
                      _cast.status == CastStatus.connecting ? null : _startCast,
                ),
              ),
            if (widget.play.isInlinePlayable)
              IconButton(
                key: const ValueKey('vod-fullscreen-button'),
                tooltip: '全屏',
                onPressed: _media.toggleFullscreen,
                icon: const Icon(Icons.fullscreen),
              ),
          ],
        ),
        body: Center(child: _buildBody(context)),
      );

  Widget _buildBody(BuildContext context) {
    if (_initialize != null) {
      return FutureBuilder<void>(
        future: _initialize,
        builder: (_, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const CircularProgressIndicator();
          }
          if (snapshot.hasError) {
            return _fallback(context, '视频加载失败，请打开播放页重试');
          }
          return AspectRatio(
            aspectRatio: _media.aspectRatio,
            child: _media.buildVideo(),
          );
        },
      );
    }
    return _fallback(context, widget.play.message);
  }

  Widget _fallback(BuildContext context, String message) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.ondemand_video_outlined, size: 58),
          const SizedBox(height: 12),
          Text(message.isEmpty ? '当前线路未提供直链' : message,
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openUpstream,
            icon: const Icon(Icons.open_in_new),
            label: const Text('在播放页打开'),
          ),
        ]),
      );

  Future<void> _startCast() async {
    final url = widget.play.mediaUrl;
    if (url == null) return;
    await _cast.start(mediaUrl: url, title: widget.title);
    if (mounted && _cast.status == CastStatus.unsupported) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_cast.message)));
    }
  }

  void _handleCastState() {
    if (_cast.status == CastStatus.connected &&
        _cast.shouldPauseLocalPlayback &&
        _media.isPlaying) {
      unawaited(_media.pause().then((_) {
        _persistProgress();
        if (mounted) setState(() {});
      }));
    }
  }

  Future<void> _openUpstream() async {
    final url = widget.play.upstreamUrl ?? widget.play.embedUrl;
    if (url == null) return;
    _persistProgress();
    final opened = await _cast.openFallback(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('播放页地址无效')));
    }
  }

  void _persistProgress() {
    final position = _mediaOpened ? _media.position : widget.resumePosition;
    unawaited(_historyService.save(VideoHistoryEntry(
      source: widget.source ?? widget.play.sourceId ?? 'ncat21',
      videoId: widget.play.videoId,
      episodeId: widget.play.episodeId,
      lineId: widget.play.lineId,
      position: position,
    )));
  }
}
