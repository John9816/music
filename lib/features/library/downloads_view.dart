import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_controller.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/song_download_service.dart';
import '../../widgets/glass.dart';
import '../../widgets/song_row.dart';

class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<SongDownloadService>();
    final downloads = service.downloads;
    final taskCount = service.progress.length;
    final totalBytes = downloads.fold<int>(
      0,
      (total, entry) => total + entry.sizeBytes,
    );
    return Scaffold(
      appBar: GAppBar(
        title: '下载管理',
        onBack: () => Navigator.of(context).maybePop(),
        actions: [
          if (downloads.isNotEmpty)
            GIconButton(
              icon: Icons.delete_sweep_outlined,
              tooltip: '清空下载',
              size: 20,
              padding: 10,
              onTap: () => _clearAll(context, service),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Text(
              taskCount > 0
                  ? '$taskCount 个任务下载中 · 已下载 ${downloads.length} 首'
                  : '已下载 ${downloads.length} 首 · ${CacheService.formatBytes(totalBytes)}',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          if (taskCount > 0) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: downloads.isEmpty
                ? const GEmptyState(
                    icon: Icons.download_for_offline_outlined,
                    text: '还没有下载的歌曲',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                    itemCount: downloads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final entry = downloads[index];
                      return SongRow(
                        song: entry.song,
                        onTap: () => context.read<PlayerController>().playQueue(
                            downloads.map((item) => item.song).toList(),
                            index: index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              CacheService.formatBytes(entry.sizeBytes),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                            GIconButton(
                              icon: Icons.delete_outline_rounded,
                              tooltip: '删除 ${entry.song.name}',
                              size: 19,
                              padding: 9,
                              onTap: () => service.delete(entry),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll(
    BuildContext context,
    SongDownloadService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部下载？'),
        content: const Text('已下载的音乐文件会被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await service.clear();
  }
}
