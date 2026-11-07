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

    final row = GListTile(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      onTap: onTap,
      selected: isPlaying,
      leading: leading ??
          Stack(
            children: [
              AsyncCover(url: song.album.picUrl, size: 48, radius: 8),
              // 正在播放时显示音波图标覆盖
              if (isPlaying)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
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
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: isPlaying ? scheme.primary : null,
        ),
      ),
      subtitle: ArtistNamesLink(
        artists: song.artists,
        source: song.source,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        Padding(
          padding: const EdgeInsets.only(left: 80, right: 20),
          child: Divider(
              height: 0.5, thickness: 0.5, color: glassHairline(context)),
        ),
      ],
    );
  }

  static String _formatDuration(int ms) {
    final total = (ms / 1000).round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
