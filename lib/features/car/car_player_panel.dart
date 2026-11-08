import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/playback_time.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../../widgets/playback_mode_button.dart';

class CarPlayerPanel extends StatelessWidget {
  const CarPlayerPanel({super.key, required this.onFavorite});
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final song = context.select<PlayerController, Song?>((p) => p.current);
    final playing = context.select<PlayerController, bool>((p) => p.playing);
    final liked = context.select<PlayerController, bool>((p) => p.liked);
    final loading = context.select<PlayerController, bool>((p) => p.loading);
    final error = context.select<PlayerController, String?>((p) => p.error);
    final mode =
        context.select<PlayerController, PlaybackMode>((p) => p.playbackMode);
    final player = context.read<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AsyncCover(url: song?.album.picUrl, size: 72, radius: 16),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(song?.name ?? '准备出发',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                      const SizedBox(height: 5),
                      Text(song?.artistNames ?? '选择一首音乐，开始旅途',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15, color: scheme.onSurfaceVariant)),
                    ])),
              ],
            ),
            const SizedBox(height: 12),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error,
                      maxLines: 3,
                      style: TextStyle(color: scheme.error, fontSize: 15))),
            CarProgress(
                key: ValueKey(
                    song == null ? 'empty' : '${song.source}:${song.id}')),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              CarControl(
                  key: const ValueKey('car-previous'),
                  icon: Icons.skip_previous_rounded,
                  label: '上一首',
                  onPressed: song == null ? null : player.previous),
              CarControl(
                  key: const ValueKey('car-play-pause'),
                  icon:
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: loading
                      ? '正在加载，点击可暂停'
                      : playing
                          ? '暂停'
                          : '播放',
                  size: 80,
                  primary: true,
                  onPressed: song == null
                      ? null
                      : loading
                          ? player.pause
                          : player.togglePlay),
              CarControl(
                  key: const ValueKey('car-next'),
                  icon: Icons.skip_next_rounded,
                  label: '下一首',
                  onPressed: song == null ? null : player.next),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Tooltip(
                      message: '播放模式：${mode.label}',
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(64, 64),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            foregroundColor: scheme.onSurfaceVariant),
                        onPressed: player.cyclePlaybackMode,
                        icon: Icon(mode.icon, size: 25),
                        label: Text(mode.label,
                            maxLines: 2, style: const TextStyle(fontSize: 14)),
                      ))),
              CarControl(
                  icon: liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? AppBrand.favoriteRed : scheme.onSurfaceVariant,
                  label: liked ? '取消收藏' : '收藏歌曲',
                  onPressed: song == null ? null : onFavorite),
            ]),
          ],
        ),
      ),
    );
  }
}

class CarControl extends StatelessWidget {
  const CarControl(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.size = 64,
      this.primary = false,
      this.color});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final bool primary;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
        dimension: size,
        child: IconButton(
          tooltip: label,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            minimumSize: Size.square(size),
            padding: EdgeInsets.zero,
            backgroundColor: primary ? scheme.primary : Colors.transparent,
            foregroundColor:
                primary ? scheme.onPrimary : color ?? scheme.onSurface,
            disabledBackgroundColor:
                primary ? scheme.surfaceContainerHighest : Colors.transparent,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(primary ? 28 : 20)),
          ),
          icon: Icon(icon, size: primary ? 42 : 32),
        ));
  }
}

class CarProgress extends StatefulWidget {
  const CarProgress({super.key});
  @override
  State<CarProgress> createState() => _CarProgressState();
}

class _CarProgressState extends State<CarProgress> {
  Duration? _preview;
  @override
  Widget build(BuildContext context) {
    final duration =
        context.select<PlayerController, Duration?>((p) => p.duration);
    final player = context.read<PlayerController>();
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? player.position;
        final time =
            PlaybackTime(position: _preview ?? position, duration: duration);
        return Column(children: [
          GProgressBar(
              position: position,
              duration: duration ?? Duration.zero,
              onSeek: player.seek,
              onPreviewChanged: (value) => setState(() => _preview = value),
              height: 5,
              touchTargetHeight: 64,
              semanticLabel: '车载播放进度'),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(time.elapsed,
                            style: const TextStyle(fontSize: 14, fontFeatures: [
                              FontFeature.tabularFigures()
                            ]))))),
            const SizedBox(width: 12),
            Expanded(
                child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(time.remaining,
                            style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ]))))),
          ]),
        ]);
      },
    );
  }
}
