import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/playlist.dart';
import '../../widgets/glass.dart';
import '../playlists/playlist_import_view.dart';
import '../profile/user_library_view.dart';

/// 资料库总览页:喜欢的音乐、播放历史、下载管理 + 我的歌单列表。
class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.onOpenFavorites,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenHistory;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  Future<List<Playlist>>? _userPlaylistsFuture;

  @override
  void initState() {
    super.initState();
    _userPlaylistsFuture = _loadUserPlaylists();
  }

  Future<List<Playlist>> _loadUserPlaylists() async {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn || auth.token == null) return const [];
    try {
      final items = await UserApi().getUserPlaylists(auth.token!);
      return items
          .map<Playlist>((json) => Playlist(
                id: int.tryParse(json['playlistId']?.toString() ??
                        json['id']?.toString() ??
                        "") ??
                    0,
                name: json['name']?.toString() ??
                    json['playlistName']?.toString() ??
                    '未命名歌单',
                coverUrl: json['coverImgUrl']?.toString(),
                creatorName: json['creatorName']?.toString(),
                playCount: (json['playCount'] as num?)?.toInt(),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _openCreatePlaylist() async {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn || auth.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入歌单名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await UserApi().createPlaylist(name, null, auth.token!);
      setState(() {
        _userPlaylistsFuture = _loadUserPlaylists();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('歌单已创建')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    }
  }

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistImportView(
          onImported: () {
            setState(() {
              _userPlaylistsFuture = _loadUserPlaylists();
            });
          },
        ),
      ),
    );
  }

  void _openPlaylist(Playlist playlist) {
    final auth = context.read<AuthController>();
    if (auth.token == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserLibraryView(
          title: playlist.name,
          loader: () async {
            final items = await UserApi()
                .getUserPlaylistSongs(playlist.id.toString(), auth.token!);
            return items.map(itemToSong).toList();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: GPageHeader(
              title: '资料库',
              subtitle: '管理你的音乐收藏和歌单',
            ),
          ),
          // 搜索条
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 24,
                0,
                compact ? 18 : 24,
                16,
              ),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF2C2C2E)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: dark
                        ? const Color(0x33FFFFFF)
                        : const Color(0x263C3C43),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 17,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '在你的资料库中搜索',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 快速入口卡片
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 24,
                0,
                compact ? 18 : 24,
                8,
              ),
              child: Column(
                children: [
                  _LibraryEntryTile(
                    icon: Icons.favorite_rounded,
                    label: '喜欢的音乐',
                    color: AppBrand.red,
                    onTap: widget.onOpenFavorites,
                  ),
                  const SizedBox(height: 2),
                  _LibraryEntryTile(
                    icon: Icons.history_rounded,
                    label: '播放历史',
                    color: const Color(0xFFFF9500),
                    onTap: widget.onOpenHistory,
                  ),
                  const SizedBox(height: 2),
                  _LibraryEntryTile(
                    icon: Icons.download_rounded,
                    label: '下载管理',
                    color: const Color(0xFF007AFF),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('下载管理功能开发中')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 我的歌单
          SliverToBoxAdapter(
            child: SectionHeader(
              '我的歌单',
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GPressScale(
                    onTap: _openCreatePlaylist,
                    child: const Icon(
                      Icons.add_rounded,
                      size: 22,
                      color: AppBrand.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  GPressScale(
                    onTap: _openImport,
                    child: Icon(
                      Icons.file_download_outlined,
                      size: 20,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 歌单列表
          SliverToBoxAdapter(
            child: FutureBuilder<List<Playlist>>(
              future: _userPlaylistsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final playlists = snapshot.data ?? const [];
                if (playlists.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 18 : 24,
                      8,
                      compact ? 18 : 24,
                      24,
                    ),
                    child: GSurface(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.queue_music_outlined,
                            size: 36,
                            color: scheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '还没有歌单',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '点击 + 创建或导入歌单',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 20,
                    0,
                    compact ? 14 : 20,
                    24,
                  ),
                  child: Column(
                    children: [
                      for (final playlist in playlists)
                        _PlaylistRowTile(
                          playlist: playlist,
                          onTap: () => _openPlaylist(playlist),
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
}

/// 资料库快捷入口卡片(喜欢的音乐 / 播放历史 / 下载管理)
class _LibraryEntryTile extends StatelessWidget {
  const _LibraryEntryTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GPressScale(
      onTap: onTap,
      child: GSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        radius: 14,
        alpha: 0.04,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 13),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: TypeScale.semibold,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌单行卡片
class _PlaylistRowTile extends StatelessWidget {
  const _PlaylistRowTile({
    required this.playlist,
    required this.onTap,
  });

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: GSurface(
          radius: 12,
          alpha: 0.03,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 44,
                  height: 44,
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: Icon(
                    Icons.music_note_rounded,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: TypeScale.semibold,
                      ),
                    ),
                    if (playlist.playCount != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        '${_formatCount(playlist.playCount!)} 首',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.more_horiz_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    }
    return '$count';
  }
}
