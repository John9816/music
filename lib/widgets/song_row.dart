import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/song.dart';
import '../core/player/player_controller.dart';
import '../features/search/artist_names_link.dart';
import 'async_cover.dart';
import 'glass.dart';
import 'song_action_menu.dart';

/// 歌曲行（纯 GestureDetector，无 MouseRegion）
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.leading,
  });

  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 检查是否是当前播放的歌曲
    final isPlaying = context.select<PlayerController, bool>(
      (p) => p.current?.id == song.id && p.current?.source == song.source,
    );

    return GListTile(
      onTap: onTap,
      selected: isPlaying,
      leading: leading ??
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: AsyncCover(url: song.album.picUrl, size: 48, radius: 10),
              ),
              // 正在播放时显示音波图标覆盖
              if (isPlaying)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: scheme.primary,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: TypeScale.bodyLarge,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
          color: isPlaying ? scheme.primary : null,
        ),
      ),
      subtitle: ArtistNamesLink(
        artists: song.artists,
        source: song.source,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: TypeScale.small),
      ),
      trailing: trailing ??
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (song.durationMs > 0 &&
                  MediaQuery.sizeOf(context).width >= GBreakpoints.compact)
                Text(
                  _formatDuration(song.durationMs),
                  style: TextStyle(
                    fontSize: TypeScale.caption,
                    color: scheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              SongActionButton(song: song, onPlay: onTap),
            ],
          ),
    );
  }

  static String _formatDuration(int ms) {
    final total = (ms / 1000).round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
