import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/user_api.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/playlist.dart';
import '../../core/services/user_playlist_library.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../playlists/playlist_import_view.dart';
import '../profile/user_playlists_view.dart';
import 'downloads_view.dart';

/// Desktop library overview matching the compact macOS collection layout.
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
    UserPlaylistLibrary.instance.addListener(_onPlaylistLibraryChanged);
    _userPlaylistsFuture = _loadUserPlaylists();
  }

  @override
  void dispose() {
    UserPlaylistLibrary.instance.removeListener(_onPlaylistLibraryChanged);
    super.dispose();
  }

  void _onPlaylistLibraryChanged() {
    if (!mounted) return;
    setState(() {
      _userPlaylistsFuture = _loadUserPlaylists();
    });
  }

  Future<List<Playlist>> _loadUserPlaylists() async {
    final auth = context.read<AuthController>();
    if (!auth.isLoggedIn || auth.token == null) return const [];
    try {
      final items = await UserApi().getOwnedPlaylists(auth.token!);
      return items
          .map<Playlist>((json) => Playlist(
                id: int.tryParse(json['playlistId']?.toString() ??
                        json['id']?.toString() ??
                        '') ??
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
      _message('请先登录');
      return;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入歌单名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await UserApi().createPlaylist(name, null, auth.token!);
      if (!mounted) return;
      _message('歌单已创建');
    } catch (error) {
      _message('创建失败: $error');
    }
  }

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PlaylistImportView(),
      ),
    );
  }

  void _openUserPlaylists() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UserPlaylistsView()),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 720;
    final current = context.select<PlayerController, Song?>((p) => p.current);

    return Scaffold(
      body: FutureBuilder<List<Playlist>>(
        future: _userPlaylistsFuture,
        builder: (context, snapshot) {
          final playlistCount = snapshot.data?.length ?? 0;
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _LibraryHeader(
                  desktop: desktop,
                  onImport: _openImport,
                  onCreate: _openCreatePlaylist,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: desktop ? 20 : 18),
                sliver: SliverToBoxAdapter(
                  child: _LibraryGrid(
                    desktop: desktop,
                    playlistCount: playlistCount,
                    current: current,
                    onFavorites: widget.onOpenFavorites,
                    onHistory: widget.onOpenHistory,
                    onPlaylists: _openUserPlaylists,
                    onDownloads: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DownloadsView()),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 20 : 18,
                    desktop ? 31 : 25,
                    desktop ? 20 : 18,
                    16,
                  ),
                  child: const Text(
                    '我的歌单',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? 20 : 18,
                    0,
                    desktop ? 20 : 18,
                    28,
                  ),
                  child: _PlaylistCallout(onCreate: _openCreatePlaylist),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.desktop,
    required this.onImport,
    required this.onCreate,
  });

  final bool desktop;
  final VoidCallback onImport;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: desktop ? 77 : 72,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(desktop ? 20 : 18, 0, desktop ? 20 : 18, 0),
        child: Row(
          children: [
            Text(
              '资料库',
              style:
                  pageTitleStyle(context).copyWith(fontSize: desktop ? 28 : 27),
            ),
            const Spacer(),
            _HeaderButton(
              icon: CupertinoIcons.link,
              tooltip: '导入歌单',
              onTap: onImport,
            ),
            const SizedBox(width: 8),
            _HeaderButton(
              icon: CupertinoIcons.add,
              tooltip: '新建歌单',
              emphasized: true,
              onTap: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GPressScale(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: emphasized
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.055),
          ),
          child: Icon(
            icon,
            size: emphasized ? 25 : 19,
            color: emphasized ? Colors.white : scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({
    required this.desktop,
    required this.playlistCount,
    required this.current,
    required this.onFavorites,
    required this.onHistory,
    required this.onPlaylists,
    required this.onDownloads,
  });

  final bool desktop;
  final int playlistCount;
  final Song? current;
  final VoidCallback onFavorites;
  final VoidCallback onHistory;
  final VoidCallback onPlaylists;
  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) {
    final items = [
      _LibraryCard(
        icon: CupertinoIcons.heart_fill,
        title: '喜欢',
        subtitle: '还没有歌曲',
        accent: true,
        onTap: onFavorites,
      ),
      _LibraryCard(
        icon: CupertinoIcons.clock_fill,
        title: '播放历史',
        subtitle: '查看完整记录',
        coverUrl: current?.album.picUrl,
        onTap: onHistory,
      ),
      _LibraryCard(
        icon: CupertinoIcons.bookmark_fill,
        title: '我的歌单',
        subtitle: '$playlistCount 个歌单',
        onTap: onPlaylists,
      ),
      _LibraryCard(
        icon: CupertinoIcons.arrow_down_circle_fill,
        title: '下载',
        subtitle: '暂无下载',
        onTap: onDownloads,
      ),
    ];

    if (!desktop) {
      return Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            SizedBox(height: 92, child: items[index]),
            if (index != items.length - 1) const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 114,
          child: Row(
            children: [
              Expanded(child: items[0]),
              const SizedBox(width: 10),
              Expanded(child: items[1]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 114,
          child: Row(
            children: [
              Expanded(child: items[2]),
              const SizedBox(width: 10),
              Expanded(child: items[3]),
            ],
          ),
        ),
      ],
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
    this.coverUrl,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent
                        ? scheme.primary.withValues(alpha: 0.12)
                        : scheme.onSurface.withValues(alpha: 0.12),
                  ),
                  child: Icon(
                    icon,
                    size: 14,
                    color: accent ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.1,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 1,
              right: 0,
              child: coverUrl == null || coverUrl!.isEmpty
                  ? Icon(
                      CupertinoIcons.chevron_right,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    )
                  : AsyncCover(url: coverUrl, size: 38, radius: 7),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCallout extends StatelessWidget {
  const _PlaylistCallout({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.music_note_2,
            size: 17,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '把喜欢的歌整理成自己的歌单',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onCreate,
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              minimumSize: const Size(44, 40),
            ),
            child: const Text(
              '新建',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
