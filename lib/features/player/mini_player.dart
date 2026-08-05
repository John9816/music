import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../search/artist_names_link.dart';
import 'player_view.dart';
import 'queue_view.dart';

/// 全局播放栏。桌面端横跨侧栏和内容区，窄屏保留紧凑控制。
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key, this.sidebarWidth});

  final double? sidebarWidth;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  void _openPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlayerView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = context.select<PlayerController, Song?>((p) => p.current);
    final desktop =
        MediaQuery.sizeOf(context).width >= 1120 && widget.sidebarWidth != null;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    if (current == null && !desktop) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: desktop ? 80 : (ios ? 60 : 66),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFA2B181E)
            : scheme.surfaceContainer.withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: glassHairline(context))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: desktop
          ? current == null
              ? _emptyDesktopBar(context)
              : _desktopBar(context, current)
          : _compactBar(context, current!),
    );
  }

  Widget _emptyDesktopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.32);
    final trackAreaWidth = (widget.sidebarWidth ?? 280) + 80;
    Widget icon(IconData value, double size) =>
        Icon(value, size: size, color: muted);

    return Row(
      children: [
        SizedBox(
          width: trackAreaWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: icon(CupertinoIcons.music_note_2, 21),
                ),
                const SizedBox(width: 10),
                Text(
                  '暂未播放',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: TypeScale.semibold,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          width: 80,
          child: icon(CupertinoIcons.heart, 21),
        ),
        SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      icon(CupertinoIcons.shuffle, 16),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.backward_end_fill, 22),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.play_fill, 23),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.forward_end_fill, 22),
                      const SizedBox(width: 18),
                      icon(CupertinoIcons.repeat, 16),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text('0:00',
                        style: TextStyle(fontSize: 10.5, color: muted)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: muted.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('-0:00',
                        style: TextStyle(fontSize: 10.5, color: muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                icon(CupertinoIcons.volume_down, 18),
                const SizedBox(width: 9),
                Container(
                  width: 76,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                icon(CupertinoIcons.volume_up, 18),
                const SizedBox(width: 14),
                icon(CupertinoIcons.speaker_2, 19),
                const SizedBox(width: 13),
                icon(CupertinoIcons.text_bubble, 19),
                const SizedBox(width: 13),
                icon(CupertinoIcons.list_bullet, 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopBar(BuildContext context, Song current) {
    final player = context.read<PlayerController>();
    final liked = context.select<PlayerController, bool>((p) => p.liked);
    final trackAreaWidth = (widget.sidebarWidth ?? 280) + 80;
    return Row(
      children: [
        SizedBox(
          width: trackAreaWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: _TrackIdentity(
              song: current,
              coverSize: 56,
              onTap: _openPlayer,
            ),
          ),
        ),
        SizedBox(
          width: 80,
          child: Center(
            child: _PlayerIconButton(
              icon: liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              size: 21,
              padding: 8,
              tint: liked ? AppBrand.favoriteRed : null,
              onTap: player.toggleLike,
            ),
          ),
        ),
        SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _transportControls(context, player),
                const SizedBox(height: 5),
                const _PlaybackTimeline(showTimes: true),
              ],
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 260,
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _rightTools(context, player),
          ),
        ),
      ],
    );
  }

  Widget _compactBar(BuildContext context, Song current) {
    final player = context.read<PlayerController>();
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Column(
      children: [
        const _PlaybackTimeline(showTimes: false),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: _TrackIdentity(
                    song: current,
                    coverSize: ios ? 42 : 46,
                    onTap: _openPlayer,
                  ),
                ),
                if (!ios)
                  GIconButton(
                    icon: CupertinoIcons.backward_end_fill,
                    tooltip: '上一首',
                    size: 22,
                    padding: 7,
                    onTap: player.previous,
                  ),
                _PlayButton(player: player, size: 36),
                if (!ios)
                  GIconButton(
                    icon: CupertinoIcons.forward_end_fill,
                    tooltip: '下一首',
                    size: 22,
                    padding: 7,
                    onTap: player.next,
                  ),
                GIconButton(
                  icon: CupertinoIcons.list_bullet,
                  tooltip: '播放队列',
                  size: 19,
                  padding: 7,
                  onTap: () => showQueueSheet(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _transportControls(
    BuildContext context,
    PlayerController player,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final shuffle = context.select<PlayerController, bool>((p) => p.shuffle);
    final loopMode =
        context.select<PlayerController, String>((p) => p.loopMode.name);
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: _PlayerIconButton(
              icon: CupertinoIcons.shuffle,
              size: 16,
              padding: 8,
              tint: shuffle ? AppBrand.red : scheme.onSurfaceVariant,
              onTap: player.toggleShuffle,
            ),
          ),
          SizedBox(
            width: 32,
            child: _PlayerIconButton(
              icon: CupertinoIcons.backward_end_fill,
              size: 20,
              padding: 6,
              onTap: player.previous,
            ),
          ),
          SizedBox(
            width: 32,
            child: Center(child: _PlayButton(player: player, size: 28)),
          ),
          SizedBox(
            width: 32,
            child: _PlayerIconButton(
              icon: CupertinoIcons.forward_end_fill,
              size: 20,
              padding: 6,
              onTap: player.next,
            ),
          ),
          SizedBox(
            width: 32,
            child: _PlayerIconButton(
              icon: loopMode == 'one'
                  ? CupertinoIcons.repeat_1
                  : CupertinoIcons.repeat,
              size: 16,
              padding: 8,
              tint: loopMode != 'off' ? AppBrand.red : scheme.onSurfaceVariant,
              onTap: player.cycleLoopMode,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rightTools(BuildContext context, PlayerController player) {
    final volume = context.select<PlayerController, double>((p) => p.volume);
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _PlayerIconButton(
          icon: volume <= 0
              ? CupertinoIcons.volume_off
              : CupertinoIcons.volume_down,
          size: 18,
          padding: 6,
          onTap: () => player.setVolume(volume <= 0 ? 0.7 : 0),
        ),
        const SizedBox(width: 3),
        _VolumeBar(value: volume, onChanged: player.setVolume),
        const SizedBox(width: 5),
        Icon(
          CupertinoIcons.volume_up,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        _PlayerIconButton(
          icon: CupertinoIcons.speaker_2,
          size: 19,
          padding: 6,
          onTap: _openPlayer,
        ),
        _PlayerIconButton(
          icon: CupertinoIcons.text_bubble,
          size: 19,
          padding: 6,
          onTap: _openPlayer,
        ),
        _PlayerIconButton(
          icon: CupertinoIcons.list_bullet,
          size: 20,
          padding: 6,
          onTap: () => showQueueSheet(context),
        ),
      ],
    );
  }
}

class _PlayerIconButton extends StatelessWidget {
  const _PlayerIconButton({
    required this.icon,
    required this.onTap,
    required this.size,
    required this.padding,
    this.tint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: SizedBox.square(
        dimension: size + padding * 2,
        child: Icon(
          icon,
          size: size,
          color: tint ?? scheme.onSurface.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({
    required this.song,
    required this.coverSize,
    required this.onTap,
  });

  final Song song;
  final double coverSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final loading = context.select<PlayerController, bool>((p) => p.loading);
    final error = context.select<PlayerController, String?>((p) => p.error);
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: coverSize,
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: ShadowToken.card(context, radius: 10),
            ),
            child: AsyncCover(
              url: song.album.picUrl,
              size: coverSize,
              radius: 8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        song.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: TypeScale.semibold,
                        ),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 7),
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (error == null)
                  ArtistNamesLink(
                    artists: song.artists,
                    source: song.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player, required this.size});

  final PlayerController player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final loading = context.select<PlayerController, bool>((p) => p.loading);
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: loading ? null : player.togglePlay,
      child: SizedBox(
        width: size,
        height: size,
        child: loading
            ? Padding(
                padding: EdgeInsets.all(size * 0.28),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurface,
                ),
              )
            : Icon(
                playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                size: size * 0.82,
                color: scheme.onSurface,
              ),
      ),
    );
  }
}

class _PlaybackTimeline extends StatefulWidget {
  const _PlaybackTimeline({required this.showTimes});

  final bool showTimes;

  @override
  State<_PlaybackTimeline> createState() => _PlaybackTimelineState();
}

class _PlaybackTimelineState extends State<_PlaybackTimeline> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration) ??
            Duration.zero;
    final scheme = Theme.of(context).colorScheme;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.position;
        final totalMs = duration.inMilliseconds.toDouble();
        final fraction = totalMs <= 0
            ? 0.0
            : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);
        final remaining =
            duration > position ? duration - position : Duration.zero;
        final displayedFraction = _dragFraction ?? fraction;
        final bar = LayoutBuilder(
          builder: (context, constraints) {
            void seek(double dx, {bool preview = false}) {
              if (totalMs <= 0 || constraints.maxWidth <= 0) return;
              final value =
                  (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
              if (preview) setState(() => _dragFraction = value);
              player.seek(Duration(milliseconds: (totalMs * value).round()));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => seek(details.localPosition.dx),
              onHorizontalDragStart: (_) =>
                  setState(() => _dragFraction = fraction),
              onHorizontalDragUpdate: (details) =>
                  seek(details.localPosition.dx, preview: true),
              onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
              onHorizontalDragCancel: () =>
                  setState(() => _dragFraction = null),
              child: SizedBox(
                height: widget.showTimes ? 14 : 3,
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(
                          height: widget.showTimes ? 4 : 3,
                          color: scheme.onSurface.withValues(alpha: 0.18),
                        ),
                        FractionallySizedBox(
                          widthFactor: displayedFraction,
                          child: Container(
                            height: widget.showTimes ? 4 : 3,
                            color: scheme.onSurface.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );

        if (!widget.showTimes) return bar;
        final timeStyle = TextStyle(
          fontSize: 10.5,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: scheme.onSurfaceVariant,
        );
        return Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(_formatDuration(position), style: timeStyle),
            ),
            Expanded(child: bar),
            SizedBox(
              width: 43,
              child: Text(
                '-${_formatDuration(remaining)}',
                textAlign: TextAlign.end,
                style: timeStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VolumeBar extends StatefulWidget {
  const _VolumeBar({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeBar> createState() => _VolumeBarState();
}

class _VolumeBarState extends State<_VolumeBar> {
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayedValue = _dragFraction ?? widget.value;
    return SizedBox(
      width: 76,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void update(double dx, {bool preview = false}) {
            final value =
                (dx / constraints.maxWidth).clamp(0.0, 1.0).toDouble();
            if (preview) setState(() => _dragFraction = value);
            widget.onChanged(value);
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition.dx),
            onHorizontalDragStart: (_) =>
                setState(() => _dragFraction = widget.value),
            onHorizontalDragUpdate: (details) =>
                update(details.localPosition.dx, preview: true),
            onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
            onHorizontalDragCancel: () => setState(() => _dragFraction = null),
            child: SizedBox(
              height: 18,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(
                        height: 4,
                        color: scheme.onSurface.withValues(alpha: 0.18),
                      ),
                      FractionallySizedBox(
                        widthFactor: displayedValue.clamp(0.0, 1.0),
                        child: Container(
                          height: 4,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
