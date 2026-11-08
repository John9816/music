import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/song.dart';
import '../core/player/player_controller.dart';
import '../features/search/artist_names_link.dart';
import 'async_cover.dart';
import 'glass.dart';
import 'song_action_menu.dart';
import 'song_favorite_button.dart';

/// Shared artwork / title / artist row with direct favorite and overflow actions.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    this.onTap,
    this.trailing,
    this.leading,
    this.index,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  });

  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;
  final int? index;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPlaying = context.select<PlayerController, bool>(
      (p) => p.current?.id == song.id && p.current?.source == song.source,
    );
    final cover = Stack(children: [
      AsyncCover(url: song.album.picUrl, size: 52, radius: 10),
      if (isPlaying)
        Positioned.fill(
            child: DecoratedBox(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.black.withValues(alpha: .45)),
          child: const Icon(Icons.graphic_eq_rounded,
              color: Colors.white, size: 22),
        )),
    ]);
    return GListTile(
      margin: EdgeInsets.zero,
      padding: padding,
      onTap: onTap,
      selected: isPlaying,
      leading: leading ??
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (index != null && MediaQuery.sizeOf(context).width >= 360) ...[
              SizedBox(
                  width: 22,
                  child: Text('$index',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant))),
              const SizedBox(width: 8),
            ],
            cover,
          ]),
      title: Text(song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: isPlaying ? scheme.primary : scheme.onSurface)),
      subtitle: ArtistNamesLink(
          artists: song.artists,
          source: song.source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 13.5, height: 1.3, color: scheme.onSurfaceVariant)),
      trailing: trailing ??
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (song.durationMs > 0 &&
                MediaQuery.sizeOf(context).width >= GBreakpoints.compact)
              Text(_formatDuration(song.durationMs),
                  style: TextStyle(
                      fontSize: TypeScale.caption,
                      color: scheme.outline,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            SongFavoriteButton(song: song),
            SongActionButton(song: song, onPlay: onTap),
          ]),
    );
  }

  static String _formatDuration(int ms) {
    final total = (ms / 1000).round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }
}
