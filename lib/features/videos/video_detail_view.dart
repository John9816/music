import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/video_api.dart';
import '../../core/models/video.dart';
import '../../core/services/video_history_service.dart';
import '../../widgets/glass.dart';
import 'video_player_view.dart';

class VideoDetailView extends StatefulWidget {
  const VideoDetailView({
    super.key,
    required this.api,
    required this.videoId,
    this.source,
    this.historyService,
  });

  final VideoApi api;
  final String videoId;
  final String? source;
  final VideoHistoryService? historyService;

  @override
  State<VideoDetailView> createState() => _VideoDetailViewState();
}

class _VideoDetailViewState extends State<VideoDetailView> {
  late Future<VideoDetail> _future;
  late final VideoHistoryService _historyService;
  VideoHistoryEntry? _lastWatched;
  String? _line;
  bool _historyLoaded = false;
  bool _historyApplied = false;

  @override
  void initState() {
    super.initState();
    _historyService = widget.historyService ?? VideoHistoryService();
    _future = widget.api.detail(widget.videoId, source: widget.source);
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final entry = await _historyService.load(_sourceId, widget.videoId);
    if (!mounted) return;
    setState(() {
      _lastWatched = entry;
      _historyLoaded = true;
      _historyApplied = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GAppBar(
          title: '影视详情',
          onBack: () => Navigator.of(context).maybePop(),
        ),
        body: FutureBuilder<VideoDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () => setState(() => _future = widget.api.detail(
                        widget.videoId,
                        source: widget.source,
                      )),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新加载'),
                ),
              );
            }

            final detail = snapshot.data!;
            _applyHistorySelection(detail);
            final continueEpisode = _continueEpisode(detail);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (detail.posterUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        detail.posterUrl!,
                        width: 120,
                        height: 170,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 120,
                          height: 170,
                          child: Icon(Icons.movie),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      width: 120,
                      height: 170,
                      child: Icon(Icons.movie_outlined, size: 48),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(detail.description.isEmpty
                            ? '暂无简介'
                            : detail.description),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          children: detail.tags
                              .map((tag) => Chip(label: Text(tag.name)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                if (continueEpisode != null && _lastWatched != null) ...[
                  FilledButton.icon(
                    onPressed: () => _openEpisode(
                      detail,
                      continueEpisode,
                      lineOverride: _lastWatched!.lineId,
                      resumePosition: _lastWatched!.position,
                    ),
                    icon: const Icon(Icons.play_circle_outline),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('继续播放 ${continueEpisode.name}'),
                        const SizedBox(width: 10),
                        Text(_formatPosition(_lastWatched!.position)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (detail.lines.isNotEmpty) ...[
                  const Text(
                    '播放线路',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: detail.lines
                        .map(
                          (line) => ChoiceChip(
                            label: Text(line.name),
                            selected: _line == line.id,
                            onSelected: (_) => setState(() {
                              _line = line.id;
                              _historyApplied = true;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],
                const Text(
                  '选集播放',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (detail.episodes.isEmpty)
                  const Text('暂无可用选集')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: detail.episodes
                        .map(
                          (episode) => OutlinedButton(
                            onPressed: () => _openEpisode(detail, episode),
                            child: Text(episode.name),
                          ),
                        )
                        .toList(),
                  ),
              ],
            );
          },
        ),
      );

  void _applyHistorySelection(VideoDetail detail) {
    if (_historyLoaded && !_historyApplied) {
      final savedLine = _lastWatched?.lineId;
      if (savedLine != null &&
          detail.lines.any((line) => line.id == savedLine)) {
        _line = savedLine;
      }
      _historyApplied = true;
    }
    _line ??= detail.lines.firstOrNull?.id;
  }

  VideoEpisode? _continueEpisode(VideoDetail detail) {
    final episodeId = _lastWatched?.episodeId;
    if (episodeId == null) return null;
    for (final episode in detail.episodes) {
      if (episode.id == episodeId) return episode;
    }
    return null;
  }

  Future<void> _openEpisode(
    VideoDetail detail,
    VideoEpisode episode, {
    String? lineOverride,
    Duration resumePosition = Duration.zero,
  }) async {
    try {
      final play = await widget.api.play(
        detail.id,
        source: widget.source,
        episode: episode.id,
        line: lineOverride ?? _line ?? '1',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerView(
            api: widget.api,
            title: detail.title,
            play: play,
            source: widget.source ?? detail.sourceId ?? _sourceId,
            resumePosition: resumePosition,
            historyService: _historyService,
          ),
        ),
      );
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  String get _sourceId => widget.source ?? 'ncat21';
}

String _formatPosition(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

extension on List<VideoLine> {
  VideoLine? get firstOrNull => isEmpty ? null : first;
}
