import 'package:flutter/material.dart';

import '../core/models/playlist.dart';
import 'async_cover.dart';
import 'glass.dart';

/// 歌单卡片：封面 + 播放量角标 + 名称（大厂风格）
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({super.key, required this.playlist, this.onTap});

  final Playlist playlist;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(RadiusToken.lg),
                    boxShadow: ShadowToken.card(context, radius: 14),
                  ),
                  child: AsyncCover(
                    url: playlist.coverUrl,
                    size: double.infinity,
                    radius: RadiusToken.lg,
                  ),
                ),
                // 播放量角标（右下）
                if (playlist.playCount != null && playlist.playCount! > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.52),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatPlayCount(playlist.playCount!),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: TypeScale.semibold,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: TypeScale.semibold,
              color: scheme.onSurface,
              height: 1.25,
            ),
          ),
          if (playlist.creatorName != null) ...[
            const SizedBox(height: 2),
            Text(
              playlist.creatorName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatPlayCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}亿';
    }
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }
}
