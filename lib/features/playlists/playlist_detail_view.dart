import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/player/player_controller.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/async_cover.dart';
import '../../widgets/glass.dart';
import '../search/artist_names_link.dart';

/// Desktop playlist detail matching the persistent sidebar/player shell.
class PlaylistDetailView extends StatefulWidget {
  const PlaylistDetailView({
    super.key,
    required this.playlist,
    this.loader,
  });

  final Playlist playlist;

  /// Custom loader used by charts; regular playlists use playlist/detail.
  final Future<List<Song>> Function()? loader;

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  final MusicApi _api = MusicApi();
  late Future<List<Song>> _future;
  Future<List<Song>>? _loadingFuture;
  bool _isFavorite = false;
  bool _isAdded = false;

  @override
  void initState() {
    super.initState();
    _future = _startLoad();
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist.id != widget.playlist.id) {
      _isFavorite = false;
      _isAdded = false;
      _loadingFuture = null;
      _reload();
    }
  }

  Future<List<Song>> _load() async {
    if (widget.loader != null) return widget.loader!();
    final source = context.read<SettingsController>().source;
    return _api.getPlaylistDetail(widget.playlist.id, source: source);
  }

  Future<List<Song>> _startLoad() {
    final existing = _loadingFuture;
    if (existing != null) return existing;

    final future = _load();
    _loadingFuture = future;
    future.then<void>(
      (_) {
        if (identical(_loadingFuture, future)) _loadingFuture = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_loadingFuture, future)) _loadingFuture = null;
      },
    );
    return future;
  }

  void _reload() {
    if (!mounted) return;
    final future = _startLoad();
    if (identical(_future, future)) return;
    setState(() => _future = future);
  }

  void _toggleFavorite() {
    setState(() => _isFavorite = !_isFavorite);
    _showMessage(_isFavorite ? '已收藏歌单' : '已取消收藏');
  }

  void _toggleAdded() {
    setState(() => _isAdded = !_isAdded);
    _showMessage(_isAdded ? '已加入我的歌单' : '已从我的歌单移除');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  void _showSongMenu(Song song, List<Song> songs, int index) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: AsyncCover(
                  url: song.album.picUrl,
                  size: 44,
                  radius: 8,
                ),
                title: Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: ArtistNamesLink(
                  artists: song.artists,
                  source: song.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('播放'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.read<PlayerController>().playQueue(
                        songs,
                        index: index,
                      );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _PlaylistTopBar(
        title: widget.playlist.name,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.only(top: 56),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.only(top: 56),
              child: GEmptyState(
                icon: Icons.error_outline_rounded,
                text: '加载失败，请检查网络后重试',
                onRetry: _reload,
              ),
            );
          }

          final songs = snapshot.data ?? const <Song>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 720;
              const horizontal = 20.0;
              return CustomScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      desktop ? 70 : 74,
                      horizontal,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PlaylistHeader(
                        playlist: widget.playlist,
                        songs: songs,
                        desktop: desktop,
                        isFavorite: _isFavorite,
                        isAdded: _isAdded,
                        onFavorite: _toggleFavorite,
                        onAdd: _toggleAdded,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      desktop ? 22 : 28,
                      horizontal,
                      12,
                    ),
                    sliver: const SliverToBoxAdapter(
                      child: Text(
                        '歌曲',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: TypeScale.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                  if (songs.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: GEmptyState(
                        icon: Icons.queue_music_rounded,
                        text: '歌单为空',
                      ),
                    )
                  else
                    SliverPadding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: horizontal),
                      sliver: SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, index) => _PlaylistSongRow(
                          index: index,
                          song: songs[index],
                          onTap: () => context
                              .read<PlayerController>()
                              .playQueue(songs, index: index),
                          onMore: () =>
                              _showSongMenu(songs[index], songs, index),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 30)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlaylistTopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(
                  alpha: dark ? 0.72 : 0.78,
                ),
            border: Border(
              bottom: BorderSide(color: glassHairline(context)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              GIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                tooltip: '返回',
                size: 20,
                padding: 14,
                backgroundColor: Colors.transparent,
                onTap: onBack,
              ),
              const SizedBox(width: 19),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: TypeScale.semibold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.songs,
    required this.desktop,
    required this.isFavorite,
    required this.isAdded,
    required this.onFavorite,
    required this.onAdd,
  });

  final Playlist playlist;
  final List<Song> songs;
  final bool desktop;
  final bool isFavorite;
  final bool isAdded;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cover = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: ShadowToken.cover(context, radius: 24),
      ),
      child: AsyncCover(
        url: playlist.coverUrl,
        size: desktop ? 200 : 144,
        radius: 20,
      ),
    );
    final information = _HeaderInformation(
      playlist: playlist,
      songs: songs,
      compact: !desktop,
      isFavorite: isFavorite,
      isAdded: isAdded,
      onFavorite: onFavorite,
      onAdd: onAdd,
    );

    if (!desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              cover,
              const SizedBox(width: 18),
              Expanded(child: information),
            ],
          ),
        ],
      );
    }

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          cover,
          const SizedBox(width: 23),
          Expanded(child: information),
        ],
      ),
    );
  }
}

class _HeaderInformation extends StatelessWidget {
  const _HeaderInformation({
    required this.playlist,
    required this.songs,
    required this.compact,
    required this.isFavorite,
    required this.isAdded,
    required this.onFavorite,
    required this.onAdd,
  });

  final Playlist playlist;
  final List<Song> songs;
  final bool compact;
  final bool isFavorite;
  final bool isAdded;
  final VoidCallback onFavorite;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final creator = playlist.creatorName?.trim();
    final description = playlist.description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '歌单',
          style: TextStyle(
            color: scheme.primary,
            fontSize: 13,
            fontWeight: TypeScale.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          playlist.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 23,
            fontWeight: TypeScale.heavy,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          creator == null || creator.isEmpty ? '${songs.length} 首歌曲' : creator,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
            ),
          ),
        ],
        SizedBox(height: compact ? 16 : 24),
        Row(
          children: [
            if (compact)
              Expanded(
                child: _PlayAllButton(
                  enabled: songs.isNotEmpty,
                  onTap: () =>
                      context.read<PlayerController>().playQueue(songs),
                ),
              )
            else
              SizedBox(
                width: 314,
                child: _PlayAllButton(
                  enabled: songs.isNotEmpty,
                  onTap: () =>
                      context.read<PlayerController>().playQueue(songs),
                ),
              ),
            const SizedBox(width: 10),
            _CircleAction(
              icon: isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              color: isFavorite ? AppBrand.favoriteRed : null,
              tooltip: isFavorite ? '取消收藏' : '收藏歌单',
              onTap: onFavorite,
            ),
            const SizedBox(width: 8),
            _CircleAction(
              icon: isAdded
                  ? Icons.playlist_add_check_rounded
                  : Icons.playlist_add_rounded,
              color: isAdded ? scheme.primary : null,
              tooltip: isAdded ? '从我的歌单移除' : '加入我的歌单',
              onTap: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayAllButton extends StatelessWidget {
  const _PlayAllButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GPressScale(
      disabled: !enabled,
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: enabled ? 1 : 0.4),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 20, color: Colors.white),
            SizedBox(width: 5),
            Text(
              '全部播放',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: TypeScale.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GPressScale(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glassFill(context, alpha: 0.08),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 25, color: color ?? scheme.onSurface),
        ),
      ),
    );
  }
}

class _PlaylistSongRow extends StatelessWidget {
  const _PlaylistSongRow({
    required this.index,
    required this.song,
    required this.onTap,
    required this.onMore,
  });

  final int index;
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 65,
      child: Stack(
        children: [
          Positioned(
            left: 93,
            right: 0,
            bottom: 0,
            child: Divider(
              height: 1,
              thickness: 1,
              color: glassHairline(context),
            ),
          ),
          Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: TypeScale.medium,
                  ),
                ),
              ),
              Expanded(
                child: GPressScale(
                  onTap: onTap,
                  scale: 0.99,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        AsyncCover(
                          url: song.album.picUrl,
                          size: 46,
                          radius: 10,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: TypeScale.semibold,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ArtistNamesLink(
                                artists: song.artists,
                                source: song.source,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  height: 1.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              GIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: '更多',
                size: 22,
                padding: 12,
                backgroundColor: Colors.transparent,
                onTap: onMore,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }
}
