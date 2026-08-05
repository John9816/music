import 'package:flutter/material.dart';

import '../core/models/song.dart';
import '../features/search/artist_names_link.dart';
import 'async_cover.dart';
import 'glass.dart';

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
    return GListTile(
      onTap: onTap,
      leading: leading ??
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
      title: Text(
        song.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      subtitle: ArtistNamesLink(
        artists: song.artists,
        source: song.source,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: trailing ??
          (song.durationMs > 0
              ? Text(
                  _formatDuration(song.durationMs),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.outline,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              : null),
    );
  }

  static String _formatDuration(int ms) {
    final total = (ms / 1000).round();
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
