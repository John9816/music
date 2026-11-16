import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/video_api.dart';
import '../../core/models/video.dart';
import '../../core/services/cast_service.dart';
import '../../core/services/video_history_service.dart';
import '../../widgets/glass.dart';
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
    this.lines = const <VideoLine>[],
  });

  final VideoApi api;
  final String title;
  final VideoPlayback play;
  final String? source;
  final Duration resumePosition;
  final VideoHistoryService? historyService;
  final VideoMediaSessionFactory? mediaSessionFactory;

  /// Sibling lines offered when the current one cannot be played in-app.
  final List<VideoLine> lines;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  final CastService _cast = CastService();
  late final VideoHistoryService _historyService;
  late VideoPlayback _play;
  late VideoMediaSession _media;
  Future<void>? _initialize;
  Timer? _historyTimer;
  bool _mediaOpened = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _historyService = widget.historyService ?? VideoHistoryService();
    _play = widget.play;
    _media = _newSession();
    _cast.addListener(_handleCastState);
    _openCurrent();
  }

  void _openCurrent({Duration? resume}) {
    final url = _play.mediaUrl;
    if (!_play.isInlinePlayable || url == null) {
      _initialize = null;
      return;
    }
    _initialize = _media
        .open(
      Uri.parse(url),
      resumePosition: resume ?? widget.resumePosition,
    )
        .then<void>((_) async {
      _mediaOpened = true;
      if (!mounted) return;
      setState(() {});
      _historyTimer?.cancel();
      _historyTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _persistProgress(),
      );
    });
  }

  VideoMediaSession _newSession() =>
      (widget.mediaSessionFactory ?? MediaKitVideoMediaSession.new)();

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
        appBar: GAppBar(
          title: widget.title,
          onBack: () => Navigator.of(context).maybePop(),
          actions: [
            if (_play.isInlinePlayable)
              AnimatedBuilder(
                animation: _cast,
                builder: (_, __) => GToolbarButton(
                  tooltip: '投屏',
                  icon: _cast.status == CastStatus.connected
                      ? Icons.cast_connected
                      : Icons.cast,
                  onTap:
                      _cast.status == CastStatus.connecting ? null : _startCast,
                ),
              ),
            if (_play.isInlinePlayable)
              GToolbarButton(
                key: const ValueKey('vod-fullscreen-button'),
                tooltip: '全屏',
                onTap: _media.toggleFullscreen,
                icon: Icons.fullscreen,
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
            return _fallback(
              context,
              _play.unsupportedReason.isEmpty
                  ? '视频加载失败，可换一条线路重试'
                  : _play.unsupportedReason,
            );
          }
          return AspectRatio(
            aspectRatio: _media.aspectRatio,
            child: _media.buildVideo(),
          );
        },
      );
    }
    return _fallback(context, _play.unsupportedReason);
  }

  Widget _fallback(BuildContext context, String message) {
    final alternatives = widget.lines
        .where((line) => line.id != _play.lineId)
        .toList(growable: false);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.ondemand_video_outlined, size: 58),
        const SizedBox(height: 12),
        Text(message.isEmpty ? '当前线路未提供直链' : message,
            textAlign: TextAlign.center),
        if (alternatives.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '换一条线路',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: alternatives
                .map((line) => ActionChip(
                      key: ValueKey('vod-switch-line-${line.id}'),
                      label: Text(line.name),
                      onPressed: _switching ? null : () => _switchLine(line.id),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        Row(mainAxisSize: MainAxisSize.min, children: [
          FilledButton.icon(
            onPressed: _openUpstream,
            icon: const Icon(Icons.open_in_new),
            label: const Text('在播放页打开'),
          ),
          if (_switching) ...[
            const SizedBox(width: 14),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ]),
      ]),
    );
  }

  Future<void> _switchLine(String lineId) async {
    if (_switching) return;
    setState(() => _switching = true);
    try {
      final next = await widget.api.play(
        _play.videoId,
        source: widget.source,
        episode: _play.episodeId.isEmpty ? null : _play.episodeId,
        line: lineId,
      );
      if (!mounted) return;
      _historyTimer?.cancel();
      await _media.dispose();
      if (!mounted) return;
      _media = _newSession();
      _mediaOpened = false;
      setState(() {
        _play = next;
        _switching = false;
      });
      _openCurrent(resume: Duration.zero);
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _switching = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('切换线路失败：$error')));
    }
  }

  Future<void> _startCast() async {
    final url = _play.mediaUrl;
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
    final url = _play.upstreamUrl ?? _play.embedUrl;
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
      source: widget.source ?? _play.sourceId ?? 'ncat21',
      videoId: _play.videoId,
      episodeId: _play.episodeId,
      lineId: _play.lineId,
      position: position,
    )));
  }
}
